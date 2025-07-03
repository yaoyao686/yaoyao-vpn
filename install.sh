#!/bin/bash
# Auto L2TP/IPSec VPN install script with fixed config
# Author: yaoyao686

VPN_IP_RANGE="192.168.18"
VPN_USER="yaoyao686"
VPN_PASS="yaoyao686"
VPN_PSK="yaoyao686"

# Ensure running as root
[[ $EUID -ne 0 ]] && echo "Please run as root." && exit 1

# Install dependencies
yum -y install epel-release
yum -y install ppp xl2tpd libreswan firewalld

# Enable and start firewalld
systemctl enable --now firewalld

# Enable IP forwarding
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

# Configure IPSec
cat > /etc/ipsec.conf <<EOF
config setup
  protostack=netkey
  uniqueids=no
  nat_traversal=yes

conn L2TP-PSK
  authby=secret
  pfs=no
  auto=add
  keyingtries=3
  rekey=no
  ikelifetime=8h
  keylife=1h
  type=transport
  left=%defaultroute
  leftprotoport=17/1701
  right=%any
  rightprotoport=17/1701
EOF

# Set PSK
cat > /etc/ipsec.secrets <<EOF
%any %any : PSK "${VPN_PSK}"
EOF

# Configure xl2tpd
cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
ipsec saref = yes

[lns default]
ip range = ${VPN_IP_RANGE}.10-${VPN_IP_RANGE}.254
local ip = ${VPN_IP_RANGE}.1
require chap = yes
refuse pap = yes
require authentication = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

# Configure PPP options
cat > /etc/ppp/options.xl2tpd <<EOF
require-mschap-v2
ms-dns 8.8.8.8
ms-dns 8.8.4.4
asyncmap 0
auth
crtscts
lock
hide-password
modem
debug
name l2tpd
proxyarp
lcp-echo-interval 30
lcp-echo-failure 4
EOF

# Add user credentials
cat > /etc/ppp/chap-secrets <<EOF
${VPN_USER} l2tpd ${VPN_PASS} *
EOF

# Configure firewall
firewall-cmd --permanent --add-service=ipsec
firewall-cmd --permanent --add-port=1701/udp
firewall-cmd --permanent --add-port=4500/udp
firewall-cmd --permanent --add-port=500/udp
firewall-cmd --permanent --add-masquerade
firewall-cmd --reload

# NAT rule
iptables -t nat -A POSTROUTING -s ${VPN_IP_RANGE}.0/24 -o eth0 -j MASQUERADE

# Enable and start services
systemctl enable --now ipsec
systemctl enable --now xl2tpd

# Display connection info
clear
IP=\$(wget -qO- ipv4.icanhazip.com)
cat <<EOL

✅ L2TP/IPsec VPN Installation Complete

Server IP       : \${IP}
Pre-Shared Key  : \${VPN_PSK}
VPN Username    : \${VPN_USER}
VPN Password    : \${VPN_PASS}

Local Address   : \${VPN_IP_RANGE}.1
Client Range    : \${VPN_IP_RANGE}.10-\${VPN_IP_RANGE}.254

Connection Type : L2TP/IPSec PSK

EOL
