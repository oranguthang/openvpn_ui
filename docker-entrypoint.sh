#!/bin/bash
set -e

EASY_RSA_LOC="/etc/openvpn/easyrsa"
SERVER_CERT="${EASY_RSA_LOC}/pki/issued/server.crt"
CONFIG_DIR="/etc/openvpn-ui"

OVPN_SRV_NET=${OVPN_SERVER_NET:-10.8.0.0}
OVPN_SRV_MASK=${OVPN_SERVER_MASK:-255.255.255.0}
OVPN_SRV_PORT=${OVPN_SERVER_PORT:-1194}
UI_PORT=${WEB_PORT:-8080}

echo "================================================"
echo "  OpenVPN UI - Starting..."
echo "================================================"

# Create config directory
mkdir -p ${CONFIG_DIR}

# Initialize EasyRSA and certificates if not exist
cd ${EASY_RSA_LOC}

if [ -e "$SERVER_CERT" ]; then
    echo "[INFO] Found existing certificates - reusing"
else
    echo "[INFO] Generating new certificates..."
    easyrsa init-pki
    cp -R /usr/share/easy-rsa/* ${EASY_RSA_LOC}/pki
    echo "ca" | easyrsa build-ca nopass
    easyrsa build-server-full server nopass
    openvpn --genkey secret ./pki/ta.key
    echo "[INFO] Certificates generated successfully"
fi

# Generate CRL
easyrsa gen-crl

# Set permissions
[ -d ${EASY_RSA_LOC}/pki ] && chmod 755 ${EASY_RSA_LOC}/pki
[ -f ${EASY_RSA_LOC}/pki/crl.pem ] && chmod 644 ${EASY_RSA_LOC}/pki/crl.pem

# Create CCD directory
mkdir -p /etc/openvpn/ccd

# Create TUN device if needed
mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
fi

# Setup NAT/iptables
echo "[INFO] Configuring iptables..."
iptables -t nat -A POSTROUTING -s ${OVPN_SRV_NET}/${OVPN_SRV_MASK} -o eth0 -j MASQUERADE 2>/dev/null || true
iptables -A FORWARD -i tun0 -o eth0 -j ACCEPT 2>/dev/null || true
iptables -A FORWARD -i eth0 -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Copy OpenVPN config
cp -f /etc/openvpn/setup/openvpn.conf /etc/openvpn/openvpn.conf

echo "[INFO] Starting OpenVPN server..."

# Start OpenVPN in background
openvpn --config /etc/openvpn/openvpn.conf \
    --client-config-dir /etc/openvpn/ccd \
    --management 127.0.0.1 8989 \
    --port ${OVPN_SRV_PORT} \
    --server ${OVPN_SRV_NET} ${OVPN_SRV_MASK} &

OPENVPN_PID=$!

# Wait for OpenVPN to start
sleep 2

if ! kill -0 $OPENVPN_PID 2>/dev/null; then
    echo "[ERROR] OpenVPN failed to start"
    exit 1
fi

echo "[INFO] OpenVPN started successfully"

# Calculate network CIDR
IFS='.' read -ra NET_PARTS <<< "$OVPN_SRV_NET"
IFS='.' read -ra MASK_PARTS <<< "$OVPN_SRV_MASK"
CIDR=0
for i in "${MASK_PARTS[@]}"; do
    case $i in
        255) CIDR=$((CIDR+8));;
        254) CIDR=$((CIDR+7));;
        252) CIDR=$((CIDR+6));;
        248) CIDR=$((CIDR+5));;
        240) CIDR=$((CIDR+4));;
        224) CIDR=$((CIDR+3));;
        192) CIDR=$((CIDR+2));;
        128) CIDR=$((CIDR+1));;
    esac
done
OVPN_NETWORK="${OVPN_SRV_NET}/${CIDR}"

echo "[INFO] Starting OpenVPN UI..."

# Start UI
exec /app/openvpn-ui \
    --listen.host=0.0.0.0 \
    --listen.port=${UI_PORT} \
    --easyrsa.path=${EASY_RSA_LOC} \
    --easyrsa.index-path=${EASY_RSA_LOC}/pki/index.txt \
    --openvpn.network=${OVPN_NETWORK} \
    --openvpn.server=127.0.0.1:${OVPN_SRV_PORT}:tcp \
    --ccd \
    --ccd.path=/etc/openvpn/ccd \
    --mgmt=127.0.0.1:8989
