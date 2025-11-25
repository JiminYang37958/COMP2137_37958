#!/bin/bash

# Global flags
VERBOSE=0
EXIT_STATUS=0

# Logging function
log_change() {
    logger -t configure-host "Change applied $1"
}

# Verbose output
vmsg() {
    [ "$VERBOSE" -eq 1 ] && echo "[INFO] $1"
}

# Error handler
error() {
    echo "[ERROR] $1" >&2
    EXIT_STATUS=1
}

# Require root privileges
require_root() {
    if [ "$EUID" -ne 0 ]; then
        error "PLEASE RUN THIS SCRIPT WITH SUDO."
        exit 1
    fi
}

# Ignore interrupt signals
trap '' TERM HUP INT

# ---------------------
# Hostname configuration
# ---------------------
set_hostname() {
    local desired="$1"
    local current

    current=$(hostnamectl --static 2>/dev/null || hostname)

    if [ "$current" = "$desired" ]; then
        vmsg "Hostname already set to '$desired'."
        return
    fi

    echo "$desired" > /etc/hostname || {
        error "Failed to update /etc/hostname"
        return
    }

    if grep -qE "^127\.0\.1\.1\s+$current(\s|$)" /etc/hosts; then
        sed -i "s/^127\.0\.1\.1\s\+$current.*/127.0.1.1\t$desired/" /etc/hosts
    elif grep -qE "^127\.0\.1\.1" /etc/hosts; then
        sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$desired/" /etc/hosts
    else
        echo "127.0.1.1   $desired" >> /etc/hosts
    fi

    if command -v hostnamectl >/dev/null 2>&1; then
        hostnamectl set-hostname "$desired" 2>/dev/null || hostname "$desired"
    else
        hostname "$desired"
    fi

    vmsg "Hostname changed from '$current' to '$desired'."
    log_change "Hostname changed from $current to $desired"
}

# ---------------------
# Detect LAN interface
# ---------------------
get_lan_iface() {
    local iface

    iface=$(ip -o -4 addr show | awk '$2!="lo"{print $2,$4}' \
        | awk '$2 ~ /^192\.168\.16\./ {print $1; exit}')

    if [ -z "$iface" ]; then
        iface=$(ip -o -4 addr show | awk '$2!="lo"{print $2; exit}')
    fi

    echo "$iface"
}

# ---------------------
# IP configuration
# ---------------------
set_ip() {
    local desired_ip="$1"
    local lan_if current_cidr current_ip prefix desired_cidr
    local netplan_file

    lan_if=$(get_lan_iface)
    if [ -z "$lan_if" ]; then
        error "Unable to determine LAN interface."
        return
    fi

    current_cidr=$(ip -o -4 addr show dev "$lan_if" | awk '{print $4}' | head -n1)
    current_ip=${current_cidr%%/*}
    prefix=${current_cidr##*/}

    if [ "$current_ip" = "$desired_ip" ]; then
        vmsg "IP for $lan_if already set to $desired_ip."
        return
    fi

    desired_cidr="$desired_ip/$prefix"

    local hn
    hn=$(hostnamectl --static 2>/dev/null || hostname)

    # Update /etc/hosts
    if grep -qE "^$current_ip\s+$hn(\s|$)" /etc/hosts; then
        sed -i "s/^$current_ip\s\+$hn.*/$desired_ip\t$hn/" /etc/hosts
    elif grep -qE "^$desired_ip\s+$hn(\s|$)" /etc/hosts; then
        :
    else
        echo "$desired_ip   $hn" >> /etc/hosts
    fi

    netplan_file=$(ls /etc/netplan/*.yaml 2>/dev/null | head -n1)
    if [ -z "$netplan_file" ]; then
        error "No netplan configuration file found."
        return
    fi

    cp "$netplan_file" "${netplan_file}.bak.$(date +%s)" || {
        error "Failed to backup netplan file."
        return
    }

    # --- FIX: sed delimiter changed from / to # to avoid CIDR errors ---
    if grep -q "$current_cidr" "$netplan_file"; then
        sed -i "s#$current_cidr#$desired_cidr#" "$netplan_file"
    else
        error "Current IP not found inside netplan file."
        return
    fi

    ip addr flush dev "$lan_if" >/dev/null 2>&1
    ip addr add "$desired_cidr" dev "$lan_if" || {
        error "Failed to assign new IP."
        return
    }
    ip link set "$lan_if" up >/dev/null 2>&1

    if command -v netplan >/dev/null 2>&1; then
        netplan apply >/dev/null 2>&1 || vmsg "netplan apply reported a warning."
    fi

    vmsg "IP on $lan_if changed from $current_ip to $desired_ip."
    log_change "IP on $lan_if changed from $current_ip to $desired_ip"
}

# ---------------------
# /etc/hosts entry mgmt
# ---------------------
ensure_hostentry() {
    local name="$1"
    local ip="$2"

    if grep -qE "^$ip\s+$name(\s|$)" /etc/hosts; then
        vmsg "Host entry '$name $ip' already present."
        return
    fi

    if grep -qE "^\S+\s+$name(\s|$)" /etc/hosts; then
        sed -i "s/^\S\+\s\+$name.*/$ip\t$name/" /etc/hosts
    else
        echo "$ip   $name" >> /etc/hosts
    fi

    vmsg "Host entry for $name set to $ip."
    log_change "Host entry updated for $name → $ip"
}

# ---------------------
# Argument parsing
# ---------------------
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -verbose)
                VERBOSE=1
                ;;
            -name|-hostname)
                set_hostname "$2"
                shift
                ;;
            -ip)
                set_ip "$2"
                shift
                ;;
            -hostentry)
                ensure_hostentry "$2" "$3"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
        shift
    done
}

# ---------------------
# Main
# ---------------------
require_root
parse_args "$@"
exit $EXIT_STATUS
