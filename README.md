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

### Dartec Bootstrap (installer only, hidden)

A one-shot add-on the Dartec provisioner uses while setting up a home: it
installs HACS and gives it its GitHub token, which HACS otherwise only accepts
through GitHub's interactive device flow. It stops Home Assistant Core, adds a
`hacs` config entry built from the shape of an existing entry, and starts Core
again. It is `stage: experimental`, so it does not show in the normal store
view, and the provisioner uninstalls it when setup is done.

It **refuses to do anything but clean up** unless the provisioner passes a
fresh `run_token` (`dartec1.<unix seconds>.<random>`, at most 30 minutes old,
never used before on this box). It wipes both of its options from the
Supervisor as soon as it has read them. Installing it by hand therefore never
stops anyone's Core.

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
to ghcr on every change to an add-on's directory. Installing is a pull, not a build:
seconds, and no compiler, package index or network fetch between a customer
and a working add-on.

Verified pullable anonymously, which is what a customer's Supervisor does:

```
ghcr.io/kaboomae/dartec-addons/{aarch64,amd64,armv7}-dartec-link:<version>
```

`dartec-bootstrap` (aarch64, amd64) is new: **its packages start private and
must be made public** after the first build, before any home can install it.

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

## Store images

Each add-on carries `icon.png` (128 x 128) and `logo.png` (250 x 100), the sizes
Home Assistant recommends. They are the Dartec mark and lockup on the brand's
cream ground, because the store shows them unchanged on both its light and dark
themes and has no dark variant to fall back on.

They are rendered, not drawn: the Dartec brand builder in the internal
onboarding repository (`scripts/brand/build-icons.mjs --addons=<this checkout>`)
produces all four from the brand's own SVGs. Regenerate them there rather than
editing them by hand.

The Supervisor reads these files from this repository, not from the image, so
changing them never rebuilds or re-pushes an image (see the change check in
`.github/workflows/build.yml`).

## Licence

MIT — see [LICENSE](LICENSE).
