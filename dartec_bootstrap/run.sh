#!/usr/bin/with-contenv bashio
# Install HACS and activate it without GitHub's device flow.
#
# This is the HA Panel Designer's sandbox method (smarthome-planner, removed in
# 677c140: core/ha_sandbox.py _install_hacs/_activate_hacs) moved from Docker
# to the Supervisor: download HACS, stop Core, add a `hacs` config entry that
# carries the GitHub token, start Core. Never logs the token.
set -euo pipefail

HACS_VERSION="2.0.5"
CONFIG="/homeassistant"
ENTRIES="${CONFIG}/.storage/core.config_entries"
SUPERVISOR="http://supervisor"

TOKEN="$(bashio::config 'github_token')"
if bashio::var.is_empty "${TOKEN}"; then
    bashio::exit.nok "github_token is not set."
fi

supervisor_post() {
    curl -fsS -X POST -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" "${SUPERVISOR}$1" >/dev/null
}

# --- 1. HACS files --------------------------------------------------------
if [ -f "${CONFIG}/custom_components/hacs/manifest.json" ]; then
    bashio::log.info "HACS files already present; not downloading."
else
    bashio::log.info "Downloading HACS ${HACS_VERSION}."
    tmp="$(mktemp -d)"
    curl -fsSL -o "${tmp}/hacs.zip" \
        "https://github.com/hacs/integration/releases/download/${HACS_VERSION}/hacs.zip"
    mkdir -p "${CONFIG}/custom_components/hacs"
    unzip -q -o "${tmp}/hacs.zip" -d "${CONFIG}/custom_components/hacs"
    rm -rf "${tmp}"
    bashio::log.info "HACS unpacked into custom_components/hacs."
fi

# --- 2. Config entry --------------------------------------------------------
if [ ! -f "${ENTRIES}" ]; then
    bashio::exit.nok "${ENTRIES} does not exist; has onboarding finished?"
fi
if jq -e '.data.entries | any(.domain == "hacs")' "${ENTRIES}" >/dev/null; then
    bashio::log.info "A hacs config entry already exists; not touching the store."
    bashio::exit.ok
fi

# Stop Core first: it holds the store in memory and would overwrite our edit
# on its next save or on shutdown.
bashio::log.info "Stopping Home Assistant Core."
supervisor_post /core/stop

now="$(date -u +%Y-%m-%dT%H:%M:%S.000000+00:00)"
entry_id="$(od -An -N13 -tx1 /dev/urandom | tr -d ' \n' | cut -c1-26 | tr 'a-f' 'A-F')"

# Build the entry from an EXISTING entry in this very file rather than from a
# hand-written field list. The sandbox's hand-transcribed entry crash-looped HA
# 2026.7.4 on a missing `created_at`; copying the live shape keeps up with
# whatever fields this HA version expects, and we override every value that
# identifies the entry.
bashio::log.info "Template entry keys: $(jq -c '.data.entries[0] // {} | keys' "${ENTRIES}")"
cp "${ENTRIES}" "${ENTRIES}.dartec-bootstrap.bak"
jq --arg token "${TOKEN}" --arg id "${entry_id}" --arg now "${now}" '
  .data.entries += [
    ((.data.entries[0] // {}) + {
      entry_id: $id, version: 1, minor_version: 1, domain: "hacs", title: "",
      data: {token: $token}, options: {}, source: "user", unique_id: null,
      disabled_by: null, created_at: $now, modified_at: $now,
      discovery_keys: {}, pref_disable_new_entities: false,
      pref_disable_polling: false, subentries: []
    })
  ]' "${ENTRIES}.dartec-bootstrap.bak" > "${ENTRIES}.dartec-bootstrap.tmp"
mv "${ENTRIES}.dartec-bootstrap.tmp" "${ENTRIES}"
bashio::log.info "hacs config entry ${entry_id} written."

# --- 3. Start Core ----------------------------------------------------------
bashio::log.info "Starting Home Assistant Core."
supervisor_post /core/start
bashio::log.info "Done. Uninstall this add-on; it has nothing left to do."
