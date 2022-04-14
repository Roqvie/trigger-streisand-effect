#!/bin/bash
#
# Installing wireguard server and
# generatying client conf files
#


# Check a user is root
if [ "$(id -u)" != 0 ]; then
  echo " - Please, run the script as root: 'sudo wireguard.sh'"
  exit 1
fi

# Exit on errors and dont display commands output
set -e
set +x

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

if [[ `apt install software-properties-common curl net-tools wireguard iptables qrencode -y 2> /dev/null` ]]; then
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

readonly INTERFACE=$(route -n | awk '$1 == "0.0.0.0" {print $8}')
readonly SERVER_IP=$(curl ifconfig.me 2> /dev/null)
readonly SERVER_PORT=$(random_unused_port)
echo " + Interface name: $INTERFACE"
echo " + Server ip address: $SERVER_IP"
echo " + Port for wireguard server: $SERVER_IP"


#   GENERATING CONFIGS
# + Generate server and client keys
# + Generate server interface config
# + Generate client configs
mkdir -p keys
wg genkey | tee "keys/server_private.key" | wg pubkey | tee "keys/server_public.key" >/dev/null 2>&1
SERVER_PRIVATE_KEY=$(cat keys/server_private.key)
SERVER_PUBLIC_KEY=$(cat keys/server_public.key)

mkdir -p generated
mkdir -p generated/wg-clients
cat > "generated/wg0.conf" <<EOL
[Interface]
Address = 10.0.0.1/24
SaveConfig = true
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${INTERFACE} -j MASQUERADE
EOL

# Generate client interface configs
for client_num in {1..10}; do
  echo " + Generating ${client_num} client:"
  client_interface_ip=10.0.0.$((client_num+1))/32

  wg genkey | tee "keys/client${client_num}_private.key" | wg pubkey | tee "keys/client${client_num}_public.key" >/dev/null 2>&1
  client_private_key=$(< "keys/client${client_num}_private.key")
  client_public_key=$(< "keys/client${client_num}_public.key")
  
  cat > "generated/wg-clients/client${client_num}.conf" <<EOL
[Interface]
Address = ${client_interface_ip}
PrivateKey = ${client_private_key}
DNS = 1.1.1.1

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
PersistentKeepalive = 25
AllowedIPs = 0.0.0.0/0
Endpoint = ${SERVER_IP}:${SERVER_PORT}
EOL

  cat >> "generated/wg0.conf" <<EOL
[Peer]
PublicKey = ${client_public_key}
AllowedIPs = ${client_interface_ip}
EOL
done

#   ENABLING INTERFACE AND SERVICE
# + Setup permissions for configs
# + Adding iptables rules
# + Enabling wg interface
mv -v generated/wg0.conf /etc/wireguard/
chown -v root:root /etc/wireguard/wg0.conf
chmod -v 600 /etc/wireguard/wg0.conf

iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p udp -m udp --dport $SERVER_PORT -m conntrack --ctstate NEW -j ACCEPT
iptables -A INPUT -s 10.0.0.0/24 -p tcp -m tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
iptables -A INPUT -s 10.0.0.0/24 -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT

wg-quick up wg0
systemctl enable wg-quick@wg0

sysctl net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf

# QR-codes for clients
for client_num in {1..10}; do
  qrencode -t ansiutf8 < generated/wg-clients/wireguard-client-${client_num}.conf
  qrencode -o generated/wg-clients/wireguard-client-${client_num}-qrcode.png < generated/wg-clients/wireguard-client-${client_num}.conf
done 
echo -e " + Configured 10 clients\n + DONE\n"
