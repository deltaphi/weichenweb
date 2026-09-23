#!/bin/bash

if [ -f /workspace/main.lua ] && [ -f /workspace/remote-host.txt ]; then
    sudo mkdir -p /www/cgi-bin
    sudo cp /workspace/main.lua /www/cgi-bin/weichenweb
    sudo cp /workspace/remote-host.txt /www/cgi-bin/remote-host.txt
    sudo chmod +x /www/cgi-bin/weichenweb
    if ! pidof uhttpd >/dev/null 2>&1; then
        sudo uhttpd -p 0.0.0.0:8080 -h /www -x /cgi-bin
    fi
else
    echo "weichenweb: waiting for /workspace/main.lua and remote-host.txt" >&2
fi

exec /bin/bash
