#!/bin/bash

# shellcheck disable=SC2317
# shellcheck disable=SC1091
# shellcheck disable=SC2120

#echo -e "${SCRIPTDIR}/variable.sh"
#echo -e "${SCRIPTDIR}/function.sh"

source "${SCRIPTDIR}/function.sh"

#===============================================================================================
#                                     WINDOWS BUILD LIBRARIES
#===============================================================================================

build_dlfcn() {
	if [[ $compiler_flavors != "native" ]]; then # build some stuff that don't build native...
    change_dir "$src_dir"
		do_git_checkout https://github.com/dlfcn-win32/dlfcn-win32.git
		change_dir dlfcn-win32_git
		if [[ ! -f Makefile.bak ]]; then # Change CFLAGS.
			sed -i.bak "s/-O3/-O2/" Makefile
		fi
		do_configure "--prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix" # rejects some normal cross compile options so custom here
		do_make_and_make_install
		gen_ld_script libdl.a dl_s -lpsapi # dlfcn-win32's 'README.md': "If you are linking to the static 'dl.lib' or 'libdl.a', then you would need to explicitly add 'psapi.lib' or '-lpsapi' to your linking command, depending on if MinGW is used."
		change_dir "$src_dir"
	fi
}

build_bzip2() {
  change_dir "$src_dir"
	download_and_unpack_file https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
	change_dir bzip2-1.0.8
	apply_patch "file://$WINPATCHDIR/bzip2-1.0.8_brokenstuff.diff"
	if [[ ! -f ./libbz2.a ]] || [[ -f $mingw_w64_x86_64_prefix/lib/libbz2.a && ! $(/usr/bin/env md5sum ./libbz2.a) = $(/usr/bin/env md5sum "$mingw_w64_x86_64_prefix"/lib/libbz2.a) ]]; then # Not built or different build installed
		do_make "$compiler_flags libbz2.a"
		install -m644 bzlib.h "$mingw_w64_x86_64_prefix"/include/bzlib.h
		install -m644 libbz2.a "$mingw_w64_x86_64_prefix"/lib/libbz2.a
	else
		echo -e "Already made bzip2-1.0.8"
	fi
	change_dir "$src_dir"
}

build_liblzma() {
	change_dir "$src_dir"
	download_and_unpack_file https://sourceforge.net/projects/lzmautils/files/xz-5.8.1.tar.xz
	change_dir xz-5.8.1
	generic_configure "--disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-scripts --disable-doc --disable-nls"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_zlib() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/madler/zlib.git zlib_git
	change_dir zlib_git
	local make_options
	if [[ $compiler_flavors == "native" ]]; then
		export CFLAGS="$CFLAGS -fPIC" # For some reason glib needs this even though we build a static library
	else
		export ARFLAGS=rcs # Native can't take ARFLAGS; https://stackoverflow.com/questions/21396988/zlib-build-not-configuring-properly-with-cross-compiler-ignores-ar
	fi
	do_configure "--prefix=$mingw_w64_x86_64_prefix --static"
	do_make_and_make_install "$compiler_flags ARFLAGS=rcs"
	if [[ $compiler_flavors == "native" ]]; then
		reset_cflags
	else
		unset ARFLAGS
	fi
	change_dir "$src_dir"
}

build_iconv() {
	change_dir "$src_dir"
	download_and_unpack_file https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.18.tar.gz
	change_dir libiconv-1.18
	generic_configure "--disable-nls"
	do_make "install-lib" # No need for 'do_make_install', because 'install-lib' already has install-instructions.
	change_dir "$src_dir"
}

build_brotli() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/google/brotli.git brotli_git v1.0.9 # v1.1.0 static headache stay away
	change_dir brotli_git
	if [ ! -f "brotli.exe" ]; then
		remove_path -f configure
	fi
	generic_configure
	sed -i.bak -e "s/\(allow_undefined=\)yes/\1no/" libtool
	do_make_and_make_install
	sed -i.bak "s/Libs.*$/Libs: -L${libdir} -lbrotlicommon/" "$PKG_CONFIG_PATH/libbrotlicommon.pc" # remove rpaths not possible in conf
	sed -i.bak "s/Libs.*$/Libs: -L${libdir} -lbrotlidec/" "$PKG_CONFIG_PATH/libbrotlidec.pc"
	sed -i.bak "s/Libs.*$/Libs: -L${libdir} -lbrotlienc/" "$PKG_CONFIG_PATH/libbrotlienc.pc"
	change_dir "$src_dir"
}

build_zstd() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/facebook/zstd.git zstd_git v1.5.7
	change_dir zstd_git
	do_cmake "-S build/cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DZSTD_BUILD_SHARED=OFF -DZSTD_USE_STATIC_RUNTIME=ON -DCMAKE_BUILD_WITH_INSTALL_RPATH=OFF"
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_sdl2() {
	change_dir "$src_dir"
	download_and_unpack_file https://www.libsdl.org/release/SDL2-2.32.10.tar.gz
	change_dir SDL2-2.32.10
	apply_patch "file://$WINPATCHDIR/SDL2-2.32.10_lib-only.diff"
	if [[ ! -f configure.bak ]]; then
		sed -i.bak "s/ -mwindows//" configure # Allow ffmpeg to output anything to console.
	fi
	export CFLAGS="$CFLAGS -DDECLSPEC=" # avoid SDL trac tickets 939 and 282 [broken shared builds]
	if [[ $compiler_flavors == "native" ]]; then
		unset PKG_CONFIG_LIBDIR # Allow locally installed things for native builds; libpulse-dev is an important one otherwise no audio for most Linux
	fi
	generic_configure "--bindir=$mingw_bin_path"
	do_make_and_make_install
	if [[ $compiler_flavors == "native" ]]; then
		export PKG_CONFIG_LIBDIR=
	fi
	if [[ ! -f $mingw_bin_path/$host_target-sdl2-config ]]; then
		mv "$mingw_bin_path/sdl2-config" "$mingw_bin_path/$host_target-sdl2-config" # At the moment FFmpeg's 'configure' doesn't use 'sdl2-config', because it gives priority to 'sdl2.pc', but when it does, it expects 'i686-w64-mingw32-sdl2-config' in 'cross_compilers/mingw-w64-i686/bin'.
	fi
	reset_cflags
	change_dir "$src_dir"
}

build_amd_amf_headers() {
	change_dir "$src_dir"
	# was https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git too big
	# or https://github.com/DeadSix27/AMF smaller
	# but even smaller!
	do_git_checkout https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git amf_headers_git
	change_dir amf_headers_git
	if [ ! -f "already_installed" ]; then
		#rm -rf "./Thirdparty" # ?? plus too chatty...
		if [ ! -d "$mingw_w64_x86_64_prefix/include/AMF" ]; then
			create_dir "$mingw_w64_x86_64_prefix/include/AMF"
		fi
		cp -av "amf/public/include/." "$mingw_w64_x86_64_prefix/include/AMF"
		touch "already_installed"
	fi
	change_dir "$src_dir"
}

build_nv_headers() {
	change_dir "$src_dir"
	if [[ $ffmpeg_git_checkout_version == *"n6.0"* ]] || [[ $ffmpeg_git_checkout_version == *"n5"* ]] || [[ $ffmpeg_git_checkout_version == *"n4"* ]] || [[ $ffmpeg_git_checkout_version == *"n3"* ]] || [[ $ffmpeg_git_checkout_version == *"n2"* ]]; then
		# nv_headers for old versions
		do_git_checkout https://github.com/FFmpeg/nv-codec-headers.git nv-codec-headers_git n12.0.16.1
	else
		do_git_checkout https://github.com/FFmpeg/nv-codec-headers.git
	fi
	change_dir nv-codec-headers_git
	do_make_install "PREFIX=$mingw_w64_x86_64_prefix" # just copies in headers
	change_dir "$src_dir"
}

build_intel_qsv_mfx() {   
	change_dir "$src_dir"                                                            # disableable via command line switch...
	do_git_checkout https://github.com/lu-zero/mfx_dispatch.git mfx_dispatch_git 2cd279f # lu-zero?? oh well seems somewhat supported...
	change_dir mfx_dispatch_git
	if [[ ! -f "configure" ]]; then
		autoreconf -fiv || exit 1
		automake --add-missing || exit 1
	fi
	if [[ $compiler_flavors == "native" && $OSTYPE != darwin* ]]; then
		unset PKG_CONFIG_LIBDIR # allow mfx_dispatch to use libva-dev or some odd on linux...not sure for OS X so just disable it :)
		generic_configure_make_install
		export PKG_CONFIG_LIBDIR=
	else
		generic_configure_make_install
	fi
	change_dir "$src_dir"
}

build_libvpl() {
	if [[ $compiler_flavors != "native" ]]; then
		change_dir "$src_dir"
		# build_intel_qsv_mfx
		do_git_checkout https://github.com/intel/libvpl.git libvpl_git # f8d9891
		change_dir libvpl_git
		if [ "$bits_target" = "32" ]; then
			apply_patch "https://raw.githubusercontent.com/msys2/MINGW-packages/master/mingw-w64-libvpl/0003-cmake-fix-32bit-install.patch" -p1
		fi
		do_cmake "-B build -GNinja -DCMAKE_BUILD_TYPE=Release -DINSTALL_EXAMPLES=OFF -DINSTALL_DEV=ON -DBUILD_EXPERIMENTAL=OFF"
		do_ninja_and_ninja_install
		sed -i.bak "s/Libs: .*/& -lstdc++/" "$PKG_CONFIG_PATH/vpl.pc"
		change_dir "$src_dir"
	fi
}

build_giflib() {
	change_dir "$src_dir"
	generic_download_and_make_and_install https://sourceforge.net/projects/giflib/files/giflib-5.1.4.tar.gz
	change_dir "$src_dir"
}

build_libleptonica() {
	build_libjpeg_turbo
	build_giflib
	change_dir "$src_dir"
	do_git_checkout "https://github.com/DanBloomberg/leptonica.git leptonica_git"
	change_dir "leptonica_git"
	export CPPFLAGS="-DOPJ_STATIC"
	generic_configure_make_install
	reset_cppflags
	change_dir "$src_dir"
}

build_libtiff() {
	build_libjpeg_turbo # auto uses it?
	change_dir "$src_dir"
	generic_download_and_make_and_install http://download.osgeo.org/libtiff/tiff-4.7.1.tar.gz
	sed -i.bak "s/-ltiff.*$/-ltiff -llzma -ljpeg -lz/" "$PKG_CONFIG_PATH/libtiff-4.pc" # static deps
	change_dir "$src_dir"
}

build_libtensorflow() {
	change_dir "$src_dir"
	if [[ ! -e Tensorflow ]]; then
		create_dir "Tensorflow"
		change_dir "Tensorflow"
		wget "https://storage.googleapis.com/tensorflow/versions/2.18.1/libtensorflow-cpu-windows-x86_64.zip" # tensorflow.dll required by ffmpeg to run
		unzip -o "libtensorflow-cpu-windows-x86_64.zip" -d "$mingw_w64_x86_64_prefix"
		remove_path -f "libtensorflow-cpu-windows-x86_64.zip"
		change_dir ..
	else
		echo -e "Tensorflow already installed"
	fi
	change_dir "$src_dir"
}

build_gettext() {
	change_dir "$src_dir"
	generic_download_and_make_and_install "https://ftp.gnu.org/pub/gnu/gettext/gettext-0.26.tar.gz"
	change_dir "$src_dir"
}

build_libffi() {
	change_dir "$src_dir"
	download_and_unpack_file "https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz" # also dep
	change_dir libffi-3.5.2
	apply_patch "file://$WINPATCHDIR/libffi.patch" -p1
	generic_configure_make_install
	change_dir "$src_dir"
}

build_glib() {
	build_gettext
	build_libffi
	change_dir "$src_dir"
	do_git_checkout https://github.com/GNOME/glib.git glib_git
	activate_meson
	change_dir glib_git
	local meson_options="setup --force-fallback-for=libpcre -Dforce_posix_threads=true -Dman-pages=disabled -Dsysprof=disabled -Dglib_debug=disabled -Dtests=false --wrap-mode=default . build"
	if [[ $compiler_flavors != "native" ]]; then
		# get_local_meson_cross_with_propeties
		meson_options+=" --cross-file=${BASEDIR}/meson-cross.mingw.txt"
		do_meson "$meson_options"
	else
		generic_meson "$meson_options"
	fi
	do_ninja_and_ninja_install
	if [[ $compiler_flavors == "native" ]]; then
		sed -i.bak "s/-lglib-2.0.*$/-lglib-2.0 -lm -liconv/" "$PKG_CONFIG_PATH/glib-2.0.pc"
	else
		sed -i.bak "s/-lglib-2.0.*$/-lglib-2.0 -lintl -lws2_32 -lwinmm -lm -liconv -lole32/" "$PKG_CONFIG_PATH/glib-2.0.pc"
	fi
	deactivate
	change_dir "$src_dir"
}

build_lensfun() {
	build_glib
	change_dir "$src_dir"
	do_git_checkout "https://github.com/lensfun/lensfun.git lensfun_git"
	change_dir "lensfun_git"
	export CPPFLAGS="$CPPFLAGS-DGLIB_STATIC_COMPILATION"
	export CXXFLAGS="$CFLAGS -DGLIB_STATIC_COMPILATION"
	do_cmake "-DBUILD_STATIC=on -DCMAKE_INSTALL_DATAROOTDIR=$mingw_w64_x86_64_prefix -DBUILD_TESTS=off -DBUILD_DOC=off -DINSTALL_HELPER_SCRIPTS=off -DINSTALL_PYTHON_MODULE=OFF"
	do_make_and_make_install
	sed -i.bak "s/-llensfun/-llensfun -lstdc++/" "$PKG_CONFIG_PATH/lensfun.pc"
	reset_cppflags
	unset CXXFLAGS
	change_dir "$src_dir"
}

build_lz4() {
	change_dir "$src_dir"
	download_and_unpack_file https://github.com/lz4/lz4/releases/download/v1.10.0/lz4-1.10.0.tar.gz
	change_dir lz4-1.10.0
	do_cmake "-S build/cmake -B build -GNinja -DCMAKE_BUILD_TYPE=Release -DBUILD_STATIC_LIBS=ON"
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_libarchive() {
	build_lz4
	change_dir "$src_dir"
	download_and_unpack_file https://github.com/libarchive/libarchive/releases/download/v3.8.1/libarchive-3.8.1.tar.gz
	change_dir libarchive-3.8.1
	generic_configure "--with-nettle --bindir=$mingw_w64_x86_64_prefix/bin --without-openssl --without-iconv --disable-posix-regex-lib"
	do_make_install
	change_dir "$src_dir"
}

build_flac() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/xiph/flac.git flac_git
	change_dir flac_git
	do_cmake "-B build -DCMAKE_BUILD_TYPE=Release -DINSTALL_MANPAGES=OFF -GNinja"
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_openmpt() {
	build_flac
	change_dir "$src_dir"
	do_git_checkout https://github.com/OpenMPT/openmpt.git openmpt_git # OpenMPT-1.30
	change_dir openmpt_git
	do_make_and_make_install "PREFIX=$mingw_w64_x86_64_prefix CONFIG=mingw64-win64 EXESUFFIX=.exe SOSUFFIX=.dll SOSUFFIXWINDOWS=1 DYNLINK=0 SHARED_LIB=0 STATIC_LIB=1 
      SHARED_SONAME=0 IS_CROSS=1 NO_ZLIB=0 NO_LTDL=0 NO_DL=0 NO_MPG123=0 NO_OGG=0 NO_VORBIS=0 NO_VORBISFILE=0 NO_PORTAUDIO=1 NO_PORTAUDIOCPP=1 NO_PULSEAUDIO=1 NO_SDL=0 
      NO_SDL2=0 NO_SNDFILE=0 NO_FLAC=0 EXAMPLES=0 OPENMPT123=0 TEST=0" # OPENMPT123=1 >>> fail
	sed -i.bak "s/Libs.private.*/& -lrpcrt4/" "$PKG_CONFIG_PATH/libopenmpt.pc"
	change_dir "$src_dir"
}

build_libpsl() {
	change_dir "$src_dir"
	export CFLAGS="-DPSL_STATIC"
	download_and_unpack_file https://github.com/rockdaboot/libpsl/releases/download/0.21.5/libpsl-0.21.5.tar.gz
	change_dir libpsl-0.21.5
	generic_configure "--disable-nls --disable-rpath --disable-gtk-doc-html --disable-man --disable-runtime"
	do_make_and_make_install
	sed -i.bak "s/Libs: .*/& -lidn2 -lunistring -lws2_32 -liconv/" "$PKG_CONFIG_PATH/libpsl.pc"
	reset_cflags
	change_dir "$src_dir"
}

build_nghttp2() {
	change_dir "$src_dir"
	export CFLAGS="-DNGHTTP2_STATICLIB"
	download_and_unpack_file https://github.com/nghttp2/nghttp2/releases/download/v1.67.1/nghttp2-1.67.1.tar.gz
	change_dir nghttp2-1.67.1
	do_cmake "-B build -DENABLE_LIB_ONLY=1 -DBUILD_SHARED_LIBS=0 -DBUILD_STATIC_LIBS=1 -GNinja"
	do_ninja_and_ninja_install
	reset_cflags
	change_dir "$src_dir"
}

build_libssh2() {
	change_dir "$src_dir"
	generic_download_and_make_and_install https://github.com/libssh2/libssh2/releases/download/libssh2-1.11.1/libssh2-1.11.1.tar.gz
	change_dir "$src_dir"
}

build_curl() {
	change_dir "$src_dir"
	build_libssh2
	build_zstd
	build_brotli
	build_libpsl
	build_nghttp2
	local config_options=""
	if [[ $compiler_flavors == "native" ]]; then
		local config_options+="-DGNUTLS_INTERNAL_BUILD"
	fi
	export CPPFLAGS+="$CPPFLAGS -DNGHTTP2_STATICLIB -DPSL_STATIC $config_options"
	change_dir "$src_dir"
	do_git_checkout https://github.com/curl/curl.git curl_git curl-8_16_0
	change_dir curl_git
	if [[ $compiler_flavors != "native" ]]; then
		generic_configure "--with-libssh2 --with-libpsl --with-libidn2 --disable-debug --enable-hsts --with-brotli --enable-versioned-symbols --enable-sspi --with-schannel"
	else
		generic_configure "--with-gnutls --with-libssh2 --with-libpsl --with-libidn2 --disable-debug --enable-hsts --with-brotli --enable-versioned-symbols" # untested on native
	fi
	do_make_and_make_install
	reset_cppflags
	change_dir "$src_dir"
}

build_libtesseract() {
	build_libtiff
	build_libleptonica
	build_libarchive
	change_dir "$src_dir"
	do_git_checkout https://github.com/tesseract-ocr/tesseract.git tesseract_git
	change_dir tesseract_git
	export CPPFLAGS="$CPPFLAGS -DCURL_STATICLIB"
	generic_configure "--disable-openmp --with-archive --disable-graphics --disable-tessdata-prefix --with-curl LIBLEPT_HEADERSDIR=$mingw_w64_x86_64_prefix/include --datadir=$mingw_w64_x86_64_prefix/bin"
	do_make_and_make_install
	sed -i.bak "s/Requires.private.*/& lept libarchive liblzma libtiff-4 libcurl/" "$PKG_CONFIG_PATH/tesseract.pc"
	sed -i "s/-ltesseract.*$/-ltesseract -lstdc++ -lws2_32 -lbz2 -lz -liconv -lpthread  -lgdi32 -lcrypt32/" "$PKG_CONFIG_PATH/tesseract.pc"
	if [[ ! -f $mingw_w64_x86_64_prefix/bin/tessdata/tessdata/eng.traineddata ]]; then
		create_dir "$mingw_w64_x86_64_prefix/bin/tessdata"
		cp -f /usr/share/tesseract-ocr/**/tessdata/eng.traineddata "$mingw_w64_x86_64_prefix/bin/tessdata/"
	fi
	reset_cppflags
	change_dir "$src_dir"
}

build_libzimg() {
	change_dir "$src_dir"
	do_git_checkout_and_make_install https://github.com/sekrit-twc/zimg.git zimg_git
}

build_libopenjpeg() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/uclouvain/openjpeg.git openjpeg_git
	change_dir openjpeg_git
	do_cmake_and_install "-DBUILD_CODEC=0"
	change_dir "$src_dir"
}

