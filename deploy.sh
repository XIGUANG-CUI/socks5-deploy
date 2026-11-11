#!/usr/bin/env bash
#
# dante SOCKS5 一键部署脚本（Debian / Ubuntu）
# 两种安装方式：
#   deb     : 使用预编译包，要求 glibc >= 2.38（Debian 13 / Ubuntu 24.04+）
#   compile : 源码编译，适用于任意 Debian/Ubuntu
#
# 用法见 --help
#
set -euo pipefail

PORT=2016
MODE=auto
BASE="${REPO_BASE:-}"
PROXY_USER=""
PROXY_PASS=""
CONF=/etc/danted.conf
LOGFILE=/var/log/danted.log

ok()   { printf '\033[32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
cat <<'USAGE'
用法: sudo bash deploy.sh --user=<账号> --passwd=<密码> [选项]

必填:
  --user=<账号>      SOCKS5 认证账号（不存在时自动创建为系统用户）
  --passwd=<密码>    SOCKS5 认证密码

可选:
  --port=<端口>      监听端口，默认 2016
  --mode=<模式>      auto | deb | compile，默认 auto
                     deb     : 预编译 deb 包，要求 glibc >= 2.38
                     compile : 源码编译，适用于任意 Debian/Ubuntu
  --base=<URL>       从远程仓库取安装文件，例如
                     https://raw.githubusercontent.com/<你>/<仓库>/main
                     不填则使用本脚本同目录下的本地文件

示例:
  sudo bash deploy.sh --user=proxy --passwd='P@ss1234' --port=2016
  sudo bash deploy.sh --user=proxy --passwd='P@ss1234' \
      --base=https://raw.githubusercontent.com/me/socks5-deploy/main
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --user=*)   PROXY_USER="${1#*=}" ;;
        --passwd=*) PROXY_PASS="${1#*=}" ;;
        --port=*)   PORT="${1#*=}" ;;
        --mode=*)   MODE="${1#*=}" ;;
        --base=*)   BASE="${1#*=}" ;;
        --help|-h)  usage; exit 0 ;;
        *)          die "未知参数: $1（用 --help 查看用法）" ;;
    esac
    shift
done

[ "$(id -u)" -eq 0 ] || die "需要 root 权限，请用 sudo 运行"
[ -n "$PROXY_USER" ] || { usage; die "缺少 --user"; }
[ -n "$PROXY_PASS" ] || { usage; die "缺少 --passwd"; }
case "$PORT" in ''|*[!0-9]*) die "--port 必须是数字" ;; esac
case "$MODE" in auto|deb|compile) ;; *) die "--mode 只能是 auto / deb / compile" ;; esac

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# 取文件：优先本地，其次 --base 指定的远程仓库
get() {
    local rel="$1" dst="$2"
    if [ -f "$SCRIPT_DIR/$rel" ]; then
        cp -f "$SCRIPT_DIR/$rel" "$dst"
    elif [ -n "$BASE" ]; then
        wget -q --no-check-certificate --tries=3 --timeout=20 "$BASE/$rel" -O "$dst" || return 1
    else
        return 1
    fi
}

# ---------- 系统检查 ----------
[ -r /etc/os-release ] || die "无法识别系统（缺少 /etc/os-release）"
. /etc/os-release
case "${ID:-} ${ID_LIKE:-}" in
    *debian*|*ubuntu*) ok "系统: ${PRETTY_NAME:-$ID}" ;;
    *) die "本脚本只支持 Debian / Ubuntu；其他系统请用 install/ 下的原版脚本" ;;
esac

case "$(uname -m)" in
    x86_64|amd64)  DEB_ARCH=amd64 ;;
    aarch64|arm64) DEB_ARCH=arm64 ;;
    *)             DEB_ARCH="" ;;
esac

ver_ge() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]; }
GLIBC=$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}' || true)

if [ "$MODE" = auto ]; then
    if [ -n "$DEB_ARCH" ] && [ -n "$GLIBC" ] && ver_ge "$GLIBC" 2.38; then
        MODE=deb
    else
        MODE=compile
    fi
fi
ok "安装方式: $MODE（架构 ${DEB_ARCH:-未知}，glibc ${GLIBC:-未知}）"

