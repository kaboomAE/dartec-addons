#!/usr/bin/with-contenv bashio
# Install HACS and activate it without GitHub's device flow.
#
# Download HACS, stop Core, add a `hacs` config entry that carries the GitHub
# token, start Core. Never logs either secret.
#
# It only does that when given a fresh, never-used `run_token` from the
# Dartec provisioner. Without one it only cleans up after an earlier run, so
# installing it from the store by hand can never stop someone's Core.
set -euo pipefail

HACS_VERSION="2.0.5"
CONFIG="/homeassistant"
ENTRIES="${CONFIG}/.storage/core.config_entries"
BACKUP="${ENTRIES}.dartec-bootstrap.bak"
SUPERVISOR="http://supervisor"
USED="/data/used_run_tokens"
TOKEN_MAX_AGE=1800

# Every Supervisor call has a ceiling: an unbounded curl is a add-on that never
# exits. /core/start returns only once Core is up (or has failed), so it gets
# the longest one.
supervisor_post() {
    curl -fsS --max-time "${2:-60}" -X POST \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" "${SUPERVISOR}$1" >/dev/null
}

cleanup_backup() {
    if [ -f "${BACKUP}" ]; then
        rm -f "${BACKUP}"
        bashio::log.info "Removed a leftover $(basename "${BACKUP}")."
    fi
}

# --- 0. Read both options, then wipe them from the Supervisor ---------------
GITHUB_TOKEN="$(bashio::config 'github_token')"
RUN_TOKEN="$(bashio::config 'run_token')"
if ! bashio::var.is_empty "${GITHUB_TOKEN}${RUN_TOKEN}"; then
    # /addons/self/options is open to every add-on role. Whatever happens
    # next, the token does not stay in this add-on's saved options.
    if curl -fsS --max-time 30 -X POST -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"options":{"github_token":"","run_token":""}}' \
        "${SUPERVISOR}/addons/self/options" >/dev/null; then
        bashio::log.info "Cleared this add-on's options."
    else
        bashio::log.warning "Could not clear this add-on's options; uninstall it to remove them."
    fi
fi

# --- 1. Is this a real provisioning run? -------------------------------------
valid_run_token() {
    local token="$1" issued now digest
    [[ "${token}" =~ ^dartec1\.([0-9]{10})\.[A-Za-z0-9_-]{16,128}$ ]] || { echo "malformed"; return 1; }
    issued="${BASH_REMATCH[1]}"
    now="$(date +%s)"
    if [ $((now - issued)) -gt "${TOKEN_MAX_AGE}" ] || [ $((issued - now)) -gt "${TOKEN_MAX_AGE}" ]; then
        echo "expired"; return 1
    fi
    digest="$(printf '%s' "${token}" | sha256sum | cut -d' ' -f1)"
    if [ -f "${USED}" ] && grep -qx "${digest}" "${USED}"; then
        echo "already used"; return 1
    fi
    echo "${digest}"
}

if bashio::var.is_empty "${RUN_TOKEN}"; then
    bashio::log.info "No run_token: clean-up only."
    cleanup_backup
    bashio::exit.ok
fi
if ! result="$(valid_run_token "${RUN_TOKEN}")"; then
    bashio::log.warning "run_token refused (${result}): clean-up only."
    cleanup_backup
    bashio::exit.ok
fi
# Spend it before doing anything, so a crash cannot make it reusable.
echo "${result}" >> "${USED}"

# --- 2. Config entry already there? -----------------------------------------
if [ ! -f "${ENTRIES}" ]; then
    bashio::exit.nok "${ENTRIES} does not exist; has onboarding finished?"
fi
if jq -e '.data.entries | any(.domain == "hacs")' "${ENTRIES}" >/dev/null; then
    bashio::log.info "A hacs config entry already exists; not touching the store."
    cleanup_backup
    bashio::exit.ok
fi
if bashio::var.is_empty "${GITHUB_TOKEN}"; then
    bashio::exit.nok "github_token is not set, and this box has no hacs entry yet."
fi

# --- 3. HACS files -------------------------------------------------------------
if [ -f "${CONFIG}/custom_components/hacs/manifest.json" ]; then
    bashio::log.info "HACS files already present; not downloading."
else
    bashio::log.info "Downloading HACS ${HACS_VERSION}."
    tmp="$(mktemp -d)"
    curl -fsSL --max-time 300 -o "${tmp}/hacs.zip" \
        "https://github.com/hacs/integration/releases/download/${HACS_VERSION}/hacs.zip"
    mkdir -p "${CONFIG}/custom_components/hacs"
    unzip -q -o "${tmp}/hacs.zip" -d "${CONFIG}/custom_components/hacs"
    rm -rf "${tmp}"
    bashio::log.info "HACS unpacked into custom_components/hacs."
fi

# --- 4. Write the entry with Core stopped ---------------------------------------
# Core holds the store in memory and would overwrite the edit on its next save.
bashio::log.info "Stopping Home Assistant Core."
supervisor_post /core/stop 300

now="$(date -u +%Y-%m-%dT%H:%M:%S.000000+00:00)"
entry_id="$(od -An -N13 -tx1 /dev/urandom | tr -d ' \n' | cut -c1-26 | tr 'a-f' 'A-F')"

# Built from an EXISTING entry in this very file rather than a hand-written
# field list, so it keeps up with whatever fields this HA version expects.
bashio::log.info "Template entry keys: $(jq -c '.data.entries[0] // {} | keys' "${ENTRIES}")"
cp "${ENTRIES}" "${BACKUP}"
jq --arg token "${GITHUB_TOKEN}" --arg id "${entry_id}" --arg now "${now}" '
  .data.entries += [
    ((.data.entries[0] // {}) + {
      entry_id: $id, version: 1, minor_version: 1, domain: "hacs", title: "",
      data: {token: $token}, options: {}, source: "user", unique_id: null,
      disabled_by: null, created_at: $now, modified_at: $now,
      discovery_keys: {}, pref_disable_new_entities: false,
      pref_disable_polling: false, subentries: []
    })
  ]' "${BACKUP}" > "${ENTRIES}.dartec-bootstrap.tmp"
mv "${ENTRIES}.dartec-bootstrap.tmp" "${ENTRIES}"
bashio::log.info "hacs config entry ${entry_id} written."

# --- 5. Start Core ------------------------------------------------------------------
# The Supervisor answers /core/start only once Core is running, or with an
# error if it failed to come up. (v0.1.x polled /core/api/ instead, which
# needs `homeassistant_api: true`; without it every poll was a 401, the loop
# ran out, and the backup was left behind on every box.)
bashio::log.info "Starting Home Assistant Core."
if supervisor_post /core/start 900; then
    rm -f "${BACKUP}"
    bashio::log.info "Core is up; removed $(basename "${BACKUP}")."
else
    # Keep the pre-edit store (no token in it) so a person can restore it.
    bashio::exit.nok "Core did not start after the edit; $(basename "${BACKUP}") kept for recovery."
fi
bashio::log.info "Done. Uninstall this add-on; it has nothing left to do."
