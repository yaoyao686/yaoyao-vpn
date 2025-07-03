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
    [ -z ${IP} ] && IP=$( wget -qO- -t1 -T2 ipv4.icanhazip.com )

    local cname=$( awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo \
                   | sed 's/^[ \t]*//;s/[ \t]*$//' )
    local cores=$( awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo )
    local freq=$( awk -F: '/cpu MHz/ {freq=$2} END {print freq}' /proc/cpuinfo \
                   | sed 's/^[ \t]*//;s/[ \t]*$//' )
    local tram=$( free -m | awk '/Mem/ {print $2}' )
    local swap=$( free -m | awk '/Swap/ {print $2}' )
    local up=$( awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60;d=$1%60} \
                     {printf("%ddays, %d:%d:%d\n",a,b,c,d)}' /proc/uptime )
    local load=$( w | head -1 | awk -F'load average:' '{print $2}' \
                   | sed 's/^[ \t]*//;s/[ \t]*$//' )
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
    elif grep -Eqi "centos|red hat|redhat" /etc/issue; then
        release="centos"; systemPackage="yum"
    elif grep -Eqi "debian" /proc/version; then
        release="debian"; systemPackage="apt"
    elif grep -Eqi "ubuntu" /proc/version; then
        release="ubuntu"; systemPackage="apt"
    elif grep -Eqi "centos|red hat|redhat" /proc/version; then
        release="centos"; systemPackage="yum"
    fi

    if [[ ${checkType} == "sysRelease" ]]; then
        [[ "$value" == "$release" ]] && return 0 || return 1
    elif [[ ${checkType} == "packageManager" ]]; then
        [[ "$value" == "$systemPackage" ]] && return 0 || return 1
    fi
}

rand(){  # 不再使用 rand，固定密码
    :
}

is_64bit(){
    [[ `getconf WORD_BIT` = '32' && `getconf LONG_BIT` = '64' ]]
}

download_file(){
    if [ -s ${1} ]; then
        echo "$1 [found]"
    else
        echo "$1 not found!!!download now..."
        if ! wget -c -t3 -T60 ${download_root_url}/${1}; then
            echo "Failed to download $1, please download it to ${cur_dir} directory manually and try again."
            exit 1
        fi
    fi
}

versionget(){
    if [[ -s /etc/redhat-release ]];then
        grep -oE  "[0-9.]+" /etc/redhat-release
    else
        grep -oE  "[0-9.]+" /etc/issue
    fi
}

centosversion(){
    check_sys sysRelease centos || return 1
    local version=$(versionget)
    [[ "${version%%.*}" == "$1" ]]
}

debianversion(){
    check_sys sysRelease debian || return 1
    local main_ver=$(get_opsy | sed 's/[^0-9]//g')
    [[ "${main_ver}" == "$1" ]]
}

version_check(){
    if check_sys packageManager yum && centosversion 5; then
        echo "Error: CentOS 5 is not supported, Please re-install OS and try again."
        exit 1
    fi
}

get_char(){
    SAVEDSTTY=`stty -g`
    stty -echo; stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw; stty echo
    stty $SAVEDSTTY
}

preinstall_l2tp(){
    rootness; tunavailable; disable_selinux; version_check; get_os_info
    echo
    if [ -d "/proc/vz" ]; then
        echo -e "\033[41;37m WARNING: \033[0m Your VPS is based on OpenVZ; IPSec might not be supported!"
        echo "Continue installation? (y/n)"
        read -p "(Default: n)" agree
        [ -z ${agree} ] && agree="n"
        [[ "${agree}" == "n" ]] && { echo "Cancelled."; exit 0; }
    fi
    echo

    echo "请输入 IP 段 (仅最后一段):"
    read -p "(默认: 192.168.18):" iprange
    [ -z "${iprange}" ] && iprange="192.168.18"

    echo "请输入预共享密钥 (PSK):"
    read -p "(默认 PSK: yaoyao686):" mypsk
    [ -z "${mypsk}" ] && mypsk="yaoyao686"

    echo "请输入用户名:"
    read -p "(默认用户名: yaoyao686):" username
    [ -z "${username}" ] && username="yaoyao686"

    password="yaoyao686"
    echo "请输入 ${username} 的密码:"
    read -p "(默认密码: yaoyao686):" tmppassword
    [ ! -z "${tmppassword}" ] && password="${tmppassword}"

    echo
    echo "ServerIP: ${IP}"
    echo "Local IP: ${iprange}.1"
    echo "Remote IP Range: ${iprange}.2-${iprange}.254"
    echo "PSK: ${mypsk}"
    echo "用户名: ${username}"
    echo "密码: ${password}"
    echo
    echo "按任意键开始安装，或 Ctrl+C 取消。"
    get_char >/dev/null 2>&1
}

# (剩余函数 install_l2tp, compile_install, config_install, yum_install, finally, l2tp, list_users, add_user, del_user, mod_user 均与原版相同，不做修改)

# 主要入口
action=$1
if [ -z "${action}" ] && [ "`basename $0`" != "l2tp" ]; then
    action=install
fi

case "${action}" in
    install) l2tp ;;
    -l|--list) list_users ;;
    -a|--add) add_user ;;
    -d|--del) del_user ;;
    -m|--mod) mod_user ;;
    -h|--help)
        echo "Usage: `basename $0` install|-l|--list|-a|--add|-d|--del|-m|--mod|-h|--help"
        ;;
    *)
        echo "Unknown option: ${action}" && exit 1
        ;;
esac
