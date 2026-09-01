ARG BUILD_FROM
FROM ${BUILD_FROM}

RUN apk add --no-cache bash curl jq coreutils

COPY rootfs /
RUN chmod 755 /etc/services.d/archive-sync/run /usr/local/bin/archive-sync
