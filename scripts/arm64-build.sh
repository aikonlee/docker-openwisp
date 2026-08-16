#!/usr/bin/env bash
set -euo pipefail

# Build all local OpenWISP images for linux/arm64 and tag them :arm64-local
# Usage: ./scripts/arm64-build.sh

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

IMAGES=(
	openwisp/openwisp-base:arm64-local
	openwisp/openwisp-dashboard:arm64-local
	openwisp/openwisp-api:arm64-local
	openwisp/openwisp-websocket:arm64-local
	openwisp/openwisp-nginx:arm64-local
	openwisp/openwisp-freeradius:arm64-local
	openwisp/openwisp-postfix:arm64-local
	openwisp/openwisp-openvpn:arm64-local
	openwisp/postgis:arm64-local
)

declare -A DOCKERFILES
DOCKERFILES[openwisp / openwisp - base]=images/openwisp_base
DOCKERFILES[openwisp / openwisp - dashboard]=images/openwisp_dashboard
DOCKERFILES[openwisp / openwisp - api]=images/openwisp_api
DOCKERFILES[openwisp / openwisp - websocket]=images/openwisp_websocket
DOCKERFILES[openwisp / openwisp - nginx]=images/openwisp_nginx
DOCKERFILES[openwisp / openwisp - freeradius]=images/openwisp_freeradius
DOCKERFILES[openwisp / openwisp - postfix]=images/openwisp_postfix
DOCKERFILES[openwisp / openwisp - openvpn]=images/openwisp_openvpn
DOCKERFILES[openwisp / postgis]=images/postgis

echo "Building ARM64 images (tagged :arm64-local)..."

for fulltag in "${IMAGES[@]}"; do
	name=${fulltag%%:*}
	tag=${fulltag##*:}
	builddir=${DOCKERFILES[$name]:-}
	if [ -z "$builddir" ]; then
		echo "Skipping $fulltag (no build dir configured)"
		continue
	fi
	if [ ! -f "$builddir/Dockerfile" ]; then
		echo "Skipping $fulltag (no Dockerfile at $builddir/Dockerfile)"
		continue
	fi
	echo "- Preparing to build $name from $builddir as $tag"
	# Use images/ as the build context (Dockerfiles reference paths relative to images/)
	BUILD_CTX="$ROOT_DIR/images"
	# Simple sanity: verify that COPY source files referenced in Dockerfile exist in build context
	missing=0
	# Extract COPY sources; strip common COPY options like --chown=... before tokenizing
	for src in $(sed -n '1,200p' "$builddir/Dockerfile" | grep -Ei '^[[:space:]]*COPY ' | sed -E 's/^[[:space:]]*COPY[[:space:]]+//I' | sed -E 's/--[^ =]+(=[^ ]+)?//g' | tr -d '\\' | awk '{for(i=1;i<NF;i++) print $i}'); do
		# ignore absolute paths or remote URLs
		case "$src" in
		/*) continue ;;
		http* | https*) continue ;;
		esac
		# check relative to images context as many Dockerfiles COPY from ./common or other folders
		if [ ! -e "$BUILD_CTX/$src" ] && [ ! -e "$builddir/$src" ] && [ ! -e "$src" ]; then
			echo "  missing source: $src" >&2
			missing=1
		fi
	done
	if [ "$missing" -eq 1 ]; then
		echo "  Skipping build for $name: missing COPY sources in $builddir/Dockerfile"
		continue
	fi
	echo "  Running docker build..."
	docker build --platform linux/arm64 -t "$name:$tag" -f "$builddir/Dockerfile" "$BUILD_CTX"
done

echo "All done. You can now run:"
echo "  docker compose -f docker-compose.yml -f docker-compose.arm64.yml up -d --force-recreate"
