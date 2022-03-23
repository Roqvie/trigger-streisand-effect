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

if [[ `apt install tor obfs4proxy iptables -y 2> /dev/null` ]]; then
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


readonly INTERFACE=$(ls /sys/class/net | grep ens)
readonly SERVER_IP=$(curl ifconfig.me 2> /dev/null)
echo " + Interface name: $INTERFACE"
echo " + Server ip address: $SERVER_IP"

sudo mv /etc/tor/torrc /etc/tor/torrc.sample
echo " + Backuping default tor config"

ORPort=$(random_unused_port)
OBFS_PORT=$(random_unused_port $ORPort)
echo " ! Generated port for obfs: ${ORPort}"
echo " ! Generated port for bridge: ${OBFS_PORT}"
echo -e "ExitPolicy reject *:*\nRunAsDaemon 1\nORPort ${ORPort}\nBridgeRelay 1\nPublishServerDescriptor 0\nServerTransportPlugin obfs3,obfs4 exec /usr/bin/obfs4proxy\nServerTransportListenAddr obfs4 0.0.0.0:${OBFS_PORT}\nExtORPort auto\nContactInfo x\nNickname x" > /etc/tor/torrc
echo " + Generated config for torrc"

iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport $OBFS_PORT -j ACCEPT
iptables -A PREROUTING -t nat -i $INTERFACE -p tcp --dport 443 -j REDIRECT --to-port $OBFS_PORT
echo " + Enabled iptables rules"

systemctl restart tor

FINGERPRINT=$(cat /var/lib/tor/fingerprint)
touch generated/tor-bridgeline.txt
cat /var/lib/tor/pt_state/obfs4_bridgeline.txt | tail -1 > generated/tor-bridgeline.txt
sed -i "s/<IP ADDRESS>/${SERVER_IP}/g" generated/tor-bridgeline.txt
sed -i "s/<PORT>/443/g" generated/tor-bridgeline.txt
sed -i "s/<FINGERPRINT>/${FINGERPRINT:2}/g" generated/tor-bridgeline.txt

BRIDGELINE=$(cat generated/tor-bridgeline.txt)
echo -e " + Generated bridgeline for client:\n\n   ${BRIDGELINE}\n"
echo -e " + DONE\n"
