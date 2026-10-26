ARG BUILD_FROM
FROM ${BUILD_FROM}

# openssh-client — сам туннель; jq — разбор /data/options.json; nc — проба HA и роутера.
RUN apk add --no-cache bash jq openssh-client netcat-openbsd

COPY rootfs /
RUN chmod 755 /etc/services.d/ha-tunnel/run
