#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292,2207

if (( BASH_VERSINFO[0] < 4 )); then
    for bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$bash" ]]; then
            exec "$bash" "$0" "$@"
        fi
    done

    echo "GNU Bash 4+ is required." >&2
    exit 1
fi
set -euo pipefail

ARM_TOOLCHAIN_PATH="${ARM_TOOLCHAIN_PATH:-/usr/local/arm-gnu-toolchain}"
SYSROOT="${SYSROOT:-/opt/sysroots/aarch64-linux-gnu}"
ARM_TOOLCHAIN_URL="${ARM_TOOLCHAIN_URL:-https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz}"
RHEL_RELEASEVER="${RHEL_RELEASEVER:-$(rpm -E %rhel)}"
MODULE_PLATFORM_ID="${MODULE_PLATFORM_ID:-platform:el${RHEL_RELEASEVER}}"
DNF_INSTALL_DISABLE_MODULAR_FILTERING_ARGS=()
DNF_DOWNLOAD_DISABLE_MODULAR_FILTERING_ARGS=()

rust_target_installed() {
  local target="$1"
  ! command -v rustup >/dev/null 2>&1 || rustup target list --installed 2>/dev/null | grep -qx "$target"
}

write_linux_arm64_environment() {
  cat >/etc/profile.d/linux-arm64-toolchain.sh <<EOF
export SYSROOT="${SYSROOT}"
export ARM_TOOLCHAIN_PATH="${ARM_TOOLCHAIN_PATH}"
export PATH="${ARM_TOOLCHAIN_PATH}/sys-bin:\$PATH"
EOF
  chmod +x /etc/profile.d/linux-arm64-toolchain.sh

  export PATH="${ARM_TOOLCHAIN_PATH}/sys-bin:$PATH"

  if [[ -n "${GITHUB_ENV:-}" ]]; then
    grep -qxF "SYSROOT=${SYSROOT}" "$GITHUB_ENV" 2>/dev/null || echo "SYSROOT=${SYSROOT}" >>"$GITHUB_ENV"
    grep -qxF "ARM_TOOLCHAIN_PATH=${ARM_TOOLCHAIN_PATH}" "$GITHUB_ENV" 2>/dev/null || echo "ARM_TOOLCHAIN_PATH=${ARM_TOOLCHAIN_PATH}" >>"$GITHUB_ENV"
  fi
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    grep -qxF "${ARM_TOOLCHAIN_PATH}/sys-bin" "$GITHUB_PATH" 2>/dev/null || echo "${ARM_TOOLCHAIN_PATH}/sys-bin" >>"$GITHUB_PATH"
  fi
}

linux_arm64_toolchain_ready() {
  [[ -x "${ARM_TOOLCHAIN_PATH}/sys-bin/aarch64-linux-gnu-gcc" ]] &&
    [[ -e "${SYSROOT}/lib64/libc.so.6" ]] &&
    [[ -e "${SYSROOT}/usr/include/features.h" ]] &&
    [[ -d "${SYSROOT}/usr/include/c++" ]] &&
    [[ -e "${SYSROOT}/usr/lib64/libgcc_s.so" ]] &&
    rust_target_installed aarch64-unknown-linux-gnu
}

linux_arm64_sysroot_ready() {
  [[ -e "${SYSROOT}/lib64/libc.so.6" ]] &&
    [[ -e "${SYSROOT}/usr/include/features.h" ]] &&
    [[ -d "${SYSROOT}/usr/include/c++" ]] &&
    [[ -e "${SYSROOT}/usr/lib64/libgcc_s.so" ]]
}

fix_linux_arm64_sysroot_links() {
  if [[ ! -e "${SYSROOT}/usr/lib64/libgcc_s.so" && -e "${SYSROOT}/usr/lib64/libgcc_s.so.1" ]]; then
    ln -sf libgcc_s.so.1 "${SYSROOT}/usr/lib64/libgcc_s.so"
  fi
}

