#!/bin/bash
#
# Provides:          sockd.info (Lozy)
#

VERSION="1.4.3"
INSTALL_FROM="compile"
DEFAULT_PORT="2016"
DEFAULT_USER=""
DEFAULT_PAWD=""
WHITE_LIST_NET=""
WHITE_LIST=""
SCRIPT_HOST="${SCRIPT_HOST:-https://public.sockd.info}"
PACKAGE_NAME="dante_1.3.2-1_$(uname -m).deb"
COLOR_PATH="/etc/default/color"

BIN_DIR="/etc/danted"
BIN_PATH="/etc/danted/sbin/sockd"
CONFIG_PATH="/etc/danted/sockd.conf"
BIN_SCRIPT="/etc/init.d/sockd"

DEFAULT_IPADDR=$(ip addr | grep 'inet ' | grep -Ev 'inet 127|inet 192\.168' | \
            sed "s/[[:space:]]*inet \([0-9.]*\)\/.*/\1/")
RUN_PATH=$(cd `dirname $0`;pwd )
RUN_OPTS=$*

##################------------Func()---------#####################################
remove_install(){
    [ -s "${BIN_SCRIPT}" ] && ${BIN_SCRIPT} stop > /dev/null 2>&1
    [ -f "${BIN_SCRIPT}" ] && rm "${BIN_SCRIPT}"
    [ -n "$BIN_DIR" ] && rm -r "$BIN_DIR"
}

detect_install(){
    if [ -s "${BIN_PATH}" ];then
        echo "dante socks5 already install"
        ${BIN_PATH} -v
    fi
}

generate_config_ip(){
    local ipaddr="$1"
    local port="$2"

    cat <<EOF
# Generate interface ${ipaddr}
internal: ${ipaddr}  port = ${port}
external: ${ipaddr}

EOF
}

