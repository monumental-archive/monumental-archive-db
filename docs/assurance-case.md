# Security assurance case

Why this project's security requirements are met: the threat model, the
trust boundaries, the design argument, and the argument that common
implementation weaknesses are countered. The security requirements
themselves — what a user can and cannot expect — are stated in the
organisation's
[SECURITY.md](https://github.com/monumental-archive/.github/blob/main/SECURITY.md),
which is served to this repository as an org default; this document is
the evidence that they hold.

**State, 2026-08-21.** This repository joined `monumental-archive`
(`.github#670`) and its private toolchain was deleted with the import.
Enforcement — every linter, the secret scan, the workflow audit — is the
organisation's shared gate over the organisation's toolbelt, and the
publish machinery is the org's continuous archetype, called from
`.github/workflows/continuous.yml`. That stub landed with the base-image
repin onto the org-path `edtf-postgres` image, and **between the import
and that pull request this repository published nothing** — no merge
publish and no weekly rebuild. The gap is stated plainly rather than
smoothed over: an assurance case that claims a control ran when it did
not is the defect it exists to prevent. Everything below that describes
the publish path describes the archetype this repository calls.

The unusual thing about this project is that it contains no application
code. It is an *assembly*: a Dockerfile, three extension pins, and a
pipeline that proves what it publishes. So the entire attack surface worth
arguing about is the supply chain, and this document spends its length
there rather than on input handling that does not exist here.

## Threat model

In rough order of exposure.

**Supply-chain substitution — the primary threat.** A consumer runs
whatever bytes they pull. An attacker who can change what `docker pull`
returns, or what our build ingests, owns every database built from it.
Four distinct substitution points:

1. *The base image.* `postgres:18-trixie` is a mutable tag; whoever
   controls that tag controls our base.
2. *The extension build stage.* `edtf-postgres` is published by a related
   but separate repository, with its own compromise surface.
3. *The apt layer.* PostGIS and pgaudit come from PGDG at our build time.
4. *The published manifest.* An attacker with registry write could push a
   different image under our tag.

**CI compromise.** The publish path can push to GHCR, and somewhere in
the organisation a Sigstore OIDC identity is held. A workflow that can be
induced to build something other than the reviewed tree, or to sign
something it did not prove, is equivalent to registry compromise — and
*more* dangerous, because the result would carry a valid signature. The
org's answer is the split: the job that runs this repository's tree can
push, and the job that mints the identity is in a different repository
and runs no caller-supplied code, so the two capabilities never meet.

**Known-vulnerable OS packages.** PostGIS drags in the GDAL stack, and
with it libraries (libexpat1, libnss3) with a steady CVE cadence. This is
not a hypothetical: the decision record
([0001](decisions/0001-own-the-installation.md)) exists because
`postgis/postgis` once froze exactly those two packages at versions
carrying 22 CVEs that no rebuild of ours could refresh.

**Configuration that misleads a consumer.** The image bakes
`shared_preload_libraries` and `wal_level=logical` into `CMD`. If a
consumer believes pgaudit is loaded and it is not, they lose their audit
trail without any error — a silent failure of a security control.

### Explicitly out of scope

- **What the consumer does with the database.** Network exposure,
  `POSTGRES_PASSWORD` handling, TLS termination, volume permissions, and
  role design are deployment decisions. The image ships no credentials and
  publishes no ports by itself.
- **Vulnerabilities in PostgreSQL, PostGIS, pgaudit, or Debian.** In scope
  is *failing to ship the fix*; the defect itself belongs upstream.
- **Volume denial of service.** A database can be overwhelmed by load;
  nothing in an image can prevent that.
- **Confidentiality of the image contents.** Everything here is public by
  construction. There is nothing secret in the image, and the build
  deliberately embeds its full non-secret input set in the provenance
  attestation.

## Trust boundaries

- **The publish boundary — what CI builds versus what a consumer pulls.**
  This is the boundary that matters most, and the pipeline is arranged so
  that nothing is trusted across it without re-proof: build → smoke →
  push → **pull the published bytes back by digest and prove them again**
  → sign → verify the signature the way a stranger would. The signature
  therefore asserts something demonstrated *of the bytes a consumer gets*,
  not of a local twin that was never published.
- **The build-stage boundary.** `edtf-postgres` is a separate trust domain.
  It is crossed by exactly two `COPY --from` globs
  ([Dockerfile:98-99](../Dockerfile#L98-L99)) — the `.so` and the
  `edtf_postgres*` control/SQL files — rather than by `FROM`, and
  deliberately not by copying the extension directory wholesale, so
  nothing else that stage ever holds can displace this base's control
  files. The narrow glob is the boundary enforcement.
- **The apt boundary.** PGDG and Debian archives are trusted for package
  contents, authenticated by apt's own repository signing, and pinned to
  exact versions under the Renovate convention.
- **The privilege boundary inside the image.** The server runs as `USER
  postgres`; there is no root phase and no setuid path to one, because
  `gosu` — whose only purpose is root→postgres descent — is deleted.
- **The registry identity boundary.** Consumers distinguish our images
  from anyone else's by verifying the signature and the build provenance
  the org signer minted for that digest, not by the tag. The identity
  moved at the import — images published before the transfer were signed
  by this repository's own publish workflow, which is a different
  publisher and is recorded as such in the README.

## Secure design principles

- **Economy of mechanism.** The deliverable is ~95 lines of Dockerfile and
  a smoke script. There is no application code, no init scripts, no
  entrypoint of our own, no seed data. Most classes of defect are absent
  because the code that would contain them was never written.
- **Fail-safe defaults.** Every trust decision is fail-closed by
  construction rather than by checking. Both `FROM`s are digest-pinned, and
  BuildKit refuses to proceed on mismatch — a substituted base does not
  produce a warning, it produces a failed build. The apt versions are exact
  pins, so a missing version fails the install rather than silently
  resolving to something newer. The image starts non-root by default, and
  cannot be talked into root because the tool for it is gone.
- **Complete mediation.** There is exactly one path by which an image is
  produced and exactly one identity that can sign one — and that identity
  lives in a repository of its own, the org signer, which holds
  `id-token: write` and runs no caller-supplied code. No manual publish
  path exists, `mise run ci` in a shell and the shared gate run the same
  tasks from the same lockfile in the same order, and every signing path
  builds cold: a cache is an unattested build input, so the org's
  attested paths carry none.
- **Defence in depth on the extension pin — currently single, not
  doubled.** The digest proves the bytes did not change; an attestation
  over that same digest would prove they are the *right* bytes. Neither
  alone suffices: a digest pins whatever it was first set to, including
  something wrong; an attestation without a digest pin does not say which
  bytes ship. This repository's own attestation gate was deleted at the
  import because a hand-rolled verifier beside the canonical one is a
  second derivation, and the canon's base-approval walk is pgrx-scoped
  and does not reach a first-party base in a sibling repository. That gap
  is filed as `.github#715` and is named here rather than papered over:
  until it lands, this leg of the argument rests on the digest pin and on
  the publisher being the same organisation.
- **Least privilege.** Workflows default to `contents: read`, with
  additional scopes granted per job and stated rather than inherited (a
  nested `uses:` job takes its own file's default, never the caller's
  grant). `id-token: write` is not held by any workflow here at all: the
  organisation's capability boundary puts it in the signer repository,
  which runs no caller-supplied code, so a build job that executes this
  repository's tree can never mint an identity. Runner hardening was
  retracted org-wide and is deliberately absent rather than missing. No
  long-lived registry or signing credential exists to leak — GHCR uses
  the run's own token and signing is keyless.

## Common implementation weaknesses, countered

| Weakness class | Countermeasure | Evidence |
| --- | --- | --- |
| Memory safety, injection, logic defects in our own code | There is no application code. The only executable content authored here is one shell script, which handles no untrusted input. | [Dockerfile](../Dockerfile), [scripts/](../scripts/) |
| Known-vulnerable OS packages | Own the installation, then rebuild on a clock: a weekly cache-free rebuild re-resolves the unpinnable layer from `trixie-security`, capping exposure at seven days. | [0001](decisions/0001-own-the-installation.md), the continuous archetype's schedule leg (wired at [#5](https://github.com/monumental-archive/monumental-archive-db/issues/5)) |
| Known-vulnerable dependencies, undetected | Decided at the publish path's commit point, never in the gate: an advisory in the artifact's SBOM blocks the publish until it carries a signed decision, and the published digest's package-CVE state is on every run log. A gate that fails on a CVE published overnight fails unrelated pull requests, so vulnerability scanning is deliberately out of it. | the org's dependency track; the canon's `lint:trivy` (misconfig + secrets only) |
| Dependency drift and stale pins | Renovate under the org preset, with the pin convention enforced by the `ARG *_VERSION=` + `# renovate:` pairing so a pin cannot silently lose coverage. | [renovate.json](../renovate.json) |
| Supply-chain substitution | Digest pinning on both `FROM`s (fail-closed in BuildKit) and keyless signing of the published index under the org signer's identity. The attestation gate over the extension base is the open leg — `.github#715`. | Dockerfile |
| Publishing something that was never proved | The publish invariant, now the org's shared one: build and smoke before any push; after the index exists, pull it back by digest and re-prove; sign last and only on proof. | the org's `continuous.yml` → `build-oci-image.yml` → `assemble-oci-index.yml` → signer |
| A signature that succeeds but does not verify | Signing is the org signer's, and the org verifies its own output as a stranger would rather than trusting a step's exit code. | the signer repository, and the org's verification path |
| Silent loss of a security control | The smoke test asserts against `pg_get_loaded_modules()`, not `\dx`. `\dx` reports what is *installable*; only the former proves pgaudit is actually loaded. | [scripts/db-image-smoke.sh](../scripts/db-image-smoke.sh) |
| Vulnerable or malformed CI workflows | actionlint and zizmor from the belt on every commit and in the shared gate, plus the belt's structural workflow lints (SHA-pinned `uses:`, stated nested permissions, no cache on an attested path, the capability boundary); the online audits run on the Monday cron. SAST is the org security configuration's default CodeQL setup, not a workflow here. | `mise run ci`, `.github/workflows/audit.yml` |
| Unpinned CI actions | Every `uses:` is pinned to a full commit SHA with the version in a trailing comment. | `.github/workflows/` |
| Credential leakage | gitleaks over tracked files in the gate; `persist-credentials: false` on every checkout; no long-lived publishing secret exists. | `mise run lint:gitleaks` |
| Dockerfile antipatterns | hadolint from the belt in the gate, at the org's configuration rather than a repo-local copy of it. | `mise run lint:hadolint` |

## Why this is believed sufficient

The residual risks, named honestly:

- **A compromise of the `edtf-postgres` publishing repository** would
  produce a correctly-attested malicious extension, and both of our gates
  would pass. This is a real transitive trust relationship, mitigated only
  by that repository running the same hardening as this one and by the
  narrowness of what crosses the boundary — two globbed paths, not a base
  image. It is the strongest argument for keeping that boundary a `COPY`
  and never a `FROM`.
- **A seven-day window on OS-layer CVEs.** The weekly rebuild is a
  deliberate trade: a daily rebuild would republish digests faster than
  consumers could reasonably track, and a rebuild triggered by advisory
  feeds would make the publish path depend on a scanner having a good day.
  Seven days is the stated commitment, not an accident, and any consumer
  needing tighter can rebuild from this repository themselves.
- **Three Scorecard checks and the Best Practices gold badge are
  structurally unreachable** for a single maintainer: Code-Review,
  Contributors, and non-author review. These are head-count facts, not
  hygiene gaps. The mitigation is the organisation's
  [governance](https://github.com/monumental-archive/.github/blob/main/GOVERNANCE.md)
  rather than a pretence that a second reviewer exists.

Both residual risks fail toward *detectability* rather than silence, which
is the property the design is actually organised around. A substituted
base fails the build rather than shipping. A wrong extension digest fails
the build. A signature over unproved bytes cannot be produced, because
signing happens after the re-proof step and nowhere else. An unloaded
pgaudit fails the smoke test rather than producing a database that quietly
audits nothing. The one thing this design consciously accepts — a
vulnerable OS package during the rebuild window — is public in the
package-CVE report of every publish run, rather than hidden.
