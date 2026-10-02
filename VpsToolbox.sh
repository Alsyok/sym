#!/usr/bin/env bash

VERSION="0.4"

SB_DEBIAN="https://raw.githubusercontent.com/hooghub/singboxversion/main/sbinstall.sh"
SB_ALPINE="https://raw.githubusercontent.com/hooghub/Alpine01/main/Encrypt.sh"
XR_ALPINE="https://raw.githubusercontent.com/hooghub/ksy/main/musl-Xray.sh"

CYAN=$'\033[1;36m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
RESET=$'\033[0m'

if [[ ! -t 1 ]]; then
    CYAN="" GREEN="" YELLOW="" RESET=""
fi

OS_ID="unknown"
if [[ -r /etc/os-release ]]; then
    OS_ID=$(. /etc/os-release; printf '%s' "${ID:-unknown}")
fi

line() {
    printf '  ────────────────────────────────────────\n'
}

page() {
    if [[ -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" ]]; then
        clear 2>/dev/null
    fi
    printf '\n  %s%s%s\n' "$CYAN" "$1" "$RESET"
    line
}

pause() {
    printf '\n'
    read -r -p "  按回车返回…" || exit 0
}

warn() {
    printf '\n  %s%s%s\n' "$YELLOW" "$1" "$RESET"
}

item() {
    printf '  %s%s%s  %s\n' "$GREEN" "$1" "$RESET" "$2"
}

# ========= 公网信息 =========
load_ip() {
    PUBLIC_IP="未获取"
    PUBLIC_IPV6="未获取"
    IP_REGION="未获取"

    command -v curl >/dev/null 2>&1 || {
        PUBLIC_IP="需要安装 curl"
        return
    }

    local ip region country family
    printf '  正在查询公网信息…\n'

    ip=$(curl -4 -fsS --connect-timeout 3 --max-time 6 \
        https://api.ipify.org 2>/dev/null)
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        PUBLIC_IP="$ip"
    fi

    ip=$(curl -6 -fsS --connect-timeout 3 --max-time 6 \
        https://api6.ipify.org 2>/dev/null)
    if [[ "$ip" == *:* && "$ip" =~ ^[0-9a-fA-F:]+$ ]]; then
        PUBLIC_IPV6="$ip"
    fi

    for family in -4 -6; do
        region=$(curl "$family" -fsS --connect-timeout 3 \
            --max-time 6 https://ipinfo.io/region 2>/dev/null) || continue
        region="${region//$'\r'/}"

        if [[ -z "$region" || ${#region} -gt 120 ||
              "$region" == *$'\n'* || "$region" == *'<'* ||
              "$region" == *'{'* ]]; then
            continue
        fi

        country=$(curl "$family" -fsS --connect-timeout 3 \
            --max-time 6 https://ipinfo.io/country 2>/dev/null)
        country="${country//$'\r'/}"

        if [[ "$country" =~ ^[A-Z]{2}$ ]]; then
            IP_REGION="$region / $country"
        else
            IP_REGION="$region / 国家未获取"
        fi
        break
    done
}

summary() {
    local name cpu mem disk
    name="未知 Linux"

    if [[ -r /etc/os-release ]]; then
        name=$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-Linux}")
    fi

    cpu=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
    [[ -n "$cpu" ]] || cpu=$(nproc 2>/dev/null)

    mem=$(free -m 2>/dev/null |
        awk '/^Mem:/ {printf "%s / %s MiB", $3, $2}')
    disk=$(df -Ph / 2>/dev/null |
        awk 'NR==2 && NF>=6 {printf "%s / %s（%s）", $3, $2, $5}')

    printf '  %s系统      %s%s\n' "$CYAN" "$RESET" "$name"
    printf '  %sCPU       %s%s 核\n' "$CYAN" "$RESET" "${cpu:-未知}"
    printf '  %s内存      %s%s\n' "$CYAN" "$RESET" "${mem:-未获取}"
    printf '  %s根分区    %s%s\n' "$CYAN" "$RESET" "${disk:-未获取}"
    printf '  %s公网 IPv4 %s%s\n' "$CYAN" "$RESET" "$PUBLIC_IP"
    printf '  %s公网 IPv6 %s%s\n' "$CYAN" "$RESET" "$PUBLIC_IPV6"
    printf '  %sIP 地区   %s%s\n' "$CYAN" "$RESET" "$IP_REGION"
}

# ========= 下载并运行节点脚本 =========
run_node_script() {
    local core="$1" url file result

    case "$core:$OS_ID" in
        sing-box:alpine) url="$SB_ALPINE" ;;
        sing-box:debian) url="$SB_DEBIAN" ;;
        xray:alpine) url="$XR_ALPINE" ;;
        *)
            warn "当前系统 $OS_ID 尚未接入此安装脚本。"
            return 1
            ;;
    esac

    if (( EUID != 0 )); then
        warn "请使用 root 用户运行节点管理功能。"
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        warn "未找到 curl，请先安装 curl。"
        return 1
    fi

    file=$(mktemp) || return 1

    # 下载成功后才执行，避免运行下载不完整的内容
    if ! curl -fL --connect-timeout 10 --max-time 120 \
        "$url" -o "$file"; then
        rm -f "$file"
        warn "下载失败，未执行节点脚本。"
        return 1
    fi

    bash "$file"
    result=$?
    rm -f "$file"

    if (( result != 0 )); then
        warn "节点脚本退出码：$result"
    fi
    return "$result"
}

# ========= 检测服务 =========
find_service() {
    local core="$1" name load
    local names=("$core")
    [[ "$core" == "sing-box" ]] && names+=("singbox")

    SERVICE=""
    MANAGER=""

    if [[ -d /run/systemd/system ]] &&
       command -v systemctl >/dev/null 2>&1; then
        for name in "${names[@]}"; do
            load=$(systemctl show "$name.service" \
                -p LoadState --value 2>/dev/null)
            if [[ -n "$load" && "$load" != "not-found" ]]; then
                SERVICE="$name"
                MANAGER="systemd"
                return 0
            fi
        done
    fi

    if command -v rc-service >/dev/null 2>&1; then
        for name in "${names[@]}"; do
            if [[ -x "/etc/init.d/$name" ]]; then
                SERVICE="$name"
                MANAGER="openrc"
                return 0
            fi
        done
    fi

    return 1
}

service_action() {
    local core="$1" action="$2"

    if ! find_service "$core"; then
        warn "未找到 $core 的常见服务名，请通过原节点脚本管理。"
        return 1
    fi

    if [[ "$action" == "restart" ]] && (( EUID != 0 )); then
        warn "重启服务需要 root 权限。"
        return 1
    fi

    printf '\n  服务：%s，管理方式：%s\n\n' "$SERVICE" "$MANAGER"

    case "$MANAGER:$action" in
        systemd:status)
            systemctl status "$SERVICE" --no-pager
            ;;
        openrc:status)
            rc-service "$SERVICE" status
            ;;
        systemd:restart)
            if systemctl restart "$SERVICE"; then
                printf '  重启命令执行成功。\n'
                systemctl status "$SERVICE" --no-pager
            else
                warn "重启失败。"
            fi
            ;;
        openrc:restart)
            if rc-service "$SERVICE" restart; then
                rc-service "$SERVICE" status
            else
                warn "重启失败。"
            fi
            ;;
    esac
}

