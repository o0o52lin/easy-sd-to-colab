#!/bin/bash

# url='https://civitai.com/api/download/models/66043'
# location=$(curl -Is -X GET "$url" | grep -i location | awk '{print $2}')
# if [[ ! -z $location ]]; then
#   url=$(echo -e "$location" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d '\n')
# fi
# cmd='curl -Is -X "GET" "<url>"'
# header=$(eval ${cmd/<url>/$url})
# header=$(echo "$header" | tr '[:upper:]' '[:lower:]')
# remote_size=$(echo "$header" | awk '/content-length/ {clen=$2} /x-linked-size/ {xsize=$2} END {if (xsize) print xsize; else print clen;}' | tr -dc '0-9' || echo '')
# local_size=0
# echo "LOCAL_SIZE: $local_size"
# echo "REMOTE_SIZE: $remote_size"
# if [[ $local_size != 0 ]] && [[ "$local_size" -eq "$remote_size" ]]; then
#   echo "INFO: local file '$output_filename' is up-to-date, skipping download"
#   return 0
# fi


#!/bin/bash

# Generate root password
password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c20)

# Download ngrok
wget -q -c -nc https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip
unzip -qq -n ngrok-stable-linux-amd64.zip

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
/content/ngrok authtoken '2RkIiHPgfucdreF63Z5L8P1BR3V_5RpsFfVRQNyDBSgTyUBxr' && /content/ngrok tcp 22 &

# Get public address and print connect command
host=$(curl -s http://localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url' | cut -d':' -f2,3,4)
port=$(curl -s http://localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url' | cut -d':' -f5)
echo "SSH command: ssh -p$port root@$host"

# Print root password
echo "Root password: $password"

