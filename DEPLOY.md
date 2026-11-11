# dante SOCKS5 代理架设指南（新手版）

本文档面向**第一次接触 Linux 服务器**的人。照着从上往下做，每一步都给了可直接复制的命令。

- 仓库地址：`https://github.com/XIGUANG-CUI/socks5-deploy`
- 适用系统：Debian / Ubuntu / CentOS（详见第 0.3 节）

---

## 0. 开始之前

### 0.1 你需要准备

| 项目 | 说明 |
|---|---|
| 一台云服务器 | 1 核 1G 就够，不需要高配置 |
| 服务器 root 密码 | 或可用的 SSH 密钥 |
| 一个 SSH 客户端 | Windows 用系统自带 PowerShell；Mac/Linux 用「终端」 |
| 约 10 分钟 | 国外服务器约 1 分钟，国内服务器慢一些 |

### 0.2 30 秒判断你该走哪条路

在你的电脑上打开 PowerShell（Windows）或终端（Mac），执行：

```powershell
curl.exe -m 8 -I https://raw.githubusercontent.com
```

看输出的第一行：

- 是 `HTTP/2 200` 或 `HTTP/1.1 200` → **走第 2 章：国外服务器**
- 卡住、超时，或报 `Could not resolve host` → **走第 3 章：国内服务器**

> 这个判断依据是 `raw.githubusercontent.com` 能不能直连。国内大部分网络访问不了它，而部署脚本要从这里下载安装包。

### 0.3 系统支持对照

| 你的系统 | 用哪个脚本 | 安装方式 |
|---|---|---|
| Ubuntu 24.04 及以上 | `deploy.sh` | 直接装 deb 包，最快 |
| Ubuntu 18.04 ~ 22.04 | `deploy.sh` | 自动源码编译，约 3-5 分钟 |
| Debian 13 | `deploy.sh` | 直接装 deb 包 |
| Debian 10 ~ 12 | `deploy.sh` | 自动源码编译 |
| CentOS 7 / Rocky / Alma | `install/install_centos.sh` | 源码编译 |

不确定自己的系统版本？登录服务器后执行：

```bash
cat /etc/os-release | head -3
```

---

## 1. 登录服务器

在 PowerShell 或终端里执行（把 `1.2.3.4` 换成你服务器的公网 IP）：

```bash
ssh root@1.2.3.4
```

第一次连接会问 `Are you sure you want to continue connecting?`，输入 `yes` 回车，然后输入服务器密码（输入时屏幕不显示字符，是正常的，输完直接回车）。

登录成功后，命令行提示符会变成类似 `root@iZufxxxx:~#`，说明你已经进到服务器里了。

> 后面所有命令都在**服务器上**执行，除非特别注明「在你自己的电脑上」。

---

## 2. ① 国外服务器部署

国外服务器能直接访问 GitHub，一条命令就能装完。

### 2.1 执行一键部署

```bash
curl -fsSL https://raw.githubusercontent.com/XIGUANG-CUI/socks5-deploy/main/deploy.sh \
  | sudo bash -s -- --user=proxy --passwd='MyPass123' \
      --base=https://raw.githubusercontent.com/XIGUANG-CUI/socks5-deploy/main
```

三个参数说明：

| 参数 | 含义 | 建议 |
|---|---|---|
| `--user=proxy` | 代理的登录账号 | 随便起，别用 root |
| `--passwd='MyPass123'` | 代理的登录密码 | 换成你自己的，**必须用单引号包起来** |
| `--base=...` | 安装包下载地址 | 保持原样不动 |

> 密码里如果有 `$`、`!`、`&` 这类符号，一定要用**单引号** `'...'` 包住，否则 shell 会吃掉它们。
>
> 如果提示 `sudo: command not found`，说明你已经是 root，把命令里的 `sudo ` 去掉直接执行即可。

### 2.2 看到这个就是成功了

脚本会先打印系统信息，然后自动判断安装方式，最后输出：

