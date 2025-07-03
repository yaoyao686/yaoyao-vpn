#!/usr/bin/env bash
# Auto L2TP/IPsec VPN install script with fixed config
# Author: yaoyao686

VPN_IP_RANGE="192.168.18"
VPN_USER="yaoyao686"
VPN_PASS="yaoyao686"
VPN_PSK="yaoyao686"

# 必须以 root 运行
[[ $EUID -ne 0 ]] && echo "请使用 root 权限运行此脚本！" && exit 1

# 安装依赖
yum -y install epel-release
yum -y install ppp xl2tpd libreswan firewalld

# 启动并开机自启 firewalld
systemctl enable --now firewalld

# 开启 IP 转发
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

# 配置 IPSec
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

# 写入 PSK
cat > /etc/ipsec.secrets <<EOF
%any  %any  : PSK "${VPN_PSK}"
EOF

# 配置 xl2tpd
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

# 配置 PPP
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

# 写入用户名/密码
cat > /etc/ppp/chap-secrets <<EOF
${VPN_USER}    l2tpd    ${VPN_PASS}    *
EOF

# 配置防火墙
firewall-cmd --permanent --add-service=ipsec
firewall-cmd --permanent --add-port=1701/udp
firewall-cmd --permanent --add-port=4500/udp
firewall-cmd --permanent --add-port=500/udp
firewall-cmd --permanent --add-masquerade
firewall-cmd --reload

iptables -t nat -A POSTROUTING -s ${VPN_IP_RANGE}.0/24 -o eth0 -j MASQUERADE

# 启动服务
systemctl enable --now ipsec
systemctl enable --now xl2tpd

# 输出结果
clear
IP=$(wget -qO- ipv4.icanhazip.com)
cat <<EOL

✅ L2TP/IPsec VPN 安装完成

服务器 IP       : ${IP}
预共享密钥      : ${VPN_PSK}
VPN 用户名      : ${VPN_USER}
VPN 密码        : ${VPN_PASS}

本地地址        : ${VPN_IP_RANGE}.1
客户端分配范围  : ${VPN_IP_RANGE}.10-${VPN_IP_RANGE}.254

连接类型        : L2TP/IPSec PSK

EOL
