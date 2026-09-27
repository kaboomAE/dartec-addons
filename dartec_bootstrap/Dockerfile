ARG BUILD_FROM
FROM ${BUILD_FROM}

# curl stays at runtime: bashio uses it for every Supervisor call (see the
# note in dartec_link/Dockerfile). jq edits HA's config-entry store and reads
# HACS's manifest; unzip unpacks the HACS release.
RUN apk add --no-cache curl jq unzip

# HACS is fetched here, once, by the build, and never in a home. The archive
# must be byte for byte the one pinned in hacs.pin, or there is no image: HACS
# runs inside Home Assistant Core, with everything Core can reach. It comes
# only from HACS's own release assets, over HTTPS all the way through GitHub's
# redirect. run.sh checks the baked copy again before unpacking it.
COPY hacs.pin hacs.sh /opt/dartec/
RUN bash -euo pipefail -c '\
    . /opt/dartec/hacs.pin; . /opt/dartec/hacs.sh; \
    hacs_check_pin; \
    curl --proto "=https" --proto-redir "=https" --tlsv1.2 -fsSL --max-time 300 \
        -o "${HACS_ARCHIVE}" "$(hacs_url)"; \
    hacs_verify "${HACS_ARCHIVE}"; \
    echo "HACS ${HACS_VERSION} verified: ${HACS_SHA256}"'

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
