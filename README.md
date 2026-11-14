# monumental-archive-db

<!-- badges:begin -->
[![ci](https://github.com/monumental-archive/monumental-archive-db/actions/workflows/ci.yml/badge.svg)](https://github.com/monumental-archive/monumental-archive-db/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/monumental-archive/monumental-archive-db/badge)](https://scorecard.dev/viewer/?uri=github.com/monumental-archive/monumental-archive-db)
[![SLSA source](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fmonumental-archive%2Fmonumental-archive-db%2Flevels%2Fmonumental-archive-db%2Fsource.shield.json)](https://raw.githubusercontent.com/monumental-archive/monumental-archive-db/levels/monumental-archive-db/source.report.json)
[![SLSA build](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fmonumental-archive%2Fmonumental-archive-db%2Flevels%2Fmonumental-archive-db%2Fbuild.shield.json)](https://raw.githubusercontent.com/monumental-archive/monumental-archive-db/levels/monumental-archive-db/build.report.json)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/13998/badge)](https://www.bestpractices.dev/projects/13998)
[![OpenSSF Baseline](https://www.bestpractices.dev/projects/13998/baseline)](https://www.bestpractices.dev/projects/13998)
<!-- pending (human step): REUSE — register at https://api.reuse.software/register (no account: name, email, project URL, confirmation link), then set 'reuse registered' in .badge-states and re-run fix:badges -->
[![license](https://img.shields.io/badge/license-AGPL--3.0--only-blue)](LICENSES/)
[![fair-software](https://img.shields.io/badge/fair--software.eu-%E2%97%8F%20%E2%97%8F%20%E2%97%8B%20%E2%97%8B%20%E2%97%8F-orange)](https://fair-software.eu)
<!-- badges:end -->

The [Monumental Archive](https://github.com/monumental-archive)'s
PostgreSQL image: official `postgres:18` (Debian trixie) plus exactly
three audited extensions — [PostGIS](https://postgis.net/),
[pgaudit](https://github.com/pgaudit/pgaudit), and
[edtf_postgres](https://github.com/monumental-archive/edtf) (native EDTF
validation from the same `edtf-core` the archive's web layer runs as
WASM, so the two can never diverge).

## Where the image is published

**Publishing is paused.** This repository joined the organisation on
2026-08-21 and its own publish pipeline was deleted with the rest of the
private toolchain; the org's continuous archetype
(`.github/workflows/continuous.yml`, the shared workflow every org image
publishes through) is wired in the follow-up pull request that also
repins the extension base image
([#5](https://github.com/monumental-archive/monumental-archive-db/issues/5)).
Until then no new digest is published from this tree.

- **Published before the transfer:** `ghcr.io/carlallenn/monumental-archive-db`,
  signed keylessly by the pre-transfer publish workflow. Those digests
  still verify against the identity they were minted under, which is
  recorded verbatim below because it is not derivable from this tree any
  more.
- **After the continuous stub lands:**
  `ghcr.io/monumental-archive/monumental-archive-db`, `:latest` the
  stream tag, every digest signed by the org signer and carrying build
  provenance. Consumers pin the digest; the tag exists so Renovate has
  something to resolve digest updates against.

The transfer flips the workflow identity every signature is anchored to,
so a consumer pinning the old identity pattern must move to the new one
when they move to the new path — the two are different publishers and
that is the point of anchoring at all.

### Verifying a digest published before the transfer

```sh
cosign verify ghcr.io/carlallenn/monumental-archive-db@<digest> \
  --certificate-identity-regexp \
    '^https://github.com/CarlAllenn/monumental-archive-db/\.github/workflows/publish\.yml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## What the image asserts

- **Multi-architecture for real.** amd64 and arm64 are each built on
  native hardware — no QEMU, ever. A green build proves the image on the
  machine that will run it.
- **Tested before published.** Every architecture boots and proves its
  extensions actually load (`pg_get_loaded_modules()`, not `\dx`) before
  anything is pushed; after the manifest exists, the published bytes are
  pulled back by digest and proved again before signing.
- **Signed, with provenance.** The index is signed by the org signer —
  the one repository in the organisation that holds `id-token: write` and
  runs no caller-supplied code — and the digest carries build
  provenance, so what a stranger pulls can be traced to the build that
  produced it.
- **Rebuilt weekly, cache-free.** PostGIS's transitive OS dependencies
  can be pinned by nobody; a scheduled rebuild resolves them fresh from
  `trixie-security`, capping exposure on that layer at seven days with
  every deliberate pin intact. The reasoning is
  [docs/decisions/0001-own-the-installation.md](docs/decisions/0001-own-the-installation.md).

The first three describe the org's continuous archetype, which this
repository adopts at the follow-up PR above; the weekly rebuild is that
archetype's schedule leg.

## Tags

There are no version tags and no releases: this image has no version
surface of its own — its "version" is the postgres major plus three
extension pins, and its changes are pin bumps. That is what the
continuous archetype is for, and this repository is the org's first
member of it.

## Baked-in server configuration

`shared_preload_libraries=pg_stat_statements,pgaudit` and
`wal_level=logical` ride the image `CMD`, so every consumer — compose
stacks, throwaway schema-tooling containers, production — behaves
identically. `/docker-entrypoint-initdb.d` is emptied (the consuming
archive is migration-defined) and the server starts as the postgres
user directly — `USER 999`, numeric so an orchestrator enforcing
runAsNonRoot can verify it — with `gosu` removed as dead code.

## Development

The organisation's toolbelt is the whole toolchain: pinned versions,
per-platform checksums, one lockfile, delivered from
[monumental-archive/.github](https://github.com/monumental-archive/.github)
at the SHA `.github/workflows/ci.yml` pins. This repository carries no
linter configuration of its own — the belt passes each tool its config
at run time, so there is no second copy here to drift.

```bash
mise trust && mise install && mise run hooks:install   # once per clone
mise run ci                                            # the whole gate
```

`mise run ci` is exactly what the shared gate runs on a pull request:
same tools, same versions, same order, from the same lockfile.

Building the image is not part of the gate — the publish path builds it,
smoke-tests it, and signs what it published, so a gate build would prove
something about bytes nobody ships. To build and prove one by hand:

```bash
docker build --tag monumental-archive-db:candidate .
bash scripts/db-image-smoke.sh monumental-archive-db:candidate
```

Contributions are welcome. The contribution model, the security policy,
the code of conduct and the governance model are the organisation's and
are served from
[monumental-archive/.github](https://github.com/monumental-archive/.github)
— sign off your commits (DCO), there is no CLA. Beyond those, this
repository keeps its own [roadmap](docs/roadmap.md), the
[security assurance case](docs/assurance-case.md), the
[2026 security review](docs/security-review-2026.md) and its
[decision records](docs/decisions/).
