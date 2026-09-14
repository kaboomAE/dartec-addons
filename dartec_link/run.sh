#!/usr/bin/with-contenv bashio
# Join this home to the Dartec mesh.
#
# The whole reason this add-on exists rather than the official Tailscale one:
# the official add-on offers `login_server` but no way to pass an auth key, so
# enrolment means a person opening a login URL in every house. The manager
# provisions homes remotely over the agent's WebSocket, so it needs a key it
# can hand over unattended. Everything else here is deliberately boring.
set -euo pipefail

LOGIN_SERVER="$(bashio::config 'login_server')"
AUTH_KEY="$(bashio::config 'auth_key')"
HOSTNAME="$(bashio::config 'hostname')"
ACCEPT_DNS="$(bashio::config 'accept_dns')"

if bashio::var.is_empty "${LOGIN_SERVER}"; then
    bashio::exit.nok "login_server is not set. This add-on is configured by the \
Dartec manager; it is not meant to be filled in by hand."
fi

# State on the add-on's persistent volume, so a restart rejoins as the SAME
# node. Without this the node identity is regenerated every boot, the
# single-use key is already spent, and the house arrives as an unknown machine
# that nobody approved.
STATE_DIR="/data/tailscale"
mkdir -p "${STATE_DIR}"

if bashio::var.is_empty "${HOSTNAME}"; then
    HOSTNAME="$(bashio::info.hostname || echo 'dartec-home')"
fi

bashio::log.info "Starting tailscaled (control plane: ${LOGIN_SERVER})"

# userspace-networking is NOT used: we want a real interface so the rest of
# the house can be reached through this node later if we ever advertise
# routes. That is also why the container needs NET_ADMIN and /dev/net/tun.
tailscaled \
    --state="${STATE_DIR}/tailscaled.state" \
    --socket=/var/run/tailscale/tailscaled.sock \
    --port=41641 &
TAILSCALED_PID=$!

# Hand the signal on rather than dying and leaving a half-configured
# interface; the Supervisor stops add-ons with SIGTERM.
trap 'bashio::log.info "Stopping tailscaled"; kill -TERM ${TAILSCALED_PID} 2>/dev/null || true' \
    SIGTERM SIGINT

for _ in $(seq 1 30); do
    if tailscale --socket=/var/run/tailscale/tailscaled.sock status >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

UP_ARGS=(
    --login-server="${LOGIN_SERVER}"
    --hostname="${HOSTNAME}"
    --accept-routes=false
)

# Home Assistant resolves names for the whole house; letting the mesh take
# over DNS is a good way to break local integrations that expect the LAN's
# resolver. Off unless someone deliberately turns it on.
if bashio::var.true "${ACCEPT_DNS}"; then
    UP_ARGS+=(--accept-dns=true)
else
    UP_ARGS+=(--accept-dns=false)
fi

if bashio::config.has_value 'advertise_routes'; then
    ROUTES="$(bashio::config 'advertise_routes | join(",")')"
    if ! bashio::var.is_empty "${ROUTES}"; then
        UP_ARGS+=(--advertise-routes="${ROUTES}")
        bashio::log.info "Advertising routes: ${ROUTES}"
    fi
fi

# Only pass the key when there is one. On a restart the node is already
# registered and the key is spent, so passing it again would fail the start
# for no reason.
if bashio::var.is_empty "${AUTH_KEY}"; then
    bashio::log.info "No auth key set -- assuming this node is already registered"
else
    UP_ARGS+=(--authkey="${AUTH_KEY}")
fi

bashio::log.info "Bringing up the mesh interface as '${HOSTNAME}'"
if ! tailscale --socket=/var/run/tailscale/tailscaled.sock up "${UP_ARGS[@]}"; then
    bashio::log.error "Could not join the mesh. If the key was already used, \
ask the manager to re-provision this home."
    kill -TERM "${TAILSCALED_PID}" 2>/dev/null || true
    exit 1
fi

bashio::log.info "Connected. Addresses: $(tailscale --socket=/var/run/tailscale/tailscaled.sock ip -4 2>/dev/null | tr '\n' ' ')"

wait "${TAILSCALED_PID}"
