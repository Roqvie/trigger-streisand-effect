#!/bin/bash
#
# Installing shadowsocks proxy server with
# v2ray plugin for websocket obfuscation
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

if [[ `apt install qrencode net-tools iptables -y 2> /dev/null` ]]; then
  echo ' + Pre-requirements installed: OK'
else
  echo ' - Error while installing pre-requirements' >$2
  exit 1
fi

readonly INTERFACE=$(ls /sys/class/net | grep ens)
readonly SERVER_IP=$(curl ifconfig.me 2> /dev/null)
echo " + Interface name: $INTERFACE"
echo " + Server ip address: $SERVER_IP"


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

if [[ `apt install shadowsocks-libev -y 2> /dev/null` ]]; then
  echo ' + Shadowsocks packet installed: OK'
else
  echo ' - Error while installing' >$2
  exit 1
fi


wget -q https://github.com/shadowsocks/v2ray-plugin/releases/download/v1.1.0/v2ray-plugin-linux-amd64-v1.1.0.tar.gz 
echo ' + v2ray plugin downloaded: OK'

tar -xf v2ray-plugin-linux-amd64-v1.1.0.tar.gz
rm  v2ray-plugin-linux-amd64-v1.1.0.tar.gz
sudo mv v2ray-plugin_linux_amd64 /etc/shadowsocks-libev/v2ray-plugin
sudo chmod +x  /etc/shadowsocks-libev/v2ray-plugin

sudo setcap 'cap_net_bind_service=+eip' /etc/shadowsocks-libev/v2ray-plugin
sudo setcap 'cap_net_bind_service=+ep' /etc/shadowsocks-libev/v2ray-plugin
sudo setcap 'cap_net_bind_service=+ep' /usr/bin/ss-server


readonly PORT=$(random_unused_port)
readonly PASSWORD=$(date +%s | sha256sum | base64 | head -c 32 ; echo)
echo " + Generated port for shadowsocks"
echo " + Generated password for shadowsocks"

mkdir -p generated
cp samples/ss-config.json generated/ss-config.json
sed -i "s/<SERVER_IP>/${SERVER_IP}/g" generated/ss-config.json
sed -i "s/<PORT>/${PORT}/g" generated/ss-config.json
sed -i "s/<PASSWORD>/${PASSWORD}/g" generated/ss-config.json
cp generated/ss-config.json /etc/shadowsocks-libev/config.json
echo " + Generated shadowsocks server config"

sudo systemctl restart shadowsocks-libev
echo -e " ! Shadowsocks + v2ray proxy config\n\n   Server Addr: ${SERVER_IP}\n   Server Port: ${PORT}\n   Password: ${PASSWORD}\n   Encryption: aes-256-cfb\n   Plugin Program: v2ray.exe\n   v2ray host: ${SERVER_IP}\n\n"
B_STR='ss://'`echo -n "aes-256-cfb:${PASSWORD}@${SERVER_IP}:${PORT}" | base64 -w0`

echo -n $B_STR | qrencode -t ansiutf8
qrencode -o shadowsocks-client.png $B_STR
dir=$(pwd) 
echo -e "\n\n ! QR code saved to ${dir}/shadowsocks-client.png\n"
echo -e " + Done\n"
