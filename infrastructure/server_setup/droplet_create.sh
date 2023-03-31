#!/bin/bash

doctl compute droplet create \
    --image ubuntu-22-04-x64 \
    --size s-1vcpu-512mb-10gb \
    --region nyc1 \
    --enable-ipv6 \
    --ssh-keys 63:dd:ac:4f:df:08:cd:6d:57:d9:5a:92:79:a7:ba:0d \
    --user-data-file=server_bootstrap.sh \
    --verbose \
    "$1"
