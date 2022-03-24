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

if [[ `apt install wireguard iptables qrencode -y 2> /dev/null` ]]; then
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
  while [[ " ${ports_in_use[@]} " =~ " ${random_port} " || " ${exclude_ports[@]} " =~ " ${random_port} "$    $random_port=$(shuf -i 10000-59999 -n 1)
  done
  echo $random_port
}


readonly INTERFACE=$(ls /sys/class/net | grep ens 2> /dev/null)
readonly SERVER_IP=$(curl ifconfig.me 2> /dev/null)
echo " + Interface name: $INTERFACE"
echo " + Server ip address: $SERVER_IP"

echo -e "net.ipv4.ip_forward = 1\n" >> /etc/sysctl.conf
sysctl -p 2> /dev/null
echo " + Enabled ip forwarding"

mkdir -p keys
wg genkey | sudo tee keys/server_private.key | wg pubkey | sudo tee keys/server_public.key 2> /dev/null
SERVER_PRIVATE_KEY=$(echo -n < keys/server_private.key)
SERVER_PUBLIC_KEY=$(echo -n < keys/server_public.key)
SERVER_PORT=$(random_unused_port)

mkdir -p generated
cp samples/wg0.conf generated/wg0.conf
sed -i "s/<SERVER_PORT>/${SERVER_PORT}/g" generated/wg0.conf
sed -i "s/<SERVER_PRIVATE_KEY>/${SERVER_PRIVATE_KEY}/g" generated/wg0.conf
sed -i "s/<INTERFACE>/${INTERFACE}/g" generated/wg0.conf
cp generated/wg0.conf /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/{privatekey,wg0.conf}
dir=$(pwd)
echo " + Generated configuration for interface: /etc/wireguard/wg0.conf or ${dir}/generated/wg0.conf"
sudo wg-quick up wg0
sudo systemctl enable wg-quick@wg0
echo " + Enabled wg0 interface"


mkdor -p generated/wg-clients
for client_num in {2..11}; do
  echo " + Configuring ${client_num} client:"
  wg genkey | sudo tee keys/client_private_$client_num.key | wg pubkey | sudo tee keys/client_public_$client_num.key
  local CLIENT_PRIVATE_KEY=$(cat keys/client_private_$client_num.key)
  local CLIENT_PUBLIC_KEY=$(cat client_public_$client_num.key)
  cp samples/wireguard-client.conf generated/wg-clients/wireguard-client-${client_num}.conf
  sed -i "s/<CLIENT_PRIVATE_KEY>/${CLIENT_PRIVATE_KEY}/g" generated/wg-clients/wireguard-client-${client_num}.conf
  sed -i "s/<CLIENT_NUM>/${client_num}/g" generated/wg-clients/wireguard-client-${client_num}.conf
  sed -i "s/<SERVER_PUBLIC_KEY>/${SERVER_PUBLIC_KEY}/g" generated/wg-clients/wireguard-client-${client_num}.conf
  sed -i "s/<SERVER_IP_ADDRESS>/${SERVER_IP}/g" generated/wg-clients/wireguard-client-${client_num}.conf
  sed -i "s/<SERVER_PORT>/${SERVER_PORT}/g" generated/wg-clients/wireguard-client-${client_num}.conf
  wg set wg0 peer $CLIENT_PUBLIC_KEY allowed-ips 10.0.0.$client_num
  echo -e "\n    + Client ${client_num} conf file:\n      ${dir}/generated/wg-clients/wireguard-client-${client_num}.conf"
  qrencode -t ansiutf8 < generated/wg-clients/wireguard-client-${client_num}.conf
  qrencode -o generated/wg-clients/wireguard-client-${client_num}-qrcode.png < generated/wg-clients/wireguard-client-${client_num}.conf
done

echo -e " + Configured 10 clients\n + DONE\n"
