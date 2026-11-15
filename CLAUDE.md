# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## What this repo is

A single Docker image: official `postgres:18` (Debian trixie) plus
exactly three extensions — PostGIS, pgaudit, and edtf_postgres. There is
no application code; the deliverables are the [Dockerfile](Dockerfile),
the smoke test, and the supply-chain guarantees around them. It has no
version surface — no tags, no releases — which is why it is the org's
first member of the **continuous archetype**: the artifact's "version"
is its pin set, and a change is a pin bump.

This repository joined `monumental-archive` on 2026-08-21
(`.github#670`). The governance, the toolchain and the publish machinery
all live in
[monumental-archive/.github](https://github.com/monumental-archive/.github)
— the canon. Its docs are the authority; nothing here restates a rule
the canon owns.

## Commands

The org toolbelt is the whole toolchain, delivered from the canon at the
SHA `.github/workflows/ci.yml` pins.

- `mise trust && mise install && mise run hooks:install` — once per
  clone.
- `mise run ci` — the whole gate, identical locally and in CI (belt
  linters over tracked files, then whatever repo tasks exist; this repo
  defines none).
- `mise run fix` — the write-mode siblings the gate deliberately
  excludes.
- `docker build --tag monumental-archive-db:candidate .` then
  `bash scripts/db-image-smoke.sh monumental-archive-db:candidate` —
  build and prove an image by hand. Not gate work: the publish path
  builds, smokes and signs the bytes it published, so a gate build would
  prove something about bytes nobody ships.

Nothing is pinned or configured here that the belt already delivers.
`mise.toml` carries no tools and no tasks on purpose; if a task is ever
added it needs `[task_config] shell = "bash -euo pipefail -c"` beside it
(`.github#700`).

## Architecture / invariants

- **Own the installation**
  ([0001](docs/decisions/0001-own-the-installation.md)): PostGIS and
  pgaudit are installed here from PGDG at our build time — never
  inherited from an image like `postgis/postgis` — so their OS
  dependencies resolve fresh from `trixie-security`. A weekly cache-free
  scheduled rebuild caps exposure at seven days.
- **edtf_postgres supply chain**: consumed as an OCI image pinned by
  manifest-index digest (nothing is compiled in this image). That image
  is edtf's `-artifact` variant — `FROM scratch`, the extension's files
  only — and it is a **build stage only**: the runtime base stays ours,
  which is what "own the installation" above requires. The runtime
  stage globs `edtf_postgres*` out of the two extension paths rather
  than copying the extension directory wholesale, so none of its base
  files cross over. The digest is fail-closed in BuildKit. Proving the
  bytes are the *right* bytes — an attestation over that digest naming
  the org signer at the release tag — is the canon's base-approval
  machinery: the shared image build verifies every first-party `FROM`
  before building and fails closed (`.github#715`). The hand-rolled gate
  this repo used to carry was deleted at the import.
- **The edtf `FROM` line is read by two things besides BuildKit.** The
  shared build derives the release tag to verify against from its tag
  (`1.3.4-pg18-artifact` → `refs/tags/v1.3.4`), and
  `scripts/db-image-smoke.sh` parses the same line for the expected
  extension version. Keep the `<version>-pg<major>-artifact` shape.
- **Renovate pin convention**: apt versions live in `ARG *_VERSION=`
  lines with a `# renovate:` comment above them — an inline version in
  an apt line would silently lose Renovate coverage. Image pins need
  none of that: the native Dockerfile manager reads `FROM` lines and
  bumps tag and digest together. `renovate.json` extends the org preset
  by tag; the two rules it keeps are repo identity (this image's package
  names, and the postgres major decision), and Renovate merges them with
  the preset's rather than replacing them.
- **Baked server config**: `CMD` carries
  `shared_preload_libraries=pg_stat_statements,pgaudit` and
  `wal_level=logical` (ElectricSQL logical replication) so every
  consumer behaves identically. `/docker-entrypoint-initdb.d` is emptied
  (the consuming archive is migration-defined) and gosu is removed; the
  server starts directly as the postgres user, declared numerically
  (`USER 999`) so an orchestrator enforcing runAsNonRoot can verify it.
- **Multi-arch without QEMU**: amd64 and arm64 each build and smoke on
  native runners. That property belongs to the org's shared image build,
  which `.github/workflows/continuous.yml` calls.
- **Smoke-test trap**: the official entrypoint starts postgres twice on
  a fresh volume; the smoke script waits for the *second* "ready to
  accept connections" before asserting. Preserve that if touching
  `scripts/db-image-smoke.sh`.

## Enforcement layer

Git hooks come from the canon by remote (`lefthook.yml` pins a canon
tag): typos and actionlint at pre-commit, the commit canon and the DCO
sign-off at commit-msg, `mise run ci` at pre-push. Commits are
conventional, imperative, lowercase, 72 columns, signed off; the PR
title becomes the squash subject and is held to the same rules. Fixing
lint output is never optional — the belt runs at maximum enforcement and
the repo conforms to the tools, never the reverse. Personal overrides go
in `lefthook-local.yml` (gitignored).
