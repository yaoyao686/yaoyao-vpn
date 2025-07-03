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
    [ -f /etc/os-release ]     && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    [ -f /etc/lsb-release ]    && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

get_os_info(){
    IP=$( ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' \
         | egrep -v "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." \
         | head -n 1 )
    [ -z ${IP} ] && IP=$( wget -qO- -t1 -T2 ipv4.icanhazip.com )

    local cname=$( awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' )
    local cores=$( awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo )
    local freq=$( awk -F: '/cpu MHz/ {freq=$2} END {print freq}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' )
    local tram=$( free -m | awk '/Mem/ {print $2}' )
    local swap=$( free -m | awk '/Swap/ {print $2}' )
    local up=$( awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60;d=$1%60} \
                     {printf("%ddays, %d:%d:%d\n",a,b,c,d)}' /proc/uptime )
    local load=$( w | head -1 | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//' )
    local opsy=$( get_opsy )
    local arch=$( uname -m )
    local lbit=$( getconf LONG_BIT )
    local host=$( hostname )
    local kern=$( uname -r )

    echo "########## System Information ##########"
    echo 
    echo "CPU model            : ${cname}"
    echo "Number of cores      : ${cores}"
    echo "CPU frequency        : ${freq} MHz"
    echo "Total amount of ram  : ${tram} MB"
    echo "Total amount of swap : ${swap} MB"
    echo "System uptime        : ${up}"
    echo "Load average         : ${load}"
    echo "OS                   : ${opsy}"
    echo "Arch                 : ${arch} (${lbit} Bit)"
    echo "Kernel               : ${kern}"
    echo "Hostname             : ${host}"
    echo "IPv4 address         : ${IP}"
    echo 
    echo "########################################"
}

check_sys(){
    local checkType=$1
    local value=$2

    local release='' systemPackage=''

    if [[ -f /etc/redhat-release ]]; then
        release="centos"; systemPackage="yum"
    elif grep -Eqi "debian" /etc/issue; then
        release="debian"; systemPackage="apt"
    elif grep -Eqi "ubuntu" /etc/issue; then
        release="ubuntu"; systemPackage="apt"
    fi

    if [[ ${checkType} == "sysRelease" ]]; then
        [[ "$value" == "$release" ]]
    else
        [[ "$value" == "$systemPackage" ]]
    fi
}

rand(){
    index=0; str=""
    for i in {a..z} {A..Z} {0..9}; do
        arr[index]=${i}; index=$((index+1))
    done
    for i in {1..10}; do
        str+="${arr[$RANDOM%$index]}"
    done
    echo ${str}
}

preinstall_l2tp(){
    echo
    if [[ -d "/proc/vz" ]]; then
        echo -e "\033[41;37m WARNING: \033[0m Your VPS is OpenVZ; IPSec might not work."
        echo "Continue? (y/n)"; read -p "(Default: n) " agree
        agree=${agree:-n}; [[ "${agree}" != "y" ]] && { echo "Cancelled."; exit 1; }
    fi
    echo

    # —— 下面三项仅改默认值为 yaoyao686 —— #
    echo "请输入 IP 范围前缀 (默认: 192.168.18):"
    read -p "(Default: 192.168.18) " iprange
    iprange=${iprange:-192.168.18}

    echo "请输入预共享密钥 (默认: yaoyao686):"
    read -p "(Default: yaoyao686) " mypsk
    mypsk=${mypsk:-yaoyao686}

    echo "请输入用户名 (默认: yaoyao686):"
    read -p "(Default: yaoyao686) " username
    username=${username:-yaoyao686}

    echo "请输入 ${username} 的密码 (默认: yaoyao686):"
    read -p "(Default: yaoyao686) " password
    password=${password:-yaoyao686}
    # —— 默认值替换结束 —— #

    echo
    echo "ServerIP: ${IP}"
    echo "Local IP: ${iprange}.1"
    echo "Client IP Range: ${iprange}.2-${iprange}.254"
    echo "PSK: ${mypsk}"
    echo
    echo "按任意键开始，Ctrl+C 取消"
    read -n1
}

install_l2tp(){
    disable_selinux
    check_sys packageManager yum && yum -y install epel-release ppp libreswan xl2tpd firewalld || \
                                 apt-get -y update && apt-get -y install ppp libreswan xl2tpd firewalld

    # （以下配置不变，直接照搬原脚本）…
    # …（中间部分略）…

    # 最后启动、firewall & iptables 配置，以及输出信息
}

# Main
rootness; tunavailable; get_os_info; preinstall_l2tp; install_l2tp; finally
