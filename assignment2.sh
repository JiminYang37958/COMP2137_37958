users=(dennis aubrey captain snibbles brownie scooter sandy perrier cindy tiger yoda)

for user in "${users[@]}"; do
    if ! id "$user" &>/dev/null; then
        echo "Creating user $user..."
        useradd -m -s /bin/bash "$user"
    else
        echo "User $user already exists."
    fi
done

if id "dennis" &>/dev/null; then
    usermod -aG sudo dennis
    mkdir -p /home/dennis/.ssh
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm" >> /home/dennis/.ssh/authorized_keys
    chown -R dennis:dennis /home/dennis/.ssh
    chmod 700 /home/dennis/.ssh
    chmod 600 /home/dennis/.ssh/authorized_keys
fi
