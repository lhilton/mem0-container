#!/bin/bash
set -e

# Locally patched from init/init-db.upstream.sh to support APP_DB_NAME.
APP_DB_NAME="${APP_DB_NAME:-mem0_app}"

# Create the configured application database for user/auth/api-key data.
# The default 'postgres' database is used by pgvector for memory storage.
psql -v ON_ERROR_STOP=1 \
    --username "$POSTGRES_USER" \
    --dbname "$POSTGRES_DB" \
    --set=app_db_name="$APP_DB_NAME" <<-'EOSQL'
    SELECT format('CREATE DATABASE %I', :'app_db_name')
    WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'app_db_name')\gexec
EOSQL
