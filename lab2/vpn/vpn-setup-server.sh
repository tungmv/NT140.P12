#!/bin/sh

set -e

# Compile the VPN server
make -C /app/vpn

# Check if the TUN device exists
if [ ! -c /dev/net/tun ]; then
    echo "TUN device does not exist. Need to create it..."
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
    chmod 600 /dev/net/tun
fi

# Start the VPN server in the background
/app/vpn/vpnserver &

## Create and configure the tun0 interface
#ip tuntap add dev tun0 mode tun || echo "tun0 device already exists"
#ip addr add 10.0.0.1/24 dev tun0 || echo "IP address already assigned to tun0"
#ip link set dev tun0 up

## Enable IP forwarding
#sysctl -w net.ipv4.ip_forward=1 || echo "Failed to enable IP forwarding"

## Set up NAT for VPN clients
#iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE || echo "NAT rule already exists"

# Keep the script running
tail -f /dev/null
