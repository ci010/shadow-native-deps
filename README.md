# Shadow native dependencies

Public build recipes and corresponding-source bundles for Shadow. No third-party prebuilt aria2 binaries are consumed.

## aria2 1.37.0 / recipe 1

Source: https://github.com/aria2/aria2 at `02f2d0d8472b3c38c29b4dba8c75ebd5fdd2899a`.
Release: `aria2-1.37.0-shadow.1`. Targets: Windows x64, macOS x64/ARM64 and Linux x64 (Ubuntu 22.04 baseline).

`workflow_dispatch` builds all four native targets. Only a successful complete matrix can publish. Existing release tags are never overwritten. Archives have SHA-256 sidecars. Consumers must pin release URL and independently record the real archive digest, not trust a sidecar downloaded alongside an unpinned binary.

The build script is copied from Shadow's `scripts/build-aria2-native.sh`: HTTP(S)/FTP focused, no BitTorrent, Metalink, NLS, XML, c-ares, SSH or SQLite. macOS uses AppleTLS; Linux/Windows use OpenSSL; Windows uses ARIA2_STATIC. CI executes the binary in the normal runner environment (outside MSYS2), validates header architecture/version, checks Linux loader resolution and records macOS linked libraries. This is native-runner validation, not a claim of compatibility with every OS version.

Each archive contains `aria2c` (or `.exe`), `aria2-1.37.0-source.tar.gz`, `COPYING`, `LICENSE.OpenSSL`, the exact build script, and `THIRD-PARTY-NOTICES.txt` (including installed Windows toolchain/OpenSSL notices). aria2 is distributed under its bundled GPL license (GPL-2.0-or-later with the exceptions documented in upstream COPYING). Preserve all license notices and corresponding source when redistributing. The aria2 OpenSSL exception and actual dependency notices are included; inspect upstream licenses before downstream redistribution. Build-system packages are installed from the hosted runner's OS package repositories, and are not vendored.

## LayerFS Node SDK 2.0.0-rc.1 / recipe 1