build_glew() {
	change_dir "$src_dir"
	download_and_unpack_file https://sourceforge.net/projects/glew/files/glew/2.2.0/glew-2.2.0.tgz glew-2.2.0
	change_dir glew-2.2.0/build
	local cmake_params=""
	if [[ $compiler_flavors != "native" ]]; then
		cmake_params+=" -DWIN32=1"
	fi
	do_cmake_from_build_dir ./cmake "$cmake_params" # "-DWITH_FFMPEG=0 -DOPENCV_GENERATE_PKGCONFIG=1 -DHAVE_DSHOW=0"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_glfw() {
	change_dir "$src_dir"
	download_and_unpack_file https://github.com/glfw/glfw/releases/download/3.4/glfw-3.4.zip glfw-3.4
	change_dir glfw-3.4
	do_cmake_and_install
	change_dir "$src_dir"
}

build_libpng() {
	change_dir "$src_dir"
	do_git_checkout_and_make_install https://github.com/glennrp/libpng.git
}

build_libwebp() {
	change_dir "$src_dir"
	do_git_checkout https://chromium.googlesource.com/webm/libwebp.git libwebp_git
	change_dir libwebp_git
	export LIBPNG_CONFIG="$mingw_w64_x86_64_prefix/bin/libpng-config --static" # LibPNG somehow doesn't get autodetected.
	generic_configure "--disable-wic"
	do_make_and_make_install
	unset LIBPNG_CONFIG
	change_dir "$src_dir"
}

build_harfbuzz() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/harfbuzz/harfbuzz.git harfbuzz_git 10.4.0 # 11.0.0 no longer found by ffmpeg via this method, multiple issues, breaks harfbuzz freetype circular depends hack
	activate_meson
	build_freetype
	change_dir harfbuzz_git
	if [[ ! -f DUN ]]; then
		local meson_options="setup -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dicu=disabled -Dtests=disabled -Dintrospection=disabled -Ddocs=disabled . build"
		if [[ $compiler_flavors != "native" ]]; then
			# get_local_meson_cross_with_propeties
			meson_options+=" --cross-file=${BASEDIR}/meson-cross.mingw.txt"
			do_meson "$meson_options"
		else
			generic_meson "$meson_options"
		fi
		do_ninja_and_ninja_install
		touch DUN
	fi
	change_dir "$src_dir"
	build_freetype # with harfbuzz now
	deactivate
	sed -i.bak 's/-lfreetype.*/-lfreetype -lharfbuzz -lpng -lbz2/' "$PKG_CONFIG_PATH/freetype2.pc"
	sed -i.bak 's/-lharfbuzz.*/-lfreetype -lharfbuzz -lpng -lbz2/' "$PKG_CONFIG_PATH/harfbuzz.pc"
}

build_freetype() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/freetype/freetype.git freetype_git
	change_dir freetype_git
	local config_options=""
	if [[ -e $PKG_CONFIG_PATH/harfbuzz.pc ]]; then
		local config_options+=" -Dharfbuzz=enabled"
	fi
	local meson_options="setup $config_options . build"
	if [[ $compiler_flavors != "native" ]]; then
		# get_local_meson_cross_with_propeties
		meson_options+=" --cross-file=${BASEDIR}/meson-cross.mingw.txt"
		do_meson "$meson_options"
	else
		generic_meson "$meson_options"
	fi
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_libxml2() {
	change_dir "$src_dir"
	do_git_checkout https://gitlab.gnome.org/GNOME/libxml2.git libxml2_git
	change_dir libxml2_git
	generic_configure "--with-ftp=no --with-http=no --with-python=no"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libvmaf() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/Netflix/vmaf.git vmaf_git
	activate_meson
	change_dir vmaf_git/libvmaf
	local meson_options="setup -Denable_float=true -Dbuilt_in_models=true -Denable_tests=false -Denable_docs=false . build"
	if [[ $compiler_flavors != "native" ]]; then
		# get_local_meson_cross_with_propeties
		meson_options+=" --cross-file=${BASEDIR}/meson-cross.mingw.txt"
		do_meson "$meson_options"
	else
		generic_meson "$meson_options"
	fi
	do_ninja_and_ninja_install
	sed -i.bak "s/Libs: .*/& -lstdc++/" "$PKG_CONFIG_PATH/libvmaf.pc"
	deactivate
	change_dir "$src_dir"
}

build_fontconfig() {
	change_dir "$src_dir"
	do_git_checkout https://gitlab.freedesktop.org/fontconfig/fontconfig.git fontconfig_git # meson build for fontconfig no good
	change_dir fontconfig_git
	generic_configure "--enable-iconv --enable-libxml2 --disable-docs --with-libiconv" # Use Libxml2 instead of Expat; will find libintl from gettext on 2nd pass build and ffmpeg rejects it
	do_make_and_make_install
	change_dir "$src_dir"
}

build_gmp() {
	change_dir "$src_dir"
	download_and_unpack_file https://ftp.gnu.org/pub/gnu/gmp/gmp-6.3.0.tar.xz
	change_dir gmp-6.3.0
	export CC_FOR_BUILD=/usr/bin/gcc # WSL seems to need this..
	export CPP_FOR_BUILD=usr/bin/cpp
	generic_configure "ABI=$bits_target"
	unset CC_FOR_BUILD
	unset CPP_FOR_BUILD
	do_make_and_make_install
	change_dir "$src_dir"
}

build_librtmfp() {
	# needs some version of openssl...
	# build_openssl_1_0_2 # fails OS X
	build_openssl_1_1_1 # fails WSL
	change_dir "$src_dir"
	do_git_checkout https://github.com/MonaSolutions/librtmfp.git
	change_dir librtmfp_git/include/Base
	do_git_checkout https://github.com/meganz/mingw-std-threads.git mingw-std-threads # our g++ apparently doesn't have std::mutex baked in...weird...this replaces it...
	change_dir ../../..
	change_dir librtmfp_git
	if [[ $compiler_flavors != "native" ]]; then
		apply_patch "file://$WINPATCHDIR/rtmfp.static.cross.patch" -p1  # works e48efb4f
		apply_patch "file://$WINPATCHDIR/rtmfp_capitalization.diff" -p1 # cross for windows needs it if on linux...
		apply_patch "file://$WINPATCHDIR/librtmfp_xp.diff.diff" -p1     # cross for windows needs it if on linux...
	else
		apply_patch "file://$WINPATCHDIR/rtfmp.static.make.patch" -p1
	fi
	do_make "$compiler_flags GPP=${cross_prefix}g++"
	do_make_install "prefix=$mingw_w64_x86_64_prefix PKGCONFIGPATH=$PKG_CONFIG_PATH"
	if [[ $compiler_flavors == "native" ]]; then
		sed -i.bak "s/-lrtmfp.*/-lrtmfp -lstdc++/" "$PKG_CONFIG_PATH/librtmfp.pc"
	else
		sed -i.bak "s/-lrtmfp.*/-lrtmfp -lstdc++ -lws2_32 -liphlpapi/" "$PKG_CONFIG_PATH/librtmfp.pc"
	fi
	change_dir "$src_dir"
}

build_libnettle() {
	change_dir "$src_dir"
	download_and_unpack_file https://ftp.gnu.org/gnu/nettle/nettle-3.10.2.tar.gz
	change_dir nettle-3.10.2
	local config_options="--disable-openssl --disable-documentation" # in case we have both gnutls and openssl, just use gnutls [except that gnutls uses this so...huh?
	if [[ $compiler_flavors == "native" ]]; then
		config_options+=" --libdir=${mingw_w64_x86_64_prefix}/lib" # Otherwise native builds install to /lib32 or /lib64 which gnutls doesn't find
	fi
	generic_configure "$config_options" # in case we have both gnutls and openssl, just use gnutls [except that gnutls uses this so...huh? https://github.com/rdp/ffmpeg-windows-build-helpers/issues/25#issuecomment-28158515
	do_make_and_make_install            # What's up with "Configured with: ... --with-gmp=/cygdrive/d/ffmpeg-windows-build-helpers-master/native_build/windows/ffmpeg_local_builds/prebuilt/cross_compilers/pkgs/gmp/gmp-6.1.2-i686" in 'config.log'? Isn't the 'gmp-6.1.2' above being used?
	change_dir "$src_dir"
}

build_unistring() {
	change_dir "$src_dir"
	generic_download_and_make_and_install https://ftp.gnu.org/gnu/libunistring/libunistring-1.4.1.tar.gz
	change_dir "$src_dir"
}

build_libidn2() {
	change_dir "$src_dir"
	download_and_unpack_file https://ftp.gnu.org/gnu/libidn/libidn2-2.3.8.tar.gz
	change_dir libidn2-2.3.8
	generic_configure "--disable-doc --disable-rpath --disable-nls --disable-gtk-doc-html --disable-fast-install"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_gnutls() {
	change_dir "$src_dir"
	download_and_unpack_file https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.9.tar.xz # v3.8.10 not found by ffmpeg with identical .pc?
	change_dir gnutls-3.8.9
	export CFLAGS="-Wno-int-conversion"
	local config_options=""
	if [[ $compiler_flavors != "native" ]]; then
		local config_options+=" --disable-non-suiteb-curves"
	fi
	generic_configure "--disable-cxx --disable-doc --disable-tools --disable-tests --disable-nls --disable-rpath --disable-libdane --disable-gcc-warnings --disable-code-coverage
      --without-p11-kit --with-idn --without-tpm --with-included-unistring --with-included-libtasn1 -disable-gtk-doc-html --with-brotli $config_options"
	do_make_and_make_install
	reset_cflags
	if [[ $compiler_flavors != "native" ]]; then
		sed -i.bak 's/-lgnutls.*/-lgnutls -lcrypt32 -lnettle -lhogweed -lgmp -liconv -lunistring/' "$PKG_CONFIG_PATH/gnutls.pc"
		if [[ $OSTYPE == darwin* ]]; then
			sed -i.bak 's/-lgnutls.*/-lgnutls -framework Security -framework Foundation/' "$PKG_CONFIG_PATH/gnutls.pc"
		fi
	fi
	change_dir "$src_dir"
}

build_openssl_1_0_2() {
	change_dir "$src_dir"
	download_and_unpack_file https://www.openssl.org/source/openssl-1.0.2p.tar.gz
	change_dir openssl-1.0.2p
	apply_patch "file://$WINPATCHDIR/openssl-1.0.2l_lib-only.diff"
	export CC="${cross_prefix}gcc"
	export AR="${cross_prefix}ar"
	export RANLIB="${cross_prefix}ranlib"
	local config_options="--prefix=$mingw_w64_x86_64_prefix zlib "
	if [ "$1" = "dllonly" ]; then
		config_options+="shared "
	else
		config_options+="no-shared no-dso "
	fi
	if [ "$bits_target" = "32" ]; then
		config_options+="mingw" # Build shared libraries ('libeay32.dll' and 'ssleay32.dll') if "dllonly" is specified.
		local arch=x86
	else
		config_options+="mingw64" # Build shared libraries ('libeay64.dll' and 'ssleay64.dll') if "dllonly" is specified.
		local arch=x86_64
	fi
	do_configure "$config_options" ./Configure
	if [[ ! -f Makefile_1 ]]; then
		sed -i_1 "s/-O3/-O2/" Makefile # Change CFLAGS (OpenSSL's 'Configure' already creates a 'Makefile.bak').
	fi
	if [ "$1" = "dllonly" ]; then
		do_make "build_libs"

		create_dir "$WORKDIR/redist" # Strip and pack shared libraries.
		archive="$WORKDIR/redist/openssl-${arch}-v1.0.2l.7z"
		if [[ ! -f $archive ]]; then
			for sharedlib in *.dll; do
				"${cross_prefix}strip" "$sharedlib"
			done
			sed "s/$/\r/" LICENSE >LICENSE.txt
			7z a -mx=9 "$archive" "*.dll" LICENSE.txt && remove_path -f LICENSE.txt
		fi
	else
		do_make_and_make_install
	fi
	unset CC
	unset AR
	unset RANLIB
	change_dir "$src_dir"
}

build_openssl_1_1_1() {
	change_dir "$src_dir"
	download_and_unpack_file https://www.openssl.org/source/openssl-1.1.1.tar.gz
	change_dir openssl-1.1.1
	export CC="${cross_prefix}gcc"
	export AR="${cross_prefix}ar"
	export RANLIB="${cross_prefix}ranlib"
	local config_options="--prefix=$mingw_w64_x86_64_prefix zlib "
	if [ "$1" = "dllonly" ]; then
		config_options+="shared no-engine "
	else
		config_options+="no-shared no-dso no-engine "
	fi
	if [[ $(uname) =~ 5.1 ]] || [[ $(uname) =~ 6.0 ]]; then
		config_options+="no-async " # "Note: on older OSes, like CentOS 5, BSD 5, and Windows XP or Vista, you will need to configure with no-async when building OpenSSL 1.1.0 and above. The configuration system does not detect lack of the Posix feature on the platforms." (https://wiki.openssl.org/index.php/Compilation_and_Installation)
	fi
	if [[ $compiler_flavors == "native" ]]; then
		if [[ $OSTYPE == darwin* ]]; then
			config_options+="darwin64-x86_64-cc "
		else
			config_options+="linux-generic64 "
		fi
		local arch=native
	elif [ "$bits_target" = "32" ]; then
		config_options+="mingw" # Build shared libraries ('libcrypto-1_1.dll' and 'libssl-1_1.dll') if "dllonly" is specified.
		local arch=x86
	else
		config_options+="mingw64" # Build shared libraries ('libcrypto-1_1-x64.dll' and 'libssl-1_1-x64.dll') if "dllonly" is specified.
		local arch=x86_64
	fi
	do_configure "$config_options" ./Configure
	if [[ ! -f Makefile.bak ]]; then # Change CFLAGS.
		sed -i.bak "s/-O3/-O2/" Makefile
	fi
	do_make "build_libs"
	if [ "$1" = "dllonly" ]; then
		create_dir "$WORKDIR/redist" # Strip and pack shared libraries.
		archive="$WORKDIR/redist/openssl-${arch}-v1.1.0f.7z"
		if [[ ! -f $archive ]]; then
			for sharedlib in *.dll; do
				"${cross_prefix}strip" "$sharedlib"
			done
			sed "s/$/\r/" LICENSE >LICENSE.txt
			7z a -mx=9 "$archive" "*.dll" LICENSE.txt && remove_path -f LICENSE.txt
		fi
	else
		do_make_install "" "install_dev"
	fi
	unset CC
	unset AR
	unset RANLIB
	change_dir "$src_dir"
}

build_libogg() {
	change_dir "$src_dir"
	do_git_checkout_and_make_install https://github.com/xiph/ogg.git
	change_dir "$src_dir"
}

build_libvorbis() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/xiph/vorbis.git
	change_dir vorbis_git
	generic_configure "--disable-docs --disable-examples --disable-oggtest"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libopus() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/xiph/opus.git opus_git origin/main
	change_dir opus_git
	generic_configure "--disable-doc --disable-extra-programs --disable-stack-protector"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libspeexdsp() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/xiph/speexdsp.git
	change_dir speexdsp_git
	generic_configure "--disable-examples"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libspeex() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/xiph/speex.git
	change_dir speex_git
	export SPEEXDSP_CFLAGS="-I$mingw_w64_x86_64_prefix/include"
	export SPEEXDSP_LIBS="-L$mingw_w64_x86_64_prefix/lib -lspeexdsp" # 'configure' somehow can't find SpeexDSP with 'pkg-config'.
	generic_configure "--disable-binaries"                           # If you do want the libraries, then 'speexdec.exe' needs 'LDFLAGS=-lwinmm'.
	do_make_and_make_install
	unset SPEEXDSP_CFLAGS
	unset SPEEXDSP_LIBS
	change_dir "$src_dir"
}

build_libtheora() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/xiph/theora.git
	change_dir theora_git
	generic_configure "--disable-doc --disable-spec --disable-oggtest --disable-vorbistest --disable-examples --disable-asm" # disable asm: avoid [theora @ 0x1043144a0]error in unpack_block_qpis in 64 bit... [OK OS X 64 bit tho...]
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libsndfile() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/libsndfile/libsndfile.git
	change_dir libsndfile_git
	generic_configure "--disable-sqlite --disable-external-libs --disable-full-suite"
	do_make_and_make_install
	if [[ ! -f $mingw_w64_x86_64_prefix/lib/libgsm.a ]]; then
		install -m644 src/GSM610/gsm.h "$mingw_w64_x86_64_prefix/include/gsm.h" || exit 1
		install -m644 src/GSM610/.libs/libgsm.a "$mingw_w64_x86_64_prefix/lib/libgsm.a" || exit 1
	else
		echo -e "already installed GSM 6.10 ..."
	fi
	change_dir "$src_dir"
}

build_mpg123() {
	change_dir "$src_dir"
	do_svn_checkout svn://scm.orgis.org/mpg123/trunk mpg123_svn r5008 # avoid Think again failure
	change_dir mpg123_svn
	generic_configure_make_install
	change_dir "$src_dir"
}

build_lame() {
	change_dir "$src_dir"
	do_svn_checkout https://svn.code.sf.net/p/lame/svn/trunk/lame lame_svn r6525 # anything other than r6525 fails
	change_dir lame_svn
	# sed -i.bak '1s/^\xEF\xBB\xBF//' libmp3lame/i386/nasm.h # Remove a UTF-8 BOM that breaks nasm if it's still there; should be fixed in trunk eventually https://sourceforge.net/p/lame/patches/81/
	generic_configure "--enable-nasm --enable-libmpg123"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_twolame() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/njh/twolame.git twolame_git "origin/main"
	change_dir twolame_git
	if [[ ! -f Makefile.am.bak ]]; then # Library only, front end refuses to build for some reason with git master
		sed -i.bak "/^SUBDIRS/s/ frontend.*//" Makefile.am || exit 1
	fi
	cpu_count=1 # maybe can't handle it http://betterlogic.com/roger/2017/07/mp3lame-woe/ comments
	generic_configure_make_install
	cpu_count=$original_cpu_count
	change_dir "$src_dir"
}

# build_fdk-aac() {
# local checkout_dir=fdk-aac_git
#     if [[ ! -z $fdk_aac_git_checkout_version ]]; then
#       checkout_dir+="_$fdk_aac_git_checkout_version"
#       do_git_checkout "https://github.com/mstorsjo/fdk-aac.git" $checkout_dir "refs/tags/$fdk_aac_git_checkout_version"
#     else
#       do_git_checkout "https://github.com/mstorsjo/fdk-aac.git" $checkout_dir
#     fi
#   change_dir $checkout_dir
#     if [[ ! -f "configure" ]]; then
#       autoreconf -fiv || exit 1
#     fi
#     generic_configure_make_install
#   change_dir ..
# }

