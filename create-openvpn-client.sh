#!/bin/bash
set -e

# === Input ===
SERVER_DOMAIN="$1"
CLIENT_NAME="$2"
CAPABILITY="$3" # Optional: --internet

# === Usage Function ===
function usage() {
  echo "------------------------------------------------------------"
  echo "Usage: $0 <server-domain-or-ip> <client-name> [--internet]"
  echo
  echo "Arguments:"
  echo "  server-domain-or-ip   The domain or IP of your VPN server"
  echo "  client-name           Name for the client (no spaces)"
  echo "  --internet            (Optional) Route all traffic through VPN"
  echo
  echo "Examples:"
  echo "  $0 vpn.example.com alice"
  echo "  $0 10.0.200.226 bob --internet"
  echo "------------------------------------------------------------"
  exit 1
}

# === Validate Inputs ===
if [ -z "$SERVER_DOMAIN" ] || [ -z "$CLIENT_NAME" ]; then
  echo "  Error: Missing required arguments."
  usage
fi

# === Validate Optional Flag ===
if [ -n "$CAPABILITY" ] && [ "$CAPABILITY" != "--internet" ]; then
  echo "  Error: Unknown flag '$CAPABILITY'"
  usage
fi

echo "  Server: $SERVER_DOMAIN"
echo "  Client: $CLIENT_NAME"
if [ "$CAPABILITY" == "--internet" ]; then
  echo "  Capability: Full internet routing enabled"
else
  echo "  Capability: LAN-only access"
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

# === Create client config ===
cat > "$OUTPUT_DIR/$CLIENT_NAME.ovpn" <<EOF
client
dev tun
proto udp
remote $SERVER_DOMAIN 1194
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