The Linux x86-64 glibc `@layerfs/node` package is built from public LayerFS commit [`ff114a5265e2b504db437e7514e4ac09c8a6ca70`](https://github.com/Ephemeral-AI-Lab/layerfs/commit/ff114a5265e2b504db437e7514e4ac09c8a6ca70). The recipe checks the commit, tree and exact `Cargo.lock`; it does not track a branch or consume an upstream prebuilt addon. It builds with upstream `npm --prefix api run build:native` and packs with upstream `npm pack` in `api/node`. Rust 1.85.1, the Debian 12 amd64 builder image (glibc 2.36), Ubuntu 24.04 amd64 consumer image (glibc 2.39), and the upstream Node 22.22.0 archive (bundling npm 10.9.4) are pinned. The offline build and smoke have no Docker socket or host LayerFS home.

From this repository root, on a native Linux x64 Docker/BuildKit host, with a new output directory:

```sh
docker buildx build --platform linux/amd64 --progress plain --output type=local,dest=dist integrations/layerfs-node
(cd dist && sha256sum --strict -c SHA256SUMS)
```

The Ubuntu smoke installs only the packed tarball into a fresh npm project, without networking, lifecycle scripts, or `LAYERFS_NATIVE`. It tests ELF loader resolution and the real import, validates and exports the native call table, calls `machine.platforms()` and checks that the isolated home stays empty. This qualifies the SDK import and discovery on **Ubuntu 24.04 glibc 2.39 / OpenSSL 3 / Node 22.22.0**. Building on glibc 2.36 and recording the highest referenced ELF symbol do not lower Shadow's glibc >= 2.39 manifest policy or establish compatibility with every distro, Node version or OS. Both `libssl.so.3` and `libcrypto.so.3` must resolve. No musl, other arch/OS, Windows CLI or DSH compatibility is claimed.

`.github/workflows/layerfs-node.yml` is manual; `publish=false` (default) produces only the `layerfs-node-linux-x64-glibc` Actions artifact. After reviewing that run, use `publish=true` on `main` to rebuild, requalify and release. Only the release job receives contents-write. It rejects existing tags and releases (including drafts), checks the new draft's uploaded hashes before publishing and never replaces an asset. The repo does not enforce GitHub's repository-wide Immutable Releases setting; this recipe follows a publish-once convention, not a platform-enforced guarantee. If a failed attempt leaves a draft, inspect it before trying again; the workflow will not replace it. Recipe or toolchain changes require a new `shadow.N` tag. Do not lock hashes from build-only output: download the actual published asset and independently compute/record its SHA-256 in Shadow.

Expected release tag: `layerfs-node-2.0.0-rc.1-shadow.1`. Under `https://github.com/ci010/shadow-native-deps/releases/download/layerfs-node-2.0.0-rc.1-shadow.1/`:

- `layerfs-node-2.0.0-rc.1-linux-x64-glibc.tgz` — npm package with upstream MIT `LICENSE`, declarations, and addon.
- `call-table.json` — structured native SDK families and calls from the installed package, not from a CLI help scrape.
- `provenance.json` — source and lock identity, build/toolchain, addon and tarball SHA-256, ABI/loader/smoke results, and CI producer/run identity when built in Actions.
- `layerfs-node-2.0.0-rc.1-linux-x64-glibc-source.tar.gz` — pinned LayerFS source archive, build recipe, exact lock and locked Cargo sources with shipped licenses (includes packages outside the addon graph), linked system-library notices, and the actual addon Cargo tree. System libraries are not bundled; preserve applicable notices when redistributing. The Cargo source copy is for distribution/inspection and is not substituted into the upstream build.
- `SHA256SUMS` — digest of every payload above.

This is the host SDK only. Any worker-backed workspace test needs a separately produced and verified sealed Linux guest bundle from the same upstream pin (see upstream `tools/linux_bundle.py` and its `bundle.json` protocol/platform/hash contract). The smoke neither creates a machine nor qualifies guest/workspace operation. Do not substitute an unrelated CLI or reuse an existing Shadow runtime/home for the workspace acceptance test.

## Maintenance

Update the source revision in both script and workflow, review upstream license/security changes, and increment the `shadow.N` recipe suffix for any recipe/toolchain change. Never replace published assets. Run the workflow manually, inspect all native gates and release checksums, then update Shadow's pinned lock using actual published digests. Source revision is immutable, but hosted runner images and package versions evolve: this recipe does not promise bit-for-bit reproducibility. GitHub run logs identify the actual build environment. Only the release job receives contents-write permission; checkouts do not persist credentials.

Windows Autotools are selected explicitly with `WANT_AUTOCONF=2.71` and `WANT_AUTOMAKE=1.16` (provided by MSYS2 versioned packages). Both tested Autoconf 2.73 and 2.71 generated invalid shell for upstream wslay's raw case/AC_CHECK_HEADERS combination. `wslay-autoconf.patch` converts that one conditional to the proper AS_CASE macro; no compiler flags or library code change. The build script copies/applies this patch and checks both generated configure scripts with `bash -n` as a regression gate. Each bundle contains the immutable baseline source archive plus the exact patch and replayable build script. Recipe `shadow.1` identifies this complete recipe (none of the failed attempts was released); published archive SHA-256 covers both script and patch bytes. Rebuilding extracted baseline source requires keeping this patch alongside the bundled script. Future patch changes require a new recipe version.

## agent-desktop 0.10.1 / recipe 1

`agent-desktop-0.10.1-shadow.1` builds **Windows x64 and ARM64 on matching native runners**. macOS/Linux do not consume this Windows-only backend. The pinned upstream is `lahfir/agent-desktop@5a2c9ad43e269164a8adc8978a733c40b1d38a8b` (Apache-2.0). The complete independent addon, owned observation/gate patches, and C# input guard live here; no Shadow checkout, package install, pre-existing native output or source cache is required.

Replay in a Windows MSVC developer shell with Node 24.15.0 and Rust 1.94.0: `node scripts/build-agent-desktop.mjs x64` (or `arm64` on native ARM64). Git, Windows SDK, .NET Framework 4 compiler/runtime, and tar are prerequisites. Do not fetch before invoking this fresh-build recipe; it fetches and verifies the upstream itself. No upstream scripts are executed. Registry crates use the committed Cargo.lock. Source distributions contain recipe.tar, pinned unmodified upstream.tar, and vendor/ with all dependency source and license notices. Preserve LICENSE, NOTICE, THIRD-PARTY-NOTICES.json, provenance.json and source.tar.gz with redistributions. Shadow-owned migrated source is Apache-2.0 by copyright-holder authorization; this does not change the license of the rest of Shadow. Windows system assemblies are not bundled.

The manual workflow publishes only after both native targets pass source contracts, locked Rust tests, isolated addon identity/request/shutdown, guard identity, PE architecture and dependency checks. No UI enumeration, capture, input injection, elevated process access, signing or live provider acceptance is claimed. Addon and guard retain all existing runtime permissions and fail-closed safety constraints. Recipe/compiler changes require a new version; application-only changes do not trigger native builds. Runner images/SDK/system compiler versions remain externally supplied and logged; this is replayable, not a byte-for-byte reproducibility promise. Only the release job has write permission.