# build_AudioToolboxWrapper() {
#   do_git_checkout https://github.com/cynagenautes/AudioToolboxWrapper.git AudioToolboxWrapper_git
#   change_dir AudioToolboxWrapper_git
#     do_cmake "-B build -GNinja"
#     do_ninja_and_ninja_install
#     # This wrapper library enables FFmpeg to use AudioToolbox codecs on Windows, with DLLs shipped with iTunes.
#     # i.e. You need to install iTunes, or be able to LoadLibrary("CoreAudioToolbox.dll"), for this to work.
#     # test ffmpeg build can use it [ffmpeg -f lavfi -i sine=1000 -c aac_at -f mp4 -y NUL]
#   change_dir ..
# }

build_libopencore() {
	change_dir "$src_dir"
	generic_download_and_make_and_install https://sourceforge.net/projects/opencore-amr/files/opencore-amr/opencore-amr-0.1.6.tar.gz
	change_dir "$src_dir"
	generic_download_and_make_and_install https://sourceforge.net/projects/opencore-amr/files/vo-amrwbenc/vo-amrwbenc-0.1.3.tar.gz
	change_dir "$src_dir"
}

build_libilbc() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/TimothyGu/libilbc.git libilbc_git
	change_dir libilbc_git
	do_cmake "-B build -GNinja"
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_libmodplug() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/Konstanty/libmodplug.git
	change_dir libmodplug_git
	sed -i.bak 's/__declspec(dllexport)//' "$mingw_w64_x86_64_prefix/include/libmodplug/modplug.h" #strip DLL import/export directives
	sed -i.bak 's/__declspec(dllimport)//' "$mingw_w64_x86_64_prefix/include/libmodplug/modplug.h"
	if [[ ! -f "configure" ]]; then
		autoreconf -fiv || exit 1
		automake --add-missing || exit 1
	fi
	generic_configure_make_install # or could use cmake I guess
	change_dir "$src_dir"
}

build_libgme() {
	# do_git_checkout https://bitbucket.org/mpyne/game-music-emu.git
	change_dir "$src_dir"
	download_and_unpack_file https://bitbucket.org/mpyne/game-music-emu/downloads/game-music-emu-0.6.3.tar.xz
	change_dir game-music-emu-0.6.3
	do_cmake_and_install "-DENABLE_UBSAN=0"
	change_dir "$src_dir"
}

build_mingw_std_threads() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/meganz/mingw-std-threads.git # it needs std::mutex too :|
	change_dir mingw-std-threads_git
	cp "*.h" "$mingw_w64_x86_64_prefix/include"
	change_dir "$src_dir"
}

build_opencv() {
	build_mingw_std_threads
	#do_git_checkout https://github.com/opencv/opencv.git # too big :|
	change_dir "$src_dir"
	download_and_unpack_file https://github.com/opencv/opencv/archive/3.4.5.zip opencv-3.4.5
	create_dir opencv-3.4.5/build
	change_dir opencv-3.4.5
	apply_patch "file://$WINPATCHDIR/opencv.detection_based.patch"
	change_dir ..
	change_dir opencv-3.4.5/build
	# could do more here, it seems to think it needs its own internal libwebp etc...
	cpu_count=1
	do_cmake_from_build_dir .. "-DWITH_FFMPEG=0 -DOPENCV_GENERATE_PKGCONFIG=1 -DHAVE_DSHOW=0" # https://stackoverflow.com/q/40262928/32453, no pkg config by default on "windows", who cares ffmpeg
	do_make_and_make_install
	cp unix-install/opencv.pc "$PKG_CONFIG_PATH"
	cpu_count=$original_cpu_count
	change_dir "$src_dir"
}

build_facebooktransform360() {
	build_opencv
	change_dir "$src_dir"
	do_git_checkout https://github.com/facebook/transform360.git
	change_dir transform360_git
	apply_patch "file://$WINPATCHDIR/transform360.pi.diff" -p1
	change_dir ..
	change_dir transform360_git/Transform360
	do_cmake ""
	sed -i.bak "s/isystem/I/g" CMakeFiles/Transform360.dir/includes_CXX.rsp # weird stdlib.h error
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libbluray() {
	change_dir "$src_dir"
	do_git_checkout https://code.videolan.org/videolan/libbluray.git
	activate_meson
	change_dir libbluray_git
	apply_patch "https://raw.githubusercontent.com/m-ab-s/mabs-patches/master/libbluray/0001-dec-prefix-with-libbluray-for-now.patch" -p1
	local meson_options="setup -Denable_examples=false -Dbdj_jar=disabled --wrap-mode=default . build"
	if [[ $compiler_flavors != "native" ]]; then
		# get_local_meson_cross_with_propeties
		meson_options+=" --cross-file=${BASEDIR}/meson-cross.mingw.txt"
		do_meson "$meson_options"
	else
		generic_meson "$meson_options"
	fi
	do_ninja_and_ninja_install # "CPPFLAGS=\"-Ddec_init=libbr_dec_init\""
	sed -i.bak "s/-lbluray.*/-lbluray -lstdc++ -lssp -lgdi32/" "$PKG_CONFIG_PATH/libbluray.pc"
	deactivate
	change_dir "$src_dir"
}

build_libbs2b() {
	change_dir "$src_dir"
	download_and_unpack_file https://downloads.sourceforge.net/project/bs2b/libbs2b/3.1.0/libbs2b-3.1.0.tar.gz
	change_dir libbs2b-3.1.0
	apply_patch "file://$WINPATCHDIR/libbs2b.patch"
	sed -i.bak "s/AC_FUNC_MALLOC//" configure.ac # #270
	export LIBS=-lm                              # avoid pow failure linux native
	generic_configure_make_install
	unset LIBS
	change_dir "$src_dir"
}

build_libsoxr() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/chirlu/soxr.git soxr_git
	change_dir soxr_git
	do_cmake_and_install "-DWITH_OPENMP=0 -DBUILD_TESTS=0 -DBUILD_EXAMPLES=0"
	change_dir "$src_dir"
}

build_libflite() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/festvox/flite.git flite_git
	change_dir flite_git
	apply_patch "file://$WINPATCHDIR/flite-2.1.0_mingw-w64-fixes.patch"
	if [[ ! -f main/Makefile.bak ]]; then
		sed -i.bak "s/cp -pd/cp -p/" main/Makefile # friendlier cp for OS X
	fi
	generic_configure "--bindir=$mingw_w64_x86_64_prefix/bin --with-audio=none"
	do_make
	if [[ ! -f $mingw_w64_x86_64_prefix/lib/libflite.a ]]; then
		cp -rf ./build/x86_64-mingw32/lib/libflite* "$mingw_w64_x86_64_prefix/lib/"
		cp -rf include "$mingw_w64_x86_64_prefix/include/flite"
		# cp -rf ./bin/*.exe $mingw_w64_x86_64_prefix/bin # if want .exe's uncomment
	fi
	change_dir "$src_dir"
}

build_libsnappy() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/google/snappy.git snappy_git # got weird failure once 1.1.8
	change_dir snappy_git
	do_cmake_and_install "-DBUILD_BINARY=OFF -DCMAKE_BUILD_TYPE=Release -DSNAPPY_BUILD_TESTS=OFF -DSNAPPY_BUILD_BENCHMARKS=OFF" # extra params from deadsix27 and from new cMakeLists.txt content
	remove_path -f "$mingw_w64_x86_64_prefix/lib/libsnappy.dll.a"                                                                 # unintall shared :|
	change_dir "$src_dir"
}

build_vamp_plugin() {
	#download_and_unpack_file https://code.soundsoftware.ac.uk/attachments/download/2691/vamp-plugin-sdk-2.10.0.tar.gz
	change_dir "$src_dir"
	download_and_unpack_file https://github.com/vamp-plugins/vamp-plugin-sdk/archive/refs/tags/vamp-plugin-sdk-v2.10.zip vamp-plugin-sdk-vamp-plugin-sdk-v2.10
	#cd vamp-plugin-sdk-2.10.0
	change_dir vamp-plugin-sdk-vamp-plugin-sdk-v2.10
	apply_patch "file://$WINPATCHDIR/vamp-plugin-sdk-2.10_static-lib.diff"
	if [[ $compiler_flavors != "native" && ! -f src/vamp-sdk/PluginAdapter.cpp.bak ]]; then
		sed -i.bak "s/#include <mutex>/#include <mingw.mutex.h>/" src/vamp-sdk/PluginAdapter.cpp
	fi
	if [[ ! -f configure.bak ]]; then # Fix for "'M_PI' was not declared in this scope" (see https://stackoverflow.com/a/29264536).
		sed -i.bak "s/c++11/gnu++11/" configure
		sed -i.bak "s/c++11/gnu++11/" Makefile.in
	fi
	do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-programs"
	do_make "install-static" # No need for 'do_make_install', because 'install-static' already has install-instructions.
	change_dir "$src_dir"
}

build_fftw() {
	change_dir "$src_dir"
	download_and_unpack_file http://fftw.org/fftw-3.3.10.tar.gz
	change_dir fftw-3.3.10
	generic_configure "--disable-doc --prefix=$mingw_w64_x86_64_prefix --host=$host_target --enable-static --disable-shared"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libsamplerate() {
	# I think this didn't work with ubuntu 14.04 [too old automake or some odd] :|
	change_dir "$src_dir"
	do_git_checkout_and_make_install https://github.com/erikd/libsamplerate.git
	# but OS X can't use 0.1.9 :|
	# rubberband can use this, but uses speex bundled by default [any difference? who knows!]
	change_dir "$src_dir"
}

build_librubberband() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/breakfastquay/rubberband.git rubberband_git 18c06ab8c431854056407c467f4755f761e36a8e
	change_dir rubberband_git
	apply_patch "file://$WINPATCHDIR/rubberband_git_static-lib.diff" # create install-static target
	do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-ladspa"
	do_make "install-static AR=${cross_prefix}ar" # No need for 'do_make_install', because 'install-static' already has install-instructions.
	sed -i.bak "s/-lrubberband.*$/-lrubberband -lfftw3 -lsamplerate -lstdc++/" "$PKG_CONFIG_PATH/rubberband.pc"
	change_dir "$src_dir"
}

build_frei0r() {
	#do_git_checkout https://github.com/dyne/frei0r.git
	#cd frei0r_git
	change_dir "$src_dir"
	download_and_unpack_file https://github.com/dyne/frei0r/archive/refs/tags/v2.3.3.tar.gz frei0r-2.3.3
	change_dir frei0r-2.3.3
	sed -i.bak 's/-arch i386//' CMakeLists.txt # OS X https://github.com/dyne/frei0r/issues/64
	do_cmake_and_install "-DWITHOUT_OPENCV=1"  # XXX could look at this more...

	create_dir "$WORKDIR/redist" # Strip and pack shared libraries.
	if [ "$bits_target" = 32 ]; then
		local arch=x86
	else
		local arch=x86_64
	fi
	archive="$WORKDIR/redist/frei0r-plugins-${arch}-$(git describe --tags).7z"
	if [[ ! -f "$archive.done" ]]; then
		for sharedlib in "$mingw_w64_x86_64_prefix"/lib/frei0r-1/*.dll; do
			"${cross_prefix}strip" "$sharedlib"
		done
		for doc in AUTHORS ChangeLog COPYING README.md; do
			sed "s/$/\r/" $doc >"$mingw_w64_x86_64_prefix/lib/frei0r-1/$doc.txt"
		done
		7z a -mx=9 "$archive $mingw_w64_x86_64_prefix/lib/frei0r-1" && remove_path -f "$mingw_w64_x86_64_prefix/lib/frei0r-1/*.txt"
		touch "$archive.done" # for those with no 7z so it won't restrip every time
	fi
	change_dir "$src_dir"
}

build_svt_hevc() {
	if [[ "$bits_target" != "32" ]] && [[ $build_svt_hevc = y ]]; then
		change_dir "$src_dir"
		do_git_checkout https://github.com/OpenVisualCloud/SVT-HEVC.git
		create_dir SVT-HEVC_git/release
		change_dir SVT-HEVC_git/release
		do_cmake_from_build_dir .. "-DCMAKE_BUILD_TYPE=Release"
		do_make_and_make_install
		change_dir "$src_dir"
	fi
}

build_svt_vp9() {
	if [[ "$bits_target" != "32" ]] && [[ $build_svt_vp9 = y ]]; then
		change_dir "$src_dir"
		do_git_checkout https://github.com/OpenVisualCloud/SVT-VP9.git
		change_dir SVT-VP9_git/Build
		do_cmake_from_build_dir .. "-DCMAKE_BUILD_TYPE=Release"
		do_make_and_make_install
		change_dir "$src_dir"
	fi
}

build_cpuinfo() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/pytorch/cpuinfo.git
	change_dir cpuinfo_git
	do_cmake_and_install # builds included cpuinfo bugged
	change_dir "$src_dir"
}

build_svt_av1() {
	if [[ "$bits_target" != "32" ]]; then
		build_cpuinfo
		change_dir "$src_dir"
		do_git_checkout https://gitlab.com/AOMediaCodec/SVT-AV1.git SVT-AV1_git
		change_dir SVT-AV1_git
		do_cmake "-B build -GNinja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DUSE_CPUINFO=SYSTEM" # -DSVT_AV1_LTO=OFF if fails try adding this
		do_ninja_and_ninja_install
		change_dir "$src_dir"
	fi
}

build_vidstab() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/georgmartius/vid.stab.git vid.stab_git
	change_dir vid.stab_git
	do_cmake_and_install "-DUSE_OMP=0" # '-DUSE_OMP' is on by default, but somehow libgomp ('cygwin_local_install/lib/gcc/i686-pc-cygwin/5.4.0/include/omp.h') can't be found, so '-DUSE_OMP=0' to prevent a compilation error.
	change_dir "$src_dir"
}

build_libmysofa() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/hoene/libmysofa.git libmysofa_git "origin/main"
	change_dir libmysofa_git
	local cmake_params="-DBUILD_TESTS=0"
	if [[ $compiler_flavors == "native" ]]; then
		cmake_params+=" -DCODE_COVERAGE=0"
	fi
	do_cmake "$cmake_params"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libcaca() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/cacalabs/libcaca.git libcaca_git 813baea7a7bc28986e474541dd1080898fac14d7
	change_dir libcaca_git
	apply_patch "file://$WINPATCHDIR/libcaca_git_stdio-cruft.diff" -p1 # Fix WinXP incompatibility.
	change_dir caca
	sed -i.bak "s/__declspec(dllexport)//g" "*.h" # get rid of the declspec lines otherwise the build will fail for undefined symbols
	sed -i.bak "s/__declspec(dllimport)//g" "*.h"
	change_dir ..
	generic_configure "--libdir=$mingw_w64_x86_64_prefix/lib --disable-csharp --disable-java --disable-cxx --disable-python --disable-ruby --disable-doc --disable-cocoa --disable-ncurses"
	do_make_and_make_install
	if [[ $compiler_flavors == "native" ]]; then
		sed -i.bak "s/-lcaca.*/-lcaca -lX11/" "$PKG_CONFIG_PATH/caca.pc"
	fi
	change_dir "$src_dir"
}

build_libdecklink() {
	change_dir "$src_dir"
	do_git_checkout https://gitlab.com/m-ab-s/decklink-headers.git decklink-headers_git 47d84f8d272ca6872b5440eae57609e36014f3b6
	change_dir decklink-headers_git
	do_make_install "PREFIX=$mingw_w64_x86_64_prefix"
	change_dir "$src_dir"
}

build_zvbi() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/zapping-vbi/zvbi.git zvbi_git
	change_dir zvbi_git
	generic_configure "--disable-dvb --disable-bktr --disable-proxy --disable-nls --without-doxygen --disable-examples --disable-tests --without-libiconv-prefix"
	do_make_and_make_install
	change_dir ..
}

build_fribidi() {
	change_dir "$src_dir"
	download_and_unpack_file https://github.com/fribidi/fribidi/releases/download/v1.0.16/fribidi-1.0.16.tar.xz # Get c2man errors building from repo
	change_dir fribidi-1.0.16
	generic_configure "--disable-debug --disable-deprecated --disable-docs"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libsrt() {
	# do_git_checkout https://github.com/Haivision/srt.git # might be able to use these days...?
	change_dir "$src_dir"
	download_and_unpack_file https://github.com/Haivision/srt/archive/v1.5.4.tar.gz srt-1.5.4
	change_dir srt-1.5.4
	if [[ $compiler_flavors != "native" ]]; then
		apply_patch "file://$WINPATCHDIR/srt.app.patch" -p1
	fi
	# CMake Warning at CMakeLists.txt:893 (message):
	#   On MinGW, some C++11 apps are blocked due to lacking proper C++11 headers
	#   for <thread>.  FIX IF POSSIBLE.
	do_cmake "-DUSE_ENCLIB=gnutls -DENABLE_SHARED=OFF -DENABLE_CXX11=OFF"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libass() {
	change_dir "$src_dir"
	do_git_checkout_and_make_install https://github.com/libass/libass.git
	change_dir "$src_dir"
}

build_vulkan() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/KhronosGroup/Vulkan-Headers.git Vulkan-Headers_git v1.4.326
	change_dir Vulkan-Headers_git
	do_cmake_and_install "-DCMAKE_BUILD_TYPE=Release -DVULKAN_HEADERS_ENABLE_MODULE=NO -DVULKAN_HEADERS_ENABLE_TESTS=NO -DVULKAN_HEADERS_ENABLE_INSTALL=YES"
	change_dir "$src_dir"
}

build_vulkan_loader() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/BtbN/Vulkan-Shim-Loader.git Vulkan-Shim-Loader.git 9657ca8e395ef16c79b57c8bd3f4c1aebb319137
	change_dir Vulkan-Shim-Loader.git
	do_git_checkout https://github.com/KhronosGroup/Vulkan-Headers.git Vulkan-Headers v1.4.326
	do_cmake_and_install "-DCMAKE_BUILD_TYPE=Release -DVULKAN_SHIM_IMPERSONATE=ON"
	change_dir "$src_dir"
}

build_libunwind() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/libunwind/libunwind.git libunwind_git
	change_dir libunwind_git
	autoreconf -i
	do_configure "--host=x86_64-linux-gnu --prefix=$mingw_w64_x86_64_prefix --disable-shared --enable-static"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libxxhash() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/Cyan4973/xxHash.git xxHash_git dev
	change_dir xxHash_git
	do_cmake "-S build/cmake -B build -DCMAKE_BUILD_TYPE=release -GNinja"
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_spirv-cross() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/KhronosGroup/SPIRV-Cross.git SPIRV-Cross_git b26ac3fa8bcfe76c361b56e3284b5276b23453ce
	change_dir SPIRV-Cross_git
	do_cmake "-B build -GNinja -DSPIRV_CROSS_STATIC=ON -DSPIRV_CROSS_SHARED=OFF -DCMAKE_BUILD_TYPE=Release -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF -DSPIRV_CROSS_FORCE_PIC=ON -DSPIRV_CROSS_ENABLE_CPP=OFF"
	do_ninja_and_ninja_install
	mv "$PKG_CONFIG_PATH/spirv-cross-c.pc" "$PKG_CONFIG_PATH/spirv-cross-c-shared.pc"
	change_dir "$src_dir"
}

