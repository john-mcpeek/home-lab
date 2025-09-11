#!/bin/bash

DNS_SERVER=10.0.0.10
ZONE=lab
KEYFILE=/etc/ddns-key.conf
HOSTNAME=$(hostname)
TTL=600
INTERFACE=eth0
IP=$(ip --color=never -4 addr show $INTERFACE | grep -oP -m 1 '(?<=inet\s)\d+(\.\d+){3}')

nsupdate -k $KEYFILE << EOF
server $DNS_SERVER
zone $ZONE
update delete $HOSTNAME.$ZONE A
update add $HOSTNAME.$ZONE $TTL A $IP
send
EOF