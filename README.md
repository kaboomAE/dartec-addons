# Dartec Add-ons

Home Assistant add-ons for [Dartec](https://dartec.ae) smart homes.

## Installation

Add this repository to your Home Assistant add-on store:

**Settings → Add-ons → Add-on Store → ⋮ → Repositories**, then paste:

```
https://github.com/kaboomAE/dartec-addons
```

On a Dartec-managed home you do not need to do this by hand — the Dartec
agent adds the repository and installs the add-on when the home is set up.

## Add-ons

### Dartec Link

Connects a home to Dartec over an encrypted private network (WireGuard, via
[Tailscale](https://tailscale.com)) so it can be reached for support **without
being published to the internet**.

It replaces the previous arrangement, where each home was given its own public
hostname through a Cloudflare tunnel. That meant a Home Assistant login page
facing the open internet, protected only by the household's own password. On
the mesh there is no public address at all — nothing to scan, nothing to
brute-force.

See [dartec_link/DOCS.md](dartec_link/DOCS.md) for options and troubleshooting.

## Why this exists rather than the official Tailscale add-on

The excellent [`hassio-addons/app-tailscale`](https://github.com/hassio-addons/app-tailscale)
offers a `login_server` option for self-hosted control planes, but **no way to
pass an auth key** — enrolment means a person opening a login URL in each
house. Dartec provisions homes unattended, so it needs a key it can hand over
with nobody present.

That single missing field is the whole reason for this add-on. Everything else
here is a thin, boring wrapper around `tailscaled`. If you are not Dartec, you
almost certainly want the official add-on instead.

## Building

There is no published image: `config.yaml` has no `image:` key, so the
Supervisor builds the Dockerfile on the home's own hardware. Installing takes a
few minutes on a Raspberry Pi rather than seconds.

Both the Tailscale version and the Home Assistant base images are pinned, and
the Tailscale tarball is verified against its published SHA256 before it is
installed — this binary runs with `NET_ADMIN` in someone's home, so an
unverified download is not acceptable.

## Licence

MIT — see [LICENSE](LICENSE).
