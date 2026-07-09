#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292,2207

set -euo pipefail

brew install 'bash' 'coreutils' 'ragel' 'curl' 'pkg-config' 'make' 'git' 'svn' 'gcc' \
'autoconf' 'automake' 'yasm' 'cvs' 'flex' 'bison' 'ed' 'pax' 'unzip' 'wget' 'xz' 'nasm' \
'gperf' 'autogen' 'bzip2' 'python3' 'cython' 'bc' 'texinfo' 'glib' 'llvm' 'lld' 'pipx' \
'autoconf-archive' 'bc' 'binutils' 'gpatch' 'libtool' 'gsed' 'libdatrie' 'ripgrep'
echo "HOMEBREW_BASH=$(brew --prefix)/bin/bash" >> "$GITHUB_ENV"