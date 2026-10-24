#!/usr/bin/env bash
# One-time (and safe to re-run) local setup: tools, server deps, server/.env,
# a local Postgres with SSL, and seed data. Usage: make setup
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PGDATA="${PGDATA:-$HOME/.hacktx26/pgdata}"
PGPORT="${PGPORT:-5432}"
DB_NAME="hacktx26"
DB_URL="postgresql://postgres@localhost:$PGPORT/$DB_NAME"
ENV_FILE="$ROOT/server/.env"
# Postgres refuses to start on macOS without a locale.
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

step "Tools"
command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
command -v node >/dev/null || brew install node
[ -x "$(brew --prefix)/opt/postgresql@17/bin/pg_ctl" ] || brew install postgresql@17
PG="$(brew --prefix)/opt/postgresql@17/bin"
echo "node $(node -v), $("$PG/postgres" --version)"

step "Server dependencies"
(cd "$ROOT/server" && npm install --no-fund --no-audit)

step "server/.env"
if [ ! -f "$ENV_FILE" ]; then
  cp "$ROOT/server/.env.example" "$ENV_FILE"
  echo "Created server/.env from .env.example"
fi
# Point at the local database only if no DATABASE_URL is set (keeps a Tiger URL if you have one).
if grep -q '^DATABASE_URL=$' "$ENV_FILE"; then
  sed -i '' "s#^DATABASE_URL=\$#DATABASE_URL=$DB_URL#" "$ENV_FILE"
  echo "DATABASE_URL -> $DB_URL"
fi

step "Postgres ($PGDATA, port $PGPORT)"
if [ ! -f "$PGDATA/PG_VERSION" ]; then
  mkdir -p "$PGDATA"
  "$PG/initdb" -D "$PGDATA" -U postgres --auth=trust >/dev/null
  # The server's pg client always asks for SSL, so serve a self-signed cert locally.
  openssl req -new -x509 -days 3650 -nodes -subj "/CN=localhost" \
    -out "$PGDATA/server.crt" -keyout "$PGDATA/server.key" >/dev/null 2>&1
  chmod 600 "$PGDATA/server.key"
  printf "ssl = on\nport = %s\n" "$PGPORT" >> "$PGDATA/postgresql.conf"
  echo "Initialized a new cluster"
fi
if ! "$PG/pg_ctl" -D "$PGDATA" status >/dev/null 2>&1; then
  "$PG/pg_ctl" -D "$PGDATA" -l "$PGDATA/log.txt" -w start >/dev/null
fi
echo "Running"
"$PG/psql" -U postgres -h localhost -p "$PGPORT" -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 \
  || "$PG/createdb" -U postgres -h localhost -p "$PGPORT" "$DB_NAME"

step "Schema and seed data"
(cd "$ROOT/server" && npm run --silent db:reset)

step "API keys"
missing=()
for key in GEMINI_API_KEY META_API_KEY SERPAPI_KEY; do
  grep -q "^$key=." "$ENV_FILE" || missing+=("$key")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing in server/.env: ${missing[*]}"
  echo "The app still runs, but the AI and places steps use canned fixtures until you add them."
else
  echo "All keys set"
fi

printf '\nDone. Next: make server   (then make sim or make phone)\n'
