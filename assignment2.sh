#!/bin/bash
# COMP2137 Assignment 2 configuration script
# This script is intended to be run as root on server1.

echo "==========================================="
echo "  COMP2137 - Assignment 2 configuration"
echo "==========================================="

#------------------------------------------------------------------
# 0. Require root
#------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] This script must be run as root." >&2
    exit 1
fi

#------------------------------------------------------------------
# 1. Network configuration: netplan + /etc/hosts
#------------------------------------------------------------------
echo
echo "==== 1) Network configuration (192.168.16.21/24) ===="

NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -n 1)

if [ -z "$NETPLAN_FILE" ]; then
    echo "[ERROR] No netplan YAML file found in /etc/netplan."
else
    echo "[INFO] Using netplan file: $NETPLAN_FILE"

    if grep -q "192.168.16.21/24" "$NETPLAN_FILE"; then
        echo "[INFO] Netplan already configured for 192.168.16.21/24."
    else
        if grep -q "192.168.16." "$NETPLAN_FILE"; then
            sed -i 's/192\.168\.16\.[0-9]\+\/24/192.168.16.21\/24/' "$NETPLAN_FILE"
            echo "[INFO] Updated existing 192.168.16.x address to 192.168.16.21/24."
        else
            echo "[WARN] No existing 192.168.16.x/24 address found in $NETPLAN_FILE."
        fi
        echo "[INFO] Applying netplan configuration..."
        if netplan apply 2>/tmp/netplan-error.log; then
            echo "[INFO] netplan apply succeeded."
        else
            echo "[ERROR] netplan apply failed. See /tmp/netplan-error.log for details."
        fi
    fi
fi

# Update /etc/hosts
echo
echo "[INFO] Updating /etc/hosts for server1..."
if grep -q "server1" /etc/hosts; then
    sed -i '/server1/d' /etc/hosts
fi

if grep -q "^192\.168\.16\.21[[:space:]]\+server1" /etc/hosts; then
    echo "[INFO] /etc/hosts already contains correct entry."
else
    echo "192.168.16.21 server1" >> /etc/hosts
    echo "[INFO] Added '192.168.16.21 server1' to /etc/hosts."
fi

#------------------------------------------------------------------
# 2. Software installation: apache2 + squid
#------------------------------------------------------------------
echo
echo "==== 2) Software installation (apache2, squid) ===="

APT_UPDATED=0

install_pkg_if_needed() {
    local pkg="$1"
    if dpkg -l | grep -qw "$pkg"; then
        echo "[INFO] Package '$pkg' already installed."
    else
        if [ "$APT_UPDATED" -eq 0 ]; then
            echo "[INFO] Running apt-get update..."
            apt-get update -y
            APT_UPDATED=1
        fi
        echo "[INFO] Installing $pkg..."
        if apt-get install -y "$pkg"; then
            echo "[INFO] $pkg installed successfully."
        else
            echo "[ERROR] Failed to install $pkg."
        fi
    fi
}

install_pkg_if_needed "apache2"
install_pkg_if_needed "squid"

echo "[INFO] Enabling and starting apache2..."
systemctl enable --now apache2 2>/dev/null || echo "[WARN] Could not enable/start apache2."

echo "[INFO] Enabling and starting squid..."
systemctl enable --now squid 2>/dev/null || echo "[WARN] Could not enable/start squid."

#------------------------------------------------------------------
# 3. User accounts and SSH keys
#------------------------------------------------------------------
echo
echo "==== 3) User accounts and SSH keys ===="

USERS=(dennis aubrey captain snibbles brownie scooter sandy perrier cindy tiger yoda)

for user in "${USERS[@]}"; do
    echo
    echo "[INFO] Processing user: $user"

    if id "$user" &>/dev/null; then
        echo "[INFO] User '$user' already exists."
    else
        echo "[INFO] Creating user '$user'..."
        useradd -m -s /bin/bash "$user"
    fi

    HOME_DIR="/home/$user"

    if [ ! -d "$HOME_DIR" ]; then
        echo "[ERROR] Home directory $HOME_DIR does not exist for $user."
        continue
    fi

    if [ ! -d "$HOME_DIR/.ssh" ]; then
        echo "[INFO] Creating $HOME_DIR/.ssh..."
        mkdir -p "$HOME_DIR/.ssh"
    fi

    chmod 700 "$HOME_DIR/.ssh"
    chown "$user:$user" "$HOME_DIR/.ssh"

    AUTH_KEYS="$HOME_DIR/.ssh/authorized_keys"
    touch "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    chown "$user:$user" "$AUTH_KEYS"

    # RSA key
    if [ ! -f "$HOME_DIR/.ssh/id_rsa" ]; then
        echo "[INFO] Generating RSA key for $user..."
        su - "$user" -c "ssh-keygen -t rsa -b 2048 -N '' -f ~/.ssh/id_rsa -q"
    else
        echo "[INFO] RSA key already exists for $user."
    fi

    # ED25519 key
    if [ ! -f "$HOME_DIR/.ssh/id_ed25519" ]; then
        echo "[INFO] Generating ED25519 key for $user..."
        su - "$user" -c "ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519 -q"
    else
        echo "[INFO] ED25519 key already exists for $user."
    fi

    # Add public keys to authorized_keys (no duplicates)
    for pubkey in "$HOME_DIR/.ssh/id_rsa.pub" "$HOME_DIR/.ssh/id_ed25519.pub"; do
        if [ -f "$pubkey" ]; then
            KEY_CONTENT=$(cat "$pubkey")
            if grep -qxF "$KEY_CONTENT" "$AUTH_KEYS"; then
                echo "[INFO] $(basename "$pubkey") already in authorized_keys."
            else
                echo "[INFO] Adding $(basename "$pubkey") to authorized_keys."
                echo "$KEY_CONTENT" >> "$AUTH_KEYS"
            fi
        fi
    done

    # Special config for dennis
    if [ "$user" = "dennis" ]; then
        echo "[INFO] Adding dennis to sudo group..."
        usermod -aG sudo dennis

        PROFESSOR_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm"

        if grep -qxF "$PROFESSOR_KEY" "$AUTH_KEYS"; then
            echo "[INFO] Professor key already present for dennis."
        else
            echo "[INFO] Adding professor key to dennis's authorized_keys."
            echo "$PROFESSOR_KEY" >> "$AUTH_KEYS"
        fi
    fi

    chmod 700 "$HOME_DIR/.ssh"
    chmod 600 "$AUTH_KEYS"
    chown -R "$user:$user" "$HOME_DIR/.ssh"
done

echo
echo "==========================================="
echo " Assignment 2 configuration complete."
echo " You can safely re-run this script any time."
echo "==========================================="