```
==================================================
 dante SOCKS5 部署完成
--------------------------------------------------
 地址     : 8.8.8.8:2016
 账号     : proxy
 密码     : MyPass123
 配置文件 : /etc/danted.conf
 日志     : /var/log/danted.log
 服务名   : danted
--------------------------------------------------
 本机测试 : curl -x socks5h://proxy:MyPass123@127.0.0.1:2016 https://api.ipify.org
==================================================
```

**把「地址 / 账号 / 密码」这三行记下来**，客户端要用。

### 2.3 跑一次自检

```bash
curl -x socks5h://proxy:MyPass123@127.0.0.1:2016 https://api.ipify.org
```

- 返回一个 IP（就是你的服务器 IP）→ **代理正常**
- 返回 `curl: (97) ...` → 账号密码不对
- 卡住不动 → 端口没监听，执行 `systemctl status danted` 看日志

---

## 3. ② 国内服务器部署

国内服务器通常访问不了 `raw.githubusercontent.com`，所以**不能**用上面那条一键命令，会卡在第 1 步。改用下面任意一个方案。

### 3.1 方案 A：从你的电脑上传（推荐，最稳）

这个方案不依赖任何外网，只要你能 SSH 上服务器就能装。

**第 1 步：在你自己的电脑上**，打开 PowerShell，进到项目目录的上一级：

```powershell
cd "c:\Users\Administrator\Documents\trae_projects\SOCKS 5"
```

**第 2 步：上传整个目录**

```powershell
scp -r ".\socks5-deploy" root@你的服务器IP:/root/
```

> 会提示输入服务器密码。上传约 50 MB（主要是 gost.exe 那 48 MB），耐心等一会儿。

**第 3 步：回到服务器上**，执行安装：

```bash
cd /root/socks5-deploy
sudo bash deploy.sh --user=proxy --passwd='MyPass123'
```

注意这里**不需要** `--base` 参数，因为安装包就在当前目录里。

### 3.2 方案 B：用 GitHub 加速镜像

如果你不想传文件，可以走镜像站（把 `raw.githubusercontent.com` 换成 `ghfast.top` 前缀）：

```bash
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/XIGUANG-CUI/socks5-deploy/main/deploy.sh \
  | sudo bash -s -- --user=proxy --passwd='MyPass123' \
      --base=https://ghfast.top/https://raw.githubusercontent.com/XIGUANG-CUI/socks5-deploy/main
```

镜像站是第三方服务，可能不稳定、也可能某天失效。**装不成功就退回方案 A**。

### 3.3 放行端口（国内云必须做）

阿里云、腾讯云、华为云有「安全组」这一层防火墙，**在服务器里改防火墙是没用的**，必须去网页控制台加规则：

1. 登录云厂商控制台 → 找到你的服务器实例
2. 进入「安全组」→「配置规则」→「入方向」→「手动添加」
3. 按下表填写：

| 项目 | 填写内容 |
|---|---|
| 协议类型 | 自定义 TCP |
| 端口范围 | `2016/2016` |
| 授权对象 / 源地址 | `0.0.0.0/0`（允许所有 IP 连） |
| 备注 | socks5 |

4. 保存

> 只想自己用的话，把「授权对象」改成你家的公网 IP，安全性更高。

### 3.4 验证

先从服务器本机测：

```bash
curl -x socks5h://proxy:MyPass123@127.0.0.1:2016 https://api.ipify.org
```

再从**你自己的电脑**上测（这一步才能证明安全组放行成功）：

```powershell
curl.exe -x socks5h://proxy:MyPass123@你的服务器IP:2016 https://api.ipify.org --max-time 15
```

- 返回服务器 IP → 全部打通
- 卡住超时 → 99% 是安全组没放行，回 3.3 检查
- 报 `Connection refused` → 服务没起来，服务器上执行 `systemctl status danted`

---

## 4. CentOS / RHEL 系服务器

如果你的是 CentOS 7、Rocky、AlmaLinux、阿里云 Linux 等，**不要用 `deploy.sh`**（它只支持 Debian/Ubuntu），改用：

```bash
cd /root/socks5-deploy

# 起一个本地文件服务（脚本只支持 http 协议读取安装包）
python3 -m http.server 8000 &

# CentOS 7 若提示 python3 不存在，改用下面这条：
# python -m SimpleHTTPServer 8000 &

SCRIPT_HOST=http://127.0.0.1:8000 \
  bash install/install_centos.sh --user=proxy --passwd='MyPass123'
```

