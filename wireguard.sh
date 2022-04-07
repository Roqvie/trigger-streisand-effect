#!/bin/bash
#
# Installing wireguard server and
# generatying client conf files
#


#   PREREQUIREMENTS
#
# + Updating system packages,
# + Installing requirements
# + Define major constants
if [[ `apt update -y 2> /dev/null` ]]; then
  echo ' + APT updated: OK'
else
  echo ' - Error while updating APT' >$2
  exit 1
fi

if [[ `apt install curl net-tools wireguard iptables qrencode -y 2> /dev/null` ]]; then
  echo ' + Pre-requirements installed: OK'
else
  echo ' - Error while installing pre-requirements' >$2
  exit 1
fi


# Generating random port that not in use in current system
# Arguments:
#   - ports (port for excluding)
# Return:
#   - port (generated port)
function random_unused_port() {
  ports_in_use=($(netstat -ltn | sed -rne '/^tcp/{/:(22|25)\>/d;s/.*:([0-9]+)\>.*/\1/p}'))
  exclude_ports=("$@")
  random_port=$(shuf -i 10000-59999 -n 1)
  while [[ " ${ports_in_use[@]} " =~ " ${random_port} " || " ${exclude_ports[@]} " =~ " ${random_port} " ]]; do
    $random_port=$(shuf -i 10000-59999 -n 1)
  done
  echo $random_port
}


readonly INTERFACE=$(ls /sys/class/net | grep ens | head -n 1 2> /dev/null)
readonly SERVER_IP=$(curl ifconfig.me 2> /dev/null)
echo " + Interface name: $INTERFACE"
echo " + Server ip address: $SERVER_IP"

echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p > /dev/null
echo " + Enabled ip forwarding"

mkdir -p keys
wg genkey | tee "keys/server_private.key" | wg pubkey | tee "keys/server_public.key" >/dev/null 2>&1
SERVER_PRIVATE_KEY=$(cat keys/server_private.key)
SERVER_PUBLIC_KEY=$(cat keys/server_public.key)
SERVER_PORT=$(random_unused_port)

# Generate server interface config
mkdir -p generated

cat <<-EOF > "generated/wg0.conf"
[Interface]
Address = 10.0.0.1/24
SaveConfig = true
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${INTERFACE} -j MASQUERADE\n
EOF

cp generated/wg0.conf /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf
dir=$(pwd)
echo " + Generated configuration for interface: /etc/wireguard/wg0.conf or ${dir}/generated/wg0.conf"
sudo wg-quick up wg0 2> /dev/null
sudo systemctl enable wg-quick@wg0 2> /dev/null
echo " + Enabled wg0 interface"


# Configuring client peers
mkdir -p generated/wg-clients
for client_num in {1..10}; do
  echo " + Configuring ${client_num} client:"
  client_interface_ip=$((client_num+1))

  # Generating keys
  wg genkey | tee "keys/client${client_num}_private.key" | wg pubkey | tee "keys/client${client_num}_public.key" >/dev/null 2>&1
  wg genpsk | tee "keys/client${client_num}.psk" >/dev/null 2>&1
  CLIENT_PRIVATE_KEY=$(< "keys/client${client_num}_private.key")
  CLEINT_PUBLIC_KEY=$(< "keys/client${client_num}_public.key")
  
  # Generating client config's
  cat <<-EOF > "generated/wg-clients/client${client_num}.conf"
  [Interface]
  Address = 10.0.0.${client_interface_ip}/32
  PrivateKey = $(cat "keys/client${client_num}_private.key")
  DNS = 1.1.1.1

  [Peer]
  PublicKey = $(cat "keys/server_public.key")
  PresharedKey = $(cat "keys/client${client_num}.psk")
  PersistentKeepalive = 25
  AllowedIPs = 0.0.0.0/0, ::/0
  Endpoint = ${SERVER_IP}:${SERVER_PORT}
  EOF

  # Enabling peer
  wg set wg0 peer $CLIENT_PUBLIC_KEY allowed-ips 10.0.0.$client_interface_ip
  echo -e "\n    + Client ${client_num} conf file:\n      ${dir}/generated/wg-clients/client${client_num}.conf"
  
  # QR-codes for clients
  qrencode -t ansiutf8 < generated/wg-clients/wireguard-client-${client_num}.conf
  qrencode -o generated/wg-clients/wireguard-client-${client_num}-qrcode.png < generated/wg-clients/wireguard-client-${client_num}.conf
done

echo -e " + Configured 10 clients\n + DONE\n"
