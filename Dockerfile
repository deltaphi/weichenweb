FROM debian:bookworm-slim

ARG USERNAME=lua
ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        git \
        luarocks \
        lua5.4 \
        sudo \
    && ln -s /usr/bin/lua5.4 /usr/local/bin/lua \
    && ln -s /usr/bin/luac5.4 /usr/local/bin/luac \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid "${GID}" "${USERNAME}" \
    && useradd --uid "${UID}" --gid "${GID}" --create-home --shell /bin/bash "${USERNAME}" \
    && echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}" \
    && chmod 0440 "/etc/sudoers.d/${USERNAME}"

WORKDIR /workspace
USER ${USERNAME}

CMD ["bash"]
