# Shadow native dependencies

Public build recipes and corresponding-source bundles for Shadow. No third-party prebuilt aria2 binaries are consumed.

## aria2 1.37.0 / recipe 1

Source: https://github.com/aria2/aria2 at `02f2d0d8472b3c38c29b4dba8c75ebd5fdd2899a`.
Release: `aria2-1.37.0-shadow.1`. Targets: Windows x64, macOS x64/ARM64 and Linux x64 (Ubuntu 22.04 baseline).

`workflow_dispatch` builds all four native targets. Only a successful complete matrix can publish. Existing release tags are never overwritten. Archives have SHA-256 sidecars. Consumers must pin release URL and independently record the real archive digest, not trust a sidecar downloaded alongside an unpinned binary.

The build script is copied from Shadow's `scripts/build-aria2-native.sh`: HTTP(S)/FTP focused, no BitTorrent, Metalink, NLS, XML, c-ares, SSH or SQLite. macOS uses AppleTLS; Linux/Windows use OpenSSL; Windows uses ARIA2_STATIC. CI executes the binary in the normal runner environment (outside MSYS2), validates header architecture/version, checks Linux loader resolution and records macOS linked libraries. This is native-runner validation, not a claim of compatibility with every OS version.

Each archive contains `aria2c` (or `.exe`), `aria2-1.37.0-source.tar.gz`, `COPYING`, `LICENSE.OpenSSL`, the exact build script, and `THIRD-PARTY-NOTICES.txt` (including installed Windows toolchain/OpenSSL notices). aria2 is distributed under its bundled GPL license (GPL-2.0-or-later with the exceptions documented in upstream COPYING). Preserve all license notices and corresponding source when redistributing. The aria2 OpenSSL exception and actual dependency notices are included; inspect upstream licenses before downstream redistribution. Build-system packages are installed from the hosted runner's OS package repositories, and are not vendored.

## Maintenance

Update the source revision in both script and workflow, review upstream license/security changes, and increment the `shadow.N` recipe suffix for any recipe/toolchain change. Never replace published assets. Run the workflow manually, inspect all native gates and release checksums, then update Shadow's pinned lock using actual published digests. Source revision is immutable, but hosted runner images and package versions evolve: this recipe does not promise bit-for-bit reproducibility. GitHub run logs identify the actual build environment. Only the release job receives contents-write permission; checkouts do not persist credentials.

Windows Autotools are selected explicitly with `WANT_AUTOCONF=2.71` and `WANT_AUTOMAKE=1.16` (provided by the MSYS2 versioned packages). Autoconf 2.73 generates invalid shell in the unmodified upstream wslay configure script; the release gate checks the chosen version rather than patching pinned aria2 source.
