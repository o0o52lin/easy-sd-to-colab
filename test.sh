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

apt-get install -qq -o=Dpkg::Use-Pty=0 openssh-server pwgen > /dev/null
mkdir -p /var/run/sshd
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
echo "LD_LIBRARY_PATH=/usr/lib64-nvidia" >> /root/.bashrc
echo "export LD_LIBRARY_PATH" >> /root/.bashrc
service ssh restart
apt-get install -qq -o=Dpkg::Use-Pty=0 ngrok-client > /dev/null
