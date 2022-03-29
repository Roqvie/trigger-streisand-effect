#!/bin/bash
#
# Installing tor for setuping bridge wuth
# obfs4 obfuscation proxy
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

if [[ `apt install wireguard curl net-tools iptables qrencode -y 2> /dev/null` ]]; then
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
wg genkey | sudo tee keys/server_private.key
SERVER_PRIVATE_KEY=$(cat keys/server_private.key)
sudo cat keys/server_private.key | wg pubkey | sudo tee keys/server_public.key
SERVER_PUBLIC_KEY=$(cat keys/server_public.key)
SERVER_PORT=$(random_unused_port)

mkdir -p generated
conf="[Interface]\nAddress = 10.0.0.1/24\nSaveConfig = true\nListenPort = ${SERVER_PORT}\nPrivateKey = ${SERVER_PRIVATE_KEY}\nPostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${INTERFACE} -j MASQUERADE\nPostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${INTERFACE} -j MASQUERADE\n"
                                                                                                                                       
> generated/wg0.conf
echo -e $conf > generated/wg0.conf
cp generated/wg0.conf /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf
dir=$(pwd)
echo " + Generated configuration for interface: /etc/wireguard/wg0.conf or ${dir}/generated/wg0.conf"
sudo wg-quick up wg0 2> /dev/null
sudo systemctl enable wg-quick@wg0 2> /dev/null
echo " + Enabled wg0 interface"


mkdir -p generated/wg-clients
for client_num in {2..11}; do
  echo " + Configuring ${client_num} client:"
  wg genkey | sudo tee keys/client_private.key
  CLIENT_PRIVATE_KEY=$(< keys/client_private.key)
  sudo cat keys/client_private.key | wg pubkey | sudo tee keys/client_public.key
  CLIENT_PUBLIC_KEY=$(< keys/client_public.key)
  client_conf="[Interface]\nPrivateKey = ${CLIENT_PRIVATE_KEY}\nAddress = 10.0.0.${client_num}/24\n\n[Peer]\nPublicKey = ${SERVER_PUBLIC_KEY}\nEndpoint = ${SERVER_IP}:${SERVER_PORT}\nAllowedIPs = 0.0.0.0/0"
   > generated/wg-clients/wireguard-client-${client_num}.conf
  echo -e $client_conf > generated/wg-clients/wireguard-client-${client_num}.conf
  peer_conf="\n[Peer]\nPublicKey = ${CLIENT_PUBLIC_KEY}\nAllowedIPs = 10.0.0.${client_num}/32"
  echo -e $peer_conf >> /etc/wireguard/wg0.conf
  wg set wg0 peer $CLIENT_PUBLIC_KEY allowed-ips 10.0.0.$client_num
  echo -e "\n    + Client ${client_num} conf file:\n      ${dir}/generated/wg-clients/wireguard-client-${client_num}.conf"
  qrencode -t ansiutf8 < generated/wg-clients/wireguard-client-${client_num}.conf
  qrencode -o generated/wg-clients/wireguard-client-${client_num}-qrcode.png < generated/wg-clients/wireguard-client-${client_num}.conf
done

echo -e " + Configured 10 clients\n + DONE\n"
