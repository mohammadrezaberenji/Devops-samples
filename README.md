# Linux User Creation and SSH Hardening — Homework

This beginner-friendly exercise automates a practical Linux administration task: create two users, make their home directories private, and let them access SSH with public keys instead of passwords.

> Goal: create two normal Linux users with private home directories and key-only SSH access, then move SSH from port `22` to a chosen available port.

This guide targets Ubuntu/Debian systems using OpenSSH. Practice on a VM or test server first.

## What the script does

- Asks for two usernames and two SSH public-key file paths.
- Creates users with Bash login shells and home directories.
- Sets each home directory to `700`.
- Creates `~/.ssh/authorized_keys` from the supplied public key.
- Locks local passwords and disables password/keyboard-interactive SSH for only these two users.
- Adds a configurable SSH port, validates the configuration, opens the port in UFW if available, then reloads SSH.

## Prerequisites

- Ubuntu or Debian, with `sudo` access.
- OpenSSH server installed and running.
- `ssh-keygen`, `ss`, and preferably UFW installed.
- Two SSH public-key (`.pub`) files available on the server.
- Keep an existing SSH session open while testing the change.

Check the environment:

```bash
sudo systemctl status ssh
command -v sshd ssh-keygen ss
sudo ufw status
```

Install the SSH server if required:

```bash
sudo apt update
sudo apt install -y openssh-server
```

## 1. Generate SSH keys

Generate keys on each **client** machine. The private key stays on the client; only the `.pub` file is copied to the server.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/alice_ed25519 -C "alice"
ssh-keygen -t ed25519 -f ~/.ssh/bob_ed25519 -C "bob"
```

Expected layout:

```text
~/.ssh/
├── alice_ed25519       # private — never share or upload
├── alice_ed25519.pub   # public — place in authorized_keys
├── bob_ed25519         # private — never share or upload
└── bob_ed25519.pub     # public — place in authorized_keys
```

For the exercise, put the public files on the server, for example:

```text
/tmp/alice_ed25519.pub
/tmp/bob_ed25519.pub
```

## 2. Complete Bash script

Save this as `create_hardened_ssh_users.sh`.

```bash
#!/usr/bin/env bash

# Creates two users with private homes and SSH public-key-only access.
# Intended for Ubuntu/Debian with OpenSSH Server.

set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
    echo "Error: run with sudo: sudo $0" >&2
    exit 1
fi

if ! command -v sshd >/dev/null 2>&1; then
    echo "Error: sshd was not found. Install openssh-server first." >&2
    exit 1
fi

read -r -p "Enter the first username: " user1
read -r -p "Enter the second username: " user2
read -r -p "Public-key file for $user1: " key1
read -r -p "Public-key file for $user2: " key2
read -r -p "New SSH port [2222]: " ssh_port
ssh_port=${ssh_port:-2222}

