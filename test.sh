#!/bin/bash

# Generate root password
password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c20)

# Download ngrok
# wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz -O ngrok.tgz && sudo tar xvzf ngrok-v3-stable-linux-amd64.tgz -C /usr/bin

# Setup sshd
apt-get install -qq -o=Dpkg::Use-Pty=0 openssh-server pwgen > /dev/null
apt-get -y install jq

# Set root password
echo "root:$password" | chpasswd
mkdir -p /var/run/sshd
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
echo "LD_LIBRARY_PATH=/usr/lib64-nvidia" >> /root/.bashrc
echo "export LD_LIBRARY_PATH" >> /root/.bashrc

# Run sshd
/usr/sbin/sshd -D &

# Create tunnel
ngrok authtoken '2RkIiHPgfucdreF63Z5L8P1BR3V_5RpsFfVRQNyDBSgTyUBxr' && ngrok tcp 22 &

# Get public address and print connect command
curl -s http://localhost:4040/api/tunnels
echo "SSH command: ssh -p$port root@$host"

# Print root password
echo "Root password: $password"

