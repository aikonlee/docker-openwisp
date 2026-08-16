#!/usr/bin/env bash
# Check and build missing/incorrect-arch Docker images for docker-openwisp on an ARM64 host
# Usage: ./scripts/check_and_build_arm64.sh
# - Inspects a curated list of images used by the compose files
# - If an image is missing or not linux/arm64, attempts to rebuild its corresponding service
# - Prints a summary at the end

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_FILES="-f ${ROOT_DIR}/docker-compose.yml -f ${ROOT_DIR}/docker-compose.arm64.yml"

# Verbose log for environments with flaky docker CLI output
LOGFILE="/tmp/arm64-check.log"
echo "Starting ARM64 check at $(date)" >"$LOGFILE"
echo "ROOT_DIR=$ROOT_DIR" >>"$LOGFILE"

# Mapping: service -> image (expected tag as used in compose/arm64 override)
declare -A SERVICE_IMAGE=(
	[dashboard]=openwisp/openwisp-dashboard:arm64-local
	[api]=openwisp/openwisp-api:arm64-local
	[websocket]=openwisp/openwisp-websocket:arm64-local
	[nginx]=openwisp/openwisp-nginx:arm64-local
	[freeradius]=openwisp/openwisp-freeradius:arm64-local
	[postfix]=openwisp/openwisp-postfix:arm64-local
	[openvpn]=openwisp/openwisp-openvpn:arm64-local
	[celery]=openwisp/openwisp-dashboard:arm64-local
	[celery_monitoring]=openwisp/openwisp-dashboard:arm64-local
	[celerybeat]=openwisp/openwisp-dashboard:arm64-local
	[postgres]=openwisp/postgis:arm64-local
	[influxdb]=influxdb:1.8
	[redis]=redis:7-alpine
)

missing=()
not_arm64=()
rebuild_services=()

echo "Checking local Docker images and architectures..." | tee -a "$LOGFILE"
if [ "${1:-}" = "--dry-run" ]; then
	echo "DRY RUN: Will check the following service -> expected image mapping:" | tee -a "$LOGFILE"
	for svc in "${!SERVICE_IMAGE[@]}"; do
		echo "  - $svc -> ${SERVICE_IMAGE[$svc]}" | tee -a "$LOGFILE"
	done
	echo "DRY RUN complete." | tee -a "$LOGFILE"
	exit 0
fi
for svc in "${!SERVICE_IMAGE[@]}"; do
	img=${SERVICE_IMAGE[$svc]}
	printf "\nService: %s\n  Expected image: %s\n" "$svc" "$img" | tee -a "$LOGFILE"

	if ! docker image inspect "$img" >/dev/null 2>&1; then
		echo "  -> Image not found locally" | tee -a "$LOGFILE"
		missing+=("$img")
		# If the service has a build section in compose, mark it for rebuild
		# We assume that services with these names have build defined in compose
		rebuild_services+=("$svc")
		continue
	fi

	arch=$(docker image inspect --format '{{.Architecture}}/{{.Os}}' "$img" 2>/dev/null || true)
	if [ -z "$arch" ]; then
		echo "  -> Could not determine image architecture" | tee -a "$LOGFILE"
		not_arm64+=("$img (unknown)")
		rebuild_services+=("$svc")
		continue
	fi

	echo "  -> Local image architecture: $arch" | tee -a "$LOGFILE"
	if [[ "$arch" != "arm64/"* && "$arch" != "aarch64/"* && "$arch" != "arm64" ]]; then
		echo "  -> Image is not arm64" | tee -a "$LOGFILE"
		not_arm64+=("$img ($arch)")
		rebuild_services+=("$svc")
	else
		echo "  -> OK: image is arm64" | tee -a "$LOGFILE"
	fi
done

# Deduplicate rebuild_services while preserving order
declare -A seen=()
unique_rebuild=()
for s in "${rebuild_services[@]}"; do
	if [ -z "${seen[$s]:-}" ]; then
		unique_rebuild+=("$s")
		seen[$s]=1
	fi
done

if [ ${#unique_rebuild[@]} -eq 0 ]; then
	echo "\nAll checked images are present and ARM64. Nothing to rebuild." | tee -a "$LOGFILE"
	exit 0
fi

echo "\nImages missing or not ARM64 detected. Will attempt to rebuild the following services (in parallel):" | tee -a "$LOGFILE"
for s in "${unique_rebuild[@]}"; do
	echo "  - $s" | tee -a "$LOGFILE"
done

# Rebuild services
echo "\nStarting rebuild..." | tee -a "$LOGFILE"
# Build each service individually to be safer about failures
for s in "${unique_rebuild[@]}"; do
	echo "\n--- Building service: $s ---" | tee -a "$LOGFILE"
	echo "Building $s at $(date)" >>"$LOGFILE"
	if ! docker compose $COMPOSE_FILES build --no-cache --pull "$s" 2>&1 | tee -a "$LOGFILE"; then
		echo "Build failed for service $s" | tee -a "$LOGFILE" >&2
	fi
done

# After rebuild, re-check architectures
echo "\nRe-checking architectures after rebuild..." | tee -a "$LOGFILE"
failed_after=()
for s in "${unique_rebuild[@]}"; do
	img=${SERVICE_IMAGE[$s]}
	if ! docker image inspect "$img" >/dev/null 2>&1; then
		echo "  - $s: image $img still missing" | tee -a "$LOGFILE"
		failed_after+=("$s")
		continue
	fi
	arch=$(docker image inspect --format '{{.Architecture}}/{{.Os}}' "$img" 2>/dev/null || true)
	echo "  - $s: $img -> $arch" | tee -a "$LOGFILE"
	if [[ "$arch" != "arm64/"* && "$arch" != "aarch64/"* && "$arch" != "arm64" ]]; then
		failed_after+=("$s (not arm64: $arch)")
		echo "  - $s is not arm64 after rebuild: $arch" >>"$LOGFILE"
	fi
done

if [ ${#failed_after[@]} -eq 0 ]; then
	echo "\nSuccess: all rebuilt images are ARM64 or present locally." | tee -a "$LOGFILE"
	exit 0
else
	echo "\nWarning: some services could not be rebuilt as ARM64 or remain missing:" | tee -a "$LOGFILE" >&2
	for f in "${failed_after[@]}"; do
		echo "  - $f" | tee -a "$LOGFILE" >&2
	done
	echo "\nNext steps: inspect the build logs for the failing services above. Common fixes: ensure the base image supports arm64 or adjust docker-compose.arm64.yml to point to an arm64-compatible upstream image." | tee -a "$LOGFILE"
	echo "Logs saved to $LOGFILE" | tee -a "$LOGFILE"
	exit 2
fi