validate_username() {
    local username=$1

    if [[ ! $username =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "Error: invalid username '$username'." >&2
        exit 1
    fi
}

validate_public_key() {
    local key_file=$1

    if [[ ! -f $key_file ]]; then
        echo "Error: public-key file not found: $key_file" >&2
        exit 1
    fi

    if ! ssh-keygen -l -f "$key_file" >/dev/null 2>&1; then
        echo "Error: '$key_file' is not a valid SSH public key." >&2
        exit 1
    fi
}

validate_port() {
    local port=$1

    if [[ ! $port =~ ^[0-9]+$ ]] || (( port < 1024 || port > 65535 )); then
        echo "Error: choose a port from 1024 to 65535." >&2
        exit 1
    fi

    # Do not select a port that a local service already uses.
    if ss -lntH | awk -v port="$port" '$4 ~ (":" port "$") { found=1 } END { exit !found }'; then
        echo "Error: port $port is already in use. Choose another one." >&2
        exit 1
    fi
}

create_and_configure_user() {
    local username=$1
    local key_file=$2
    local home_directory="/home/$username"
    local primary_group

    if id "$username" >/dev/null 2>&1; then
        echo "User '$username' already exists; updating its SSH setup."
    else
        # -m creates the home, -U creates a matching group, -s sets the shell.
        useradd -m -U -s /bin/bash "$username"
        echo "Created user '$username'."
    fi

    if [[ ! -d $home_directory ]]; then
        echo "Error: home directory does not exist: $home_directory" >&2
        exit 1
    fi

    primary_group=$(id -gn "$username")
    chown "$username:$primary_group" "$home_directory"
    chmod 700 "$home_directory"

    install -d -m 700 -o "$username" -g "$primary_group" \
        "$home_directory/.ssh"
    install -m 600 -o "$username" -g "$primary_group" \
        "$key_file" "$home_directory/.ssh/authorized_keys"

    # This locks password authentication for the local account.
    # Public-key login is still allowed.
    passwd --lock "$username" >/dev/null
    echo "Configured private home and public key for '$username'."
}

validate_username "$user1"
validate_username "$user2"

if [[ $user1 == "$user2" ]]; then
    echo "Error: usernames must be different." >&2
    exit 1
fi

validate_public_key "$key1"
validate_public_key "$key2"
validate_port "$ssh_port"

create_and_configure_user "$user1" "$key1"
create_and_configure_user "$user2" "$key2"

SSHD_CONFIG_DIR=/etc/ssh/sshd_config.d
PORT_DROP_IN="$SSHD_CONFIG_DIR/80-homework-custom-port.conf"
USER_DROP_IN="$SSHD_CONFIG_DIR/90-homework-key-only-users.conf"
BACKUP_DIR="/root/ssh-homework-backup-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$SSHD_CONFIG_DIR" "$BACKUP_DIR"

# Preserve old homework files when running this script again.
for file in "$PORT_DROP_IN" "$USER_DROP_IN"; do
    if [[ -e $file ]]; then
        cp -a "$file" "$BACKUP_DIR/"
    fi
done

# Standard Ubuntu/Debian configs have the original Port 22 line commented.
# This drop-in makes sshd listen on the selected port.
cat > "$PORT_DROP_IN" <<EOF
# Managed by create_hardened_ssh_users.sh
Port $ssh_port
EOF

cat > "$USER_DROP_IN" <<EOF
# Managed by create_hardened_ssh_users.sh
Match User $user1,$user2
    PubkeyAuthentication yes
    AuthenticationMethods publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
EOF

chmod 600 "$PORT_DROP_IN" "$USER_DROP_IN"

# Never reload SSH until the new configuration has passed validation.
if ! sshd -t; then
    echo "Error: invalid sshd configuration; restoring previous homework files." >&2
    rm -f "$PORT_DROP_IN" "$USER_DROP_IN"
    find "$BACKUP_DIR" -maxdepth 1 -type f -exec cp -a {} "$SSHD_CONFIG_DIR/" \;
    exit 1
fi

# Allow the new port before reloading and testing it.
if command -v ufw >/dev/null 2>&1; then
    ufw allow "${ssh_port}/tcp"
else
    echo "Warning: UFW is unavailable; allow TCP $ssh_port in your firewall." >&2
fi

if systemctl is-active --quiet ssh; then
    systemctl reload ssh
elif systemctl is-active --quiet sshd; then
    systemctl reload sshd
else
    echo "Warning: SSH is not active; start it after checking the configuration." >&2
fi

echo
echo "Completed successfully."
echo "Users: $user1, $user2"
echo "New SSH port: $ssh_port"
echo "Backup directory: $BACKUP_DIR"
echo "Keep this session open and test key login before removing old port-22 access."
```

Make it executable and run it:

```bash
chmod +x create_hardened_ssh_users.sh
sudo ./create_hardened_ssh_users.sh
```

Example answers:

```text
Enter the first username: alice
Enter the second username: bob
Public-key file for alice: /tmp/alice_ed25519.pub
Public-key file for bob: /tmp/bob_ed25519.pub
New SSH port [2222]: 2222
```

## 3. Permissions and important commands

| Item | Meaning |
|---|---|
| `set -Eeuo pipefail` | Stops on failures, undefined variables, and failed pipeline commands. It helps catch mistakes early. |
| `read -r -p` | Shows a prompt and saves typed text in a variable. |
| `useradd -m -U -s /bin/bash` | Creates the user, its home directory, its matching group, and a Bash shell. |
| `chmod 700 /home/user` | Only the owner can read, write, and enter the home directory. |
| `~/.ssh` mode `700` | Only the account owner can access the SSH directory. |
| `authorized_keys` mode `600` | Only the owner can read or modify accepted public keys. |
| `passwd --lock user` | Locks the account password but does not prevent valid public-key login. |
| `Match User alice,bob` | Applies the following SSH settings to Alice and Bob only. |
| `sshd -t` | Validates SSH configuration before a reload. |
| `ufw allow 2222/tcp` | Allows inbound TCP traffic to the new SSH port. |

Expected server-side layout:

```text
/home/alice/                         # mode 700
└── .ssh/                             # mode 700
    └── authorized_keys               # mode 600; contains alice's public key

/home/bob/                           # mode 700
└── .ssh/                             # mode 700
    └── authorized_keys               # mode 600; contains bob's public key

/etc/ssh/sshd_config.d/
├── 80-homework-custom-port.conf
└── 90-homework-key-only-users.conf
```

Private home permissions stop Alice and Bob from entering each other's homes. They can still read normal world-readable files such as `/etc/hosts`; this is not a full filesystem sandbox.

## 4. Verify the result

On the server, run:

```bash
id alice
id bob
sudo ls -ld /home/alice /home/bob
sudo ls -ld /home/alice/.ssh /home/bob/.ssh
sudo ls -l /home/alice/.ssh/authorized_keys /home/bob/.ssh/authorized_keys

sudo sshd -t
sudo sshd -T -C user=alice,host=localhost,addr=127.0.0.1 | \
  grep -E '^(passwordauthentication|kbdinteractiveauthentication|authenticationmethods|pubkeyauthentication)'

sudo ss -lntp | grep ':2222'
sudo ufw status numbered
```

For Alice, the effective settings should include:

```text
passwordauthentication no
kbdinteractiveauthentication no
authenticationmethods publickey
pubkeyauthentication yes
```

From a second client terminal, test the public key:

```bash
ssh -p 2222 -i ~/.ssh/alice_ed25519 alice@SERVER_IP
```

Confirm that a password cannot be used:

```bash
ssh -p 2222 -o PreferredAuthentications=password -o PubkeyAuthentication=no \
  alice@SERVER_IP
```

This second command should fail. Do not close the original administrative SSH session until the key login succeeds.

## 5. Port 22 safety and rollback

The script opens the new port but does **not** remove firewall access to port `22` automatically. That is deliberate: removing it before a successful test could lock you out.

After key login works, inspect the effective SSH ports:

```bash
sudo sshd -T | grep '^port '
```

On standard Ubuntu/Debian configurations, the chosen port should be the only port. If `22` still appears, another config file explicitly sets it. Locate it:

```bash
sudo grep -RIn --include='*.conf' --include='sshd_config' '^\s*Port\s\+' \
  /etc/ssh/sshd_config /etc/ssh/sshd_config.d
```

When the new key connection works and SSH no longer listens on `22`, remove the old UFW rule if present:

```bash
sudo ufw status numbered
sudo ufw delete allow 22/tcp
```

Also update any cloud security group, router rule, or hosting firewall before removing port-22 access.

To remove this homework configuration and return to the previous port behavior:

```bash
sudo rm -f /etc/ssh/sshd_config.d/80-homework-custom-port.conf
sudo rm -f /etc/ssh/sshd_config.d/90-homework-key-only-users.conf
sudo sshd -t
sudo systemctl reload ssh
```

If the script was run again, restore any earlier files from the backup directory printed by the script, then validate and reload:

```bash
sudo cp -a /root/ssh-homework-backup-TIMESTAMP/*.conf /etc/ssh/sshd_config.d/
sudo sshd -t
sudo systemctl reload ssh
```

## 6. Common errors encountered

| Error or issue | Cause | Fix |
|---|---|---|
| `chown: cannot access '/home/test1'` | `useradd` was used without `-m`, so no home directory was created. | Use `useradd -m -s /bin/bash username`. |
| `chown: cannot access ''` | An empty variable was passed to `chown`, commonly from writing `home_direcotry` instead of `home_directory`. | Fix the spelling and keep `set -u` enabled. |
| `public-key file not found` | The supplied path is incorrect or the `.pub` file is not on the server. | Check it with `ls -l /path/key.pub`; never provide the private key. |
| `sshd -t` fails | An SSH directive is invalid or a config file conflicts. | Read the reported line, correct it, and run `sshd -t` again before reloading. |
| Key login is refused | Wrong key, wrong ownership/mode, or the client did not offer the intended key. | Check `700`/`600`, inspect `authorized_keys`, and test with `ssh -vvv -i private_key ...`. |
| New port is unreachable | UFW, cloud firewall, or router does not allow it. | Open the TCP port in every relevant firewall and check `sudo ss -lntp`. |
| Port 22 is still listening | Another config file defines `Port 22`. | Use `sshd -T` and the `grep` command in section 5. |

## Learning outcomes

After this homework, I can:

- read and validate interactive Bash input;
- create Linux users and home directories with `useradd`;
- use ownership and permissions to protect user data;
- distinguish SSH private keys from public keys;
- set up `authorized_keys` safely;
- require public-key SSH for selected users with `Match User`;
- validate SSH configuration with `sshd -t` before reloading;
- check open ports, update UFW, test safely, and roll back an SSH change.