build_libdovi() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/quietvoid/dovi_tool.git dovi_tool_git
	change_dir dovi_tool_git
	if [[ ! -e $mingw_w64_x86_64_prefix/lib/libdovi.a ]]; then
		curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && . "$HOME/.cargo/env" && rustup update && rustup target add x86_64-pc-windows-gnu # rustup self uninstall
		if [[ $compiler_flavors != "native" ]]; then
			wget https://github.com/quietvoid/dovi_tool/releases/download/2.3.1/dovi_tool-2.3.1-x86_64-pc-windows-msvc.zip
			unzip -o dovi_tool-2.3.1-x86_64-pc-windows-msvc.zip -d "$mingw_w64_x86_64_prefix/bin"
			remove_path -f dovi_tool-2.3.1-x86_64-pc-windows-msvc.zip
		fi

		unset PKG_CONFIG_PATH
		if [[ $compiler_flavors == "native" ]]; then
			cargo build --release --no-default-features --features internal-font && cp /target/release//dovi_tool "$mingw_w64_x86_64_prefix/bin"
		fi
		change_dir dolby_vision
		cargo install cargo-c --features=vendored-openssl
		if [[ $compiler_flavors == "native" ]]; then
			cargo cinstall --release --prefix="$mingw_w64_x86_64_prefix" --libdir="$mingw_w64_x86_64_prefix/lib" --library-type=staticlib
		fi

		export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
		if [[ $compiler_flavors != "native" ]]; then
			cargo cinstall --release --prefix="$mingw_w64_x86_64_prefix" --libdir="$mingw_w64_x86_64_prefix/lib" --library-type=staticlib --target x86_64-pc-windows-gnu
		fi
		change_dir ..
	else
		echo -e "libdovi already installed"
	fi
	change_dir "$src_dir"
}

build_shaderc() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/google/shaderc.git shaderc_git 3a44d5d7850da3601aa43d523a3d228f045fb43d
	change_dir shaderc_git
	./utils/git-sync-deps
	do_cmake "-B build -DCMAKE_BUILD_TYPE=release -GNinja -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_TESTS=ON -DSPIRV_SKIP_TESTS=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON -DENABLE_EXCEPTIONS=ON -DENABLE_GLSLANG_BINARIES=OFF -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_TOOLS_BUILD_STATIC=ON -DBUILD_SHARED_LIBS=OFF"
	do_ninja_and_ninja_install
	cp build/libshaderc_util/libshaderc_util.a "$mingw_w64_x86_64_prefix/lib"
	sed -i.bak "s/Libs: .*/& -lstdc++/" "$PKG_CONFIG_PATH/shaderc_combined.pc"
	sed -i.bak "s/Libs: .*/& -lstdc++/" "$PKG_CONFIG_PATH/shaderc_static.pc"
	change_dir "$src_dir"
}

build_lcms() {
	change_dir "$src_dir"
	do_git_checkout_and_make_install https://github.com/ImageMagick/lcms.git
	change_dir "$src_dir"
}

build_libplacebo() {
	build_vulkan_loader
	build_lcms
	build_libunwind
	build_libxxhash
	build_spirv-cross
	build_libdovi
	build_shaderc
	change_dir "$src_dir"
	do_git_checkout https://code.videolan.org/videolan/libplacebo.git libplacebo_git 515da9548ad734d923c7d0988398053f87b454d5
	activate_meson
	change_dir libplacebo_git
	git submodule update --init --recursive --depth=1 --filter=blob:none
	local config_options=""
	if [[ $OSTYPE != darwin* ]]; then
		local config_options+=" -Dvulkan-registry=$mingw_w64_x86_64_prefix/share/vulkan/registry/vk.xml"
	fi
	local meson_options="setup -Ddemos=false -Dbench=false -Dfuzz=false -Dvulkan=enabled -Dvk-proc-addr=disabled -Dshaderc=enabled -Dglslang=disabled -Dc_link_args=-static -Dcpp_link_args=-static $config_options . build" # https://mesonbuild.com/Dependencies.html#shaderc trigger use of shaderc_combined
	if [[ $compiler_flavors != "native" ]]; then
		# get_local_meson_cross_with_propeties
		meson_options+=" --cross-file=${BASEDIR}/meson-cross.mingw.txt"
		do_meson "$meson_options"
	else
		generic_meson "$meson_options"
	fi
	do_ninja_and_ninja_install
	sed -i.bak 's/-lplacebo.*$/-lplacebo -lm -lshlwapi -lunwind -lxxhash -lversion -lstdc++/' "$PKG_CONFIG_PATH/libplacebo.pc"
	deactivate
	change_dir "$src_dir"
}

build_libaribb24() {
	change_dir "$src_dir"
	do_git_checkout_and_make_install https://github.com/nkoriyama/aribb24
	change_dir "$src_dir"
}

build_libaribcaption() {
	if [[ $ffmpeg_git_checkout_version != *"n6.0"* ]] && [[ $ffmpeg_git_checkout_version != *"n5"* ]] && [[ $ffmpeg_git_checkout_version != *"n4"* ]] && [[ $ffmpeg_git_checkout_version != *"n3"* ]] && [[ $ffmpeg_git_checkout_version != *"n2"* ]]; then
		change_dir "$src_dir"
		do_git_checkout https://github.com/xqq/libaribcaption
		mkdir libaribcaption/build
		change_dir libaribcaption/build
		do_cmake_from_build_dir .. "-DCMAKE_BUILD_TYPE=Release"
		do_make_and_make_install
		change_dir "$src_dir"
	fi
}

build_libxavs() {
	if [[ $compiler_flavors != "native" ]]; then # build some stuff that don't build native...
		change_dir "$src_dir"
		do_git_checkout https://github.com/Distrotech/xavs.git xavs_git
		change_dir xavs_git
		if [[ ! -f Makefile.bak ]]; then
			sed -i.bak "s/O4/O2/" configure # Change CFLAGS.
		fi
		apply_patch "https://patch-diff.githubusercontent.com/raw/Distrotech/xavs/pull/1.patch" -p1
		do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix" # see https://github.com/rdp/ffmpeg-windows-build-helpers/issues/3
		do_make_and_make_install "$compiler_flags"
		remove_path -f NUL # cygwin causes windows explorer to not be able to delete this folder if it has this oddly named file in it...
		change_dir "$src_dir"
	fi
}

build_libxavs2() {
	if [[ $host_target != 'i686-w64-mingw32' ]]; then
		change_dir "$src_dir"
		do_git_checkout https://github.com/pkuvcl/xavs2.git xavs2_git
		change_dir xavs2_git
		for file in "${PWD}/build/linux/already_configured"*; do
			if [[ -e "$file" ]]; then
				curl "https://github.com/pkuvcl/xavs2/compare/master...1480c1:xavs2:gcc14/pointerconversion.patch" | git apply -v
			fi
		done
		change_dir build/linux
		do_configure "--cross-prefix=$cross_prefix --host=$host_target --prefix=$mingw_w64_x86_64_prefix --enable-strip" # --enable-pic
		do_make_and_make_install
		change_dir "$src_dir"
	fi
}

build_libdavs2() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/pkuvcl/davs2.git
	change_dir davs2_git/build/linux
	if [[ $host_target == "i686-w64-mingw32" ]]; then
		do_configure "--cross-prefix=$cross_prefix --host=$host_target --prefix=$mingw_w64_x86_64_prefix --enable-pic --disable-asm"
	else
		do_configure "--cross-prefix=$cross_prefix --host=$host_target --prefix=$mingw_w64_x86_64_prefix --enable-pic"
	fi
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libxvid() {
	change_dir "$src_dir"
	download_and_unpack_file https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.gz xvidcore
	change_dir xvidcore/build/generic
	apply_patch "file://$WINPATCHDIR/xvidcore-1.3.7_static-lib.patch"
	do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix" # no static option...
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libvpx() {
	change_dir "$src_dir"
	do_git_checkout https://chromium.googlesource.com/webm/libvpx.git libvpx_git "origin/main"
	change_dir libvpx_git
	# apply_patch file://$WINPATCHDIR/vpx_160_semaphore.patch -p1 # perhaps someday can remove this after 1.6.0 or mingw fixes it LOL
	if [[ $compiler_flavors == "native" ]]; then
		local config_options=""
	elif [[ "$bits_target" = "32" ]]; then
		local config_options="--target=x86-win32-gcc"
	else
		local config_options="--target=x86_64-win64-gcc"
	fi
	export CROSS="$cross_prefix"
	# VP8 encoder *requires* sse3 support
	do_configure "$config_options --prefix=$mingw_w64_x86_64_prefix --enable-ssse3 --enable-static --disable-shared --disable-examples --disable-tools --disable-docs --disable-unit-tests --enable-vp9-highbitdepth --extra-cflags=-fno-asynchronous-unwind-tables --extra-cflags=-mstackrealign" # fno for Error: invalid register for .seh_savexmm
	do_make_and_make_install
	unset CROSS
	change_dir "$src_dir"
}

build_libaom() {
	change_dir "$src_dir"
	do_git_checkout https://aomedia.googlesource.com/aom aom_git
	if [[ $compiler_flavors == "native" ]]; then
		local config_options=""
	elif [ "$bits_target" = "32" ]; then
		local config_options="-DCMAKE_TOOLCHAIN_FILE=../build/cmake/toolchains/x86-mingw-gcc.cmake -DAOM_TARGET_CPU=x86"
	else
		local config_options="-DCMAKE_TOOLCHAIN_FILE=../build/cmake/toolchains/x86_64-mingw-gcc.cmake -DAOM_TARGET_CPU=x86_64"
	fi
	create_dir aom_git/aom_build
	change_dir aom_git/aom_build
	do_cmake_from_build_dir .. "$config_options"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_dav1d() {
	change_dir "$src_dir"
	do_git_checkout https://code.videolan.org/videolan/dav1d.git libdav1d
	activate_meson
	change_dir libdav1d
	if [[ $bits_target == 32 || $bits_target == 64 ]]; then # XXX why 64???
		apply_patch "file://$WINPATCHDIR/david_no_asm.patch" -p1 # XXX report
	fi
	cpu_count=1 # XXX report :|
	local meson_options="setup -Denable_tests=false -Denable_examples=false . build"
	if [[ $compiler_flavors != "native" ]]; then
		# get_local_meson_cross_with_propeties
		meson_options+=" --cross-file=${BASEDIR}/meson-cross.mingw.txt"
		do_meson "$meson_options"
	else
		generic_meson "$meson_options"
	fi
	do_ninja_and_ninja_install
	cp build/src/libdav1d.a "$mingw_w64_x86_64_prefix/lib" || exit 1 # avoid 'run ranlib' weird failure, possibly older meson's https://github.com/mesonbuild/meson/issues/4138 :|
	cpu_count=$original_cpu_count
	deactivate
	change_dir "$src_dir"
}

build_avisynth() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/AviSynth/AviSynthPlus.git avisynth_git
	create_dir avisynth_git/avisynth-build
	change_dir avisynth_git/avisynth-build
	do_cmake_from_build_dir .. -DHEADERS_ONLY:bool=on
	do_make "$compiler_flags VersionGen install"
	change_dir "$src_dir"
}

build_libvvenc() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/fraunhoferhhi/vvenc.git libvvenc_git
	change_dir libvvenc_git
	do_cmake "-B build -DCMAKE_BUILD_TYPE=Release -DVVENC_ENABLE_LINK_TIME_OPT=OFF -DVVENC_INSTALL_FULLFEATURE_APP=ON -GNinja"
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_libvvdec() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/fraunhoferhhi/vvdec.git libvvdec_git
	change_dir libvvdec_git
	do_cmake "-B build -DCMAKE_BUILD_TYPE=Release -DVVDEC_ENABLE_LINK_TIME_OPT=OFF -DVVDEC_INSTALL_VVDECAPP=ON -GNinja"
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_libx265() {
	change_dir "$src_dir"
	local checkout_dir=x265
	local remote="https://bitbucket.org/multicoreware/x265_git"
	if [[ ! -z $x265_git_checkout_version ]]; then
		checkout_dir+="_$x265_git_checkout_version"
		do_git_checkout "$remote" "$checkout_dir" "$x265_git_checkout_version"
	else
		if [[ $prefer_stable = "n" ]]; then
			checkout_dir+="_unstable"
			do_git_checkout "$remote" "$checkout_dir" "origin/master"
		fi
		if [[ $prefer_stable = "y" ]]; then
			do_git_checkout "$remote" "$checkout_dir" "origin/stable"
		fi
	fi
	change_dir "$checkout_dir"

	local cmake_params="-DENABLE_SHARED=0" # build x265.exe

	# Apply x86 noasm detection fix on newer versions
	if [[ $x265_git_checkout_version != *"3.5"* ]] && [[ $x265_git_checkout_version != *"3.4"* ]] && [[ $x265_git_checkout_version != *"3.3"* ]] && [[ $x265_git_checkout_version != *"3.2"* ]] && [[ $x265_git_checkout_version != *"3.1"* ]]; then
		git apply "$WINPATCHDIR/x265_x86_noasm_fix.patch"
	fi

	if [ "$bits_target" = "32" ]; then
		cmake_params+=" -DWINXP_SUPPORT=1" # enable windows xp/vista compatibility in x86 build, since it still can I think...
	fi
	create_dir 8bit 10bit 12bit

	# Build 12bit (main12)
	change_dir 12bit
	local cmake_12bit_params="$cmake_params -DENABLE_CLI=0 -DHIGH_BIT_DEPTH=1 -DMAIN12=1 -DEXPORT_C_API=0"
	if [ "$bits_target" = "32" ]; then
		cmake_12bit_params="$cmake_12bit_params -DENABLE_ASSEMBLY=OFF" # apparently required or build fails
	fi
	do_cmake_from_build_dir ../source "$cmake_12bit_params"
	do_make
	cp libx265.a ../8bit/libx265_main12.a

	# Build 10bit (main10)
	change_dir ../10bit
	local cmake_10bit_params="$cmake_params -DENABLE_CLI=0 -DHIGH_BIT_DEPTH=1 -DENABLE_HDR10_PLUS=1 -DEXPORT_C_API=0"
	if [ "$bits_target" = "32" ]; then
		cmake_10bit_params="$cmake_10bit_params -DENABLE_ASSEMBLY=OFF" # apparently required or build fails
	fi
	do_cmake_from_build_dir ../source "$cmake_10bit_params"
	do_make
	cp libx265.a ../8bit/libx265_main10.a

	# Build 8 bit (main) with linked 10 and 12 bit then install
	change_dir ../8bit
	cmake_params="$cmake_params -DENABLE_CLI=1 -DEXTRA_LINK_FLAGS=-L. -DLINKED_10BIT=1 -DLINKED_12BIT=1"
	if [[ $compiler_flavors == "native" && $OSTYPE != darwin* ]]; then
		cmake_params+=" -DENABLE_SHARED=0 -DEXTRA_LIB='$(pwd)/libx265_main10.a;$(pwd)/libx265_main12.a;-ldl'" # Native multi-lib CLI builds are slightly broken right now; other option is to -DENABLE_CLI=0, but this seems to work (https://bitbucket.org/multicoreware/x265/issues/520)
	else
		cmake_params+=" -DEXTRA_LIB='$(pwd)/libx265_main10.a;$(pwd)/libx265_main12.a'"
	fi
	do_cmake_from_build_dir ../source "$cmake_params"
	do_make
	mv libx265.a libx265_main.a
	if [[ $compiler_flavors == "native" && $OSTYPE == darwin* ]]; then
		libtool -static -o libx265.a libx265_main.a libx265_main10.a libx265_main12.a 2>/dev/null
	else
		"${cross_prefix}ar" -M <<EOF
CREATE libx265.a
ADDLIB libx265_main.a
ADDLIB libx265_main10.a
ADDLIB libx265_main12.a
SAVE
END
EOF
	fi
	make install # force reinstall in case you just switched from stable to not :|
	change_dir "$src_dir"
}

build_libopenh264() {
	change_dir "$src_dir"
	do_git_checkout "https://github.com/cisco/openh264.git" openh264_git v2.6.0 #75b9fcd2669c75a99791 # wels/codec_api.h weirdness
	change_dir openh264_git
	sed -i.bak "s/_M_X64/_M_DISABLED_X64/" codec/encoder/core/inc/param_svc.h # for 64 bit, avoid missing _set_FMA3_enable, it needed to link against msvcrt120 to get this or something weird?
	if [[ $bits_target == 32 ]]; then
		local arch=i686 # or x86?
	else
		local arch=x86_64
	fi
	if [[ $compiler_flavors == "native" ]]; then
		# No need for 'do_make_install', because 'install-static' already has install-instructions. we want install static so no shared built...
		do_make "$compiler_flags ASM=yasm install-static"
	else
		do_make "$compiler_flags OS=mingw_nt ARCH=$arch ASM=yasm install-static"
	fi
	change_dir "$src_dir"
}

build_libx264() {
	change_dir "$src_dir"
	local checkout_dir="x264"
	if [[ $build_x264_with_libav == "y" ]]; then
		build_ffmpeg static --disable-libx264 ffmpeg_git_pre_x264 # installs libav locally so we can use it within x264.exe FWIW...
		checkout_dir="${checkout_dir}_with_libav"
		# they don't know how to use a normal pkg-config when cross compiling, so specify some manually: (see their mailing list for a request...)
		export LAVF_LIBS="$LAVF_LIBS $(pkg-config --libs libavformat libavcodec libavutil libswscale)"
		export LAVF_CFLAGS="$LAVF_CFLAGS $(pkg-config --cflags libavformat libavcodec libavutil libswscale)"
		export SWSCALE_LIBS="$SWSCALE_LIBS $(pkg-config --libs libswscale)"
	fi

	local x264_profile_guided=n # or y -- haven't gotten this proven yet...TODO

	if [[ $prefer_stable = "n" ]]; then
		checkout_dir="${checkout_dir}_unstable"
		do_git_checkout "https://code.videolan.org/videolan/x264.git" $checkout_dir "origin/master"
	else
		do_git_checkout "https://code.videolan.org/videolan/x264.git" $checkout_dir "origin/stable"
	fi
	change_dir $checkout_dir
	if [[ ! -f configure.bak ]]; then # Change CFLAGS.
		sed -i.bak "s/O3 -/O2 -/" configure
	fi

	local configure_flags="--host=$host_target --enable-static --cross-prefix=$cross_prefix --prefix=$mingw_w64_x86_64_prefix --enable-strip" # --enable-win32thread --enable-debug is another useful option here?
	if [[ $build_x264_with_libav == "n" ]]; then
		configure_flags+=" --disable-lavf" # lavf stands for libavformat, there is no --enable-lavf option, either auto or disable...
	fi
	configure_flags+=" --bit-depth=all"
	for i in $CFLAGS; do
		configure_flags+=" --extra-cflags=$i" # needs it this way seemingly :|
	done

	if [[ $x264_profile_guided = y ]]; then
		# I wasn't able to figure out how/if this gave any speedup...
		# TODO more march=native here?
		# TODO profile guided here option, with wine?
		do_configure "$configure_flags"
		curl -4 http://samples.mplayerhq.hu/yuv4mpeg2/example.y4m.bz2 -O --fail || exit 1
		remove_path -f example.y4m # in case it exists already...
		bunzip2 example.y4m.bz2 || exit 1
		# XXX does this kill git updates? maybe a more general fix, since vid.stab does also?
		sed -i.bak "s_\\, ./x264_, wine ./x264_" Makefile     # in case they have wine auto-run disabled http://askubuntu.com/questions/344088/how-to-ensure-wine-does-not-auto-run-exe-files
		do_make_and_make_install "fprofiled VIDS=example.y4m" # guess it has its own make fprofiled, so we don't need to manually add -fprofile-generate here...
	else
		# normal path non profile guided
		do_configure "$configure_flags"
		do_make
		make install # force reinstall in case changed stable -> unstable
	fi

	unset LAVF_LIBS
	unset LAVF_CFLAGS
	unset SWSCALE_LIBS
	change_dir "$src_dir"
}

build_lsmash() { # an MP4 library
	change_dir "$src_dir"
	do_git_checkout https://github.com/l-smash/l-smash.git l-smash
	change_dir l-smash
	do_configure "--prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libdvdread() {
	build_libdvdcss
	change_dir "$src_dir"
	download_and_unpack_file http://dvdnav.mplayerhq.hu/releases/libdvdread-4.9.9.tar.xz # last revision before 5.X series so still works with MPlayer
	change_dir libdvdread-4.9.9
	# XXXX better CFLAGS here...
	generic_configure "CFLAGS=-DHAVE_DVDCSS_DVDCSS_H LDFLAGS=-ldvdcss --enable-dlfcn" # vlc patch: "--enable-libdvdcss" # XXX ask how I'm *supposed* to do this to the dvdread peeps [svn?]
	do_make_and_make_install
	sed -i.bak 's/-ldvdread.*/-ldvdread -ldvdcss/' "$PKG_CONFIG_PATH/dvdread.pc"
	change_dir "$src_dir"
}

build_libdvdnav() {
	change_dir "$src_dir"
	download_and_unpack_file http://dvdnav.mplayerhq.hu/releases/libdvdnav-4.2.1.tar.xz # 4.2.1. latest revision before 5.x series [?]
	change_dir libdvdnav-4.2.1
	if [[ ! -f ./configure ]]; then
		./autogen.sh
	fi
	generic_configure_make_install
	sed -i.bak 's/-ldvdnav.*/-ldvdnav -ldvdread -ldvdcss -lpsapi/' "$PKG_CONFIG_PATH/dvdnav.pc" # psapi for dlfcn ... [hrm?]
	change_dir "$src_dir"
}

build_libdvdcss() {
	change_dir "$src_dir"
	generic_download_and_make_and_install https://download.videolan.org/pub/videolan/libdvdcss/1.2.13/libdvdcss-1.2.13.tar.bz2
}

build_libjpeg_turbo() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/libjpeg-turbo/libjpeg-turbo libjpeg-turbo_git "origin/main"
	change_dir libjpeg-turbo_git
	local cmake_params="-DENABLE_SHARED=0 -DCMAKE_ASM_NASM_COMPILER=yasm"
	if [[ $compiler_flavors != "native" ]]; then
		cmake_params+=" -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake"
		local target_proc=AMD64
		if [ "$bits_target" = "32" ]; then
			target_proc=X86
		fi
		cat >toolchain.cmake <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR ${target_proc})
