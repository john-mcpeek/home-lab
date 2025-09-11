#!/usr/bin/env bash

apt update && apt install -y dnsutils

cp -f ddns-key.conf /etc/
chown root:root /etc/ddns-key.conf
chmod 0600 /etc/ddns-key.conf

cp -f register-dns.sh /usr/local/bin/
chmod 0744 /usr/local/bin/register-dns.sh

systemctl daemon-reload
systemctl enable --now register-dns