#!/usr/bin/env bash
set -euo pipefail
umask 022

readonly upstream=https://github.com/Ephemeral-AI-Lab/layerfs.git
readonly commit=ff114a5265e2b504db437e7514e4ac09c8a6ca70
readonly tree=6aba9fc617137bea646119938e18b0b1dda558a3
readonly lock=3e92435847d41da4323a206842fd94e1cbe0cc685ac079906268aebce9926bf6
# Use the same approved platform manifest pins as the native-deps Node SDK recipe.
readonly builder=docker.io/library/rust:1.85.1-bookworm@sha256:bf7d87666c4da6eace19e06d21bc4859c6e2a5c97a21ac273b0e082112753cf0
readonly base=docker.io/library/ubuntu:24.04@sha256:77eb101c607d6e3d4f5ad0c8a02c2136c689b98aba1f359e6502ba517e5c57ec
readonly recipe="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly scratch="${RUNNER_TEMP:?set RUNNER_TEMP to a private per-job directory}"
readonly prefix=layerfs-test-only-2.0.0-linux-x86_64
readonly out="$scratch/layerfs-test-bundle"

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null PYTHONDONTWRITEBYTECODE=1
export DOCKER_BUILDKIT=1
[[ "$(uname -s):$(uname -m)" == Linux:x86_64 ]]
python3 -c 'import fcntl, sys, tomllib; sys.exit(0 if sys.version_info >= (3, 11) else "Python 3.11+ required")'
[[ "$(docker info --format '{{.OSType}}:{{.Architecture}}')" == linux:x86_64 ]]
# Headroom for image unpacking, locked dependencies and the private Cargo target.
docker_root=$(docker info --format '{{.DockerRootDir}}')
for storage in "$scratch" "$docker_root"; do
  df -h -- "$storage"
  df -Pk -- "$storage" | awk 'NR == 2 { ok = ($4 >= 10 * 1024 * 1024) } END { exit !ok }'
done
mkdir -- "$out"
work=$(mktemp -d -- "$scratch/layerfs-bundle-build.XXXXXXXX")
trap 'status=$?; if (( status != 0 )); then
  find "$work/state" -maxdepth 4 -type f -name "*.log" -print -exec tail -n 40 {} \; 2>/dev/null || :
  df -h -- "$scratch" "$docker_root"
fi' EXIT
src="$work/upstream"
git init --template= "$src"
git -C "$src" remote add origin "$upstream"
git -C "$src" fetch --no-tags --depth=1 origin "$commit"
git -C "$src" -c core.autocrlf=false checkout --detach FETCH_HEAD
verify_source() {
  [[ "$(git -C "$src" rev-parse HEAD)" == "$commit" ]]
  [[ "$(git -C "$src" rev-parse 'HEAD^{tree}')" == "$tree" ]]
  printf '%s  %s\n' "$lock" "$src/Cargo.lock" | sha256sum --strict -c
  [[ -z "$(git -C "$src" status --porcelain --untracked-files=all)" ]]
}
verify_source
(cd "$src/tools" && python3 -m unittest -v test_linux_bundle)

docker pull --platform linux/amd64 "$builder"
docker pull --platform linux/amd64 "$base"
# Upstream's default is unpublished. This intentionally shell-only fixture has
# no apt, no repository checkout, no private config and no supplied credentials.
sandbox="layerfs-bundle-ci:${work##*.}"
docker build --platform linux/amd64 --network=none --build-arg "BASE=$base" --tag "$sandbox" - <<'DOCKERFILE'
ARG BASE
FROM ${BASE}
LABEL org.shadow.layerfs.fixture="shell-only-test"
CMD ["/bin/bash"]
DOCKERFILE
for image in "$builder" "$base" "$sandbox"; do
  [[ "$(docker image inspect --format '{{.Os}}:{{.Architecture}}' "$image")" == linux:amd64 ]]
done

cd "$src"
resources=$(python3 tools/worktree.py register --owner native-deps-bundle-ci \
  --worktree "$src" --root "$work/state" --build-image "$builder" \
  --runtime-image "$base" --sandbox-image "$sandbox")
python3 tools/worktree.py prepare --resources "$resources" --platform linux
# A cold optimized compile can exceed linux_bundle.py's hard 300 s ceiling.
# Populate only its private target, using the same offline Cargo flags and
# feature sets, then let linux_bundle.py independently build/stamp each step.
prewarm() {
  python3 tools/worktree.py cargo --resources "$resources" --platform linux --timeout 1200 \
    -- build "$@" -j 6 --release
}
prewarm -p layerfs-daemon --bin layerfs-daemon
prewarm -p layerfs-cli --no-default-features --bin layerfs
prewarm -p layerfs-sandbox-backend --bin layerfs-sandbox-helper
for step in daemon worker helper runtime seal; do
  python3 tools/linux_bundle.py "$step" --profile release --timeout 300 \
    --resources "$resources" --dest "$work/stage"
done
verify_source
bundle="$work/stage/2.0.0/linux-x86_64"
python3 "$recipe/verify.py" "$bundle" "$resources" "$commit" "$tree" "$lock" "$builder" "$base" \
  > "$work/stage/BUILD-PROVENANCE.json"
cp -- "$src/LICENSE" "$work/stage/UPSTREAM-LICENSE"

# Preserve executable modes. Upload only an already-compressed tar and checksum.
tar --format=pax -C "$work/stage" -czf "$out/$prefix.tar.gz" \
  2.0.0 BUILD-PROVENANCE.json UPSTREAM-LICENSE
raw=$(du --apparent-size --bytes --summarize -- "$work/stage" | cut -f1)
packed=$(stat -c %s -- "$out/$prefix.tar.gz")
sandbox_bytes=$(stat -c %s -- "$bundle/sandbox-image.tar")
summary="Bytes: Sandbox docker-archive=$sandbox_bytes; staged payload=$raw; tar.gz=$packed."
printf '%s\n' "$summary"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then printf '%s\n' "$summary" >> "$GITHUB_STEP_SUMMARY"; fi
# Local test policy, not GitHub product limits. Fail closed on size regressions.
(( raw <= 512 * 1024 * 1024 && packed <= 256 * 1024 * 1024 ))
# Revalidate the actual transport payload as a downstream Linux consumer sees it.
mkdir -- "$work/unpack"
tar -xzf "$out/$prefix.tar.gz" -C "$work/unpack"
python3 "$recipe/verify.py" "$work/unpack/2.0.0/linux-x86_64" "$resources" \
  "$commit" "$tree" "$lock" "$builder" "$base" > "$work/rechecked.json"
cmp -- "$work/rechecked.json" "$work/unpack/BUILD-PROVENANCE.json"
cmp -- "$src/LICENSE" "$work/unpack/UPSTREAM-LICENSE"
(cd "$out" && sha256sum -- "$prefix.tar.gz" > SHA256SUMS && sha256sum --strict -c SHA256SUMS)
# Only metadata goes to the logs and summary; the public run never uploads files.
tar_line=$(cat -- "$out/SHA256SUMS")
bundle_hash=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["bundle_sha256"])' "$work/rechecked.json")
printf 'Verified sealed bundle SHA-256: %s\nVerified transport SHA-256: %s\n' "$bundle_hash" "$tar_line"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '\n- Sealed bundle SHA-256: `%s`\n- Transport SHA-256: `%s`\n' \
    "$bundle_hash" "${tar_line%% *}" >> "$GITHUB_STEP_SUMMARY"
fi