generate_config_iplist(){
    local ipaddr_list="$1"
    local port="$2"

    [ -z "${ipaddr_list}" ] && return 1
    [ -z "${port}" ] && return 2

    for ipaddr in ${ipaddr_list};do
        generate_config_ip ${ipaddr} ${port} >> ${CONFIG_PATH}
    done

    ipaddr_array=($ipaddr_list)

    if [ ${#ipaddr_array[@]} -gt 1 ];then
        echo "external.rotation: same-same" >> ${CONFIG_PATH}
    fi
}

generate_config_static(){
    if [ "$VERSION" == "1.3.2" ];then
    cat <<EOF
method: pam none
clientmethod: none
user.privileged: root
user.notprivileged: sockd
logoutput: /var/log/sockd.log

client pass {
        from: 0.0.0.0/0  to: 0.0.0.0/0
}
client block {
        from: 0.0.0.0/0 to: 0.0.0.0/0
}
EOF
    else
    cat <<EOF
clientmethod: none
socksmethod: pam.username none

user.privileged: root
user.notprivileged: sockd

logoutput: /var/log/sockd.log

client pass {
    from: 0/0  to: 0/0
    log: connect disconnect
}
client block {
    from: 0/0 to: 0/0
    log: connect error
}
EOF
    fi
}
generate_config_white(){
    local white_ipaddr="$1"

    [ -z "${white_ipaddr}" ] && return 1

    # x.x.x.x/32
    for ipaddr_range in ${white_ipaddr};do
        cat <<EOF
#------------ Network Trust: ${ipaddr_range} ---------------
pass {
        from: ${ipaddr_range} to: 0.0.0.0/0
        method: none
}

EOF
    done
}

generate_config_whitelist(){
    local whitelist_url="$1"

    if [ -n "${whitelist_url}" ];then
        ipaddr_list=$(curl -s --insecure -A "Mozilla Server Init" ${whitelist_url})
        generate_config_white "${ipaddr_list}"
    fi
}

generate_config_bottom(){
    if [ "$VERSION" == "1.3.2" ];then
    cat <<EOF
pass {
        from: 0.0.0.0/0 to: 0.0.0.0/0
        protocol: tcp udp
        method: pam
        log: connect disconnect
}
block {
        from: 0.0.0.0/0 to: 0.0.0.0/0
        log: connect error
}

EOF
    else
    cat <<EOF
socks pass {
    from: 0/0 to: 0/0
    socksmethod: pam.username
    log: connect disconnect
}
socks block {
    from: 0/0 to: 0/0
    log: connect error
}

EOF
    fi
}

generate_config(){
    local ipaddr_list="$1"
    local whitelist_url="$2"
    local whitelist_ip="$3"

    mkdir -p ${BIN_DIR}

    echo "# Generate by sockd.info" > ${CONFIG_PATH}

    generate_config_iplist "${ipaddr_list}" ${DEFAULT_PORT} >> ${CONFIG_PATH}

    generate_config_static >> ${CONFIG_PATH}
    generate_config_white ${whitelist_ip} >> ${CONFIG_PATH}
    generate_config_whitelist "${whitelist_url}" >> ${CONFIG_PATH}
    generate_config_bottom  >> ${CONFIG_PATH}
}

download_file(){
    local path="$1"
    local filename="$2"
    local execute="$3"

    [ -z "${filename}" ] && filename="$path"

    [ -n "$path" ] && \
        wget -q --no-check-certificate ${SCRIPT_HOST}/${path} -O ${filename}

    [ -f "${filename}" ] && [ -n "${execute}" ] && chmod +x ${filename}
}

##################------------Envs Fix()-----###################################

# CentOS 7 已 EOL，官方 mirrorlist 失效，改用 vault 源
fix_eol_repo(){
    [ -f /etc/redhat-release ] || return 0
    grep -qE 'release 7\.' /etc/redhat-release || return 0

    echo "[*] 检测到 CentOS 7（已 EOL），切换 yum 源到 vault.centos.org"
    for repo in /etc/yum.repos.d/CentOS-*.repo; do
        [ -f "${repo}" ] || continue
        sed -i \
            -e 's|^mirrorlist=|#mirrorlist=|g' \
            -e 's|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' \
            "${repo}"
    done
    yum clean all >/dev/null 2>&1
    if yum makecache >/dev/null 2>&1; then
        echo "[+] yum 源已切换到 vault"
    else
        echo "[!] yum 源刷新失败，请检查网络或 /etc/yum.repos.d/ 配置"
    fi
}

# SELinux 为 Enforcing 时给监听端口打标签，避免 bind 被拒绝
fix_selinux(){
    command -v getenforce >/dev/null 2>&1 || return 0
    [ "$(getenforce)" = "Enforcing" ] || { echo "SELinux: $(getenforce)"; return 0; }

    if ! command -v semanage >/dev/null 2>&1; then
        yum install -y policycoreutils-python-utils >/dev/null 2>&1 \
            || yum install -y policycoreutils-python >/dev/null 2>&1
    fi

    if command -v semanage >/dev/null 2>&1; then
        semanage port -a -t http_port_t -p tcp ${DEFAULT_PORT} >/dev/null 2>&1 \
            || semanage port -m -t http_port_t -p tcp ${DEFAULT_PORT} >/dev/null 2>&1
        echo "SELinux: 已放行 ${DEFAULT_PORT}/tcp（http_port_t）"
    else
        echo "[!] SELinux 处于 Enforcing 且 semanage 不可用，若服务起不来请执行:"
        echo "    setenforce 0    # 临时关闭，重启后失效"
    fi
}

##################------------Menu()---------#####################################
echo "Current Options: $RUN_OPTS"
for _PARAMETER in $RUN_OPTS
do
    case "${_PARAMETER}" in
      --version=*)
        VERSION="${_PARAMETER#--version=}"
      ;;
      --ip=*)   #split by: ip1:ip2:ip3
        ipaddr_list=$(echo "${_PARAMETER#--ip=}" | sed 's/:/\n/g' | sed '/^$/d')
      ;;
      --port=*)
        port="${_PARAMETER#--port=}"
      ;;
      --user=*)
        user="${_PARAMETER#--user=}"
      ;;
      --passwd=*)
        passwd="${_PARAMETER#--passwd=}"
      ;;
      --whitelist=*)
        whitelist_ipaddrs=$(echo "${_PARAMETER#--whitelist=}" | sed 's/:/\n/g' | sed '/^$/d')
      ;;
      --whitelist-url=*)
        whitelist="${_PARAMETER#--whitelist-url=}"
      ;;
      --from-package|-p)
        echo "Sorry, install from-package is not available for CentOS."
        # INSTALL_FROM="package"
        exit 1
      ;;
      --update-whitelist|-u)
        gen_config_only="True"
      ;;
      --force|-f)
        remove_install
      ;;
      --uninstall)
        remove_install
        exit 0
      ;;
      --no-github)
        echo "skip download script from github.com"
      ;;
      --help|-h)
        clear
        options=(
                  "--ip=@Socks5 Server Ip address" \
                  "--port=[${DEFAULT_PORT}]@port for dante socks5 server" \
                  "--version=@Specify dante version [$VERSION]"\s
                  "--user=@Socks5 Auth user" \
                  "--passwd=@Socks5 Auth passwd"\
                  "--whitelist=@Socks5 Auth IP list" \
                  "--whitelist-url=@Socks Auth whitelist http online" \
                  "--from-package | -p @Install package from Bin package" \
                  "--update-whitelist | -u @update white list" \
                  "--force-update | -f @force update sockd" \
                  "--help,-h@print help info" )
        printf "Usage: %s [OPTIONS]\n\nOptions:\n\n" $0

        for option in "${options[@]}";do
          printf "  %-20s%s\n" "$( echo ${option} | sed 's/@.*//g')"  "$( echo ${option} | sed 's/.*@//g')"
        done
        echo -e "\n"
        exit 1
      ;;
      *)
        echo "option ${_PARAMETER} is not support"
        exit 1
      ;;

    esac
