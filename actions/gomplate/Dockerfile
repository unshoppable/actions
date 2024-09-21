FROM alpine:latest

RUN apk add --no-cache curl \
  && curl -Lo /usr/local/bin/gomplate https://github.com/hairyhenderson/gomplate/releases/download/v3.11.3/gomplate_linux-amd64-slim \
  && chmod +x /usr/local/bin/gomplate

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
