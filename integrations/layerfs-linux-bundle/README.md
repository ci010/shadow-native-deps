# LayerFS Linux x64 build verification

Manually dispatch **Build test-only LayerFS Linux bundle (x64)** with `upload_artifact=false` (the default) in `ci010/shadow-native-deps`. GitHub requires the workflow to be present on the default branch before it can receive manual dispatches. The hosted Ubuntu 24.04 x64 runner builds, seals, packs and rechecks the bundle in job-local scratch, then reports sizes and SHA-256 digests. Nothing is retained for download. No LayerFS worker or runtime starts. The build uses only public inputs, no repository secrets, private feeds, host resources, or Docker socket mounted into a container. Checkout does not persist credentials.

For an approved private Actions repository, an explicit `upload_artifact=true` request retains only the checked tarball and `SHA256SUMS` for seven days. The same request fails in a public repository, including `ci010/shadow-native-deps`. The shell-only Ubuntu fixture replaces the unpublished upstream default solely for this build check. Neither a verified build nor a private upload authorizes a live runtime test or wider redistribution.

## Before redistributing a bundle

Obtain explicit approval and review the obligations for the exact payload built, not just the LayerFS repository license:

- Preserve the upstream LayerFS MIT notice and any applicable notices or license texts for Rust dependencies actually compiled into the payload. Inventory those dependencies against the locked build and verify any additional obligations.
- Preserve the sealed runtime's `licenses/`, including the Debian copyright files and `SOURCES`. Use `sandbox_runtime.sources` and the recorded signed APT package metadata to obtain the exact corresponding Debian sources for the copied runtime files (including any patches and applicable build scripts). The upstream `linux_bundle.py sources` command can collect the named Debian source packages. It is not run by this build-only workflow.
- `sandbox-image.tar` redistributes a full pinned Ubuntu base layer. Inventory the packages in that exact amd64 image and preserve its notices; obtain corresponding source for covered packages at their exact Ubuntu source versions. The Debian runtime source list does not cover this Ubuntu layer.
- Make any required corresponding source available to recipients with the same release, or use another license-permitted source delivery method whose terms the actual distributor can satisfy. Include patches and build/install scripts as applicable. Do not rely on an upstream maintainer's source offer or on image/package digests alone to meet the distributor's obligations. This workflow does not assemble or validate a redistribution-ready source package.
