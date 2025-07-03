#!/bin/bash
# L2TP/IPsec VPN Auto Installer (Silent Mode)
# Author: Merciless (原始脚本)
# Modified: yaoyao686 版本，全自动部署无交互

# 固定变量
iprange="192.168.18"
mypsk="yaoyao686"
username="yaoyao686"
password="yaoyao686"

# 检查 root 权限
[[ $EUID -ne 0 ]] && echo "请使用 root 权限运行该脚本！" && exit 1

# 检查 TUN 模块
[[ ! -e /dev/net/tun ]] && echo "TUN 模块未开启，VPN 无法使用。" && exit 1

# 设置变量
IP=$(wget -qO- -t1 -T2 ipv4.icanhazip.com)
yum install -y epel-release
yum install -y xl2tpd libreswan ppp iptables-services firewalld

# 创建配置文件
cat > /etc/ipsec.conf <<EOF
config setup
    protostack=netkey
    uniqueids=no
    nat_traversal=yes

conn L2TP-PSK
    auto=add
    left=%defaultroute
    leftid=${IP}
    right=%any
    type=transport
    authby=secret
    pfs=no
    ike=aes128-sha1;modp1024
    phase2alg=aes128-sha1
    keyingtries=3
    rekey=no
    leftprotoport=17/1701
    rightprotoport=17/%any
EOF

cat > /etc/ipsec.secrets <<EOF
%any %any : PSK "${mypsk}"
EOF

cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
ipsec saref = yes

[lns default]
ip range = ${iprange}.10-${iprange}.254
local ip = ${iprange}.1
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
${username} l2tpd ${password} *
EOF

# 系统转发与防火墙规则
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

firewall-cmd --permanent --add-service=ipsec
firewall-cmd --permanent --add-port=1701/udp
firewall-cmd --permanent --add-port=4500/udp
firewall-cmd --permanent --add-port=500/udp
firewall-cmd --permanent --add-masquerade
firewall-cmd --reload

iptables -t nat -A POSTROUTING -s ${iprange}.0/24 -o eth0 -j MASQUERADE

# 启动服务
systemctl enable ipsec
systemctl enable xl2tpd
systemctl restart ipsec
systemctl restart xl2tpd

# 输出信息
clear
echo "✅ L2TP/IPsec VPN 安装完成"
echo "-------------------------------"
echo "服务器 IP：${IP}"
echo "预共享密钥：${mypsk}"
echo "VPN 用户名：${username}"
echo "VPN 密码：${password}"
echo "本地地址：${iprange}.1"
echo "客户端分配：${iprange}.10-${iprange}.254"
echo "-------------------------------"
echo "连接类型：L2TP/IPSec PSK"
