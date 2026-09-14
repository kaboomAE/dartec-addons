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

## Images are prebuilt — and the packages must be PUBLIC

`.github/workflows/build.yml` builds one image per architecture and pushes it
to ghcr on every change to `dartec_link/`. Installing is a pull, not a build:
seconds, and no compiler, package index or network fetch between a customer
and a working add-on.

Verified pullable anonymously, which is what a customer's Supervisor does:

```
ghcr.io/kaboomae/dartec-addons/{aarch64,amd64,armv7}-dartec-link:<version>
```

> ghcr packages can be private even when their repository is public, and a
> private one fails in a home with an authentication error that says nothing
> about the real cause. These published public, so nothing needs doing — but
> if a future arch or rename ever fails to pull, check that first, and check
> it by fetching the manifest **without credentials** rather than by looking
> at the package page while signed in.

**The image tag is `version:` from `config.yaml`.** Bumping the version without
publishing that tag is a failed install in someone's house, so the workflow
reads the version out of that file rather than having it typed twice.

This replaced building on the home, which was the original arrangement and a
bad trade: a build on a small box is slow enough to look like a hang, and it
fails in ways nobody can see from here.

Both the Tailscale version and the Home Assistant base images are pinned, and
the Tailscale tarball is verified against its published SHA256 before it is
installed — this binary runs with `NET_ADMIN` in someone's home, so an
unverified download is not acceptable.

## Licence

MIT — see [LICENSE](LICENSE).
