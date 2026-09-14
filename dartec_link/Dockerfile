ARG BUILD_FROM
FROM ${BUILD_FROM}

# Pinned deliberately. tailscaled talks a versioned protocol to the control
# plane, and "latest" would mean a customer's house silently changing its
# networking stack on a rebuild. Bump this on purpose, with a changelog entry.
ARG TAILSCALE_VERSION=1.94.2
ARG BUILD_ARCH

# The static tarball rather than the Alpine package: the package lags, and its
# version moves when the base image moves, which is the thing we are pinning
# against. Checked against the published SHA256 -- this binary gets NET_ADMIN
# in a customer's home, so an unverified download is not acceptable here.
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
      amd64)   TS_ARCH="amd64"  ;; \
      aarch64) TS_ARCH="arm64"  ;; \
      armv7)   TS_ARCH="arm"    ;; \
      *) echo "unsupported architecture: ${BUILD_ARCH}" >&2; exit 1 ;; \
    esac; \
    apk add --no-cache ca-certificates iptables iproute2 curl; \
    cd /tmp; \
    curl -fsSL -o ts.tgz \
      "https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_${TS_ARCH}.tgz"; \
    curl -fsSL -o ts.sha256 \
      "https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_${TS_ARCH}.tgz.sha256"; \
    echo "$(cat ts.sha256)  ts.tgz" | sha256sum -c -; \
    tar xzf ts.tgz; \
    install -m 755 "tailscale_${TAILSCALE_VERSION}_${TS_ARCH}/tailscaled" /usr/sbin/tailscaled; \
    install -m 755 "tailscale_${TAILSCALE_VERSION}_${TS_ARCH}/tailscale"  /usr/bin/tailscale; \
    rm -rf /tmp/*

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
