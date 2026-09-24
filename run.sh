#!/usr/bin/env bash
# One command from Terminal: builds hospital_quality and saves the full output to build_log.txt
#   ./run.sh                   (connects as user "postgres"; asks for its password)
#   PGUSER=myname ./run.sh     (connect as a different Postgres user)
set -euo pipefail
cd "$(dirname "$0")"

# psql is often not on the PATH on a Mac; look in the usual install locations
PSQL="$(command -v psql || true)"
if [ -z "$PSQL" ]; then
  for candidate in /Library/PostgreSQL/*/bin/psql \
                   /Applications/Postgres.app/Contents/Versions/latest/bin/psql \
                   /opt/homebrew/bin/psql /opt/homebrew/opt/postgresql@*/bin/psql \
                   /usr/local/bin/psql; do
    if [ -x "$candidate" ]; then PSQL="$candidate"; fi
  done
fi
if [ -z "$PSQL" ]; then
  echo "Could not find psql. Use pgAdmin instead: right-click the server > PSQL Tool, then run:"
  echo "  \\i '$(pwd)/create_and_load.sql'"
  exit 1
fi

echo "Using $PSQL"
"$PSQL" -h "${PGHOST:-localhost}" -U "${PGUSER:-postgres}" -d postgres -f create_and_load.sql 2>&1 | tee build_log.txt
echo
echo "Full output saved to build_log.txt"