done

[ -n "${port}" ] && DEFAULT_PORT="${port}"
[ -n "${ipaddr_list}" ] && DEFAULT_IPADDR="${ipaddr_list}"
[ -n "${user}" ] && DEFAULT_USER="${user}"
[ -n "${passwd}" ] && DEFAULT_PAWD="${passwd}"
[ -n "${whitelist_ipaddrs}" ] && WHITE_LIST_NET="${whitelist_ipaddrs}"
[ -n "${whitelist}" ] && WHITE_LIST="${whitelist}"

generate_config "${DEFAULT_IPADDR}" "${WHITE_LIST}" "${WHITE_LIST_NET}"

[ -n "$gen_config_only" ]  && echo "===========>> update config" && cat ${CONFIG_PATH} && exit 0

download_file "script/sockd" "${BIN_SCRIPT}" "execute"

[ -n "$(detect_install)" ] && echo -e "\n[Warning] dante sockd already install." && exit 1

[ -n "$COLOR_PATH" ] && [ ! -s "$COLOR_PATH" ] && download_file "script/color" $COLOR_PATH && . $COLOR_PATH

########################################## DEBIAN 8 ####################################################################
fix_eol_repo

yum install gcc g++ make vim pam-devel tcp_wrappers-devel unzip httpd-tools wget curl -y

