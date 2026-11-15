#!/usr/bin/env bash
# Smoke-test a built database image before it is published.
# Usage: scripts/db-image-smoke.sh <image-ref>
#
# A build succeeding is not the same as an extension loading, so every
# assertion here is about the running server rather than the build log:
# modules are checked with pg_get_loaded_modules() (what the backend
# actually mapped) rather than \dx (what the catalogue merely lists).
#
# This runs on the native runner for the architecture that just built the
# image — a green leg on one architecture proves nothing about the other.
set -euo pipefail

image=${1:?usage: db-image-smoke.sh <image-ref>}
container="db-smoke-$$"

cleanup() {
  docker rm -f "${container}" > /dev/null 2>&1 || true
}
rc=0
trap 'rc=$?; cleanup; [[ -n ${org_done:-} || ${rc} -ne 0 ]] || rc=1; exit "${rc}"' EXIT

docker run -d --name "${container}" -e POSTGRES_PASSWORD=smoke "${image}" > /dev/null

# The official entrypoint starts postgres TWICE on a fresh volume (a
# temporary init server, then the real one); pg_isready alone can catch
# the temporary one and the next psql lands in the restart gap. Require
# the second "ready to accept connections" in the log, then pg_isready.
ready=false
for _ in $(seq 1 60); do
  starts=$(docker logs "${container}" 2>&1 \
    | grep -c 'database system is ready to accept connections' || true)
  if [[ ${starts} -ge 2 ]] \
    && docker exec "${container}" pg_isready -U postgres > /dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [[ ${ready} != true ]]; then
  echo "db-smoke: server never became ready" >&2
  docker logs "${container}" >&2
  exit 1
fi

q() {
  docker exec "${container}" psql -U postgres -tAX -c "$1"
}

fail=0
assert() {
  # $1 = description, $2 = expected, $3 = actual
  if [[ $2 == "$3" ]]; then
    echo "db-smoke: ok — $1"
  else
    echo "db-smoke: FAIL — $1 (expected '$2', got '$3')" >&2
    fail=1
  fi
}

# Non-root. The image sets USER 999 (the postgres user, by uid); a root
# server would mean the official entrypoint took its privileged path
# after all.
uid=$(docker exec "${container}" id -u)
if [[ ${uid} -eq 0 ]]; then
  echo "db-smoke: FAIL — server runs as root" >&2
  fail=1
else
  echo "db-smoke: ok — runs as non-root (uid ${uid})"
fi

# wal_level must survive into the running server, not just the CMD line:
# the consuming archive's read path is logical replication.
wal=$(q 'show wal_level')
assert "wal_level is logical" "logical" "${wal}"

# Shared-preloaded modules are mapped at startup; if the preload list were
# wrong the server would still boot happily without them.
loaded=$(q "select string_agg(module_name, ',' order by module_name) from pg_get_loaded_modules()")
for module in pgaudit pg_stat_statements; do
  case ",${loaded}," in
    *",${module},"*) echo "db-smoke: ok — ${module} loaded" ;;
    *)
      echo "db-smoke: FAIL — ${module} not loaded (got '${loaded}')" >&2
      fail=1
      ;;
  esac
done

docker exec "${container}" psql -U postgres -qX -v ON_ERROR_STOP=1 \
  -c 'CREATE EXTENSION postgis' \
  -c 'CREATE EXTENSION pgaudit' \
  -c 'CREATE EXTENSION pg_stat_statements' \
  -c 'CREATE EXTENSION edtf_postgres' > /dev/null

# The .so genuinely mapped, not merely registered in pg_extension: these
# calls execute extension code.
postgis_ok=$(q "select st_area(st_buffer(st_point(0, 0), 1)) > 3")
assert "postgis executes" "t" "${postgis_ok}"

edtf_ok=$(q "select edtf_valid('1984-06?')")
assert "edtf validates" "t" "${edtf_ok}"

edtf_bounds=$(q "select edtf_min('198X') || '|' || edtf_max('198X')")
assert "edtf bounds are correct" "1980-01-01|1989-12-31" "${edtf_bounds}"

# The extension version must be the one the Dockerfile pins, or the image
# silently shipped something else. Read from the tag of the edtf build
# stage (`:<version>-pg<major>@sha256:...`) — the digest beside it is what
# actually fixes the bytes, so this reads the human-facing half of the same
# pin and would catch a tag and digest that disagree.
expected_edtf=$(sed -n \
  's|^FROM ghcr\.io/carlallenn/edtf-postgres:\(.*\)-pg[0-9]*@sha256:.* AS edtf$|\1|p' \
  Dockerfile | head -1)
if [[ -z ${expected_edtf} ]]; then
  echo "db-smoke: no version in the edtf stage's tag in Dockerfile" >&2
  exit 1
fi
actual_edtf=$(q "select extversion from pg_extension where extname = 'edtf_postgres'")
assert "edtf_postgres version is the pinned one" "${expected_edtf}" "${actual_edtf}"

if [[ ${fail} -ne 0 ]]; then
  exit 1
fi
echo "db-smoke: ${image} passed every assertion"
org_done=1
