#!/bin/bash
set -e

# Enable pgvector extension in postgres (memory storage) and mem0_app (auth schemas).
# Runs AFTER 01-init-db.sh due to alphabetical ordering (02- > 01-).
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
EOSQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "mem0_app" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
EOSQL
