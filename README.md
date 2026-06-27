# mem0-container

Automatically rebuilds and publishes [mem0](https://github.com/mem0ai/mem0)'s
official **server** and **dashboard** Docker images to the GitHub Container
Registry every time mem0 ships a new Python SDK release.

mem0 does not publish container images, but they ship buildable Dockerfiles and
release Python SDK versions regularly (tagged `v2.0.x`). This repo polls those
release tags daily, resolves the tag to a commit SHA, builds the upstream
Dockerfiles verbatim (zero drift), and pushes multi-arch (Intel + ARM) images
with cosign signing and SLSA provenance.

## What this repo does

- Polls the mem0 release tags once a day (cron) and on manual dispatch.
- Builds `server/Dockerfile` and `server/dashboard/Dockerfile` from the mem0
  source tree at the resolved commit SHA.
- Publishes two independently-pullable images to GHCR:
  - `ghcr.io/lhilton/mem0-server`
  - `ghcr.io/lhilton/mem0-dashboard`
- Signs every image with cosign (keyless) and attaches SLSA provenance + SBOM.
- Commits the processed tag back to `.upstream-release` so the next run is a
  no-op until mem0 ships again.

## Quickstart

```bash
cp .env.example .env
# edit .env — at minimum set POSTGRES_PASSWORD and JWT_SECRET
docker compose -f docker-compose.sample.yaml up -d
```

The sample compose also starts a `postgres` service using the upstream
`pgvector/pgvector:pg17` image (PostgreSQL 17 with the pgvector extension) for
memory storage. It is not republished — pull it directly from Docker Hub.

Services come up in dependency order:
`postgres` → `alembic-migrate` (one-shot) → `mem0-server` → `mem0-dashboard`.

Once healthy:
- Dashboard: http://localhost:3000
- API: http://localhost:8888

## First-admin bootstrap

There are exactly **two** ways to create the first admin user:

### (a) Browser setup wizard

After `docker compose up`, open http://localhost:3000/setup and complete the
wizard. This is the default path for a fresh deploy with zero users.

### (b) Pre-set `ADMIN_API_KEY`

Set `ADMIN_API_KEY=<random-string>` in `.env` **before** the first `up`. mem0
bootstraps this key as an admin when zero users exist, letting you skip the
wizard and call the API directly with that key.

> There is no third path. If both are unset on a deploy with existing users,
> use an existing admin's credentials.

## Available image tags

Each build publishes the following tags (example for a `v2.0.8` release):

| Tag | Meaning |
| --- | --- |
| `:latest` | Most recent daily-cron build (only promoted when no manual `tag` dispatch was used) |
| `:v2.0.8` | Full release tag |
| `:2.0.8` | Release without the `v` prefix |
| `:2.0` | Major.minor |
| `:2` | Major |
| `:mem0-<sha>` | Pinned to the upstream commit SHA |

> Note: `:v2.0.8` is populated on the first cron run because `.upstream-release`
> is seeded at `v2.0.7` (one release behind current). Subsequent tags appear as
> mem0 ships new releases.

## Configuration

The sample compose reads everything from `.env` (see `.env.example`). Three
URLs **must match your deployment topology** or you will get CORS / mixed-origin
errors:

| Variable | Seen by | Must match |
| --- | --- | --- |
| `DASHBOARD_URL` | mem0-server (CORS origin) | Your dashboard's externally-reachable URL |
| `NEXT_PUBLIC_API_URL` | The browser | Your API's externally-reachable URL |
| `API_INTERNAL_URL` | mem0-dashboard (server-to-server) | The API URL reachable from the dashboard host (service DNS name under compose) |

For a single-host `localhost` deploy the `.env.example` defaults are correct.

## How to pull

```bash
docker pull ghcr.io/lhilton/mem0-server:latest
docker pull ghcr.io/lhilton/mem0-dashboard:latest
```

> GHCR packages are published **private** by default on first push. Flip them to
> public in the GitHub UI (Packages → settings) if you want unauthenticated
> pulls.

## How to verify signatures (REQUIRED for production use)

Every image is signed with cosign keyless signing and carries a SLSA provenance
attestation. Verify before trusting any pulled image:

```bash
cosign verify \
  --certificate-identity 'https://github.com/lhilton/mem0-container/.github/workflows/mem0-upstream-rebuild.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/lhilton/mem0-server:latest
```

Verify the SLSA provenance attestation:

```bash
cosign verify-attestation --type slsaprovenance \
  --certificate-identity 'https://github.com/lhilton/mem0-container/.github/workflows/mem0-upstream-rebuild.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/lhilton/mem0-server:latest
```

Replace `mem0-server` with `mem0-dashboard` to verify the dashboard image.

> Use the exact `--certificate-identity` string above. Do **not** use a loose
> wildcard identity (the `...-regexp` variant) — strict identity matching
> prevents a different workflow or repo from satisfying the verify.

## Telemetry notice

mem0's PostHog telemetry is **ON by default** in the upstream image. To opt out,
set in `.env`:

```env
MEM0_TELEMETRY=false
```

## How to manually trigger a rebuild

GitHub → **Actions** → **mem0-upstream-rebuild** → **Run workflow**:

- **`force: true`** — rebuilds the current latest release and re-promotes
  `:latest`.
- **`tag: vX.Y.Z`** — rebuilds a specific historical release tag. This will
  **not** promote `:latest` and will **not** update `.upstream-release` (so the
  daily cron's no-op detection is preserved).

## Image sizes (approximate)

| Image | Per-arch size |
| --- | --- |
| `mem0-server` | ~800 MB – 1.2 GB |
| `mem0-dashboard` | ~300 – 500 MB |

Multi-arch (amd64 + arm64) roughly doubles the stored size. GHCR public packages
have no storage limit; private packages are capped at 500 MB on the free tier.

## Known limitations

1. **`--reload` dev flag.** mem0's production `server/Dockerfile` runs uvicorn
   with `--reload` (a development flag). This is inherited verbatim from
   upstream.
2. **Brief unsigned window for version tags.** Cosign signing happens **after**
   the image push. There is a short window where a version tag exists but is not
   yet signed. The `:latest` tag is promoted only after signing + attestation
   verification succeed.
3. **GHCR visibility.** Images are published **private** by default on first
   push. Manually flip them to public in the GitHub UI for unauthenticated pulls.
4. **Vendored `init/init-db.sh`.** Pinned to mem0 `v2.0.8`. The workflow warns
   in its logs when upstream changes (drift detection), but a manual re-vendor
   is required to update it.

## Attribution

mem0 source: https://github.com/mem0ai/mem0

This repo packages mem0's Dockerfiles for automated GHCR publishing. It does not
own or modify the mem0 source.
