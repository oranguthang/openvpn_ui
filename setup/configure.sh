#!/usr/bin/env bash
set -e

EASY_RSA_LOC="/etc/openvpn/easyrsa"
SERVER_CERT="${EASY_RSA_LOC}/pki/issued/server.crt"

OPENVPN_SRV_NET=${OPENVPN_SERVER_NET:-10.8.0.0}
OPENVPN_SRV_MASK=${OPENVPN_SERVER_MASK:-255.255.255.0}
OPENVPN_SRV_PORT=${OPENVPN_SERVER_PORT:-1194}

cd $EASY_RSA_LOC

if [ -e "$SERVER_CERT" ]; then
    echo "Found existing certs - reusing"
else
    echo "Generating new certs"
    easyrsa init-pki
    cp -R /usr/share/easy-rsa/* $EASY_RSA_LOC/pki
    echo "ca" | easyrsa build-ca nopass
    easyrsa build-server-full server nopass
    openvpn --genkey secret ./pki/ta.key
fi

easyrsa gen-crl

[ -d $EASY_RSA_LOC/pki ] && chmod 755 $EASY_RSA_LOC/pki
[ -f $EASY_RSA_LOC/pki/crl.pem ] && chmod 644 $EASY_RSA_LOC/pki/crl.pem

mkdir -p /etc/openvpn/ccd
mkdir -p /dev/net

if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
fi

cp -f /etc/openvpn/setup/openvpn.conf /etc/openvpn/openvpn.conf

openvpn --config /etc/openvpn/openvpn.conf \
    --client-config-dir /etc/openvpn/ccd \
    --management 127.0.0.1 8989 \
    --port ${OPENVPN_SRV_PORT} \
    --server ${OPENVPN_SRV_NET} ${OPENVPN_SRV_MASK}
