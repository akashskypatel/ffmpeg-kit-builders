# Use the official Manylinux 2.28 image (AlmaLinux 8 based, glibc 2.28)
# This ensures binaries work on Ubuntu 20.04+, Debian 10+, RHEL 8+
FROM quay.io/pypa/manylinux_2_28_x86_64

# 1. Setup Environment & Repositories
# Install EPEL (Extra Packages for Enterprise Linux) for tools like Ragel/Wine dependencies
RUN dnf install -y epel-release && \
    dnf config-manager --set-enabled powertools && \
    dnf update -y

# 2. Install System Packages
# Added '--allowerasing' to resolve the coreutils conflict.
RUN dnf install -y --allowerasing --setopt=install_weak_deps=False \
    autoconf-archive \
    autogen \
    asciidoc \
    alsa-lib-devel \
    bc \
    binutils \
    bison \
    bzip2 \
    clang \
    cmake \
    compiler-rt \
    coreutils \
    clang-tools-extra \
    curl \
    cvs \
    doxygen \
    ed \
    flex \
    git \
    gcc \
    gcc-c++ \
    gcc-gfortran \
    gcc-toolset-14-libasan-devel \
    gcc-toolset-14-libubsan-devel \
    gcc-toolset-14-libtsan-devel \
    gettext \
    gettext-devel \
    glib2-devel \
    glibc-static \
    gperf \
    help2man \
    libstdc++-static \
    libzstd-devel \
    lld \
    llvm \
    llvm-compat-libs \
    libasan \
    make \
    nasm \
    ninja-build \
    openssl-devel \
    p7zip \
    patch \
    pax \
    perl-IPC-Cmd \
    perl-Thread-Queue \
    perl-Time-Piece \
    pkgconf-pkg-config \
    python3.11 \
    python3.11-devel \
    python3-pip \
    ragel \
    SDL2-devel \
    subversion \
    sudo \
    texinfo \
    unzip \
    valgrind-devel \
    wget \
    which \
    xorg-x11-util-macros \
    xorg-x11-xtrans-devel \
    xorg-x11-proto-devel \
    libXext-devel \
    libXdmcp-devel \
    libXrender-devel \
    libXft-devel \
    libX11-devel \
    libXau-devel \
    libxcb-devel \
    libpciaccess-devel \
    dbus-devel \
    libsmbclient-devel \
    ocl-icd-devel \
    wayland-devel \
    wayland-protocols-devel \
    libxkbcommon-devel \
    libXcursor-devel \
    libXi-devel \
    libXinerama-devel \
    libXrandr-devel \
    mesa-libGL-devel \
    mesa-libGLU-devel \
    libXmu-devel \
    xz \
    yasm \
    zip \
    zlib-devel

# override installed older tools with bundled existing newer tools
RUN for tool in autoconf automake aclocal autoheader autoreconf autom4te; do \
    ln -sf /usr/local/bin/$tool /usr/bin/$tool; \
    done

RUN ln -sf /usr/local/bin/aclocal /usr/bin/aclocal-1.18 \
    && ln -sf /usr/local/bin/automake /usr/bin/automake-1.18 \
    && ln -sf /usr/local/bin/aclocal /usr/local/bin/aclocal-1.18 \
    && ln -sf /usr/local/bin/automake /usr/local/bin/automake-1.18

ENV PATH="/opt/python/cp312-cp312/bin:${PATH}"

RUN python3 --version && pip3 --version && \
    pip3 install numpy Cython setuptools && \
    sudo ln -sf /opt/python/cp312-cp312/bin/cython /bin/cython

# 3. Create 'vscode' user
# Manylinux images are root-only by default. We must recreate the vscode user 
# to match the Dev Container standard.
RUN useradd -m -s /bin/bash vscode && \
    echo "vscode ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# 4. Rust Installation
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN echo 'export RUSTUP_HOME=/usr/local/rustup' >> /etc/profile.d/rust.sh && \
    echo 'export CARGO_HOME=/usr/local/cargo' >> /etc/profile.d/rust.sh && \
    echo 'export PATH=/usr/local/cargo/bin:$PATH' >> /etc/profile.d/rust.sh && \
    chmod +x /etc/profile.d/rust.sh && \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path && \
    . /usr/local/cargo/env && \
    rustup default stable && \
    ln -sf /usr/local/cargo/bin/rustup /usr/bin/rustup && \
    ln -sf /usr/local/cargo/bin/cargo /usr/bin/cargo && \
    cargo --version && \
    curl -fsSL https://github.com/lu-zero/cargo-c/releases/download/v0.10.20/cargo-c-x86_64-unknown-linux-musl.tar.gz -o /tmp/cargo-c.tar.gz && \
    mkdir -p /tmp/cargo-c /usr/local/bin && \
    tar -xzf /tmp/cargo-c.tar.gz -C /tmp/cargo-c && \
    find /tmp/cargo-c -type f -name 'cargo-c*' -exec install -m 0755 {} /usr/local/bin/ \; && \
    rm -rf /tmp/cargo-c /tmp/cargo-c.tar.gz && \
    ln -sf /usr/local/bin/cargo-cbuild /usr/bin/cargo-cbuild && \
    ln -sf /usr/local/bin/cargo-cinstall /usr/bin/cargo-cinstall && \
    cargo cbuild --version && \
    rustc --version && \
    cargo --version && \
    dnf clean all

RUN echo 'source /etc/profile.d/rust.sh' >> /home/vscode/.bashrc || true

# Allow 'vscode' user to use Cargo
RUN chmod -R a+w /usr/local/cargo /usr/local/rustup

SHELL ["/bin/bash", "-c"]

# Finalize
RUN git config --global --add safe.directory '*'

# Copy entrypoint script
COPY docker/docker-entry.sh /usr/local/bin/docker-entry.sh
RUN chmod +x /usr/local/bin/docker-entry.sh

# Set the default user back to vscode for the dev container
USER vscode

RUN mkdir -p "$HOME/.config/keystore/maven" && \
    touch "$HOME/.config/keystore/maven/maven" && \
    touch "$HOME/.config/keystore/github"

ENTRYPOINT ["/usr/local/bin/docker-entry.sh"]