set(CMAKE_C_COMPILER ${cross_prefix}gcc)
set(CMAKE_RC_COMPILER ${cross_prefix}windres)
EOF
	fi
	do_cmake_and_install "$cmake_params"
	change_dir "$src_dir"
}

build_libproxy() {
	# NB this lacks a .pc file still
	change_dir "$src_dir"
	download_and_unpack_file https://libproxy.googlecode.com/files/libproxy-0.4.11.tar.gz
	change_dir libproxy-0.4.11
	sed -i.bak "s/= recv/= (void *) recv/" libmodman/test/main.cpp # some compile failure
	do_cmake_and_install
	change_dir "$src_dir"
}

build_lua() {
	change_dir "$src_dir"
	download_and_unpack_file https://www.lua.org/ftp/lua-5.3.3.tar.gz
	change_dir lua-5.3.3
	export AR="${cross_prefix}ar rcu"                                    # needs rcu parameter so have to call it out different :|
	do_make "CC=${cross_prefix}gcc RANLIB=${cross_prefix}ranlib generic" # generic == "generic target" and seems to result in a static build, no .exe's blah blah the mingw option doesn't even build liblua.a
	unset AR
	do_make_install "INSTALL_TOP=$mingw_w64_x86_64_prefix" "generic install"
	cp etc/lua.pc "$PKG_CONFIG_PATH"
	change_dir "$src_dir"
}

build_libhdhomerun() {
	exit 1 # still broken unfortunately, for cross compile :|
	change_dir "$src_dir"
	download_and_unpack_file https://download.silicondust.com/hdhomerun/libhdhomerun_20150826.tgz libhdhomerun
	change_dir libhdhomerun
	do_make "CROSS_COMPILE=$cross_prefix OS=Windows_NT"
	change_dir "$src_dir"
}

build_meson_cross_jsoncpp() {
	local cpu_family="x86_64"
	if [ "$bits_target" = 32 ]; then
		cpu_family="x86"
	fi
	remove_path -fv "${work_dir}/jsoncpp/meson-cross-jsoncpp.mingw.txt"
	cat >>"${work_dir}/jsoncpp/meson-cross-jsoncpp.mingw.txt" <<EOF
[built-in options]
buildtype = 'release'
wrap_mode = 'nofallback'  
default_library = 'both'
backend = 'ninja'
prefix = '$mingw_w64_x86_64_prefix'
libdir = 'lib'
includedir = 'include'

[binaries]
c = '${cross_prefix}gcc'
cpp = '${cross_prefix}g++'
ld = '${cross_prefix}ld'
ar = '${cross_prefix}ar'
strip = '${cross_prefix}strip'
nm = '${cross_prefix}nm'
windres = '${cross_prefix}windres'
dlltool = '${cross_prefix}dlltool'
pkg-config = 'pkg-config'
nasm = 'nasm'
cmake = 'cmake'

[host_machine]
system = 'windows'
cpu_family = '$cpu_family'
cpu = '$cpu_family'
endian = 'little'

[properties]
pkg_config_libdir = '$mingw_w64_x86_64_prefix/lib/pkgconfig'
EOF
}

build_libjsoncpp() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/open-source-parsers/jsoncpp jsoncpp
	change_dir jsoncpp
	if [[ "$BUILD_FORCE" -eq 1 ]]; then
		remove_path -rf already_*
	fi
	local config_options=""
	local meson_options="setup $config_options . build"
	if [[ $compiler_flavors != "native" ]]; then
		build_meson_cross_jsoncpp
		meson_options+=" --cross-file=${work_dir}/jsoncpp/meson-cross-jsoncpp.mingw.txt"
		do_meson "$meson_options"
	else
		generic_meson "$meson_options"
	fi
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_dvbtee_app() {
	build_iconv # said it needed it
	build_curl  # it "can use this" so why not
	#  build_libhdhomerun # broken but possible dependency apparently :|
	change_dir "$src_dir"
	do_git_checkout https://github.com/mkrufky/libdvbtee.git libdvbtee_git
	change_dir libdvbtee_git
	# checkout its submodule, apparently required
	if [ ! -e libdvbpsi/bootstrap ]; then
		remove_path -rf libdvbpsi # remove placeholder
		do_git_checkout https://github.com/mkrufky/libdvbpsi.git
		change_dir libdvbpsi_git
		generic_configure_make_install # library dependency submodule... TODO don't install it, just leave it local :)
		change_dir ..
	fi
	generic_configure
	do_make # not install since don't have a dependency on the library
	change_dir "$src_dir"
}

build_qt() {
	build_libjpeg_turbo # libjpeg a dependency [?]
	unset CFLAGS        # it makes something of its own first, which runs locally, so can't use a foreign arch, or maybe it can, but not important enough: http://stackoverflow.com/a/18775859/32453 XXXX could look at this
	#download_and_unpack_file http://pkgs.fedoraproject.org/repo/pkgs/qt/qt-everywhere-opensource-src-4.8.7.tar.gz/d990ee66bf7ab0c785589776f35ba6ad/qt-everywhere-opensource-src-4.8.7.tar.gz # untested
	#cd qt-everywhere-opensource-src-4.8.7
	# download_and_unpack_file http://download.qt-project.org/official_releases/qt/5.1/5.1.1/submodules/qtbase-opensource-src-5.1.1.tar.xz qtbase-opensource-src-5.1.1 # not officially supported seems...so didn't try it
	change_dir "$src_dir"
	download_and_unpack_file http://pkgs.fedoraproject.org/repo/pkgs/qt/qt-everywhere-opensource-src-4.8.5.tar.gz/1864987bdbb2f58f8ae8b350dfdbe133/qt-everywhere-opensource-src-4.8.5.tar.gz
	change_dir qt-everywhere-opensource-src-4.8.5
	apply_patch "file://$WINPATCHDIR/imageformats.patch"
	apply_patch "file://$WINPATCHDIR/qt-win64.patch"
	# vlc's configure options...mostly
	do_configure "-static -release -fast -no-exceptions -no-stl -no-sql-sqlite -no-qt3support -no-gif -no-libmng -qt-libjpeg -no-libtiff -no-qdbus -no-openssl -no-webkit -sse -no-script -no-multimedia -no-phonon -opensource -no-scripttools -no-opengl -no-script -no-scripttools -no-declarative -no-declarative-debug -opensource -no-s60 -host-little-endian -confirm-license -xplatform win32-g++ -device-option CROSS_COMPILE=$cross_prefix -prefix $mingw_w64_x86_64_prefix -prefix-install -nomake examples"
	if [ ! -f 'already_qt_maked_k' ]; then
		make sub-src -j "$(get_cpu_count)"
		make install sub-src                                                                    # let it fail, baby, it still installs a lot of good stuff before dying on mng...? huh wuh?
		cp ./plugins/imageformats/libqjpeg.a "$mingw_w64_x86_64_prefix/lib" || exit 1             # I think vlc's install is just broken to need this [?]
		cp ./plugins/accessible/libqtaccessiblewidgets.a "$mingw_w64_x86_64_prefix/lib" || exit 1 # this feels wrong...
		# do_make_and_make_install "sub-src" # sub-src might make the build faster? # complains on mng? huh?
		touch 'already_qt_maked_k'
	fi
	# vlc needs an adjust .pc file? huh wuh?
	sed -i.bak "s/Libs: -L${libdir} -lQtGui/Libs: -L${libdir} -lcomctl32 -lqjpeg -lqtaccessiblewidgets -lQtGui/" "$PKG_CONFIG_PATH/QtGui.pc" # sniff
	change_dir "$src_dir"
	reset_cflags
}

build_vlc() {
	# currently broken, since it got too old for libavcodec and I didn't want to build its own custom one yet to match, and now it's broken with gcc 5.2.0 seemingly
	# call out dependencies here since it's a lot, plus hierarchical FTW!
	# should be ffmpeg 1.1.1 or some odd?
	echo -e "not building vlc, broken dependencies or something weird"
	return
	# vlc's own dependencies:
	build_lua
	build_libdvdread
	build_libdvdnav
	build_libx265
	build_libjpeg_turbo
	build_ffmpeg
	build_qt
	change_dir "$src_dir"
	# currently vlc itself currently broken :|
	do_git_checkout https://github.com/videolan/vlc.git
	change_dir vlc_git
	#apply_patch file://$WINPATCHDIR/vlc_localtime_s.patch # git revision needs it...
	# outdated and patch doesn't apply cleanly anymore apparently...
	#if [[ "$non_free" = "y" ]]; then
	#  apply_patch https://raw.githubusercontent.com/gcsx/ffmpeg-windows-build-helpers/patch-5/patches/priorize_avcodec.patch
	#fi
	if [[ ! -f "configure" ]]; then
		./bootstrap
	fi
	export DVDREAD_LIBS='-ldvdread -ldvdcss -lpsapi'
	do_configure "--disable-libgcrypt --disable-a52 --host=$host_target --disable-lua --disable-mad --enable-qt --disable-sdl --disable-mod" # don't have lua mingw yet, etc. [vlc has --disable-sdl [?]] x265 disabled until we care enough... Looks like the bluray problem was related to the BLURAY_LIBS definition. [not sure what's wrong with libmod]
	remove_path -f "$(find . -name "*.exe")"                                                                                                     # try to force a rebuild...though there are tons of .a files we aren't rebuilding as well FWIW...:|
	remove_path -f already_ran_make*                                                                                                         # try to force re-link just in case...
	do_make
	# do some gymnastics to avoid building the mozilla plugin for now [couldn't quite get it to work]
	#sed -i.bak 's_git://git.videolan.org/npapi-vlc.git_https://github.com/rdp/npapi-vlc.git_' Makefile # this wasn't enough...following lines instead...
	sed -i.bak "s/package-win-common: package-win-install build-npapi/package-win-common: package-win-install/" Makefile
	sed -i.bak "s/.*cp .*builddir.*npapi-vlc.*//g" Makefile
	make package-win-common # not do_make, fails still at end, plus this way we get new vlc.exe's
	echo -e "


     vlc success, created a file like ${PWD}/vlc-xxx-git/vlc.exe



"
	change_dir "$src_dir"
	unset DVDREAD_LIBS
}

reset_cflags() {
	export CFLAGS=$original_cflags
}

reset_cppflags() {
	export CPPFLAGS=$original_cppflags
}

reset_ldflags() {
	export LDFLAGS=$original_ldflags
}

build_meson_cross() {
	local cpu_family="x86_64"
	if [ "$bits_target" = 32 ]; then
		cpu_family="x86"
	fi
	remove_path -fv meson-cross.mingw.txt
	cat >>meson-cross.mingw.txt <<EOF
[built-in options]
buildtype = 'release'
wrap_mode = 'nofallback'  
default_library = 'static'  
prefer_static = 'true'
default_both_libraries = 'static'
backend = 'ninja'
prefix = '$mingw_w64_x86_64_prefix'
libdir = '$mingw_w64_x86_64_prefix/lib'
 
[binaries]
c = '${cross_prefix}gcc'
cpp = '${cross_prefix}g++'
ld = '${cross_prefix}ld'
ar = '${cross_prefix}ar'
strip = '${cross_prefix}strip'
nm = '${cross_prefix}nm'
windres = '${cross_prefix}windres'
dlltool = '${cross_prefix}dlltool'
pkg-config = 'pkg-config'
nasm = 'nasm'
cmake = 'cmake'

[host_machine]
system = 'windows'
cpu_family = '$cpu_family'
cpu = '$cpu_family'
endian = 'little'

[properties]
pkg_config_sysroot_dir = '$mingw_w64_x86_64_prefix'
pkg_config_libdir = '$pkg_config_sysroot_dir/lib/pkgconfig'
EOF
	mv -v meson-cross.mingw.txt ../..
}

get_local_meson_cross_with_propeties() {
	local local_dir="$1"
	if [[ -z $local_dir ]]; then
		local_dir="."
	fi
	cp "$BASEDIR/meson-cross.mingw.txt" "$local_dir"
	cat >>meson-cross.mingw.txt <<EOF
EOF
}

build_mplayer() {
	# pre requisites
	build_libjpeg_turbo
	build_libdvdread
	build_libdvdnav

	download_and_unpack_file https://sourceforge.net/projects/mplayer-edl/files/mplayer-export-snapshot.2014-05-19.tar.bz2 mplayer-export-2014-05-19
	change_dir mplayer-export-2014-05-19
	do_git_checkout https://github.com/FFmpeg/FFmpeg ffmpeg d43c303038e9bd # known compatible commit
	export LDFLAGS='-lpthread -ldvdnav -ldvdread -ldvdcss'                 # not compat with newer dvdread possibly? huh wuh?
	export CFLAGS=-DHAVE_DVDCSS_DVDCSS_H
	do_configure "--enable-cross-compile --host-cc=cc --cc=${cross_prefix}gcc --windres=${cross_prefix}windres --ranlib=${cross_prefix}ranlib --ar=${cross_prefix}ar --as=${cross_prefix}as --nm=${cross_prefix}nm --enable-runtime-cpudetection --extra-cflags=$CFLAGS --with-dvdnav-config=$mingw_w64_x86_64_prefix/bin/dvdnav-config --disable-dvdread-internal --disable-libdvdcss-internal --disable-w32threads --enable-pthreads --extra-libs=-lpthread --enable-debug --enable-ass-internal --enable-dvdread --enable-dvdnav --disable-libvpx-lavc" # haven't reported the ldvdcss thing, think it's to do with possibly it not using dvdread.pc [?] XXX check with trunk
	# disable libvpx didn't work with its v1.5.0 some reason :|
	unset LDFLAGS
	reset_cflags
	sed -i.bak "s/HAVE_PTHREAD_CANCEL 0/HAVE_PTHREAD_CANCEL 1/g" config.h # mplayer doesn't set this up right?
	touch -t 201203101513 config.h                                        # the above line change the modify time for config.h--forcing a full rebuild *every time* yikes!
	# try to force re-link just in case...
	remove_path -f "*.exe"
	remove_path -f already_ran_make* # try to force re-link just in case...
	do_make
	cp mplayer.exe mplayer_debug.exe
	"${cross_prefix}strip" mplayer.exe
	echo -e "built ${PWD}/{mplayer,mencoder,mplayer_debug}.exe"
	change_dir "$src_dir"
}

build_mp4box() { # like build_gpac
	# This script only builds the gpac_static lib plus MP4Box. Other tools inside
	# specify revision until this works: https://sourceforge.net/p/gpac/discussion/287546/thread/72cf332a/
	do_git_checkout https://github.com/gpac/gpac.git mp4box_gpac_git
	change_dir mp4box_gpac_git
	# are these tweaks needed? If so then complain to the mp4box people about it?
	sed -i.bak "s/has_dvb4linux=\"yes\"/has_dvb4linux=\"no\"/g" configure
	# XXX do I want to disable more things here?
	# ./prebuilt/cross_compilers/mingw-w64-i686/bin/i686-w64-mingw32-sdl-config
	generic_configure "  --cross-prefix=${cross_prefix} --target-os=MINGW32 --extra-cflags=-Wno-format --static-build --static-bin --disable-oss-audio --extra-ldflags=-municode --disable-x11 --sdl-cfg=${cross_prefix}sdl-config"
	./check_revision.sh
	# I seem unable to pass 3 libs into the same config line so do it with sed...
	sed -i.bak "s/EXTRALIBS=.*/EXTRALIBS=-lws2_32 -lwinmm -lz/g" config.mak
	change_dir src
	do_make "$compiler_flags"
	change_dir ..
	remove_path -f ./bin/gcc/MP4Box* # try and force a relink/rebuild of the .exe
	change_dir applications/mp4box
	remove_path -f already_ran_make* # ??
	do_make "$compiler_flags"
	change_dir ../..
	# copy it every time just in case it was rebuilt...
	cp ./bin/gcc/MP4Box ./bin/gcc/MP4Box.exe # it doesn't name it .exe? That feels broken somehow...
	echo -e "built $(readlink -f ./bin/gcc/MP4Box.exe)"
	change_dir "$src_dir"
}

build_libMXF() {
	download_and_unpack_file https://sourceforge.net/projects/ingex/files/1.0.0/libMXF/libMXF-src-1.0.0.tgz "libMXF-src-1.0.0"
	change_dir libMXF-src-1.0.0
	apply_patch "file://$WINPATCHDIR/libMXF.diff"
	do_make "MINGW_CC_PREFIX=$cross_prefix"
	#
	# Manual equivalent of make install. Enable it if desired. We shouldn't need it in theory since we never use libMXF.a file and can just hand pluck out the *.exe files already...
	#
	#cp libMXF/lib/libMXF.a $mingw_w64_x86_64_prefix/lib/libMXF.a
	#cp libMXF++/libMXF++/libMXF++.a $mingw_w64_x86_64_prefix/lib/libMXF++.a
	#mv libMXF/examples/writeaviddv50/writeaviddv50 libMXF/examples/writeaviddv50/writeaviddv50.exe
	#mv libMXF/examples/writeavidmxf/writeavidmxf libMXF/examples/writeavidmxf/writeavidmxf.exe
	#cp libMXF/examples/writeaviddv50/writeaviddv50.exe $mingw_w64_x86_64_prefix/bin/writeaviddv50.exe
	#cp libMXF/examples/writeavidmxf/writeavidmxf.exe $mingw_w64_x86_64_prefix/bin/writeavidmxf.exe
	change_dir "$src_dir"
}

