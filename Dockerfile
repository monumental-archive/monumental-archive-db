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

FROM postgres:18-trixie@sha256:2ea8630df176ad090ec92136dee850397c5af8781e4bcf2e4162593691c61bbc AS base

# --- edtf-postgres: prebuilt, attested, digest-pinned ----------------------
# EDTF validation as a native extension: the same edtf-core the archive's
# web app runs via WASM, so the two layers can never diverge. Consumed as
# the publisher's OCI image rather than compiled here — the image compiles
# nothing, which is what makes a native arm64 build cheap.
#
# A BUILD STAGE, never our base. This is edtf's `-artifact` image: FROM
# scratch, holding the extension's files and nothing else, in both the
# Debian layout the two COPY lines below read and the CNPG layout
# (/lib, /share/extension) this image does not use. It has no OS layer to
# inherit, and it stays a stage regardless: the runtime base is ours, so
# the apt layer below stays ours to refresh on the weekly rebuild
# (docs/decisions/0001-own-the-installation.md).
#
# Pinned by manifest-INDEX digest, which commits to both the amd64 and the
# arm64 manifest: one pin fixes the bytes for both architectures whichever
# one is being built, so the "a wrong pin is caught even for the platform
# this build is not producing" property the two per-arch tarball checksums
# used to provide now holds by construction. BuildKit is fail-closed on
# mismatch, and Renovate's native Dockerfile manager bumps tag and digest
# together — the checksums this replaced had to be hand-edited.
# The digest proves the bytes did not change; proving they are the RIGHT
# bytes — an attestation over this exact digest, signed by the org signer
# at the release tag the pinned version names — is the canon's
# base-approval machinery, not this repository's. The shared image build
# verifies every first-party FROM that way before it builds anything, and
# fails closed (.github#715); the hand-rolled gate that used to do it here
# was deleted at the import (.github#670), because a second derivation
# beside the canonical one passes its own exam. That check derives the
# release tag from this line's tag, so the tag must stay a version.
#
# The .so is compiled against one postgres minor and can need symbols an
# older minor lacks, which the `pg18` in the tag does not say. Measured
# 2026-11-15: 1.3.4 was built against 18.7 and fails to load on 18.6
# ("undefined symbol: heap_datum_check"), so this pin and the base digest
# above moved together. Nothing but the smoke test catches that — it
# loads the library in the server it ships with, before any push.
FROM ghcr.io/monumental-archive/edtf-postgres:1.3.4-pg18-artifact@sha256:6c6aa265a752e13330ab370e60eb4490b7883204a97c7dd6b546d0ea27fdc92a AS edtf

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
#
# The -scripts package is named and pinned to the SAME version, never left
# to apt: postgresql-18-postgis-3 depends on it unversioned, so apt
# resolves the newest one, and PostGIS refuses CREATE EXTENSION when the
# scripts are newer than the library. Measured 2026-11-15: library pinned
# at 3.6.4, scripts resolved to 3.7.0, "extension scripts version 3.7.0
# cannot use older library version 3.6.4". The two are built from one
# source package, so one ARG is the right number of pins.
# renovate: datasource=deb depName=postgis packageName=postgresql-18-postgis-3
ARG POSTGIS_VERSION=3.6.4+dfsg-2.pgdg13+1
# renovate: datasource=deb depName=pgaudit packageName=postgresql-18-pgaudit
ARG PGAUDIT_VERSION=18.0-3.pgdg13+1
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    "postgresql-18-postgis-3=${POSTGIS_VERSION}" \
    "postgresql-18-postgis-3-scripts=${POSTGIS_VERSION}" \
    "postgresql-18-pgaudit=${PGAUDIT_VERSION}" \
  && rm -rf /var/lib/apt/lists/*

# Only the extension itself crosses the stage boundary. Globbed rather than
# copying /usr/share/postgresql/18/extension/ wholesale: the artifact image
# holds only edtf's own files there today, but a glob keeps that true of
# this image whatever the stage later contains — a directory copied whole
# would replace this base's control files with whatever sat beside them.
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
