# 0001 — Own the installation, and rebuild on a clock

Status: accepted. Inherited from the Monumental Archive's decision record
of 2026-08-01, restated here standalone when the image moved into its own
repository; this is the reasoning the Dockerfile is built on.

## Context

Twenty-two CVEs (21 × `libexpat1`, 1 × `libnss3`) once sat red on the
archive's image scan, with no change that could clear them. No newer
`postgis/postgis` digest existed, Renovate had nothing to bump, and
waivers are banned — correctly.

The reason was structural, not incidental. `postgis/postgis` installs
PostGIS at *its* build time, which is when those packages were baked in.
The consumer never installed them, so it could not refresh them; only the
publisher could, and they had stopped. Measured on native arm64:

| | libexpat1 | libnss3 |
| --- | --- | --- |
| `postgis/postgis:18-3.6` | `2.7.1-2` | `2:3.110-1+deb13u2` |
| `postgres:18-trixie` | absent | absent |
| installed by us, from `trixie-security` | `2.8.2-1~deb13u1` | `2:3.110-1+deb13u4` |

Same Debian. Same packages. The only difference is *who ran apt, and when*.

"Official sources only, everything pinned" was followed to the letter and
did not help, because it has nothing to say about who performs the
installation. That is the gap this record fills.

## Decision

**Prefer the upstream-official base and install what we need ourselves,
over a community image that bundles it.** The bundle is a convenience that
transfers the refresh obligation to someone with no obligation to us.

Three rules follow, and they are the reusable part:

1. **A package you did not install is a package you cannot refresh.** When
   choosing a base, ask which layer the security-relevant packages will be
   installed in. Prefer the arrangement where that layer is ours.
2. **Pins stay; the un-pinnable layer is bounded by time, not by
   floating.** Named packages are pinned exactly. Their transitive
   dependencies cannot be pinned by anyone — so exposure there is capped
   by a scheduled rebuild that runs weekly and carries no cache of any
   kind, which resolves them fresh from `trixie-security` with every
   deliberate pin intact. The mechanism moved at the 2026-08-21 import:
   the repo's own `publish.yml` is gone and the schedule is the org
   continuous archetype's, called from `.github/workflows/continuous.yml`.
   Under a community base a rebuild refreshed nothing; under this
   arrangement it is a real remediation.
3. **A digest proves the bytes did not change; an attestation proves they
   are the right bytes.** A digest alone is a fail-closed check on the
   wrong question: an edit changing the reference and its digest together
   satisfies it. The rule is unchanged by the import; its mechanism
   moved. This repo's own attestation gate was deleted on 2026-08-21
   because a hand-rolled verifier beside the canonical one is a second
   derivation (`.github#670`), and the canon's base-approval walk does
   not yet reach a first-party base in a sibling repository — filed as
   `.github#715`, which is what this rule now waits on.

Publishing follows from the same posture: each architecture is built on
its own hardware (no QEMU), boots and proves its extensions load before
anything is pushed, and the published manifest is pulled back by digest
and proved again before it is signed.

## Consequences

**Buys.** No publisher's neglect can strand a consumer behind a CVE in a
package installed here. The image is genuinely multi-arch, and it compiles
nothing — which is what makes a native arm64 build cheap enough to publish
weekly.

**Costs, honestly.** PostGIS upgrades are owned here: its version needs
its own Renovate manager and its own adjudication when a major lands. Two
apt pins to maintain. The weekly rebuild republishes a digest even when
nothing changed.

**Residual dependency, stated narrowly.** This still depends on Docker
Official Images rebuilding — but only for what the base itself bakes in;
the `libexpat1`/`libnss3` class is no longer in that set. Building from
bare `debian:trixie` instead would mean owning the official entrypoint's
initdb, `PGDATA`, password bootstrap, locale and signal handling —
including the root→postgres drop the image's non-root `USER` relies on.
That trade is not worth making.

**Revisit triggers.** Docker Official Images beginning to publish
signatures. A second database image appearing in this family, at which
point per-extension OCI images' fleet-shaped economics start to apply.

## Amendment, 2026-08-08

edtf-postgres began publishing an OCI image, and this image now consumes
that instead of the release tarball — rule 3's mechanism changed from a
pair of per-arch `ADD --checksum` hashes to one manifest-index digest, and
the wording above was updated to match. The decision itself is unchanged,
and the change is a test of it: that image is `postgres:18-trixie` with
the extension installed, so adopting it as a *base* would have reproduced
the `postgis/postgis` failure exactly — an apt layer resolved at someone
else's build time, refreshable only by their next release. It is consumed
as a build stage, two globbed paths wide, and the base stays ours.