build_lsw() {
	# Build L-Smash-Works, which are AviSynth plugins based on lsmash/ffmpeg
	#build_ffmpeg static # dependency, assume already built since it builds before this does...
	build_lsmash # dependency
	do_git_checkout https://github.com/VFR-maniac/L-SMASH-Works.git lsw
	change_dir lsw/VapourSynth
	do_configure "--prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix --target-os=mingw"
	do_make_and_make_install
	# AviUtl is 32bit-only
	if [ "$bits_target" = "32" ]; then
		change_dir ../AviUtl
		do_configure "--prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix"
		do_make
	fi
	change_dir "$src_dir"
}

build_chromaprint() {
	echo -e "$mingw_w64_x86_64_prefix"
	build_fftw
	do_git_checkout https://github.com/acoustid/chromaprint.git chromaprint
	change_dir chromaprint
	cat >toolchain.cmake <<EOF
set(CMAKE_SYSTEM_NAME Windows)  
set(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc)  
set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++)  
set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres)  
set(CMAKE_FIND_ROOT_PATH $mingw_w64_x86_64_prefix)  
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)  
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)  
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)  
set(CMAKE_C_IMPLICIT_INCLUDE_DIRECTORIES "")  
set(CMAKE_CXX_IMPLICIT_INCLUDE_DIRECTORIES "")
set(CMAKE_C_FLAGS "-static -static-libgcc -static-libstdc++")  
set(CMAKE_CXX_FLAGS "-static -static-libgcc -static-libstdc++")
EOF
	do_cmake_and_install "-DCMAKE_BUILD_TYPE=Release -DBUILD_TOOLS=OFF -DBUILD_TESTS=OFF -DFFT_LIB=fftw3 -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake"
	change_dir ..
}

find_all_build_exes() {
	local found=""
	# NB that we're currently in the prebuilt dir...
	for file in $(find . -name ffmpeg.exe) $(find . -name ffmpeg_g.exe) $(find . -name ffplay.exe) $(find . -name ffmpeg) $(find . -name ffplay) $(find . -name ffprobe) $(find . -name MP4Box.exe) $(find . -name mplayer.exe) $(find . -name mencoder.exe) $(find . -name avconv.exe) $(find . -name avprobe.exe) $(find . -name x264.exe) $(find . -name writeavidmxf.exe) $(find . -name writeaviddv50.exe) $(find . -name rtmpdump.exe) $(find . -name x265.exe) $(find . -name ismindex.exe) $(find . -name dvbtee.exe) $(find . -name boxdumper.exe) $(find . -name muxer.exe) $(find . -name remuxer.exe) $(find . -name timelineeditor.exe) $(find . -name lwcolor.auc) $(find . -name lwdumper.auf) $(find . -name lwinput.aui) $(find . -name lwmuxer.auf) $(find . -name vslsmashsource.dll); do
		found="$found $(readlink -f "$file")"
	done

	# bash recursive glob fails here again?
	for file in $(find . -name vlc.exe | grep -- -); do
		found="$found $(readlink -f "$file")"
	done
	echo -e "$found" # pseudo return value...
}

check_audiotoolbox() {
	# if [[ "$non_free" = "y" ]]; then
	#   build_fdk-aac # Uses dlfcn.
	# if [[ $OSTYPE != darwin* ]]; then
	#     build_AudioToolboxWrapper # This wrapper library enables FFmpeg to use AudioToolbox codecs on Windows, with DLLs shipped with iTunes.
	# fi
	if [[ $compiler_flavors != "native" ]]; then
		build_libdecklink # Error finding rpc.h in native builds even if it's available
	fi
	#fi
}

build_all_ffmpeg_dependencies() {
	echo -e "INFO: Building dependencies..."
	# Create a clean array without empty elements
	local steps=${#BUILD_STEPS[@]}
	local current_step=0

	for step_name in "${BUILD_STEPS[@]}"; do
		change_dir "$src_dir"
		if [[ -z "${step_name// /}" ]]; then
			continue
		fi
		((current_step++))
		percent=$((current_step * 100 / steps))
		bars=$((percent * 40 / 100))

		bar_str=""
		for ((j = 0; j < bars; j++)); do bar_str="${bar_str}█"; done
		for ((j = bars; j < 40; j++)); do bar_str="${bar_str} "; done

		printf "\r\033[K[%s] %3d%% (%2d/%2d) | %s" "$bar_str" "$percent" "$current_step" "$steps" "$step_name"

		build_ffmpeg_dependency_only "$step_name" 1>>"$LOG_FILE" 2>&1
	done
	printf "\r\033[KAll dependencies built successfully!\n"
}

build_ffmpeg_dependency_only() {
	step=$1
	if [[ -n "$step" ]]; then
		change_dir "$src_dir"
		if declare -F "$step" >/dev/null; then
			echo -e "Executing step: $step"
			"$step" # Execute the function
		else
			echo -e "Error: Function '$step' not found."
			return 1 # Indicate an error
		fi
	else
		echo -e "Error: Step argument is missing."
		return 1 # Indicate an error
	fi
}

build_apps() {
	if [[ $build_dvbtee = "y" ]]; then
		build_dvbtee_app
	fi
	# now the things that use the dependencies...
	if [[ $build_libmxf = "y" ]]; then
		build_libMXF
	fi
	if [[ $build_mp4box = "y" ]]; then
		build_mp4box
	fi
	if [[ $build_mplayer = "y" ]]; then
		build_mplayer
	fi
	if [[ $build_ffmpeg_static = "y" ]]; then
		build_ffmpeg static
	fi
	if [[ $build_ffmpeg_shared = "y" ]]; then
		build_ffmpeg shared
	fi
	if [[ $build_vlc = "y" ]]; then
		build_vlc
	fi
	if [[ $build_lsw = "y" ]]; then
		build_lsw
	fi
}

# This new function centralizes the setup for each build target.
setup_build_environment() {
	local flavor="$1"
	echo -e
	echo -e "************** Setting up environment for $flavor build... **************"
	if [[ $flavor == "win32" ]]; then
		export ARCH=$(get_arch_name "$(from_arch_name "$flavor")")
		export FULL_ARCH="i686"
		export target_name="$FFMPEG_KIT_BUILD_TYPE-$FULL_ARCH"
		export work_dir="$(realpath "$WORKDIR"/"$target_name")"
		export host_target='i686-w64-mingw32'
		export mingw_w64_x86_64_prefix="$(realpath "$work_dir"/cross_compilers/mingw-w64-i686/$host_target)"
		export mingw_bin_path="$(realpath "$work_dir"/cross_compilers/mingw-w64-i686/bin)"
		export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
		export PATH="$mingw_bin_path:$original_path"
		export bits_target=32
		export cross_prefix="$mingw_bin_path/i686-w64-mingw32-"
		export compiler_flags="CC=${cross_prefix}gcc AR=${cross_prefix}ar PREFIX=$mingw_w64_x86_64_prefix RANLIB=${cross_prefix}ranlib LD=${cross_prefix}ld STRIP=${cross_prefix}strip CXX=${cross_prefix}g++"
	elif [[ $flavor == "win64" ]]; then
		export ARCH=$(get_arch_name "$(from_arch_name "$flavor")")
		export FULL_ARCH="x86_64"
		export work_dir="$(realpath "$WORKDIR"/"$target_name")"
		export host_target='x86_64-w64-mingw32'
		export mingw_w64_x86_64_prefix="$(realpath "$work_dir"/cross_compilers/mingw-w64-x86_64/$host_target)"
		export mingw_bin_path="$(realpath "$work_dir"/cross_compilers/mingw-w64-x86_64/bin)"
		export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
		export PATH="$mingw_bin_path:$original_path"
		export bits_target=64
		export cross_prefix="$mingw_bin_path/x86_64-w64-mingw32-"
		export compiler_flags="CC=${cross_prefix}gcc AR=${cross_prefix}ar PREFIX=$mingw_w64_x86_64_prefix RANLIB=${cross_prefix}ranlib LD=${cross_prefix}ld STRIP=${cross_prefix}strip CXX=${cross_prefix}g++"
		export LIB_INSTALL_BASE=$work_dir
	else
		echo -e "Error: Unknown compiler flavor '$flavor'"
		exit 1
	fi
	export make_prefix_options="--cc=${cross_prefix}gcc \
--ar=$(realpath "${cross_prefix}"ar) \
--as=$(realpath "${cross_prefix}"as) \
--nm=$(realpath "${cross_prefix}"nm) \
--ranlib=$(realpath "${cross_prefix}"ranlib) \
--ld=$(realpath "${cross_prefix}"ld) \
--strip=$(realpath "${cross_prefix}"strip) \
--cxx=$(realpath "${cross_prefix}"g++)"
	export src_dir="${work_dir}/$target_name/src"
	export LIB_INSTALL_BASE="$work_dir"
	export INSTALL_PKG_CONFIG_DIR="${work_dir}/pkgconfig"
	export ffmpeg_source_dir="${work_dir}/ffmpeg"
	export install_prefix="$ffmpeg_source_dir/build_$(get_build_type)" # install them to their a separate dir
	export ffmpeg_kit_install="${work_dir}/ffmpeg-kit_$(get_build_type)"
	export ffmpeg_kit_bundle="${work_dir}/$(get_bundle_directory)"
	create_dir "$work_dir"
	change_dir "$work_dir" || exit
}

get_arch_specific_ldflags() {
	case ${ARCH} in
	x86-64)
		echo -e "-march=x86-64 -Wl,-z,text"
		;;
	esac
}

get_size_optimization_ldflags() {
	if [[ -z ${NO_LINK_TIME_OPTIMIZATION} ]]; then
		local LINK_TIME_OPTIMIZATION_FLAGS="-flto"
	else
		local LINK_TIME_OPTIMIZATION_FLAGS=""
	fi

	case ${ARCH} in
	x86-64)
		case $1 in
		ffmpeg)
			echo -e "${LINK_TIME_OPTIMIZATION_FLAGS} -O2 -ffunction-sections -fdata-sections -finline-functions"
			;;
		*)
			echo -e "-Os -ffunction-sections -fdata-sections"
			;;
		esac
		;;
	esac
}

get_common_linked_libraries() {
	local COMMON_LIBRARIES=""

	case $1 in
	chromaprint | ffmpeg-kit | kvazaar | srt | zimg)
		echo -e "-stdlib=libstdc++ -lstdc++ -lc -lm ${COMMON_LIBRARIES}"
		;;
	*)
		echo -e "-lc -lm -ldl ${COMMON_LIBRARIES}"
		;;
	esac
}

get_ldflags() {
	local ARCH_FLAGS=$(get_arch_specific_ldflags)
	if [[ -z ${FFMPEG_KIT_DEBUG} ]]; then
		local OPTIMIZATION_FLAGS="$(get_size_optimization_ldflags "$1")"
	else
		local OPTIMIZATION_FLAGS="${FFMPEG_KIT_DEBUG}"
	fi
	local COMMON_LINKED_LIBS=$(get_common_linked_libraries "$1")

	echo -e "${ARCH_FLAGS} ${OPTIMIZATION_FLAGS} ${COMMON_LINKED_LIBS} ${LLVM_CONFIG_LDFLAGS} -Wl,--hash-style=both -fuse-ld=lld"
}

get_cxxflags() {
	if [[ -z ${NO_LINK_TIME_OPTIMIZATION} ]]; then
		local LINK_TIME_OPTIMIZATION_FLAGS="-flto"
	else
		local LINK_TIME_OPTIMIZATION_FLAGS=""
	fi

	if [[ -z ${FFMPEG_KIT_DEBUG} ]]; then
		local OPTIMIZATION_FLAGS="-Os -ffunction-sections -fdata-sections"
	else
		local OPTIMIZATION_FLAGS="${FFMPEG_KIT_DEBUG}"
	fi

	local BUILD_DATE="-DFFMPEG_KIT_BUILD_DATE=$(date +%Y%m%d 2>>"$LOG_FILE")"
	local COMMON_FLAGS="-stdlib=libstdc++ -std=c++11 ${OPTIMIZATION_FLAGS} ${BUILD_DATE} $(get_arch_specific_cflags)"

	case $1 in
	ffmpeg)
		if [[ -z ${FFMPEG_KIT_DEBUG} ]]; then
			echo -e "${LINK_TIME_OPTIMIZATION_FLAGS} -stdlib=libstdc++ -std=c++11 -O2 -ffunction-sections -fdata-sections"
		else
			echo -e "${FFMPEG_KIT_DEBUG} -stdlib=libstdc++ -std=c++11"
		fi
		;;
	ffmpeg-kit)
		echo -e "${COMMON_FLAGS}"
		;;
	srt | tesseract | zimg)
		echo -e "${COMMON_FLAGS} -fcxx-exceptions -fPIC"
		;;
	*)
		echo -e "${COMMON_FLAGS} -fno-exceptions -fno-rtti"
		;;
	esac
}

get_common_includes() {
	echo -e "-I${LLVM_CONFIG_INCLUDEDIR:-.}"
}

get_size_optimization_cflags() {
	if [[ -z ${NO_LINK_TIME_OPTIMIZATION} ]]; then
		local LINK_TIME_OPTIMIZATION_FLAGS="-flto"
	else
		local LINK_TIME_OPTIMIZATION_FLAGS=""
	fi

	local ARCH_OPTIMIZATION=""
	case ${ARCH} in
	x86-64 | x86_64)
		case $1 in
		ffmpeg)
			ARCH_OPTIMIZATION="${LINK_TIME_OPTIMIZATION_FLAGS} -Os -ffunction-sections -fdata-sections"
			;;
		*)
			ARCH_OPTIMIZATION="-Os -ffunction-sections -fdata-sections"
			;;
		esac
		;;
	esac

	local LIB_OPTIMIZATION=""

	echo -e "${ARCH_OPTIMIZATION} ${LIB_OPTIMIZATION}"
}

get_common_cflags() {
	if [[ -n ${FFMPEG_KIT_LTS_BUILD} ]]; then
		local LTS_BUILD_FLAG="-DFFMPEG_KIT_LTS "
	fi

	echo -e "-fstrict-aliasing -fPIC -DWINDOWS ${LTS_BUILD_FLAG} ${LLVM_CONFIG_CFLAGS}"
}

get_app_specific_cflags() {
	local APP_FLAGS=""
	case $1 in
	ffmpeg)
		APP_FLAGS="-Wno-unused-function"
		;;
	ffmpeg-kit)
		APP_FLAGS="-Wno-unused-function -Wno-pointer-sign -Wno-switch -Wno-deprecated-declarations"
		;;
	kvazaar)
		APP_FLAGS="-std=gnu99 -Wno-unused-function"
		;;
	openh264)
		APP_FLAGS="-std=gnu99 -Wno-unused-function -fstack-protector-all"
		;;
	srt)
		APP_FLAGS="-Wno-unused-function"
		;;
	*)
		APP_FLAGS="-std=c99 -Wno-unused-function"
		;;
	esac

	echo -e "${APP_FLAGS}"
}

get_arch_specific_cflags() {
	case ${ARCH} in
	x86-64 | x86_64)
		echo -e "-target $(get_target) -DFFMPEG_KIT_X86_64"
		;;
	esac
}

get_cflags() {
	local ARCH_FLAGS=$(get_arch_specific_cflags)
	local APP_FLAGS=$(get_app_specific_cflags "$1")
	local COMMON_FLAGS=$(get_common_cflags)
	if [[ -z ${FFMPEG_KIT_DEBUG} ]]; then
		local OPTIMIZATION_FLAGS=$(get_size_optimization_cflags "$1")
	else
		local OPTIMIZATION_FLAGS="${FFMPEG_KIT_DEBUG}"
	fi
	local COMMON_INCLUDES=$(get_common_includes)

	echo -e "${ARCH_FLAGS} ${APP_FLAGS} ${COMMON_FLAGS} ${OPTIMIZATION_FLAGS} ${COMMON_INCLUDES}"
}

get_target_cpu() {
	case ${ARCH} in
	i686 | x86 | win32)
		echo -e "i686"
		;;
	x86-64 | x86_64 | win64)
		echo -e "x86_64"
		;;
	esac
}

get_build_directory() {
	local LTS_POSTFIX=""
	if [[ -n ${FFMPEG_KIT_LTS_BUILD} ]]; then
		LTS_POSTFIX="-lts"
	fi

	echo -e "windows-$(get_target_cpu)${LTS_POSTFIX}"
}

detect_clang_version() {
	if [[ -n ${FFMPEG_KIT_LTS_BUILD} ]]; then
		for clang_version in 6 .. 10; do
			if [[ $(command_exists "clang-$clang_version") -eq 0 ]]; then
				echo -e "$clang_version"
				return
			elif [[ $(command_exists "clang-$clang_version.0") -eq 0 ]]; then
				echo -e "$clang_version.0"
				return
			fi
		done
		echo -e "none"
	else
		for clang_version in 11 .. 20; do
			if [[ $(command_exists "clang-$clang_version") -eq 0 ]]; then
				echo -e "$clang_version"
				return
			elif [[ $(command_exists "clang-$clang_version.0") -eq 0 ]]; then
				echo -e "$clang_version.0"
				return
			fi
		done
		echo -e "none"
	fi
}

set_toolchain_paths() {
	export PATH="${PATH}:${mingw_bin_path}:${mingw_w64_x86_64_prefix}/bin"
	export CC="${cross_prefix}gcc"
	export AR="$(realpath "${cross_prefix}ar")"
	export AS="$(realpath "${cross_prefix}as")"
	export NM="$(realpath "${cross_prefix}nm")"
	export RANLIB="$(realpath "${cross_prefix}ranlib")"
	export LD="$(realpath "${cross_prefix}ld")"
	export STRIP="$(realpath "${cross_prefix}strip")"
	export CXX="$(realpath "${cross_prefix}g++")"
}

enable_lts_build() {
	export FFMPEG_KIT_LTS_BUILD="1"
}

install_pkg_config_file() {
	local FILE_NAME="$1"
	local SOURCE="${INSTALL_PKG_CONFIG_DIR}/${FILE_NAME}"
	local DESTINATION="${FFMPEG_KIT_BUNDLE_PKG_CONFIG_DIRECTORY}/${FILE_NAME}"

	# DELETE OLD FILE
	if ! remove_path -rf "$DESTINATION" 2>>"$LOG_FILE"; then
			echo -e "failed\n\nSee $LOG_FILE for details\n"
			exit 1
	fi

	# INSTALL THE NEW FILE
	if ! copy_path "$SOURCE" "$DESTINATION" 2>>"$LOG_FILE"; then
			echo -e "failed\n\nSee $LOG_FILE for details\n"
			exit 1
	fi

	prepare_inline_sed
	# UPDATE PATHS
	${SED_INLINE} "s|${ffmpeg_kit_install}|${ffmpeg_kit_bundle}|g" "$DESTINATION" 1>>"$LOG_FILE" 2>&1 || return 1
	${SED_INLINE} "s|${ffmpeg_source_dir}|${ffmpeg_kit_bundle}|g" "$DESTINATION" 1>>"$LOG_FILE" 2>&1 || return 1
}

get_ffmpeg_kit_version() {
	local FFMPEG_KIT_VERSION=$(grep -Eo 'FFmpegKitVersion = .*' "${BASEDIR}/windows/src/FFmpegKitConfig.h" 2>>"$LOG_FILE" | grep -Eo ' \".*' | tr -d '"; ')

	echo -e "${FFMPEG_KIT_VERSION}"
}

