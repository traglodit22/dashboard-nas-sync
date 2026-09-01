ARG BUILD_FROM
FROM ${BUILD_FROM}

RUN apk add --no-cache bash curl jq coreutils python3

COPY rootfs /
RUN chmod 755 /etc/services.d/dashboard-nas-sync/run
RUN chmod 755 /usr/local/bin/dashboard-nas-sync-api /usr/local/bin/nas-sync.sh
