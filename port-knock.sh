#!/bin/bash


# PREREQUIREMENTS
#
# + Updating system packages,
# + Installing requirements
# + Define major constants
#
if [[ `apt update -y 2> /dev/null` ]]; then
	echo ' + APT updated: OK'
else
	echo ' - Error while updating APT'
	exit 1
fi

if [[ `apt install net-tools iptables -y 2> /dev/null` ]]; then
        echo ' + Pre-requirements installed: OK'
else
        echo ' - Error while installing pre-requirements'
	exit 1
fi

readonly INTERFACE=$(ls /sys/class/net | grep ens)
echo " + Interface name: $INTERFACE"


# PORT-KNOCKING
#
# + Setup port-knocking for the SSH connection
# + Generating random ports for knocking
# + Setuping configs for knockd
#
function random_unused_port() {
	ports_in_use=($(netstat -ltn | sed -rne '/^tcp/{/:(22|25)\>/d;s/.*:([0-9]+)\>.*/\1/p}'))
	exclude_ports=("$@")
	port=$(shuf -i 10000-59999 -n 1)
	while [[ " ${ports_in_use[@]} " =~ " ${port} " || " ${exclude_ports[@]} " =~ " ${port} " ]]
	do
		$port=$(shuf -i 10000-59999 -n 1)
	done
	echo $port
}

if [[ `sudo apt install knockd -y 2> /dev/null` ]]; then
        echo ' + knockd installed: OK'
else
        echo ' - Error while installing knockd'
        exit 1
fi

KNOCK_PORT_1=$(random_unused_port)
KNOCK_PORT_2=$(random_unused_port "${KNOCK_PORT_1}")
KNOCK_PORT_3=$(random_unused_port "${KNOCK_PORT_1}" "${KNOCK_PORT_2}")
echo "    + Generated ports for knocking sequence: ${KNOCK_PORT_1} <-> ${KNOCK_PORT_2} <-> ${KNOCK_PORT_3}"

mkdir -p generated
cp samples/knockd.conf generated/knockd.conf
sed -i "s/<KNOCK_PORT_1>/${KNOCK_PORT_1}/g" generated/knockd.conf
sed -i "s/<KNOCK_PORT_2>/${KNOCK_PORT_2}/g" generated/knockd.conf
sed -i "s/<KNOCK_PORT_3>/${KNOCK_PORT_3}/g" generated/knockd.conf
cp generated/knockd.conf /etc/knockd.conf

cp samples/knockd generated/knockd
sed -i "s/<YOUR_INTERFACE>/${INTERFACE}/g" generated/knockd
cp generated/knockd /etc/default/knockd

echo '    + Generated conf files for knockd: /etc/default/knockd and /etc/default/knockd'


iptables -I INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
echo '    + Created iptables rule for keep current connections established: OK'

iptables -I INPUT -p tcp --destination-port 22 -j DROP
echo '    + Created iptables rule for block connections on ssh(22) port: OK'

iptables-save > /etc/iptables/rules.v4
echo '    + Saved iptables rule for blocking ssh port: OK'

systemctl start knockd
systemctl enable knockd
echo '    + knockd service started: OK'
