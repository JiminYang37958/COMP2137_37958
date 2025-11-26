#!/bin/bash
# COMP2137 Assignment 2 - server1 configuration script

echo "==========================================="
echo "  COMP2137 - Assignment 2 configuration"
echo "==========================================="

# 0. Must be root
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Please run this script as root." >&2
    exit 1
fi

# -------------------------------------------
# 1. Network configuration (netplan + /etc/hosts)
# -------------------------------------------
echo
echo "---- Step 1: Network configuration ----"

NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -n 1)

if [ -z "$NETPLAN_FILE" ]; then
    echo "[ERROR] No netplan file found in /etc/netplan."
else
    echo "[INFO] Using netplan file: $NETPLAN_FILE"

    # if already correct, do nothing
    if grep -q "192.168.16.21/24" "$NETPLAN_FILE"; then
        echo "[INFO] Netplan already has 192.168.16.21/24."
    else
        # replace any 192.168.16.x/24 with 192.168.16.21/24
        if grep -q "192.168.16." "$NETPLAN_FILE"; then
            sed -i 's/192\.168\.16\.[0-9]\+\/24/192.168.16.21\/24/' "$NETPLAN_FILE"
            echo "[INFO] Changed 192.168.16.x/24 to 192.168.16.21/24."
        else
            echo "[WARN] Did not find 192.168.16.x/24 in netplan file."
        fi

        echo "[INFO] Applying netplan..."
        if netplan apply 2>/tmp/netplan-error.log; then
            echo "[INFO] netplan apply succeeded."
        else
            echo "[ERROR] netplan apply failed (see /tmp/netplan-error.log)."
        fi
    fi
fi

echo
echo "[INFO] Updating /etc/hosts for server1..."

# remove old server1 lines
if grep -q "server1" /etc/hosts; then
    sed -i '/[[:space:]]server1$/d' /etc/hosts
fi

# add correct entry
if grep -q "^192\.168\.16\.21[[:space:]]\+server1" /etc/hosts; then
    echo "[INFO] /etc/hosts already has '192.168.16.21 server1'."
else
    echo "192.168.16.21 server1" >> /etc/hosts
    echo "[INFO] Added '192.168.16.21 server1' to /etc/hosts."
fi

# -------------------------------------------
# 2. Software installation (apache2, squid)
# -------------------------------------------
echo
echo "---- Step 2: Software installation ----"

APT_UPDATED=0

install_pkg() {
    pkg="$1"
    if dpkg -l | grep -qw "$pkg"; then
        echo "[INFO] $pkg already installed."
    else
        if [ "$APT_UPDATED" -eq 0 ]; then
            echo "[INFO] Running apt-get update..."
            apt-get update -y
            APT_UPDATED=1
        fi
        echo "[INFO] Installing $pkg..."
        if apt-get install -y "$pkg"; then
            echo "[INFO] $pkg installed."
        else
            echo "[ERROR] Failed to install $pkg."
        fi
    fi
}

install_pkg apache2
install_pkg squid

echo "[INFO] Enabling and starting apache2..."
systemctl enable --now apache2 2>/dev/null || echo "[WARN] Could not enable/start apache2."

echo "[INFO] Enabling and starting squid..."
systemctl enable --now squid 2>/dev/null || echo "[WARN] Could not enable/start squid."

# -------------------------------------------
# 3. Users and SSH keys
# -------------------------------------------
echo
echo "---- Step 3: Users and SSH keys ----"

USERS=(dennis aubrey captain snibbles brownie scooter sandy perrier cindy tiger yoda)
PROFESSOR_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm"

for user in "${USERS[@]}"; do
    echo
    echo "[INFO] Working on user: $user"

    # create user if needed
    if id "$user" &>/dev/null; then
        echo "[INFO] User $user already exists."
    else
        echo "[INFO] Creating user $user..."
        useradd -m -s /bin/bash "$user"
    fi

    HOME_DIR="/home/$user"

    if [ ! -d "$HOME_DIR" ]; then
        echo "[ERROR] Home directory $HOME_DIR does not exist. Skipping $user."
        continue
    fi

    # prepare .ssh directory
    if [ ! -d "$HOME_DIR/.ssh" ]; then
        echo "[INFO] Creating $HOME_DIR/.ssh..."
        mkdir -p "$HOME_DIR/.ssh"
    fi

    chmod 700 "$HOME_DIR/.ssh"
    chown "$user:$user" "$HOME_DIR/.ssh"

    # generate keys only if missing
    if [ ! -f "$HOME_DIR/.ssh/id_rsa" ]; then
        echo "[INFO] Generating RSA key for $user..."
        su - "$user" -c "ssh-keygen -t rsa -b 2048 -N '' -f ~/.ssh/id_rsa -q"
    else
        echo "[INFO] RSA key already exists for $user."
    fi

    if [ ! -f "$HOME_DIR/.ssh/id_ed25519" ]; then
        echo "[INFO] Generating ED25519 key for $user..."
        su - "$user" -c "ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519 -q"
    else
        echo "[INFO] ED25519 key already exists for $user."
    fi

    AUTH_KEYS="$HOME_DIR/.ssh/authorized_keys"

    # rebuild authorized_keys every time to avoid duplicates
    > "$AUTH_KEYS"
    if [ -f "$HOME_DIR/.ssh/id_rsa.pub" ]; then
        cat "$HOME_DIR/.ssh/id_rsa.pub" >> "$AUTH_KEYS"
    fi
    if [ -f "$HOME_DIR/.ssh/id_ed25519.pub" ]; then
        cat "$HOME_DIR/.ssh/id_ed25519.pub" >> "$AUTH_KEYS"
    fi

    # extra setup for dennis
    if [ "$user" = "dennis" ]; then
        echo "[INFO] Making sure dennis is in sudo group..."
        usermod -aG sudo dennis

        echo "[INFO] Adding professor key for dennis..."
        echo "$PROFESSOR_KEY" >> "$AUTH_KEYS"
    fi

    chmod 600 "$AUTH_KEYS"
    chown -R "$user:$user" "$HOME_DIR/.ssh"

    echo "[INFO] Finished SSH setup for $user."
done

echo
echo "==========================================="
echo " Assignment 2 configuration complete."
echo " It is safe to run this script multiple times."
echo "==========================================="
