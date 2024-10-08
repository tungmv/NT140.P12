#!/bin/sh

make -C /app/vpn
/app/vpn/vpnserver &
ip tuntap add dev tun0 mode tun
ip addr add 10.0.0.1/24 dev tun0
ip link set dev tun0 up
sysctl -w net.ipv4.ip_forward=1
ip route add 192.168.53.0/24 dev tun0

tail -f /dev/null