build_ffmpeg_kit() {
	echo -e "INFO: Building ffmpeg kit\n" 1>>"$LOG_FILE" 2>&1
	# BUILD FFMPEG KIT

	echo -e "INFO: Done building ffmpeg kit\n" 1>>"$LOG_FILE" 2>&1
}

download_ffmpeg() {
	local output_dir="$work_dir/ffmpeg"
	local desired_version="$ffmpeg_git_checkout_version"

	if [[ -z $desired_version ]]; then
		desired_version="master"
	fi

	do_git_checkout "$ffmpeg_git_checkout" "$output_dir" "$desired_version" || exit 1
	ffmpeg_source_dir=$output_dir
}

install_cross_compiler() {
	echo -e "INFO: Building (or already built) MinGW-w64 cross-compiler(s)..." | tee -a "$LOG_FILE"
	echo -e "$(date)" | tee -a "$LOG_FILE"
	local win32_gcc="$work_dir/cross_compilers/mingw-w64-i686/bin/i686-w64-mingw32-gcc"
	local win64_gcc="$work_dir/cross_compilers/mingw-w64-x86_64/bin/x86_64-w64-mingw32-gcc"
	if [[ -f $win32_gcc && -f $win64_gcc ]]; then
		echo -e "MinGW-w64 compilers both already installed, not re-installing..." | tee -a "$LOG_FILE"
		if [[ -z $compiler_flavors ]]; then
			echo -e "selecting multi build (both win32 and win64)...since both cross compilers are present assuming you want both..." 1>>"$LOG_FILE"2 >&1
			compiler_flavors=multi
		fi
		return # early exit they've selected at least some kind by this point...
	fi

	if [[ -z $compiler_flavors ]]; then
		pick_compiler_flavors
	fi
	setup_build_environment "$compiler_flavors"
	create_dir "$work_dir"/cross_compilers
	change_dir "$work_dir"/cross_compilers

	unset CFLAGS # don't want these "windows target" settings used the compiler itself since it creates executables to run on the local box (we have a parameter allowing them to set them for the script "all builds" basically)
	# pthreads version to avoid having to use cvs for it
	echo -e "Starting to download and build cross compile version of gcc [requires working internet access] with thread count $gcc_cpu_count..." 1>>"$LOG_FILE"2 >&1
	echo -e "" 1>>"$LOG_FILE"2 >&1

	# --disable-shared allows c++ to be distributed at all...which seemed necessary for some random dependency which happens to use/require c++...
	local zeranoe_script_name=mingw-w64-build
	local zeranoe_script_options="--gcc-branch=releases/gcc-14 --mingw-w64-branch=master --binutils-branch=binutils-2_44-branch" # --cached-sources"
	if [[ ($compiler_flavors == "win32" || $compiler_flavors == "multi") && ! -f ../$win32_gcc ]]; then
		echo -e "Building win32 cross compiler..." 1>>"$LOG_FILE"2 >&1
		download_gcc_build_script $zeranoe_script_name
		if [[ "$(uname)" =~ (5.1) ]]; then # Avoid using secure API functions for compatibility with msvcrt.dll on Windows XP.
			sed -i "s/ --enable-secure-api//" $zeranoe_script_name
		fi
		# shellcheck disable=SC2086
		CFLAGS='-O2 -pipe' CXXFLAGS='-O2 -pipe' nice ./$zeranoe_script_name $zeranoe_script_options i686 || exit 1 # i586 option needs work to implement
		if [[ ! -f ../$win32_gcc ]]; then
			echo -e "Failure building 32 bit gcc? Recommend nuke prebuilt (rm -rf prebuilt) and start over..." 1>>"$LOG_FILE"2 >&1
			exit 1
		fi
		if [[ ! -f ../cross_compilers/mingw-w64-i686/i686-w64-mingw32/lib/libmingwex.a ]]; then
			echo -e "failure building mingwex? 32 bit" 1>>"$LOG_FILE"2 >&1
			exit 1
		fi
	fi
	if [[ ($compiler_flavors == "win64" || $compiler_flavors == "multi") && ! -f ../$win64_gcc ]]; then
		echo -e "Building win64 x86_64 cross compiler..." 1>>"$LOG_FILE"2 >&1
		download_gcc_build_script $zeranoe_script_name
		# shellcheck disable=SC2086
		CFLAGS='-O3 -pipe' CXXFLAGS='-O3 -pipe' nice ./$zeranoe_script_name $zeranoe_script_options x86_64 || exit 1
		if [[ ! -f ../$win64_gcc ]]; then
			echo -e "Failure building 64 bit gcc? Recommend nuke prebuilt (rm -rf prebuilt) and start over..." 1>>"$LOG_FILE"2 >&1
			exit 1
		fi
		if [[ ! -f ../cross_compilers/mingw-w64-x86_64/x86_64-w64-mingw32/lib/libmingwex.a ]]; then
			echo -e "failure building mingwex? 64 bit" 1>>"$LOG_FILE"2 >&1
			exit 1
		fi
	fi

	# rm -f build.log # leave resultant build log...sometimes useful...
	reset_cflags
	change_dir ..
	echo -e "INFO: Done building (or already built) MinGW-w64 cross-compiler(s) successfully..." | tee -a "$LOG_FILE"
	echo -e "$(date)" | tee -a "$LOG_FILE" # so they can see how long it took :)
}

check_builds() {
	shared_build_exists=0
	static_build_exists=0

	# Check shared build
	echo -e "DEBUG: Checking $ffmpeg_source_dir/build_$(get_build_type)"
	if [[ -d "${ffmpeg_source_dir}/build_$(get_build_type)" && -d "${ffmpeg_source_dir}/build_$(get_build_type)/bin" ]]; then
		echo -e "DEBUG: Checking binaries in $ffmpeg_source_dir/build_$(get_build_type)/bin"
		check_binaries=0
		if find "${ffmpeg_source_dir}/build_$(get_build_type)/bin" -maxdepth 1 -type f \( -name '*.a' -o -name '*.dll' -o -name '*.so' -o -name '*.dylib' -o -name '*.lib' -o -name '*.exe' \) -print -quit | grep -q .; then
			check_binaries=1
		fi
		[[ $check_binaries -eq 1 ]] && shared_build_exists=1
	fi
	echo -e "DEBUG: Checking $ffmpeg_source_dir/build_$(get_build_type)"
	# Check static build
	if [[ -d "${ffmpeg_source_dir}/build_$(get_build_type)" && -d "${ffmpeg_source_dir}/build_$(get_build_type)/bin" ]]; then
		echo -e "DEBUG: Checking binaries in $ffmpeg_source_dir/build_$(get_build_type)/bin"
		check_binaries=0
		if find "${ffmpeg_source_dir}/build_$(get_build_type)/bin" -maxdepth 1 -type f \( -name '*.a' -o -name '*.dll' -o -name '*.so' -o -name '*.dylib' -o -name '*.lib' -o -name '*.exe' \) -print -quit | grep -q .; then
			check_binaries=1
		fi
		[[ $check_binaries -eq 1 ]] && static_build_exists=1
	fi

	echo -e "INFO: Checking if build already exists..." | tee -a "$LOG_FILE"

	if [[ ${build_ffmpeg_static,,} =~ ^(y|yes|1|true|on)$ ]]; then
		echo -e "INFO: Static build requested..." | tee -a "$LOG_FILE"
		if [[ $static_build_exists == 0 || "$BUILD_FORCE" -eq 1 ]]; then
			echo -e "INFO: Static build does not exist or force requested. (Re-)configuring Ffmpeg for static build." | tee -a "$LOG_FILE"
			# shellcheck disable=SC2129
			remove_path -rf "${ffmpeg_source_dir}/build_$(get_build_type)" 1>>"$LOG_FILE"2 >&1
			remove_path -f "${ffmpeg_source_dir}/already_*" 1>>"$LOG_FILE"2 >&1
			configure_ffmpeg 1>>"$LOG_FILE"2 >&1
		fi
	elif [[ ${build_ffmpeg_shared,,} =~ ^(y|yes|1|true|on)$ ]]; then
		echo -e "INFO: Shared build requested..." | tee -a "$LOG_FILE"
		if [[ $shared_build_exists == 0 || "$BUILD_FORCE" -eq 1 ]]; then
			echo -e "INFO: Shared build does not exist or force requested. (Re-)configuring Ffmpeg for shared build." | tee -a "$LOG_FILE"
			# shellcheck disable=SC2129
			remove_path -rf "${ffmpeg_source_dir}/build_$(get_build_type)" 1>>"$LOG_FILE"2 >&1
			remove_path -f "${ffmpeg_source_dir}/already_*" 1>>"$LOG_FILE"2 >&1
			configure_ffmpeg 1>>"$LOG_FILE"2 >&1
		fi
	fi
}

install_ffmpeg() {
	check_builds
	echo -e "INFO: Installing ffmpeg if not installed\n" | tee -a "$LOG_FILE"
	change_dir "$ffmpeg_source_dir"

	echo -e "INFO: Making Ffmpeg $(pwd)" | tee -a "$LOG_FILE"

	create_dir "$install_prefix"

	do_make_and_make_install "" "" "$(get_build_type)" 1>>"$LOG_FILE"2 >&1

	echo -e "INFO: Moving all binaries" | tee -a "$LOG_FILE"

	{
		mv "*/*.a" "${install_prefix}/bin" 
		mv "*/*.dylib" "${install_prefix}/bin"
		mv "*/*.lib" "${install_prefix}/bin"
		mv "*/*.dll" "${install_prefix}/bin"
		mv "*.exe" "${install_prefix}/bin"
		mv "*.so" "${install_prefix}/bin"
	} 1>>"$LOG_FILE"2 >&1

	echo -e "INFO: Done installing ffmpeg\n" | tee -a "$LOG_FILE"

	install_ffmpeg_pkg
}

install_ffmpeg_pkg() {
	echo -e "INFO: Checking deployment files...\n" | tee -a "$LOG_FILE"

	required_files=(
		"${install_prefix}/lib/pkgconfig/libavformat.pc"
		"${install_prefix}/lib/pkgconfig/libswresample.pc"
		"${install_prefix}/lib/pkgconfig/libswscale.pc"
		"${install_prefix}/lib/pkgconfig/libavdevice.pc"
		"${install_prefix}/lib/pkgconfig/libavfilter.pc"
		"${install_prefix}/lib/pkgconfig/libavcodec.pc"
		"${install_prefix}/lib/pkgconfig/libavutil.pc")

	check_files_exist "false" "${required_files[@]}"

	echo -e "INFO: Done checking deployment files.\n" | tee -a "$LOG_FILE"

	echo -e "INFO: Installing ffmpeg pkg-config\n" | tee -a "$LOG_FILE"

	create_dir "$INSTALL_PKG_CONFIG_DIR"

	# MANUALLY COPY PKG-CONFIG FILES
	overwrite_file "${install_prefix}"/lib/pkgconfig/libavformat.pc "${INSTALL_PKG_CONFIG_DIR}/libavformat.pc" || return 1
	overwrite_file "${install_prefix}"/lib/pkgconfig/libswresample.pc "${INSTALL_PKG_CONFIG_DIR}/libswresample.pc" || return 1
	overwrite_file "${install_prefix}"/lib/pkgconfig/libswscale.pc "${INSTALL_PKG_CONFIG_DIR}/libswscale.pc" || return 1
	overwrite_file "${install_prefix}"/lib/pkgconfig/libavdevice.pc "${INSTALL_PKG_CONFIG_DIR}/libavdevice.pc" || return 1
	overwrite_file "${install_prefix}"/lib/pkgconfig/libavfilter.pc "${INSTALL_PKG_CONFIG_DIR}/libavfilter.pc" || return 1
	overwrite_file "${install_prefix}"/lib/pkgconfig/libavcodec.pc "${INSTALL_PKG_CONFIG_DIR}/libavcodec.pc" || return 1
	overwrite_file "${install_prefix}"/lib/pkgconfig/libavutil.pc "${INSTALL_PKG_CONFIG_DIR}/libavutil.pc" || return 1

	# # MANUALLY ADD REQUIRED HEADERS
	{
		mkdir -p "${install_prefix}"/include/libavutil/x86 
		mkdir -p "${install_prefix}"/include/libavutil/arm 
		mkdir -p "${install_prefix}"/include/libavutil/aarch64 
		mkdir -p "${install_prefix}"/include/libavcodec/x86 
		mkdir -p "${install_prefix}"/include/libavcodec/arm 
		overwrite_file "${ffmpeg_source_dir}"/config.h "${install_prefix}"/include/config.h 
		overwrite_file "${ffmpeg_source_dir}"/libavcodec/mathops.h "${install_prefix}"/include/libavcodec/mathops.h 
		overwrite_file "${ffmpeg_source_dir}"/libavcodec/x86/mathops.h "${install_prefix}"/include/libavcodec/x86/mathops.h 
		overwrite_file "${ffmpeg_source_dir}"/libavcodec/arm/mathops.h "${install_prefix}"/include/libavcodec/arm/mathops.h 
		overwrite_file "${ffmpeg_source_dir}"/libavformat/network.h "${install_prefix}"/include/libavformat/network.h 
		overwrite_file "${ffmpeg_source_dir}"/libavformat/os_support.h "${install_prefix}"/include/libavformat/os_support.h 
		overwrite_file "${ffmpeg_source_dir}"/libavformat/url.h "${install_prefix}"/include/libavformat/url.h 
		overwrite_file "${ffmpeg_source_dir}"/libavutil/attributes_internal.h "${install_prefix}"/include/libavutil/attributes_internal.h 
		overwrite_file "${ffmpeg_source_dir}"/libavutil/bprint.h "${install_prefix}"/include/libavutil/bprint.h 
		overwrite_file "${ffmpeg_source_dir}"/libavutil/getenv_utf8.h "${install_prefix}"/include/libavutil/getenv_utf8.h 
		overwrite_file "${ffmpeg_source_dir}"/libavutil/internal.h "${install_prefix}"/include/libavutil/internal.h 
		overwrite_file "${ffmpeg_source_dir}"/libavutil/libm.h "${install_prefix}"/include/libavutil/libm.h 
		overwrite_file "${ffmpeg_source_dir}"/libavutil/reverse.h "${install_prefix}"/include/libavutil/reverse.h 
		overwrite_file "${ffmpeg_source_dir}"/libavutil/thread.h "${install_prefix}"/include/libavutil/thread.h 
		overwrite_file "${ffmpeg_source_dir}"/libavutil/timer.h "${install_prefix}"/include/libavutil/timer.h 
		overwrite_file "${ffmpeg_source_dir}"/libavutil/x86/asm.h "${install_prefix}"/include/libavutil/x86/asm.h 
		overwrite_file "${ffmpeg_source_dir}"/libavutil/x86/timer.h "${install_prefix}"/include/libavutil/x86/timer.h 
		overwrite_file "${ffmpeg_source_dir}"/libavutil/arm/timer.h "${install_prefix}"/include/libavutil/arm/timer.h 
		overwrite_file "${ffmpeg_source_dir}"/libavutil/aarch64/timer.h "${install_prefix}"/include/libavutil/aarch64/timer.h 
		overwrite_file "${ffmpeg_source_dir}"/compat/w32pthreads.h "${install_prefix}"/include/libavutil/compat/w32pthreads.h 
		overwrite_file "${ffmpeg_source_dir}"/libavutil/wchar_filename.h "${install_prefix}"/include/libavutil/wchar_filename.h 
	} 1>>"$LOG_FILE"2 >&1

	echo -e "INFO: Done installing ffmpeg pkg-config\n" | tee -a "$LOG_FILE"
}

