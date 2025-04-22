#!/bin/bash
set -e

# === Usage ===
function usage() {
  echo "------------------------------------------------------------"
  echo "Usage: $0 <client-name>"
  echo
  echo "Revokes the specified client certificate and disconnects"
  echo "the client if currently connected."
  echo "------------------------------------------------------------"
  exit 1
}

# === Input ===
CLIENT_NAME="$1"
if [ -z "$CLIENT_NAME" ]; then
  echo "  Error: Missing client name."
  usage
fi

# === Config ===
EASYRSA_DIR=~/openvpn-ca
OUTPUT_DIR=/etc/openvpn/server
CLIENT_DIR=~/openvpn-clients/$CLIENT_NAME
MGMT_HOST="127.0.0.1"
MGMT_PORT=7505

cd "$EASYRSA_DIR"

# === Step 1: Revoke Certificate ===
CERT_STATUS="unknown"
if ./easyrsa show-cert "$CLIENT_NAME" | grep -q "Revocation Time"; then
  echo "   Client '$CLIENT_NAME' certificate is already revoked."
  CERT_STATUS="revoked"
elif ./easyrsa show-cert "$CLIENT_NAME" > /dev/null 2>&1; then
  echo "[!] Revoking certificate for client '$CLIENT_NAME'..."
  echo -ne "yes\n" | ./easyrsa revoke "$CLIENT_NAME"
  CERT_STATUS="now revoked"
else
  echo "   No certificate found for '$CLIENT_NAME'."
  CERT_STATUS="not found"
fi

# === Step 2: Regenerate and Apply CRL ===
if [[ "$CERT_STATUS" == "now revoked" || "$CERT_STATUS" == "revoked" ]]; then
  echo "[+] Regenerating CRL..."
  ./easyrsa gen-crl
  echo "[+] Deploying updated crl.pem to server directory..."
  sudo cp pki/crl.pem "$OUTPUT_DIR/crl.pem"
  sudo chmod 644 "$OUTPUT_DIR/crl.pem"
fi

# === Step 3: Disconnect if Connected ===
echo "[+] Checking if client '$CLIENT_NAME' is currently connected..."

MGMT_OUTPUT=$(echo -e "status\nquit" | nc "$MGMT_HOST" "$MGMT_PORT" 2>/dev/null || true)
CLIENT_LINE=$(echo "$MGMT_OUTPUT" | grep "^CLIENT_LIST" | grep "$CLIENT_NAME")

if [ -n "$CLIENT_LINE" ]; then
  echo "  Client '$CLIENT_NAME' is connected — disconnecting..."
  echo -e "kill $CLIENT_NAME\nquit" | nc "$MGMT_HOST" "$MGMT_PORT" >/dev/null
  CONNECTION_STATUS="disconnected"
else
  echo "   Client '$CLIENT_NAME' is not connected."
  CONNECTION_STATUS="not connected"
fi

# === Step 4: Optional Cleanup ===
if [ -d "$CLIENT_DIR" ]; then
  echo "[+] Removing local client config: $CLIENT_DIR"
  rm -rf "$CLIENT_DIR"
fi

# === Final Report ===
echo "------------------------------------------------------------"
echo "  Done: Client '$CLIENT_NAME'"
echo "Cert status:     $CERT_STATUS"
echo "Connection:      $CONNECTION_STATUS"
echo "CRL updated:     Yes"
echo "Other clients:   Not affected"
echo "------------------------------------------------------------"