# ========= 节点管理子菜单 =========
node_menu() {
    local core="$1" title="$2" choice confirm

    while true; do
        page "工具箱 / 脚本中心 / $title 管理"
        item 1 "安装 $title"
        item 2 "查看节点信息"
        item 3 "查看运行状态"
        item 4 "重启 $title"
        item 5 "卸载 $title"
        printf '\n  0  返回上级菜单\n'
        line
        read -r -p "  请选择 › " choice || return

        case "$choice" in
            1)
                run_node_script "$core"
                pause
                ;;
            2)
                warn "将打开原节点脚本，请选择其中的节点信息查询功能。"
                read -r -p "  回车继续，输入 0 取消：" confirm || return
                if [[ "$confirm" != "0" ]]; then
                    run_node_script "$core"
                fi
                pause
                ;;
            3)
                service_action "$core" status
                pause
                ;;
            4)
                service_action "$core" restart
                pause
                ;;
            5)
                warn "将打开原节点脚本，请使用它提供的卸载功能。"
                warn "此工具箱不会自行删除服务或配置。"
                read -r -p "  回车继续，输入 0 取消：" confirm || return
                if [[ "$confirm" != "0" ]]; then
                    run_node_script "$core"
                fi
                pause
                ;;
            0) return ;;
            *) warn "选择无效。"; pause ;;
        esac
    done
}

# ========= 脚本中心 =========
script_menu() {
    local choice
    while true; do
        page "工具箱 / 脚本中心"
        item 1 "sing-box 管理 ›"
        item 2 "Xray 管理 ›（仅 Alpine）"
        printf '\n  0  返回主菜单\n'
        line
        read -r -p "  请选择 › " choice || return

        case "$choice" in
            1) node_menu sing-box sing-box ;;
            2)
                if [[ "$OS_ID" == "alpine" ]]; then
                    node_menu xray Xray
                else
                    warn "Xray 入口仅支持 Alpine。"
                    pause
                fi
                ;;
            0) return ;;
            *) warn "选择无效。"; pause ;;
        esac
    done
}

# ========= 系统信息 =========
system_menu() {
    local choice
    while true; do
        page "工具箱 / 系统信息"
        item 1 "系统版本与内核"
        item 2 "CPU 详细信息"
        item 3 "内存使用情况"
        item 4 "磁盘使用情况"
        item 5 "本机网络地址"
        item 6 "刷新公网 IP 和地区"
        printf '\n  0  返回主菜单\n'
        line
        read -r -p "  请选择 › " choice || return

        case "$choice" in
            1)
                cat /etc/os-release
                uname -r
                pause
                ;;
            2)
                if command -v lscpu >/dev/null 2>&1; then
                    lscpu
                else
                    cat /proc/cpuinfo
                fi
                pause
                ;;
            3) free -h; pause ;;
            4) df -Ph; pause ;;
            5)
                if command -v ip >/dev/null 2>&1; then
                    ip address
                else
                    warn "未找到 ip 命令。"
                fi
                pause
                ;;
            6) load_ip; summary; pause ;;
            0) return ;;
            *) warn "选择无效。"; pause ;;
        esac
    done
}

# ========= 主菜单 =========
load_ip

while true; do
    page "VPS TOOLBOX · 服务器工具箱 v$VERSION"
    summary
    line
    item 1 "系统信息 ›"
    item 2 "脚本中心 ›"
    printf '\n  0  退出工具箱\n'
    line

    read -r -p "  请选择 › " choice || break

    case "$choice" in
        1) system_menu ;;
        2) script_menu ;;
        0) printf '\n  已退出工具箱。\n'; break ;;
        *) warn "选择无效。"; pause ;;
    esac
done
