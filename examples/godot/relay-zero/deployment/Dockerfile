FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash ca-certificates libatomic1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY build/server/relay-zero-server.x86_64 /app/relay-zero-server.x86_64
COPY build/server/relay-zero-server.pck /app/relay-zero-server.pck
COPY deployment/entrypoint.sh /app/entrypoint.sh
RUN chmod 0755 /app/entrypoint.sh /app/relay-zero-server.x86_64

EXPOSE 9080/tcp
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/${PORT:-9080}' || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
