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
    bc \
    binutils \
    bison \
    bzip2 \
    clang \
    compiler-rt \
    coreutils \
    clang-tools-extra \
    curl \
    cvs \
    ed \
    flex \
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
    gtkmm30-devel \
    help2man \
    java-17-openjdk-devel \
    libstdc++-static \
    libzstd-devel \
    lld \
    llvm \
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
    ragel \
    SDL2-devel \
    subversion \
    sudo \
    texinfo \
    unzip \
    wget \
    which \
    xorg-x11-util-macros \
    xz \
    yasm \
    zip \
    zlib-devel

# override installed older tools with bundled existing newer tools
RUN for tool in autoconf automake aclocal autoheader autoreconf autom4te; do \
    ln -sf /usr/local/bin/$tool /usr/bin/$tool; \
    done

ENV PATH="/opt/python/cp312-cp312/bin:${PATH}"

RUN python3 --version && pip3 --version && \
    pip3 install numpy Cython setuptools && \
    sudo ln -sf /opt/python/cp312-cp312/bin/cython /bin/cython

# 3. Create 'vscode' user
# Manylinux images are root-only by default. We must recreate the vscode user 
# to match the Dev Container standard.
RUN useradd -m -s /bin/bash vscode && \
    echo "vscode ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

ENV PATH="/usr/local/mingw-w64/bin:${PATH}"

# 4. Install xPack MinGW-w64 GCC 15.2.0-2
RUN wget https://github.com/xpack-dev-tools/mingw-w64-gcc-xpack/releases/download/v15.2.0-2/xpack-mingw-w64-gcc-15.2.0-2-linux-x64.tar.gz && \
    mkdir -p tools && \
    tar xf xpack-mingw-w64-gcc-15.2.0-2-linux-x64.tar.gz -C tools && \
    rm xpack-mingw-w64-gcc-15.2.0-2-linux-x64.tar.gz && \
    mv tools/xpack-mingw-w64-gcc-15.2.0-2 /usr/local/mingw-w64 && \
    chown -R root:users /usr/local/mingw-w64 && \
    chmod -R 775 /usr/local/mingw-w64

# 5. Rust Installation
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
    rustup target add x86_64-pc-windows-gnu && \
    curl -L https://github.com/lu-zero/cargo-c/releases/download/v0.10.20/cargo-c-x86_64-unknown-linux-musl.tar.gz | tar -xz -C /usr/local/bin && \
    rustc --version && \
    cargo --version && \
    dnf clean all

RUN echo 'source /etc/profile.d/rust.sh' >> /home/vscode/.bashrc || true

# Allow 'vscode' user to use Cargo
RUN chmod -R a+w /usr/local/cargo /usr/local/rustup

# 6. Install Flutter
RUN git clone https://github.com/flutter/flutter.git -b stable /usr/local/flutter
RUN chown -R vscode:vscode /usr/local/flutter
ENV PATH="/usr/local/flutter/bin:${PATH}"
RUN git config --system --add safe.directory /usr/local/flutter

# Pre-download development binaries as vscode
USER vscode
RUN flutter config --no-analytics && flutter precache
USER root

# 7. Install WineHQ (RHEL 8 / AlmaLinux 8 version)
# We need to add the WineHQ repo. 
RUN dnf makecache --refresh && \
    dnf install -y wine

# 8. Install Android SDK
# (Note: We already installed java-17-openjdk-devel in step 2)
ENV ANDROID_HOME=/usr/local/android-sdk
ENV PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools"

RUN mkdir -p ${ANDROID_HOME}/cmdline-tools && \
    curl -o /tmp/cmdline-tools.zip -L https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip && \
    unzip -q /tmp/cmdline-tools.zip -d ${ANDROID_HOME}/cmdline-tools && \
    mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest && \
    rm /tmp/cmdline-tools.zip && \
    sdkmanager "ndk;29.0.14206865" && \
    rustup target add x86_64-linux-android i686-linux-android aarch64-linux-android armv7-linux-androideabi

SHELL ["/bin/bash", "-c"]

ENV SDKMAN_DIR="/usr/local/sdkman"

RUN curl -s "https://get.sdkman.io" | bash && \
    source "$SDKMAN_DIR/bin/sdkman-init.sh" && \
    sdk install gradle && \
    sdk flush archives && \
    sdk flush temp

ENV PATH="${SDKMAN_DIR}/candidates/gradle/current/bin:${PATH}"

ENV SDKMAN_CANDIDATES_DIR="${SDKMAN_DIR}/candidates"

RUN chown -R vscode:vscode ${ANDROID_HOME}

RUN wget https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.xz && \
    tar -xvf shellcheck-v0.11.0.linux.x86_64.tar.xz && \
    mkdir -p /usr/local/shellcheck/bin && \
    cp shellcheck-v0.11.0/shellcheck /usr/local/shellcheck/bin/shellcheck && \
    rm -rf shellcheck-v0.11.0 shellcheck-v0.11.0.linux.x86_64.tar.xz

ENV PATH="/usr/local/shellcheck/bin:${PATH}"
ENV ARM_TOOLCHAIN_PATH="/usr/local/arm-gnu-toolchain"
RUN curl -Lo /tmp/arm-toolchain.tar.xz "https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz" && \
    mkdir -p ${ARM_TOOLCHAIN_PATH} && \
    tar -xf /tmp/arm-toolchain.tar.xz --strip-components=1 -C ${ARM_TOOLCHAIN_PATH} && \
    rm /tmp/arm-toolchain.tar.xz && \
    # Create compatibility symlinks (e.g., aarch64-linux-gnu-gcc -> aarch64-none-linux-gnu-gcc)
    mkdir -p ${ARM_TOOLCHAIN_PATH}/sys-bin && \
    for tool in gcc g++ ar as ld nm objcopy objdump ranlib strip; do \
    ln -sf ${ARM_TOOLCHAIN_PATH}/bin/aarch64-none-linux-gnu-$tool ${ARM_TOOLCHAIN_PATH}/sys-bin/aarch64-linux-gnu-$tool; \
    done

# Accept Licenses & Install Basics
USER vscode
RUN yes | sdkmanager --licenses && \
    sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"
USER root

# Finalize
RUN git config --global --add safe.directory '*'

# Set the default user back to vscode for the dev container
USER vscode
