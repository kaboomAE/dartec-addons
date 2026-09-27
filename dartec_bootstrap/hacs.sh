# shellcheck shell=bash
# Checking and unpacking the pinned HACS archive (hacs.pin).
#
# Sourced by the Dockerfile, which fetches the archive and must not build an
# image around the wrong bytes, and by run.sh, which checks the baked copy
# again and is the only thing that ever puts it into a home. Each function
# prints why it refused and returns non-zero; the callers decide what that
# means for a build or a run.

# shellcheck disable=SC2034  # read by run.sh and the Dockerfile
HACS_ARCHIVE="/opt/dartec/hacs.zip"

# The pin itself: HACS's own repository, a release tag (never a branch), and a
# whole SHA-256. A pin that fails this is a mistake in this repository, and
# nothing is fetched or unpacked on the strength of it.
hacs_check_pin() {
    if [ "${HACS_REPO:-}" != "hacs/integration" ]; then
        echo "HACS_REPO is '${HACS_REPO:-}', not hacs/integration"; return 1
    fi
    if ! [[ "${HACS_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "HACS_VERSION '${HACS_VERSION:-}' is not a release tag such as 2.0.5"; return 1
    fi
    if ! [[ "${HACS_SHA256:-}" =~ ^[0-9a-f]{64}$ ]]; then
        echo "HACS_SHA256 is not a SHA-256 (64 lowercase hex characters)"; return 1
    fi
}

# Built from the pin alone: the expected repository's release asset, nowhere else.
hacs_url() {
    echo "https://github.com/${HACS_REPO}/releases/download/${HACS_VERSION}/hacs.zip"
}

hacs_verify() {
    local archive="$1" actual
    if [ ! -f "${archive}" ]; then
        echo "${archive} does not exist"; return 1
    fi
    actual="$(sha256sum "${archive}" | cut -d' ' -f1)"
    if [ "${actual}" != "${HACS_SHA256}" ]; then
        echo "its SHA-256 is ${actual}, not the pinned ${HACS_SHA256}"; return 1
    fi
}

# Unpack a verified archive into <config>/custom_components/hacs.
#
# It goes into a staging directory beside custom_components first, on the same
# filesystem, and is renamed into place only once it is complete and its
# manifest names the pinned version. A refusal leaves custom_components as it
# was.
hacs_unpack() {
    local archive="$1" config="$2" stage version
    hacs_check_pin || return 1
    hacs_verify "${archive}" || return 1
    stage="${config}/.dartec-bootstrap-hacs"
    rm -rf "${stage}"
    mkdir -p "${stage}"
    if ! unzip -q "${archive}" -d "${stage}"; then
        rm -rf "${stage}"; echo "unzip failed"; return 1
    fi
    version="$(jq -r '.version // empty' "${stage}/manifest.json" 2>/dev/null || true)"
    if [ "${version}" != "${HACS_VERSION}" ]; then
        rm -rf "${stage}"; echo "its manifest says version '${version}', not ${HACS_VERSION}"; return 1
    fi
    mkdir -p "${config}/custom_components"
    rm -rf "${config}/custom_components/hacs"
    mv "${stage}" "${config}/custom_components/hacs"
}
