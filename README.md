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

Windows Autotools are selected explicitly with `WANT_AUTOCONF=2.71` and `WANT_AUTOMAKE=1.16` (provided by MSYS2 versioned packages). Both tested Autoconf 2.73 and 2.71 generated invalid shell for upstream wslay's raw case/AC_CHECK_HEADERS combination. `wslay-autoconf.patch` converts that one conditional to the proper AS_CASE macro; no compiler flags or library code change. The build script copies/applies this patch and checks both generated configure scripts with `bash -n` as a regression gate. Each bundle contains the immutable baseline source archive plus the exact patch and replayable build script. Recipe `shadow.1` identifies this complete recipe (none of the failed attempts was released); published archive SHA-256 covers both script and patch bytes. Rebuilding extracted baseline source requires keeping this patch alongside the bundled script. Future patch changes require a new recipe version.

## agent-desktop 0.10.1 / recipe 1

`agent-desktop-0.10.1-shadow.1` builds **Windows x64 and ARM64 on matching native runners**. macOS/Linux do not consume this Windows-only backend. The pinned upstream is `lahfir/agent-desktop@5a2c9ad43e269164a8adc8978a733c40b1d38a8b` (Apache-2.0). The complete independent addon, owned observation/gate patches, and C# input guard live here; no Shadow checkout, package install, pre-existing native output or source cache is required.

Replay in a Windows MSVC developer shell with Node 24.15.0 and Rust 1.94.0: `node scripts/build-agent-desktop.mjs x64` (or `arm64` on native ARM64). Git, Windows SDK, .NET Framework 4 compiler/runtime, and tar are prerequisites. Do not fetch before invoking this fresh-build recipe; it fetches and verifies the upstream itself. No upstream scripts are executed. Registry crates use the committed Cargo.lock. Source distributions contain recipe.tar, pinned unmodified upstream.tar, and vendor/ with all dependency source and license notices. Preserve LICENSE, NOTICE, THIRD-PARTY-NOTICES.json, provenance.json and source.tar.gz with redistributions. Shadow-owned migrated source is Apache-2.0 by copyright-holder authorization; this does not change the license of the rest of Shadow. Windows system assemblies are not bundled.

The manual workflow publishes only after both native targets pass source contracts, locked Rust tests, isolated addon identity/request/shutdown, guard identity, PE architecture and dependency checks. No UI enumeration, capture, input injection, elevated process access, signing or live provider acceptance is claimed. Addon and guard retain all existing runtime permissions and fail-closed safety constraints. Recipe/compiler changes require a new version; application-only changes do not trigger native builds. Runner images/SDK/system compiler versions remain externally supplied and logged; this is replayable, not a byte-for-byte reproducibility promise. Only the release job has write permission.
