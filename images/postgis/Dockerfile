# Minimal PostGIS image for arm64
# Based on Debian slim with PostgreSQL 15 from the official postgres image and PostGIS packages.
# This Dockerfile is intentionally small and uses packages to avoid building PostGIS from source.

FROM --platform=linux/arm64 postgres:15-bullseye

# Install PostGIS and dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       postgis postgresql-15-postgis-3 \
    && rm -rf /var/lib/apt/lists/*

# Provide a recognizable tag and keep entrypoint of postgres
LABEL maintainer="docker-openwisp arm64 helper"

# No changes to entrypoint/cmd; this image is a drop-in replacement for postgis/postgis:15-3.4

# Copy a small init helper and the FreeRADIUS SQL schema so the container can
# apply the schema at startup if the tables are missing. This helps avoid
# manual imports when bringing up the dev stack.
COPY postgis/init-sql/freeradius-schema.sql /docker-entrypoint-initdb.d/zz-freeradius-schema.sql
COPY postgis/docker-entrypoint.sh /usr/local/bin/docker-entrypoint-wrapper.sh
COPY postgis/apply-schema-if-missing.sh /usr/local/bin/apply-schema-if-missing.sh
RUN chmod +x /usr/local/bin/docker-entrypoint-wrapper.sh /usr/local/bin/apply-schema-if-missing.sh
ENTRYPOINT ["/usr/local/bin/docker-entrypoint-wrapper.sh"]
