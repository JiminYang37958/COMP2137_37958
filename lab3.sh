#!/bin/bash

# lab3.sh - deploy and run configure-host.sh on server1 and server2,
# then update the local /etc/hosts file.

VERBOSE=0

# Parse -verbose option
if [ "$1" = "-verbose" ]; then
    VERBOSE=1
    shift
fi

# Verbose message helper
vmsg() {
    [ "$VERBOSE" -eq 1 ] && echo "[INFO] $1"
}

# Error helper
error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# Check configure-host.sh exists in current directory
if [ ! -f configure-host.sh ]; then
    error "configure-host.sh not found in current directory."
fi

##############################
# 1. Copy to server1 and run
##############################
vmsg "Copying configure-host.sh to server1-mgmt..."
scp configure-host.sh remoteadmin@server1-mgmt:/root/ || error "Failed to copy to server1-mgmt."

vmsg "Running configure-host.sh on server1-mgmt..."
ssh remoteadmin@server1-mgmt -- /root/configure-host.sh \
    ${VERBOSE:+-verbose} \
    -name loghost \
    -ip 192.168.16.3 \
    -hostentry webhost 192.168.16.4 || error "Failed to run configure-host.sh on server1-mgmt."

##############################
# 2. Copy to server2 and run
##############################
vmsg "Copying configure-host.sh to server2-mgmt..."
scp configure-host.sh remoteadmin@server2-mgmt:/root/ || error "Failed to copy to server2-mgmt."

vmsg "Running configure-host.sh on server2-mgmt..."
ssh remoteadmin@server2-mgmt -- /root/configure-host.sh \
    ${VERBOSE:+-verbose} \
    -name webhost \
    -ip 192.168.16.4 \
    -hostentry loghost 192.168.16.3 || error "Failed to run configure-host.sh on server2-mgmt."

##############################
# 3. Update local hostvm
##############################
vmsg "Updating local /etc/hosts for loghost..."
sudo ./configure-host.sh ${VERBOSE:+-verbose} -hostentry loghost 192.168.16.3 || error "Failed to update local loghost entry."

vmsg "Updating local /etc/hosts for webhost..."
sudo ./configure-host.sh ${VERBOSE:+-verbose} -hostentry webhost 192.168.16.4 || error "Failed to update local webhost entry."

vmsg "lab3.sh completed successfully."
