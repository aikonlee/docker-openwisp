#!/bin/bash
set -e

# Delegate to the original postgres entrypoint
exec /usr/local/bin/docker-entrypoint.sh "$@"
