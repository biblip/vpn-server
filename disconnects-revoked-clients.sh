#!/bin/bash
set -e

EASYRSA_DIR=~/openvpn-ca
MGMT_HOST="127.0.0.1"
MGMT_PORT=7505

# === Check Management Interface ===
echo "[+] Connecting to OpenVPN management interface at $MGMT_HOST:$MGMT_PORT..."

MGMT_OUTPUT=$(echo -e "status\nquit" | nc "$MGMT_HOST" "$MGMT_PORT" 2>/dev/null)
if [ -z "$MGMT_OUTPUT" ]; then
  echo "  Could not connect to OpenVPN management interface."
  exit 1
fi

# === Parse Connected Clients ===
CONNECTED_CLIENTS=$(echo "$MGMT_OUTPUT" | grep '^CLIENT_LIST' | cut -d',' -f2)

if [ -z "$CONNECTED_CLIENTS" ]; then
  echo "   No currently connected clients."
  exit 0
fi

echo "[+] Found connected clients:"
echo "$CONNECTED_CLIENTS"
echo ""

# === Process Each Client ===
cd "$EASYRSA_DIR"
DISCONNECTED=()
SKIPPED=()

for CLIENT_NAME in $CONNECTED_CLIENTS; do
  if ./easyrsa show-cert "$CLIENT_NAME" 2>/dev/null | grep -q "Revocation Time"; then
    echo "  Revoked client detected: $CLIENT_NAME → disconnecting..."
    echo -e "kill $CLIENT_NAME\nquit" | nc "$MGMT_HOST" "$MGMT_PORT" >/dev/null
    DISCONNECTED+=("$CLIENT_NAME")
  else
    echo "  Client $CLIENT_NAME is active (not revoked)."
    SKIPPED+=("$CLIENT_NAME")
  fi
done

# === Report ===
echo "------------------------------------------------------------"
echo "  Disconnect Completed"

echo ""
echo "🔌 Disconnected (revoked):"
for name in "${DISCONNECTED[@]}"; do
  echo "  - $name"
done

echo ""
echo "  Still connected (valid cert):"
for name in "${SKIPPED[@]}"; do
  echo "  - $name"
done
echo "------------------------------------------------------------"
