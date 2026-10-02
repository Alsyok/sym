#!/usr/bin/env bash

# ========= 颜色 =========
CYAN=$'\033[1;36m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
GRAY=$'\033[90m'
RESET=$'\033[0m'

if [[ ! -t 1 ]]; then
    CYAN=""
    GREEN=""
    YELLOW=""
    GRAY=""
    RESET=""
fi

# ========= 通用界面 =========
line() {
    printf '  %s────────────────────────────────────────%s\n' \
        "$GRAY" "$RESET"
}

pause() {
    printf '\n'
    read -r -p "  按回车返回菜单…" || exit 0
}

page() {
    if [[ -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" ]]; then
        clear 2>/dev/null
    fi

    printf '\n  %s%s%s\n' "$CYAN" "$1" "$RESET"
    line
}

# ========= 公网地址和地区 =========
load_ip() {
    PUBLIC_IP="未获取"
    PUBLIC_IPV6="未获取"
    IP_REGION="未获取"

    if ! command -v curl >/dev/null 2>&1; then
        PUBLIC_IP="需要安装 curl"
        PUBLIC_IPV6="需要安装 curl"
        return
    fi

    local ipv4 ipv6 region country family

    printf '  正在查询公网地址和地区，请稍候…\n'

    ipv4=$(curl -4 -fsS --connect-timeout 3 --max-time 6 \
        https://api.ipify.org 2>/dev/null)

    if [[ "$ipv4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        PUBLIC_IP="$ipv4"
    fi

    ipv6=$(curl -6 -fsS --connect-timeout 3 --max-time 6 \
        https://api6.ipify.org 2>/dev/null)

    if [[ "$ipv6" == *:* && "$ipv6" =~ ^[0-9a-fA-F:]+$ ]]; then
        PUBLIC_IPV6="$ipv6"
    fi

    # 优先查询 IPv4 出口地区，失败后尝试 IPv6
    for family in -4 -6; do
        region=$(curl "$family" -fsS \
            --connect-timeout 3 --max-time 6 \
            https://ipinfo.io/region 2>/dev/null) || continue

        region="${region//$'\r'/}"

        if [[ -z "$region" ||
              ${#region} -gt 120 ||
              "$region" == *$'\n'* ||
              "$region" == *'<'* ||
              "$region" == *'{'* ||
              "$region" == *'}'* ]]; then
            continue
        fi

        country=$(curl "$family" -fsS \
            --connect-timeout 3 --max-time 6 \
            https://ipinfo.io/country 2>/dev/null)

        country="${country//$'\r'/}"

        if [[ "$country" =~ ^[A-Z]{2}$ ]]; then
            IP_REGION="$region / $country"
        else
            IP_REGION="$region / 国家未获取"
        fi

        break
    done
}

# ========= 系统概览 =========
show_summary() {
    local system_name cpu_count memory disk

    system_name="未知 Linux"

    if [[ -r /etc/os-release ]]; then
        system_name=$(
            . /etc/os-release
            printf '%s' "${PRETTY_NAME:-Linux}"
        )
    fi

    cpu_count=$(getconf _NPROCESSORS_ONLN 2>/dev/null)

    if [[ -z "$cpu_count" ]] &&
       command -v nproc >/dev/null 2>&1; then
        cpu_count=$(nproc 2>/dev/null)
    fi

    memory=$(free -m 2>/dev/null |
        awk '/^Mem:/ {printf "%s / %s MiB", $3, $2}')

    # -P 保证文件系统信息不换行，兼容 Alpine
    disk=$(df -Ph / 2>/dev/null |
        awk 'NR==2 && NF>=6 {
            printf "%s / %s（%s）", $3, $2, $5
        }')

    # 标签均占 10 个显示位置，右侧内容统一起点
    printf '  %s系统      %s%s\n' \
        "$CYAN" "$RESET" "$system_name"
    printf '  %sCPU       %s%s 核\n' \
        "$CYAN" "$RESET" "${cpu_count:-未知}"
    printf '  %s内存      %s%s\n' \
        "$CYAN" "$RESET" "${memory:-未获取}"
    printf '  %s根分区    %s%s\n' \
        "$CYAN" "$RESET" "${disk:-未获取}"
    printf '  %s公网 IPv4 %s%s\n' \
        "$CYAN" "$RESET" "$PUBLIC_IP"
    printf '  %s公网 IPv6 %s%s\n' \
        "$CYAN" "$RESET" "$PUBLIC_IPV6"
    printf '  %sIP 地区   %s%s\n' \
        "$CYAN" "$RESET" "$IP_REGION"
}

# ========= 系统信息子菜单 =========
system_menu() {
    local choice

    while true; do
        page "工具箱 / 系统信息"

        printf '  %s1%s  系统版本与内核\n' "$GREEN" "$RESET"
        printf '  %s2%s  CPU 详细信息\n' "$GREEN" "$RESET"
        printf '  %s3%s  内存使用情况\n' "$GREEN" "$RESET"
        printf '  %s4%s  磁盘使用情况\n' "$GREEN" "$RESET"
        printf '  %s5%s  本机网络地址\n' "$GREEN" "$RESET"
        printf '  %s6%s  刷新公网 IP 和地区\n' "$GREEN" "$RESET"
        printf '\n  0  返回主菜单\n'
        line

        read -r -p "  请选择 › " choice || return

        case "$choice" in
            1)
                printf '\n'
                if [[ -r /etc/os-release ]]; then
                    cat /etc/os-release
                fi
                printf '\n内核版本：'
                uname -r
                pause
                ;;
            2)
                printf '\n'
                if command -v lscpu >/dev/null 2>&1; then
                    lscpu
                elif [[ -r /proc/cpuinfo ]]; then
                    cat /proc/cpuinfo
                else
                    printf '无法获取 CPU 信息。\n'
                fi
                pause
                ;;
            3)
                printf '\n'
                if command -v free >/dev/null 2>&1; then
                    free -h
                else
                    printf '未找到 free 命令。\n'
                fi
                pause
                ;;
            4)
                printf '\n'
                df -Ph
                pause
                ;;
            5)
                printf '\n'
                if command -v ip >/dev/null 2>&1; then
                    ip address
                else
                    printf '未找到 ip 命令。\n'
                fi
                pause
                ;;
            6)
                printf '\n'
                load_ip
                printf '\n公网 IPv4：%s\n' "$PUBLIC_IP"
                printf '公网 IPv6：%s\n' "$PUBLIC_IPV6"
                printf 'IP 地区：%s\n' "$IP_REGION"
                pause
                ;;
            0)
                return
                ;;
            *)
                printf '\n  %s选择无效，请重新输入。%s\n' \
                    "$YELLOW" "$RESET"
                pause
                ;;
        esac
    done
}

# ========= 脚本中心子菜单 =========
script_menu() {
    local choice

    while true; do
        page "工具箱 / 脚本中心"

        printf '  %s1%s  sing-box 安装脚本（待接入）\n' \
            "$GREEN" "$RESET"
        printf '  %s2%s  测速脚本（待接入）\n' \
            "$GREEN" "$RESET"
        printf '  %s3%s  自定义脚本（待接入）\n' \
            "$GREEN" "$RESET"
        printf '\n  0  返回主菜单\n'
        line

        read -r -p "  请选择 › " choice || return

        case "$choice" in
            1|2|3)
                printf '\n  %s这个入口尚未接入脚本。%s\n' \
                    "$YELLOW" "$RESET"
                pause
                ;;
            0)
                return
                ;;
            *)
                printf '\n  %s选择无效，请重新输入。%s\n' \
                    "$YELLOW" "$RESET"
                pause
                ;;
        esac
    done
}

# ========= 启动 =========
load_ip

# ========= 主菜单 =========
while true; do
    page "VPS TOOLBOX · 服务器工具箱 v0.3"

    show_summary
    line

    printf '  %s1%s  系统信息  ›\n' "$GREEN" "$RESET"
    printf '  %s2%s  脚本中心  ›\n' "$GREEN" "$RESET"
    printf '\n  0  退出工具箱\n'
    line

    read -r -p "  请选择 › " choice || break

    case "$choice" in
        1)
            system_menu
            ;;
        2)
            script_menu
            ;;
        0)
            printf '\n  已退出工具箱。\n\n'
            break
            ;;
        *)
            printf '\n  %s选择无效，请重新输入。%s\n' \
                "$YELLOW" "$RESET"
            pause
            ;;
    esac
done
