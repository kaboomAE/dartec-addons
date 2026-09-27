ARG BUILD_FROM
FROM ${BUILD_FROM}

# Pinned deliberately. tailscaled talks a versioned protocol to the control
# plane, and "latest" would mean a customer's house silently changing its
# networking stack on a rebuild. Bump this on purpose, with a changelog entry.
ARG TAILSCALE_VERSION=1.94.2
# ... and so are its bytes, one SHA-256 per architecture, copied from the
# .sha256 Tailscale publishes beside each tarball. A new version needs all
# three replaced in the same commit. The build refuses a tarball that does not
# match this pin, and a pin that Tailscale's published checksum disagrees with.
ARG TAILSCALE_SHA256_AMD64=c6f99a5d774c7783b56902188d69e9756fc3dddfb08ac6be4cb2585f3fecdc32
ARG TAILSCALE_SHA256_ARM64=76300e808c57eb7853090d69c8bd8806e86341862e244183f6611f9105799bba
ARG TAILSCALE_SHA256_ARM=e5d1489c8315c88deb7d0104a9eb16a116938fff9455f8232703a1a1bf957b65
ARG BUILD_ARCH

# The static tarball rather than the Alpine package: the package lags, and its
# version moves when the base image moves, which is the thing we are pinning
# against. Checked against the SHA-256 pinned above -- this binary gets
# NET_ADMIN in a customer's home, so an unverified download is not acceptable
# here. A checksum fetched from the same place as the tarball, on its own,
# would only prove that the two agree with each other.
# curl is NOT only a build dependency: bashio shells out to it for every
# Supervisor API call. Removing it after the build left `bashio::config`
# returning nothing, so the add-on read an empty login_server and stopped
# itself -- with "curl: command not found" as the only clue. It stays.
#
# This note lives ABOVE the RUN rather than inside it: a # line within a
# continuation is handled differently across Docker versions, and once the
# continuations are joined a stray # comments out the rest of the command.
RUN set -eux; \
    case "${BUILD_ARCH}" in \
      amd64)   TS_ARCH="amd64"; TS_SHA256="${TAILSCALE_SHA256_AMD64}" ;; \
      aarch64) TS_ARCH="arm64"; TS_SHA256="${TAILSCALE_SHA256_ARM64}" ;; \
      armv7)   TS_ARCH="arm";   TS_SHA256="${TAILSCALE_SHA256_ARM}"   ;; \
      *) echo "unsupported architecture: ${BUILD_ARCH}" >&2; exit 1 ;; \
    esac; \
    echo "${TS_SHA256}" | grep -Eqx '[0-9a-f]{64}'; \
    apk add --no-cache ca-certificates iptables iproute2 curl; \
    cd /tmp; \
    curl --proto "=https" --proto-redir "=https" --tlsv1.2 -fsSL -o ts.tgz \
      "https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_${TS_ARCH}.tgz"; \
    curl --proto "=https" --proto-redir "=https" --tlsv1.2 -fsSL -o ts.sha256 \
      "https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_${TS_ARCH}.tgz.sha256"; \
    test "$(tr -d ' \n' < ts.sha256)" = "${TS_SHA256}"; \
    echo "${TS_SHA256}  ts.tgz" | sha256sum -c -; \
    tar xzf ts.tgz; \
    install -m 755 "tailscale_${TAILSCALE_VERSION}_${TS_ARCH}/tailscaled" /usr/sbin/tailscaled; \
    install -m 755 "tailscale_${TAILSCALE_VERSION}_${TS_ARCH}/tailscale"  /usr/bin/tailscale; \
    rm -rf /tmp/*

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
