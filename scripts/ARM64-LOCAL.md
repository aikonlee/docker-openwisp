# Running the development stack natively on ARM64

This document explains how to build the local arm64 images and run the development stack without QEMU.

1. Build local arm64 images

```bash
# From the repository root
./scripts/arm64-build.sh
```

The script builds images and tags them `openwisp/<service>:arm64-local`. It uses the `images/` directory as the Docker build context.

2. Start the stack with the arm64 override

```bash
# Start services using the arm64 overrides
docker compose -f docker-compose.yml -f docker-compose.arm64.yml up -d --force-recreate
```

3. Notes & troubleshooting

- FreeRADIUS: the image includes a small DB-wait so it won't crash if the `nas` table is not yet present. If FreeRADIUS fails to load SQL modules, inspect its logs with:

```bash
docker compose -f docker-compose.yml -f docker-compose.arm64.yml logs -f freeradius
```

- PostGIS/Postgres: upstream alpine `postgis/postgis:15-3.4-alpine` lacks an arm64 manifest. The override file uses a local `openwisp/postgis:arm64-local` image built from Debian/postgres.

- InfluxDB: the arm64 override uses `influxdb:1.8` (non-alpine) which has multi-arch manifests; if you hit Docker Hub rate limits when resolving manifests, try authenticating with `docker login`.

- If `./scripts/arm64-build.sh` reports missing COPY sources, ensure you're running it from the repository root and that the `images/` directory is intact.

4. Next steps / improvements

- Add CI to build and publish arm64 images automatically.
- Improve healthchecks and depends_on ordering if you need stricter startup sequencing.
