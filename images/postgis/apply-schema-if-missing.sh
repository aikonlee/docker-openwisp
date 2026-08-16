#!/bin/sh
set -eu

# Apply FreeRADIUS schema to an existing Postgres database if the 'nas' table
# is missing. This script is intended to be run as a one-off against the
# Postgres service, for example:
#
# docker compose -f docker-compose.yml -f docker-compose.arm64.yml run --rm postgres /usr/local/bin/apply-schema-if-missing.sh

PGHOST=${PGHOST:-postgres}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-postgres}
PGDATABASE=${PGDATABASE:-postgres}
PGPASSWORD=${PGPASSWORD:-}

export PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE

SCHEMA=/docker-entrypoint-initdb.d/zz-freeradius-schema.sql
if [ ! -f "$SCHEMA" ]; then
	echo "Schema file not found at $SCHEMA"
	exit 1
fi

check_table() {
	psql -qtAX -c "SELECT to_regclass('public.nas');" 2>/dev/null | grep -q "nas" || return 1
}

# Wait for Postgres to be ready
echo "Waiting for Postgres to be ready on $PGHOST:$PGPORT..."
for i in $(seq 1 60); do
	pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" >/dev/null 2>&1 && break || true
	sleep 1
done

if check_table; then
	echo "'nas' table already exists; nothing to do."
	exit 0
fi

echo "Applying FreeRADIUS schema from $SCHEMA..."
psql -v ON_ERROR_STOP=1 -f "$SCHEMA"

echo "Schema applied."
