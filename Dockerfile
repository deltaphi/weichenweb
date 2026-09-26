
# Use the following FROM statement to build and run on an M-series Mac:
#FROM --platform=linux/amd64 openwrt/rootfs:armvirt-64-21.02.7

ARG USERNAME=lua
ARG UID=1000
ARG GID=1000

RUN mkdir -p /var/lock \
    && opkg update \
    && opkg install \
        bash \
        ca-bundle \
        lua \
        luac \
        luci-lib-nixio \
        shadow-groupadd \
        shadow-useradd \
        sudo \
        uhttpd \
    && rm -rf /var/opkg-lists/*

RUN groupadd -g "${GID}" "${USERNAME}" \
    && useradd -u "${UID}" -g "${USERNAME}" -m -s /bin/bash "${USERNAME}" \
    && echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}" \
    && chmod 0440 "/etc/sudoers.d/${USERNAME}"

WORKDIR /workspace
USER ${USERNAME}

CMD ["/workspace/container-start.sh"]
