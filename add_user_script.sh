#!/bin/bash

read -r -p "Hi , Enter two usernames:" user1 user2

SSH_PORT=2222

sudo tee /etc/ssh/sshd_config.d/80-custom-port.conf >/dev/null <<EOF
Port $SSH_PORT
EOF

for username in "$user1" "$user2"; do
    if id "$username" >/dev/null 2>&1; then
        echo "User '$username' already exists."
    else
        sudo useradd -m -s /bin/bash "$username"
        echo "Created user: $username"
    fi

    home_directory="/home/$username"

    sudo chown "$username:$username" "$home_directory"
    sudo chmod 700 "$home_directory"

    read -r -p "Enter public key file for $username: " public_key_file

    if [[ ! -f "$public_key_file" ]]; then
        echo "Error: key file does not exist: $public_key_file" >&2
        continue
    fi

    sudo mkdir -p "$home_directory/.ssh"

    sudo cp "$public_key_file" \
        "$home_directory/.ssh/authorized_keys"

    sudo chown -R "$username:$username" \
        "$home_directory/.ssh"

    sudo chmod 700 "$home_directory/.ssh"
    sudo chmod 600 "$home_directory/.ssh/authorized_keys"

    echo "Configured public key for '$username'."
done
