#!/bin/bash
set -e

# Simple wrapper that delegates to the upstream Postgres docker-entrypoint.
# It exists to ensure the image has a predictable entrypoint path and to
# keep the ability to extend behavior in the future. For fresh databases
# the SQL files placed into /docker-entrypoint-initdb.d/ (copied at build
# time) will be executed by the upstream entrypoint during initialization.

ORIG_ENTRYPOINT=/usr/local/bin/docker-entrypoint.sh

if [ ! -x "$ORIG_ENTRYPOINT" ]; then
	echo "ERROR: upstream entrypoint not found at $ORIG_ENTRYPOINT" >&2
	exec "$@"
fi

echo "[postgis-wrapper] Delegating to upstream entrypoint: $ORIG_ENTRYPOINT $@"
exec "$ORIG_ENTRYPOINT" "$@"
