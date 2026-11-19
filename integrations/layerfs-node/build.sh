#!/usr/bin/env bash
set -euo pipefail

repo=https://github.com/Ephemeral-AI-Lab/layerfs.git
commit=ff114a5265e2b504db437e7514e4ac09c8a6ca70
tree=6aba9fc617137bea646119938e18b0b1dda558a3
lock=3e92435847d41da4323a206842fd94e1cbe0cc685ac079906268aebce9926bf6
node_tar=node-v22.22.0-linux-x64.tar.xz
node_sha=9aa8e9d2298ab68c600bd6fb86a6c13bce11a4eca1ba9b39d79fa021755d7c37
target=x86_64-unknown-linux-gnu
prefix=layerfs-node-2.0.0-rc.1
asset=$prefix-linux-x64-glibc.tgz
export PATH=/opt/node/bin:$PATH
# Portable baseline, no caller-specific flags or build target.
unset RUSTFLAGS CARGO_ENCODED_RUSTFLAGS CARGO_BUILD_TARGET CARGO_TARGET_DIR LAYERFS_NATIVE_OUTPUT
export CARGO_BUILD_JOBS=4

case "$1" in
  fetch)
    test "$(uname -m)" = x86_64
    test "$(getconf GNU_LIBC_VERSION)" = 'glibc 2.36'
    rustc +1.85.1 -Vv
    mkdir /opt/node /src /corresponding
    curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 180 \
      "https://nodejs.org/dist/v22.22.0/$node_tar" -o "/tmp/$node_tar"
    printf '%s  %s\n' "$node_sha" "/tmp/$node_tar" | sha256sum -c -
    tar -xJf "/tmp/$node_tar" --strip-components=1 -C /opt/node
    rm "/tmp/$node_tar"
    cd /src
    git init -q
    git fetch --no-tags --depth=1 "$repo" "$commit"
    git checkout -q --detach FETCH_HEAD
    test "$(git rev-parse HEAD)" = "$commit"
    test "$(git rev-parse 'HEAD^{tree}')" = "$tree"
    printf '%s  Cargo.lock\n' "$lock" | sha256sum -c -
    cargo +1.85.1 fetch --locked --target "$target"
    ;;
  build)
    cd /src
    test "$(node --version)" = v22.22.0
    test "$(npm --version)" = 10.9.4
    cmp LICENSE api/node/LICENSE
    npm --prefix api run build:native
    mkdir /out
    (cd api/node && npm pack --offline --pack-destination /out)
    mv "/out/$prefix.tgz" "/out/$asset"
    for member in package/LICENSE package/layerfs.node package/package.json package/src/index.d.ts; do
      tar -tf "/out/$asset" "$member" >/dev/null
    done
    tar -xOf "/out/$asset" package/LICENSE | cmp LICENSE -
    addon=api/node/layerfs.node
    LC_ALL=C readelf -h "$addon" | grep -E 'Class: +ELF64$'
    LC_ALL=C readelf -h "$addon" | grep -E 'Machine: +Advanced Micro Devices X86-64$'
    LC_ALL=C readelf -d "$addon" > /corresponding/elf-dynamic.txt
    # No RPATH pointing into the builder and no missing shared libraries.
    if grep -E 'RPATH|RUNPATH' /corresponding/elf-dynamic.txt; then exit 1; fi
    grep -F '[libssl.so.3]' /corresponding/elf-dynamic.txt
    grep -F '[libcrypto.so.3]' /corresponding/elf-dynamic.txt
    ldd "$addon" | tee /tmp/loader.txt
    if grep -F 'not found' /tmp/loader.txt; then exit 1; fi
    LC_ALL=C readelf --version-info "$addon" > /tmp/elf-versions.txt
    grep -oE 'GLIBC_[0-9.]+' /tmp/elf-versions.txt | sort -Vu > /corresponding/elf-glibc-symbols.txt
    highest_glibc=$(tail -1 /corresponding/elf-glibc-symbols.txt | cut -d_ -f2)
    dpkg --compare-versions "$highest_glibc" le 2.36
    cargo +1.85.1 tree --locked --offline --target "$target" -p layerfs-node \
      -e normal,build --format '{p} [{l}]' > /corresponding/cargo-build-tree.txt
    git diff --exit-code -- Cargo.lock
    git archive --format=tar --prefix=layerfs/ "$commit" | gzip -n > /corresponding/upstream.tar.gz
    cp LICENSE Cargo.lock /corresponding/
    mkdir /corresponding/system-notices
    for pkg in libssl3 libc6 libgcc-s1; do
      cp -L "/usr/share/doc/$pkg/copyright" "/corresponding/system-notices/$pkg.txt"
    done
    dpkg-query -W -f='${Package} ${Version}\n' libc6 libssl3 libssl-dev gcc binutils libgcc-s1 \
      > /corresponding/builder-packages.txt
    addon_sha=$(sha256sum "$addon" | cut -d' ' -f1)
    asset_sha=$(sha256sum "/out/$asset" | cut -d' ' -f1)
    highest_glibc=$(tail -1 /corresponding/elf-glibc-symbols.txt | cut -d_ -f2)
    python3 - "$repo" "$commit" "$tree" "$lock" "$node_sha" "$target" "$asset" "$asset_sha" "$addon_sha" "$highest_glibc" <<'PY' > /out/provenance.json
import json, sys
repo, commit, tree, lock, node_sha, target, asset, asset_sha, addon_sha, glibc = sys.argv[1:]
print(json.dumps({
    'recipe': 'layerfs-node-2.0.0-rc.1-shadow.1',
    'upstream': {'repository': repo, 'commit': commit, 'tree': tree, 'cargoLockSha256': lock},
    'build': {'target': target, 'rust': '1.85.1', 'node': '22.22.0', 'npm': '10.9.4',
              'nodeArchiveSha256': node_sha, 'os': 'Debian 12', 'glibc': '2.36',
              'command': 'npm --prefix api run build:native',
              'pack': '(cd api/node && npm pack --offline)'},
    'artifact': {'name': asset, 'sha256': asset_sha, 'addonSha256': addon_sha,
                 'package': '@layerfs/node', 'version': '2.0.0-rc.1', 'license': 'MIT',
                 'highestGlibcSymbol': glibc},
}, indent=2))
PY
    ;;
  bundle)
    cd /corresponding
    # Separate from the binary build: preserve whole locked sources and their
    # shipped licenses, including git dependencies, without changing resolution.
    (cd /src && cargo +1.85.1 vendor --locked --versioned-dirs /corresponding/vendor) > cargo-vendor-config.toml
    sed -i 's|^directory = "/corresponding/vendor"$|directory = "vendor"|' cargo-vendor-config.toml
    grep -Fx 'directory = "vendor"' cargo-vendor-config.toml >/dev/null
    mkdir recipe
    cp /recipe/{Dockerfile,build.sh,smoke.mjs} recipe/
    tar -czf "/out/$prefix-linux-x64-glibc-source.tar.gz" -C /corresponding .
    ;;
  *) printf 'invalid stage: %s\n' "$1" >&2; exit 2 ;;
esac
