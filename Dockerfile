ARG ALPINE_VER=3.15

FROM ghcr.io/linuxserver/baseimage-alpine:${ALPINE_VER} AS base

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


FROM base AS builder

COPY --from=goaccess /usr/local/bin/ /bar/usr/local/bin/

# add local files
COPY root/ /bar/

RUN \
    echo "**** goaccess: build and install ****" && \
    chmod a+x /bar/usr/local/bin/*


# 
# RELEASE
# 
FROM base
LABEL maintainer="by275"
LABEL org.opencontainers.image.source https://github.com/by275/docker-goaccess

# install packages
RUN \
    echo "**** install runtime packages ****" && \
    apk add --no-cache \
        `# logrotate` \
        logrotate gzip tar docker-cli \
        `# goaccess` \
        gettext libmaxminddb ncurses \
        `# nginx` \
        nginx

# add build artifacts
COPY --from=builder /bar/ /

# environment settings
ENV \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    TRAEFIK_ACCESSLOG_FILEPATH="/logs/access.log" \
    TRAEFIK_CONAINER_ID_COMMAND="docker ps --quiet --filter ancestor=traefik" \
    LOGROTATE_INTERVAL=yearly \
    LOGROTATE_MAXSIZE=5M \
    LOGROTATE_NROTATE=10 \
    LOGROTATE_CRON_SCHEDULE="* * * * *" \
    LOGROTATE_CRON_LOG_LEVEL=9 \
    GOACCESS_BASE_URL=/goaccess \
    GOACCESS_WS_URL=example.com:80

VOLUME /config /logs
WORKDIR /config

HEALTHCHECK --interval=5s --timeout=2s --retries=20 \
    CMD /usr/local/bin/healthcheck || exit 1

ENTRYPOINT ["/init"]
