#!/bin/bash

# Generate root password
password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c20)

# Download ngrok
if ! command -v ngrok &> /dev/null
then
  echo "ngrok is installing..."
  curl -s -X GET "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz" -o ngrok-v3-stable-linux-amd64.tgz
  tar xvzf ngrok-v3-stable-linux-amd64.tgz -C /usr/local/bin
  rm ngrok-v3-stable-linux-amd64.tgz
else
  echo "ngrok is installed, skip"
fi

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

pid=$(ps aux | grep ngrok | grep -v grep | awk '{print $2}')
if [ -n "$pid" ]; then
    kill -9 $pid
    echo 'Kill old ngrok: pid='$pid
fi

if [[ $# -gt 0 ]]; then
  authtoken=$1
else
  #Ask token
  echo "Copy authtoken from https://dashboard.ngrok.com/auth"
  read -s authtoken
fi
echo 'authtoken :'$authtoken

# Create tunnel
ngrok config add-authtoken $authtoken
nohup ngrok tcp 22 &
echo 'wait for ngrok set up...'
sleep 3
pid=$(ps aux | grep ngrok | grep -v grep | awk '{print $2}')
echo 'New ngrok setup :pid='$pid

# Get public address and print connect command
res=$(curl -s http://localhost:4040/api/tunnels)
str=$(echo $res | jq '.tunnels[0].public_url')

# 使用sed命令和正则表达式替换字符串
new_str=$(echo $str | sed 's/tcp:\/\///')
new_str=$(echo $new_str | sed 's/"//g')
echo $new_str
# 使用cut命令提取子字符串
host=$(echo $new_str | cut -d':' -f1)
port=$(echo $new_str | cut -d':' -f2)

echo "SSH command: ssh -p$port root@$host"

# Print root password
echo "Root password: $password"

