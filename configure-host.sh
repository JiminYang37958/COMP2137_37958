#!/bin/bash
# COMP2137 Assignment 3 - configure-host.sh
# Configure hostname, IP address, and /etc/hosts entries.

# Ignore TERM, HUP, INT signals
trap '' TERM HUP INT

VERBOSE=0

log_msg() {
    # $1 = message
    if [ "$VERBOSE" -eq 1 ]; then
        echo "$1"
    fi
}

error_msg() {
    # errors should always be shown
    echo "[ERROR] $1" >&2
}

# Check for root
if [ "$EUID" -ne 0 ]; then
    error_msg "This script must be run as root."
    exit 1
fi

NEW_NAME=""
NEW_IP=""
HOSTENTRY_NAMES=()
HOSTENTRY_IPS=()

# -----------------------------
# Parse command line arguments
# -----------------------------
while [ "$#" -gt 0 ]; do
    case "$1" in
        -verbose)
            VERBOSE=1
            shift
            ;;
        -name)
            NEW_NAME="$2"
            shift 2
            ;;
        -ip)
            NEW_IP="$2"
            shift 2
            ;;
        -hostentry)
            if [ -z "$2" ] || [ -z "$3" ]; then
                error_msg "-hostentry requires name and IP."
                exit 1
            fi
            HOSTENTRY_NAMES+=("$2")
            HOSTENTRY_IPS+=("$3")
            shift 3
            ;;
        *)
            error_msg "Unknown option: $1"
            exit 1
            ;;
    esac
done

# -----------------------------
# 1) Hostname configuration
# -----------------------------
if [ -n "$NEW_NAME" ]; then
    CURRENT_NAME=$(hostname)
    if [ "$CURRENT_NAME" = "$NEW_NAME" ]; then
        log_msg "[INFO] Hostname already set to $NEW_NAME."
    else
        log_msg "[INFO] Changing hostname from $CURRENT_NAME to $NEW_NAME..."

        # Update /etc/hostname
        echo "$NEW_NAME" > /etc/hostname

        # Update running hostname
        hostname "$NEW_NAME"

        # Update 127.0.1.1 line in /etc/hosts if it exists
        if grep -q "^127\.0\.1\.1" /etc/hosts; then
            sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$NEW_NAME/" /etc/hosts
        else
            echo "127.0.1.1    $NEW_NAME" >> /etc/hosts
        fi

        logger "configure-host: Hostname changed from $CURRENT_NAME to $NEW_NAME"
    fi
fi

# -----------------------------
# 2) IP configuration
# -----------------------------
if [ -n "$NEW_IP" ]; then
    NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -n 1)
    if [ -z "$NETPLAN_FILE" ]; then
        error_msg "No netplan file found in /etc/netplan."
    else
        log_msg "[INFO] Using netplan file: $NETPLAN_FILE"

        # use /24 as in previous assignments
        if grep -q "$NEW_IP/24" "$NETPLAN_FILE"; then
            log_msg "[INFO] Netplan already has $NEW_IP/24."
        else
            # Replace any 192.168.16.x/24 entry with the new IP
            if grep -q "192.168.16." "$NETPLAN_FILE"; then
                OLD_ADDR=$(grep -o "192\.168\.16\.[0-9]\+/24" "$NETPLAN_FILE" | head -n 1)
                sed -i "s/$OLD_ADDR/$NEW_IP\/24/" "$NETPLAN_FILE"
                log_msg "[INFO] Changed $OLD_ADDR to $NEW_IP/24 in netplan."
                logger "configure-host: IP changed in netplan from $OLD_ADDR to $NEW_IP/24"
            else
                log_msg "[WARN] No 192.168.16.x/24 entry found in netplan file."
            fi
        fi

        log_msg "[INFO] Applying netplan..."
        if ! netplan apply 2>/tmp/configure-host-netplan-error.log; then
            error_msg "netplan apply failed (see /tmp/configure-host-netplan-error.log)."
        fi
    fi

    # Update /etc/hosts own IP entry (192.168.16.x hostname)
    HOSTNAME_NOW=$(hostname)
    if grep -q "192\.168\.16\." /etc/hosts; then
        OLD_LINE=$(grep "192\.168\.16\." /etc/hosts | head -n 1)
        sed -i "s/^192\.168\.16\.[0-9]\+\s\+.*/$NEW_IP $HOSTNAME_NOW/" /etc/hosts
        log_msg "[INFO] Updated /etc/hosts from '$OLD_LINE' to '$NEW_IP $HOSTNAME_NOW'."
        logger "configure-host: IP host entry changed in /etc/hosts to $NEW_IP $HOSTNAME_NOW"
    else
        echo "$NEW_IP $HOSTNAME_NOW" >> /etc/hosts
        log_msg "[INFO] Added '$NEW_IP $HOSTNAME_NOW' to /etc/hosts."
        logger "configure-host: Added IP host entry $NEW_IP $HOSTNAME_NOW to /etc/hosts"
    fi

    # Change running IP (best effort) – get lan interface with 192.168.16.x
    LAN_IF=$(ip -4 addr show | awk '/192\.168\.16\./ {print $NF; exit}')
    if [ -n "$LAN_IF" ]; then
        CURRENT_IP=$(ip -4 addr show "$LAN_IF" | awk '/192\.168\.16\./ {sub("/24","",$2); print $2; exit}')
        if [ "$CURRENT_IP" != "$NEW_IP" ]; then
            log_msg "[INFO] Changing IP on $LAN_IF from $CURRENT_IP to $NEW_IP/24..."
            ip addr flush dev "$LAN_IF"
            ip addr add "$NEW_IP/24" dev "$LAN_IF"
            logger "configure-host: Runtime IP on $LAN_IF changed from $CURRENT_IP to $NEW_IP/24"
        else
            log_msg "[INFO] Runtime IP already $NEW_IP/24 on $LAN_IF."
        fi
    else
        log_msg "[WARN] Could not find interface with 192.168.16.x to change runtime IP."
    fi
fi

# -----------------------------
# 3) /etc/hosts hostentry updates
# -----------------------------
if [ "${#HOSTENTRY_NAMES[@]}" -gt 0 ]; then
    i=0
    while [ $i -lt ${#HOSTENTRY_NAMES[@]} ]; do
        NAME="${HOSTENTRY_NAMES[$i]}"
        IP="${HOSTENTRY_IPS[$i]}"

        # Remove any existing line for that name or IP
        if grep -q "[[:space:]]$NAME\$" /etc/hosts; then
            OLD_LINE=$(grep "[[:space:]]$NAME\$" /etc/hosts | head -n 1)
            sed -i "/[[:space:]]$NAME\$/d" /etc/hosts
            log_msg "[INFO] Removed old hosts entry: $OLD_LINE"
        fi

        # Add the desired line
        echo "$IP $NAME" >> /etc/hosts
        log_msg "[INFO] Added hosts entry: $IP $NAME"
        logger "configure-host: hosts entry set to '$IP $NAME'"

        i=$((i + 1))
    done
fi

exit 0
