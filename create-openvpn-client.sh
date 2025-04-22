#!/bin/bash
set -e

CLIENT_NAME="$1"
CAPABILITY="$2" # Optional: --internet

if [ -z "$CLIENT_NAME" ]; then
  echo "Usage: $0 <client-name> [--internet]"
  exit 1
fi

EASYRSA_DIR=~/openvpn-ca
OUTPUT_DIR=~/openvpn-clients/$CLIENT_NAME
mkdir -p "$OUTPUT_DIR"
cd "$EASYRSA_DIR"

# === Create client cert/key ===
./easyrsa gen-req "$CLIENT_NAME" nopass
echo -ne "yes\n" | ./easyrsa sign-req client "$CLIENT_NAME"

# === Copy certs ===
cp "pki/private/$CLIENT_NAME.key" "$OUTPUT_DIR/"
cp "pki/issued/$CLIENT_NAME.crt" "$OUTPUT_DIR/"
cp "pki/ca.crt" "$OUTPUT_DIR/"

# === Get public IP ===
SERVER_IP=$(curl -s ifconfig.me)

# === Create client config ===
cat > "$OUTPUT_DIR/$CLIENT_NAME.ovpn" <<EOF
client
dev tun
proto udp
remote $SERVER_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
verb 3

<ca>
$(cat "$OUTPUT_DIR/ca.crt")
</ca>
<cert>
$(cat "$OUTPUT_DIR/$CLIENT_NAME.crt")
</cert>
<key>
$(cat "$OUTPUT_DIR/$CLIENT_NAME.key")
</key>
EOF

# === Add full tunnel option if specified ===
if [ "$CAPABILITY" == "--internet" ]; then
  echo "redirect-gateway def1" >> "$OUTPUT_DIR/$CLIENT_NAME.ovpn"
fi

echo "Client '$CLIENT_NAME' created at: $OUTPUT_DIR/$CLIENT_NAME.ovpn"
