# Build context must be this directory. Use BuildKit and native linux/amd64.
FROM rust:1.85.1-bookworm@sha256:bf7d87666c4da6eace19e06d21bc4859c6e2a5c97a21ac273b0e082112753cf0 AS builder
COPY build.sh /recipe/build.sh
RUN bash /recipe/build.sh fetch
RUN --network=none bash /recipe/build.sh build
COPY Dockerfile smoke.mjs /recipe/
RUN bash /recipe/build.sh bundle

# Shadow's manifest policy is glibc >= 2.39. Exercise the consumer ABI on Noble
# rather than inferring it from a successful Bookworm build or ELF symbols.
FROM ubuntu:24.04@sha256:77eb101c607d6e3d4f5ad0c8a02c2136c689b98aba1f359e6502ba517e5c57ec AS consumer
# The pinned Noble image includes the libssl3t64 runtime used by the smoke.
COPY --from=builder /opt/node /opt/node
COPY --from=builder /out /out
COPY smoke.mjs /recipe/smoke.mjs
RUN --network=none env -i PATH=/opt/node/bin:/usr/bin:/bin bash -euo pipefail -c '\
    test "$(getconf GNU_LIBC_VERSION)" = "glibc 2.39"; \
    test "$(node --version)" = v22.22.0; \
    test "$(npm --version)" = 10.9.4; \
    mkdir -p /smoke/home /smoke/project; cd /smoke/project; \
    export HOME=/smoke/home npm_config_cache=/smoke/npm-cache; \
    printf "{\"name\":\"layerfs-node-smoke\",\"private\":true}\n" > package.json; \
    npm install --offline --ignore-scripts --no-audit --no-fund --package-lock=false /out/layerfs-node-2.0.0-rc.1-linux-x64-glibc.tgz; \
    ldd node_modules/@layerfs/node/layerfs.node | tee /smoke/loader; \
    if grep -F "not found" /smoke/loader; then exit 1; fi; \
    dpkg-query -W -f="\${Package} \${Version}\n" libc6 libssl3t64; \
    cp /recipe/smoke.mjs .; node smoke.mjs /out; \
    cd /out; sha256sum -- *.tgz *.json *.tar.gz > SHA256SUMS; sha256sum -c SHA256SUMS'

FROM scratch AS release-assets
COPY --from=consumer /out/ /
