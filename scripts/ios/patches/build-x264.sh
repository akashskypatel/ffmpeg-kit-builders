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

CONFIGURE_FLAGS="--enable-static --enable-pic --disable-cli"

ARCHS="arm64 x86_64 i386 armv7 armv7s"

# directories
SOURCE="x264"
FAT="x264-iOS"

SCRATCH="scratch-x264"
# must be an absolute path
THIN=`pwd`/"thin-x264"

COMPILE="y"
LIPO="y"

if [ "$*" ]
then
	if [ "$*" = "lipo" ]
	then
		# skip compile
		COMPILE=
	else
		ARCHS="$*"
		if [ $# -eq 1 ]
		then
			# skip lipo
			LIPO=
		fi
	fi
fi

# Detect simulator context from install prefix path.
IS_SIMULATOR="${IS_SIMULATOR:-}"
if echo "${THIN}" | grep -qi "iphonesimulator"; then
    IS_SIMULATOR="y"
fi

if [ "$COMPILE" ]
then
	CWD=`pwd`
	for ARCH in $ARCHS
	do
		echo "building $ARCH..."
		mkdir -p "$SCRATCH/$ARCH"
		cd "$SCRATCH/$ARCH"
		CFLAGS=
		ASFLAGS=
		SIM_TARGET=

		if [ "$ARCH" = "i386" -o "$ARCH" = "x86_64" ]
		then
			PLATFORM="iPhoneSimulator"
			CFLAGS="-arch $ARCH"
			if [ "$ARCH" = "x86_64" ]
			then
				CFLAGS="$CFLAGS -mios-simulator-version-min=7.0"
				HOST=
			else
				CFLAGS="$CFLAGS -mios-simulator-version-min=5.0"
				HOST="--host=i386-apple-darwin"
			fi
		elif [ "$ARCH" = "arm64" -a "$IS_SIMULATOR" = "y" ]
		then
			PLATFORM="iPhoneSimulator"
			SIM_TARGET="arm64-apple-ios13.0-simulator"
			CFLAGS="-arch arm64 -mios-simulator-version-min=13.0"
			HOST="--host=aarch64-apple-darwin"
			XARCH="-arch aarch64"
			ASFLAGS="$CFLAGS"
		else
			PLATFORM="iPhoneOS"
			CFLAGS="-arch $ARCH"
			if [ "$ARCH" = "arm64" ]
			then
				HOST="--host=aarch64-apple-darwin"
				XARCH="-arch aarch64"
			else
				HOST="--host=arm-apple-darwin"
				XARCH="-arch arm"
			fi
			CFLAGS="$CFLAGS -fembed-bitcode -mios-version-min=7.0"
			ASFLAGS="$CFLAGS"
		fi

		XCRUN_SDK=`echo $PLATFORM | tr '[:upper:]' '[:lower:]'`
		SYSROOT=$(xcrun -sdk $XCRUN_SDK --show-sdk-path)
		CC="xcrun -sdk $XCRUN_SDK clang"

		if [ -n "$SIM_TARGET" ]
		then
			CC="xcrun -sdk $XCRUN_SDK clang -target $SIM_TARGET -isysroot $SYSROOT"
		fi

		if [ "$PLATFORM" = "IPhoneOS" -o \( "$ARCH" = "arm64" -a "$IS_SIMULATOR" = "y" \) ]
		then
			export AS="$CWD/tools/gas-preprocessor.pl $XARCH -- $CC"
		else
			export -n AS
		fi

		CXXFLAGS="$CFLAGS"
		LDFLAGS="$CFLAGS"

		CC=$CC $CWD/configure \
			$CONFIGURE_FLAGS \
			$HOST \
			--extra-cflags="$CFLAGS" \
			--extra-asflags="$ASFLAGS" \
			--extra-ldflags="$LDFLAGS" \
			--prefix="$THIN/$ARCH" || exit 1

		make -j3 install || exit 1
		cd $CWD
	done
fi

if [ "$LIPO" ]
then
	echo "building fat binaries..."

	DEVICE_ARCHS=""
	SIM_ARCHS=""
	for ARCH in $ARCHS
	do
		case $ARCH in
			x86_64|i386)
				SIM_ARCHS="$SIM_ARCHS $ARCH" ;;
			arm64)
				if [ "$IS_SIMULATOR" = "y" ]
				then
					SIM_ARCHS="$SIM_ARCHS $ARCH"
				else
					DEVICE_ARCHS="$DEVICE_ARCHS $ARCH"
				fi ;;
			*)
				DEVICE_ARCHS="$DEVICE_ARCHS $ARCH" ;;
		esac
	done

	CWD=`pwd`

	if [ -n "$DEVICE_ARCHS" ]
	then
		mkdir -p "$FAT/lib"
		FIRST_DEVICE=$(echo $DEVICE_ARCHS | awk '{print $1}')
		cd "$THIN/$FIRST_DEVICE/lib"
		for LIB in *.a
		do
			cd $CWD
			INPUTS=$(for A in $DEVICE_ARCHS; do echo "$THIN/$A/lib/$LIB"; done | xargs)
			lipo -create $INPUTS -output "$FAT/lib/$LIB"
		done
		cd $CWD
		cp -rf "$THIN/$FIRST_DEVICE/include" "$FAT"
	fi

	if [ -n "$SIM_ARCHS" ]
	then
		mkdir -p "$FAT-simulator/lib"
		FIRST_SIM=$(echo $SIM_ARCHS | awk '{print $1}')
		cd "$THIN/$FIRST_SIM/lib"
		for LIB in *.a
		do
			cd $CWD
			INPUTS=$(for A in $SIM_ARCHS; do echo "$THIN/$A/lib/$LIB"; done | xargs)
			lipo -create $INPUTS -output "$FAT-simulator/lib/$LIB"
		done
		cd $CWD
		cp -rf "$THIN/$FIRST_SIM/include" "$FAT-simulator"
	fi
fi