#!/bin/bash

if [ -f /workspace/main.lua ]; then
    sudo mkdir -p /www/cgi-bin
    sudo ln -sf /workspace/main.lua /www/cgi-bin/weichenweb
    if [ -f /workspace/remote-host.txt ]; then
        sudo ln -sf /workspace/remote-host.txt /www/cgi-bin/remote-host.txt
    else
        sudo rm -f /www/cgi-bin/remote-host.txt
    fi
    sudo chmod +x /www/cgi-bin/weichenweb
    if ! pidof uhttpd >/dev/null 2>&1; then
        sudo uhttpd -p 0.0.0.0:8080 -h /www -x /cgi-bin
    fi
else
    echo "weichenweb: waiting for /workspace/main.lua" >&2
fi

exec /bin/bash
