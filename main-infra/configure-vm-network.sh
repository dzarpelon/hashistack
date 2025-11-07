#!/bin/bash

# Script to configure static IP on a VM via console
# Usage: ./configure-vm-network.sh <vm-name> <ip-address> <hostname>

VM_NAME=$1
IP_ADDR=$2
HOSTNAME=$3

if [ -z "$VM_NAME" ] || [ -z "$IP_ADDR" ] || [ -z "$HOSTNAME" ]; then
    echo "Usage: $0 <vm-name> <ip-address> <hostname>"
    echo "Example: $0 k8s-1 192.168.100.102 k8s-1.lab.dzarpelon.com"
    exit 1
fi

echo "Configuring $VM_NAME with IP $IP_ADDR and hostname $HOSTNAME"
echo "Please start the VM and run these commands manually:"
echo ""
echo "# Set hostname"
echo "sudo hostnamectl set-hostname $HOSTNAME"
echo ""
echo "# Configure static IP on enp0s9 (host-only network)"
echo "sudo nmcli con mod 'Wired connection 2' ipv4.addresses $IP_ADDR/24"
echo "sudo nmcli con mod 'Wired connection 2' ipv4.method manual"
echo "sudo nmcli con up 'Wired connection 2'"
echo ""
echo "# Verify"
echo "ip addr show enp0s9"
echo "hostname"
