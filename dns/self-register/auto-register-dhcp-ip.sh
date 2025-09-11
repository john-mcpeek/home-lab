#!/usr/bin/env bash

apt update && apt install -y dnsutils

cp -f ddns-key.conf /etc/
chown root:root /etc/ddns-key.conf
chmod 0600 /etc/ddns-key.conf

cp -f ddns-update /etc/dhcp/dhclient-exit-hooks.d/
chmod 0744 /etc/dhcp/dhclient-exit-hooks.d/ddns-update