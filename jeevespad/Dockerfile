FROM ghcr.io/home-assistant/base-python:3.13-alpine3.24

ARG BUILD_VERSION=0.1.0
ARG BUILD_ARCH=amd64

# ssh/scp/sshpass: installing and maintaining wallPads (the same commands deploy.sh uses)
RUN apk add --no-cache openssh-client sshpass

WORKDIR /app
COPY app/requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ /app/

# with-contenv: s6 starts the command with an empty environment, which would hide SUPERVISOR_TOKEN
CMD [ "/command/with-contenv", "python3", "-m", "jeevespad_manager" ]

LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="app" \
    io.hass.arch="aarch64|amd64" \
    io.hass.name="JeevesPad Manager" \
    io.hass.description="Manage Jeeves wall panels from Home Assistant" \
    io.hass.url="https://github.com/JonnyFunFun/JeevesPad" \
    org.opencontainers.image.title="JeevesPad Manager" \
    org.opencontainers.image.source="https://github.com/JonnyFunFun/JeevesPad" \
    org.opencontainers.image.licenses="MIT"
