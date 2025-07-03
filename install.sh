#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
#=======================================================================#
#   System Supported:  CentOS 6+ / Debian 7+ / Ubuntu 12+               #
#   Description: L2TP VPN Auto Installer                                #
#   Author: Merciless                                                   #
#   Intro:  www.merciless.cn                                            #
#=======================================================================#
cur_dir=`pwd`

libreswan_filename="libreswan-3.27"
download_root_url="https://dl.lamp.sh/files"

rootness(){
    if [[ $EUID -ne 0 ]]; then
       echo "Error:This script must be run as root!" 1>&2
       exit 1
    fi
}

tunavailable(){
    if [[ ! -e /dev/net/tun ]]; then
        echo "Error:TUN/TAP is not available!" 1>&2
        exit 1
    fi
}

disable_selinux(){
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
}

get_opsy(){
    [ -f /etc/redhat-release ] && awk '{print ($1,$3~/^[0-9]/?$3:$4)}' /etc/redhat-release && return
    [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

get_os_info(){
    IP=$( ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' \
         | egrep -v "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." \
         | head -n 1 )
    [ -z "${IP}" ] && IP=$( wget -qO- -t1 -T2 ipv4.icanhazip.com )

    echo "########## System Information ##########"
    awk -F: '/model name/ {print "CPU model            : "$2}
             /cpu MHz/    {print "CPU frequency        : "$2" MHz"}
             /Mem:/       {print "Total RAM            : "$2" MB"}
             /Swap:/      {print "Total Swap           : "$2" MB"}' /proc/cpuinfo /proc/meminfo
    echo "OS                   : $( get_opsy )"
    echo "IPv4 address         : ${IP}"
    echo "########################################"
}

check_sys(){
    local checkType=$1
    local value=$2
    if [[ -f /etc/redhat-release ]]; then
        release="centos"; packageManager="yum"
    elif grep -Eqi "debian" /etc/issue; then
        release="debian"; packageManager="apt"
    elif grep -Eqi "ubuntu" /etc/issue; then
        release="ubuntu"; packageManager="apt"
    fi

    if [[ "${checkType}" == "sysRelease" ]]; then
        [[ "${value}" == "${release}" ]]
    else
        [[ "${value}" == "${packageManager}" ]]
    fi
}

download_file(){
    if [[ ! -s ${1} ]]; then
        wget -c -t3 -T60 ${download_root_url}/${1} || {
            echo "Failed to download $1, please download manually." 1>&2
            exit 1
        }
    fi
}

preinstall_l2tp(){
    echo
    if [[ -d "/proc/vz" ]]; then
        echo "WARNING: OpenVZ may not support IPSec. Continue? (y/n)"
        read -p "(Default: n) " agree
        agree=${agree:-n}
        [[ "${agree}" != "y" ]] && { echo "Cancelled."; exit 0; }
    fi
    echo

    # 只修改默认提示，用户可按回车直接接受 yaoyao686
    echo "请输入 IP 范围前缀 (默认 192.168.18):"
    read -p "(Default: 192.168.18) " iprange
    iprange=${iprange:-192.168.18}

    echo "请输入预共享密钥 (默认 yaoyao686):"
    read -p "(Default: yaoyao686) " mypsk
    mypsk=${mypsk:-yaoyao686}

    echo "请输入用户名 (默认 yaoyao686):"
    read -p "(Default: yaoyao686) " username
    username=${username:-yaoyao686}

    echo "请输入 ${username} 的密码 (默认 yaoyao686):"
    read -p "(Default: yaoyao686) " password
    password=${password:-yaoyao686}

    echo
    echo "ServerIP: ${IP}"
    echo "Local IP Range: ${iprange}.1"
    echo "Client IP Range: ${iprange}.2-${iprange}.254"
    echo "PSK: ${mypsk}"
    echo
    echo "按任意键开始安装，或 Ctrl+C 取消"
    read -n1
}

install_l2tp(){
    disable_selinux
    check_sys packageManager yum && \
        yum -y install epel-release ppp libreswan xl2tpd firewalld || \
        apt-get -y update && apt-get -y install ppp libreswan xl2tpd firewalld

    # 配置
    cat > /etc/ipsec.conf <<EOF
config setup
    protostack=netkey
    uniqueids=no
    nat_traversal=yes

conn L2TP-PSK
    authby=secret
    pfs=no
    auto=add
    ike=aes128-sha1;modp1024
    phase2alg=aes128-sha1
    left=%defaultroute
    leftid=${IP}
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    keyingtries=3
    rekey=no
    ikelifetime=8h
    keylife=1h
EOF

    cat > /etc/ipsec.secrets <<EOF
%any %any : PSK "${mypsk}"
EOF

    cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
ipsec saref = yes

[lns default]
ip range = ${iprange}.2-${iprange}.254
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
${username}    l2tpd    ${password}    *
EOF

    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -p

    systemctl enable --now firewalld
    firewall-cmd --permanent --add-service=ipsec
    firewall-cmd --permanent --add-port=1701/udp
    firewall-cmd --permanent --add-port=4500/udp
    firewall-cmd --permanent --add-port=500/udp
    firewall-cmd --permanent --add-masquerade
    firewall-cmd --reload

    iptables -t nat -A POSTROUTING -s ${iprange}.0/24 -o eth0 -j MASQUERADE

    systemctl enable --now ipsec
    systemctl enable --now xl2tpd
}

finally(){
    clear
    echo "✅ L2TP/IPsec VPN 安装完成！"
    echo "服务器 IP        : ${IP}"
    echo "预共享密钥       : ${mypsk}"
    echo "VPN 用户名       : ${username}"
    echo "VPN 密码         : ${password}"
    echo "本地地址         : ${iprange}.1"
    echo "客户端分配范围   : ${iprange}.2-${iprange}.254"
    echo "连接类型         : L2TP/IPSec PSK"
}

# Main
rootness
tunavailable
get_os_info
preinstall_l2tp
install_l2tp
finally
