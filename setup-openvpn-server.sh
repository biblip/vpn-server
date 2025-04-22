#!/bin/bash
set -e

# === Variables ===
SERVER_CN="vpn-server"
ORG="Secure VPN"
EASYRSA_DIR=~/openvpn-ca
OUTPUT_DIR=/etc/openvpn/server

# === Install Dependencies ===
sudo apt update
sudo apt install openvpn easy-rsa iptables-persistent curl -y

# === Easy-RSA Setup ===
make-cadir "$EASYRSA_DIR"
cd "$EASYRSA_DIR"
./easyrsa init-pki
echo -ne "$ORG\n" | ./easyrsa build-ca nopass

./easyrsa gen-req "$SERVER_CN" nopass
echo -ne "yes\n" | ./easyrsa sign-req server "$SERVER_CN"
./easyrsa gen-dh

# === Copy Credentials ===
sudo cp pki/ca.crt pki/private/$SERVER_CN.key pki/issued/$SERVER_CN.crt pki/dh.pem "$OUTPUT_DIR"

# === OpenVPN Server Config ===
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
sudo sed -i '/^#net.ipv4.ip_forward=1/s/^#//' /etc/sysctl.conf
sudo sysctl -p

# === Configure NAT ===
sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -d 10.0.0.0/16 -o eth0 -j MASQUERADE
sudo iptables-save | sudo tee /etc/iptables/rules.v4

# === Enable and Start OpenVPN ===
sudo systemctl enable openvpn-server@server
sudo systemctl start openvpn-server@server

echo "OpenVPN server setup complete."
