# ========================================================
# Stage 1: Build Frontend
# ========================================================
FROM node:18-alpine AS frontend-builder
WORKDIR /app
COPY frontend/package*.json ./
RUN npm install
COPY frontend/ ./
RUN npm run build

# ========================================================
# Stage 2: Build Backend
# ========================================================
FROM golang:1.21-alpine AS backend-builder
WORKDIR /app

RUN apk add --no-cache git build-base

# Install packr2
RUN go install github.com/gobuffalo/packr/v2/packr2@latest

# Copy frontend build
COPY --from=frontend-builder /app/static /app/frontend/static

# Copy backend source
COPY backend/ ./

# Build
ARG TARGETARCH
RUN packr2 && \
    CGO_ENABLED=1 GOOS=linux GOARCH=${TARGETARCH} \
    go build -a -tags netgo -ldflags '-linkmode external -extldflags -static -s -w' \
    -o openvpn_ui && \
    packr2 clean

# ========================================================
# Stage 3: Final Image
# ========================================================
FROM alpine:3.18

LABEL maintainer="OpenVPN UI"
LABEL description="OpenVPN server with Web UI"

WORKDIR /app

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    openvpn \
    easy-rsa \
    openssl \
    coreutils \
    iptables \
    ip6tables \
    ca-certificates \
    tzdata \
    && ln -s /usr/share/easy-rsa/easyrsa /usr/local/bin \
    && rm -rf /tmp/* /var/tmp/* /var/cache/apk/*

# Copy built binary
COPY --from=backend-builder /app/openvpn_ui /app/openvpn_ui

# Copy templates
COPY templates/ /app/templates/

# Copy setup scripts
COPY setup/ /etc/openvpn/setup/

# Copy entrypoint
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh /app/openvpn_ui

# Environment variables
ENV OPENVPN_SERVER_NET=10.8.0.0
ENV OPENVPN_SERVER_MASK=255.255.255.0
ENV OPENVPN_SERVER_PORT=1194
ENV WEB_PORT=8080
ENV ADMIN_USERNAME=""
ENV ADMIN_PASSWORD=""
ENV DOMAIN=""
ENV TZ=UTC

# Volumes
VOLUME ["/etc/openvpn/easyrsa", "/etc/openvpn/ccd", "/etc/openvpn-ui"]

# Expose ports (actual ports configured via env)
EXPOSE 1194/udp 1194/tcp 8080 443

ENTRYPOINT ["/app/docker-entrypoint.sh"]