install_linux_arm64_sysroot_from_rpms() {
  local rpm_dir
  local rpm_file
  local packages=(
    glibc
    glibc-devel
    glibc-headers
    kernel-headers
    libgcc
    libstdc++
    libstdc++-devel
    libxcrypt
    libxcrypt-devel
  )

  rpm_dir="$(mktemp -d)"
  dnf download \
    --installroot="$SYSROOT" \
    --resolve \
    --alldeps \
    --destdir "$rpm_dir" \
    --forcearch=aarch64 \
    --releasever="$RHEL_RELEASEVER" \
    --setopt=module_platform_id="$MODULE_PLATFORM_ID" \
    "${DNF_DOWNLOAD_DISABLE_MODULAR_FILTERING_ARGS[@]}" \
    --arch=aarch64,noarch \
    "${packages[@]}"

  mkdir -p "$SYSROOT"
  for rpm_file in "$rpm_dir"/*.rpm; do
    (cd "$SYSROOT" && rpm2cpio "$rpm_file" | cpio -idmu --quiet)
  done
  rm -rf "$rpm_dir"
}

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This script must run as root." >&2
  exit 1
fi

if linux_arm64_toolchain_ready; then
  fix_linux_arm64_sysroot_links
  write_linux_arm64_environment
  echo "Linux arm64 toolchain is already available at ${ARM_TOOLCHAIN_PATH}; skipping setup."
  aarch64-linux-gnu-gcc --version
  strings "${SYSROOT}/lib64/libc.so.6" | grep 'GNU C Library' || true
  exit 0
fi

if dnf install --help 2>&1 | grep -q -- '--disable-modular-filtering'; then
  DNF_INSTALL_DISABLE_MODULAR_FILTERING_ARGS=(--disable-modular-filtering)
fi

if dnf download --help 2>&1 | grep -q -- '--disable-modular-filtering'; then
  DNF_DOWNLOAD_DISABLE_MODULAR_FILTERING_ARGS=(--disable-modular-filtering)
fi

dnf install -y dnf-plugins-core curl xz tar cpio rpm

if [[ ! -x "${ARM_TOOLCHAIN_PATH}/sys-bin/aarch64-linux-gnu-gcc" ]]; then
  tmp_tar="$(mktemp)"
  curl -L "$ARM_TOOLCHAIN_URL" -o "$tmp_tar"
  rm -rf "$ARM_TOOLCHAIN_PATH"
  mkdir -p "$ARM_TOOLCHAIN_PATH"
  tar -xf "$tmp_tar" --strip-components=1 -C "$ARM_TOOLCHAIN_PATH"
  rm -f "$tmp_tar"
  mkdir -p "${ARM_TOOLCHAIN_PATH}/sys-bin"
  for tool in gcc g++ ar as ld nm objcopy objdump ranlib strip; do
    ln -sf "${ARM_TOOLCHAIN_PATH}/bin/aarch64-none-linux-gnu-${tool}" "${ARM_TOOLCHAIN_PATH}/sys-bin/aarch64-linux-gnu-${tool}"
  done
fi

fix_linux_arm64_sysroot_links

if ! linux_arm64_sysroot_ready; then
  if ! dnf --installroot="$SYSROOT" \
    --forcearch=aarch64 \
    --releasever="$RHEL_RELEASEVER" \
    --setopt=install_weak_deps=False \
    --setopt=tsflags=nodocs \
    --setopt=module_platform_id="$MODULE_PLATFORM_ID" \
    "${DNF_INSTALL_DISABLE_MODULAR_FILTERING_ARGS[@]}" \
    install -y glibc glibc-devel glibc-headers kernel-headers libgcc libstdc++ libstdc++-devel libxcrypt-devel; then
    echo "WARNING: dnf installroot failed; falling back to downloading and extracting aarch64 RPMs into ${SYSROOT}." >&2
    install_linux_arm64_sysroot_from_rpms
  fi
fi

if ! linux_arm64_sysroot_ready; then
  fix_linux_arm64_sysroot_links
fi

if ! linux_arm64_sysroot_ready; then
  echo "ERROR: Linux arm64 sysroot setup did not produce required glibc and libstdc++ headers in ${SYSROOT}." >&2
  exit 1
fi

write_linux_arm64_environment

if command -v rustup >/dev/null 2>&1; then
  rust_target_installed aarch64-unknown-linux-gnu || rustup target add aarch64-unknown-linux-gnu
fi

aarch64-linux-gnu-gcc --version
strings "${SYSROOT}/lib64/libc.so.6" | grep 'GNU C Library' || true
