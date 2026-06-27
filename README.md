# mem0-container

Pre-built, automatically updated Docker images for [mem0](https://github.com/mem0ai/mem0)'s
**server** API and **dashboard** web UI, published to GitHub Container Registry with cosign
signatures and SLSA provenance.

mem0 ships Dockerfiles but does not publish container images. This repo tracks mem0's Python SDK
release tags, builds the upstream Dockerfiles, and publishes multi-arch images for `linux/amd64`
and `linux/arm64`.

## Quickstart

Clone this repo and run the setup commands from the repo root:

```bash
git clone https://github.com/lhilton/mem0-container.git
cd mem0-container
cp .env.example .env
```

Edit `.env` before starting the stack:

- Set `POSTGRES_PASSWORD` to a real Postgres password.
- Set `JWT_SECRET` to a random 32+ character string, for example `openssl rand -hex 32`.
- Set at least one provider key expected by your mem0 usage, such as `OPENAI_API_KEY`.
- Optionally set `ADMIN_API_KEY` before first boot to skip the dashboard setup wizard.

If GHCR returns `denied` while pulling these images, either make the GitHub packages public or log in
with a token that has `read:packages`:

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
```

Start the sample stack:

```bash
docker compose -f docker-compose.sample.yaml up -d
docker compose -f docker-compose.sample.yaml ps
```

Services start in this order:

```text
postgres -> alembic-migrate (one-shot) -> mem0-server -> mem0-dashboard
```

Once healthy:

| Service | URL |
|---|---|
| Dashboard | http://localhost:3000 |
| API server | http://localhost:8888 |
| Postgres, from host | localhost:8432 |

Open http://localhost:3000/setup on first launch to create the first admin user. If
`ADMIN_API_KEY` was set before first boot, mem0 bootstraps that key as the first admin instead.

Useful local commands:

```bash
docker compose -f docker-compose.sample.yaml logs -f mem0-server mem0-dashboard
docker compose -f docker-compose.sample.yaml down
docker compose -f docker-compose.sample.yaml down -v
```

`down -v` deletes the sample stack's named volumes, including Postgres data. Use it only for
disposable local deployments.

## Compose Reference

`docker-compose.sample.yaml` is the canonical Compose example for this repo. Prefer using it as-is
or copying it whole, rather than copying a partial YAML snippet from documentation.

The sample stack contains:

| Service | Image | Purpose |
|---|---|---|
| `postgres` | `pgvector/pgvector:pg17` | PostgreSQL 17 plus pgvector |
| `alembic-migrate` | `ghcr.io/lhilton/mem0-server:latest` | One-shot database migration |
| `mem0-server` | `ghcr.io/lhilton/mem0-server:latest` | mem0 API |
| `mem0-dashboard` | `ghcr.io/lhilton/mem0-dashboard:latest` | mem0 web UI |

The sample uses two named volumes:

- `postgres_db` for Postgres data.
- `mem0_history` for the server's SQLite history path at `/app/history`.

The sample uses one Docker network named by `MEM0_NETWORK_NAME`, defaulting to `mem0_network`.
Set a unique `MEM0_NETWORK_NAME` when running parallel stacks or smoke tests on the same Docker
host.

## Database Configuration

The sample has two database names with different jobs:

| Variable | Default | Meaning |
|---|---|---|
| `POSTGRES_DB` | `postgres` | Database used by pgvector memory storage |
| `APP_DB_NAME` | `mem0_app` | Application database for users, auth, and API keys |

The Postgres init scripts in `init/` create `APP_DB_NAME` and enable the `vector` extension when a
fresh Postgres volume is initialized. Changing `APP_DB_NAME` after Postgres data already exists does
not rename or create a new database. For an existing volume, create the database and extension
manually, or reset a disposable local stack:

```bash
docker compose -f docker-compose.sample.yaml down -v
docker compose -f docker-compose.sample.yaml up -d
```

## Configuration

Copy `.env.example` to `.env` and fill in deployment-specific values.

Required:

| Variable | Description |
|---|---|
| `POSTGRES_PASSWORD` | Postgres password. The sample Compose file refuses to start without it. |
| `JWT_SECRET` | Random 32+ character string used to sign JWTs. |

URLs that must match your topology:

| Variable | Seen by | Must match |
|---|---|---|
| `DASHBOARD_URL` | `mem0-server` CORS checks | Dashboard URL reachable by users |
| `NEXT_PUBLIC_API_URL` | Browser | API URL reachable by users' browsers |
| `API_INTERNAL_URL` | `mem0-dashboard` server process | API URL reachable from the dashboard container or host |

For the sample `localhost` deployment, the `.env.example` URL defaults are correct.

Common optional values:

| Variable | Default | Description |
|---|---|---|
| `POSTGRES_USER` | `postgres` | Postgres user used by the sample stack |
| `POSTGRES_DB` | `postgres` | pgvector memory database |
| `APP_DB_NAME` | `mem0_app` | Application database; honored by init scripts only on fresh volumes |
| `MEM0_NETWORK_NAME` | `mem0_network` | Docker network name shared by the sample stack and standalone migration runner |
| `MEM0_TELEMETRY` | `true` | Upstream mem0 PostHog telemetry toggle; set `false` to opt out |
| `ADMIN_API_KEY` | empty | Optional first admin API key for fresh deployments |
| `OPENAI_API_KEY` | empty | Provider key; use another supported provider key if preferred |

## First Admin Bootstrap

There are two supported first-admin paths:

1. Browser setup wizard: after the stack is running, open http://localhost:3000/setup and complete
   the wizard.
2. Pre-set admin key: set `ADMIN_API_KEY=<random-string>` in `.env` before the first `up`.

Both paths only apply when the application database has zero users.

## Standalone Migrations

Use the standalone migration runner when Postgres is already running and you want to rerun Alembic
without starting the whole sample stack. Run this from the repo root:

```bash
docker compose -f docker-compose.sample.yaml up -d postgres
docker compose --env-file .env -f scripts/alembic-migrate.yaml run --rm alembic-migrate
```

The standalone file joins the existing Docker network instead of creating a new one. If you set
`MEM0_NETWORK_NAME` for the sample stack, use the same `.env` file for the standalone migration
command.

## Advanced Docker CLI Usage

Compose is the recommended path. If you need raw `docker run` commands, run them from the repo root
so the `init/` bind mounts resolve correctly.

```bash
export MEM0_POSTGRES_PASSWORD='change-me'
export MEM0_JWT_SECRET="$(openssl rand -hex 32)"
export MEM0_OPENAI_API_KEY='sk-your-key'

docker network create mem0-cli-net

docker run -d --name mem0-cli-postgres \
  --network mem0-cli-net \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD="$MEM0_POSTGRES_PASSWORD" \
  -e POSTGRES_DB=postgres \
  -e APP_DB_NAME=mem0_app \
  -v mem0_cli_pgdata:/var/lib/postgresql/data \
  -v "$PWD/init/init-db.sh:/docker-entrypoint-initdb.d/01-init-db.sh:ro" \
  -v "$PWD/init/init-extensions.sh:/docker-entrypoint-initdb.d/02-init-extensions.sh:ro" \
  pgvector/pgvector:pg17

until docker exec mem0-cli-postgres pg_isready -q -d postgres -U postgres; do
  sleep 1
done

docker run --rm --network mem0-cli-net \
  -e POSTGRES_HOST=mem0-cli-postgres \
  -e POSTGRES_PORT=5432 \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD="$MEM0_POSTGRES_PASSWORD" \
  -e POSTGRES_DB=postgres \
  -e APP_DB_NAME=mem0_app \
  ghcr.io/lhilton/mem0-server:latest \
  sh -c "alembic upgrade head"

docker run -d --name mem0-cli-server \
  --network mem0-cli-net \
  -p 8888:8000 \
  -e POSTGRES_HOST=mem0-cli-postgres \
  -e POSTGRES_PORT=5432 \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD="$MEM0_POSTGRES_PASSWORD" \
  -e POSTGRES_DB=postgres \
  -e APP_DB_NAME=mem0_app \
  -e JWT_SECRET="$MEM0_JWT_SECRET" \
  -e OPENAI_API_KEY="$MEM0_OPENAI_API_KEY" \
  -e DASHBOARD_URL=http://localhost:3000 \
  -e HISTORY_DB_PATH=/app/history/history.db \
  -v mem0_cli_history:/app/history \
  ghcr.io/lhilton/mem0-server:latest

docker run -d --name mem0-cli-dashboard \
  --network mem0-cli-net \
  -p 3000:3000 \
  -e API_INTERNAL_URL=http://mem0-cli-server:8000 \
  -e NEXT_PUBLIC_API_URL=http://localhost:8888 \
  -e NEXT_PUBLIC_INSTANCE_NAME=Mem0 \
  ghcr.io/lhilton/mem0-dashboard:latest
```

Cleanup for the raw Docker example:

```bash
docker rm -f mem0-cli-dashboard mem0-cli-server mem0-cli-postgres
docker network rm mem0-cli-net
docker volume rm mem0_cli_pgdata mem0_cli_history
```

## Available Image Tags

Normal tracking builds, including daily cron runs and manual `force: true` runs without a manual
`tag`, publish exact tags first. After the built digest has a verified cosign signature and SLSA
provenance attestation, the workflow promotes mutable channel tags to that same digest.

Example for upstream release `v2.0.8`:

| Tag | Meaning |
|---|---|
| `:v2.0.8` | Exact upstream release tag |
| `:2.0.8` | Exact upstream release tag without the `v` prefix |
| `:mem0-<sha>` | Exact upstream commit SHA |
| `:latest` | Mutable latest verified tracking build |
| `:2.0` | Mutable major.minor channel |
| `:2` | Mutable major channel |

Manual historical rebuilds with `tag: vX.Y.Z` always rebuild that tag, even when it matches
`.upstream-release`. They publish only the three exact tags, never move `:latest`, `:X.Y`, or `:X`,
and never update `.upstream-release`.

## Pulling Images

```bash
docker pull ghcr.io/lhilton/mem0-server:latest
docker pull ghcr.io/lhilton/mem0-dashboard:latest
```

GitHub packages are private by default on first publish. Anonymous pulls work only after the package
owner makes both GHCR packages public; otherwise authenticate with `docker login ghcr.io`.

## Verifying Images

For production use, verify both the image signature and SLSA provenance attestation with the strict
workflow identity:

```bash
cosign verify \
  --certificate-identity 'https://github.com/lhilton/mem0-container/.github/workflows/mem0-upstream-rebuild.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/lhilton/mem0-server:latest

cosign verify-attestation --type slsaprovenance \
  --certificate-identity 'https://github.com/lhilton/mem0-container/.github/workflows/mem0-upstream-rebuild.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/lhilton/mem0-server:latest
```

Replace `mem0-server` with `mem0-dashboard` to verify the dashboard image.

Exact tags such as `:vX.Y.Z`, `:X.Y.Z`, and `:mem0-<sha>` are pushed before signing, so there can be
a brief window where an exact tag exists but verification does not yet pass. Mutable tags
`:latest`, `:X.Y`, and `:X` are promoted only after verification succeeds.

## How Images Are Published

The release workflow runs daily at 09:17 UTC and can be run manually from GitHub Actions. It:

1. Resolves the latest non-prerelease mem0 `vX.Y.Z` release tag, or validates a manual `tag`.
2. Resolves the tag to a commit SHA and checks whether a build is needed.
3. Builds `mem0-server` and `mem0-dashboard` from the upstream mem0 source at that SHA.
4. Pushes exact tags, signs the built digest, and verifies the signature and SLSA attestation.
5. Promotes mutable tags only for normal tracking builds.
6. Updates `.upstream-release` only for normal tracking builds.

Manual dispatch options:

- `force: true` rebuilds the current latest release and re-promotes mutable tags after verification.
- `tag: vX.Y.Z` rebuilds a specific historical release and never promotes mutable tags.

The workflow fails before building or pushing unless it is running on `refs/heads/main`, matching the
strict OIDC identity used by cosign verification.

## Image Sizes

| Image | Approximate per-arch size |
|---|---|
| `mem0-server` | 800 MB to 1.2 GB |
| `mem0-dashboard` | 300 MB to 500 MB |

Multi-arch images store separate architecture manifests, so registry storage is larger than a
single pulled image.

## Known Limitations

1. mem0's upstream production `server/Dockerfile` currently runs uvicorn with `--reload`; this repo
   inherits that behavior from upstream.
2. GHCR packages may need to be made public manually before anonymous pulls work.
3. `init/init-db.sh` is locally patched from `init/init-db.upstream.sh` so `APP_DB_NAME` works. The
   workflow warns when the tracked upstream baseline drifts.

## Attribution

mem0 source: https://github.com/mem0ai/mem0

This repo packages mem0's Dockerfiles for automated GHCR publishing. It does not own or modify the
mem0 source.
