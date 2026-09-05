# PostgreSQL 18.4-1.1C (official build with the 1C patch) for 1C:Enterprise.
# Native arm64 build for Apple Silicon: Debian 12 (bookworm) aarch64 packages.
#
# Before building, download from releases.1c.ru (the "PostgreSQL for 1C:Enterprise"
# project, version 18.4-1.1C) the archive for Debian 12.11 ARM and place it in dists/:
#   postgresql_18.4_1_debian_12.11_aarch64_package.tar.bz2
FROM debian:12-slim

ARG PG_PACKAGE=postgresql_18.4_1_debian_12.11_aarch64_package.tar.bz2
ARG PG_MAJOR=18

LABEL org.opencontainers.image.title="PostgreSQL ${PG_MAJOR} for 1C" \
      org.opencontainers.image.description="PostgreSQL 18.4-1.1C (1C-patched), Debian 12 arm64" \
      org.opencontainers.image.version="18.4-1.1C"

# installation per the official 1C recommendation (PostgreSQL 18.4-1.1C release notes)
ENV DEBIAN_FRONTEND=noninteractive

# the packages tar.bz2 comes in via bind-mount and does not remain in image layers
RUN --mount=type=bind,source=dists,target=/dists set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bzip2 ca-certificates gnupg locales ssl-cert tzdata; \
    # the locale is mandatory: the 1C cluster is created with ru_RU.UTF-8
    echo 'ru_RU.UTF-8 UTF-8' >> /etc/locale.gen; \
    locale-gen; \
    # unpack and install the 1C build of PostgreSQL
    mkdir -p /tmp/pg-dists; \
    tar -xjf "/dists/${PG_PACKAGE}" -C /tmp/pg-dists; \
    apt-get install -y --no-install-recommends /tmp/pg-dists/*.deb; \
    # postgresql-common may create a default cluster — remove it,
    # the entrypoint creates the cluster on first start (in the volume)
    pg_dropcluster ${PG_MAJOR} main --stop 2>/dev/null || true; \
    rm -rf /etc/postgresql /var/lib/postgresql/*; \
    install -d -m 700 -o postgres -g postgres /var/lib/postgresql/${PG_MAJOR}/main; \
    # cleanup
    apt-get purge -y --auto-remove gnupg; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/pg-dists \
           /usr/share/doc /usr/share/man

ENV PATH=/usr/lib/postgresql/${PG_MAJOR}/bin:$PATH \
    PGDATA=/var/lib/postgresql/${PG_MAJOR}/main \
    LANG=ru_RU.UTF-8

# config/entrypoint AFTER the heavy layer: edits do not invalidate the PG install cache
COPY src/entrypoints/docker-entrypoint.sh /usr/local/bin/
COPY src/conf/postgresql-1c.conf /conf/postgresql-1c.conf

USER postgres
VOLUME /var/lib/postgresql/${PG_MAJOR}/main
EXPOSE 5432

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["postgres"]