WORK=$(mktemp -d /tmp/dante-deploy.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

apt-get update -qq
apt-get install -y -qq ca-certificates wget curl

# ---------- 安装主程序 ----------
if [ "$MODE" = deb ]; then
    [ -n "$DEB_ARCH" ] || die "不支持的 CPU 架构，请改用 --mode=compile"
    PKG="dante-server_1.4.4+dfsg2-1+b1_${DEB_ARCH}.deb"
    get "package/$PKG" "$WORK/$PKG" || die "取不到安装包 $PKG"
    ok "已获取 $PKG"
    apt-get install -y "$WORK/$PKG"
    BIN=/usr/sbin/danted
    SVC=danted
else
    apt-get install -y -qq build-essential libpam0g-dev libwrap0-dev
    get "source/dante-1.4.3-official.tar.gz" "$WORK/dante.tar.gz" \
        || die "取不到源码包 dante-1.4.3-official.tar.gz"
    tar xzf "$WORK/dante.tar.gz" -C "$WORK"
    SRC="$WORK/dante-1.4.3"
    [ -d "$SRC" ] || die "源码包解压异常"

    # 新版系统上旧 config.guess 识别不出架构，用仓库内附带的版本替换
    for f in config.guess config.sub; do
        get "source/$f" "$SRC/$f" && chmod +x "$SRC/$f" || warn "未取到 $f，继续尝试"
    done

    ok "开始编译（视 CPU 性能需要几分钟）"
    (
        cd "$SRC"
        export CFLAGS="${CFLAGS:--O2 -Wno-implicit-function-declaration}"
        ./configure --prefix=/usr/local \
                    --with-sockd-conf="$CONF" \
                    --with-pam >/dev/null
        make -j"$(nproc)" >/dev/null
        make install >/dev/null
    ) || die "编译失败，可改用 --mode=deb（若系统较新）"
    BIN=/usr/local/sbin/sockd
    SVC=sockd
    ok "编译安装完成: $BIN"
fi

# ---------- 生成配置 ----------
IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' || true)
[ -n "$IFACE" ] || IFACE=$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}' || true)
[ -n "$IFACE" ] || die "无法识别外网网卡，请手动编辑 $CONF 的 external 字段"
ok "外网网卡: $IFACE"

if [ -f "$CONF" ]; then
    cp "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
    warn "已备份旧配置: $CONF.bak.*"
fi

cat > "$CONF" <<EOF
# generate by deploy.sh
logoutput: $LOGFILE

internal: 0.0.0.0 port = $PORT
external: $IFACE

clientmethod: none
socksmethod: username
user.privileged: root
user.notprivileged: nobody

client pass {
    from: 0/0 to: 0/0
    log: connect error
}

socks pass {
    from: 0/0 to: 0/0
    protocol: tcp udp
    log: connect disconnect
}

socks block {
    from: 0/0 to: 0/0
    log: connect error
}
EOF
chmod 600 "$CONF"
ok "已写入配置 $CONF"

# ---------- 创建账号 ----------
if id "$PROXY_USER" >/dev/null 2>&1; then
    warn "用户 $PROXY_USER 已存在，将重置密码"
else
    useradd -M -s /usr/sbin/nologin "$PROXY_USER"
    ok "已创建系统用户 $PROXY_USER"
fi
echo "$PROXY_USER:$PROXY_PASS" | chpasswd
ok "认证账号已就绪"

# ---------- 注册服务 ----------
if [ "$MODE" = compile ]; then
    cat > /etc/systemd/system/sockd.service <<EOF
[Unit]
Description=dante SOCKS5 server (sockd)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN -f $CONF
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
fi

systemctl enable "$SVC" >/dev/null 2>&1 || true
systemctl restart "$SVC"
sleep 2

# ---------- 放行防火墙 ----------
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi 'Status: active'; then
    ufw allow "$PORT"/tcp >/dev/null && ok "ufw 已放行 $PORT/tcp"
fi
if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port="$PORT"/tcp >/dev/null \
        && firewall-cmd --reload >/dev/null \
        && ok "firewalld 已放行 $PORT/tcp"
fi

# ---------- 校验 ----------
if ! systemctl is-active --quiet "$SVC"; then
    journalctl -u "$SVC" -n 30 --no-pager || true
    die "服务 $SVC 启动失败，请检查上面的日志"
fi
if ss -lnt 2>/dev/null | awk '{print $4}' | grep -q ":$PORT$"; then
    ok "端口 $PORT 正在监听"
else
    warn "未检测到 $PORT 监听，请执行: ss -lntp | grep $PORT"
fi

PUBIP=$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)

cat <<EOF

==================================================
 dante SOCKS5 部署完成
--------------------------------------------------
 地址     : ${PUBIP:-<服务器公网IP>}:${PORT}
 账号     : $PROXY_USER
 密码     : $PROXY_PASS
 配置文件 : $CONF
 日志     : $LOGFILE
 服务名   : $SVC
--------------------------------------------------
 本机测试 : curl -x socks5h://$PROXY_USER:$PROXY_PASS@127.0.0.1:$PORT https://api.ipify.org
 查看状态 : systemctl status $SVC
 停止     : systemctl stop $SVC
==================================================
EOF
