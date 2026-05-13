# syntax=docker/dockerfile:1

FROM rust:bookworm AS rust-builder
WORKDIR /src
COPY native/transport native/transport
WORKDIR /src/native/transport
RUN cargo build -p ct_ffi --release

FROM dart:stable AS dart-builder
WORKDIR /src
COPY pubspec.yaml ./
COPY packages packages
RUN dart pub get
RUN mkdir -p /out \
    && dart compile exe packages/connectanum_router/bin/connectanum_router.dart -o /out/connectanum_router

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -r -u 10001 -g nogroup connectanum
RUN mkdir -p /app/lib /etc/connectanum /etc/connectanum/tls \
    && chown -R connectanum:nogroup /app /etc/connectanum

COPY --from=dart-builder /out/connectanum_router /app/connectanum_router
COPY --from=rust-builder /src/native/transport/target/release/libct_ffi.so /app/lib/libct_ffi.so

RUN chmod +x /app/connectanum_router \
    && chown -R connectanum:nogroup /app

ENV CONNECTANUM_NATIVE_LIB=/app/lib/libct_ffi.so

EXPOSE 8443
EXPOSE 9100

USER connectanum

ENTRYPOINT ["/app/connectanum_router"]
CMD ["--config", "/etc/connectanum/router.yaml"]
