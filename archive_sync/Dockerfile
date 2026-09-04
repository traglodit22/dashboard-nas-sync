ARG BUILD_FROM
FROM ${BUILD_FROM}

RUN apk add --no-cache bash curl jq coreutils python3 openssh-client

COPY rootfs /
RUN chmod 755 /etc/services.d/archive-sync/run \
  /etc/services.d/archive-sync-api/run \
  /etc/services.d/archive-sync-tunnel/run \
  /usr/local/bin/archive-sync \
  /usr/local/bin/archive-sync-api
