#!/bin/bash
# Auto install L2TP/IPSec VPN Server on CentOS 7+, Debian, Ubuntu
# Customized for user: yaoyao

set -e

# 安装必要软件
echo "Updating system and installing packages..."
yum install -y epel-release || apt-get update -y
yum install -y xl2tpd libreswan ppp || apt-get install -y xl2tpd libreswan ppp

# 自定义账户信息
VPN_IPSEC_PSK='yaoyao'
VPN_USER='yaoyao'
VPN_PASSWORD='yaoyao'

# 配置 /etc/ipsec.conf
cat > /etc/ipsec.conf <<EOF
config setup
  uniqueids=no
conn L2TP-PSK
  authby=secret
  pfs=no
  auto=add
  keyingtries=3
  rekey=no
  ike=aes128-sha1;modp1024
  phase2alg=aes128-sha1
  type=transport
  left=%defaultroute
  leftprotoport=17/1701
  right=%any
  rightprotoport=17/%any
EOF

# 配置 /etc/ipsec.secrets
cat > /etc/ipsec.secrets <<EOF
%any  %any  : PSK "$VPN_IPSEC_PSK"
EOF

# 配置 /etc/xl2tpd/xl2tpd.conf
cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
ipsec saref = yes
[lns default]
ip range = 10.10.10.2-10.10.10.10
local ip = 10.10.10.1
refuse chap = no
refuse pap = yes
require authentication = yes
name = L2TPVPN
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

# 配置 /etc/ppp/options.xl2tpd
cat > /etc/ppp/options.xl2tpd <<EOF
require-mschap-v2
ms-dns 8.8.8.8
ms-dns 8.8.4.4
auth
name l2tpd
mtu 1200
mru 1200
nodefaultroute
debug
lock
proxyarp
connect-delay 5000
EOF

# 添加用户
cat > /etc/ppp/chap-secrets <<EOF
$VPN_USER  l2tpd  $VPN_PASSWORD  *
EOF

# 启用IP转发
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf

# 设置防火墙规则
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -s 10.10.10.0/24 -j ACCEPT
iptables-save > /etc/iptables.rules

# 启动服务
systemctl enable ipsec
systemctl enable xl2tpd
systemctl restart ipsec
systemctl restart xl2tpd

echo "✅ VPN 安装完成！"
echo "IPSec 预共享密钥: $VPN_IPSEC_PSK"
echo "VPN 用户名: $VPN_USER"
echo "VPN 密码: $VPN_PASSWORD"
