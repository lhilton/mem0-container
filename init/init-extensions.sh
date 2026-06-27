#!/bin/bash
set -e

APP_DB_NAME="${APP_DB_NAME:-mem0_app}"

# Enable pgvector extension in postgres (memory storage) and the app database.
# Runs AFTER 01-init-db.sh due to alphabetical ordering (02- > 01-).
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
EOSQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$APP_DB_NAME" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
EOSQL
