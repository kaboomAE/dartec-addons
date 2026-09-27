#!/usr/bin/env bash
# dartec_link installs only the Tailscale tarball pinned in its Dockerfile.
#
# 1. Every pinned SHA-256 is the one Tailscale publishes for that tarball.
# 2. The image builds with the pins as they are.
# 3. It does not build when the pin is wrong: not when the tarball differs
#    from the pin, and not when Tailscale's published checksum does.
#
# Needs docker and curl.
#
#   bash tests/link_tailscale_test.sh
set -euo pipefail
export MSYS_NO_PATHCONV=1

here="$(cd "$(dirname "$0")" && { pwd -W 2>/dev/null || pwd; })"
repo="$(cd "${here}/.." && { pwd -W 2>/dev/null || pwd; })"
dockerfile="${repo}/dartec_link/Dockerfile"
ARCH="${ARCH:-amd64}"
BASE="$(sed -n "s|^  ${ARCH}:[[:space:]]*||p" "${repo}/dartec_link/build.yaml")"
failures=0

pass() { echo "  PASS  $*"; }
fail() { echo "  FAIL  $*"; failures=$((failures + 1)); }
check() { local what="$1"; shift; if "$@"; then pass "${what}"; else fail "${what}"; fi; }
arg() { sed -n "s|^ARG $1=||p" "${dockerfile}"; }

version="$(arg TAILSCALE_VERSION)"
echo "== pins against Tailscale's published checksums (${version})"
for pair in AMD64:amd64 ARM64:arm64 ARM:arm; do
    pinned="$(arg "TAILSCALE_SHA256_${pair%%:*}")"
    published="$(curl --proto '=https' -fsSL \
        "https://pkgs.tailscale.com/stable/tailscale_${version}_${pair##*:}.tgz.sha256" | tr -d ' \n')"
    check "${pair##*:}: pinned ${pinned:0:12}... is the published checksum" [ "${pinned}" = "${published}" ]
done

build() {
    docker build -q --no-cache --build-arg "BUILD_FROM=${BASE}" --build-arg "BUILD_ARCH=${ARCH}" "$@" \
        -t dartec-link-test:local "${repo}/dartec_link" >/dev/null 2>&1
}
wont_build() { ! build "$@"; }
case "${ARCH}" in amd64) key=AMD64 ;; aarch64) key=ARM64 ;; armv7) key=ARM ;; esac
echo "== the image (${ARCH})"
check "builds with the pinned tarball"      build
check "does not build with a wrong pin"     wont_build --build-arg "TAILSCALE_SHA256_${key}=$(printf '%064d' 0)"
check "does not build with a malformed pin" wont_build --build-arg "TAILSCALE_SHA256_${key}=latest"
docker rmi dartec-link-test:local >/dev/null 2>&1 || true

echo
if [ "${failures}" -eq 0 ]; then
    echo "all checks passed"
else
    echo "${failures} check(s) failed"; exit 1
fi