脚本会自动帮你：
- 检测 CentOS 7 并切换到 `vault.centos.org` 源（7 已停止维护，官方源失效）
- 安装 `semanage` 并给 2016 端口打上 SELinux 标签
- 放行 firewalld 端口

装完验证：

```bash
ss -lntp | grep 2016
curl -x socks5h://proxy:MyPass123@127.0.0.1:2016 https://api.ipify.org
```

---

## 5. 客户端怎么用

代理地址格式统一是：`socks5://账号:密码@服务器IP:端口`

### Windows

| 工具 | 说明 |
|---|---|
| 系统设置 | 设置 → 网络和 Internet → 代理 → 手动设置 → SOCKS5，填 IP 和端口。**注意：Windows 系统代理不支持填写账号密码**，需要认证时用下面的工具 |
| Proxifier | 支持账号密码，可让某个程序单独走代理 |
| v2rayN / Clash | 导入 SOCKS5 节点即可，支持账号密码 |

### 手机

| 系统 | 工具 |
|---|---|
| iOS | Shadowrocket（付费）、Potatso |
| Android | v2rayNG、Clash for Android |

配置时选择 **SOCKS5** 类型，填服务器 IP、端口、账号、密码。

### 浏览器

Chrome/Edge 装 `SwitchyOmega` 插件，新建情景模式选 SOCKS5，填地址账号密码即可。

---

## 6. 日常维护

### 看状态

```bash
systemctl status danted      # deb 安装方式
systemctl status sockd       # 源码编译方式
```

### 重启

```bash
systemctl restart danted
```

### 改密码

```bash
passwd proxy
```

改完立即生效，不需要重启服务。

### 看日志

```bash
tail -f /var/log/danted.log
```

### 停止 / 卸载

```bash
systemctl disable --now danted     # 停止并取消开机自启
apt remove --purge dante-server    # Debian/Ubuntu 彻底卸载
```

---

## 7. 常见问题

| 现象 | 原因 | 解决 |
|---|---|---|
| 脚本卡在下载不动 | `raw.githubusercontent.com` 无法访问 | 改用第 3 章方案 A |
| `curl: (97) No authentication method was acceptable` | 账号或密码错误 | 检查密码特殊字符是否被 shell 吃掉，用单引号 |
| `Connection refused` | 服务没启动 | `systemctl status danted` 看报错 |
| 本机能通、外面连不上 | 云厂商安全组没放行 | 去控制台加入方向 2016/TCP 规则 |
| `external interface not found` | 配置文件里网卡名不对 | 编辑 `/etc/danted.conf`，把 `external:` 改成 `ip -br a` 里看到的网卡名 |
| Debian 12 / Ubuntu 22.04 装 deb 报依赖错误 | 系统 glibc 太低，deb 包要 2.38+ | 脚本会自动改用源码编译，无需干预 |
| 编译到最后报错 | 缺少编译依赖 | 先执行 `apt install -y build-essential libpam0g-dev libwrap0-dev` 再重跑 |

---

## 8. 安全须知

1. **不要用简单密码**，也不要把代理账号设成 `root`。
2. **不要对公网开放无密码的 SOCKS5**，会被扫端口的人当成免费跳板。
3. 只给自己用时，安全组「授权对象」填自己的固定 IP，不要填 `0.0.0.0/0`。
4. 服务器退役或不用了，记得 `systemctl disable --now danted` 并删除安全组规则。
5. 请遵守你所在地区的法律法规使用本工具。

---

## 附：文件说明（不用全看）

```
socks5-deploy/
├── deploy.sh                 # Debian/Ubuntu 一键部署脚本
├── install/                  # 原版安装脚本（CentOS 用 install_centos.sh）
├── package/                  # 预编译的 deb 安装包
├── source/                   # dante 源码包和编译辅助文件
├── script/                   # 服务管理脚本
├── windows/gost.exe          # Windows 上的替代方案（单文件 SOCKS5 服务端）
└── SHA256SUMS.txt            # 文件校验值
```
