ARG BUILD_FROM
FROM ${BUILD_FROM}

# curl stays at runtime: bashio uses it for every Supervisor call (see the
# note in dartec_link/Dockerfile). jq edits HA's config-entry store; unzip
# unpacks the HACS release.
RUN apk add --no-cache curl jq unzip

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
