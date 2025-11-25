#!/bin/bash
# COMP2137 Assignment 3 - lab3.sh
# Copy configure-host.sh to two servers and run it there,
# then update the local /etc/hosts file.

VERBOSE=0
CFG_SCRIPT="./configure-host.sh"

# Simple argument: if -verbose passed to lab3.sh, pass to remote too
if [ "$1" = "-verbose" ]; then
    VERBOSE=1
fi

if [ ! -f "$CFG_SCRIPT" ]; then
    echo "[ERROR] configure-host.sh not found in current directory." >&2
    exit 1
fi

if [ ! -x "$CFG_SCRIPT" ]; then
    echo "[INFO] Making configure-host.sh executable..."
    chmod +x "$CFG_SCRIPT" || {
        echo "[ERROR] Could not chmod configure-host.sh" >&2
        exit 1
    }
fi

REMOTE_OPTS=""
if [ "$VERBOSE" -eq 1 ]; then
    REMOTE_OPTS="-verbose"
    echo "[INFO] Running in verbose mode."
fi

echo "[INFO] Copying script to server1-mgmt..."
scp "$CFG_SCRIPT" remoteadmin@server1-mgmt:/root || {
    echo "[ERROR] scp to server1-mgmt failed." >&2
    exit 1
}

echo "[INFO] Running configure-host.sh on server1..."
ssh remoteadmin@server1-mgmt -- /root/configure-host.sh $REMOTE_OPTS -name loghost -ip 192.168.16.3 -hostentry webhost 192.168.16.4
if [ "$?" -ne 0 ]; then
    echo "[WARN] configure-host.sh failed on server1-mgmt." >&2
fi

echo "[INFO] Copying script to server2-mgmt..."
scp "$CFG_SCRIPT" remoteadmin@server2-mgmt:/root || {
    echo "[ERROR] scp to server2-mgmt failed." >&2
    exit 1
}

echo "[INFO] Running configure-host.sh on server2..."
ssh remoteadmin@server2-mgmt -- /root/configure-host.sh $REMOTE_OPTS -name webhost -ip 192.168.16.4 -hostentry loghost 192.168.16.3
if [ "$?" -ne 0 ]; then
    echo "[WARN] configure-host.sh failed on server2-mgmt." >&2
fi

echo "[INFO] Updating local /etc/hosts entries..."
sudo ./configure-host.sh $REMOTE_OPTS -hostentry loghost 192.168.16.3
sudo ./configure-host.sh $REMOTE_OPTS -hostentry webhost 192.168.16.4

echo "[INFO] lab3.sh finished."
exit 0
