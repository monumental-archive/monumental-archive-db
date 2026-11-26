# Roadmap

What this project intends to do — and deliberately not do — over roughly
the next year (written 2026-08-09; revised 2026-08-21 at the import into
`monumental-archive`). A roadmap is a statement of direction, not a
promise; when it changes, this file changes with it.

This repository is closer to "finished" than most. It publishes one image
with a deliberately fixed surface, so the honest roadmap is mostly about
*maintaining a guarantee*, not about growing features.

## Will do

- **Keep the remediation clock running.** The weekly cache-free rebuild is
  the product's central safety property: it caps exposure on the
  unpinnable OS layer at seven days
  ([0001](decisions/0001-own-the-installation.md)). Work that defends it —
  keeping the scheduled publish green and keeping every pin under Renovate
  coverage — takes priority over anything additive. Two mechanisms that
  used to be this repo's are the org's now: the rebuild schedule rides the
  continuous archetype, and vulnerability scanning is decided at the
  publish path's commit point rather than on pull requests (a new CVE must
  not fail an unrelated pull request; the canon's `lint:trivy` states the
  rule).
- **Track the postgres major.** The image moved to PostgreSQL 19 on
  2026-11-24 (#73), by hand rather than as a Renovate automerge, once
  PGDG carried PostGIS and pgaudit for it and `edtf_postgres` published a
  `-pg19` image. PostgreSQL 20 takes the same route under the same gate.
- **Finish the supply-chain scoring work.** The org's now, not this
  repo's: Scorecard runs from the canon's stub against a per-repo
  ratcheted floor in `security/scorecard-floors.txt`, REUSE compliance is
  machine-checked by the belt's `lint:reuse`, and the README badge block
  becomes a derivation rather than hand-written markup. Structurally
  unreachable checks are documented as such rather than chased.
- **Keep the docs honest about digests.** Every document here that names a
  digest or a version is a thing that can rot without failing anything.

## Will not do

Exclusions are use-case-gated rather than absolute — that keeps the
contribution door open without inviting scope creep.

- **No fourth extension speculatively.** The image is postgres plus
  PostGIS, pgaudit and `edtf_postgres` because the consuming archive needs
  exactly those three. A fourth stays out until a specific consumer needs
  it; a contribution backed by one is welcome, held to the same bar as the
  existing three — installed from a distribution we can refresh, pinned
  under the Renovate convention, and asserted in the smoke test.
  plpgsql_check's files came in on that bar (#86): a consumer's
  PL/pgSQL coverage needed them, and the image carries them without
  loading them.
- **No version tags, no releases.** This image has no version surface of
  its own; its "version" is the postgres major plus four extension pins.
  Consumers pin digests and Renovate resolves against the stream tag.
  Inventing releases so that a scoring check has something to read would
  be ceremony that makes the artifact worse. This is what the org's
  continuous archetype exists for, and this repository is its first
  member.
- **No application code, no migrations, no seed data.**
  `/docker-entrypoint-initdb.d` stays empty: the consuming archive is
  migration-defined, and an image that initialises schema is an image that
  fights its consumer's migration tool.
- **No QEMU builds, ever.** Emulated builds test the image on the wrong
  machine. If a new architecture cannot get a native runner, it does not
  ship.
- **No inheriting a prebuilt extension image as our base.** This is the
  standing decision in [0001](decisions/0001-own-the-installation.md), and
  it is the one exclusion that will look like a free simplification to
  every future reader: it would inherit an apt layer we cannot refresh, and
  the weekly rebuild would stop meaning anything.
- **No SBOM-scanning job or dependency-snapshot submission.** SBOMs are
  attached to what we publish; trivy already opens the actual artifact and
  matches against the same databases, so a snapshot pipeline is a second
  notification surface for a gap that is not open.
