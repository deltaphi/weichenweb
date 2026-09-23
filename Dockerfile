FROM openwrt/rootfs:x86_64-21.02.7

ARG USERNAME=lua
ARG UID=1000
ARG GID=1000

RUN mkdir -p /var/lock \
    && opkg update \
    && opkg install \
        bash \
        ca-bundle \
        git \
        lua \
        luac \
        luasocket \
        shadow-groupadd \
        shadow-useradd \
        sudo \
        uhttpd \
    && rm -rf /var/opkg-lists/*

RUN groupadd -g "${GID}" "${USERNAME}" \
    && useradd -u "${UID}" -g "${USERNAME}" -m -s /bin/bash "${USERNAME}" \
    && echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}" \
    && chmod 0440 "/etc/sudoers.d/${USERNAME}"

COPY container-start.sh /usr/local/bin/container-start.sh
RUN chmod 0755 /usr/local/bin/container-start.sh

WORKDIR /workspace
USER ${USERNAME}

CMD ["/usr/local/bin/container-start.sh"]