mkdir -p /tmp/danted && rm /tmp/danted/* -rf && cd /tmp/danted

id sockd > /dev/null 2>&1 || useradd sockd -s /bin/false

# Installing Start-Stop Daemon
if [ -z "$(command -v start-stop-daemon)" ];then
    download_file "source/apps-sys-utils-start-stop-daemon-IR1_9_18-2.tar.gz" "start-stop-daemon-IR1_9_18-2.tar.gz"
    tar zxvf start-stop-daemon-IR1_9_18-2.tar.gz
    gcc apps/sys-utils/start-stop-daemon-IR1_9_18-2/start-stop-daemon.c \
        -o /sbin/start-stop-daemon
fi

#--# Check libpam-pwdfile
if [ ! -s /lib/security/pam_pwdfile.so ];then
    download_file "source/libpam-pwdfile.zip" "libpam-pwdfile.zip"
    if [ -f "libpam-pwdfile.zip" ];then
        unzip libpam-pwdfile.zip
        cd libpam-pwdfile-master && make -j && make install
        cd ../
    fi
fi

if [ -d /lib64/security/ ] && [ ! -f /lib64/security/pam_pwdfile.so ];then
    [ -f /lib/security/pam_pwdfile.so ] && \
        cp /lib/security/pam_pwdfile.so /lib64/security/ || echo "[ERROR] pam_pwdfile.so not exist!"
fi

if [ "$INSTALL_FROM" == "compile" ];then
    yum install gcc g++ make pam-devel tcp_wrappers-devel -y

    download_file "source/dante-${VERSION}.tar.gz" "dante-${VERSION}.tar.gz"

    if [ -f "dante-${VERSION}.tar.gz" ];then
        tar xzf dante-${VERSION}.tar.gz --strip 1

        # 旧版 config.guess 识别不出新架构（如 ARM64），用仓库内附带的版本替换
        download_file "source/config.guess" "config.guess"
        download_file "source/config.sub" "config.sub"
        chmod +x config.guess config.sub 2>/dev/null

        compile_args='--with-pam'
        [ "$VERSION" == "1.3.2" ] && compile_args="${compile_args} --disable-preload"

        ./configure --with-sockd-conf=${CONFIG_PATH} --prefix=${BIN_DIR} ${compile_args} \
            && make -j && make install
    fi
else
    echo "[ERROR] CentOS/RHEL 不支持 --from-package 选项，该选项安装的是 Debian 的 deb 包"
    echo "        请去掉 -p 参数改用源码编译，或安装官方包："
    echo "        yum install -y epel-release && yum install -y dante-server"
    exit 1
fi

cat > /etc/pam.d/sockd  <<EOF
auth required pam_pwdfile.so pwdfile ${BIN_DIR}/sockd.passwd
account required pam_permit.so
EOF

cat > /etc/default/sockd <<EOF
# Default Config for sockd
# -n :: not tcp-keep alive
Start_Process=1
Sockd_Opts="-n"
EOF

rm /usr/bin/sockd -f && ln -s /etc/danted/sbin/sockd /usr/bin/sockd
${BIN_SCRIPT} adduser "${DEFAULT_USER}" "${DEFAULT_PAWD}"

if [ -n "$(ls -l /sbin/init | grep systemd)" ];then
    download_file "script/sockd.service" "/lib/systemd/system/sockd.service"
    systemctl enable sockd
else
    chkconfig --add sockd
fi

# SELinux 与 firewalld 放行
fix_selinux

if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port=${DEFAULT_PORT}/tcp >/dev/null
    firewall-cmd --reload >/dev/null
    echo "firewalld: 已放行 ${DEFAULT_PORT}/tcp"
fi

service sockd restart
clear

if [ -n "$(ss -ln | grep "$DEFAULT_PORT")" ];then
    cat <<EOF
${CCYAN}+-----------------------------------------+$CEND
${CGREEN} Dante Socks5 Install Done. $CEND
${CCYAN}+-----------------------------------------+$CEND
${CGREEN} Dante Version:       $CMAGENTA v${VERSION}$CEND
${CGREEN} Socks5 Info:         $CMAGENTA$CEND
EOF

    for ipaddr in ${DEFAULT_IPADDR};do
        echo "${CGREEN}                      $CMAGENTA ${ipaddr}:${DEFAULT_PORT}$CEND"
    done

    cat <<EOF
${CGREEN} Socks5 User&Passwd:  $CMAGENTA ${DEFAULT_USER}:${DEFAULT_PAWD}$CEND
${CCYAN}+_________________________________________+$CEND
EOF
    echo -e "\033[32m Dante Server Install Successfuly! \033[0m"
else
    echo -e "\033[1;31m Dante Server Install Failed! \033[0m"
fi

echo ""
${BIN_SCRIPT} -h

exit 0
