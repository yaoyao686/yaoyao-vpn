#!/bin/bash
# Auto L2TP/IPsec VPN install script with fixed config
# Author: yaoyao686

VPN_IP_RANGE="192.168.18"
VPN_USER="yaoyao686"
VPN_PASS="yaoyao686"
VPN_PSK="yaoyao686"

# 1. 转换格式（如果你已经在本地改过可以忽略）
# sed -i 's/\r$//' "$0"

# 2. 安装依赖
yum -y install epel-release
yum -y install ppp xl2tpd libreswan firewalld

# 3. 启动并开机自启 firewalld
systemctl enable --now firewalld

# 4. 开启内核转发
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

# 5. 写配置文件
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

cat > /etc/ipsec.secrets <<EOF
%any  %any  : PSK "${VPN_PSK}"
EOF

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

cat > /etc/ppp/chap-secrets <<EOF
${VPN_USER} l2tpd ${VPN_PASS} *
EOF

# 6. 防火墙规则
firewall-cmd --permanent --add-service=ipsec
firewall-cmd --permanent --add-port=1701/udp
firewall-cmd --permanent --add-port=4500/udp
firewall-cmd --permanent --add-port=500/udp
firewall-cmd --permanent --add-masquerade
firewall-cmd --reload

iptables -t nat -A POSTROUTING -s ${VPN_IP_RANGE}.0/24 -o eth0 -j MASQUERADE

# 7. 启动服务
systemctl enable --now ipsec
systemctl enable --now xl2tpd

# 8. 输出结果
clear
IP=$(wget -qO- ipv4.icanhazip.com)
cat <<EOL

✅ L2TP/IPsec VPN 安装完成

服务器 IP：${IP}
预共享密钥：${VPN_PSK}
VPN 用户名：${VPN_USER}
VPN 密码：${VPN_PASS}

本地地址：${VPN_IP_RANGE}.1
客户端分配：${VPN_IP_RANGE}.10-${VPN_IP_RANGE}.254

连接类型：L2TP/IPSec PSK

EOL
