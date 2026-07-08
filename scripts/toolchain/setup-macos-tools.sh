#!/usr/bin/env bash

set -euo pipefail

brew install 'bash' 'coreutils' 'ragel' 'curl' 'pkg-config' 'make' 'git' 'svn' 'gcc' \
'autoconf' 'automake' 'yasm' 'cvs' 'flex' 'bison' 'ed' 'pax' 'unzip' 'wget' 'xz' 'nasm' \
'gperf' 'autogen' 'bzip2' 'python3' 'cython' 'bc' 'texinfo' 'glib' 'llvm' 'lld' 'pipx' \
'autoconf-archive' 'bc' 'binutils' 'gpatch' 'libtool' 'gsed' 'libdatrie' 'ripgrep'
echo "HOMEBREW_BASH=$(brew --prefix)/bin/bash" >> "$GITHUB_ENV"