"""Validate the sealed Linux bundle without loading its image or executing its code."""

import hashlib
import json
from pathlib import Path
import re
import sys
import tarfile

BINARIES = ("layerfs", "layerfs-daemon", "layerfs-sandbox-helper")
ARCHIVE = "sandbox-image.tar"
LOADER = "lib/ld-linux-x86-64.so.2"
STATIC = ("bash-static", "busybox-static")
# Diff ID from the pinned amd64 Noble config, not the registry's gzip layer digest.
BASE_DIFF_ID = "sha256:21210938f5a37a9887b2d0a20428917b923a636ca6efe038c3c7d9cd9f1f9b61"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_json(path):
    return json.loads(path.read_bytes())


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def aggregate(files):
    # Same canonicalization as the upstream linux_bundle.py bundle_hash().
    return hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()


def check_archive(path, image):
    require(re.fullmatch(r"sha256:[0-9a-f]{64}", image), "invalid Sandbox config digest")
    config_name = image.removeprefix("sha256:") + ".json"
    with tarfile.open(path, "r:") as archive:
        members = archive.getmembers()
        require(all(member.isfile() for member in members), "non-file Sandbox archive member")
        listing = json.load(archive.extractfile("manifest.json"))
        require(listing == [{"Config": config_name, "RepoTags": None, "Layers": ["0/layer.tar"]}],
                "expected the official docker-archive shape with one untagged Noble layer")
        require(sorted(member.name for member in members) == ["0/layer.tar", config_name, "manifest.json"],
                "unexpected Sandbox archive members")
        config_bytes = archive.extractfile(config_name).read()
        require("sha256:" + hashlib.sha256(config_bytes).hexdigest() == image, "Sandbox config hash mismatch")
        config = json.loads(config_bytes)
        require((config["os"], config["architecture"]) == ("linux", "amd64"), "wrong Sandbox platform")
        require(config["config"]["Labels"]["org.shadow.layerfs.fixture"] == "shell-only-test"
                and config["config"]["Cmd"] == ["/bin/bash"], "wrong Sandbox fixture configuration")
        require(config["rootfs"]["diff_ids"] == [BASE_DIFF_ID], "unexpected Sandbox root filesystem")
        with archive.extractfile("0/layer.tar") as layer:
            require("sha256:" + hashlib.file_digest(layer, "sha256").hexdigest() == BASE_DIFF_ID,
                    "Sandbox layer does not match the pinned uncompressed layer")


def check_bundle(root, source, sandbox_id):
    require(not root.is_symlink() and (root / "bundle.json").is_file(), "bundle manifest is missing")
    paths = list(root.rglob("*"))
    require(all(not p.is_symlink() and (p.is_dir() or p.is_file()) for p in paths),
            "bundle contains a link or a special file")
    manifest = read_json(root / "bundle.json")
    for key, expected in {
        "version": "2.0.0", "platform": "linux-x86_64", "profile": "release",
        "protocol": 3, "toolchain": "1.85.1", "source": source, "saved_from": sandbox_id,
    }.items():
        require(manifest[key] == expected, f"unexpected manifest {key}")
    files = manifest["files"]
    actual = {p.relative_to(root).as_posix() for p in paths if p.is_file()} - {"bundle.json"}
    require(set(files) == actual, "bundle file set differs from manifest")
    runtime = {name: h for name, h in files.items() if name.startswith("runtime/")}
    licenses = {name for name in files if name.startswith("licenses/")}
    require(actual == {*BINARIES, ARCHIVE, *runtime, *licenses}, "unexpected bundle payload")
    for name in sorted(actual):
        require(digest(root / name) == files[name], f"bundle file hash mismatch: {name}")
    require(aggregate(files) == manifest["hash"], "aggregate bundle hash mismatch")
    require(aggregate({name: files[name] for name in BINARIES}) == manifest["runtime"], "binary hash mismatch")
    sandbox_runtime = manifest["sandbox_runtime"]
    require(aggregate(runtime) == sandbox_runtime["hash"] and sandbox_runtime["loader"] == LOADER,
            "runtime-layer hash or loader mismatch")
    require(set(STATIC) <= sandbox_runtime["packages"].keys() and sandbox_runtime["sources"],
            "runtime source provenance missing")
    required_notices = ["SOURCES", *(package + ".copyright" for package in STATIC)]
    require(all("licenses/" + name in licenses and (root / "licenses" / name).stat().st_size
                for name in required_notices), "missing license notices or source offer")
    for name in (*BINARIES, "runtime/" + LOADER, "runtime/bin/bash", "runtime/bin/busybox", "runtime/bin/getent"):
        path = root / name
        with path.open("rb") as stream:
            header = stream.read(20)
        require(header[:6] == b"\x7fELF\x02\x01" and header[18:20] == b"\x3e\x00"
                and path.stat().st_mode & 0o111, f"not an executable x86-64 ELF: {name}")
    check_archive(root / ARCHIVE, manifest["image"])
    return manifest


def main(root, registration, commit, tree, lock, builder, base):
    record = read_json(registration)
    checkout = Path(record["worktree"])
    # Import the official input digest algorithm only from the verified checkout.
    sys.path.insert(0, str(checkout / "tools"))
    from worktree_resources import inputs

    source = inputs(record)
    require(source["head"] == commit and not source["dirty"], "wrong or dirty build source")
    require(digest(checkout / "Cargo.lock") == lock, "Cargo.lock digest changed")
    source = {key: source[key] for key in ("head", "dirty", "sha256")}
    manifest = check_bundle(root, source, record["images"]["sandbox"])
    fetched = read_json(Path(record["state"]) / "linux-bundle/runtime/runtime.json")
    require(fetched["image"] == record["images"]["build"], "runtime packages came from a different builder")
    require({pkg: meta["version"] for pkg, meta in fetched["packages"].items()}
            == manifest["sandbox_runtime"]["packages"], "runtime package provenance mismatch")
    for name in ("bash", "busybox"):
        require(fetched["files"][name] == manifest["files"]["runtime/bin/" + name], "runtime binary provenance mismatch")
    print(json.dumps({
        "test_only": True,
        "upstream": {**source, "tree": tree, "cargo_lock_sha256": lock},
        "builder": builder,
        "sandbox_base": base,
        "installed_image_ids": record["images"],
        "sandbox_config_digest": manifest["image"],
        "bundle_sha256": manifest["hash"],
        "runtime_static_packages": fetched["packages"],
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    bundle, resources, *pins = sys.argv[1:]
    main(Path(bundle), Path(resources), *pins)
