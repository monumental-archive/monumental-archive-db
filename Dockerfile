# The Monumental Archive's database image: official Postgres plus audited
# extensions (PostGIS, pgaudit, edtf_postgres). Renovate manages the FROM
# digest. Base is Debian 13 (trixie).
#
# Why the official postgres image rather than postgis/postgis: PostGIS is
# installed HERE, at our build time, so its dependencies resolve fresh from
# trixie-security on every uncached build. postgis/postgis bakes them in at
# ITS build time — which once froze libexpat1 and libnss3 at versions
# carrying 22 CVEs no rebuild of ours could ever refresh, because the
# packages were not ours to refresh. A package you did not install is a
# package you cannot refresh (docs/decisions/0001-own-the-installation.md).
# The official image is also genuinely multi-arch; postgis/postgis
# publishes amd64 only.

FROM postgres:18-trixie@sha256:4ef4dbc939d61acea57712655ddb4b4ab27419c913f94cca0cd57cb3ea3c2280 AS base

# --- edtf-postgres: prebuilt, attested, digest-pinned ----------------------
# EDTF validation as a native extension: the same edtf-core the archive's
# web app runs via WASM, so the two layers can never diverge. Consumed as
# the publisher's OCI image rather than compiled here — the image compiles
# nothing, which is what makes a native arm64 build cheap.
#
# A BUILD STAGE, never our base. This image IS postgres:18-trixie with the
# extension installed, so taking it as a base would put the OS packages
# that carry CVEs in a layer frozen at edtf's build time and refreshable
# only by an edtf release — the exact failure
# docs/decisions/0001-own-the-installation.md was written about. Copying
# two paths out of a stage receives none of that image's base layers, so
# the apt layer below stays ours to refresh on the weekly rebuild.
#
# Pinned by manifest-INDEX digest, which commits to both the amd64 and the
# arm64 manifest: one pin fixes the bytes for both architectures whichever
# one is being built, so the "a wrong pin is caught even for the platform
# this build is not producing" property the two per-arch tarball checksums
# used to provide now holds by construction. BuildKit is fail-closed on
# mismatch, and Renovate's native Dockerfile manager bumps tag and digest
# together — the checksums this replaced had to be hand-edited.
# The digest proves the bytes did not change; proving they are the RIGHT
# bytes — an attestation over this exact digest naming edtf's publish
# workflow at the ref that could legitimately have minted it — is the
# canon's base-approval machinery, not this repository's. The hand-rolled
# gate that used to do it here was deleted at the import (.github#670): a
# second derivation beside the canonical one passes its own exam. The
# canon's approval walk is pgrx-scoped today and does not reach a
# first-party base in a sibling repo, which is filed as .github#715 and is
# the gate this line answers to once it lands.
#
# THIS REF IS THE ONE KNOWN LEFTOVER OF THE IMPORT (2026-08-21). It still
# names the pre-transfer publisher because an image published before the
# transfer cannot carry an org-identity attestation at all; it is repinned
# to ghcr.io/monumental-archive/edtf-postgres, at the digest of edtf's
# first org-path release, in this repo's follow-up PR (#5, .github#669).
FROM ghcr.io/carlallenn/edtf-postgres:1.2.3-pg18@sha256:4ee81e447e122deeb6c7361ad48d33a518a630d116318e6816f286b06c33b0e8 AS edtf

# --- runtime ---------------------------------------------------------------
FROM base

# PostGIS and pgaudit from PGDG (the repo ships in the base image). PostGIS
# drags in the GDAL stack, and with it libexpat1 and libnss3 — absent from
# the base, installed here, resolved from trixie-security at build time.
#
# ARG, not a bare version in the apt line: Renovate's regex manager matches
# `# renovate:` comments above `ARG *_VERSION=` and nothing else, so a pin
# written inline would be tracked by nothing. PostGIS is the most important
# package in the image; its version must never lose Renovate coverage.
#
# depName and packageName are both stated, and they differ on purpose:
# packageName is what the deb datasource looks up, depName is the display
# name the org's commit-subject template interpolates. The full package
# name mints an 81-column subject, nine past the org ceiling, and a
# machine-minted subject cannot be shortened after the fact — so the
# short name is declared here, where the pin is (renovate.json).
# renovate: datasource=deb depName=postgis packageName=postgresql-18-postgis-3
ARG POSTGIS_VERSION=3.6.4+dfsg-2.pgdg13+1
# renovate: datasource=deb depName=pgaudit packageName=postgresql-18-pgaudit
ARG PGAUDIT_VERSION=18.0-3.pgdg13+1
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    "postgresql-18-postgis-3=${POSTGIS_VERSION}" \
    "postgresql-18-pgaudit=${PGAUDIT_VERSION}" \
  && rm -rf /var/lib/apt/lists/*

# Only the extension itself crosses the stage boundary. Globbed rather than
# copying /usr/share/postgresql/18/extension/ wholesale (the form upstream's
# README suggests): that directory in the edtf image also holds the control
# files of ITS base image, and copying it whole would silently replace this
# base's copies with those — inheriting files we did not install, by the
# back door, in the one stage that exists to avoid exactly that.
COPY --from=edtf /usr/lib/postgresql/18/lib/edtf_postgres.so /usr/lib/postgresql/18/lib/
COPY --from=edtf /usr/share/postgresql/18/extension/edtf_postgres* /usr/share/postgresql/18/extension/

# gosu exists to drop root→postgres; this image starts as postgres (USER
# below), so it's dead code — and it ships with stale-Go-stdlib CVEs. Gone.
# The initdb.d directory is emptied because the consuming archive is
# migration-defined: extensions are created by its schema tooling, never by
# container init.
RUN rm -f /docker-entrypoint-initdb.d/* /usr/local/bin/gosu

# Preloads baked into the image so every consumer (compose stacks, schema
# tooling's throwaway dev containers, production) behaves identically:
# pgaudit and pg_stat_statements require shared preload.
# wal_level=logical: the archive's live read path is logical replication
# (ElectricSQL); baked here so every consumer matches production exactly.
CMD ["postgres", \
  "-c", "shared_preload_libraries=pg_stat_statements,pgaudit", \
  "-c", "wal_level=logical"]

# Non-root by default; the official entrypoint supports starting as the
# postgres user directly (it skips its root-phase chown dance).
#
# NUMERIC, not `postgres`: an orchestrator enforcing runAsNonRoot cannot
# verify a named user and refuses to start the pod, which is what
# hadolint DL3066 is about — the belt runs hadolint at its maximum and
# this repo takes the fix rather than an exception. 999 is not a guess:
# `docker run --entrypoint id <the pinned base digest> postgres` reads
# uid=999(postgres) gid=999(postgres) groups=999(postgres),101(ssl-cert),
# and starting the image by uid rather than by name was measured to
# produce the identical group set, ssl-cert included (2026-08-21). The
# coupling to the base's assignment is real and is bounded by the smoke
# test: a uid that upstream moved would fail to start the server, and
# nothing publishes without booting first.
USER 999

HEALTHCHECK --interval=5s --timeout=3s --retries=10 \
  CMD ["pg_isready", "-U", "postgres"]
