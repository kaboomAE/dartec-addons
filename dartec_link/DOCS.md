# Dartec Link

Connects this home to Dartec over an encrypted private network (WireGuard, via
Tailscale), so Dartec can reach it for support **without the home being
published to the internet**.

Nothing here is meant to be filled in by hand. The Dartec manager configures
and starts this add-on remotely when a home is set up.

## What it replaces

Previously each home was given its own public address, pointed at the house
through a Cloudflare tunnel. That works, but it means a Home Assistant login
page facing the open internet, protected only by the household's own password
— and in the UAE it was also slow, because free-plan Cloudflare zones are
routed through Amsterdam or Hong Kong rather than Dubai (431 ms typical,
1.9 s at the 95th percentile, measured).

On the mesh there is no public address at all. Nothing to find, nothing to
scan, and the connection is direct rather than crossing a continent twice.

## Options

| Option | What it does |
|---|---|
| `login_server` | The Dartec control plane. Set by the manager; required. |
| `auth_key` | Single-use enrolment key, valid one hour. Masked in the UI. |
| `hostname` | The name this home appears as. Defaults to the HA hostname. |
| `accept_dns` | Off by default — see below. |
| `advertise_routes` | Reach other devices on the house LAN through this node. Off by default. |

### Why `accept_dns` defaults to off

Home Assistant resolves names for the whole house. Letting the mesh take over
DNS is a reliable way to break local integrations that expect the LAN's own
resolver, and the symptom — some devices stop being discovered — looks nothing
like a networking change. Turn it on only if something specifically needs it.

### Why the node is not ephemeral

An ephemeral node is deleted from the network when it goes offline. For a
house, "offline" usually means a power cut, and the home would silently drop
off and need re-provisioning to come back. So it persists, and access is
revoked explicitly by removing it from the manager instead.

## Restarts

Node identity is stored on the add-on's persistent volume, so a restart
rejoins as the same node. The single-use auth key is already spent by then and
is not sent again — that is expected, not an error.

If the log says the key was already used **and** the node is not registered,
the state volume was lost. Ask the manager to re-provision this home; it mints
a fresh key.

## Troubleshooting

**"Could not join the mesh"** — the key expired (they last one hour) or was
already used. Re-provision from the manager.

**Installed but the manager still shows the home as offline** — check that the
add-on is actually started, then look at its log for the address it was given.
No address means it never completed enrolment.