# shellcheck disable=SC2120
configure_ffmpeg() {
	echo -e "INFO: Configuring ffmpeg\n" | tee -a "$LOG_FILE"

	change_dir "$ffmpeg_source_dir" 1>>"$LOG_FILE" 2>&1 || return 1

	if [[ $BUILD_FORCE == "1" ]]; then
		remove_path -f "${ffmpeg_source_dir}/already_configured_$(get_build_type)*"
	fi

	# SET DEBUG OPTIONS
	if [[ -z ${FFMPEG_KIT_DEBUG} ]]; then
		# SET LTO FLAGS
		DEBUG_OPTIONS=" --disable-debug"
	else
		DEBUG_OPTIONS=" --enable-debug --disable-stripping"
	fi
	local extra_postpend_configure_options=$2

	local postpend_configure_opts=""

	# can't mix and match --enable-static --enable-shared unfortunately, or the final executable seems to just use shared if the're both present
	if [[ ${build_ffmpeg_shared,,} =~ ^(y|yes|1|true|on)$ ]]; then
		postpend_configure_opts="--enable-shared --disable-static --prefix=${install_prefix}" # I guess this doesn't have to be at the end...
	else
		postpend_configure_opts="--enable-static --disable-shared --prefix=${install_prefix}"
	fi

	if [[ $ffmpeg_git_checkout_version == *"n4.4"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.3"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.2"* ]]; then
		postpend_configure_opts="${postpend_configure_opts} --disable-libdav1d " # dav1d has diverged since so isn't compat with older ffmpegs
	fi

	change_dir "$ffmpeg_source_dir" || exit
	apply_patch file://"$WINPATCHDIR"/frei0r_load-shared-libraries-dynamically.diff
	if [ "$bits_target" = "32" ]; then
		local arch=x86
	else
		local arch=amd64
	fi

	local init_options="--pkg-config=pkg-config"
	init_options+=" --pkg-config-flags=--static"
	init_options+=" --enable-version3"
	init_options+=" --disable-debug"

	if [[ $compiler_flavors != "native" ]]; then
		init_options+=" --arch=$arch"
		init_options+=" --target-os=mingw32"
		init_options+=" --cross-prefix=$cross_prefix"
	else
		if [[ $OSTYPE != darwin* ]]; then
			unset PKG_CONFIG_LIBDIR # just use locally packages for all the xcb stuff for now, you need to install them locally first...
			init_options+=" --enable-libv4l2"
			init_options+=" --enable-libxcb"
			init_options+=" --enable-libxcb-shm"
			init_options+=" --enable-libxcb-xfixes"
			init_options+=" --enable-libxcb-shape "
		else
			config_options+=" --disable-libv4l2"
		fi
	fi
	if [[ $(uname) =~ 5.1 ]]; then
		init_options+=" --disable-schannel"
		# Fix WinXP incompatibility by disabling Microsoft's Secure Channel, because Windows XP doesn't support TLS 1.1 and 1.2, but with GnuTLS or OpenSSL it does.  XP compat!
	fi
	local config_options=" $init_options"
	config_options+=" --disable-alsa"
	config_options+=" --disable-appkit"
	config_options+=" --disable-audiotoolbox"
	config_options+=" --disable-autodetect"
	config_options+=" --disable-doc"
	config_options+=" --disable-gmp"
	config_options+=" --disable-gnutls"
	config_options+=" --disable-htmlpages"
	config_options+=" --disable-iconv"
	config_options+=" --disable-libdav1d"
	config_options+=" --disable-libfribidi"
	config_options+=" --disable-libilbc"
	config_options+=" --disable-libkvazaar"
	config_options+=" --disable-libopencore-amrnb"
	config_options+=" --disable-libopencore-amrwb"
	config_options+=" --disable-libopenh264"
	config_options+=" --disable-librubberband"
	config_options+=" --disable-libshine"
	config_options+=" --disable-libsnappy"
	config_options+=" --disable-libsoxr"
	config_options+=" --disable-libspeex"
	config_options+=" --disable-libsrt"
	config_options+=" --disable-libtesseract"
	config_options+=" --disable-libtheora"
	config_options+=" --disable-libtwolame"
	config_options+=" --disable-libvidstab"
	config_options+=" --disable-libvo-amrwbenc"
	config_options+=" --disable-libxml2"
	config_options+=" --disable-libxvid"
	config_options+=" --disable-libzimg"
	config_options+=" --disable-manpages"
	config_options+=" --disable-neon-clobber-test"
	config_options+=" --disable-openssl"
	config_options+=" --disable-podpages"
	config_options+=" --disable-pthreads"
	config_options+=" --disable-sdl2"
	config_options+=" --disable-securetransport"
	config_options+=" --disable-sndio"
	config_options+=" --disable-txtpages"
	config_options+=" --disable-v4l2-m2m"
	config_options+=" --disable-vaapi"
	config_options+=" --disable-vdpau"
	config_options+=" --disable-videotoolbox"
	config_options+=" --disable-xlib"
	config_options+=" --disable-xmm-clobber-test"
	config_options+=" --enable-bzlib"
	config_options+=" --enable-cross-compile"
	config_options+=" --enable-cuda"
	config_options+=" --enable-cuvid"
	config_options+=" --enable-ffnvcodec"
	config_options+=" --enable-filter=drawtext"
	config_options+=" --enable-libass"
	config_options+=" --enable-libfontconfig"
	config_options+=" --enable-libfreetype"
	config_options+=" --enable-libmp3lame"
	config_options+=" --enable-libopus"
	config_options+=" --enable-libvorbis"
	config_options+=" --enable-libvpx"
	config_options+=" --enable-libwebp"
	config_options+=" --enable-libx264"
	config_options+=" --enable-nvdec"
	config_options+=" --enable-nvenc"
	config_options+=" --enable-optimizations"
	config_options+=" --enable-pic"
	config_options+=" --enable-small"
	config_options+=" --enable-swscale"
	config_options+=" --enable-w32threads"
	config_options+=" --enable-zlib"
	#config_options+=" --disable-indevs"
	#config_options+=" --disable-outdevs"
	config_options+=${SIZE_OPTIONS}
	config_options+=${DEBUG_OPTIONS}

	if [[ $build_svt_hevc = y ]]; then
		# SVT-HEVC patches and enable
		if [[ $ffmpeg_git_checkout_version == *"n4.4"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.3"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.2"* ]]; then
			git apply "$work_dir/SVT-HEVC_git/ffmpeg_plugin/n4.4-0001-lavc-svt_hevc-add-libsvt-hevc-encoder-wrapper.patch"
			git apply "$WINPATCHDIR/SVT-HEVC-0002-doc-Add-libsvt_hevc-encoder-docs.patch"
		elif [[ $ffmpeg_git_checkout_version == *"n4.1"* ]] || [[ $ffmpeg_git_checkout_version == *"n3"* ]] || [[ $ffmpeg_git_checkout_version == *"n2"* ]]; then
			: # too old...
		else
			git apply "$work_dir/SVT-HEVC_git/ffmpeg_plugin/master-0001-lavc-svt_hevc-add-libsvt-hevc-encoder-wrapper.patch"
		fi
		config_options+=" --enable-libsvthevc"
	fi

	if [[ $build_svt_vp9 = y ]]; then
		# SVT-VP9 patches and enable
		if [[ $ffmpeg_git_checkout_version == *"n4.3.1"* ]]; then
			git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/n4.3.1-0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"
		elif [[ $ffmpeg_git_checkout_version == *"n4.2.3"* ]]; then
			git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/n4.2.3-0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"
		elif [[ $ffmpeg_git_checkout_version == *"n4.2.2"* ]]; then
			git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"
		else
			git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/master-0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"
		fi
		config_options+=" --enable-libsvtvp9"
	fi
	local enable_libsvtav1=" --enable-libsvtav1"
	# SVT-AV1
	if [[ $ffmpeg_git_checkout_version != *"n6"* ]] && [[ $ffmpeg_git_checkout_version != *"n5"* ]] && [[ $ffmpeg_git_checkout_version != *"n4"* ]] && [[ $ffmpeg_git_checkout_version != *"n3"* ]] && [[ $ffmpeg_git_checkout_version != *"n2"* ]]; then
		git apply "$work_dir/SVT-AV1_git/.gitlab/workflows/linux/ffmpeg_n7_fix.patch" >/dev/null 2>&1
		patch_exists=$?
		if [[ $patch_exists != 0 ]]; then
			enable_libsvtav1=" --disable-libsvtav1"
		fi
	fi
	config_options+=$enable_libsvtav1

	config_options+=" --enable-libaom"

	# ==================== ORIGINAL EXTRAS (conditionally kept) ====================

	if [[ $build_amd_amf = n ]]; then
		config_options+=" --disable-amf"
	else
		config_options+=" --enable-amf"
	fi

	if [[ $compiler_flavors != "native" ]]; then
		config_options+=" --enable-libvpl"
	else
		config_options+=" --disable-libvpl"
	fi

	if [[ $ffmpeg_git_checkout_version != *"n6.0"* ]] && [[ $ffmpeg_git_checkout_version != *"n5"* ]] && [[ $ffmpeg_git_checkout_version != *"n4"* ]] && [[ $ffmpeg_git_checkout_version != *"n3"* ]] && [[ $ffmpeg_git_checkout_version != *"n2"* ]]; then
		config_options+=" --enable-libaribcaption"
	fi

	if [[ $GPL_ENABLED == 'y' ]] || [[ $GPL_ENABLED == 'yes' ]]; then
		config_options+=" --enable-gpl --enable-frei0r --enable-librubberband --enable-libvidstab --enable-libx265 --enable-avisynth"
		config_options+=" --enable-libxvid --enable-libdavs2"
		if [[ $host_target != 'i686-w64-mingw32' ]]; then
			config_options+=" --enable-libxavs2"
		fi
		if [[ $compiler_flavors != "native" ]]; then
			config_options+=" --enable-libxavs"
		fi
	fi

	# Extra libs and flags
	config_options+=" --extra-libs=-lz"
	config_options+=" --extra-libs=-lpng"
	config_options+=" --extra-libs=-lm"
	config_options+=" --extra-libs=-lfreetype"

	if [[ $compiler_flavors != "native" ]]; then
		config_options+=" --extra-libs=-lshlwapi"
	fi
	config_options+=" --extra-libs=-lmpg123"
	config_options+=" --extra-libs=-lpthread"

	config_options+=" --extra-cflags=-DLIBTWOLAME_STATIC --extra-cflags=-DMODPLUG_STATIC --extra-cflags=-DCACA_STATIC"
	config_options+=" --extra-cflags=-DWIN32_ANSI_API --extra-cflags=-DHAVE_WCHAR_FILENAME_H=0"
	config_options+=" --extra-ldflags=-lole32 --extra-ldflags=-lshlwapi"
	config_options+=" --extra-ldflags=-static-libgcc --extra-ldflags=-static-libstdc++"
	for i in $CFLAGS; do
		config_options+=" --extra-cflags=$i"
	done

	config_options+=" $postpend_configure_opts"

	# if [[ "$non_free" = "y" ]]; then
	#   config_options+=" --enable-nonfree --enable-libfdk-aac"
	#   if [[ $OSTYPE != darwin* ]]; then
	#     config_options+=" --enable-audiotoolbox --disable-outdev=audiotoolbox --extra-libs=-lAudioToolboxWrapper" && apply_patch file://"$WINPATCHDIR"/AudioToolBox.patch -p1
	#   fi
	#   if [[ $compiler_flavors != "native" ]]; then
	#     config_options+=" --enable-decklink"
	#   fi
	# fi

	do_debug_build=n
	if [[ "$do_debug_build" = "y" ]]; then
		config_options+=" --disable-optimizations --extra-cflags=-Og --extra-cflags=-fno-omit-frame-pointer --enable-debug=3 --extra-cflags=-fno-inline $postpend_configure_opts"
		config_options+=" --disable-libgme"
	fi
	config_options+=" $extra_postpend_configure_options"

	do_configure "$config_options" "./configure" "$(get_build_type)" 1>>"$LOG_FILE" 2>&1

	echo -e "INFO: Done configuering ffmpeg\n" | tee -a "$LOG_FILE"
}

configure_ffmpeg_kit() {
	echo -e "INFO: Configuring ffmpeg kit\n" | tee -a "$LOG_FILE"
	local TYPE_POSTFIX="$(get_build_type)"
	local FFMPEG_KIT_VERSION=$(get_ffmpeg_kit_version)

	if [[ $BUILD_FORCE == "1" ]]; then
		remove_path -rf "${BASEDIR}"/windows/already_configured_*
		remove_path -rf "$ffmpeg_kit_install"
	fi

	create_dir "$ffmpeg_kit_install"

	export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${install_prefix}/lib/pkgconfig"
	set_toolchain_paths

	reset_cflags
	reset_cppflags
	local local_cflags="${CFLAGS} -I${install_prefix}/include -L${install_prefix}/bin -L${install_prefix}/lib -I${ffmpeg_source_dir} -I${ffmpeg_source_dir}/compat -DHAVE_W32PTHREADS_H=1"
	local local_cxxfalgs="${CXXFLAGS} -I${install_prefix}/include -L${install_prefix}/bin -L${install_prefix}/lib -I${ffmpeg_source_dir} -I${ffmpeg_source_dir}/compat"

	change_dir "${BASEDIR}/windows"
	make distclean 2>/dev/null 1>/dev/null

	local touch_name=$(get_small_touchfile_name "already_autoreconf_${TYPE_POSTFIX}" "$FFMPEG_KIT_VERSION $local_cflags $local_cxxfalgs")
	if [ ! -f "$touch_name" ]; then
		remove_path -f "${BASEDIR}/windows/already_autoreconf_${TYPE_POSTFIX}*"
		change_dir "${BASEDIR}/windows"
		autoreconf_library "ffmpeg-kit" 1>>"$LOG_FILE"2 >&1 || return 1
		touch -- "$touch_name"
		local BUILD_DATE="-DFFMPEG_KIT_BUILD_DATE=$(date +%Y%m%d 2>>"${BASEDIR}"/build.log)"
		export CFLAGS="${local_cflags} ${BUILD_DATE}"
		export CXXFLAGS="${local_cxxfalgs} ${BUILD_DATE}"
	fi

	local config_options="--prefix=${ffmpeg_kit_install}"

	config_options+=" --host=${host_target}"
	if [[ ${build_ffmpeg_static,,} =~ ^(y|yes|1|true|on)$ ]]; then
		config_options+=" --enable-static"
		config_options+=" --disable-shared"
	else
		config_options+=" --enable-shared"
		config_options+=" --disable-static"
	fi
	change_dir "${BASEDIR}/windows"
	do_configure "${config_options}" "./configure" "${TYPE_POSTFIX}" 1>>"$LOG_FILE"2 >&1 || return 1

	echo -e "INFO: Done configuring ffmpeg kit\n" | tee -a "$LOG_FILE"
}

create_ffmpegkit_package_config() {
	local FFMPEGKIT_VERSION="$1"

	cat >"${INSTALL_PKG_CONFIG_DIR}/ffmpeg-kit.pc" <<EOF
prefix=${ffmpeg_kit_install}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: ffmpeg-kit
Description: FFmpeg for applications on Windows
Version: ${FFMPEGKIT_VERSION}

# Public dependencies that have their own .pc files
Requires: libavfilter, libswscale, libavformat, libavcodec, libswresample, libavutil

# Linker flags for the ffmpeg-kit library itself (includes jsoncpp if static)
Libs: -L\${libdir} -lffmpegkit

# Private dependencies needed for linking on Windows
Libs.private: -lstdc++ -lws2_32 -lpsapi -lole32 -lshlwapi -lgdi32 -lbcrypt -luser32 -luuid

# Compiler flags for the ffmpeg-kit headers (includes jsoncpp headers if bundled)
Cflags: -I\${includedir}
EOF
}

install_ffmpeg_kit() {
	echo -e "INFO: Installing ffmpeg kit to ${ffmpeg_kit_install}\n" | tee -a "$LOG_FILE"

	change_dir "${BASEDIR}/windows"
	do_make_and_make_install "" "" "$(get_build_type)" 1>>"$LOG_FILE" 2>&1

	create_ffmpegkit_package_config "$(get_ffmpeg_kit_version)" 1>>"$LOG_FILE"2 >&1 || return 1

	echo -e "INFO: Done installing ffmpeg kit to ${ffmpeg_kit_install}\n" | tee -a "$LOG_FILE"
}

get_bundle_directory() {
	local LTS_POSTFIX=""
	if [[ -n ${FFMPEG_KIT_LTS_BUILD} ]]; then
		LTS_POSTFIX="-lts"
	fi
	local TYPE_POSTFIX="$(get_build_type)"
	echo -e "bundle-windows-${TYPE_POSTFIX}${LTS_POSTFIX}"
}

create_windows_bundle() {
	echo -e "INFO: Creating bundle" 1>>"$LOG_FILE" 2>&1
	local TYPE_POSTFIX="$(get_build_type)"
	local FFMPEG_KIT_VERSION=$(get_ffmpeg_kit_version)

	if [[ $BUILD_FORCE == "1" ]]; then
		remove_path -rf "${BASEDIR}/windows/already_bundled_${TYPE_POSTFIX}*"
	fi

	local touch_name=$(get_small_touchfile_name "already_bundled_${TYPE_POSTFIX}" "$FFMPEG_KIT_VERSION $ffmpeg_kit_bundle")
	if [ ! -f "$touch_name" ]; then
		export FFMPEG_KIT_BUNDLE_INCLUDE_DIRECTORY="${ffmpeg_kit_bundle}/include"
		export FFMPEG_KIT_BUNDLE_LIB_DIRECTORY="${ffmpeg_kit_bundle}/lib"
		export FFMPEG_KIT_BUNDLE_BIN_DIRECTORY="${ffmpeg_kit_bundle}/bin"
		export FFMPEG_KIT_BUNDLE_PKG_CONFIG_DIRECTORY="${ffmpeg_kit_bundle}/pkgconfig"
		remove_path "-rf" "${ffmpeg_kit_bundle}"
		create_dir "${ffmpeg_kit_bundle}"
		create_dir "${FFMPEG_KIT_BUNDLE_INCLUDE_DIRECTORY}"
		create_dir "${FFMPEG_KIT_BUNDLE_LIB_DIRECTORY}"
		create_dir "${FFMPEG_KIT_BUNDLE_BIN_DIRECTORY}"
		create_dir "${FFMPEG_KIT_BUNDLE_PKG_CONFIG_DIRECTORY}"
		{
			# COPY HEADERS
			copy_path "${ffmpeg_kit_install}/include/*" "${FFMPEG_KIT_BUNDLE_INCLUDE_DIRECTORY}" "-r -P"
			copy_path "${install_prefix}/include/*" "${FFMPEG_KIT_BUNDLE_INCLUDE_DIRECTORY}" "-r -P"

			# COPY LIBS
			copy_path "${ffmpeg_kit_install}/lib/*" "${FFMPEG_KIT_BUNDLE_LIB_DIRECTORY}" "-r -P"
			copy_path "${install_prefix}/lib/*" "${FFMPEG_KIT_BUNDLE_LIB_DIRECTORY}" "-r -P"

			# COPY BINARIES
			copy_path "${ffmpeg_kit_install}/bin/*" "${FFMPEG_KIT_BUNDLE_BIN_DIRECTORY}" "-r -P"
			copy_path "${install_prefix}/bin/*" "${FFMPEG_KIT_BUNDLE_BIN_DIRECTORY}" "-r -P"
		} 1>>"$LOG_FILE"2 >&1

		install_pkg_config_file "libavformat.pc"
		install_pkg_config_file "libswresample.pc"
		install_pkg_config_file "libswscale.pc"
		install_pkg_config_file "libavdevice.pc"
		install_pkg_config_file "libavfilter.pc"
		install_pkg_config_file "libavcodec.pc"
		install_pkg_config_file "libavutil.pc"
		install_pkg_config_file "ffmpeg-kit.pc"

		local LICENSE_BASEDIR="${ffmpeg_kit_bundle}/licenses"

		create_dir "${LICENSE_BASEDIR}"

		echo -e "INFO: Copying licenses...\n" | tee -a "$LOG_FILE"
		bash "${SCRIPTDIR}/extract_licenses.sh" "${work_dir}" "${LICENSE_BASEDIR}" 1>>"$LOG_FILE" 2>&1
		echo -e "INFO: Done copying licenses\n" | tee -a "$LOG_FILE"

		copy_path "${BASEDIR}"/tools/source/SOURCE "${LICENSE_BASEDIR}/source.txt" 1>>"$LOG_FILE" 2>&1
		copy_path "${BASEDIR}"/tools/license/LICENSE.GPLv3 "${LICENSE_BASEDIR}"/license.txt 1>>"${BASEDIR}"/build.log 2>&1
		touch -- "$touch_name"
	fi
	echo -e "INFO: Done creating bundle\n" | tee -a "$LOG_FILE"
}

pick_clean_type() {
	while [[ ! "$clean_type" =~ ^([1-5]|all|ffmpeg|ffmpeg-kit|ffmpeg-kit-bundle)$ ]]; do
		# shellcheck disable=SC2199
		if [[ -n "${unknown_opts[@]}" ]]; then
			echo -e -n 'Unknown option(s)'
			for unknown_opt in "${unknown_opts[@]}"; do
				echo -e -n " '$unknown_opt'"
			done
			echo -e ', ignored.'
			echo
		fi
		cat <<'EOF'
What would you like to clean?
  1. all
  2. ffmpeg
  3. ffmpeg-kit
  4. ffmpeg-kit-bundle
  5. Exit
EOF
		echo -e -n 'Input your choice [1-5]: '
		read -r clean_type
	done
	case "$clean_type" in
	1) export clean_type="all" ;;
	2) export clean_type="ffmpeg" ;;
	3) export clean_type="ffmpeg-kit" ;;
	4) export clean_type="ffmpeg-kit-bundle" ;;
	all) export clean_type="all" ;;
	ffmpeg) export clean_type="ffmpeg" ;;
	ffmpeg-kit) export clean_type="ffmpeg-kit" ;;
	ffmpeg-kit-bundle) export clean_type="ffmpeg-kit-bundle" ;;
	5)
		echo -e "exiting"
		exit 0
		;;
	*)
		echo -e 'Your choice was not valid, please try again.'
		echo
		;;
	esac
}

clean_ffmpeg_builds() {
	if [[ -z $compiler_flavors ]]; then
		pick_compiler_flavors
	fi
	pick_clean_type
	if [[ ${compiler_flavors,,} =~ ^(multi)$ ]]; then
		clean_builds "win32"
		clean_builds "win64"
	else
		clean_builds "$compiler_flavors"
		exit 0
	fi
}

clean_builds() {
	local build_flavor=$1
	if [[ -z $build_flavor ]]; then
		exit 1
	fi
	pick_compiler_flavors "$build_flavor"
	setup_build_environment "$compiler_flavors"
	if [[ ${clean_type,,} =~ ^("all"|"ffmpeg")$ ]]; then
		echo -e "INFO: Deleting ${install_prefix}..."
		remove_path "${install_prefix}"
	fi
	if [[ ${clean_type,,} =~ ^("all"|"ffmpeg-kit")$ ]]; then
		echo -e "INFO: Deleting ${ffmpeg_kit_install}..."
		remove_path "${ffmpeg_kit_install}"
	fi
	if [[ ${clean_type,,} =~ ^("all"|"ffmpeg-kit-bundle")$ ]]; then
		echo -e "INFO: Deleting ${ffmpeg_kit_bundle}..."
		remove_path "${ffmpeg_kit_bundle}"
	fi
}
