#!/bin/bash
# Script to bootstrap a new VPS with the necessary users and groups

groupadd vipyrsec

useradd --create-home --home-dir /home/shenanigansd --shell /bin/bash --groups sudo,vipyrsec --user-group shenanigansd
echo "shenanigansd:shadow" | chpasswd
mkdir /home/shenanigansd/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN+zdYNAzevMYs2uTKWmhW6lLtWWe24PHcVSo10MYX0W azuread\bradleyreynolds@5CD042JKKK" >/home/shenanigansd/.ssh/authorized_keys
chown -R shenanigansd:shenanigansd /home/shenanigansd/.ssh
chmod 700 /home/shenanigansd/.ssh
chmod 600 /home/shenanigansd/.ssh/authorized_keys

useradd --create-home --home-dir /home/rem --shell /bin/bash --groups sudo,vipyrsec --user-group rem
echo "rem:shadow" | chpasswd
mkdir /home/rem/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICxt8Y50hNh192jUbOuhyah3bVUG0mUUXdo3dWe9uzHZ 44jmn@Syrup" >/home/rem/.ssh/authorized_keys
chown -R rem:rem /home/rem/.ssh
chmod 700 /home/rem/.ssh
chmod 600 /home/rem/.ssh/authorized_keys

mkdir /opt/vipyrsec
chown shenanigansd:vipyrsec /opt/vipyrsec
chmod g+w /opt/vipyrsec
