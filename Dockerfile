ARG ALPINE_VER=3.19

FROM ghcr.io/by275/base:alpine AS prebuilt
FROM ghcr.io/by275/base:alpine${ALPINE_VER} AS base

# 
# BUILD
# 
FROM base AS goaccess

RUN \
    echo "**** goaccess: prepare source ****" && \
    apk add --no-cache curl jq && \
    GOACCESS_VER=$(curl -fsSL "https://api.github.com/repos/allinurl/goaccess/tags" | jq -r '.[0].name') && \
    curl -sLJ -o /tmp/goaccess.tar.gz https://tar.goaccess.io/goaccess-${GOACCESS_VER//v/}.tar.gz && \
    tar -xzvf /tmp/goaccess.tar.gz -C /tmp --strip-components 1

RUN \
    echo "**** goaccess: install build-deps ****" && \
    apk add --no-cache \
        build-base \
        gettext-dev \
        libmaxminddb-dev \
        ncurses-dev \
        openssl-dev

RUN \
    echo "**** goaccess: build and install ****" && \
    cd /tmp && \
    ./configure --enable-utf8 --enable-geoip=mmdb --with-openssl && \
    make -j$(nproc) && \
    make install

# 
# COLLECT
# 
FROM base AS collector

# add s6-overlay
COPY --from=prebuilt /s6/ /bar/
ADD https://raw.githubusercontent.com/by275/docker-base/main/_/etc/cont-init.d/adduser /bar/etc/cont-init.d/10-adduser

# add traefik
COPY --from=traefik:latest /usr/local/bin/traefik /bar/usr/local/bin/

# add goaccess
COPY --from=goaccess /usr/local/bin/ /bar/usr/local/bin/

# add local files
COPY root/ /bar/

RUN \
    echo "**** directories ****" && \
    mkdir -p \
        /bar/traefik \
        /bar/goaccess \
        && \
    echo "**** permissions ****" && \
    chmod a+x \
        /bar/usr/local/bin/* \
        /bar/etc/cont-init.d/* \
        /bar/etc/s6-overlay/s6-rc.d/*/run \
        /bar/etc/s6-overlay/s6-rc.d/*/data/*

RUN \
    echo "**** s6: resolve dependencies ****" && \
    for dir in /bar/etc/s6-overlay/s6-rc.d/*; do mkdir -p "$dir/dependencies.d"; done && \
    for dir in /bar/etc/s6-overlay/s6-rc.d/*; do touch "$dir/dependencies.d/legacy-cont-init"; done && \
    echo "**** s6: create a new bundled service ****" && \
    mkdir -p /tmp/app/contents.d && \
    for dir in /bar/etc/s6-overlay/s6-rc.d/*; do touch "/tmp/app/contents.d/$(basename "$dir")"; done && \
    echo "bundle" > /tmp/app/type && \
    mv /tmp/app /bar/etc/s6-overlay/s6-rc.d/app && \
    echo "**** s6: deploy services ****" && \
    rm /bar/package/admin/s6-overlay/etc/s6-rc/sources/top/contents.d/legacy-services && \
    touch /bar/package/admin/s6-overlay/etc/s6-rc/sources/top/contents.d/app

# 
# RELEASE
# 
FROM base
LABEL maintainer="by275"
LABEL org.opencontainers.image.source https://github.com/by275/docker-traefik

# install packages
RUN \
    echo "**** install runtime packages ****" && \
    apk add --no-cache \
        `# logrotate` \
        logrotate gzip tar \
        `# goaccess` \
        gettext libmaxminddb ncurses \
        `# nginx` \
        nginx

# add build artifacts
COPY --from=collector /bar/ /

# environment settings
ENV \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    TRAEFIK_CONFIGFILE=/traefik/traefik.yml \
    TRAEFIK_ACCESSLOG_FILEPATH=/traefik/logs/access.log \
    LOGROTATE_INTERVAL=yearly \
    LOGROTATE_MAXSIZE=5M \
    LOGROTATE_NROTATE=10 \
    LOGROTATE_CRON_SCHEDULE="* * * * *" \
    LOGROTATE_CRON_LOG_LEVEL=9 \
    GOACCESS_ENABLED=true \
    GOACCESS_CONFIGFILE=/goaccess/goaccess.conf

EXPOSE 8890 7890

VOLUME /traefik /goaccess

ENTRYPOINT ["/init"]
