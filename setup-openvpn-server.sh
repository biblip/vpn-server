#!/bin/bash
set -e

# === Configuration ===
SERVER_CN="vpn-server"
ORG="Secure VPN"
EASYRSA_DIR=~/openvpn-ca
OUTPUT_DIR=/etc/openvpn/server
# === Vpn ===
VPN_SUBNET="10.8.0.0/24"
# === Lan ===
LAN_SUBNET="10.0.0.0/16"
LAN_PROBE_IP="10.0.0.1"

LAN_INTERFACE=$(ip route get "$LAN_PROBE_IP" | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')

if [ -z "$LAN_INTERFACE" ]; then
  echo "❌ Could not detect LAN interface. Please set LAN_INTERFACE manually."
  exit 1
fi

# === Help ===
function usage() {
    echo "-----------------------------------------------------------"
    echo " OpenVPN Server Installer"
    echo "-----------------------------------------------------------"
    echo "Sets up an OpenVPN server on Ubuntu."
    echo ""
    echo "VPN clients will be assigned IPs in: $VPN_SUBNET"
    echo "They will have access to LAN: $LAN_SUBNET"
    echo "Make sure your LAN router or devices know to route traffic"
    echo "for $VPN_SUBNET via the VPN server IP (e.g., 10.0.200.226)."
    echo ""
    echo "To persist iptables rules: they are saved to /etc/iptables/rules.v4"
    echo "-----------------------------------------------------------"
    echo ""
}

usage

# === Install Dependencies ===
echo "[+] Installing OpenVPN, Easy-RSA, and iptables-persistent..."
sudo apt update
sudo apt install openvpn easy-rsa iptables-persistent curl -y

# === Easy-RSA Setup ===
echo "[+] Initializing PKI with Easy-RSA..."
make-cadir "$EASYRSA_DIR"
cd "$EASYRSA_DIR"
./easyrsa init-pki
echo -ne "$ORG\n" | ./easyrsa build-ca nopass
./easyrsa gen-req "$SERVER_CN" nopass
echo -ne "yes\n" | ./easyrsa sign-req server "$SERVER_CN"
./easyrsa gen-dh

# === Copy Credentials ===
echo "[+] Copying server credentials to OpenVPN directory..."
sudo cp pki/ca.crt pki/private/$SERVER_CN.key pki/issued/$SERVER_CN.crt pki/dh.pem "$OUTPUT_DIR"

# === OpenVPN Server Config ===
echo "[+] Writing OpenVPN server config..."
sudo tee "$OUTPUT_DIR/server.conf" > /dev/null <<EOF
port 1194
proto udp
dev tun
ca ca.crt
cert $SERVER_CN.crt
key $SERVER_CN.key
dh dh.pem
server 10.8.0.0 255.255.255.0
push "route 10.0.0.0 255.255.0.0"
ifconfig-pool-persist ipp.txt
keepalive 10 120
persist-key
persist-tun
status openvpn-status.log
verb 3
explicit-exit-notify 1
EOF

# === Enable IP Forwarding ===
echo "[+] Enabling IP forwarding..."
sudo sed -i '/^#net.ipv4.ip_forward/s/^#//' /etc/sysctl.conf
sudo sysctl -p

# === Configure NAT ===
echo "[+] Setting up iptables MASQUERADE rule for VPN subnet access..."
sudo iptables -t nat -A POSTROUTING -s "$VPN_SUBNET" -d "$LAN_SUBNET" -o "$LAN_INTERFACE" -j MASQUERADE
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null

# === Start OpenVPN ===
echo "[+] Enabling and starting OpenVPN service..."
sudo systemctl enable openvpn-server@server
sudo systemctl start openvpn-server@server

# === Final Output ===
echo "-----------------------------------------------------------"
echo "  OpenVPN server setup complete!"
echo ""
echo "   VPN Subnet: $VPN_SUBNET"
echo "  LAN Subnet: $LAN_SUBNET"
echo ""
echo "  Make sure devices in $LAN_SUBNET can reach VPN clients."
echo "    - On LAN router or gateway, add a route:"
echo "      Destination: $VPN_SUBNET"
echo "      Next hop:    [LAN IP of VPN server, e.g., 10.0.200.226]"
echo ""
echo "  iptables rules saved and will persist after reboot."
echo "-----------------------------------------------------------"
