#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,SC2269

# 1. exit code
# 2. message
# shellcheck disable=SC2244
exit_message() {
	local code=$1
	shift 1
	local msg="$*"
	
	if truthy "$code"; then
		if [ "$msg" ]; then
			echo -e "\nERROR: $msg" | tee -a "$LOG_FILE"
		else
			echo -e "\nERROR: an error occured" | tee -a "$LOG_FILE"
		fi
	exit 1
	else
		if [ "$msg" ]; then
			echo -e "INFO: $msg" >>"$LOG_FILE"
		fi
	fi
}

# 1. info_msg
# 2. error_msg
# 3. no_exit
execute() {
	local info_msg="$1"
	local error_msg="$2"
	local no_exit="$3"
	shift 3
  # shellcheck disable=SC2244
	if [ ! "$error_msg" ]; then
		error_msg="error"
	fi
  echo "INFO: Executing: $*" >>"$LOG_FILE"
	if [[ $no_exit != "true" ]]; then
		eval "$*" 1>>"$LOG_FILE" 2>&1 || exit_message 1 "$error_msg, check $LOG_FILE for details"
	else
		echo -e "${info_msg}" >>"$LOG_FILE"
		eval "$*" 1>>"$LOG_FILE" 2>&1
	fi
}

# 1. path
create_dir() {
	local path="$1"

	echo -e "DEBUG: creating path ${path}" >>"$LOG_FILE"

	if [ -z "$path" ]; then
		exit_message 1 "create_dir: path argument is required"
	fi

	if [[ ! -d "$path" ]]; then
		execute "INFO: creating path: '$path'" "ERROR: unable to create directory '$path'" "true" \
			mkdir -pv "$path"
	else
		echo -e "DEBUG: directory already exists, skipping creation." >>"$LOG_FILE"
	fi
  execute "INFO: updating path permissions: '$path'" "ERROR: unable to update permissions on '$path'" "true" \
    chmod -R a+rwx "$path"
}
# 1. options
# @. paths
remove_path() {
    local recursive=false force=false other_options=()
    local paths=()
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--recursive) recursive=true ;;
            -f|--force) force=true ;;
            --)
                shift
                paths+=("$@")
                break
                ;;
            -*) other_options+=("$1")
                [[ $1 == *"r"* ]] && recursive=true
                [[ $1 == *"f"* ]] && force=true
                ;;
            *) paths+=("$1") ;;
        esac
        shift
    done

    local rm_options=()
    [[ "$recursive" == true ]] && rm_options+=(-r)
    [[ "$force" == true ]] && rm_options+=(-f)
    rm_options+=("${other_options[@]}")

    if [ ${#paths[@]} -eq 0 ]; then
        echo -e "ERROR: at least one path argument is required" >>"$LOG_FILE"
        return 1
    fi

    for path in "${paths[@]}"; do
        if [[ -z "$path" ]]; then
            echo -e "ERROR: empty path argument" >>"$LOG_FILE"
            return 1
        fi
        
        if [[ "$path" == "/" || "$path" == "$HOME" || "$path" == "~" || "$path" == "." || "$path" == ".." ]]; then
            echo -e "ERROR: dangerous path '$path' - refusing to remove" >>"$LOG_FILE"
            return 1
        fi
    done

    # Process each path
    for path in "${paths[@]}"; do
        echo -e "DEBUG: removing path: '$path'" >>"$LOG_FILE"

        if [[ -e "$path" ]]; then
            # For directories, ensure recursive flag is set
            if [[ -d "$path" && "$recursive" != true ]]; then
                echo -e "WARNING: '$path' is a directory but recursive option not set. Adding -r flag for removal." >>"$LOG_FILE"
                rm_options+=(-r)
            fi
            execute "INFO: updating path permissions: '$path'" "ERROR: unable to update permissions on '$path'" "true" \
              chmod -R a+rwx "$path"
            execute "INFO: removing path: '$path'" "ERROR: unable to remove path '$path'" "true" \
                rm "${rm_options[@]}" "$path"
        else
            echo -e "INFO: path '$path' does not exist" >>"$LOG_FILE"
            if [[ "$force" != true ]]; then
                echo -e "WARNING: path '$path' not found and force flag not set" >>"$LOG_FILE"
            fi
        fi
    done
}

# 1. path
# 2. create if not exists
change_dir() {
	local path="$1"
	local create="$2"
	if [ -z "$path" ]; then
		exit_message 1 "change_dir: path argument is required"
	fi

	if [[ -e "$path" ]]; then
		execute "INFO: changing to path: '$(validate_path "$path")'" "ERROR: unable to cd to directory '$(validate_path "$path")'" "true" \
			cd "$path"
		if [[ ! -r "$path" ]] || [[ ! -w "$path" ]] || [[ ! -x "$path" ]]; then
      execute "INFO: updating path permissions: '$path'" "ERROR: unable to update permissions on '$path'" "true" \
        chmod -R a+rwx "$(pwd)"
		fi
	else
		echo -e "INFO: path '$path' does not exist" >>"$LOG_FILE"
		if [[ -n $create ]]; then
			echo -e "INFO: creating '$path'" >>"$LOG_FILE"
			create_dir "$path"
			change_dir "$path"
		fi
	fi
}

# 1. source_path
# 2. destination_path
# 3. options
# 4. skip_if_exists
copy_path() {
	local source_path="$1"
	local destination_path="$2"
	local options="${3:-}"             # Default to empty
	local skip_if_exists="${4:-false}" # Default to false

	echo -e "DEBUG: copying from ${source_path} to ${destination_path}" >>"$LOG_FILE"

	if [ -z "$source_path" ] || [ -z "$destination_path" ]; then
		exit_message 1 "copy_path: both source and destination path arguments are required"
	fi

	if [ ! -e "$source_path" ]; then
		echo -e "ERROR: source path '$source_path' does not exist" >>"$LOG_FILE"
		return 0
	fi

	# Check if destination already exists
	if [ "$skip_if_exists" = "true" ] && [ -e "$destination_path" ]; then
		echo -e "INFO: destination '$destination_path' already exists, skipping copy" >>"$LOG_FILE"
		return 0
	fi

	# Create destination directory if it doesn't exist
	local destination_dir
	destination_dir=$(dirname "$destination_path")

	if [ ! -d "$destination_dir" ]; then
		create_dir "$destination_dir"
	fi

	# Perform the copy operation
	if [ -n "$options" ]; then
		execute "INFO: copying path: '$source_path' to '$destination_path' with options '$options'" "ERROR: unable to copy '$source_path' to '$destination_path'" "false" \
			cp "$options" "$source_path" "$destination_path"
	else
		execute "INFO: copying path: '$source_path' to '$destination_path'" "ERROR: unable to copy '$source_path' to '$destination_path'" "false" \
			cp -r "$source_path" "$destination_path"
	fi

	# Update permissions on the copied path
  execute "INFO: updating path permissions: '$path'" "ERROR: unable to update permissions on '$path'" "true" \
    chmod -R a+rwx "$path"
}

# 1. skip_if_missing
check_files_exist() {
	local skip_if_missing="${1:-false}"
	shift 1
	local files=("$@")

	echo -e "DEBUG: checking ${#files[@]} files" >>"$LOG_FILE"

	if [ ${#files[@]} -eq 0 ]; then
		echo -e "ERROR: file list argument is required" >>"$LOG_FILE"
		return 1
	fi

	local missing_files=()

	for file in "${files[@]}"; do
		if [ ! -e "$file" ]; then
			missing_files+=("$file")
		fi
	done

	if [ ${#missing_files[@]} -gt 0 ]; then
		if [ "$skip_if_missing" = "true" ]; then
			echo -e "INFO: ${#missing_files[@]} files are missing" >>"$LOG_FILE"
			return 0
		else
			exit_message 1 "check_files_exist: ${#missing_files[@]} required files are missing: ${missing_files[*]}"
		fi
	else
		echo -e "INFO: all ${#files[@]} files exist" >>"$LOG_FILE"
	fi
}

require_sudo() {
	if [ "$EUID" -ne 0 ]; then
		exit_message 1 "This script must be run with sudo"
	fi

	if [ -z "$SUDO_USER" ]; then
		echo "Warning: Running as root directly (not via sudo)" | tee -a "$LOG_FILE"
	else
		echo "Running with sudo privileges (user: $SUDO_USER)" | tee -a "$LOG_FILE"
	fi
}

is_integer() {
    local str="$1"
    if [[ "$str" =~ ^[-+]?[0-9]+$ ]]; then
        echo "0" # Is integer
    else
        echo "1" # Not integer
    fi
}

is_alpha() {
	local str="$1"
	if [[ "$str" =~ ^[a-zA-Z]+$ ]]; then
		echo "0" # Is integer
	else
		echo "1" # Not integer
	fi
}
find_build_step() {
  local search="$1"
  for key in "${OPTIMIZED_BUILD_STEPS[@]}"; do
    if [[ "$key" == *"$search"* ]]; then
      echo "$key"
      return 0
    fi
  done
  return 1
}
array_index_of() {
	local search_string="$1"
	shift
	local array=("$@")

	for i in "${!array[@]}"; do
		if [[ "${array[i]}" == *"$search_string" ]]; then
			echo "$i" # Return the index
			return 0
		fi
	done
	exit_message 0 "array_index_of: $search_string could not be found in array.\n ${array[*]}" | tee -a "$LOG_FILE"
	return 1
}

concat_array() {
    local array_name="$1"
    local separator="${2:- }"
    local -n arr="$array_name"
    
    if [ ${#arr[@]} -eq 0 ]; then
        echo ""
        return
    fi
    
    local result=""
    printf -v result "%s$separator" "${arr[@]}"
    echo "$result%$separator"
}

# Check if value is truthy
# Returns 0 (success) for truthy values, 1 (failure) for falsey values
truthy() {
  local value="$1"
  case "${value,,}" in
    true|1|T|t|True|TRUE|y|Y|yes|Yes|YES|on|On|ON) return 0 ;;
    *) return 1 ;;
  esac
}

# Check if value is falsey  
# Returns 0 (success) for falsey values, 1 (failure) for truthy values
falsey() {
  local value="$1"
  case "${value,,}" in
    false|0|F|f|False|FALSE|n|N|no|No|NO|off|Off|OFF) return 0 ;;
    *) return 1 ;;
  esac
}

#
# 1. source file
# 2. destination file
#
overwrite_file() {
	copy_path "$2" "$2.bak" "-rf" # backup
	remove_path -f "$2" 2>>"$LOG_FILE"
	copy_path "$1" "$2" "-rf" 2>>"$LOG_FILE"
}

setup_build_environment() {
    pick_host_platform "$host_platform"
    pick_host_arch "$host_arch"
    calculate_bits_target
    determine_distro
    export host_name="$host_platform-$host_arch"
    echo -e "\n************** Setting up environment for $host_name build... **************" | tee -a "$LOG_FILE"
    
    export work_dir="$(validate_path "$WORKDIR"/"$host_name")"
    export build_triple="${build_triple:-$(gcc -dumpmachine)}"
    # Common setup for all platforms
    export ffmpeg_source_dir=${ffmpeg_source_dir:-"${src_dir}/ffmpeg"}
    export ffmpeg_install_prefix="${work_dir}/$(get_ffmpeg_directory)"
    export ffmpeg_kit_install="${work_dir}/$(get_ffmpeg_kit_directory)"
    export ffmpeg_kit_bundle="${work_dir}/$(get_bundle_directory)"
    export host_touch="${host_name}_src_state.touch"
    export ffmpeg_kit_src_dir="${BASEDIR}/FFmpegKit"
    export original_pkg_config_path="$PKG_CONFIG_PATH"
    case "$host_platform" in
        "windows") setup_windows_environment ;;
        "linux") setup_linux_environment ;;
        "android") setup_android_environment ;;
        "macos") setup_macos_environment ;;
        "ios") setup_ios_environment ;;
        "iphonesimulator") setup_ios_environment "iphonesimulator" ;;
        "appletvos") setup_tvos_environment "appletvos" ;;
        "appletvsimulator") setup_tvos_environment "appletvsimulator" ;;
        *) exit_message 1 "setup_build_environment: Unknown host platform '$host_platform'" ;;
    esac
    create_dir "$src_dir"
    change_dir "$work_dir" || exit_message 1 "setup_build_environment: Unable to change to directory '$work_dir'"
    # PyPa Manylinux comes bundled with these tools that are higher version than whats available through pkg manager
    # We need to use the bundled versions
    # List of tools to check
    for tool in autoconf automake aclocal autoheader autoreconf autom4te libtool libtoolize; do
        # 1. Get Bundled Version (or 0 if missing)
        if [ -x "/usr/local/bin/$tool" ]; then
            bundled_ver=$(/usr/local/bin/"$tool" --version 2>/dev/null | head -n 1 | awk '{print $NF}')
        else
            bundled_ver="0"
        fi
        # 2. Get Installed System Version (or 0 if missing)
        if [ -x "/usr/bin/$tool" ]; then
            installed_ver=$(/usr/bin/"$tool" --version 2>/dev/null | head -n 1 | awk '{print $NF}')
        else
            installed_ver="0"
        fi
        echo "Checking $tool: Bundled=$bundled_ver vs System=$installed_ver" >> "$LOG_FILE"
        # 3. Compare: Find the Highest Version
        # We sort the two versions; 'tail -n 1' gives us the "winner" (highest ver)
        winner=$(printf '%s\n%s\n' "$bundled_ver" "$installed_ver" | sort -V | tail -n 1)
        # 4. If Bundled is the winner (and it actually exists), Force Link
        if [ "$winner" = "$bundled_ver" ] && [ "$bundled_ver" != "0" ]; then
            echo " -> Updating system $tool to use bundled version $bundled_ver" >> "$LOG_FILE"
            ln -sf "/usr/local/bin/$tool" "/usr/bin/$tool"
        else
            echo " -> Keeping system version (System is newer or Bundled is missing)" >> "$LOG_FILE"
        fi
    done
}

calculate_bits_target() {
    case "$host_arch" in
        "armv7a"|"armeabi-v7a"|"arm"|"i686") export bits_target=32 ;;
        "x86_64"|"aarch64"|"arm64-v8a"|"arm64") export bits_target=64 ;;
        *) exit_message 1 "calculate_bits_target: Unknown host arch '$host_arch'" ;;
    esac
}

setup_windows_environment() {
    export PATCHDIR="$SCRIPTDIR/windows/patches"
    export host_target="$host_arch-w64-mingw32"
    export rust_target="$host_arch-pc-windows-gnu"
    export toolchain_root="mingw-w64-$host_arch"
    export dependency_install_prefix="$work_dir/libraries" # dependencies
    export toolchain_root_dir="/usr/local/mingw-w64/"
    export toolchain_bin_path="/usr/local/mingw-w64/bin"
    export install_pkgconfig_dir="${dependency_install_prefix}/lib/pkgconfig"

    export PKG_CONFIG_PATH="$install_pkgconfig_dir:$ffmpeg_install_prefix/lib/pkgconfig"
    # export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"
    # export PKG_CONFIG_SYSROOT_DIR="$dependency_install_prefix"
    export PATH="$original_path:$toolchain_bin_path:$ffmpeg_install_prefix/bin"
    export cross_prefix="/usr/local/mingw-w64/bin/$host_target-"
    export CROSS_COMPILE="$host_target-"
    create_dir "$install_pkgconfig_dir"
    create_dir "$work_dir/pkgconfig"
    create_dir "$dependency_install_prefix/{bin,lib/pkgconfig,include,usr/include}"

    case "$host_arch" in
        "x86_64")
            export host_arch="x86_64"
            export cmake_host_arch="x86_64"
            ;;
        # TODO: Add support for aarch64
        # "aarch64"|"arm64"|"arm64-v8a")
        #     export host_arch="aarch64"
        #     export cmake_host_arch="aarch64"
        #     ;;
        *)
            exit_message 1 "setup_windows_environment: Unsupported host arch '$host_arch' for $host_platform"
            ;;
    esac
    
    reset_cross_vars
    export PREFIX="$dependency_install_prefix"
    export build_cross_compile=y
    
    export stdcpp_path="$(realpath "$("$CXX" -print-file-name=libstdc++.a)")"
    export stdgcc_path="$(realpath "$("$CXX" -print-file-name=libgcc.a)")"

    export windows_cflags="$original_cflags -std=gnu11 -mtune=generic -O3 -pipe -Wno-pedantic -D_POSIX_THREADS -fno-use-linker-plugin -mstackrealign"
    export CFLAGS="$windows_cflags"
    
    export windows_cxxflags="$original_cxxflags -I${dependency_install_prefix}/include -D_POSIX_THREADS -fno-use-linker-plugin -mstackrealign"
    export CXXFLAGS="$windows_cxxflags"
    
    export windows_cppflags="$original_cppflags -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -I${dependency_install_prefix}/include"
    export CPPFLAGS="$windows_cppflags"
    
    export windows_ldflags="-static -static-libgcc -static-libstdc++ $original_ldflags -L${dependency_install_prefix}/lib"
    export LDFLAGS="$windows_ldflags"

    export GXX_STANDARD_LIBS="$stdcpp_path $stdgcc_path"
    export GCC_STANDARD_LIBS="$stdgcc_path"

    cross_windres
}

setup_linux_environment() {
    export PATCHDIR="$SCRIPTDIR/linux/patches"
    export host_target="$build_triple"
    export rust_target="$host_arch-unknown-linux-gnu"
    export dependency_install_prefix="$work_dir/libraries" # dependencies
    export install_pkgconfig_dir="${dependency_install_prefix}/lib/pkgconfig"
    
    export PKG_CONFIG_PATH="$original_pkg_config_path:$dependency_install_prefix/share/pkgconfig:$install_pkgconfig_dir:$dependency_install_prefix/lib/$host_target/pkgconfig:$work_dir/pkgconfig:$ffmpeg_install_prefix/lib/pkgconfig:/usr/lib/$host_target/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    export PATH="$ffmpeg_install_prefix/bin:$dependency_install_prefix/bin:$original_path"
    
    export linux_cflags="$original_cflags -Wno-pedantic -I${dependency_install_prefix}/include "
    export CFLAGS="$linux_cflags"
    export linux_cppflags="$original_cppflags -I${dependency_install_prefix}/include -DLINUX "
    export CPPFLAGS="$linux_cppflags"
    export linux_cxxflags="$original_cxxflags -I${dependency_install_prefix}/include "
    export CXXFLAGS="$linux_cxxflags"
    export linux_ldflags="$original_ldflags -L${dependency_install_prefix}/lib -Wl,-rpath,${dependency_install_prefix}/lib "
    export LDFLAGS="$linux_ldflags"
    export LD_LIBRARY_PATH="${dependency_install_prefix}/lib:$LD_LIBRARY_PATH"

    case "$host_arch" in
        "x86_64")
            export host_arch="x86_64"
            export cmake_host_arch="x86_64"
            ;;
        # TODO: Add support for aarch64
        # "aarch64"|"arm64"|"arm64-v8a")
        #     export host_arch="aarch64"
        #     export cmake_host_arch="aarch64"
        #     ;;
        *)
            exit_message 1 "setup_linux_environment: Unsupported host arch '$host_arch' for $host_platform"
            ;;
    esac
    
    source /opt/rh/gcc-toolset-14/enable
    
    export NASM=nasm
    export CC=gcc
    export AR=ar
    export AS=as
    export RANLIB=ranlib
    export LD=ld
    export STRIP=strip
    export CXX=g++

    create_dir "$install_pkgconfig_dir"
    create_dir "$work_dir/pkgconfig"
    create_dir "$dependency_install_prefix/{bin,lib/pkgconfig,include,usr/include}"
}

setup_android_environment() {
    export PATCHDIR="$SCRIPTDIR/android/patches"

    # Detect Android SDK/NDK
    if [[ -z "$ANDROID_HOME" ]]; then
        export ANDROID_HOME="/usr/local/android-sdk"
    fi

    # Try to find NDK
    if [[ -z "$ANDROID_NDK_ROOT" ]]; then
        if [[ -d "$ANDROID_HOME/ndk-bundle" ]]; then
            export ANDROID_NDK_ROOT="$ANDROID_HOME/ndk-bundle"
        else
            # shellcheck disable=2012
            export latest_ndk="$(ls -v "$ANDROID_HOME/ndk" 2>/dev/null | tail -n 1)"
            if [[ -n "$latest_ndk" ]]; then
                export ANDROID_NDK_ROOT="$ANDROID_HOME/ndk/$latest_ndk"
            fi
        fi
    fi

    if [[ -z "$ANDROID_NDK_ROOT" ]] || [[ ! -d "$ANDROID_NDK_ROOT" ]]; then
        echo "WARNING: Android NDK not found in $ANDROID_HOME/ndk. Attempting to install latest NDK..."
        yes | sdkmanager "ndk;29.0.14206865"
        export ANDROID_NDK_ROOT="$ANDROID_HOME/ndk/29.0.14206865"
    fi

    export ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-26}"

    # Map host_arch to Android target triples
    # Market Analysis 2026:
    # 1. arm64-v8a (aarch64): Modern standard for 64-bit devices, AI processing, and security.
    # 2. armeabi-v7a (armv7a): Legacy/budget tier. Dropped by flagships but persists in IoT/ultra-budget.
    # 3. x86_64: Primarily for Android Studio emulators and specialized ChromeOS devices.
    # 4. x86 (i686): Removed as native x86 devices are effectively extinct.
    case "$host_arch" in
        "x86_64")
            export host_arch="x86_64"
            export cmake_host_arch="x86_64"
            export host_target="x86_64-linux-android"
            export rust_target="x86_64-linux-android"
            export clang_arch="x86_64"
            export aar_arch="x86_64"
            ;;
        "aarch64"|"arm64"|"arm64-v8a")
            export host_arch="aarch64"
            export cmake_host_arch="aarch64"
            export host_target="aarch64-linux-android"
            export rust_target="aarch64-linux-android"
            export clang_arch="aarch64"
            export aar_arch="arm64-v8a"
            ;;
        "armv7a"|"arm"|"armeabi-v7a")
            export host_arch="armv7a"
            export cmake_host_arch="armv7-a"
            export host_target="armv7a-linux-androideabi"
            export rust_target="armv7-linux-androideabi"
            export clang_arch="arm"
            export aar_arch="armeabi-v7a"
            ;;
        *)
            exit_message 1 "setup_android_environment: Unsupported host arch '$host_arch' for Android"
            ;;
    esac

    export dependency_install_prefix="$work_dir/libraries"
    export install_pkgconfig_dir="${dependency_install_prefix}/lib/pkgconfig"

    local os_type=$(uname -s | tr '[:upper:]' '[:lower:]')
    export toolchain_bin_path="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/${os_type}-x86_64/bin"
    export toolchain_include_path="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/${os_type}-x86_64/sysroot/usr/include"
    export toolchain_lib_path="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/${os_type}-x86_64/sysroot/usr/lib"
    # For Android, cross_prefix points to the clang wrapper which includes the API level
    export clang_target="$host_target"
    if [[ "$host_arch" == "armv7a" ]]; then
        export clang_target="armv7a-linux-androideabi"
    fi
    export cross_prefix="${toolchain_bin_path}/${clang_target}${ANDROID_API_LEVEL}-"
    export CROSS_COMPILE="$host_target-"
    export PKG_CONFIG_PATH="$install_pkgconfig_dir:$ffmpeg_install_prefix/lib/pkgconfig:$toolchain_lib_path/pkgconfig"
    export PATH="$toolchain_bin_path:$original_path:$ffmpeg_install_prefix/bin"

    create_dir "$install_pkgconfig_dir"
    create_dir "$work_dir/pkgconfig"
    create_dir "$dependency_install_prefix/{bin,lib/pkgconfig,include,usr/include}"

    reset_cross_vars
    # Override standard GCC/G++ with Clang wrappers
    export CC="${toolchain_bin_path}/${clang_target}${ANDROID_API_LEVEL}-clang"
    export CXX="${toolchain_bin_path}/${clang_target}${ANDROID_API_LEVEL}-clang++"
    export AR="${toolchain_bin_path}/llvm-ar"
    export AS="${toolchain_bin_path}/llvm-as"
    export NM="${toolchain_bin_path}/llvm-nm"
    export RANLIB="${toolchain_bin_path}/llvm-ranlib"
    export STRIP="${toolchain_bin_path}/llvm-strip"
    export LD="${toolchain_bin_path}/ld.lld"

    export PREFIX="$dependency_install_prefix"
    export build_cross_compile=y

    export android_cflags="$original_cflags -D__ANDROID_API__=$ANDROID_API_LEVEL \
-fPIC \
-Wno-error=implicit-function-declaration \
-Wno-error=int-conversion \
-Wno-error=macro-redefined \
-Wno-macro-redefined \
-Wno-unused-command-line-argument \
-I${toolchain_include_path} \
-I${dependency_install_prefix}/include"
    [[ "$host_arch" == "armv7a" ]] && android_cflags+=" -march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16 "
    
    export CFLAGS="$android_cflags"
    export android_cxxflags="$original_cxxflags $android_cflags"
    export CXXFLAGS="$android_cxxflags"
    export android_cppflags="$original_cppflags -I${toolchain_include_path} -I${dependency_install_prefix}/include"
    export CPPFLAGS="$android_cppflags"
    export android_ldflags="$original_ldflags -L${dependency_install_prefix}/lib -L${toolchain_lib_path}"
    export LDFLAGS="$android_ldflags"
}

setup_macos_environment() {
    export PATCHDIR="$SCRIPTDIR/macos/patches"
    export dependency_install_prefix="$work_dir/libraries"
    export install_pkgconfig_dir="${dependency_install_prefix}/lib/pkgconfig"
    export toolchain_sys="macosx"
    export PKG_CONFIG_PATH="$install_pkgconfig_dir:$ffmpeg_install_prefix/lib/pkgconfig:/usr/local/lib/pkgconfig:/opt/homebrew/lib/pkgconfig"
    export SDKROOT=$(xcrun --sdk "$toolchain_sys" --show-sdk-path)
    export MIN_MACOS_VERSION="13.0"

    case "$host_arch" in
        "x86_64")
            export host_arch="x86_64"
            export cmake_host_arch="x86_64"
            export build_cross_compile=y
            export PATH="$original_path"
            export host_target="x86_64-apple-darwin"
            export rust_target="x86_64-apple-darwin"
            export cflags_target="x86_64-apple-darwin$MIN_MACOS_VERSION"
            export macos_version_flag="-mmacosx-version-min=$MIN_MACOS_VERSION"
            ;;
        "aarch64"|"arm64")
            export host_arch="arm64"
            export cmake_host_arch="arm64"
            export meson_cpu_family="aarch64"
            export PATH="$ffmpeg_install_prefix/bin:$dependency_install_prefix/bin:$original_path"
            export host_target="arm64-apple-darwin"
            export rust_target="aarch64-apple-darwin"
            export cflags_target="arm64-apple-darwin$MIN_MACOS_VERSION"
            export macos_version_flag="-mmacosx-version-min=$MIN_MACOS_VERSION"
            ;;
        *)
            exit_message 1 "setup_macos_environment: Unsupported host arch '$host_arch' for $host_platform"
            ;;
    esac
    
    export macos_cflags="$original_cflags -Wno-pedantic -arch $host_arch -I${dependency_install_prefix}/include -isysroot $SDKROOT $macos_version_flag -target $cflags_target"
    export CFLAGS="$macos_cflags"
    export macos_cppflags="$original_cppflags -arch $host_arch -I${dependency_install_prefix}/include -DMACOS -isysroot $SDKROOT $macos_version_flag -target $cflags_target"
    export CPPFLAGS="$macos_cppflags"
    export macos_cxxflags="$original_cxxflags -arch $host_arch -I${dependency_install_prefix}/include -isysroot $SDKROOT $macos_version_flag -target $cflags_target"
    export CXXFLAGS="$macos_cxxflags"
    export macos_ldflags="$original_ldflags -arch $host_arch -L${dependency_install_prefix}/lib -isysroot $SDKROOT $macos_version_flag -target $cflags_target"
    export LDFLAGS="$macos_ldflags"
    export DYLD_LIBRARY_PATH="${dependency_install_prefix}/lib:$DYLD_LIBRARY_PATH"

    export CC="$(xcrun --sdk "$toolchain_sys" --find clang)"
    export CXX="$(xcrun --sdk "$toolchain_sys" --find clang++)"
    export AR="$(xcrun --sdk "$toolchain_sys" --find ar)"
    export AS="$(xcrun --sdk "$toolchain_sys" --find as)"
    export RANLIB="$(xcrun --sdk "$toolchain_sys" --find ranlib)"
    export LD="$(xcrun --sdk "$toolchain_sys" --find ld)"
    export STRIP="$(xcrun --sdk "$toolchain_sys" --find strip)"
    export NM="$(xcrun --sdk "$toolchain_sys" --find nm)"
    export LIPO="$(xcrun --sdk "$toolchain_sys" --find lipo)"
    
    create_dir "$install_pkgconfig_dir"
    create_dir "$work_dir/pkgconfig"
    create_dir "$dependency_install_prefix/{bin,lib/pkgconfig,include,usr/include}"
}

setup_ios_environment() {
    export toolchain_sys="${1:-"iphoneos"}"
    export PATCHDIR="$SCRIPTDIR/ios/patches"
    export dependency_install_prefix="$work_dir/libraries"
    export install_pkgconfig_dir="${dependency_install_prefix}/lib/pkgconfig"

    # SDK setup — toolchain_sys must be set to 'iphoneos' or 'iphonesimulator' before calling
    export IOS_SDK_PATH="$(xcrun --sdk "$toolchain_sys" --show-sdk-path)"
    export SDKROOT="$IOS_SDK_PATH"
    export IOS_SYSROOT="$IOS_SDK_PATH"

    export PKG_CONFIG_PATH="$install_pkgconfig_dir:$ffmpeg_install_prefix/lib/pkgconfig"
    export PATH="$original_path"

    export MIN_IOS_VERSION="13.0"

    case "$host_arch" in
        "aarch64"|"arm64")
            export host_arch="arm64"
            export cmake_host_arch="arm64"
            export meson_cpu_family="aarch64"
            export ios_arch="arm64"
            if [ "$toolchain_sys" = "iphonesimulator" ]; then
                export host_target="arm64-apple-ios-simulator"
                export rust_target="aarch64-apple-ios-sim"
                export cflags_target="arm64-apple-ios${MIN_IOS_VERSION}-simulator"
            else
                export host_target="arm64-apple-ios"
                export rust_target="aarch64-apple-ios"
                export cflags_target="arm64-apple-ios${MIN_IOS_VERSION}"
            fi
            ;;
        *)
            exit_message 1 "setup_ios_environment: Unsupported host arch '$host_arch' for $host_platform"
            ;;
    esac

    reset_cross_vars

    # Cross-compilation tools
    export cross_prefix="$(xcrun --sdk "$toolchain_sys" --find clang)-"
    export CC="$(xcrun --sdk "$toolchain_sys" --find clang)"
    export CXX="$(xcrun --sdk "$toolchain_sys" --find clang++)"
    export AR="$(xcrun --sdk "$toolchain_sys" --find ar)"
    export AS="$(xcrun --sdk "$toolchain_sys" --find as)"
    export RANLIB="$(xcrun --sdk "$toolchain_sys" --find ranlib)"
    export LD="$(xcrun --sdk "$toolchain_sys" --find ld)"
    export STRIP="$(xcrun --sdk "$toolchain_sys" --find strip)"
    export NM="$(xcrun --sdk "$toolchain_sys" --find nm)"

    if [ "$toolchain_sys" = "iphonesimulator" ]; then
        export ios_version_flag="-mios-simulator-version-min=$MIN_IOS_VERSION"
        export ios_cppflags="$original_cppflags -arch $ios_arch -I${dependency_install_prefix}/include -DIOS -DIOS_SIMULATOR"
    else
        export ios_version_flag="-miphoneos-version-min=$MIN_IOS_VERSION"
        export ios_cppflags="$original_cppflags -arch $ios_arch -I${dependency_install_prefix}/include -DIOS"
    fi

    export CPPFLAGS="$ios_cppflags"
    export ios_cflags="$original_cflags -arch $ios_arch -I${dependency_install_prefix}/include $ios_version_flag -target $cflags_target -isysroot $IOS_SYSROOT"
    export CFLAGS="$ios_cflags"
    export ios_cxxflags="$original_cxxflags -arch $ios_arch -I${dependency_install_prefix}/include"
    export CXXFLAGS="$ios_cxxflags"
    export ios_ldflags="$original_ldflags -arch $ios_arch -L${dependency_install_prefix}/lib $ios_version_flag -target $cflags_target -isysroot $IOS_SYSROOT"
    export LDFLAGS="$ios_ldflags"

    export PREFIX="$dependency_install_prefix"
    export build_cross_compile=y

    create_dir "$install_pkgconfig_dir"
    create_dir "$work_dir/pkgconfig"
    create_dir "$dependency_install_prefix/{bin,lib/pkgconfig,include,usr/include}"
}

setup_tvos_environment() {
    # Default to appletvos if no argument provided
    export toolchain_sys="${1:-"appletvos"}"
    export PATCHDIR="$SCRIPTDIR/tvos/patches"
    export dependency_install_prefix="$work_dir/libraries"
    export install_pkgconfig_dir="${dependency_install_prefix}/lib/pkgconfig"

    # SDK setup — toolchain_sys must be 'appletvos' or 'appletvsimulator'
    export TVOS_SDK_PATH="$(xcrun --sdk "$toolchain_sys" --show-sdk-path)"
    export SDKROOT="$TVOS_SDK_PATH"
    export TVOS_SYSROOT="$TVOS_SDK_PATH"

    export PKG_CONFIG_PATH="$install_pkgconfig_dir:$ffmpeg_install_prefix/lib/pkgconfig"
    export PATH="$original_path"

    # Minimum tvOS version (check your deployment target requirements)
    export MIN_TVOS_VERSION="13.0"

    case "$host_arch" in
        "aarch64"|"arm64")
            export host_arch="arm64"
            export cmake_host_arch="arm64"
            export meson_cpu_family="aarch64"
            export tvos_arch="arm64"
            if [ "$toolchain_sys" = "appletvsimulator" ]; then
                export host_target="arm64-apple-tvos-simulator"
                export rust_target="aarch64-apple-tvos-sim"
                export cflags_target="arm64-apple-tvos${MIN_TVOS_VERSION}-simulator"
            else
                export host_target="arm64-apple-tvos"
                export rust_target="aarch64-apple-tvos"
                export cflags_target="arm64-apple-tvos${MIN_TVOS_VERSION}"
            fi
            ;;
        *)
            exit_message 1 "setup_tvos_environment: Unsupported host arch '$host_arch'"
            ;;
    esac

    reset_cross_vars

    # Cross-compilation tools
    export CC="$(xcrun --sdk "$toolchain_sys" --find clang)"
    export CXX="$(xcrun --sdk "$toolchain_sys" --find clang++)"
    export AR="$(xcrun --sdk "$toolchain_sys" --find ar)"
    export AS="$(xcrun --sdk "$toolchain_sys" --find as)"
    export RANLIB="$(xcrun --sdk "$toolchain_sys" --find ranlib)"
    export LD="$(xcrun --sdk "$toolchain_sys" --find ld)"
    export STRIP="$(xcrun --sdk "$toolchain_sys" --find strip)"
    export NM="$(xcrun --sdk "$toolchain_sys" --find nm)"

    if [ "$toolchain_sys" = "appletvsimulator" ]; then
        # Version flag changes from -mios to -mtvos
        export tvos_version_flag="-mtvos-simulator-version-min=$MIN_TVOS_VERSION"
        export tvos_cppflags="$original_cppflags -arch $tvos_arch -I${dependency_install_prefix}/include -DTVOS -DTVOS_SIMULATOR"
    else
        export tvos_version_flag="-mtvos-version-min=$MIN_TVOS_VERSION"
        export tvos_cppflags="$original_cppflags -arch $tvos_arch -I${dependency_install_prefix}/include -DTVOS"
    fi

    export CPPFLAGS="$tvos_cppflags"
    export tvos_cflags="$original_cflags -arch $tvos_arch -I${dependency_install_prefix}/include $tvos_version_flag -target $cflags_target -isysroot $TVOS_SYSROOT"
    export CFLAGS="$tvos_cflags"
    export tvos_cxxflags="$original_cxxflags -arch $tvos_arch -I${dependency_install_prefix}/include"
    export CXXFLAGS="$tvos_cxxflags"
    export tvos_ldflags="$original_ldflags -arch $tvos_arch -L${dependency_install_prefix}/lib $tvos_version_flag -target $cflags_target -isysroot $TVOS_SYSROOT"
    export LDFLAGS="$tvos_ldflags"

    export PREFIX="$dependency_install_prefix"
    export build_cross_compile=y

    create_dir "$install_pkgconfig_dir"
    create_dir "$work_dir/pkgconfig"
    create_dir "$dependency_install_prefix/{bin,lib/pkgconfig,include,usr/include}"
}

iswindows() {
  if [[ "$host_platform" == "windows" ]]; then
    return 0
  fi
  return 1
}

islinux() {
  if [[ "$host_platform" == "linux" ]]; then
    return 0
  fi
  return 1
}

isandroid() {
  if [[ "$host_platform" == "android" ]]; then
    return 0
  fi
  return 1
}

ismacos() {
  if [[ "$host_platform" == "macos" ]]; then
    return 0
  fi
  return 1
}

isios() {
  if [[ "$host_platform" == "ios" || "$host_platform" == "iphonesimulator" ]]; then
    return 0
  fi
  return 1
}

isiossimulator() {
  if [[ "$host_platform" == "iphonesimulator" ]]; then
    return 0
  fi
  return 1
}

istvos() {
  if [[ "$host_platform" == "tvos" || "$host_platform" == "appletvos" || "$host_platform" == "appletvsimulator" ]]; then
    return 0
  fi
  return 1
}

istvossimulator() {
  if [[ "$host_platform" == "appletvsimulator" ]]; then
    return 0
  fi
  return 1
}

cross_windres() {
  if iswindows; then
    if truthy "$1"; then
      if [[ -f "${cross_prefix}windres.bak" ]]; then
        mv -f "${cross_prefix}windres.bak" "${cross_prefix}windres"
      fi
      export WINDRES=${cross_prefix}windres
      reset_cflags
    else
      if [[ -f "${cross_prefix}windres" ]]; then
        mv -f "${cross_prefix}windres" "${cross_prefix}windres.bak"
      fi
      export CFLAGS="$CFLAGS -D__NO_WINDRES__"
      export WINDRES=
    fi
  fi
}

get_compiler_flags() {
  echo "CC=$CC \
AR=$AR \
AS=$AS \
RANLIB=$RANLIB \
LD=$LD \
STRIP=$STRIP \
CXX=$CXX \
WINDRES=$WINDRES \
CROSS_COMPILE=$CROSS_COMPILE"
}

clear_cross_vars() {
  local var="$1"
  [[ -z $var || $var == CROSS_COMPILE ]] && export CROSS_COMPILE=
  [[ -z $var || $var == CC ]] && export CC=
  [[ -z $var || $var == CXX ]] && export CXX=
  [[ -z $var || $var == AR ]] && export AR=
  [[ -z $var || $var == AS ]] && export AS=
  [[ -z $var || $var == RANLIB ]] && export RANLIB=
  [[ -z $var || $var == LD ]] && export LD=
  [[ -z $var || $var == STRIP ]] && export STRIP=
  [[ -z $var || $var == WINDRES ]] && export WINDRES=
}

native_cross_vars() {
  if [[ "$BUILD_OS" == "linux" ]]; then
    export CROSS_COMPILE=
    export CC=gcc
    export CXX=g++
    export AR=ar
    export AS=as
    export RANLIB=ranlib
    export LD=ld
    export STRIP=strip
    export NM=nm
    export PKG_CONFIG_PATH="$original_pkg_config_path:/usr/lib/$host_target/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
  elif [[ "$BUILD_OS" == "macos" ]]; then
    export CROSS_COMPILE=
    export CC="$(xcrun --sdk macosx --find clang)"
    export CXX="$(xcrun --sdk macosx --find clang++)"
    export AR="$(xcrun --sdk macosx --find ar)"
    export AS="$(xcrun --sdk macosx --find as)"
    export STRIP="$(xcrun --sdk macosx --find strip)"
    export NM="$(xcrun --sdk macosx --find nm)"
    export RANLIB="$(xcrun --sdk macosx --find ranlib)"
    export LD="$(xcrun --sdk macosx --find ld)"
    export PKG_CONFIG_PATH="$original_pkg_config_path:/usr/local/lib/pkgconfig:/opt/homebrew/lib/pkgconfig"
    export SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
    export CFLAGS="-Wno-pedantic -arch $BUILD_ARCH"
    export CPPFLAGS="-arch $BUILD_ARCH -DMACOS"
    export CXXFLAGS="-arch $BUILD_ARCH"
    export LDFLAGS="-arch $BUILD_ARCH"
  fi
}

reset_cross_vars() {
  if iswindows; then
    export CROSS_COMPILE="$host_target-"
    export CC=${cross_prefix}gcc
    export CXX=${cross_prefix}g++
    export AR=${cross_prefix}ar
    export AS=${cross_prefix}as
    export RANLIB=${cross_prefix}ranlib
    export LD=${cross_prefix}ld
    export STRIP=${cross_prefix}strip
    export WINDRES="/usr/bin/true"
    export RC="/usr/bin/true"
    export CMAKE_OPTS="-DCMAKE_RC_COMPILER=/bin/false"
  elif isandroid; then
    export CC="${toolchain_bin_path}/${clang_target}${ANDROID_API_LEVEL}-clang"
    export CXX="${toolchain_bin_path}/${clang_target}${ANDROID_API_LEVEL}-clang++"
    export AR="${toolchain_bin_path}/llvm-ar"
    export AS="${toolchain_bin_path}/llvm-as"
    export NM="${toolchain_bin_path}/llvm-nm"
    export RANLIB="${toolchain_bin_path}/llvm-ranlib"
    export STRIP="${toolchain_bin_path}/llvm-strip"
    export LD="${toolchain_bin_path}/ld.lld"
  elif isios || ismacos || istvos; then
    export CC="$(xcrun --sdk "$toolchain_sys" --find clang)"
    export CXX="$(xcrun --sdk "$toolchain_sys" --find clang++)"
    export AR="$(xcrun --sdk "$toolchain_sys" --find ar)"
    export AS="$(xcrun --sdk "$toolchain_sys" --find as)"
    export RANLIB="$(xcrun --sdk "$toolchain_sys" --find ranlib)"
    export LD="$(xcrun --sdk "$toolchain_sys" --find ld)"
    export STRIP="$(xcrun --sdk "$toolchain_sys" --find strip)"
    export NM="$(xcrun --sdk "$toolchain_sys" --find nm)"
  fi
}

reset_cflags() {
	if iswindows; then
    export CFLAGS="$windows_cflags"
  elif islinux; then
    export CFLAGS="$linux_cflags"
  elif isandroid; then
    export CFLAGS="$android_cflags"
  elif ismacos; then
    export CFLAGS="$macos_cflags"
  elif isios; then
    export CFLAGS="$ios_cflags"
  elif istvos; then
    export CFLAGS="$tvos_cflags"
  elif [[ -n "$original_cflags" ]]; then
    export CFLAGS="$original_cflags"
  else
    unset CFLAGS
  fi
}

reset_cxxflags() {
	if iswindows; then
    export CXXFLAGS="$windows_cxxflags"
  elif islinux; then
    export CXXFLAGS="$linux_cxxflags"
  elif isandroid; then
    export CXXFLAGS="$android_cxxflags"
  elif ismacos; then
    export CXXFLAGS="$macos_cxxflags"
  elif isios; then
    export CXXFLAGS="$ios_cxxflags"
  elif istvos; then
    export CXXFLAGS="$tvos_cflags"
  elif [[ -n "$original_cxxflags" ]]; then
    export CXXFLAGS="$original_cxxflags"
  else
    unset CXXFLAGS
  fi
}

reset_cppflags() {
	if iswindows; then
    export CPPFLAGS="$windows_cppflags"
  elif islinux; then
    export CPPFLAGS="$linux_cppflags"
  elif isandroid; then
    export CPPFLAGS="$android_cppflags"
  elif ismacos; then
    export CPPFLAGS="$macos_cppflags"
  elif isios; then
    export CPPFLAGS="$ios_cppflags"
  elif istvos; then
    export CPPFLAGS="$tvos_cppflags"
  elif [[ -n "$original_cppflags" ]]; then
    export CPPFLAGS="$original_cppflags"
  else
    unset CPPFLAGS
  fi
}

reset_ldflags() {
	if iswindows; then
    export LDFLAGS="$windows_ldflags"
  elif islinux; then
    export LDFLAGS="$linux_ldflags"
  elif isandroid; then
    export LDFLAGS="$android_ldflags"
  elif ismacos; then
    export LDFLAGS="$macos_ldflags"
  elif isios; then
    export LDFLAGS="$ios_ldflags"
  elif istvos; then
    export LDFLAGS="$tvos_ldflags"
  elif [[ -n "$original_ldflags" ]]; then
    export LDFLAGS="$original_ldflags"
  else
    unset LDFLAGS
  fi
}

reset_allflags() {
  reset_cflags
  reset_cppflags
  reset_cxxflags
  reset_ldflags
  unset LIBS
}

get_ffmpeg_directory() {
	local build_type=$1
  local dir_name="${host_name}"
	if [[ -z $build_type ]]; then
		dir_name+="-$build_ffmpeg_type"
  else
		dir_name+="-$build_type"
	fi
  if truthy "$do_debug_build"; then
    dir_name+="-debug"
  fi
  local is_small=""
  if truthy "$build_small"; then
    is_small="-small"
  fi
  local bundle_type=""
  if [[ -n $(get_bundle_type) ]]; then
    bundle_type="$(get_bundle_type)-"
  fi
  local is_gpl=""
  if truthy "$build_gpl"; then
    is_gpl="-gpl"
  fi
  local is_nonfree=""
  if truthy "$build_nonfree"; then
    is_nonfree="-nonfree"
  fi
  echo "ffmpeg-$bundle_type$dir_name$is_small$is_gpl$is_nonfree"
}

get_ffmpeg_kit_directory() {
  local dir_name="${host_name}-$build_ffmpeg_kit_type"
  if truthy "$do_debug_build"; then
    dir_name+="-debug"
	fi
  local is_small=""
  if truthy "$build_small"; then
    is_small="-small"
  fi
  local bundle_type=""
  if [[ -n $(get_bundle_type) ]]; then
    bundle_type="$(get_bundle_type)-"
  fi
  local is_gpl=""
  if truthy "$build_gpl"; then
    is_gpl="-gpl"
  fi
  local is_nonfree=""
  if truthy "$build_nonfree"; then
    is_nonfree="-nonfree"
  fi
	echo "ffmpeg-kit-$bundle_type$dir_name$is_small$is_gpl$is_nonfree"
}

get_bundle_license() {
  if truthy "$build_gpl"; then
    echo "gpl"
  elif truthy "$build_nonfree"; then
    echo "nonfree"
  else
    echo "lgpl"
  fi
}

get_bundle_directory() {
  local dir_name="${host_name}-$build_ffmpeg_kit_type"
  if truthy "$do_debug_build"; then
    dir_name+="-debug"
	fi
  local is_small=""
  if truthy "$build_small"; then
    is_small="-small"
  fi
  local bundle_type=""
  if [[ -n $(get_bundle_type) ]]; then
    bundle_type="$(get_bundle_type)-"
  fi
	echo "bundle-$bundle_type$dir_name$is_small-$(get_bundle_license)"
}

get_bundle_type() {
  if truthy "$enable_base"; then
    echo "base"
  elif truthy "$audio_bundle"; then
    echo "audio"
  elif truthy "$video_bundle"; then
    echo "video"
  elif truthy "$audio_ai_bundle"; then
    echo "audio_ai"
  elif truthy "$video_ai_bundle"; then
    if truthy "$gpu_support"; then
      echo "video_ai_gpu_$gpu_type"
    else
      echo "video_ai_cpu"
    fi
  elif truthy "$video_hw_bundle"; then
    echo "video_hw"
  elif truthy "$video_ai_hw_bundle"; then
    if truthy "$gpu_support"; then
      echo "video_hw_ai_gpu_$gpu_type"
    else
      echo "video_hw_ai_cpu"
    fi
  elif truthy "$streaming_bundle"; then
    echo "streaming"
  elif truthy "$enable_full"; then
    echo "full"
  else
    echo "custom"
  fi
}

get_cpu_count() {
	echo -e "$cpu_count"
}

get_concurrent_proc() {
  # shellcheck disable=2046
  echo $(( ( $(get_cpu_count) / 3 ) + 1 ))
}

display_version() {
	COMMAND=$(echo -e "$0" | sed -e 's/\.\///g')

	echo -e "\
$COMMAND v$(get_latest_version_from_changelog)
Copyright (c) 2025 Akash Patel\n\
License LGPLv3.0: GNU LGPL version 3 or later\n\
<https://www.gnu.org/licenses/lgpl-3.0.en.html>\n\
This is free software: you can redistribute it and/or modify it under the terms of the \
GNU Lesser General Public License as published by the Free Software Foundation, \
either version 3 of the License, or (at your option) any later version."
}

get_ffmpeg_libavcodec_version() {
	local MAJOR=$(grep -Eo ' LIBAVCODEC_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavcodec/version_major.h | sed -e 's|LIBAVCODEC_VERSION_MAJOR||g;s| ||g')
	local MINOR=$(grep -Eo ' LIBAVCODEC_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libavcodec/version.h | sed -e 's|LIBAVCODEC_VERSION_MINOR||g;s| ||g')
	local MICRO=$(grep -Eo ' LIBAVCODEC_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libavcodec/version.h | sed -e 's|LIBAVCODEC_VERSION_MICRO||g;s| ||g')

	echo -e "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libavcodec_major_version() {
	local MAJOR=$(grep -Eo ' LIBAVCODEC_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavcodec/version_major.h | sed -e 's|LIBAVCODEC_VERSION_MAJOR||g;s| ||g')

	echo -e "${MAJOR}"
}

get_ffmpeg_libavdevice_version() {
	local MAJOR=$(grep -Eo ' LIBAVDEVICE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavdevice/version_major.h | sed -e 's|LIBAVDEVICE_VERSION_MAJOR||g;s| ||g')
	local MINOR=$(grep -Eo ' LIBAVDEVICE_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libavdevice/version.h | sed -e 's|LIBAVDEVICE_VERSION_MINOR||g;s| ||g')
	local MICRO=$(grep -Eo ' LIBAVDEVICE_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libavdevice/version.h | sed -e 's|LIBAVDEVICE_VERSION_MICRO||g;s| ||g')

	echo -e "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libavdevice_major_version() {
	local MAJOR=$(grep -Eo ' LIBAVDEVICE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavdevice/version_major.h | sed -e 's|LIBAVDEVICE_VERSION_MAJOR||g;s| ||g')

	echo -e "${MAJOR}"
}

get_ffmpeg_libavfilter_version() {
	local MAJOR=$(grep -Eo ' LIBAVFILTER_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavfilter/version_major.h | sed -e 's|LIBAVFILTER_VERSION_MAJOR||g;s| ||g')
	local MINOR=$(grep -Eo ' LIBAVFILTER_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libavfilter/version.h | sed -e 's|LIBAVFILTER_VERSION_MINOR||g;s| ||g')
	local MICRO=$(grep -Eo ' LIBAVFILTER_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libavfilter/version.h | sed -e 's|LIBAVFILTER_VERSION_MICRO||g;s| ||g')

	echo -e "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libavfilter_major_version() {
	local MAJOR=$(grep -Eo ' LIBAVFILTER_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavfilter/version_major.h | sed -e 's|LIBAVFILTER_VERSION_MAJOR||g;s| ||g')

	echo -e "${MAJOR}"
}

get_ffmpeg_libavformat_version() {
	local MAJOR=$(grep -Eo ' LIBAVFORMAT_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavformat/version_major.h | sed -e 's|LIBAVFORMAT_VERSION_MAJOR||g;s| ||g')
	local MINOR=$(grep -Eo ' LIBAVFORMAT_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libavformat/version.h | sed -e 's|LIBAVFORMAT_VERSION_MINOR||g;s| ||g')
	local MICRO=$(grep -Eo ' LIBAVFORMAT_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libavformat/version.h | sed -e 's|LIBAVFORMAT_VERSION_MICRO||g;s| ||g')

	echo -e "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libavformat_major_version() {
	local MAJOR=$(grep -Eo ' LIBAVFORMAT_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavformat/version_major.h | sed -e 's|LIBAVFORMAT_VERSION_MAJOR||g;s| ||g')

	echo -e "${MAJOR}"
}

get_ffmpeg_libavutil_version() {
	local MAJOR=$(grep -Eo ' LIBAVUTIL_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavutil/version.h | sed -e 's|LIBAVUTIL_VERSION_MAJOR||g;s| ||g')
	local MINOR=$(grep -Eo ' LIBAVUTIL_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libavutil/version.h | sed -e 's|LIBAVUTIL_VERSION_MINOR||g;s| ||g')
	local MICRO=$(grep -Eo ' LIBAVUTIL_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libavutil/version.h | sed -e 's|LIBAVUTIL_VERSION_MICRO||g;s| ||g')

	echo -e "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libavutil_major_version() {
	local MAJOR=$(grep -Eo ' LIBAVUTIL_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavutil/version_major.h | sed -e 's|LIBAVUTIL_VERSION_MAJOR||g;s| ||g')

	echo -e "${MAJOR}"
}

get_ffmpeg_libswresample_version() {
	local MAJOR=$(grep -Eo ' LIBSWRESAMPLE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libswresample/version_major.h | sed -e 's|LIBSWRESAMPLE_VERSION_MAJOR||g;s| ||g')
	local MINOR=$(grep -Eo ' LIBSWRESAMPLE_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libswresample/version.h | sed -e 's|LIBSWRESAMPLE_VERSION_MINOR||g;s| ||g')
	local MICRO=$(grep -Eo ' LIBSWRESAMPLE_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libswresample/version.h | sed -e 's|LIBSWRESAMPLE_VERSION_MICRO||g;s| ||g')

	echo -e "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libswresample_major_version() {
	local MAJOR=$(grep -Eo ' LIBSWRESAMPLE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libswresample/version_major.h | sed -e 's|LIBSWRESAMPLE_VERSION_MAJOR||g;s| ||g')

	echo -e "${MAJOR}"
}

get_ffmpeg_libswscale_version() {
	local MAJOR=$(grep -Eo ' LIBSWSCALE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libswscale/version_major.h | sed -e 's|LIBSWSCALE_VERSION_MAJOR||g;s| ||g')
	local MINOR=$(grep -Eo ' LIBSWSCALE_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libswscale/version.h | sed -e 's|LIBSWSCALE_VERSION_MINOR||g;s| ||g')
	local MICRO=$(grep -Eo ' LIBSWSCALE_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libswscale/version.h | sed -e 's|LIBSWSCALE_VERSION_MICRO||g;s| ||g')

	echo -e "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libswscale_major_version() {
	local MAJOR=$(grep -Eo ' LIBSWSCALE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libswscale/version_major.h | sed -e 's|LIBSWSCALE_VERSION_MAJOR||g;s| ||g')

	echo -e "${MAJOR}"
}

#
# 1. LIBRARY NAME
#
get_ffmpeg_library_version() {
	case $1 in
	libavcodec)
		echo -e "$(get_ffmpeg_libavcodec_version)"
		;;
	libavdevice)
		echo -e "$(get_ffmpeg_libavdevice_version)"
		;;
	libavfilter)
		echo -e "$(get_ffmpeg_libavfilter_version)"
		;;
	libavformat)
		echo -e "$(get_ffmpeg_libavformat_version)"
		;;
	libavutil)
		echo -e "$(get_ffmpeg_libavutil_version)"
		;;
	libswresample)
		echo -e "$(get_ffmpeg_libswresample_version)"
		;;
	libswscale)
		echo -e "$(get_ffmpeg_libswscale_version)"
		;;
	esac
}

#
# 1. LIBRARY NAME
#
get_ffmpeg_library_major_version() {
	case $1 in
	libavcodec)
		echo -e "$(get_ffmpeg_libavcodec_major_version)"
		;;
	libavdevice)
		echo -e "$(get_ffmpeg_libavdevice_major_version)"
		;;
	libavfilter)
		echo -e "$(get_ffmpeg_libavfilter_major_version)"
		;;
	libavformat)
		echo -e "$(get_ffmpeg_libavformat_major_version)"
		;;
	libavutil)
		echo -e "$(get_ffmpeg_libavutil_major_version)"
		;;
	libswresample)
		echo -e "$(get_ffmpeg_libswresample_major_version)"
		;;
	libswscale)
		echo -e "$(get_ffmpeg_libswscale_major_version)"
		;;
	esac
}

#
# 1. <library name>
#
autoreconf_library() {
	echo -e "\nINFO: Running full autoreconf for $1\n" >>"$LOG_FILE"
	
  local sys_ver
  sys_ver=$(libtool --version 2>/dev/null | head -n1 | awk '{print $NF}')
  local auto_ver
  auto_ver=$(autoreconf --version 2>/dev/null | head -n1 | awk '{print $NF}')

  local touch_prefix="${host_name}${touch_postfix}already"
	local touch_name=$(get_small_touchfile_name "${touch_prefix}_autoreconf" "libtool: $sys_ver autoreconf: $auto_ver")

  if [[ -f "no.autoreconf" || -f "$touch_name" ]]; then
    echo "INFO: Autoreconf already ran or not needed. Skipping." >>"$LOG_FILE"
    return
  fi

  #rm -rf aclocal.m4 autom4te.cache configure Makefile.in src/Makefile.in m4
	# FORCE INSTALL
	autoreconf -fiv > >(redirect_output) 2>&1
  
	local EXTRACT_RC=$?
	if [[ ${EXTRACT_RC} -eq 0 ]]; then
		echo -e "\nDEBUG: autoreconf completed successfully for $1\n" >>"$LOG_FILE"
    create_touch_file 0 "$touch_name"
		return
	fi

	echo -e "\nDEBUG: Full autoreconf failed. Running full autoreconf with include for $1\n" >>"$LOG_FILE"
	#rm -rf aclocal.m4 autom4te.cache configure Makefile.in src/Makefile.in m4
	# FORCE INSTALL WITH m4
	autoreconf -fiv -I m4 > >(redirect_output) 2>&1

	EXTRACT_RC=$?
	if [[ ${EXTRACT_RC} -eq 0 ]]; then
		echo -e "\nDEBUG: autoreconf completed successfully for $1\n" >>"$LOG_FILE"
    create_touch_file 0 "$touch_name"
		return
	fi

	echo -e "\nDEBUG: Full autoreconf with include failed. Running autoreconf without force for $1\n" >>"$LOG_FILE"
	#rm -rf aclocal.m4 autom4te.cache configure Makefile.in src/Makefile.in m4
	# INSTALL WITHOUT FORCE
	autoreconf -iv > >(redirect_output) 2>&1

	EXTRACT_RC=$?
	if [[ ${EXTRACT_RC} -eq 0 ]]; then
		echo -e "\nDEBUG: autoreconf completed successfully for $1\n" >>"$LOG_FILE"
    create_touch_file 0 "$touch_name"
		return
	fi

	echo -e "\nDEBUG: Autoreconf without force failed. Running autoreconf without force with include for $1\n" >>"$LOG_FILE"
	#rm -rf aclocal.m4 autom4te.cache configure Makefile.in src/Makefile.in m4
	# INSTALL WITHOUT FORCE WITH m4
	autoreconf --iv -I m4 > >(redirect_output) 2>&1

	EXTRACT_RC=$?
	if [[ ${EXTRACT_RC} -eq 0 ]]; then
		echo -e "\nDEBUG: autoreconf completed successfully for $1\n" >>"$LOG_FILE"
    create_touch_file 0 "$touch_name"
		return
	fi

	echo -e "\nDEBUG: Autoreconf without force with include failed. Running default autoreconf for $1\n" >>"$LOG_FILE"
	#rm -rf aclocal.m4 autom4te.cache configure Makefile.in src/Makefile.in m4
	# INSTALL DEFAULT
	(autoreconf) > >(redirect_output) 2>&1

	EXTRACT_RC=$?
	if [[ ${EXTRACT_RC} -eq 0 ]]; then
		echo -e "\nDEBUG: autoreconf completed successfully for $1\n" >>"$LOG_FILE"
    create_touch_file 0 "$touch_name"
		return
	fi

	echo -e "\nDEBUG: Default autoreconf failed. Running default autoreconf with include for $1\n" >>"$LOG_FILE"
	#rm -rf aclocal.m4 autom4te.cache configure Makefile.in src/Makefile.in m4
	# INSTALL DEFAULT WITH m4
	autoreconf -v -I m4 > >(redirect_output) 2>&1

	EXTRACT_RC=$?
	if [[ ${EXTRACT_RC} -eq 0 ]]; then
		echo -e "\nDEBUG: autoreconf completed successfully for $1\n" >>"$LOG_FILE"
    create_touch_file 0 "$touch_name"
		return
	else
		echo -e "\nDEBUG: Default autoreconf with include for $1 failed\n" >>"$LOG_FILE"
	fi
  return "${EXTRACT_RC}"
}

clean_ffmpeg_builds() {
	pick_host_platform "$host_platform"
	pick_host_arch "$host_arch"
	pick_clean_type
  if [[ -z $host_name ]]; then
		exit_message 1 "clean_ffmpeg_builds: no build flavor provided"
	fi
	setup_build_environment
  clean_builds "$clean_type" "$host_name"
  exit_message 0 "clean_ffmpeg_builds: Done cleaning builds"
}

clean_builds() {
	export clean_type=${1:-clean_type} # comma-separated list of components to clean
  local build_flavor=${2:-host_name}
  local clean_types=()
  IFS=',' read -ra clean_types <<< "$clean_type"
  echo -e "WARNING: Executing clean for ${clean_types[*]} and $host_name"
	if [[ " ${clean_types[*]} " =~ " all " ]] || [[ " ${clean_types[*]} " =~ " ffmpeg " ]]; then
		echo -e "INFO: Deleting ${ffmpeg_install_prefix}..."
		remove_path -rf "${ffmpeg_install_prefix}"
	fi
	if [[ " ${clean_types[*]} " =~ " all " ]] || [[ " ${clean_types[*]} " =~ " kit " ]]; then
		echo -e "INFO: Deleting ${ffmpeg_kit_install}..."
		remove_path -rf "${ffmpeg_kit_install}"
	fi
	if [[ " ${clean_types[*]} " =~ " all " ]] || [[ " ${clean_types[*]} " =~ " bundle " ]]; then
		echo -e "INFO: Deleting ${ffmpeg_kit_bundle}..."
		remove_path -rf "${ffmpeg_kit_bundle}"
	fi
}

list_libraries() {
  download_ffmpeg
  change_dir "$src_dir/ffmpeg"
  ./configure --help
  exit_message 0 "list_libraries: Done listing libraries"
}

set_box_memory_size_bytes() {
  if [[ "$(uname)" == "Darwin" ]]; then
    local ram_kilobytes=$(sysctl -n hw.memsize | awk '{print $1}')
    local swap_kilobytes=0
  else
    local ram_kilobytes=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local swap_kilobytes=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
  fi
	box_memory_size_bytes=$((ram_kilobytes * 1024 + swap_kilobytes * 1024))
}

function sortable_version { echo -e "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }

at_least_required_version() { # params: required actual
	local sortable_required=$(sortable_version "$1")
	sortable_required=$(echo -e "$sortable_required" | sed -e  's/^0*//') # remove preceding zeroes, which bash later interprets as octal or screwy
	local sortable_actual=$(sortable_version "$2")
	sortable_actual=$(echo -e "$sortable_actual" | sed -e  's/^0*//')
	[[ "$sortable_actual" -ge "$sortable_required" ]]
}

apt_not_installed() {
	for x in "$@"; do
		if ! check_package "$x"; then
			need_install="$need_install $x"
		fi
	done
	echo -e "$need_install"
}

check_package() {
  determine_distro
  local pkg_name="$1"
  local valid_name=""

  if hash "$pkg_name" &>/dev/null; then
    echo "INFO: $pkg_name already installed" >>"$LOG_FILE"
    return 0
  fi
  if $CHECK_INSTALLED_CMD "$pkg_name" &>/dev/null; then
    echo "INFO: $pkg_name already installed" >>"$LOG_FILE"
    return 0
  fi
  if valid_name=$(validate_package "$pkg_name"); then
    if $CHECK_INSTALLED_CMD "$valid_name" &>/dev/null; then
        echo "INFO: $valid_name already installed" >>"$LOG_FILE"
        return 0
    fi
  fi
  return 1
}

get_missing_packages() {
  local missing_packages=()
  for package in "$@"; do
		  if [[ -n $package ]] && ! check_package "$package"; then
        missing_packages+=("$package")
      fi
	done
  for pkg in "${missing_packages[@]}"; do
      echo "$pkg"
  done
}

check_missing_packages() {
  determine_distro
  if ! truthy "$skip_package_check"; then
    # apt install autoconf-archive autoconf autogen automake autopoint bc bison bzip2 cargo clang cmake 
    # coreutils curl cvs ed ed flex g++ gcc gettext git gperf help2man libtool libtool-bin make meson nasm
    # p7zip-full patch pax pkg-config python3 python3-setuptools python3-venv ragel subversion unzip wget
    # xz-utils yasm zlib1g-dev libglib2.0-dev libglib2.0-dev-bin sudo apt install binutils llvm lld
    # xutils-dev python3-numpy cython3
    # zeranoe's build scripts use wget, though we don't here...
    local check_packages=('ragel' 'curl' 'pkg-config' 'make' 'git' 'svn' 'gcc' 'autoconf' 'automake' \
  'yasm' 'cvs' 'flex' 'bison' 'ed' 'pax' 'unzip' 'wget' 'xz' 'nasm' 'gperf' 'autogen' \
  'bzip2' 'python3' 'bc')
    # autoconf-archive is just for leptonica FWIW
    # I'm not actually sure if VENDOR being set to centos is a thing or not. On all the centos boxes I can test on it's not been set at all.
    # that being said, if it where set I would imagine it would be set to centos... And this contition will satisfy the "Is not initially set"
    # case because the above code will assign "redhat" all the time.
    if [ -z "${VENDOR}" ] || [ "${VENDOR}" != "redhat" ] && [ "${VENDOR}" != "centos" ]; then
      check_packages+=('cmake')
    elif [ "${VENDOR}" == "redhat" ]; then
      check_packages+=('libzstd-devel')
    elif [ "${VENDOR}" == "canonical" ]; then
      check_packages+=('zstd' 'cython3' 'xutils-dev' 'python3-venv' 'python3-numpy')
    elif [ "${VENDOR}" == "macos" ]; then
      # also needs 'python@3.10' 'python@3.12' 'python@3.14'
      check_packages+=('libtool' 'texinfo' 'glib' 'llvm' 'lld' 'pipx' 'autoconf-archive' 'bc' 'binutils' 'gpatch' 'gsed' 'coreutils')
    else
      check_packages+=('libtoolize' 'g++' 'patch' 'realpath' 'clang' 'autopoint' 'ld') # the rest of the world
    fi

    if [ "${VENDOR}" != "macos" ]; then
      check_packages+=('makeinfo' 'glib-mkenums' 'ld.lld')
    fi
    # Use hash to check if the packages exist or not. Type is a bash builtin which I'm told behaves differently between different versions of bash.
    ! truthy "$skip_package_check" && mapfile -t missing_packages < <(get_missing_packages "${check_packages[@]}")

    if [ "${VENDOR}" = "redhat" ] || [ "${VENDOR}" = "centos" ]; then
      if [ -n "$(hash cmake 2>&1)" ] && [ -n "$(hash cmake3 2>&1)" ]; then missing_packages=('cmake' "${missing_packages[@]}"); fi
    fi

    if [[ ${#missing_packages[@]} -gt 0 ]]; then
      clear
      echo -e "DEBUG:" | tee -a "$LOG_FILE"
      echo -e "Could not find the following execs (svn is actually package subversion, makeinfo is actually package texinfo if you're missing them): ${missing_packages[*]}" | tee -a "$LOG_FILE"
      echo -e 'Install the missing packages before running this script.' | tee -a "$LOG_FILE"
      
      apt_pkgs='autoconf-archive autoconf autogen automake autopoint bc bison bzip2 cargo clang cmake coreutils curl cvs ed flex g++ gcc gettext git gperf help2man libtool libtool-bin make meson nasm p7zip-full patch pax pkg-config python3 python3-setuptools ragel subversion unzip wget xz-utils yasm zlib1g-dev libglib2.0-dev libglib2.0-dev-bin'

      [[ ${DISTRO,,} == "debian" ]] && apt_pkgs="$apt_pkgs libtool-bin ed" # extra for debian
      case "${DISTRO,,}" in
      *almalinux*)
        echo "AlmaLinux detected"
        ;;
      *ubuntu*)
        echo -e "for ubuntu:" | tee -a "$LOG_FILE"
        echo -e "$ sudo $INSTALL_COMMAND update" | tee -a "$LOG_FILE"
        ubuntu_ver="$(lsb_release -rs)"
        if [ "$(sortable_version "$ubuntu_ver")" -lt "$(sortable_version "24.04")" ]; then
          echo "Ubuntu < 24.04 not supported."
        fi
        if at_least_required_version "22.04" "$ubuntu_ver"; then
          apt_pkgs="$apt_pkgs ninja-build" # needed
        fi
        echo -e "$ sudo $INSTALL_COMMAND install $apt_pkgs -y" | tee -a "$LOG_FILE"
        ;;
      *debian*)
        echo -e "for debian:" | tee -a "$LOG_FILE"
        echo -e "$ sudo $INSTALL_COMMAND update" | tee -a "$LOG_FILE"
        # Debian version is always encoded in the /etc/debian_version
        # This file is deployed via the base-files package which is the essential one - deployed in all installations.
        # See their content for individual debian releases - https://sources.debian.org/src/base-files/
        # Stable releases contain a version number.
        # Testing/Unstable releases contain a textual codename description (e.g. bullseye/sid)
        #
        deb_ver="$(cat /etc/debian_version)"
        # Upcoming codenames taken from https://en.wikipedia.org/wiki/Debian_version_history
        #
        if [[ $deb_ver =~ bullseye ]]; then
          deb_ver="11"
        elif [[ $deb_ver =~ bookworm ]]; then
          deb_ver="12"
        elif [[ $deb_ver =~ trixie ]]; then
          deb_ver="13"
        fi
        if at_least_required_version "10" "$deb_ver"; then
          apt_pkgs="$apt_pkgs python3-distutils" # guess it's no longer built-in, lensfun requires it...
        fi
        if at_least_required_version "11" "$deb_ver"; then
          apt_pkgs="$apt_pkgs python-is-python3" # needed
        fi
        apt_missing="$(apt_not_installed "$apt_pkgs")"
        echo -e "$ sudo $INSTALL_COMMAND install $apt_missing -y" | tee -a "$LOG_FILE"
        ;;
      *macos*)
        xcode-select -s /Library/Developer/CommandLineTools > >(redirect_output) 2>&1
        xcode-select -s /Applications/Xcode.app/Contents/Developer > >(redirect_output) 2>&1
        xcodebuild -license
        ;;
      *)
        echo "check_missing_packages: Build platform: ${DISTRO,,} not supported. The build script may not run correctly on unsupported platforms. Please use a container with Ubuntu >= 24.04 (noble)"
        ;;
      esac
      exit_message 1 "check_missing_packages: couldnt check missing packages"
    fi
  fi
	export REQUIRED_CMAKE_VERSION="3.0.0"
	for cmake_binary in 'cmake' 'cmake3'; do
		# We need to check both binaries the same way because the check for installed packages will work if *only* cmake3 is installed or
		# if *only* cmake is installed.
		# On top of that we ideally would handle the case where someone may have patched their version of cmake themselves, locally, but if
		# the version of cmake required move up to, say, 3.1.0 and the cmake3 package still only pulls in 3.0.0 flat, then the user having manually
		# installed cmake at a higher version wouldn't be detected.
		if hash "$cmake_binary" &>/dev/null; then
			cmake_version="$("${cmake_binary}" --version | sed -e "s#${cmake_binary}##g" | head -n 1 | tr -cd '0-9.\n')"
			if at_least_required_version "${REQUIRED_CMAKE_VERSION}" "${cmake_version}"; then
				export cmake_command="${cmake_binary}"
				break
			else
				echo -e "ERROR: your ${cmake_binary} version is too old ${cmake_version} wanted ${REQUIRED_CMAKE_VERSION}" | tee -a "$LOG_FILE"
			fi
		fi
	done

	# If cmake_command never got assigned then there where no versions found which where sufficient.
	if [ -z "${cmake_command}" ]; then
		exit_message 1 "check_missing_packages: there where no appropriate versions of cmake found on your machine."
	else
		# If cmake_command is set then either one of the cmake's is adequate.
		if [[ $cmake_command != "cmake" ]]; then # don't echo -e if it's the normal default
			echo -e "DEBUG: cmake binary for this build will be ${cmake_command}" | tee -a "$LOG_FILE"
		fi
	fi

	# TODO nasm version :|

	# doing the cut thing with an assigned variable dies on the version of yasm I have installed (which I'm pretty sure is the RHEL default)
	# because of all the trailing lines of stuff
	export REQUIRED_YASM_VERSION="1.2.0" # export ???
	local yasm_binary=yasm
	local yasm_version="$("${yasm_binary}" --version | sed -e "s#${yasm_binary}##g" | head -n 1 | tr -dc '0-9.\n')"
	if ! at_least_required_version "${REQUIRED_YASM_VERSION}" "${yasm_version}"; then
		exit_message 1 "check_missing_packages: your yasm version is too old $yasm_version wanted ${REQUIRED_YASM_VERSION}"
	fi
	# local meson_version=`meson --version`
	# if ! at_least_required_version "0.60.0" "${meson_version}"; then
	# echo -e "your meson version is too old $meson_version wanted 0.60.0"
	# exit_message 1
	# fi
	# also check missing "setup" so it's early LOL

	#check if WSL
	# check WSL for interop setting make sure its disabled
	# check WSL for kernel version look for version 4.19.128 current as of 11/01/2020
	if uname -a | grep -iq -- "-microsoft"; then
		# shellcheck disable=SC2002
		if cat /proc/sys/fs/binfmt_misc/WSLInterop 2>/dev/null | grep -q enabled; then
			echo -e "windows WSL detected: you must first disable 'binfmt' by running this
      sudo bash -c 'echo -e 0 > /proc/sys/fs/binfmt_misc/WSLInterop'
      then try again" | tee -a "$LOG_FILE"
			#exit_message 1
		fi
		export MINIMUM_KERNEL_VERSION="4.19.128"
		KERNVER=$(uname -a | awk -F'[ ]' '{ print $3 }' | awk -F- '{ print $1 }')

		if [ "$(sortable_version "$KERNVER")" -lt "$(sortable_version "$MINIMUM_KERNEL_VERSION")" ]; then
			echo -e "Windows Subsystem for Linux (WSL) detected - kernel not at minumum version required: $MINIMUM_KERNEL_VERSION
      Please update via windows update then try again" | tee -a "$LOG_FILE"
			#exit_message 1
		fi
	fi

}

determine_distro() {
  local os_id=""
  local os_id_like=""

  unset VENDOR
  unset BUILD_OS
  unset BUILD_ARCH
  unset INSTALL_COMMAND
  unset SEARCH_COMMAND

  if [ -f /etc/os-release ]; then
    . /etc/os-release
    os_id="$ID"
    os_id_like="$ID_LIKE"
    DISTRO="$NAME"
  elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    os_id="$DISTRIB_ID"
    DISTRO="$NAME"
  else
    os_id=$(uname -s | tr '[:upper:]' '[:lower:]')
    DISTRO=$os_id
  fi
  export BUILD_ARCH=$(uname -m)
  # shellcheck disable=2222,2221
  case "${os_id}|${os_id_like}" in
    *rhel*|*centos*|*fedora*|*rocky*|*almalinux*|*amzn*)
      export BUILD_OS="linux"
      export VENDOR="redhat"
      export INSTALL_COMMAND="dnf"
      export SEARCH_COMMAND="dnf list"
      export CHECK_INSTALLED_CMD="rpm -q"
      ;;
    *ubuntu*|*debian*|*mint*|*kali*|*pop*|*raspbian*)
      export BUILD_OS="linux"
      export VENDOR="canonical"
      export INSTALL_COMMAND="apt-get"
      export SEARCH_COMMAND="apt-cache show"
      export CHECK_INSTALLED_CMD="dpkg -s"
      ;;
    *arch*|*manjaro*|*endeavouros*)
      export BUILD_OS="linux"
      export VENDOR="arch"
      export INSTALL_COMMAND="pacman"
      export SEARCH_COMMAND="pacman -Ss"
      export CHECK_INSTALLED_CMD="pacman -Q"
      ;;
    *alpine*)
      export BUILD_OS="linux"
      export VENDOR="alpine"
      export INSTALL_COMMAND="apk"
      export SEARCH_COMMAND="apk search"
      export CHECK_INSTALLED_CMD="apk info -e"
      ;;
    *void*)
      export BUILD_OS="linux"
      export VENDOR="void"
      export INSTALL_COMMAND="xbps-install"
      export SEARCH_COMMAND="xbps-query -Rs"
      export CHECK_INSTALLED_CMD="xbps-query" 
      ;;
    *gentoo*)
      export BUILD_OS="linux"
      export VENDOR="gentoo"
      export INSTALL_COMMAND="emerge"
      export SEARCH_COMMAND="emerge --search"
      export CHECK_INSTALLED_CMD="qlist -I"
      ;;
    *freebsd*)
      export BUILD_OS="linux"
      export VENDOR="freebsd"
      export INSTALL_COMMAND="pkg"
      export SEARCH_COMMAND="pkg search"
      export CHECK_INSTALLED_CMD="pkg info"
      ;;
    *sles*|*suse*)
      export BUILD_OS="linux"
      export VENDOR="sles"
      export INSTALL_COMMAND="zypper"
      export SEARCH_COMMAND="zypper search"
      export CHECK_INSTALLED_CMD="rpm -q"
      ;;
    *nix*)
      export BUILD_OS="linux"
      export VENDOR="nix"
      export INSTALL_COMMAND="nix-env"
      export SEARCH_COMMAND="nix-env -qa"
      export CHECK_INSTALLED_CMD="nix-env -q"
      ;;
    *guix*)
      export BUILD_OS="linux"
      export VENDOR="guix"
      export INSTALL_COMMAND="guix"
      export SEARCH_COMMAND="guix package -A"
      export CHECK_INSTALLED_CMD="guix package -I"
      ;;
    *macos*|*darwin*)
      export BUILD_OS="macos"
      export VENDOR="macos"
      export DISTRO="macos"
      export INSTALL_COMMAND="brew"
      export SEARCH_COMMAND="brew search"
      export CHECK_INSTALLED_CMD="brew list"
      ;;
    *)
      export VENDOR="unknown"
      return 1
      ;;
  esac
}

package_exists() {
  determine_distro
  local pkg="$1"
  echo "Running $SEARCH_COMMAND $pkg" >>"$LOG_FILE"
  if eval "$SEARCH_COMMAND $pkg -y" >>"$LOG_FILE" 2>&1; then
    return 0
  fi
  return 1
}

validate_package() {
    local pkg="$1"
    local candidates=()
    local roots=("$pkg")
    if [[ "$pkg" == lib* ]]; then
        roots+=("${pkg#lib}")
    else
        roots+=("lib${pkg}")
    fi
    for root in "${roots[@]}"; do
        candidates+=("$root")
        if [[ "$root" == *-dev ]]; then
            candidates+=("${root}el")
        elif [[ "$root" == *-devel ]]; then
            candidates+=("${root%el}")
        fi
    done
    for candidate in "${candidates[@]}"; do
        if package_exists "$candidate"; then
            if [[ "$candidate" != "$pkg" ]]; then
                [ -n "$LOG_FILE" ] && echo "DEBUG: Remapped '$pkg' to '$candidate'" >> "$LOG_FILE"
            fi
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

install_missing_packages() {
  determine_distro
  # shellcheck disable=2086,2048
  mapfile -t missing_packages < <(get_missing_packages $*)
  if [[ "${#missing_packages[*]}" -gt 0 ]]; then
    echo "INFO: Missing packages: ${missing_packages[*]}" >>"$LOG_FILE"
    for package in "${missing_packages[@]}"; do
      new_pkg="$(validate_package "$package")"
      if [[ -n $new_pkg ]]; then
        echo -e "INFO: Installing validated package: $new_pkg\n  running: \"$INSTALL_COMMAND install ${new_pkg} -y\"" >>"$LOG_FILE"
        eval "$INSTALL_COMMAND install ${new_pkg} -y" > >(redirect_output) 2>&1 || true;
      else
        echo "DEBUG: No validated package found for $package" >>"$LOG_FILE"
      fi
    done
  fi
}

# made into a method so I don't/don't have to download this script every time if only doing just 32 or just6 64 bit builds...
download_gcc_build_script() {
	local zeranoe_script_name=$1
	cp "$PATCHDIR"/"$zeranoe_script_name" "$PATCHDIR"/"$zeranoe_script_name".bak
	cp "$PATCHDIR"/"$zeranoe_script_name" "$zeranoe_script_name"
	#rm -f $PATCHDIR/$zeranoe_script_name || exit_message 1
	#curl -4 https://raw.githubusercontent.com/Zeranoe/mingw-w64-build/refs/heads/master/mingw-w64-build -O --fail || exit_message 1
	chmod -R a+rwx "$zeranoe_script_name"
}

# helper methods for downloading and building projects that can take generic input

do_svn_checkout() {
	repo_url="$1"
	to_dir="$2"
	desired_revision="$3"
	if [ ! -d "$to_dir" ]; then
		echo -e "INFO: svn checking out to $to_dir" >>"$LOG_FILE"
		if [[ -z "$desired_revision" ]]; then
			svn checkout "$repo_url" "$to_dir".tmp --non-interactive --trust-server-cert > >(redirect_output) 2>&1 || exit_message 1 "do_svn_checkout: could not checkout $repo_url"
		else
			svn checkout -r "$desired_revision" "$repo_url" "$to_dir".tmp > >(redirect_output) 2>&1 || exit_message 1 "do_svn_checkout: could not checkout $desired_revision $repo_url"
		fi
		mv "$to_dir".tmp "$to_dir" 2>>"$LOG_FILE"
    chmod -R a+rwx "$to_dir" 2>>"$LOG_FILE"
	else
    if truthy "$build_force" || [[ ! -f "$host_touch" ]]; then
      echo -e "INFO: Force requested, resetting repository" >>"$LOG_FILE"
      svn_hard_reset "$to_dir"
		elif truthy "$git_get_latest"; then
      echo -e "INFO: Fetching git instead" >>"$LOG_FILE"
			svn update > >(redirect_output) 2>&1 # want this for later...
		else
      chmod -R a+rwx "$to_dir" 2>>"$LOG_FILE"
      change_dir "$to_dir"
      change_dir ..
    fi
	fi
}

svn_hard_reset() {
    # Get the absolute path of the target
    local target_path
    if command -v realpath >/dev/null 2>&1; then
        target_path=$(realpath "$1" 2>/dev/null) || return
    else
        # Fallback for systems without realpath (like macOS)
        target_path=$(cd -- "$1" && pwd 2>/dev/null) || return
    fi
    
    [ -z "$target_path" ] && return
    
    # Get current directory
    local current_path
    current_path=$(pwd)
    
    # Only proceed if we're in the target directory
    if [ "$current_path" = "$target_path" ]; then
        # Ensure we're in a git repository
        if svn info >/dev/null 2>&1; then
            svn revert -R . > >(redirect_output) 2>&1                                  # Revert all tracked changes
            svn status | grep '^?' | cut -c9- | xargs rm -rf > >(redirect_output) 2>&1 # Remove untracked files
            svn update > >(redirect_output) 2>&1                                       # Get latest from repo
        else
            echo "ERROR: Not a git repository" >>"$LOG_FILE" 2>&1
            return 1
        fi
    else
        echo "ERROR: Current directory is not the target directory" >>"$LOG_FILE" 2>&1
        echo "  Current: $current_path" >>"$LOG_FILE" 2>&1
        echo "  Target:  $target_path" >>"$LOG_FILE" 2>&1
        return 1
    fi
}

get_git_command() {
  local repo_url="$1"
  local name="$2"
  local to_dir="$3"
  local type="$4"
  case "${type,,}" in
    commit)
    echo "git clone \"$repo_url\" \"$to_dir\" --recurse-submodules --single-branch && cd \"$to_dir\" && git checkout \"$name\""
    return 0
    ;;
    branch)
    echo "git clone --depth 1 --branch \"$name\" \"$repo_url\" \"$to_dir\" --recurse-submodules --single-branch"
    return 0
    ;;
    tag)
    echo "git clone --depth 1 --branch \"$name\" \"$repo_url\" \"$to_dir\" --recurse-submodules --single-branch"
    return 0
    ;;
    *)
    exit_message 1 "get_git_command: invalid git ref type $type"
    ;;
  esac
}

get_valid_remote() {
  local repo_url="$1"
  local name="$2"

  echo "DEBUG: Starting search for '$name' in $repo_url" >>"$LOG_FILE"
  
  # Get all refs at once
  local all_refs
  if ! all_refs=$(git ls-remote "$repo_url" 2>>"$LOG_FILE"); then
    echo -e "DEBUG: Cannot access repository: $repo_url" >>"$LOG_FILE"
    return 1
  fi
  echo "DEBUG: Repository is accessible" >>"$LOG_FILE"

  # Check as commit SHA
  echo "DEBUG: Checking if '$name' is a commit SHA..."  >>"$LOG_FILE"
  if [[ "$name" =~ ^[0-9a-f]{7,40}$ ]]; then
    echo "DEBUG: '$name' matches SHA pattern" >>"$LOG_FILE"
    if echo "$all_refs" | grep -q "^$name"; then
      echo "DEBUG: Found '$name' as a valid commit" >>"$LOG_FILE"
      echo "commit $name"
      return 0
    else
      echo "DEBUG: '$name' matches SHA pattern but not found in remote" >>"$LOG_FILE"
    fi
  fi
  
  # Check as branch
  echo "DEBUG: Checking if '$name' is a branch..." >>"$LOG_FILE"
  if echo "$all_refs" | grep -q "refs/heads/$name"; then
    echo "DEBUG: Found '$name' as a branch" >>"$LOG_FILE"
    echo "branch $name"
    return 0
  fi
  
  # Check as tag
  echo "DEBUG: Checking if '$name' is a tag..." >>"$LOG_FILE"
  if echo "$all_refs" | grep -q "refs/tags/$name"; then
    echo "DEBUG: Found '$name' as a tag" >>"$LOG_FILE"
    echo "tag $name"
    return 0
  fi
  
  # Fallbacks
  echo "DEBUG: Checking fallback branches..." >>"$LOG_FILE"
  for branch in main master; do
    if echo "$all_refs" | grep -q "refs/heads/$branch"; then
      echo "DEBUG: Found fallback branch '$branch'" >>"$LOG_FILE"
      echo "branch $branch"
      return 0
    fi
  done
  
  echo -e "DEBUG: No valid branch/tag/commit found in $repo_url (tried: $name, main, master)" >>"$LOG_FILE"
  return 1
}

# params: git url, to_dir
retry_git_or_die() { # originally from https://stackoverflow.com/a/76012343/32453
	local RETRIES_NO=50
	local RETRY_DELAY=30
	local repo_url="$1"
	local to_dir="$2"
	local desired_branch="$3"
  # shellcheck disable=2248,2207
  local valid_remote=($(get_valid_remote "$repo_url" "$desired_branch"))
  local remote_type="${valid_remote[0]}"
  local remote_name="${valid_remote[*]:1}"
  local git_command="$(get_git_command "$repo_url" "$remote_name" "$to_dir.tmp" "$remote_type")"
	for i in $(seq 1 "$RETRIES_NO"); do
    if [[ -n $git_command ]]; then
      echo -e "INFO: Downloading (via git clone) branch, tag, or commit: $desired_branch to $to_dir from $repo_url" >>"$LOG_FILE"
      remove_path -rf "$to_dir.tmp" # just in case it was interrupted previously...not sure if necessary...
      create_dir "$to_dir.tmp"
      echo -e "DEBUG: Evaluating \"$git_command\"\n" >>"$LOG_FILE"
      # shellcheck disable=SC2086
      if [[ -n "$git_command" ]]; then
        eval "$git_command" > >(redirect_output) 2>&1 && chmod -R a+rwx "$to_dir.tmp" && break
      else
        exit_message 1 "could not determine git command $git_command"
      fi
    else
      exit_message 1 "retry_git_or_die: Could not generate git command for $repo_url $remote_type $remote_name $to_dir"
    fi
		#git clone --depth 1 -b "$desired_branch" "$repo_url" "$to_dir.tmp" --recurse-submodules --single-branch && break
		# get here -> failure
		[[ $i -eq $RETRIES_NO ]] && exit_message 1 "retry_git_or_die: Failed to execute git cmd $repo_url $to_dir after $RETRIES_NO retries"
		echo -e "DEBUG: sleeping before retry git" >>"$LOG_FILE"
		sleep "${RETRY_DELAY}"
	done
	# prevent partial checkout confusion by renaming it only after success
	#mv $to_dir.tmp $to_dir
	echo -e "INFO: done git cloning branch $desired_branch to $to_dir" >>"$LOG_FILE"
}

is_valid_git_dir() {
    local dir="$1"
    if (GIT_DIR="$dir/.git" git rev-parse --git-dir > /dev/null 2>&1); then
        return 0
    else
        return 1
    fi
}

is_empty_dir() {
    local dir="$1"
    if [[ -d "$dir" ]] && [[ -z "$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        return 0  # empty
    else
        return 1  # not empty
    fi
}

# Get the current branch name (e.g., "main" or "feature/login")
get_git_branch() {
  git branch --show-current 2>/dev/null
}

# Get the most recent tag (e.g., "v1.0.4")
get_git_tag() {
  git describe --tags --abbrev=0 2>/dev/null
}

# Get the "release" (The tag + how many commits ahead of it you are)
get_git_release() {
  git describe --tags 2>/dev/null
}

# Get the short hash (e.g., "a1b2c3d")
get_git_commit() {
  git rev-parse HEAD 2>/dev/null
}

# Get the short commit hash (e.g., "a1b2c3d")
get_git_commit_short() {
  git rev-parse --short HEAD 2>/dev/null
}

is_current_git_ref() {
    local input="$1"
    
    [ -z "$input" ] && return 1

    # 1. Check against current Branch name
    local current_branch=$(get_git_branch)
    local all_refs=$(git ls-remote "$repo_url" 2>/dev/null)
    echo "DEBUG: Checking branch $current_branch against $input" >>"$LOG_FILE"
    if [[ "$input" == "$current_branch" ]]; then
      echo "DEBUG: Matched branch $input == $current_branch" >>"$LOG_FILE"
      return 0
    fi
    # 2. Check against current exact Tag
    # (Checking if HEAD is exactly at this tag)
    local current_tag=$(get_git_tag)
    echo "DEBUG: Checking tag $current_tag against $input" >>"$LOG_FILE"
    if [[ "$input" == "$current_tag" ]]; then
      echo "DEBUG: Matched tag $input == $current_tag" >>"$LOG_FILE"
      return 0
    fi

    # 3. Check against current Release string 
    # (e.g., v1.0.4-5-g7f2)
    local current_release=$(get_git_release)
    echo "DEBUG: Checking release $current_release against $input" >>"$LOG_FILE"
    if [[ "$input" == "$current_release" ]]; then 
      echo "DEBUG: Matched release $input == $current_release" >>"$LOG_FILE"
      return 0
    fi

    # 4. Check against current Commit (Long and Short)
    local long_commit=$(get_git_commit)
    local short_commit=$(get_git_commit_short)
    echo "DEBUG: Checking comit $long_commit against $input" >>"$LOG_FILE"
    echo "DEBUG: Checking release $short_commit against $input" >>"$LOG_FILE"
    if [[ "$input" == "$long_commit" ]]; then
      echo "DEBUG: Matched long commit $input == $long_commit" >>"$LOG_FILE"
      return 0
    elif [[ "$input" == "$short_commit" ]]; then
      echo "DEBUG: Matched short commit $input == $short_commit" >>"$LOG_FILE"
      return 0
    fi
    echo "DEBUG: $input is not current git ref" >>"$LOG_FILE"
    return 1
}

# 1. repo_url
# 2. to_dir
# 3. desired_branch
do_git_checkout() {
	local repo_url="$1"
	local to_dir="$2"
	if [[ -n "$3" ]]; then
		desired_branch="$3"
	else
		desired_branch="master"
	fi
  local touch_file="$host_touch"
	echo -e "INFO: Starting git checkout $repo_url" >>"$LOG_FILE"
	if [[ -z $to_dir ]]; then
		to_dir=$(basename "$repo_url" | sed -e  's/\.git$//; s/[?#].*$//') # http://y/abc.git -> abc
	fi
	if [ -d "$to_dir" ] && is_valid_git_dir "$to_dir"; then
    echo -e "INFO: Directory already exists $to_dir." >>"$LOG_FILE"
		change_dir "$to_dir"
    if ! is_current_git_ref "$desired_branch"; then
      git_hard_reset "$(pwd)"
      git fetch --unshallow >>"$LOG_FILE" 2>&1
      git config remote.origin.fetch \"+refs/heads/*:refs/remotes/origin/*\" >>"$LOG_FILE" 2>&1
      git fetch --all --tags >>"$LOG_FILE" >>"$LOG_FILE" 2>&1
      # shellcheck disable=2207
      local valid_remote=($(get_valid_remote "$repo_url" "$desired_branch"))
      local remote_type="${valid_remote[0]}"
      local remote_name="${valid_remote[*]:1}"
      # shellcheck disable=2128
      echo "INFO: Checking out $remote_type $remote_name from $repo_url" >>"$LOG_FILE" 2>&1
      if ! git checkout "$remote_name" >>"$LOG_FILE" 2>&1; then
        echo "WARNING: Checkout failed due to conflicts. forcing nuclear clean..." >>"$LOG_FILE"
        git reset --hard HEAD >>"$LOG_FILE" 2>&1
        git clean -fdx >>"$LOG_FILE" 2>&1
        git checkout "$remote_name" >>"$LOG_FILE" 2>&1 || exit_message 1 "do_git_checkout: final checkout failed for $remote_name"
      fi
      add_src_dir "$(pwd)"
    fi
    if truthy "$build_force" || [[ ! -f "$host_touch" ]]; then
      [[ ! -f "$host_touch" ]] && echo "INFO: Source state file not found $host_touch" >>"$LOG_FILE"
      echo -e "INFO: Force requested, resetting repository: build_force: $build_force" >>"$LOG_FILE"
      git clean -fdx >>"$LOG_FILE" 2>&1
      git_hard_reset "$(pwd)"
      add_src_dir "$(pwd)"
		fi
    if truthy "$git_get_latest"; then
      echo -e "INFO: Fetching git instead" >>"$LOG_FILE"
			git fetch --quiet >>"$LOG_FILE" 2>&1
      add_src_dir "$(pwd)"
		else
			echo -e "INFO: not doing git get latest pull for latest code $to_dir" >>"$LOG_FILE" # too slow'ish...
		fi
	else
    if [[ -d "$to_dir" ]] && is_empty_dir "$to_dir"; then
      echo -e "INFO: Empty directory already exists at $to_dir. Deleting before downloading." >>"$LOG_FILE"
      remove_path -rf "$to_dir"
    fi
		echo -e "INFO: Downloading $repo_url $desired_branch into $to_dir" >>"$LOG_FILE"
		retry_git_or_die "$repo_url" "$to_dir" "$desired_branch" || exit_message 1 "do_git_checkout: could not checkout $desired_branch from $repo_url"
    mv "$to_dir.tmp" "$to_dir" 2>>"$LOG_FILE"
		chmod -R a+rwx "$to_dir" 2>>"$LOG_FILE"
    add_src_dir "$(validate_path "$to_dir")"
    change_dir "$to_dir"
	fi
}

do_git_sparse_checkout() {
  local repo_url="$1"
	local to_dir="$2"
  local path="$3"
	echo -e "INFO: Starting git checkout $repo_url" >>"$LOG_FILE"
	if [[ -z $to_dir ]]; then
		to_dir=$(basename "$repo_url" | sed -e  's/\.git$//; s/[?#].*$//') # http://y/abc.git -> abc
	fi
  local touch_file="$host_touch"
  if truthy "$build_force" || [[ ! -f "${to_dir}/$host_touch" ]]; then
    [[ ! -f "$host_touch" ]] && echo "INFO: Source state file not found $host_touch" >>"$LOG_FILE"
    echo -e "INFO: Force requested, resetting repository: build_force: $build_force" >>"$LOG_FILE"
    git_hard_reset "${to_dir}"
    add_src_dir "$(pwd)"
  fi
	if [ -d "$to_dir" ] && is_valid_git_dir "$to_dir"; then
    echo -e "INFO: Directory already exists $to_dir." >>"$LOG_FILE"
		change_dir "$to_dir"
    if truthy "$build_force"; then
      echo -e "INFO: Force requested, resetting repository" >>"$LOG_FILE"
      git_hard_reset "$(pwd)"
      git sparse-checkout init --cone >>"$LOG_FILE" 2>&1 || exit_message 1 "do_git_sparse_checkout: could not re-init sparse-checkout"
      git sparse-checkout set "$path" >>"$LOG_FILE" 2>&1 || exit_message 1 "do_git_sparse_checkout: could not set sparse-checkout path"
      git checkout >>"$LOG_FILE" 2>&1 || exit_message 1 "do_git_sparse_checkout: could not checkout"
      add_src_dir "$(pwd)"
		elif truthy "$git_get_latest"; then
      echo -e "INFO: Fetching git instead" >>"$LOG_FILE"
			git fetch --quiet >>"$LOG_FILE" 2>&1# want this for later...
      git sparse-checkout set "$path" >>"$LOG_FILE" 2>&1
      git checkout >>"$LOG_FILE" 2>&1|| exit_message 1 "do_git_sparse_checkout: could not checkout after fetch"
      add_src_dir "$(pwd)"
		else
			echo -e "INFO: not doing git get latest pull for latest code $to_dir" >>"$LOG_FILE" # too slow'ish...
      git sparse-checkout set "$path" >>"$LOG_FILE" 2>&1
      add_src_dir "$(pwd)"
		fi
	else
    [[ -d "$to_dir.tmp" ]] && (remove_path -rf "$to_dir.tmp"; true) # just in case it failed previously
    if [[ -d "$to_dir" ]] && is_empty_dir "$to_dir"; then
      echo -e "INFO: Empty directory already exists at $to_dir. Deleting before downloading." >>"$LOG_FILE"
      remove_path -rf "$to_dir"
    fi
		echo -e "INFO: Downloading $repo_url into $to_dir" >>"$LOG_FILE"
		git clone --no-checkout "$repo_url" "$to_dir.tmp" >>"$LOG_FILE" 2>&1 || exit_message 1 "do_git_sparse_checkout: could not \"git clone --no-checkout\" $repo_url"
    change_dir "$to_dir.tmp"
    git sparse-checkout init --cone >>"$LOG_FILE" 2>&1|| exit_message 1 "do_git_sparse_checkout: could not \"git sparse-checkout init --cone\" $repo_url"
    git sparse-checkout set "$path" >>"$LOG_FILE" 2>&1|| exit_message 1 "do_git_sparse_checkout: could not \"git sparse-checkout set $path\" $repo_url"
    git checkout >>"$LOG_FILE" 2>&1|| exit_message 1 "do_git_sparse_checkout: could not \"git checkout\" $repo_url"
    change_dir ..
    mv "$to_dir.tmp" "$to_dir" 2>>"$LOG_FILE"
		chmod -R a+rwx "$to_dir" 2>>"$LOG_FILE"
    add_src_dir "$(validate_path "$to_dir")"
    change_dir "$to_dir"
	fi
  echo -e "INFO: Successfully checked out $path from $repo_url into $(pwd)" >>"$LOG_FILE"
}

git_hard_reset() {
    # Get the absolute path of the target
    local target_path
    if command -v realpath >/dev/null 2>&1; then
        target_path=$(realpath "$1" 2>/dev/null) || return
    else
        # Fallback for systems without realpath (like macOS)
        target_path=$(cd -- "$1" && pwd 2>/dev/null) || return
    fi
    
    [ -z "$target_path" ] && return
    
    # Get current directory
    local current_path
    current_path=$(pwd)
    
    # Only proceed if we're in the target directory
    if [ "$current_path" = "$target_path" ]; then
        # Ensure we're in a git repository
        if git rev-parse --git-dir >/dev/null 2>&1; then
            git reset --hard >>"$LOG_FILE" 2>&1
            git clean -fd >>"$LOG_FILE" 2>&1
            chmod -R a+rwx .
        else
            echo "ERROR: Not a git repository" >&2
            return 1
        fi
    else
        echo "ERROR: Current directory is not the target directory" >&2
        echo "  Current: $current_path" >&2
        echo "  Target:  $target_path" >&2
        return 1
    fi
}

# 1. exit_code
# 2. file_name
create_touch_file() {
	local exit_code="${1:-"0"}"
  local file_name="$2"
  echo -e "INFO: creating touch file $file_name" >>"$LOG_FILE"
	if truthy "$exit_code"; then
		touch "$file_name" >>"$LOG_FILE" || exit_message 1 "create_touch_file: unable to create touch file $file_name"
    chmod -R a+rwx "$file_name"
	else
		touch "$file_name" >>"$LOG_FILE" || echo -e "DEBUG: unable to create touch file $file_name" | tee -a "$LOG_FILE"
    chmod -R a+rwx "$file_name"
	fi
}

get_small_touchfile_name() { # have to call with assignment like a=$(get_small...)
	local beginning="$1"
	local extra_stuff="$2"
	local touch_name="${beginning}_$(echo -e -- "$extra_stuff" | /usr/bin/env md5sum)" # md5sum to make it smaller, cflags to force rebuild if changes
	touch_name=$(echo -e "$touch_name" | sed -e  "s/ //g")                                                      # md5sum introduces spaces, remove them
	echo -e "$touch_name.touch"                                                                                   # bash cruddy return system LOL
}

redirect_output() {
	local term_width="${COLUMNS:-80}"
  local max_length=$((term_width > 10 ? term_width - 2 : 78))
  while IFS= read -r line; do
    if [[ "$line" == *"<command-line>: warning:"* ]]; then
      continue
    fi
		if [[ "$line" == *$'\n'* ]]; then
      IFS=$'\n' read -ra parts <<< "$line"
      for part in "${parts[@]}"; do
				if [ "${#part}" -gt "$max_length" ]; then
        	part="${part:0:$max_length}…"
      	fi
        printf "\r\033[K%s" "$part"
      done
    else
			part=$line
			if [ "${#part}" -gt "$max_length" ]; then
        part="${part:0:$max_length}…"
      fi
			printf "\r\033[K%s" "$part"
		fi
		echo "$line" 1>>"$LOG_FILE" 2>&1
	done
}
# use if cargo build needs it
confirm_libgcc_eh() {
    local search_dir="$1"
    [[ -d "$search_dir" ]] || return 1
    
    # Exit early if any libgcc_eh.a exists
    find "$search_dir" -name "libgcc_eh.a" -quit 2>/dev/null && \
        { return 0; }
    
    while IFS= read -r -d '' file; do
        cp "$file" "${file%/*}/libgcc_eh.a" && echo "Created: ${file%/*}/libgcc_eh.a"
    done < <(find "$search_dir" -name "libgcc.a" -type f -print0 2>/dev/null)
}
# 1. configure_options
# 2. configure_name
# 2. configure_env
# 4. touch_postfix
do_python() {
	local configure_options="$1"
	local configure_name=$2
	local configure_env="$3"
	local touch_postfix=""
	[[ -n $4 ]] && touch_postfix="_${4}_" || touch_postfix="_"
	if [[ -z "${configure_name[*]}" ]]; then
		configure_name=("./waf" "configure -v")
	fi
  if [[ "${configure_name[*]}" == *"waf"* ]]; then
    remove_path -rf .waf3*
    remove_path -rf __pycache__
    [[ -d "waflib" ]] && remove_path -rf waflib
    echo -e "DEBUG: updating waf to latest version..." >>"$LOG_FILE"
    wget https://waf.io/waf-2.1.9 -O waf > >(redirect_output) 2>&1
    chmod +x waf
  fi
  # shellcheck disable=SC2206,SC2128
  configure_command=(python3 ${configure_name[*]})
	local cur_dir2=$(pwd)
	local english_name=$(basename "$cur_dir2")
  local touch_prefix="${host_name}${touch_postfix}already_python"
	local touch_name=$(get_small_touchfile_name "${touch_prefix}_$(basename "${configure_name[*]}")" "$configure_options")
  local src_touch="$(validate_path "$host_touch")"
  [[ ! -f "$src_touch" ]] && echo -e "INFO: $src_touch not found during do_python()" >>"$LOG_FILE"
	if truthy "$build_force" || [[ ! -f "$src_touch" ]]; then
    echo -e "INFO: Force requested in do_python(): build_force: $build_force" >>"$LOG_FILE"
    if [[ "${configure_name[*]}" == *configure* ]]; then
      reset_touch "$cur_dir2" "${touch_prefix}*.touch"
      if [[ -f $src_touch ]]; then
        echo -e "INFO: $src_touch found during do_python(). Uninstalling existing installation..." >>"$LOG_FILE"
        { eval "python3 ./waf uninstall" > >(redirect_output) 2>&1 || true; }
      fi
      { eval "python3 ./waf clean" > >(redirect_output) 2>&1 || true; }
    else
		  reset_touch "$cur_dir2" "${touch_prefix}_$(basename "${configure_name[*]}")*.touch"
    fi
	fi
	if [ ! -f "$touch_name" ]; then
    echo "INFO: (Re-)do_python() because $touch_name not found with \"$configure_options\"." >>"$LOG_FILE"
    remove_path -f "${touch_prefix}_$(basename "${configure_name[*]}")"*
		echo -e "INFO: Using python:\n  DIR=$cur_dir2\n  PATH=$PATH\n  PKG_CONFIG_PATH=$PKG_CONFIG_PATH\n  CFLAGS:$CFLAGS\n  CXXFLAGS:$CXXFLAGS\n  CPPFLAGS:$CPPFLAGS\n  LDFLAGS:$LDFLAGS\n  $english_name ($PWD) as PATH=$PATH ${configure_env}\n ${configure_command[*]} $configure_options\n  $(get_compiler_flags)" >>"$LOG_FILE"
		# shellcheck disable=SC1078,SC2086
		eval "${configure_command[*]} $configure_options" > >(redirect_output) 2>&1 || exit_message 1 "do_python: could not run configure ${configure_command[*]}"
		create_touch_file 0 "$touch_name"
    add_src_dir "$(pwd)"
    find . -maxdepth 1 -name "*_src_state.touch" ! -name "$(basename "$src_touch")" -delete > >(redirect_output) 2>&1 # delete other src_state.touch files
	else
		echo -e "INFO: Already used python $(basename "$cur_dir2")" >>"$LOG_FILE"
	fi
}
# shellcheck disable=SC2086
# 1. extra_build_args
# 2. extra_install_args
cargo_build_and_install() {
	local extra_build_args="$1"
	local extra_install_args="$2"
	do_cargo_build "$extra_build_args"
	do_cargo_install "$extra_install_args"
}

# shellcheck disable=SC2086
# 1. extra_build_args
do_cargo_build() {
	local extra_build_args="$1"
  local touch_postfix=""
  [[ -n $2 ]] && touch_postfix="_${2}_" || touch_postfix="_"
	local cur_dir2=$(pwd)
  local touch_prefix="${host_name}${touch_postfix}already_cargo"
	local touch_name=$(get_small_touchfile_name "${touch_prefix}_build" "cargo build $extra_build_args")
  local src_touch="$(validate_path "$host_touch")"
  [[ ! -f "$src_touch" ]] && echo -e "INFO: $src_touch not found during do_cargo_build()" >>"$LOG_FILE"
	if truthy "$build_force" || [[ ! -f "$src_touch" ]]; then
    echo -e "INFO: Force requested in do_cargo_build(): build_force: $build_force" >>"$LOG_FILE"
		reset_touch "$cur_dir2" "${touch_prefix}*.touch"
    if [[ -f $src_touch ]]; then
      echo -e "INFO: $src_touch found during do_cargo_build(). Uninstalling existing installation..." >>"$LOG_FILE"
      { cargo uninstall >>"$LOG_FILE" 2>&1 || true; }
    fi
    { cargo clean --release >>"$LOG_FILE" 2>&1 || true; }
	fi
	if [ ! -f "$touch_name" ]; then
    echo "INFO: (Re-)do_cargo_build() because $touch_name not found with \"cargo build $extra_build_args\"." >>"$LOG_FILE"
    reset_touch "$cur_dir2" "${touch_prefix}*.touch"
    { cargo clean --release >>"$LOG_FILE" 2>&1 || true; }
    export RUSTFLAGS+=" -C relocation-model=pic"
		echo -e "INFO: Running cargo build with:\n  DIR=$cur_dir2\n  RUSTFLAGS=$RUSTFLAGS\n  PATH=$PATH\n  PKG_CONFIG_PATH=$PKG_CONFIG_PATH\n  CFLAGS:$CFLAGS\n  CXXFLAGS:$CXXFLAGS\n  CPPFLAGS:$CPPFLAGS\n  LDFLAGS:$LDFLAGS\n  \"cargo build --target $rust_target $extra_build_args\"\n  $(get_compiler_flags)" >>"$LOG_FILE"
    rustup target add $rust_target > >(redirect_output) 2>&1
		cargo build --target "$rust_target" $extra_build_args > >(redirect_output) 2>&1 || {
			exit_message 1 "do_cargo_build: failed cargo build with $extra_build_args\n see $LOG_FILE for more details"
		}
		create_touch_file 0 "$touch_name"
    add_src_dir "$(pwd)"
    find . -maxdepth 1 -name "*_src_state.touch" ! -name "$(basename "$src_touch")" -delete > >(redirect_output) 2>&1 # delete other src_state.touch files
		echo -e "INFO: Done with cargo build" >>"$LOG_FILE"
	else
		echo -e "INFO: Cargo already build" >>"$LOG_FILE"
	fi
}

# shellcheck disable=SC2086
# 1. extra_install_args
do_cargo_install() {
	local extra_install_args="$1"
  local touch_postfix=""
  [[ -n $2 ]] && touch_postfix="_${2}_" || touch_postfix="_"
	local cur_dir2=$(pwd)
  local touch_prefix="${host_name}${touch_postfix}already_cargo"
	local touch_name=$(get_small_touchfile_name "${touch_prefix}_install" "cargo install $extra_install_args")
  local src_touch="$(validate_path "$host_touch")"
  [[ ! -f "$src_touch" ]] && echo -e "INFO: $src_touch not found during do_cargo_install()" >>"$LOG_FILE"
	if truthy "$build_force" || [[ ! -f "$src_touch" ]]; then
    echo -e "INFO: Force requested in do_cargo_install(): build_force: $build_force" >>"$LOG_FILE"
		reset_touch "$cur_dir2" "${touch_prefix}_install*.touch"
	fi
	if [ ! -f "$touch_name" ]; then
    echo "INFO: (Re-)do_cargo_install() because $touch_name not found with \"cargo install $extra_install_args\"." >>"$LOG_FILE"
    remove_path -f "${touch_prefix}_install"*
    export RUSTFLAGS+=" -C relocation-model=pic"
		echo -e "INFO: Running cargo install cargo-c" >>"$LOG_FILE"
    echo -e "INFO: Running cargo cinstall with:\n  DIR=$cur_dir2\n  RUSTFLAGS=$RUSTFLAGS\n  PATH=$PATH\n  PKG_CONFIG_PATH=$PKG_CONFIG_PATH\n  CFLAGS:$CFLAGS\n  CXXFLAGS:$CXXFLAGS\n  CPPFLAGS:$CPPFLAGS\n  LDFLAGS:$LDFLAGS\n  \"cargo cinstall --prefix=$dependency_install_prefix --target $rust_target $extra_install_args\"\n  $(get_compiler_flags)" >>"$LOG_FILE"
    cargo cinstall --prefix="$dependency_install_prefix" --target "$rust_target" $extra_install_args > >(redirect_output) 2>&1 || {
			exit_message 1 "do_cargo_install: failed cargo cinstall with $extra_install_args\n see $LOG_FILE for more details"
		}
		create_touch_file 0 "$touch_name"
    add_src_dir "$(pwd)"
    find . -maxdepth 1 -name "*_src_state.touch" ! -name "$(basename "$src_touch")" -delete > >(redirect_output) 2>&1 # delete other src_state.touch files
		echo -e "INFO: Done with cargo cinstall" >>"$LOG_FILE"
	else
		echo -e "INFO: Cargo already installed" >>"$LOG_FILE"
	fi
}
needs_autoreconf() {
    local src_dir="${1:-"$(pwd)"}"
    local sys_ver
    sys_ver=$(libtool --version 2>/dev/null | head -n1 | awk '{print $NF}')
    local auto_ver
    auto_ver=$(autoreconf --version 2>/dev/null | head -n1 | awk '{print $NF}')

    local touch_prefix="${host_name}${touch_postfix}already"
    local touch_name=$(get_small_touchfile_name "${touch_prefix}_autoreconf" "libtool: $sys_ver autoreconf: $auto_ver")

    echo "INFO: Checking if autoreconf is needed..."
    if [[ -f "no.autoreconf" || -f "$touch_name" ]]; then
      echo "INFO: Touch file or \"no.autoreconf\" found in directory. Skipping autoreconf."
      return 1
    fi
    # 1. If configure doesn't exist, we definitely need it >>"$LOG_FILE"
    if [ ! -f "$src_dir/configure" ]; then
        echo "INFO: autoreconf is needed because configure could not be found..." >>"$LOG_FILE"
        return 0
    fi

    local sys_ver
    sys_ver=$(libtool --version 2>/dev/null | head -n1 | awk '{print $NF}')

    # 2. Check multiple files for the source libtool version
    local src_ver=""
    if [ -f "$src_dir/ltmain.sh" ]; then
        # ltmain.sh is the most reliable source for the version
        src_ver=$(grep -E '^VERSION=' "$src_dir/ltmain.sh" | cut -d= -f2 | tr -d '"')
    elif [ -f "$src_dir/build-aux/ltmain.sh" ]; then
        src_ver=$(grep -E '^VERSION=' "$src_dir/build-aux/ltmain.sh" | cut -d= -f2 | tr -d '"')
    elif [ -f "$src_dir/aclocal.m4" ]; then
        # Fallback to aclocal.m4 with a more flexible search
        src_ver=$(grep -E "LT_PACKAGE_VERSION|macro_version" "$src_dir/aclocal.m4" | sed -e 's/.*([2-9]\.[0-9]+\.[0-9]+).*/\1/' | head -n1)
    fi

    # 3. If we can't find a version, it's safer to autoreconf than to fail
    if [ -z "$src_ver" ]; then
        echo "WARN: Could not determine source Libtool version in $src_dir. Forcing autoreconf." >>"$LOG_FILE"
        return 0
    fi

    # 4. Compare
    if [ "$sys_ver" != "$src_ver" ]; then
        echo "INFO: Libtool mismatch (System: $sys_ver vs Source: $src_ver). Autoreconf needed." >>"$LOG_FILE"
        return 0
    fi
    echo "INFO: Autoreconf is not needed." >>"$LOG_FILE"
    return 1
}

needs_libtoolize() {
    local src_dir="${1:-"$(pwd)"}"
    local sys_ver
    sys_ver=$("$LIBTOOLIZE" --version 2>/dev/null | head -n1 | awk '{print $NF}')

    local touch_prefix="${host_name}${touch_postfix}already"
    local touch_name
    touch_name=$(get_small_touchfile_name "${touch_prefix}_libtoolize" "libtoolize: $sys_ver")

    echo "INFO: Checking if libtoolize is needed..."
    if [[ -f "$touch_name" ]]; then
      echo "INFO: libtoolize touch file found in directory. Skipping libtoolize."
      return 1
    fi

    if [[ ! -f "$src_dir/config.rpath" && ! -f "$src_dir/build-aux/config.rpath" && ! -f "$src_dir/../build-aux/config.rpath" && ! -f "$src_dir/../../build-aux/config.rpath" ]] || \
      [[ ! -f "$src_dir/ltmain.sh" && ! -f "$src_dir/build-aux/ltmain.sh" && ! -f "$src_dir/../build-aux/ltmain.sh" && ! -f "$src_dir/../../build-aux/ltmain.sh" ]] || \
      [[ ! -f "$src_dir/config.guess" && ! -f "$src_dir/build-aux/config.guess" && ! -f "$src_dir/../build-aux/config.guess" && ! -f "$src_dir/../../build-aux/config.guess" ]] || \
      [[ ! -f "$src_dir/config.sub" && ! -f "$src_dir/build-aux/config.sub" && ! -f "$src_dir/../build-aux/config.sub" && ! -f "$src_dir/../../build-aux/config.sub" ]] || \
      [[ ! -f "$src_dir/install-sh" && ! -f "$src_dir/build-aux/install-sh" && ! -f "$src_dir/../build-aux/install-sh" && ! -f "$src_dir/../../build-aux/install-sh" ]]; then
      echo "INFO: libtoolize is needed because libtool build-aux files are missing." >>"$LOG_FILE"
      return 0
    fi

    echo "INFO: libtoolize is not needed." >>"$LOG_FILE"
    return 1
}

needs_automake_missing() {
    local src_dir="${1:-"$(pwd)"}"
    local auto_ver
    auto_ver=$(automake --version 2>/dev/null | head -n1 | awk '{print $NF}')

    local touch_prefix="${host_name}${touch_postfix}already"
    local touch_name
    touch_name=$(get_small_touchfile_name "${touch_prefix}_automake_missing" "automake: $auto_ver")

    echo "INFO: Checking if automake --add-missing is needed..."
    if [[ -f "$touch_name" ]]; then
      echo "INFO: automake --add-missing touch file found in directory. Skipping automake."
      return 1
    fi

    if [[ ! -f "$src_dir/Makefile.am" ]]; then
      echo "INFO: automake --add-missing is not needed because Makefile.am is missing." >>"$LOG_FILE"
      return 1
    fi

    if [[ ! -f "$src_dir/Makefile.in" && ! -f "$src_dir/Makefile" ]] || \
      [[ ! -f "$src_dir/compile" && ! -f "$src_dir/build-aux/compile" && ! -f "$src_dir/../build-aux/compile" && ! -f "$src_dir/../../build-aux/compile" ]] || \
      [[ ! -f "$src_dir/missing" && ! -f "$src_dir/build-aux/missing" && ! -f "$src_dir/../build-aux/missing" && ! -f "$src_dir/../../build-aux/missing" ]] || \
      [[ ! -f "$src_dir/depcomp" && ! -f "$src_dir/build-aux/depcomp" && ! -f "$src_dir/../build-aux/depcomp" && ! -f "$src_dir/../../build-aux/depcomp" ]]; then
      echo "INFO: automake --add-missing is needed because automake generated files are missing." >>"$LOG_FILE"
      return 0
    fi

    echo "INFO: automake --add-missing is not needed." >>"$LOG_FILE"
    return 1
}

get_config_sub() {
  local dest="$1"
  if [[ -d "$dest" ]]; then
    curl -L -o "$dest/config.sub" 'https://gitweb.git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD' > >(redirect_output) 2>&1 || {
      if ! is_valid_git_dir "$src_dir/config"; then
        do_git_checkout "$src_dir/config"
      fi
      copy_path "$src_dir/config/config.sub" "$dest/config.sub"
    }
  else
    exit_message 1 "DEBUG: Destination directory $dest does not exist"
  fi
}

get_config_guess() {
  local dest="$1"
  if [[ -d "$dest" ]]; then
    curl -L -o "$dest/config.guess" 'https://gitweb.git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD' > >(redirect_output) 2>&1 || {
      if ! is_valid_git_dir "$src_dir/config"; then
        do_git_checkout "$src_dir/config"
      fi
      copy_path "$src_dir/config/config.guess" "$dest/config.guess"
    }
  else
    exit_message 1 "DEBUG: Destination directory $dest does not exist"
  fi
}

# 1. configure_options
# 2. configure_name
# 3. touch_postfix
# shellcheck disable=2178,2128
do_configure() {
	local configure_options="$1"
	local configure_name="$2"
	local touch_postfix=""
	[[ -n $3 ]] && touch_postfix="_${3}_" || touch_postfix="_"
	if [[ -z "$configure_name" ]]; then
    if [[ -f Configure ]]; then
      configure_name="./Configure"
    else
      configure_name="./configure"
    fi
	fi
  if [[ $(uname -s | tr '[:upper:]' '[:lower:]') == "darwin" ]]; then
      echo "INFO: Setting up libtoolize for macOS" >> "$LOG_FILE"
      LIBTOOLIZE="glibtoolize"
  else
      LIBTOOLIZE="libtoolize"
  fi
	local cur_dir2=$(pwd)
	local english_name=$(basename "$cur_dir2")
  local touch_prefix="${host_name}${touch_postfix}already"
	local touch_name=$(get_small_touchfile_name "${touch_prefix}_configure" "$configure_options $configure_name")
  local src_touch="$(validate_path "$host_touch")"
  [[ ! -f "$src_touch" ]] && echo -e "INFO: $src_touch not found during do_configure()" >>"$LOG_FILE"
	if truthy "$build_force" || [[ ! -f "$src_touch" ]] || [[ -n "$4" ]]; then
    echo -e "INFO: Force requested in do_configure(): build_force: $build_force" >>"$LOG_FILE"
		reset_touch "$cur_dir2" "${touch_prefix}*.touch"
    [[ -f Makefile && "$cur_dir2" != "$ffmpeg_source_dir" ]] && { nice make clean -j"$(get_concurrent_proc)" > >(redirect_output) 2>&1 || true; }
    if [[ -f $src_touch ]]; then
      echo -e "INFO: $src_touch found during do_configure(). Uninstalling existing installation..." >>"$LOG_FILE"
      [[ -f ninja.build && "$cur_dir2" != "$ffmpeg_source_dir" ]] && { nice ninja uninstall > >(redirect_output) 2>&1 || true; }
      [[ -f Makefile && "$cur_dir2" != "$ffmpeg_source_dir" ]] && { nice make uninstall > >(redirect_output) 2>&1 || true; }
    fi
	fi
	if [ ! -f "$touch_name" ]; then
    echo "INFO: (Re-)do_configure() because $touch_name not found with \"$configure_options $configure_name\"." >>"$LOG_FILE"
    reset_touch "$cur_dir2" "${touch_prefix}*.touch"
    { nice make clean -j"$(get_concurrent_proc)" > >(redirect_output) 2>&1 || true; }
		# make uninstall # does weird things when run under ffmpeg src so disabled for now...
		echo -e "INFO: configuring $english_name ($PWD) $configure_name $configure_options" >>"$LOG_FILE" # say it now in case bootstrap fails etc.
		echo -e "INFO: all touch files ${touch_prefix}_configure* touchname= $touch_name" >>"$LOG_FILE"
		echo -e "INFO: config options $configure_name $configure_options" >>"$LOG_FILE"
		if [[ ! -f $configure_name && -f bootstrap.sh ]]; then # fftw wants to only run this if no configure :|
			(./bootstrap.sh) > >(redirect_output) 2>&1
		fi
    if needs_libtoolize "$cur_dir2" > >(redirect_output) 2>&1; then
      echo "INFO: Required libtool build-aux files not found. running libtoolize..." >>"$LOG_FILE"
      "$LIBTOOLIZE" --force --copy > >(redirect_output) 2>&1 || exit_message 1 "Failed to run libtoolize for $english_name"
      local libtoolize_ver
      libtoolize_ver=$("$LIBTOOLIZE" --version 2>/dev/null | head -n1 | awk '{print $NF}')
      create_touch_file 0 "$(get_small_touchfile_name "${touch_prefix}_libtoolize" "libtoolize: $libtoolize_ver")"
    fi

    if needs_automake_missing "$cur_dir2" > >(redirect_output) 2>&1; then
      echo -e "INFO: Makefile/build-aux files not found. running automake..." >>"$LOG_FILE"
      if ! automake --copy --force-missing --add-missing > >(redirect_output) 2>&1; then
        if needs_automake_missing "$cur_dir2" > >(redirect_output) 2>&1; then
          exit_message 1 "Failed to run automake for $english_name"
        fi
        echo "WARN: automake returned non-zero for $english_name, but required missing files were installed. Continuing." >>"$LOG_FILE"
      fi
      local automake_ver
      automake_ver=$(automake --version 2>/dev/null | head -n1 | awk '{print $NF}')
      create_touch_file 0 "$(get_small_touchfile_name "${touch_prefix}_automake_missing" "automake: $automake_ver")"
    fi

    if [[ ! -f $configure_name && -f configure.ac ]] || needs_autoreconf > >(redirect_output) 2>&1 ; then
      echo -e "INFO: Configure not found. Running autoreconf with existing configure.ac..." >>"$LOG_FILE"
			autoreconf_library || exit_message 1 "Failed to autoreconf $english_name"
    fi
		if [[ ! -f $configure_name ]]; then
      if [[ -f gitsub.sh ]]; then
        echo "INFO: gitsub.sh found. Running gitsub.sh..."
        (./gitsub.sh pull) > >(redirect_output) 2>&1
      fi
      if [ -f autogen.sh ]; then
        echo "INFO: autogen.sh found. Running autogen.sh..."
			  (./autogen.sh) > >(redirect_output) 2>&1 # some need this to create ./configure :|
		  fi
		fi
    if [[ ! -f config.h.in && -f configure.ac ]]; then
      echo -e "INFO: config.h.in not found. Running autoheader..." >>"$LOG_FILE"
      autoheader > >(redirect_output) 2>&1
    fi
		# Check if configure_name contains a space (usually from ENV_OVERRIDES)
    if [[ "$configure_name" =~ ^[[:space:]] ]] || [[ "$configure_name" == *"="* ]]; then
      echo -e "INFO: do_configure() with:\n  DIR=$cur_dir2\n  PATH=$PATH\n  PKG_CONFIG_PATH=$PKG_CONFIG_PATH\n  CFLAGS:$CFLAGS\n  CXXFLAGS:$CXXFLAGS\n  CPPFLAGS:$CPPFLAGS\n  LDFLAGS:$LDFLAGS\n running: \"$configure_name $configure_options\"\n  $(get_compiler_flags)" >>"$LOG_FILE"
      eval "$configure_name $configure_options" > >(redirect_output) 2>&1
    else
      chmod -R a+rwx "$configure_name" # In non-windows environments, with devcontainers, the configuration file doesn't have execution permissions
      echo -e "INFO: do_configure() with:\n  DIR=$cur_dir2\n  PATH=$PATH\n  PKG_CONFIG_PATH=$PKG_CONFIG_PATH\n  CFLAGS:$CFLAGS\n  CXXFLAGS:$CXXFLAGS\n  CPPFLAGS:$CPPFLAGS\n  LDFLAGS:$LDFLAGS\n nice running: \"$configure_name $configure_options\"\n  $(get_compiler_flags)" >>"$LOG_FILE"
      eval "nice -n 5 $configure_name $configure_options" > >(redirect_output) 2>&1
    fi || {
      exit_message 1 "do_configure: failed configure $english_name \n see $(find "$(pwd)" -name "config.log" -print)"
    }
		create_touch_file 0 "$touch_name"
    add_src_dir "$cur_dir2"
    find . -maxdepth 1 -name "*_src_state.touch" ! -name "$(basename "$src_touch")" -delete > >(redirect_output) 2>&1 # delete other src_state.touch files
	else
	 echo -e "DEBUG: already configured $(basename "$cur_dir2")" >>"$LOG_FILE"
	fi
}
# 1. extra config options
# 2. configure_name
# 3. touch_postfix
# shellcheck disable=2128,2178
generic_configure() {
	local extra_configure_options="$1"
  local configure_name="$2"
  local touch_postfix="$3"
  [[ $extra_configure_options != *--host=* ]] && extra_configure_options+=" --host=$host_target "
	if [[ -n $build_triple ]]; then extra_configure_options+=" --build=$build_triple"; fi
  [[ $extra_configure_options != *--prefix=* ]] && extra_configure_options+=" --prefix=\"$dependency_install_prefix\" "
  [[ $extra_configure_options != *--bindir=* ]] && extra_configure_options+=" --bindir=\"$dependency_install_prefix/bin\" "
  [[ $extra_configure_options != *--libdir=* ]] && extra_configure_options+=" --libdir=\"$dependency_install_prefix/lib\" "
  [[ $extra_configure_options != *--with-sysroot=* ]] && extra_configure_options+=" --with-sysroot=\"$dependency_install_prefix\" "
  if iswindows; then
    extra_configure_options+=" --disable-windows-manifest --disable-win32-dll "
  fi
  extra_configure_options+=" --disable-shared --enable-static "
  # truthy "$build_cross_compile" && extra_configure_options+=" --cross-prefix=$cross_prefix"
	do_configure "$extra_configure_options" "$configure_name" "$touch_postfix"
}
# 1. extra_build_args
# 2. touch_postfix
# shellcheck disable=SC2086
do_autogen() {
  local extra_build_args="$1"
	local cur_dir2=$(pwd)
  [[ -n $2 ]] && touch_postfix="_${2}_" || touch_postfix="_"
  local touch_prefix="${host_name}${touch_postfix}already"
	local touch_name=$(get_small_touchfile_name "${touch_prefix}_autogen" "autogen $extra_build_args")
  local src_touch="$(validate_path "$host_touch")"
  [[ ! -f "$src_touch" ]] && echo -e "INFO: $src_touch not found during do_autogen()" >>"$LOG_FILE"
	if truthy "$build_force" || [[ ! -f "$src_touch" ]]; then
    echo -e "INFO: Force requested in do_autogen(): build_force: $build_force" >>"$LOG_FILE"
		reset_touch "$cur_dir2" "${touch_prefix}*.touch"
	fi
	if [ ! -f "$touch_name" ]; then
    echo "INFO: (Re-)do_autogen() because $touch_name not found with \"autogen $extra_build_args\"." >>"$LOG_FILE"
    remove_path -f "${touch_prefix}_autogen"*
		echo -e "INFO: Running ./autogen.sh with:\n  DIR=$cur_dir2\n  \"./autogen.sh --build-"w$bits_target" $extra_build_args\"" >>"$LOG_FILE"
		( ./autogen.sh $extra_build_args ) > >(redirect_output) 2>&1 || ( ./autogen.sh ) > >(redirect_output) 2>&1 || {
			exit_message 1 "do_autogen: failed ./autogen.sh with $extra_build_args\n see $LOG_FILE for more details"
    }
		create_touch_file 0 "$touch_name"
    add_src_dir "$(pwd)"
    find . -maxdepth 1 -name "*_src_state.touch" ! -name "$(basename "$src_touch")" -delete > >(redirect_output) 2>&1 # delete other src_state.touch files
		echo -e "INFO: Done with ./autogen.sh" >>"$LOG_FILE"
	else
		echo -e "INFO: ./autogen.sh already ran" >>"$LOG_FILE"
	fi
}
# 1. extra_make_options
# 2. touch_postfix
do_make() {
	local extra_make_options="$1"
	local touch_postfix=""
	[[ -n $2 ]] && touch_postfix="_${2}_" || touch_postfix="_"
  if [[ "$extra_make_options" =~ -j[0-9]+ ]]; then
    extra_make_options="${extra_make_options}"
  else
    extra_make_options="-j$(get_concurrent_proc) $extra_make_options"
  fi
	local cur_dir2=$(pwd)
  local touch_prefix="${host_name}${touch_postfix}already_make"
	local touch_name=$(get_small_touchfile_name "${touch_prefix}_make" "make $extra_make_options")
  local src_touch="$(validate_path "$host_touch")"
  [[ ! -f "$src_touch" ]] && echo -e "INFO: $src_touch not found during do_make()" >>"$LOG_FILE"
	if truthy "$build_force" || [[ ! -f "$src_touch" ]] || [[ -n $3 ]]; then
    echo -e "INFO: Force requested in do_make(): build_force: $build_force" >>"$LOG_FILE"
		reset_touch "$cur_dir2" "${touch_prefix}*.touch"
    [[ -f Makefile && "$cur_dir2" != "$ffmpeg_source_dir" ]] && { nice make clean -j"$(get_concurrent_proc)" > >(redirect_output) 2>&1 || true; }
    if [[ -f $src_touch ]]; then
      echo -e "INFO: $src_touch found during do_make(). Uninstalling existing installation..." >>"$LOG_FILE"
      [[ -f ninja.build && "$cur_dir2" != "$ffmpeg_source_dir" ]] && { nice ninja uninstall > >(redirect_output) 2>&1 || true; }
      [[ -f Makefile && "$cur_dir2" != "$ffmpeg_source_dir" ]] && { nice make uninstall > >(redirect_output) 2>&1 || true; }
    fi
	fi
	if [ ! -f "$touch_name" ]; then
    echo "INFO: (Re-)do_make() because $touch_name not found with \"make $extra_make_options\"." >>"$LOG_FILE"
    remove_path -f "${touch_prefix}_make"*
    remove_path -f "${touch_prefix}_install"*
    { nice make clean -j"$(get_concurrent_proc)" > >(redirect_output) 2>&1 || true; }
		echo -e "INFO: Making $cur_dir2 as $ PATH=$PATH make $extra_make_options" >>"$LOG_FILE"
		if truthy "$build_cross_compile"; then
      [[ "$extra_make_options" != *"CC="* ]] && extra_make_options+=" CC=$CC"
      [[ "$extra_make_options" != *"AR="* ]] && extra_make_options+=" AR=$AR"
      [[ "$extra_make_options" != *"AS="* ]] && extra_make_options+=" AS=$AS"
      [[ "$extra_make_options" != *"RANLIB="* ]] && extra_make_options+=" RANLIB=$RANLIB"
      [[ "$extra_make_options" != *"LD="* ]] && extra_make_options+=" LD=$LD"
      [[ "$extra_make_options" != *"STRIP="* ]] && extra_make_options+=" STRIP=$STRIP"
      [[ "$extra_make_options" != *"CXX="* ]] && extra_make_options+=" CXX=$CXX"
      [[ "$extra_make_options" != *"WINDRES="* ]] && extra_make_options+=" WINDRES=$WINDRES"
      [[ "$extra_make_options" != *"RC="* ]] && extra_make_options+=" RC=$RC"
      [[ "$extra_make_options" != *"CROSS_COMPILE="* ]] && extra_make_options+=" CROSS_COMPILE=$CROSS_COMPILE"
    fi
    echo -e "INFO: do_make()with:\n  DIR=$cur_dir2\n  PATH=$PATH\n  PKG_CONFIG_PATH=$PKG_CONFIG_PATH\n  CFLAGS:$CFLAGS\n  CXXFLAGS:$CXXFLAGS\n  CPPFLAGS:$CPPFLAGS\n  LDFLAGS:$LDFLAGS\n  nice running: \"make $extra_make_options\"\n  $(get_compiler_flags)" >>"$LOG_FILE"
    # eval "bear -o "$ffmpeg_kit_src_dir/compile_commands.json nice make $extra_make_options"  > >(redirect_output) 2>&1 || exit_message 1 "do_make: could not make with $extra_make_options"
    eval "nice make -s $extra_make_options" > >(redirect_output) 2>&1 || exit_message 1 "do_make: could not make with $extra_make_options"
		create_touch_file 0 "$touch_name" # only touch if the build was OK
    add_src_dir "$(pwd)"
    find . -maxdepth 1 -name "*_src_state.touch" ! -name "$(basename "$src_touch")" -delete > >(redirect_output) 2>&1 # delete other src_state.touch files
	else
		echo -e "INFO: Already made $(dirname "$cur_dir2") $(basename "$cur_dir2") ..." >>"$LOG_FILE"
	fi
}
generic_make() {
  extra_make_options="$1"
  touch_postfix="$2"
  do_make "$extra_make_options PREFIX=$dependency_install_prefix" "$touch_postfix"
}
generic_make_install() {
  extra_install_options="$1"
  touch_postfix="$2"
  do_make_install "$extra_install_options PREFIX=$dependency_install_prefix" "" "$touch_postfix"
}
# 1. extra_make_options
# 2. extra_install_options
# 3. touch_postfix
do_make_and_make_install() {
	extra_make_options="$1"
	extra_install_options="$2"
	touch_postfix="$3"
	generic_make "$extra_make_options" "$touch_postfix"
	do_make_install "$extra_install_options" "" "$touch_postfix"
}
# 1. extra_make_install_options
# 2. override_make_install_options
# 3. touch_postfix
do_make_install() {
	local extra_make_install_options="$1"
	local override_make_install_options="$2" # startingly, some need/use something different than just 'make install'
	local touch_postfix=""
  local cur_dir2=$(pwd)
	[[ -n $3 ]] && touch_postfix="_${3}_" || touch_postfix="_"
	if [[ -z $override_make_install_options ]]; then
		local make_install_options="install $extra_make_install_options"
	else
		local make_install_options="$override_make_install_options $extra_make_install_options"
	fi
  local touch_prefix="${host_name}${touch_postfix}already_make"
	local touch_name=$(get_small_touchfile_name "${touch_prefix}_install" "make install $make_install_options")
  local src_touch="$(validate_path "$host_touch")"
  [[ ! -f "$src_touch" ]] && echo -e "INFO: $src_touch not found during do_make_install()" >>"$LOG_FILE"
	if truthy "$build_force" || [[ ! -f "$src_touch" ]] || [[ -n $4 ]]; then
    echo -e "INFO: Force requested in do_make_install(): build_force: $build_force" >>"$LOG_FILE"
		reset_touch "$cur_dir2" "${touch_prefix}_install*.touch"
    if [[ -f $src_touch ]]; then
      echo -e "INFO: $src_touch found during do_make_install(). Uninstalling existing installation..." >>"$LOG_FILE"
      [[ -f ninja.build && "$cur_dir2" != "$ffmpeg_source_dir" ]] && { nice ninja uninstall > >(redirect_output) 2>&1 || true; }
      [[ -f Makefile && "$cur_dir2" != "$ffmpeg_source_dir" ]] && { nice make uninstall > >(redirect_output) 2>&1 || true; }
    fi
	fi
	if [ ! -f "$touch_name" ]; then
    echo "INFO: (Re-)do_make_install() because $touch_name not found with \"make install $make_install_options\"." >>"$LOG_FILE"
    remove_path -f "${touch_prefix}_install"*
    if truthy "$build_cross_compile"; then
      [[ "$extra_make_options" != *"CC="* ]] && extra_make_options+=" CC=$CC"
      [[ "$extra_make_options" != *"AR="* ]] && extra_make_options+=" AR=$AR"
      [[ "$extra_make_options" != *"AS="* ]] && extra_make_options+=" AS=$AS"
      [[ "$extra_make_options" != *"RANLIB="* ]] && extra_make_options+=" RANLIB=$RANLIB"
      [[ "$extra_make_options" != *"LD="* ]] && extra_make_options+=" LD=$LD"
      [[ "$extra_make_options" != *"STRIP="* ]] && extra_make_options+=" STRIP=$STRIP"
      [[ "$extra_make_options" != *"CXX="* ]] && extra_make_options+=" CXX=$CXX"
      [[ "$extra_make_options" != *"WINDRES="* ]] && extra_make_options+=" WINDRES=$WINDRES"
      [[ "$extra_make_options" != *"RC="* ]] && extra_make_options+=" RC=$RC"
      [[ "$extra_make_options" != *"CROSS_COMPILE="* ]] && extra_make_options+=" CROSS_COMPILE=$CROSS_COMPILE"
    fi
		echo -e "INFO: do_make_install() with:\n  DIR=$(pwd)\n  PATH=$PATH\n  PKG_CONFIG_PATH=$PKG_CONFIG_PATH\n  CFLAGS:$CFLAGS\n  CXXFLAGS:$CXXFLAGS\n  CPPFLAGS:$CPPFLAGS\n  LDFLAGS:$LDFLAGS\n  nice running: \"make $make_install_options\"\n  $(get_compiler_flags)" >>"$LOG_FILE"
		eval "nice make -j$(get_concurrent_proc) $make_install_options" > >(redirect_output) 2>&1 || exit_message 1 "do_make_install: could not make with $make_install_options"
		create_touch_file 0 "$touch_name"
    add_src_dir "$(pwd)"
    find . -maxdepth 1 -name "*_src_state.touch" ! -name "$(basename "$src_touch")" -delete > >(redirect_output) 2>&1 # delete other src_state.touch files
	fi
}

# Usage example:
clean_cmake_cache() {
    local build_dir="${1:-./build}"
    local source_dir="${2:-$(pwd)}"
    do_clean_steps() {
        if [[ -f build.ninja || -f ninja.build ]]; then
             echo "  Running ninja clean..." >>"$LOG_FILE"
             nice ninja -t clean >/dev/null 2>&1 || true
        fi
        if [[ -f Makefile ]]; then
             echo "  Running make clean..." >>"$LOG_FILE"
             nice make clean -j"$(get_concurrent_proc)" >/dev/null 2>&1 || true
             nice make distclean -j"$(get_concurrent_proc)" >/dev/null 2>&1 || true
        fi
        echo "  Force removing CMake artifacts..." >>"$LOG_FILE"
        rm -rf CMakeCache.txt CMakeFiles cmake_install.cmake Makefile build.ninja ninja.build
    }
    if [[ "$(validate_path "$build_dir")" == "$(validate_path "$source_dir")" ]]; then
        echo "DEBUG: clean_cmake_cache: In-source build detected." >>"$LOG_FILE"
        do_clean_steps
    else
        echo "DEBUG: clean_cmake_cache: Out-of-source build in $build_dir" >>"$LOG_FILE"
        if [ -d "$build_dir" ]; then
            ( cd "$build_dir" && do_clean_steps )
        fi
    fi
}

# 1. extra_args
# 2. source_dir
# 3. touch_postfix
do_cmake() {
	extra_args="$1"
	local source_dir="$2"
	local touch_postfix=""
  local cur_dir2=$(pwd)
  local cmake_command="${cmake_command:-cmake}"
	[[ -n $3 ]] && touch_postfix="_${3}_" || touch_postfix="_"
	if [[ -z $source_dir ]]; then
		source_dir="$cur_dir2"
	fi
  local touch_prefix="${host_name}${touch_postfix}already"
	local touch_name=$(get_small_touchfile_name "${touch_prefix}_cmake" "cmake $extra_args")
  [[ ! -f "$source_dir/$host_touch" && ! -f "$cur_dir2/$host_touch" ]] && echo -e "INFO: $source_dir/$host_touch or $cur_dir2/$host_touch not found during do_cmake()" >>"$LOG_FILE"
	if truthy "$build_force" || [[ ! -f "$source_dir/$host_touch" && ! -f "$cur_dir2/$host_touch" ]] || [[ -n $4 ]]; then
    echo -e "INFO: Force requested in do_cmake(): build_force: $build_force" >>"$LOG_FILE"
		reset_touch "$cur_dir2" "${touch_prefix}*.touch"
    reset_touch "$source_dir" "${touch_prefix}*.touch"
    if [[ -f $src_touch ]]; then
      echo -e "INFO: $src_touch found during do_cmake(). Uninstalling existing installation..." >>"$LOG_FILE"
      [[ -f ninja.build && "$cur_dir2" != "$ffmpeg_kit_src_dir/build" ]] && { nice ninja uninstall > >(redirect_output) 2>&1 || true; }
      [[ -f Makefile && "$cur_dir2" != "$ffmpeg_kit_src_dir/build" ]] && { nice make uninstall > >(redirect_output) 2>&1 || true; }
    fi
    { clean_cmake_cache "$cur_dir2" "$(validate_path "$source_dir")" || true; }
	fi
	if [ ! -f "$touch_name" ]; then
    echo "INFO: (Re-)do_cmake() because $touch_name not found with \"cmake $extra_args\"." >>"$LOG_FILE"
    reset_touch "$cur_dir2" "${touch_prefix}*.touch"
    reset_touch "$source_dir" "${touch_prefix}*.touch"
    [[ -f ninja.build && "$cur_dir2" != "$ffmpeg_kit_src_dir/build" ]] && { nice ninja uninstall > >(redirect_output) 2>&1 || true; }
    [[ -f Makefile && "$cur_dir2" != "$ffmpeg_kit_src_dir/build" ]] && { nice make uninstall > >(redirect_output) 2>&1 || true; }
    { clean_cmake_cache "$cur_dir2" "$(validate_path "$source_dir")" || true; }
    [[ ! -d "$cur_dir2" ]] && create_dir "$cur_dir2"
		local config_options=""
    local command="${source_dir} -DCMAKE_MESSAGE_LOG_LEVEL=VERBOSE"
		command+=" $extra_args"
		echo -e "INFO: do_cmake() nice running:\n  DIR=$cur_dir2\n  PATH=$PATH\n  PKG_CONFIG_PATH=$PKG_CONFIG_PATH\n  CFLAGS:$CFLAGS\n  CXXFLAGS:$CXXFLAGS\n  CPPFLAGS:$CPPFLAGS\n  LDFLAGS:$LDFLAGS\n  \"${cmake_command} -G\"Unix Makefiles\" $command\"\n  $(get_compiler_flags)" >>"$LOG_FILE"
		# shellcheck disable=SC2086
		eval "nice -n 5 ${cmake_command} -G\"Unix Makefiles\" $command" > >(redirect_output) 2>&1 || exit_message 1 "do_cmake: could not run nice: \"nice -n 5 ${cmake_command} -G\"Unix Makefiles\" $command\""
		create_touch_file 0 "$touch_name"
    add_src_dir "$(pwd)" "$source_dir"
    find . -maxdepth 1 -name "*_src_state.touch" ! -name "$(basename "$src_touch")" -delete > >(redirect_output) 2>&1 # delete other src_state.touch files
	fi
}
generic_cmake() {
  # 1. extra_args
  # 2. source_dir
  # 3. touch_postfix
  extra_args="$1"
  source_dir="$2"
	touch_postfix="$3"
  if iswindows; then
    [[ "$extra_args" != *"-DENABLE_STATIC_RUNTIME"* ]] && extra_args+=" -DENABLE_STATIC_RUNTIME=1"
    [[ "$extra_args" != *"-DCMAKE_CROSSCOMPILING"* ]] && extra_args+=" -DCMAKE_CROSSCOMPILING=1"
    [[ "$extra_args" != *"-DCMAKE_TOOLCHAIN_FILE"* ]] && extra_args+=" -DCMAKE_TOOLCHAIN_FILE=$(get_generic_cmake_toolchain)"
    [[ "$extra_args" != *"-DCMAKE_EXE_LINKER_FLAGS"* ]] && extra_args+=" -DCMAKE_EXE_LINKER_FLAGS=\"-static\""
    [[ "$extra_args" != *"-DCMAKE_SHARED_LINKER_FLAGS"* ]] && extra_args+=" -DCMAKE_SHARED_LINKER_FLAGS=\"-static\""
    [[ "$extra_args" != *"-DCMAKE_MODULE_LINKER_FLAGS"* ]] && extra_args+=" -DCMAKE_MODULE_LINKER_FLAGS=\"-static\""
    [[ "$extra_args" != *"-DCMAKE_CXX_STANDARD_LIBRARIES"* ]] && extra_args+=" -DCMAKE_CXX_STANDARD_LIBRARIES=\"$GXX_STANDARD_LIBS\""
    [[ "$extra_args" != *"-DCMAKE_C_STANDARD_LIBRARIES"* ]] && extra_args+=" -DCMAKE_C_STANDARD_LIBRARIES=\"$GCC_STANDARD_LIBS\""
    [[ "$extra_args" != *"-DCMAKE_SYSTEM_LIBRARY_PATH"* ]] && extra_args+=" -DCMAKE_SYSTEM_LIBRARY_PATH=\"/usr/local/mingw-w64/$host_arch-w64-mingw32/lib;\
/usr/local/mingw-w64/lib/gcc/$host_arch-w64-mingw32/15.2.0;${dependency_install_prefix}/lib\""
    [[ "$extra_args" != *"-DCMAKE_LIBRARY_PATH"* ]] && extra_args+=" -DCMAKE_LIBRARY_PATH=\"/usr/local/mingw-w64/$host_arch-w64-mingw32/lib;\
/usr/local/mingw-w64/lib/gcc/$host_arch-w64-mingw32/15.2.0;${dependency_install_prefix}/lib\""
  fi
  if isandroid; then
    [[ "$extra_args" != *"-DCMAKE_ANDROID_API"* ]] && extra_args+=" -DCMAKE_ANDROID_API=$ANDROID_API_LEVEL"
  fi
  [[ "$extra_args" != *"-DCMAKE_SYSTEM_PROCESSOR"* ]] && extra_args+=" -DCMAKE_SYSTEM_PROCESSOR=\"$cmake_host_arch\""
  [[ "$extra_args" != *"-DCMAKE_BUILD_TYPE"* ]] && extra_args+=" -DCMAKE_BUILD_TYPE=Release"
  if ismacos; then
  [[ "$extra_args" != *"-DCMAKE_SYSTEM_NAME"* ]] && extra_args+=" -DCMAKE_SYSTEM_NAME=Darwin"
  [[ "$extra_args" != *"-DCMAKE_OSX_ARCHITECTURES"* ]] && extra_args+=" -DCMAKE_OSX_ARCHITECTURES=$host_arch"
  [[ "$extra_args" != *"-DCMAKE_OSX_DEPLOYMENT_TARGET"* ]] && extra_args+=" -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_MACOS_VERSION"
  [[ "$extra_args" != *"-DCMAKE_OSX_SYSROOT"* ]] && extra_args+=" -DCMAKE_OSX_SYSROOT=$(xcrun --sdk "$toolchain_sys" --show-sdk-path)"
  elif isiossimulator; then
  [[ "$extra_args" != *"-DCMAKE_SYSTEM_NAME"* ]] && extra_args+=" -DCMAKE_SYSTEM_NAME=iOS"
  [[ "$extra_args" != *"-DCMAKE_OSX_ARCHITECTURES"* ]] && extra_args+=" -DCMAKE_OSX_ARCHITECTURES=$host_arch"
  [[ "$extra_args" != *"-DCMAKE_OSX_DEPLOYMENT_TARGET"* ]] && extra_args+=" -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_IOS_VERSION"
  [[ "$extra_args" != *"-DCMAKE_OSX_SYSROOT"* ]] && extra_args+=" -DCMAKE_OSX_SYSROOT=$(xcrun --sdk "$toolchain_sys" --show-sdk-path)"
  elif isios; then
  [[ "$extra_args" != *"-DCMAKE_SYSTEM_NAME"* ]] && extra_args+=" -DCMAKE_SYSTEM_NAME=iOS"
  [[ "$extra_args" != *"-DCMAKE_OSX_ARCHITECTURES"* ]] && extra_args+=" -DCMAKE_OSX_ARCHITECTURES=$host_arch"
  [[ "$extra_args" != *"-DCMAKE_OSX_DEPLOYMENT_TARGET"* ]] && extra_args+=" -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_IOS_VERSION"
  [[ "$extra_args" != *"-DCMAKE_OSX_SYSROOT"* ]] && extra_args+=" -DCMAKE_OSX_SYSROOT=$(xcrun --sdk "$toolchain_sys" --show-sdk-path)"
  else
  [[ "$extra_args" != *"-DCMAKE_SYSTEM_NAME"* ]] && extra_args+=" -DCMAKE_SYSTEM_NAME=${host_platform^}"
  fi
	# [[ "$extra_args" != *"-DCMAKE_FIND_ROOT_PATH"* ]] && extra_args+=" -DCMAKE_FIND_ROOT_PATH=$dependency_install_prefix"
  # [[ "$extra_args" != *"-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM"* ]] && extra_args+=" -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER"
  [[ "$extra_args" != *"-DCMAKE_INSTALL_LIBDIR"* ]] && extra_args+=" -DCMAKE_INSTALL_LIBDIR=lib"
  [[ "$extra_args" != *"-DCMAKE_INSTALL_PREFIX"* ]] && extra_args+=" -DCMAKE_INSTALL_PREFIX=$dependency_install_prefix"
  # [[ "$extra_args" != *"-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY"* ]] && extra_args+=" -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY"
  # [[ "$extra_args" != *"-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE"* ]] && extra_args+=" -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY"
  # [[ "$extra_args" != *"-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE"* ]] && extra_args+=" -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY"
  [[ "$extra_args" != *"-DBUILD_STATIC_LIBS"* ]] && extra_args+=" -DBUILD_STATIC_LIBS=ON"
  [[ "$extra_args" != *"-DBUILD_SHARED_LIBS"* ]] && extra_args+=" -DBUILD_SHARED_LIBS=OFF"
  [[ "$extra_args" != *"-DENABLE_STATIC"* ]] && extra_args+=" -DENABLE_STATIC=ON"
  [[ "$extra_args" != *"-DENABLE_SHARED"* ]] && extra_args+=" -DENABLE_SHARED=OFF"
  [[ "$extra_args" != *"-DCMAKE_POSITION_INDEPENDENT_CODE"* ]] && extra_args+=" -DCMAKE_POSITION_INDEPENDENT_CODE=1"
  do_cmake "$extra_args" "$source_dir" "$touch_postfix"
}
# 1. source_dir
# 2. extra_args
# 3. touch_postfix
do_cmake_from_build_dir() { # some sources don't allow it, weird XXX combine with the above :)
	source_dir="$1"
	extra_args="$2"
	touch_postfix="$3"
	generic_cmake "$extra_args" "$source_dir" "$touch_postfix"
}
# 1. extra_args
# 2. source_dir
# 3. touch_postfix
do_cmake_and_install() {
	extra_args="$1"
	source_dir="$2"
	touch_postfix="$3"
	generic_cmake "$extra_args" "$source_dir" "$touch_postfix"
	do_make_and_make_install "" "" "$touch_postfix"
}

activate_meson() {
	echo -e "INFO: Activating meson" >>"$LOG_FILE"
	change_dir "$src_dir" # requires python3-full
	if [[ ! -d "$src_dir/meson" ]]; then
		do_git_checkout https://github.com/mesonbuild/meson.git meson "1.9.1"
	fi
	export local_meson="$src_dir/meson/meson.py"
	change_dir "$src_dir"
}
# 1. configure_options
# 2. configure_name
# 2. configure_env
# 4. touch_postfix
# shellcheck disable=2178,2206,2128
do_meson() {
	local configure_options="$1"
	local input_configure=($2)
	local configure_env="$3"
	local touch_postfix=""
  local configure_name=()
	[[ -n $4 ]] && touch_postfix="_${4}_" || touch_postfix="_"
	if [[ -z "${input_configure[*]}" || "${input_configure[*]}" == "setup build" ]]; then
    echo "INFO: Adding cross file to meson = $build_cross_compile" >>"$LOG_FILE"
    if truthy "$build_cross_compile"; then
      local cross_file="$(get_generic_meson_cross_file)"
      configure_name+=("setup")
      configure_name+=("--cross-file $cross_file")
      configure_name+=("build")
    else
      configure_name+=("setup")
      configure_name+=("build")
    fi
    echo "INFO: Cross compiling = $build_cross_compile Configure name = ${configure_name[*]}" >>"$LOG_FILE"
    command_name="setup_build"
		configure_options+=" --unity=off --warnlevel=0"
  else
    configure_name=$($input_configure)
    command_name="${configure_name[*]}"
	fi
	if [[ -e "$local_meson" ]]; then
    configure_command=(python3 "$local_meson" "${configure_name[*]}")
	else
		configure_command=(meson)
	fi
	local cur_dir2=$(pwd)
	local english_name=$(basename "$cur_dir2")
  local touch_prefix="${host_name}${touch_postfix}already_meson"
	local touch_name=$(get_small_touchfile_name "${touch_prefix}_${command_name}" "meson $configure_options")
  local src_touch="$(validate_path "$host_touch")"
  [[ ! -f "$src_touch" ]] && echo -e "INFO: $src_touch not found during do_meson()" >>"$LOG_FILE"
	if truthy "$build_force" || [[ ! -f "$src_touch" ]]; then
    echo -e "INFO: Force requested in do_meson(): build_force: $build_force" >>"$LOG_FILE"
    if [[ "$command_name" == "setup_build" ]]; then
		  reset_touch "$cur_dir2" "${touch_prefix}*.touch"
    else
      reset_touch "$cur_dir2" "${touch_prefix}_${command_name}*.touch"
    fi
    [[ -f ninja.build ]] && { nice ninja uninstall > >(redirect_output) 2>&1 || true; }
    [[ -f Makefile ]] && { nice make uninstall > >(redirect_output) 2>&1 || true; }
    { python3 "$local_meson" compile --clean -C build > >(redirect_output) 2>&1 || true; }
    { python3 "$local_meson" setup --wipe build > >(redirect_output) 2>&1 || true; }
    [[ "$command_name" == "setup_build" ]] && [[ -d "$(pwd)/build" ]] && { remove_path -rf "build" || true; }
	fi
	if [ ! -f "$touch_name" ]; then
    echo "INFO: (Re-)do_meson() because $touch_name not found with \"meson $configure_options\"." >>"$LOG_FILE"
		if [[ -n "$command_name" && -d "$(pwd)/build" && "$command_name" == "setup_build" ]]; then
      reset_touch "$cur_dir2" "${touch_prefix}*.touch"
      [[ -f ninja.build ]] && { nice ninja uninstall > >(redirect_output) 2>&1 || true; }
      [[ -f Makefile ]] && { nice make uninstall > >(redirect_output) 2>&1 || true; }
      { python3 "$local_meson" compile --clean -C build > >(redirect_output) 2>&1 || true; }
      { python3 "$local_meson" setup --wipe build > >(redirect_output) 2>&1 || true; }
      [[ "$command_name" == "setup_build" ]] && [[ -d "build" ]] && { remove_path -rf "build" || true; }
			echo -e "INFO: Adding --reconfigure to meson config because there is an existing previous build" >>"$LOG_FILE"
			configure_options+=" --reconfigure"
    else
      remove_path -f "${touch_prefix}_meson_${command_name}"*
		fi
		echo -e "INFO: Using meson:\n  DIR=$cur_dir2\n  PATH=$PATH\n  PKG_CONFIG_PATH=$PKG_CONFIG_PATH\n  CFLAGS:$CFLAGS\n  CXXFLAGS:$CXXFLAGS\n  CPPFLAGS:$CPPFLAGS\n  LDFLAGS:$LDFLAGS\n  ${configure_command[*]} $configure_options\nCross compiling = $build_cross_compile $(get_compiler_flags)" >>"$LOG_FILE"
		#env
		export MESON_BUILD_ROOT="$(pwd)/build"
		export MESON_SOURCE_ROOT="$(pwd)"
		#create_dir "$(pwd)/build"
		# shellcheck disable=SC2086
		# shellcheck disable=SC1078
		eval "${configure_command[*]} $configure_options" > >(redirect_output) 2>&1 || exit_message 1 "do_meson: could not run configure ${configure_command[*]}"
		create_touch_file 0 "$touch_name"
    add_src_dir "$(pwd)"
    find . -maxdepth 1 -name "*_src_state.touch" ! -name "$(basename "$src_touch")" -delete > >(redirect_output) 2>&1 # delete other src_state.touch files
	else
		echo -e "INFO: Already used meson $(basename "$cur_dir2")" >>"$LOG_FILE"
	fi
}
# 1. extra_args
# 2. touch_postfix
generic_meson() {
	local extra_configure_options="$1"
	local touch_postfix="$2"
	#create_dir "$(pwd)/build"
  [[ "$extra_configure_options" != *buildtype* ]] && extra_configure_options+=" -Dbuildtype=release"
  [[ "$extra_configure_options" != *libdir* ]] && extra_configure_options+=" -Dlibdir=${dependency_install_prefix}/lib"
  [[ "$extra_configure_options" != *prefix* ]] && extra_configure_options+=" -Dprefix=${dependency_install_prefix}"
  [[ "$extra_configure_options" != *default-library* ]] && extra_configure_options+=" --default-library=static"
  [[ "$extra_configure_options" != *staticpic* ]] && extra_configure_options+=" -Db_staticpic=true"
  [[ "$extra_configure_options" != *wrap-mode* ]] && extra_configure_options+=" --wrap-mode=nofallback"
	do_meson "$extra_configure_options" "setup build" "$touch_postfix"
}
# 1. extra_args
# 2. touch_postfix
generic_meson_ninja_install() {
	generic_meson "$1" "$2"
	do_ninja_and_ninja_install "$1" "$2"
}
# 1. extra_args
# 2. touch_postfix
do_ninja_and_ninja_install() {
	local extra_ninja_options="$1"
	local touch_postfix=""
  local cur_dir2=$(pwd)
	[[ -n $2 ]] && touch_postfix="_${2}_" || touch_postfix="_"
	do_ninja "$extra_ninja_options" "$touch_postfix"
  local touch_prefix="${host_name}${touch_postfix}already_ninja"
	local touch_name=$(get_small_touchfile_name "${touch_prefix}_install" "ninja install $extra_ninja_options")
  local src_touch="$(validate_path "$host_touch")"
  [[ ! -f "$src_touch" ]] && echo -e "INFO: $src_touch not found during do_ninja_and_ninja_install()" >>"$LOG_FILE"
	if truthy "$build_force" || [[ ! -f "$src_touch" ]]; then
    echo -e "INFO: Force requested in do_ninja_and_ninja_install(): build_force: $build_force" >>"$LOG_FILE"
		reset_touch "$cur_dir2" "${touch_prefix}_ninja_install*.touch"
	fi
	if [ ! -f "$touch_name" ]; then
    echo "INFO: (Re-)do_ninja_and_ninja_install() because $touch_name not found with \"ninja install $extra_ninja_options\"." >>"$LOG_FILE"
    remove_path -f "${touch_prefix}_ninja_install"* # reset
		echo -e "INFO: do_ninja() with:\n  DIR=$cur_dir2\n  PATH=$PATH\n  PKG_CONFIG_PATH=$PKG_CONFIG_PATH\n  CFLAGS:$CFLAGS\n  CXXFLAGS:$CXXFLAGS\n  CPPFLAGS:$CPPFLAGS\n  LDFLAGS:$LDFLAGS\n  in $(pwd) ninja running: \"build $extra_make_options\"\n  $(get_compiler_flags)" >>"$LOG_FILE"
		ninja -C build install > >(redirect_output) 2>&1 || exit_message 1 "do_ninja_and_ninja_install: could not do_ninja() in $(pwd) ninja running: \"build $extra_make_options\""
		create_touch_file 0 "$touch_name"
    add_src_dir "$(pwd)"
    find . -maxdepth 1 -name "*_src_state.touch" ! -name "$(basename "$src_touch")" -delete > >(redirect_output) 2>&1 # delete other src_state.touch files
	fi
}

# 1. touch_postfix
do_ninja() {
	local touch_postfix=""
	[[ -n $1 ]] && touch_postfix="_${1}_" || touch_postfix="_"
	local extra_make_options=" -j $(get_concurrent_proc)"
	local cur_dir2=$(pwd)
  local touch_prefix="${host_name}${touch_postfix}already_ninja"
	local touch_name=$(get_small_touchfile_name "${touch_prefix}_build" "ninja build $extra_make_options")
  local src_touch="$(validate_path "$host_touch")"
  [[ ! -f "$src_touch" ]] && echo -e "INFO: $src_touch not found during do_ninja()" >>"$LOG_FILE"
	if truthy "$build_force" || [[ ! -f "$src_touch" ]]; then
    echo -e "INFO: Force requested in do_ninja(): build_force: $build_force" >>"$LOG_FILE"
		reset_touch "$cur_dir2" "${touch_prefix}*.touch"
    if [[ -f $src_touch ]]; then
      echo -e "INFO: $src_touch found during do_ninja(). Uninstalling existing installation..." >>"$LOG_FILE"
      [[ -f ninja.build ]] && { nice ninja uninstall > >(redirect_output) 2>&1 || true; }
      [[ -f Makefile ]] && { nice make uninstall > >(redirect_output) 2>&1 || true; }
    fi
	fi
	if [ ! -f "$touch_name" ]; then
    echo "INFO: (Re-)do_ninja() because $touch_name not found with \"ninja build $extra_make_options\"." >>"$LOG_FILE"
    reset_touch "$cur_dir2" "${touch_prefix}*.touch"
		echo -e "INFO: ninja-ing $cur_dir2 as PATH=$PATH ninja -C build $extra_make_options" >>"$LOG_FILE"
		echo -e "INFO: do_ninja() ninja running:\n  DIR=$cur_dir2\n  PATH=$PATH\n  PKG_CONFIG_PATH=$PKG_CONFIG_PATH\n  CFLAGS:$CFLAGS\n  CXXFLAGS:$CXXFLAGS\n  CPPFLAGS:$CPPFLAGS\n  LDFLAGS:$LDFLAGS\n  \"build $extra_make_options\"\n  $(get_compiler_flags)" >>"$LOG_FILE"
		# shellcheck disable=SC2086
		ninja -C build ${extra_make_options} > >(redirect_output) 2>&1 || exit_message 1 "do_ninja: could not do_ninja() ninja running: \"build $extra_make_options\""
		create_touch_file 0 "$touch_name"
    add_src_dir "$(pwd)"
    find . -maxdepth 1 -name "*_src_state.touch" ! -name "$(basename "$src_touch")" -delete > >(redirect_output) 2>&1 # delete other src_state.touch files
	else
		echo -e "INFO: already did ninja $(basename "$cur_dir2")" >>"$LOG_FILE"
	fi
}

# 1. url
# 2. patch_type
# 3. extra_args
apply_patch() {
  local patch="$1"
  if git apply --reverse --check --ignore-space-change --ignore-whitespace --verbose "$patch" >/dev/null 2>&1; then
    echo "INFO: Patch already applied. Skipping." >>"$LOG_FILE"
  else
    echo "INFO: Applying $patch..." >>"$LOG_FILE"
    git apply --whitespace=fix --verbose "$patch" > >(redirect_output) 2>&1 || exit_message 1 "apply_patch: unable to patch $patch"
  fi
}
validate_path() {
  local target_path="$1"
  [[ ! -d "$target_path" && ! -f "$target_path" && "$target_path" != *.touch ]] && mkdir -p "$target_path"
  local abs_path
  if [[ -d "$target_path" ]]; then
    abs_path=$(cd "$target_path" && pwd)
  elif [[ -f "$target_path" ]]; then
    abs_path="$(realpath "$target_path")"
  else
    abs_path="$(pwd)/$target_path"
  fi
  echo "$abs_path"
}
# takes a url, output_dir as params, output_dir optional
download_and_unpack_file() {
    local url="$1"
    local dest_folder="$(validate_path "$2")"
    local filename
    filename=$(basename "$url")
    if [[ -n "$dest_folder" ]]; then
        if [ ! -d "$dest_folder" ]; then
            create_dir "$dest_folder" || exit_message 1 "download_and_unpack_file: could not create dir $dest_folder"
            chmod -R a+rwx "$dest_folder"
        fi
    fi
    local touch_name="$dest_folder"/"$(get_small_touchfile_name "already_unpacked_successfully" "$url")"
    local touch_file="$dest_folder/$host_touch"
    [[ -z "$touch_file" ]] && exit_message 1 "could not determine touch file: $touch_file"
    [[ ! -f "$touch_file" ]] && echo -e "INFO: $touch_file not found during download_and_unpack_file()" >>"$LOG_FILE"
    if [ ! -f "$touch_name" ] || truthy "$build_force"; then
        echo "INFO: Downloading $url into $dest_folder" >>"$LOG_FILE"
        remove_path -f "$dest_folder"
        create_dir "$dest_folder"
        if [[ "$filename" == *.zst ]] && ! command -v zstd &> /dev/null; then
             exit_message 1 "download_and_unpack_file: zstd is not installed. Run: sudo $INSTALL_COMMAND install zstd"
        fi
        if [[ -f "$filename" ]]; then
            rm -f "$filename"
        fi
        curl -v -4 "$url" --retry 5 -o "$filename" -L --fail > >(redirect_output) 2>&1 || {
            exit_message 1 "download_and_unpack_file: unable to download $url"
        }
        echo "INFO: Unzipping $filename inside $dest_folder ..." >>"$LOG_FILE"
        if [[ "${filename,,}" =~ \.(zip|whl|nupkg)$ ]]; then
            extract_zip "$filename" "$dest_folder" > >(redirect_output) 2>&1
            #unzip -o "$filename" > >(redirect_output) 2>&1 || exit_message 1 "unzip failed"
        else
            extract_tar "$filename" "$dest_folder" > >(redirect_output) 2>&1
            #tar -xf "$filename" > >(redirect_output) 2>&1 || exit_message 1 "tar failed"
        fi
        remove_path -f "$filename"
        chmod -R a+rwx "$dest_folder"
        create_touch_file 0 "$touch_name"
        add_src_dir "$(validate_path "$dest_folder")"
    else
      echo "DEBUG: Archive already downloaded and extracted at $dest_folder" >>"$LOG_FILE"
      chmod -R a+rwx "$dest_folder"
    fi
}
extract_tar() {
    local archive="$1"
    local dest_dir=${2:-"$(basename "$archive" | sed -e  s/\.tar\.*//)"}
    
    # Get unique top-level items using mapfile
    local top_items
    mapfile -t top_items < <(tar -tf "$archive" --strip-components=0 | cut -d/ -f1 | sort -u  || exit_message 1 "extract_tar: could not extract archive")
    
    if [[ ${#top_items[@]} -eq 1 ]]; then
        # Single top-level directory
        tar -xf "$archive" -C "$dest_dir" --strip-components=1 || exit_message 1 "extract_tar: could not extract archive"
    else
        # Multiple items at root
        tar -xf "$archive" -C "$dest_dir" || exit_message 1 "extract_tar: could not extract archive"
    fi
}
extract_zip() {
    local archive="$1"
    local dest_dir=${2:-"$(basename "$archive" | sed -e  s/\.zip//)"}
    
    # Get unique top-level items using mapfile
    local top_items
    mapfile -t top_items < <(unzip -Z -1 "$archive" | cut -d/ -f1 | sort -u  || exit_message 1 "extract_zip: could not extract archive")
    
    if [[ ${#top_items[@]} -eq 1 ]]; then
        # Single top-level directory
        mkdir -p "$dest_dir"
        # Extract everything then move contents up one level
        unzip -o "$archive" -d "$dest_dir" || exit_message 1 "extract_zip: could not extract archive"
        # Move contents up one level
        shopt -s dotglob  # Include hidden files
        mv "$dest_dir/${top_items[0]}/"* "$dest_dir/" 2>/dev/null || true
        shopt -u dotglob
        rmdir "$dest_dir/${top_items[0]}" 2>/dev/null || true
    else
        # Multiple items: normal extraction
        unzip -o "$archive" -d "$dest_dir" || exit_message 1 "extract_zip: could not extract archive"
    fi
}

# 1. url, 
# 2. optional to_dir
# 3. extra_configure_options
generic_download_and_make_and_install() {
	local url="$1"
	local to_dir=${2:-"$(basename "$url" | sed -e  s/\.tar\.*//)"}
	local extra_configure_options="$3"
	change_dir "$src_dir"
  download_and_unpack_file "$url" "$to_dir"
	change_dir "$src_dir/$to_dir"
	generic_configure "$extra_configure_options"
	do_make_and_make_install
	change_dir "$src_dir"
}

# 1. extra_config_args
# 2. configure_name
# 3. extra_make_options
# 4. extra_install_options
# 5. touch_postfix
# shellcheck disable=2128,2178
generic_configure_make_install() {
	local extra_config_args="$1"
  local configure_name="$2"
	local extra_make_options="$3"
	local extra_install_options="$4"
	local touch_postfix="$5"
	generic_configure "$extra_config_args" "$configure_name" "$touch_postfix" # no parameters, force myself to break it up if needed
	do_make_and_make_install "$extra_make_options" "$extra_install_options" "$touch_postfix"
}
# 1. git url
# 2. optional to_dir
# 3. version
do_git_checkout_and_make_install() {
	local url=$1
	local git_checkout_name=${2:-"$(basename "$url" | sed -e  s/\.git//)"} # http://y/abc.git -> abc
  local git_version="$3"
  change_dir "$src_dir"
	do_git_checkout "$url" "$git_checkout_name" "$git_version"
	change_dir "$src_dir/$git_checkout_name"
	generic_configure_make_install
	change_dir "$src_dir"
}

# 1. lib
# 2. lib_s
gen_ld_script() {
	library=$dependency_install_prefix/lib/$1
	lib_s="$2"
	if [[ ! -f $dependency_install_prefix/lib/lib$lib_s.a ]]; then
		echo -e "Generating linker script $library: $2 $3" >>"$LOG_FILE"
		mv -f "$library" "$dependency_install_prefix"/lib/lib"$lib_s".a
		echo -e "GROUP ( $dependency_install_prefix/lib/lib$lib_s.a $3 )" >"$library"
	fi
}

install_local_dependency() {
  eval "$INSTALL_COMMAND update && sudo $INSTALL_COMMAND install -y $*" > >(redirect_output) 2>&1 || exit_message 1 "install_local_dependency: failed to install required dependencies"
}

# usage: generate_pkg_config -t=<scan_dir> -o=<output_pc_file> -i=<install_prefix> -n=<name> [-v=<ver>] [-d=<desc>] [-l=<libs>]
generate_pkg_config() {
    local TARGET_SCAN_DIR=""
    local OUTPUT_FILE=""
    local INSTALL_PREFIX=""
    local LIB_VERSION="0.0.0"
    local LIB_NAME=""
    local LIB_DESC=""
    local EXTRA_LIBS=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t=*|--target=*)  TARGET_SCAN_DIR="${1#*=}"; shift ;;
            -o=*|--output=*)  OUTPUT_FILE="${1#*=}"; shift ;;
            -i=*|--install=*) INSTALL_PREFIX="${1#*=}"; shift ;;
            -v=*|--version=*) LIB_VERSION="${1#*=}"; shift ;;
            -n=*|--name=*)    LIB_NAME="${1#*=}"; shift ;;
            -d=*|--desc=*)    LIB_DESC="${1#*=}"; shift ;;
            -l=*|--libs=*)    EXTRA_LIBS="${1#*=}"; shift ;;
            --help)           echo "Usage: generate_pkg_config -t=<scan_dir> -o=<output_pc_file> -i=<install_prefix> -n=<name> [-v=<ver>] [-d=<desc>] [-l=<libs>]"; return 0 ;;
            *)                echo "ERROR: Unknown option '$1'"; return 1 ;;
        esac
    done

    # Must provide either TARGET_SCAN_DIR or EXTRA_LIBS
    if [[ -z "$TARGET_SCAN_DIR" && -z "$EXTRA_LIBS" ]]; then
        echo "Error: Must provide either TARGET_SCAN_DIR or EXTRA_LIBS."
        return 1
    fi

    # Validate required arguments
    if [[ -z "$OUTPUT_FILE" || -z "$INSTALL_PREFIX" || -z "$LIB_NAME" ]]; then
        echo "Error: Missing required arguments."
        echo "Usage: generate_pkg_config -t=<scan_dir> -o=<output_pc_file> -i=<install_prefix> -n=<name> [-v=<ver>] [-d=<desc>] [-l=<libs>]"
        return 1
    fi

    # Create directory for output file if it doesn't exist
    local OUT_DIR
    OUT_DIR=$(dirname "$OUTPUT_FILE")
    mkdir -p "$OUT_DIR"

    local libs_list=()
    local found_files

    if [[ -n "$EXTRA_LIBS" ]]; then
      while IFS= read -r lib_name; do
          if [[ "$lib_name" == -l* ]]; then
              libs_list+=("${lib_name//lib/}")
          else
              libs_list+=("-l${lib_name//lib/}")
          fi
      done <<< "$EXTRA_LIBS"
    fi

    if [[ -n "$TARGET_SCAN_DIR" ]]; then
      # Use process substitution to avoid subshell variable scope issues
      while IFS= read -r -d '' file_path; do
          local filename
          filename=$(basename "$file_path")
          local name=$(basename "$file_path")
          name="${name#lib}"
          name=$(echo "$name" | sed -e 's/\.(dll\.a|so|a|dll|dylib)(\.[0-9.]+)?$//')
          # Avoid duplicates in the list
          # shellcheck disable=2076
          if [[ ! " ${libs_list[*]} " =~ " ${name} " ]]; then
              libs_list+=("-l${name//lib/}")
          fi
      done < <(find "$TARGET_SCAN_DIR" -maxdepth 1 -type f \( -name "*.dll*" -o -name "*.dll.a*" -o -name "*.a*" -o -name "*.so*" -o -name "*.dylib" \) -print0)
    fi
    [[ ! -d "$(dirname "$OUTPUT_FILE")" ]] && create_dir "$(dirname "$OUTPUT_FILE")"
    # ---------------------------------------------------------
    # Generate .pc File Content
    # ---------------------------------------------------------
    # de-duplicate libs_list
    libs_list=("$(echo "${libs_list[*]}" | tr " " "\n" | sort -u)")
    cat > "$OUTPUT_FILE" <<EOF
prefix=${INSTALL_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: ${LIB_NAME}
Description: ${LIB_DESC:-No description provided}
Version: ${LIB_VERSION}
Libs: -L\${libdir} ${libs_list[*]}
Cflags: -I\${includedir}
EOF
    [[ -f "$OUTPUT_FILE" ]] && { echo "INFO: Generated pkg-config file at: $OUTPUT_FILE" >>"$LOG_FILE"; return 0; }
    [[ ! -f "$OUTPUT_FILE" ]] && { echo "ERROR: Failed to generated pkg-config file at: $OUTPUT_FILE" >>"$LOG_FILE"; return 1; }
}

# Usage: check_pkg_config_files <path_to_file.pc>
check_pkg_config_files() {
    local PC_FILE_PATH="$1"

    if [ -z "$PC_FILE_PATH" ]; then
        echo "DEBUG: Usage: check_pkg_config_files <path_to_file.pc>" | tee -a "$LOG_FILE"
        return 1
    fi

    # 1. Setup Environment
    # Temporarily add the .pc file's directory to PKG_CONFIG_PATH so the tool can read it
    local PC_DIR
    PC_DIR=$(dirname "$(validate_path "$PC_FILE_PATH")")
    local PC_NAME
    PC_NAME=$(basename "$PC_FILE_PATH" .pc)

    export PKG_CONFIG_PATH="$PC_DIR:$PKG_CONFIG_PATH"
    echo -e "DEBUG: PKG_CONFIG_PATH:\n$PKG_CONFIG_PATH" >>"$LOG_FILE"

    echo "INFO: --- Inspecting: $PC_NAME ---" >>"$LOG_FILE"

    # 2. Check Include Directories (-I)
    echo "  Checking Include Paths:"
    local cflags
    if ! cflags=$(pkg-config --cflags-only-I "$PC_NAME" 2>/dev/null); then
        echo "  [Error] Could not parse Cflags. Syntax error in .pc file?" | tee -a "$LOG_FILE"
        return 1
    fi

    for flag in $cflags; do
        # Remove -I prefix
        local dir="${flag#-I}"
        if [ -d "$dir" ]; then
            echo "  [OK] Found dir: $dir" >>"$LOG_FILE"
        else
            echo "  [MISSING] Directory not found: $dir" >>"$LOG_FILE"
        fi
    done

    # 3. Check Library Directories (-L)
    echo "  Checking Library Paths:" >>"$LOG_FILE"
    local ldflags
    ldflags=$(pkg-config --libs-only-L "$PC_NAME")
    # Create an array of search paths
    local search_paths=()
    for flag in $ldflags; do
        local dir="${flag#-L}"
        if [ -d "$dir" ]; then
            echo "  [OK] Found dir: $dir" >>"$LOG_FILE"
            search_paths+=("$dir")
        else
            echo "  [MISSING] Library Path not found: $dir" >>"$LOG_FILE"
        fi
    done

    # 4. Check Individual Libraries (-l)
    echo "  Checking Libraries:" >>"$LOG_FILE"
    local libs
    libs=$(pkg-config --libs-only-l "$PC_NAME")
    
    for library in $libs; do
        local lib_name="${library#-l}"
        local found=false
        
        # Search in all -L paths found earlier
        for path in "${search_paths[@]}"; do
            # Check for MinGW/Linux naming conventions
            # 1. libNAME.a (Static MinGW/Linux)
            # 2. libNAME.dll.a (Import MinGW)
            # 3. NAME.lib (MSVC style, sometimes used by lld)
            # 4. libNAME.so (Linux shared)
            
            if   [ -f "$path/lib${lib_name}.a" ]; then found=true; found_path="$path/lib${lib_name}.a"
            elif [ -f "$path/lib${lib_name}.dll.a" ]; then found=true; found_path="$path/lib${lib_name}.dll.a"
            elif [ -f "$path/${lib_name}.lib" ]; then found=true; found_path="$path/${lib_name}.lib"
            elif [ -f "$path/lib${lib_name}.so" ]; then found=true; found_path="$path/lib${lib_name}.so"
            elif [ -f "$path/lib${lib_name}.dylib" ]; then found=true; found_path="$path/lib${lib_name}.dylib"
            fi
            
            if [ "$found" = true ]; then
                break
            fi
        done

        if [ "$found" = true ]; then
            echo "  [OK] Found -l$lib_name -> $found_path" >>"$LOG_FILE"
        else
            echo "  [MISSING] Could not find library for '-l$lib_name' in any search path." >>"$LOG_FILE"
            return 1
        fi
    done
    return 0
}

check_pkg_config_batch() {
    # 1. Collect files from arguments (handling wildcards)
    local files=()
    
    # Check if no arguments provided
    if [ $# -eq 0 ]; then
        echo "DEBUG: Usage: check_pkg_config_batch \"/path/to/*.pc\"" | tee -a "$LOG_FILE"
        return 1
    fi

    for arg in "$@"; do
        # Check if argument contains a wildcard (*)
        if [[ "$arg" == *"*"* ]]; then
            # If it's a quoted glob pattern, expand it safely using compgen
            # This handles filenames with spaces correctly
            while IFS= read -r file; do
                files+=("$file")
            done < <(compgen -G "$arg")
        else
            # Otherwise, it's a specific file or shell-expanded path
            files+=("$arg")
        fi
    done

    # 2. Check if we found anything
    if [ ${#files[@]} -eq 0 ]; then
        echo "DEBUG: No .pc files found matching your input." | tee -a "$LOG_FILE"
        return 1
    fi

    echo "INFO: Found ${#files[@]} file(s). Starting checks..." >>"$LOG_FILE"
    echo "  ==========================================" >>"$LOG_FILE"

    # 3. Iterate and check
    for pc_file in "${files[@]}"; do
        if [ -f "$pc_file" ]; then
            check_pkg_config_files "$pc_file"
            echo "  ------------------------------------------" >>"$LOG_FILE"
        else
            echo "  Skipping invalid file: $pc_file" >>"$LOG_FILE"
        fi
    done
}

download_ffmpeg() {
	local output_dir="$ffmpeg_source_dir"
	local desired_version="$ffmpeg_git_checkout_version"

	if [[ -z $desired_version ]]; then
		desired_version="master"
	fi
  do_git_checkout "$ffmpeg_git_checkout" "$output_dir" "$desired_version" || exit_message 1 "download_ffmpeg: could not git $ffmpeg_git_checkout $output_dir $desired_version"
  ffmpeg_source_dir=$output_dir
  touch "$ffmpeg_source_dir/no.autoreconf"
}


print_progress() {
  local current_step=$1
  local steps=$2
  local step_name=$3
  local percent=$((current_step * 100 / steps))
  local bars=$((percent * 40 / 100))
  
  local bar_str=""
  for ((j = 0; j < bars; j++)); do bar_str="${bar_str}█"; done
  for ((j = bars; j < 40; j++)); do bar_str="${bar_str}░"; done

  printf "[%s] %3d%% (%2d/%2d) | %s\n" "$bar_str" "$percent" "$current_step" "$steps" "$step_name" >>"$LOG_FILE"
  
  printf "\r\033[K\033[1;32m[%s]\033[0m %3d%% (%2d/%2d) | \033[1;36m%s\033[0m" "$bar_str" "$percent" "$current_step" "$steps" "$step_name"
}

run_valid_build_functions() {
	local start_from=$1
	local skip_mode=${2:-false}
	# Create a clean array without empty elements
	local steps=0
	local current_step=0
  create_dir "$dependency_install_prefix/{lib/pkgconfig,include,bin}"
  # Count non-empty steps first
  for step_name in "${OPTIMIZED_BUILD_STEPS[@]}"; do
    if [[ -n "${step_name// /}" ]]; then
      ((steps++))
    fi
  done

  # If start_from is empty, start from beginning
  if [[ -z "$start_from" ]]; then
    skip_mode=false
  else
    echo -e "INFO: Starting from step: $start_from" | tee -a "$LOG_FILE"
    skip_mode=true
  fi

  for step_name in "${OPTIMIZED_BUILD_STEPS[@]}"; do
    if [[ -z "${step_name// /}" ]]; then
      continue
    fi
    # Handle skip mode
    if [[ "$skip_mode" == true ]]; then
      if [[ "$step_name" == "$start_from" ]]; then
        skip_mode=false
        echo -e "INFO: Building dependencies from: $step_name" | tee -a "$LOG_FILE"
      else
        ((current_step++))
        continue
      fi
    fi
    if truthy "$workflow"; then
      "$SCRIPTDIR/workflow-get-deps.sh" "$host_platform" "$host_arch" "$step_name"
    fi
    ((current_step++))
    print_progress "$current_step" "$steps" "$step_name"
    run_valid_function "$step_name" 2>&1 || exit_message 1 "There was an error running $step_name.\n See $LOG_FILE for details"
  done
  printf "\r\033[KAll dependencies built successfully!\n"
  if truthy "$workflow"; then
    "$SCRIPTDIR/upload-deps-release.sh" "$host_platform" "$host_arch" "${step_name#build_}"
  fi
  static_link_check "$install_pkgconfig_dir"
  reset_ldflags
}

# set run state if step_name is given, reset it otherwise
set_run_state() {
  local step_name="$1"
  if [[ -n "$step_name" ]]; then
    [[ ! -f "$RUN_STATE_FILE" ]] && { touch "$RUN_STATE_FILE"; chmod -R a+rwx "$RUN_STATE_FILE"; }
    echo "${RUN_ARGS[*]}" > "$RUN_STATE_FILE"
    echo "$step_name" >> "$RUN_STATE_FILE"
  else
    [[ -f "$RUN_STATE_FILE" ]] && remove_path -f "$RUN_STATE_FILE"
  fi
}

check_if_built() {
  local step_name="$1"
  if [[ "${INSTALLED_LIBS[$step_name]}" == "1" ]]; then
    return 0
  fi
  if [[ -f "$BUILT_STATE_FILE" ]]; then
    if grep -qFx "$step_name" "$BUILT_STATE_FILE" 2>>"$LOG_FILE"; then
      # Sync memory so we don't grep again next time
      INSTALLED_LIBS["$step_name"]="1"
      return 0
    fi
  fi
  return 1
}

mark_as_built() {
  local step_name="$1"
  INSTALLED_LIBS["$step_name"]="1"
  [[ ! -f "$BUILT_STATE_FILE" ]] && touch "$BUILT_STATE_FILE"
  echo "$step_name" >> "$BUILT_STATE_FILE"
  [[ -f "$BUILT_STATE_FILE" ]] && chmod -R a+rwx "$BUILT_STATE_FILE";
}

run_valid_function() {
	step="$1"
  shift
  local arg=()
  arg+=("$@")
  reset_allflags
  if ! ismacos && ! isios; then
    export LDFLAGS=" $LDFLAGS -static-libstdc++ "
  fi
  iswindows && export LDFLAGS=" -static $LDFLAGS"
	if [[ -n "$step" ]]; then
    if [[ "$step" == build_* ]] && check_if_built "$step"; then
      echo "INFO: $step already built. Skipping." >>"$LOG_FILE"
      return 0
    fi
		change_dir "$src_dir"
		if declare -F "$step" >/dev/null; then
			echo -e "INFO: --- Executing step: $step ---" >>"$LOG_FILE"
      set_run_state "$step"
			"$step" "${arg[@]}" 2>&1 || exit_message 1 "There was an error running $step.\n See $LOG_FILE for details"
      local status=$?
			if [[ $status -eq 0 ]]; then
         echo -e "INFO: --- Finished executing step: $step ---" >>"$LOG_FILE"
         # 2. OPTIMIZATION: Mark as built on success
         mark_as_built "$step"
         return 0
      else
         echo -e "ERROR: Step $step failed with status $status" | tee -a "$LOG_FILE"
         return "$status"
      fi
		else
			echo -e "WARNING: Function '$step' not found. Attempting eval..." >>"$LOG_FILE"
      eval "$step ${arg[*]}" || return 1
		fi
	else
		echo -e "ERROR: Step argument is missing." | tee -a "$LOG_FILE"
		return 1
	fi
  set_run_state
  reset_allflags
}

get_gas_preprocessor() {
  if ismacos || isios || isiossimulator; then
    if [[ ! -f /usr/local/bin/gas-preprocessor.pl ]]; then
      {
      wget -O gas-preprocessor.pl https://raw.githubusercontent.com/FFmpeg/gas-preprocessor/master/gas-preprocessor.pl
      copy_path "gas-preprocessor.pl" "/usr/local/bin/gas-preprocessor.pl" "-f"
      chmod +x "/usr/local/bin/gas-preprocessor.pl"
      } > >(redirect_output) 2>&1 || exit_message 1 "configure_ffmpeg: Failed to download gas-preprocessor.pl"
    fi
  fi
}

# shellcheck disable=SC2120
configure_ffmpeg() {
	echo -e "INFO: Configuring ffmpeg" | tee -a "$LOG_FILE"
	
	change_dir "$ffmpeg_source_dir" || return 1

	if truthy "$build_force"; then
		reset_touch "${ffmpeg_source_dir}" "already_configured_$build_ffmpeg_type*"
    git_hard_reset "${ffmpeg_source_dir}" || exit_message 1 "git_hard_reset: could not reset ffmpeg git repository"
    touch "no.autoreconf"
	fi

  case "$host_arch" in
    "x86_64") export ARCH=x86_64 ;;
    "i686") export ARCH=x86 ;;
    "aarch64") export ARCH=aarch64 ;;
    "armv7a") export ARCH=arm ;;
    *) export ARCH=$host_arch ;;
  esac

	change_dir "$ffmpeg_source_dir" || exit_message 1 "configure_ffmpeg: could not change to $ffmpeg_source_dir"
	# iswindows && apply_patch "$PATCHDIR"/frei0r_load-shared-libraries-dynamically.diff
  local postpend_configure_opts=""
	local init_options=""
  local extra_libs=""
  init_options+=" --disable-autodetect"
  function add_extra_libs() {
      # local libs="-Wl,--start-group $1 -Wl,--end-group"
      local libs=" $1"
      extra_libs+=" $libs"
  }
  if iswindows || isandroid; then
    fix_pkgconfig_flags
    init_options+=" --host-cc=$(command -v cc)"
  fi
  # Common compiler flags for Windows    
  if ismacos || isios || isiossimulator; then
    get_gas_preprocessor
    init_options+=" --as='gas-preprocessor.pl -arch $meson_cpu_family -- $(xcrun --sdk "$toolchain_sys" --find clang)'"
  fi
  if iswindows; then
    export LDFLAGS="$LDFLAGS -Wl,-Bstatic -l:libpthreadGC3.a"
    export CFLAGS="$CFLAGS -mstackrealign"
    export LD=${cross_prefix}gcc # ld weirdness with windows
	  init_options+=" --target-os=mingw32"
    # init_options+=" --enable-w32threads"
    init_options+=" --disable-w32threads"
    init_options+=" --enable-pthreads"
    init_options+=" --extra-cflags=\" -DPTW32_STATIC_LIB \""
    init_options+=" --disable-filter=gfxcapture"
    init_options+=" --extra-ldflags=\" -L${deps_install_prefix}/lib \""
  elif isandroid; then
    # unset PKG_CONFIG_PATH
    export PKG_CONFIG_SYSROOT_DIR="/"
    export PKG_CONFIG_LIBDIR="$install_pkgconfig_dir:$ffmpeg_install_prefix/lib/pkgconfig"
    UNWIND_STATIC=$($CXX -print-file-name=libunwind.a)
    BUILTINS_STATIC=$($CXX -print-file-name=libclang_rt.builtins-"${clang_arch}"-android.a)
    export AS="$CC"
    export LD="$CXX"
    export LDFLAGS="$LDFLAGS -L$toolchain_bin_path/lib -Wl,--allow-multiple-definition -static-libstdc++ -Wl,--start-group $UNWIND_STATIC $BUILTINS_STATIC -latomic -landroid -lm -Wl,--end-group"
    init_options+=" --ranlib=$RANLIB"
    init_options+=" --nm=$NM"
    init_options+=" --ld=$CXX"
    init_options+=" --strip=$STRIP"
	  init_options+=" --target-os=android"
    init_options+=" --enable-jni"
    init_options+=" --enable-pthreads"
    init_options+=" --extra-ldflags='$LDFLAGS'"
    init_options+=" --extra-ldexeflags='$LDFLAGS'"
    init_options+=" --disable-programs"
    if [[ "$host_arch" == "armv7a" ]]; then
      # these do not support 32bit architecture
      disable_library "libsvtav1"
      disable_library "libxevd"
      disable_library "libxeve"
    fi
  elif islinux; then
    init_options+=" --enable-pthreads"
    add_extra_libs "-lpthread -lrt -lm -ldl -lstdc++"
  elif ismacos; then
    if [[ "$host_arch" != "arm64" ]]; then
      init_options+=" --target-os=darwin"
      export LD="$CXX"
      init_options+=" --ld=$CXX"
    fi
  elif isios || isiossimulator; then
    init_options+=" --target-os=darwin"
    init_options+=" --disable-programs"
    init_options+=" --host-cc=$(xcrun --sdk macosx --find clang)"
    init_options+=" --objcc=$(xcrun --sdk "$toolchain_sys" --find clang)"
    init_options+=" --cc=$(xcrun --sdk "$toolchain_sys" --find clang)"
    init_options+=" --cxx=$(xcrun --sdk "$toolchain_sys" --find clang++)"
    init_options+=" --ld=$(xcrun --sdk "$toolchain_sys" --find clang++)"
    init_options+=" --ar=$(xcrun --sdk "$toolchain_sys" --find ar)"
    init_options+=" --strip=$(xcrun --sdk "$toolchain_sys" --find strip)"
    init_options+=" --nm=$(xcrun --sdk "$toolchain_sys" --find nm)"
    init_options+=" --ranlib=$(xcrun --sdk "$toolchain_sys" --find ranlib)"
    init_options+=" --extra-cflags='-isysroot $(xcrun --sdk "$toolchain_sys" --show-sdk-path)'"
    init_options+=" --extra-ldflags='-isysroot $(xcrun --sdk "$toolchain_sys" --show-sdk-path)'"
  fi
  if ! ismacos && ! isios; then
    init_options+=" --extra-ldflags=\" -Wl,--allow-multiple-definition \""
  fi
  init_options+=" --pkg-config=pkg-config"
	init_options+=" --pkg-config-flags=--static"
	init_options+=" --enable-version3"
	init_options+=" --arch=$ARCH"
	init_options+=" --prefix=$ffmpeg_install_prefix"
	init_options+=" --enable-pic"
	init_options+=" --enable-swscale"
  init_options+=" --extra-cflags=\" -ffunction-sections -fdata-sections \""
  init_options+=" --extra-cxxflags=\" -ffunction-sections -fdata-sections \""
	truthy "$build_small" && init_options+=" --enable-small"

	if ! islinux; then
    init_options+=" --enable-cross-compile"
    ! isandroid && ! isios && init_options+=" --cross-prefix=$cross_prefix"
  fi

  if iswindows; then
    init_options+=" --extra-cflags=\" -DWIN32_LEAN_AND_MEAN \""
	  init_options+=" --extra-cflags=\" -DWIN32_ANSI_API \""
	  init_options+=" --extra-cflags=\" -DHAVE_WCHAR_FILENAME_H=0 \""
    init_options+=" --extra-cflags=\" -mstackrealign \""
	  init_options+=" --extra-ldflags=\" -lole32 \""
	  init_options+=" --extra-ldflags=\" -lshlwapi \""
	  init_options+=" --extra-ldflags=\" -static-libgcc \""
	  init_options+=" --extra-ldflags=\" -static-libstdc++ \""
	  init_options+=" --extra-cflags=\" -mtune=generic \""
	  init_options+=" --extra-cflags=\" -O3 \""
	  init_options+=" --extra-cflags=\" -pipe \""
    init_options+=" --extra-ldflags=\" $stdcpp_path $stdgcc_path \""
    init_options+=" --extra-cflags=\" $extra_ffmpeg_c_flags \""
    add_extra_libs "$stdcpp_path -l:libpthreadGC3.a"
    init_options+=" --extra-cflags=\" -Wno-pedantic -Wno-cpp -Wno-variadic-macros \""
  fi

	# can't mix and match --enable-static --enable-shared unfortunately, or the final executable seems to just use shared if the're both present
	if [[ $build_ffmpeg_type == "static" ]]; then
		postpend_configure_opts+=" --enable-static --disable-shared --enable-pic"
    init_options+=" --extra-cflags=\" -fPIC -DPIC \""
    init_options+=" --extra-cxxflags=\" -fPIC -DPIC \""
    init_options+=" --env=\"X86ASMFLAGS=-DPIC\""
	else
    postpend_configure_opts+=" --enable-shared --disable-static"
	fi

	local config_options=""
	config_options+=" --disable-doc"
	config_options+=" --disable-htmlpages"
  config_options+=" --disable-manpages"
  config_options+=" --disable-podpages"
  config_options+=" --disable-txtpages"
	config_options+=" --disable-outdev=fbdev"
  config_options+=" --disable-indev=fbdev"
  #------------------------------------------------------------------------------     
  # ----------------------------- android features ------------------------------     
  #------------------------------------------------------------------------------      
  if isandroid; then
  truthy "$enable_jni" && config_options+=" --enable-jni"                           # enable JNI support [no]
  truthy "$enable_mediacodec" && config_options+=" --enable-mediacodec"             # enable Android MediaCodec support [no]
  fi
  #------------------------------------------------------------------------------    
  # --------------------------- OpenHarmony features ----------------------------     
  #------------------------------------------------------------------------------    
  if [[ $host_platform == "harmony" ]]; then
  truthy "$enable_ohcodec" && config_options+=" --enable-ohcodec"                   # enable OpenHarmony Codec support [no]
  fi
  #------------------------------------------------------------------------------    
  # --------------------------- linux/unix features -----------------------------     
  #------------------------------------------------------------------------------    
  if islinux; then
  truthy "$enable_alsa" && config_options+=" --enable-alsa"                         # enable ALSA support [autodetect]
  truthy "$enable_libdc1394" && { config_options+=" --enable-libdc1394" \
  && add_extra_libs "-lusb-1.0"; }                                                  # enable IIDC-1394 grabbing using libdc1394 and libraw1394 [no]
  truthy "$enable_libdrm" && config_options+=" --enable-libdrm"                     # enable DRM code (Linux) [autodetect]
  truthy "$enable_libiec61883" && { config_options+=" --enable-libiec61883" \
  && add_extra_libs "-liec61883 -lavc1394 -lrom1394 -lraw1394"; }                   # enable iec61883 via libiec61883 [no]
  truthy "$enable_libv4l2" && config_options+=" --enable-libv4l2"                   # enable libv4l2/v4l-utils [no]
  truthy "$enable_libxcb_shape" && config_options+=" --enable-libxcb-shape"         # enable X11 grabbing shape rendering [autodetect]
  truthy "$enable_libxcb_shm" && config_options+=" --enable-libxcb-shm"             # enable X11 grabbing shm communication [autodetect]
  truthy "$enable_libxcb_xfixes" && config_options+=" --enable-libxcb-xfixes"       # enable X11 grabbing mouse rendering [autodetect]
  truthy "$enable_libxcb" && config_options+=" --enable-libxcb"                     # enable X11 grabbing using XCB [autodetect]
  truthy "$enable_rkmpp" && config_options+=" --enable-rkmpp --enable-libdrm"       # enable Rockchip Media Process Platform code [no]
  truthy "$enable_v4l2_m2m" && config_options+=" --enable-v4l2-m2m"                 # enable V4L2 mem2mem code [autodetect]
  truthy "$enable_vaapi" && config_options+=" --enable-vaapi"                       # enable Video Acceleration API (mainly Unix/Intel) code [autodetect]
  truthy "$enable_xlib" && config_options+=" --enable-xlib"                         # enable xlib [autodetect]
                                                                                    # XXX --disable-sndio MinGW/Windows not supported 
  truthy "$enable_sndio" && config_options+=" --enable-sndio"                       # enable sndio support [autodetect]
                                                                                    # XXX --enable-libtorch ABI mismatch on windows
  truthy "$enable_ladspa" && config_options+=" --enable-ladspa"                     # enable LADSPA audio filtering [no]
  truthy "$enable_libxvid" && config_options+=" --enable-libxvid"                   # enable Xvid encoding via xvidcore, native MPEG-4/Xvid encoder exists [no]
  truthy "$enable_libpulse" && { config_options+=" --enable-libpulse" \
  && add_extra_libs "-lxcb -lXau -lX11 -liconv -lXdmcp"; }                            # enable Pulseaudio input via libpulse [no]
  truthy "$enable_libjack" && { config_options+=" --enable-libjack" \
  && add_extra_libs "-lxcb -liconv"; }                                                # enable JACK audio sound server [no]
  truthy "$enable_vdpau" && config_options+=" --enable-vdpau"                         # enable Nvidia Video Decode and Presentation API for Unix code [autodetect]
  fi
  #------------------------------------------------------------------------------
  # ----------------------------- hardware features ----------------------------- 
  #------------------------------------------------------------------------------
  truthy "$enable_amf" && config_options+=" --enable-amf"                             # enable AMF video encoding code [autodetect]
  truthy "$enable_vulkan" && config_options+=" --enable-vulkan"                       # enable Vulkan code [autodetect]
  truthy "$enable_libmfx" && config_options+=" --enable-libmfx"                       # enable Intel MediaSDK (AKA Quick Sync Video) code via libmfx [no]
  if ! ismacos && ! isios; then
    truthy "$enable_libvpl" && config_options+=" --enable-libvpl"                     # enable Intel oneVPL code via libvpl if libmfx is not used [no]
  fi
  truthy "$enable_vulkan_static" && config_options+=" --enable-vulkan-static"         # enable statically link to libvulkan [no]
  if truthy "$enable_libtorch" && (ismacos || islinux); then
    config_options+=" --enable-libtorch \
  --extra-cflags=\"-I${dependency_install_prefix}/include/torch/csrc/api/include\" \
  --extra-cxxflags=\"-I${dependency_install_prefix}/include/torch/csrc/api/include\"" # enable Torch as one DNN backend [no]
    if ismacos; then
      add_extra_libs "-ltorch -ltorch_cpu -lc10"
      config_options+=" --extra-cxxflags=\"-Wno-invalid-specialization\""
    fi
  fi
  if iswindows || islinux; then
  truthy "$enable_cuvid" && config_options+=" --enable-cuvid"                         # enable Nvidia CUVID support [autodetect]
  truthy "$enable_ffnvcodec" && config_options+=" --enable-ffnvcodec"                 # enable dynamically linked Nvidia code [autodetect]
  truthy "$enable_nvdec" && config_options+=" --enable-nvdec"                         # enable Nvidia video decoding acceleration (via hwaccel) [autodetect]
  truthy "$enable_nvenc" && config_options+=" --enable-nvenc"                         # enable Nvidia video encoding code [autodetect]
  fi
  if iswindows || islinux || ismacos; then
  truthy "$enable_libopenvino" && config_options+=" --enable-libopenvino"             # enable OpenVINO as a DNN module backend for DNN based filters like dnn_processing [no]
  truthy "$enable_libtensorflow" && config_options+=" --enable-libtensorflow"         # enable TensorFlow as a DNN module backend for DNN based filters like sr [no]
  fi
  if islinux; then
  truthy "$enable_cuda_nvcc" && config_options+=" --enable-cuda-nvcc"
  truthy "$enable_cuda_nvcc" && config_options+=" \
  --nvccflags=\" -gencode arch=compute_86,code=sm_86 -O2 \""                          # enable Nvidia CUDA compiler [no]
  elif iswindows; then
  truthy "$enable_cuda_llvm" && config_options+=" --enable-cuda-llvm"                 # enable CUDA compilation using clang [autodetect]
  fi
  truthy "$enable_libnpp" && config_options+=" --enable-libnpp"                       # enable Nvidia Performance Primitives-based code [no]
  #------------------------------------------------------------------------------
  # ----------------------------- windows features ------------------------------ 
  #------------------------------------------------------------------------------
  if iswindows || islinux || ismacos; then
  truthy "$enable_avisynth" && config_options+=" --enable-avisynth"                   # enable reading of AviSynth script files [no]
  fi
  #------------------------------------------------------------------------------
  # -------------------------- cross-platform features --------------------------
  #------------------------------------------------------------------------------ 
  if ! iswindows && islinux; then
  truthy "$enable_libsmbclient" && config_options+=" --enable-libsmbclient \
  --extra-cflags=\" -I/usr/include/samba-4.0 \" \
  --extra-cxxflags=\" -I/usr/include/samba-4.0 \" \
  --extra-ldflags=\" -L/usr/lib64 -lsmbclient \""                                       # enable Samba protocol via libsmbclient [no]
  truthy "$enable_libsmbclient" && add_extra_libs "-lsmbclient"
  fi
  truthy "$enable_bzlib" && config_options+=" --enable-bzlib"                         # enable bzlib [autodetect]
  truthy "$enable_iconv" && config_options+=" --enable-iconv"                         # enable iconv [autodetect]
  truthy "$enable_lzma" && config_options+=" --enable-lzma"                           # enable lzma [autodetect]
  truthy "$enable_sdl2" && config_options+=" --enable-sdl2"                           # enable sdl2 [autodetect]
  truthy "$enable_zlib" && config_options+=" --enable-zlib"                           # enable zlib [autodetect]
  truthy "$enable_libvo_amrwbenc" && config_options+=" --enable-libvo-amrwbenc"       # enable AMR-WB encoding via libvo-amrwbenc [no]
  truthy "$enable_libopencore_amrnb" && config_options+=" --enable-libopencore-amrnb" # enable AMR-NB de/encoding via libopencore-amrnb [no]
  truthy "$enable_libopencore_amrwb" && config_options+=" --enable-libopencore-amrwb" # enable AMR-WB decoding via libopencore-amrwb [no]
  truthy "$enable_liblcevc_dec" && config_options+=" --enable-liblcevc-dec"           # enable LCEVC decoding via liblcevc-dec [no]
  truthy "$enable_chromaprint" && { config_options+=" --enable-chromaprint" \
  && add_extra_libs "-lchromaprint -lfftw3"; }
  truthy "$enable_frei0r" && config_options+=" --enable-frei0r"                       # enable frei0r video filtering [no]
  truthy "$enable_gcrypt" && config_options+=" --enable-gcrypt"                       # enable gcrypt, needed for rtmp(t)e support if openssl, librtmp or gmp is not used [no]
  truthy "$enable_gmp" && config_options+=" --enable-gmp"                             # enable gmp, needed for rtmp(t)e support if openssl or librtmp is not used [no]
  truthy "$enable_gnutls" && config_options+=" --enable-gnutls"                       # enable gnutls, needed for https support if openssl, libtls or mbedtls is not used [no]
  truthy "$enable_lcms2" && config_options+=" --enable-lcms2"                         # enable ICC profile support via LittleCMS 2 [no]
  truthy "$enable_libaom" && config_options+=" --enable-libaom"                       # enable AV1 video encoding/decoding via libaom [no]
  truthy "$enable_libaribb24" && config_options+=" --enable-libaribb24"               # enable ARIB text and caption decoding via libaribb24 [no]
  truthy "$enable_libaribcaption" && config_options+=" --enable-libaribcaption"       # enable ARIB text and caption decoding via libaribcaption [no]
  truthy "$enable_libass" && config_options+=" --enable-libass"                       # enable libass subtitles rendering, needed for subtitles and ass filter [no]
  if ! isandroid && ! isios; then
    truthy "$enable_libbluray" && config_options+=" --enable-libbluray"                 # enable BluRay reading using libbluray [no]
    truthy "$enable_libbluray" && ismacos && add_extra_libs "-framework DiskArbitration"
    truthy "$enable_libcdio" && config_options+=" --enable-libcdio"                     # enable audio CD grabbing with libcdio [no]
    truthy "$enable_libdvdnav" && config_options+=" --enable-libdvdnav"                 # enable libdvdnav, needed for DVD demuxing [no]
    truthy "$enable_libdvdread" && config_options+=" --enable-libdvdread"               # enable libdvdread, needed for DVD demuxing [no]
  fi
  truthy "$enable_libbs2b" && config_options+=" --enable-libbs2b"                     # enable bs2b DSP library [no]
  truthy "$enable_libcaca" && config_options+=" --enable-libcaca"                     # enable textual display using libcaca [no]
  islinux && truthy "$enable_libcaca" && add_extra_libs "-lX11" \
  && config_options+=" --extra-ldflags=-lX11"
  # libcelt depercated - use libopus instead
  truthy "$enable_libcelt" && config_options+=" --enable-libopus"                     # enable CELT decoding via libcelt [no]
  truthy "$enable_libcodec2" && config_options+=" --enable-libcodec2"                 # enable codec2 en/decoding using libcodec2 [no]
  truthy "$enable_libdav1d" && config_options+=" --enable-libdav1d"                   # enable AV1 decoding via libdav1d [no]
  truthy "$enable_libdavs2" && config_options+=" --enable-libdavs2"                   # enable AVS2 decoding via libdavs2 [no]
  truthy "$enable_libflite" && config_options+=" --enable-libflite"                   # enable flite (voice synthesis) support via libflite [no]
  islinux && truthy "$enable_libflite" && add_extra_libs "-lasound"                   # extra libs for libflite on linux linux 
  truthy "$enable_libfontconfig" && config_options+=" --enable-libfontconfig"         # enable libfontconfig, useful for drawtext filter [no]
  truthy "$enable_libfreetype" && config_options+=" --enable-libfreetype"             # enable libfreetype, needed for drawtext filter [no]
  truthy "$enable_libfribidi" && config_options+=" --enable-libfribidi"               # enable libfribidi, improves drawtext filter [no]  
  truthy "$enable_libglslang" && config_options+=" --enable-libglslang"               # enable GLSL->SPIRV compilation via libglslang [no]
  truthy "$enable_libgme" && config_options+=" --enable-libgme"                       # enable Game Music Emu via libgme [no]
  truthy "$enable_libgsm" && config_options+=" --enable-libgsm"                       # enable GSM de/encoding via libgsm [no]
  truthy "$enable_libharfbuzz" && config_options+=" --enable-libharfbuzz"             # enable libharfbuzz, needed for drawtext filter [no]
  truthy "$enable_libilbc" && config_options+=" --enable-libilbc"                     # enable iLBC de/encoding via libilbc [no]
  truthy "$enable_libjxl" && config_options+=" --enable-libjxl"                       # enable JPEG XL de/encoding via libjxl [no]
  truthy "$enable_libklvanc" && config_options+=" --enable-libklvanc"                 # enable Kernel Labs VANC processing [no]
  truthy "$enable_libkvazaar" && config_options+=" --enable-libkvazaar"               # enable HEVC encoding via libkvazaar [no]
  truthy "$enable_liblc3" && config_options+=" --enable-liblc3"                       # enable LC3 de/encoding via liblc3 [no]
  truthy "$enable_liblc3" && add_extra_libs "-llc3"                                   # enable LC3 de/encoding via liblc3 [no]
  truthy "$enable_liblensfun" && config_options+=" --enable-liblensfun"               # enable lensfun lens correction [no]
  truthy "$enable_libmodplug" && config_options+=" --enable-libmodplug"               # enable ModPlug via libmodplug [no]
  truthy "$enable_libmp3lame" && config_options+=" --enable-libmp3lame"               # enable MP3 encoding via libmp3lame [no]
  truthy "$enable_libmysofa" && config_options+=" --enable-libmysofa"                 # enable libmysofa, needed for sofalizer filter [no]
  truthy "$enable_liboapv" && config_options+=" --enable-liboapv"                     # enable APV encoding via liboapv [no]
  truthy "$enable_libopencv" && { config_options+=" --enable-libopencv" \
  && add_extra_libs "-lsharpyuv"; }                                                   # enable video filtering via libopencv [no]
 if isandroid && truthy "$enable_libopencv"; then
  config_options+=" --extra-cflags=\"-I${dependency_install_prefix}/include\" \
  --extra-ldflags=\"-L${dependency_install_prefix}/sdk/native/3rdparty/libs\" \
  --extra-ldflags=\"-L${dependency_install_prefix}/sdk/native/staticlibs\""
 fi
  truthy "$enable_libopenh264" && config_options+=" --enable-libopenh264"             # enable H.264 encoding via OpenH264 [no]
  truthy "$enable_libopenjpeg" && config_options+=" --enable-libopenjpeg"             # enable JPEG 2000 encoding via OpenJPEG [no]
  truthy "$enable_libopenmpt" && config_options+=" --enable-libopenmpt"               # enable decoding tracked files via libopenmpt [no]
  truthy "$enable_libopus" && config_options+=" --enable-libopus"                     # enable Opus de/encoding via libopus [no]
  truthy "$enable_libplacebo" && config_options+=" --enable-libplacebo"               # enable libplacebo library [no]
  truthy "$enable_libqrencode" && config_options+=" --enable-libqrencode"             # enable QR encode generation via libqrencode [no]
  truthy "$enable_libquirc" && config_options+=" --enable-libquirc"                   # enable QR decoding via libquirc [no]
  truthy "$enable_librabbitmq" && config_options+=" --enable-librabbitmq"             # enable RabbitMQ library [no]
  truthy "$enable_librav1e" && config_options+=" --enable-librav1e"                   # enable AV1 encoding via rav1e [no]
  truthy "$enable_librist" && config_options+=" --enable-librist"                     # enable RIST via librist [no]
  truthy "$enable_librsvg" && config_options+=" --enable-librsvg"                     # enable SVG rasterization via librsvg [no]
  truthy "$enable_librsvg" && ismacos && add_extra_libs "-lresolv"
  truthy "$enable_librtmp" && config_options+=" --enable-librtmp"                     # enable RTMP[E] support via librtmp [no]
  truthy "$enable_librubberband" && config_options+=" --enable-librubberband"         # enable rubberband needed for rubberband filter [no]
  truthy "$enable_libshaderc" && config_options+=" --enable-libshaderc"               # enable GLSL->SPIRV compilation via libshaderc [no]
  truthy "$enable_libshaderc" && (ismacos || isios || isiossimulator) \
  && add_extra_libs "-lglslang -lSPIRV -lSPIRV-Tools -lSPIRV-Tools-opt"
  truthy "$enable_libshine" && config_options+=" --enable-libshine"                   # enable fixed-point MP3 encoding via libshine [no]
  truthy "$enable_libsnappy" && config_options+=" --enable-libsnappy"                 # enable Snappy compression, needed for hap encoding [no]
  truthy "$enable_libsoxr" && config_options+=" --enable-libsoxr"                     # enable Include libsoxr resampling [no]
  truthy "$enable_libspeex" && config_options+=" --enable-libspeex"                   # enable Speex de/encoding via libspeex [no]
  truthy "$enable_libsrt" && config_options+=" --enable-libsrt"                       # enable Haivision SRT protocol via libsrt [no]
  truthy "$enable_libssh" && config_options+=" --enable-libssh"                       # enable SFTP protocol via libssh [no]
  truthy "$enable_libsvtav1" && config_options+=" --enable-libsvtav1"                 # enable AV1 encoding via SVT [no]
  truthy "$enable_libtesseract" && { config_options+=" --enable-libtesseract" \
  && add_extra_libs "-ltesseract -lleptonica -lz -larchive -ltiff -lpng16 \
  -ljpeg -lgif -lwebpmux -lwebp -lopenjp2 -ljbig -lLerc -lsharpyuv \
  -llzma -lzstd -ldeflate"; }                                                         # enable Tesseract, needed for ocr filter [no]
  truthy "$enable_libtheora" && config_options+=" --enable-libtheora"                 # enable Theora encoding via libtheora [no]
  truthy "$enable_libtls" && config_options+=" --enable-libtls"                       # enable LibreSSL (via libtls), needed for https support if openssl, gnutls or mbedtls is not used [no]
  truthy "$enable_libtwolame" && config_options+=" --enable-libtwolame \
  --extra-cflags=\" -DLIBTWOLAME_STATIC \""                                           # enable MP2 encoding via libtwolame [no]
  truthy "$enable_libuavs3d" && config_options+=" --enable-libuavs3d"                 # enable AVS3 decoding via libuavs3d [no]
  truthy "$enable_libvidstab" && config_options+=" --enable-libvidstab"               # enable video stabilization using vid.stab [no]
  truthy "$enable_libvmaf" && config_options+=" --enable-libvmaf"                     # enable vmaf filter via libvmaf [no]
  truthy "$enable_libvorbis" && config_options+=" --enable-libvorbis"                 # enable Vorbis en/decoding via libvorbis, native implementation exists [no]
  truthy "$enable_libvpx" && config_options+=" --enable-libvpx"                       # enable VP8 and VP9 de/encoding via libvpx [no]
  truthy "$enable_libvvenc" && config_options+=" --enable-libvvenc"                   # enable H.266/VVC encoding via vvenc [no]
  truthy "$enable_libwebp" && config_options+=" --enable-libwebp"                     # enable WebP encoding via libwebp [no]
  truthy "$enable_libx264" && config_options+=" --enable-libx264"                     # enable H.264 encoding via x264 [no]
  truthy "$enable_libx265" && config_options+=" --enable-libx265"                     # enable HEVC encoding via x265 [no]
  truthy "$enable_libxavs" && config_options+=" --enable-libxavs"                     # enable AVS encoding via xavs [no]
  truthy "$enable_libxavs2" && config_options+=" --enable-libxavs2"                   # enable AVS2 encoding via xavs2 [no]
  truthy "$enable_libxevd" && config_options+=" --enable-libxevd"                     # enable EVC decoding via libxevd [no]
  truthy "$enable_libxeve" && config_options+=" --enable-libxeve"                     # enable EVC encoding via libxeve [no]
  truthy "$enable_libxml2" && config_options+=" --enable-libxml2"                     # enable XML parsing using the C library libxml2, needed for dash and imf demuxing support [no]
  truthy "$enable_libzimg" && config_options+=" --enable-libzimg"                     # enable z.lib, needed for zscale filter [no]
  truthy "$enable_libzmq" && config_options+=" --enable-libzmq"                       # enable message passing via libzmq [no]
  truthy "$enable_libzvbi" && config_options+=" --enable-libzvbi"                     # enable teletext support via libzvbi [no]
  truthy "$enable_lv2" && { config_options+=" --enable-lv2" \
  && add_extra_libs "-lsratom -lsord -lzix -lserd -llilv"; }                          # enable LV2 audio filtering [no]
  truthy "$enable_mbedtls" && config_options+=" --enable-mbedtls"                     # enable mbedTLS, needed for https support if openssl, gnutls or libtls is not used [no]
  truthy "$enable_openal" && config_options+=" --enable-openal"                       # enable OpenAL 1.1 capture support [no]
  truthy "$enable_opencl" && config_options+=" --enable-opencl"                       # enable OpenCL processing [no]
  truthy "$enable_opengl" && config_options+=" --enable-opengl"                       # enable OpenGL rendering [no]
  if truthy "$enable_opengl" && ismacos ; then
    add_extra_libs "-framework OpenGL -framework CoreVideo"
  fi
  if isios && truthy "$enable_opengl"; then
    add_extra_libs "-framework OpenGLES -framework CoreVideo -framework VideoToolbox -framework CoreMedia -framework CoreFoundation"
    sed -i'.bak' \
    -e "s|check_lib opengl ES2/gl.h glGetError \"-isysroot=\${sysroot} -framework OpenGLES\"|check_lib opengl OpenGLES/ES2/gl.h glGetError \"-F${IOS_SYSROOT}/System/Library/Frameworks -framework OpenGLES\"|g" \
    configure
  fi
  if isandroid && truthy "$enable_opengl"; then
    add_extra_libs "-lGLESv2 -lEGL -llog -lOpenCL -pthread -ldl"                      # enable EGL and GLES support [no]
    config_options+=" --extra-cflags=\"-I$toolchain_include_path\""
    config_options+=" --extra-cflags=\"-DglXGetProcAddress=eglGetProcAddress\""
    # patch ffmpeg configure for Android
    sed -i'' -e 's|check_lib opengl ES2/gl.h glGetError "-isysroot=${sysroot} -framework OpenGLES"|check_lib opengl GLES2/gl2.h glGetError "-lGLESv2 -lEGL"|g' configure
    sed -i'' -e 's|check_lib opencl OpenCL/cl.h clEnqueueNDRangeKernel "-framework OpenCL"|check_lib opencl CL/cl.h clEnqueueNDRangeKernel "-lOpenCL"|g' configure
  fi
  truthy "$enable_openssl" && config_options+=" --enable-openssl"                     # enable openssl, needed for https support if gnutls, libtls or mbedtls is not used [no]
  truthy "$enable_pocketsphinx" && config_options+=" --enable-pocketsphinx"           # enable PocketSphinx, needed for asr filter [no]
  truthy "$enable_pocketsphinx" && ismacos && add_extra_libs "-lresolv"
  truthy "$enable_vapoursynth" && config_options+=" --enable-vapoursynth"             # enable VapourSynth demuxer [no]
  truthy "$enable_whisper" && { config_options+=" --enable-whisper" \
  && add_extra_libs "-lwhisper -lggml -lggml-cpu -lggml-base"; }                      # enable whisper filter [no]
  truthy "$enable_whisper" && ! isandroid && ! ismacos && ! isios && add_extra_libs "-lgomp"
  truthy "$enable_whisper" && { ismacos || isios; } && add_extra_libs "-lomp -lresolv"

  # ------------------------------ windows features -------------------------------     
  if iswindows; then
    truthy "$enable_d3d11va" && config_options+=" --enable-d3d11va"                     # enable Microsoft Direct3D 11 video acceleration code [autodetect]
    truthy "$enable_d3d12va" && config_options+=" --enable-d3d12va"                     # enable Microsoft Direct3D 12 video acceleration code [autodetect]
    truthy "$enable_dxva2" && config_options+=" --enable-dxva2"                         # enable Microsoft DirectX 9 video acceleration code [autodetect]
    truthy "$enable_schannel" && config_options+=" --enable-schannel"                   # enable SChannel SSP, needed for TLS support on Windows if openssl and gnutls are not used [autodetect]
    truthy "$enable_mediafoundation" && config_options+=" --enable-mediafoundation"     # enable encoding via MediaFoundation [auto]
  fi
  # ------------------------------ apple features -------------------------------     
  if ismacos || isios; then
    truthy "$enable_avfoundation" && config_options+=" --enable-avfoundation"           # enable Apple AVFoundation framework [autodetect]
    truthy "$enable_avfoundation" && add_extra_libs "-framework AVFoundation"
    truthy "$enable_appkit" && config_options+=" --enable-appkit"                       # enable Apple AppKit framework [autodetect]
    truthy "$enable_appkit" && add_extra_libs "-framework AppKit"
    truthy "$enable_audiotoolbox" && config_options+=" --enable-audiotoolbox"           # enable Apple AudioToolbox code [autodetect]
    truthy "$enable_audiotoolbox" && add_extra_libs "-framework AudioToolbox"
    truthy "$enable_coreimage" && config_options+=" --enable-coreimage"                 # enable Apple CoreImage framework [autodetect]
    truthy "$enable_coreimage" && add_extra_libs "-framework CoreImage"
    truthy "$enable_metal" && config_options+=" --enable-metal"                         # enable Apple Metal framework [autodetect]
    truthy "$enable_metal" && add_extra_libs "-framework Metal"
    truthy "$enable_securetransport" && config_options+=" --enable-securetransport"     # enable Secure Transport, needed for TLS support on OSX if openssl and gnutls are not used [autodetect]
    truthy "$enable_securetransport" && add_extra_libs "-framework Security"
    truthy "$enable_videotoolbox" && config_options+=" --enable-videotoolbox"           # enable VideoToolbox code [autodetect]
    truthy "$enable_videotoolbox" && add_extra_libs "-framework VideoToolbox"
    if isios; then
      sed -i'.bak' 's/framework="$1"/framework="$1"\n\theader_file="${2:-$1}"/' configure
      sed -i'.bak' 's/${framework}\.h/${header_file}\.h/g' configure
      sed -i'.bak' 's/check_apple_framework CoreAudio/check_apple_framework CoreAudio CoreAudioTypes/g' configure
    fi
  fi

	if truthy "$build_gpl"; then
		config_options+=" --enable-gpl"
  fi
  if truthy "$build_nonfree"; then 
    config_options+=" --enable-nonfree"
    #------------------------------------------------------------------------------
    # ------------------------ non-free non-gpl libraries -------------------------
    #------------------------------------------------------------------------------ 
    truthy "$enable_decklink" && config_options+=" --enable-decklink"                   # enable Blackmagic DeckLink I/O support [no]
    truthy "$enable_libfdk_aac" && config_options+=" --enable-libfdk-aac"               # enable AAC de/encoding via libfdk-aac [no]
    # --------------------------- linux/unix features -----------------------------    
    if [[ $host_platform == "rpi" ]]; then
    truthy "$enable_mmal" && config_options+=" --enable-mmal"                           # enable Broadcom Multi-Media Abstraction Layer (Raspberry Pi) via MMAL [no]
    truthy "$enable_omx" && config_options+=" --enable-omx"                             # enable OpenMAX IL code [no]
    truthy "$enable_omx_rpi" && config_options+=" --enable-omx-rpi"                     # enable OpenMAX IL code for Raspberry Pi [no]
    fi
	fi

	if truthy "$do_debug_build"; then
		postpend_configure_opts+=" --disable-stripping --disable-optimizations --extra-cflags=\" -Og \" --extra-cflags=\" -fno-omit-frame-pointer \" --enable-debug=3 --extra-cflags=\" -fno-inline \""
	else
		postpend_configure_opts+=" --disable-debug --enable-stripping --enable-optimizations"
	fi
  if ismacos || isios; then
    postpend_configure_opts+=" --extra-cflags=\"-std=gnu17\" --extra-ldflags=\"-Wl,-dead_strip -Wl,-dead_strip\" --extra-libs=\"$extra_libs -lc++\" $ff_flags_values"
  else
    postpend_configure_opts+=" --extra-cflags=\"-std=gnu17\" --extra-libs=\"-Wl,--start-group $extra_libs -Wl,--end-group\" $ff_flags_values"
  fi
  
  if iswindows; then
    cross_windres y
    unset RC
  fi

	do_configure "$init_options$config_options$postpend_configure_opts" "$env_overrides ./configure" "$(get_ffmpeg_directory)" 1 || exit_message 1 "configure_ffmpeg: unable to configure ffmpeg. see $LOG_FILE for details."

	echo -e "INFO: Done configuering ffmpeg" | tee -a "$LOG_FILE"
}

build_exists() {
	shared_build_exists=n
	static_build_exists=n

	# Check shared build
	local build_dir="$work_dir/$(get_ffmpeg_directory shared)" #ffmpeg_install_prefix
	echo -e "INFO: Checking $build_dir" >>"$LOG_FILE"
	if [[ -d "$build_dir" && -d "$build_dir/bin" ]]; then
		echo -e "INFO: Checking binaries in $build_dir/bin..." >>"$LOG_FILE"
		check_binaries=n
		if find "$build_dir/bin" -maxdepth 1 -type f \( -name '*.a' -o -name '*.dll' -o -name '*.so' -o -name '*.dylib' -o -name '*.lib' -o -name '*.exe' \) -print -quit | grep -q .; then
			check_binaries=y
		fi
		truthy "$check_binaries" && shared_build_exists=y
	fi
	build_dir="$work_dir/$(get_ffmpeg_directory static)" #ffmpeg_install_prefix
	echo -e "INFO: Checking $build_dir" >>"$LOG_FILE"
	# Check static build
	if [[ -d "$build_dir" && -d "$build_dir/bin" ]]; then
		echo -e "INFO: Checking binaries in $build_dir/bin..." >>"$LOG_FILE"
		check_binaries=n
		if find "$build_dir/bin" -maxdepth 1 -type f \( -name '*.a' -o -name '*.dll' -o -name '*.so' -o -name '*.dylib' -o -name '*.lib' -o -name '*.exe' \) -print -quit | grep -q .; then
			check_binaries=y
		fi
		truthy "$check_binaries" && static_build_exists=y
	fi

	echo -e "INFO: Checking if build already exists..." | tee -a "$LOG_FILE"

	if [[ $build_ffmpeg_type == "static" ]]; then
		echo -e "INFO: Static build requested..." | tee -a "$LOG_FILE"
		if ! truthy "$static_build_exists" || truthy "$build_force"; then
			build_dir="$work_dir/$(get_ffmpeg_directory static)" #ffmpeg_install_prefix
			echo -e "INFO: Static build does not exist or force requested. (Re-)configuring Ffmpeg for static build..." | tee -a "$LOG_FILE"
			# shellcheck disable=SC2129
			remove_path -rf "$build_dir" 
			remove_path -f "${ffmpeg_source_dir}/"*.touch
			return 1
		else
			echo -e "INFO: Static build already exists at $build_dir" | tee -a "$LOG_FILE"
      return 0
		fi
	elif [[ $build_ffmpeg_type == "static" ]]; then
		echo -e "INFO: Shared build requested..." | tee -a "$LOG_FILE"
		if ! truthy "$shared_build_exists" || truthy "$build_force"; then
			build_dir="$work_dir/$(get_ffmpeg_directory shared)" #ffmpeg_install_prefix
			echo -e "INFO: Shared build does not exist or force requested. (Re-)configuring Ffmpeg for shared build..." | tee -a "$LOG_FILE"
			# shellcheck disable=SC2129
			remove_path -rf "$build_dir" 
			remove_path -f "${ffmpeg_source_dir}/"*.touch
			return 1
		else
			echo -e "INFO: Shared build already exists at $build_dir" | tee -a "$LOG_FILE"
      return 0
		fi
	fi
}

install_ffmpeg() {
	echo -e "INFO: Installing ffmpeg if not installed" | tee -a "$LOG_FILE"
  local touch_postfix="$(get_ffmpeg_directory)"
	change_dir "$ffmpeg_source_dir"

	echo -e "INFO: Making Ffmpeg $(pwd)" | tee -a "$LOG_FILE"

  remove_path -rf "$ffmpeg_install_prefix"

	create_dir "$ffmpeg_install_prefix"
  
  cross_windres y
  iswindows && unset RC
  ffmpeg_patches
  iswindows && export LD=${cross_prefix}gcc # ld weirdness with windows
  isandroid && export AS="$CC" && export LD="$CC"
  if ismacos || isios || isiossimulator; then 
    export AS="gas-preprocessor.pl -arch $meson_cpu_family -- $(xcrun --sdk "$toolchain_sys" --find clang)"
    local bin2c_py=$(create_bin2c_py)
    sed -i '.bak' 's|RUN_BIN2C = $(BIN2C)|RUN_BIN2C = python3 ffbuild/bin2c.py|' "$ffmpeg_source_dir/ffbuild/common.mak"
  fi
	do_make "AS=\"$AS\" PREFIX=\"$ffmpeg_install_prefix\"" "${touch_postfix}" 1 || exit_message 1 "install_ffmpeg: unable to make ffmpeg. see $LOG_FILE for details."
  do_make_install "PREFIX=\"$ffmpeg_install_prefix\"" "" "${touch_postfix}" 1 || exit_message 1 "install_ffmpeg: unable to make install ffmpeg. see $LOG_FILE for details."

	echo -e "INFO: Moving all binaries" | tee -a "$LOG_FILE"

	{	
    shopt -s nullglob
    find "${ffmpeg_install_prefix}/bin" -type f \
    -exec cp -fv {} "${ffmpeg_install_prefix}/bin" \; || true
    find "${ffmpeg_install_prefix}/lib" -type f \( -name "*.a" \
    -o -name "*.lib" \
    -o -name "*.so" \
    -o -name "*.dylib" \
    -o -name "*.dll" \) -exec cp -fv {} "${ffmpeg_install_prefix}/lib" \; || true
	} > >(redirect_output) 2>&1

	echo -e "INFO: Done installing ffmpeg" | tee -a "$LOG_FILE"
  chmod -R a+rwx "$work_dir"
	install_ffmpeg_pkg
  if [[ $build_ffmpeg_type == "static" ]]; then
    static_link_check "${ffmpeg_install_prefix}/lib/pkgconfig" "$(create_linker_script)"
  fi
  reset_cross_vars
}

install_ffmpeg_pkg() {
	echo -e "INFO: Checking deployment files..." | tee -a "$LOG_FILE"
  local touch_postfix="$(get_ffmpeg_directory)"

  local touch_prefix="${touch_postfix}_already"
	
  if truthy "$build_force"; then
		remove_path -rf "${ffmpeg_source_dir}/${touch_prefix}_pkgconfig"*.touch
	fi
  required_files=(
    "${ffmpeg_install_prefix}/lib/pkgconfig/libavformat.pc"
    "${ffmpeg_install_prefix}/lib/pkgconfig/libswresample.pc"
    "${ffmpeg_install_prefix}/lib/pkgconfig/libswscale.pc"
    "${ffmpeg_install_prefix}/lib/pkgconfig/libavdevice.pc"
    "${ffmpeg_install_prefix}/lib/pkgconfig/libavfilter.pc"
    "${ffmpeg_install_prefix}/lib/pkgconfig/libavcodec.pc"
    "${ffmpeg_install_prefix}/lib/pkgconfig/libavutil.pc")

  check_files_exist "false" "${required_files[@]}"

  echo -e "INFO: Done checking deployment files." | tee -a "$LOG_FILE"

  echo -e "INFO: Installing ffmpeg pkg-config" | tee -a "$LOG_FILE"

  # # MANUALLY ADD REQUIRED HEADERS
  {
    create_dir "${ffmpeg_install_prefix}"/include/libavutil/{x86,arm,aarch64}
    create_dir "${ffmpeg_install_prefix}"/include/libavcodec/{x86,arm}
    overwrite_file "${ffmpeg_source_dir}"/config.h "${ffmpeg_install_prefix}"/include/config.h
    overwrite_file "${ffmpeg_source_dir}"/config_components.h "${ffmpeg_install_prefix}"/include/config_components.h
    overwrite_file "${ffmpeg_source_dir}"/libavcodec/mathops.h "${ffmpeg_install_prefix}"/include/libavcodec/mathops.h
    overwrite_file "${ffmpeg_source_dir}"/libavcodec/x86/mathops.h "${ffmpeg_install_prefix}"/include/libavcodec/x86/mathops.h
    overwrite_file "${ffmpeg_source_dir}"/libavcodec/arm/mathops.h "${ffmpeg_install_prefix}"/include/libavcodec/arm/mathops.h
    overwrite_file "${ffmpeg_source_dir}"/libavformat/network.h "${ffmpeg_install_prefix}"/include/libavformat/network.h
    overwrite_file "${ffmpeg_source_dir}"/libavformat/os_support.h "${ffmpeg_install_prefix}"/include/libavformat/os_support.h
    overwrite_file "${ffmpeg_source_dir}"/libavformat/url.h "${ffmpeg_install_prefix}"/include/libavformat/url.h
    overwrite_file "${ffmpeg_source_dir}"/libavutil/attributes_internal.h "${ffmpeg_install_prefix}"/include/libavutil/attributes_internal.h
    overwrite_file "${ffmpeg_source_dir}"/libavutil/bprint.h "${ffmpeg_install_prefix}"/include/libavutil/bprint.h
    overwrite_file "${ffmpeg_source_dir}"/libavutil/getenv_utf8.h "${ffmpeg_install_prefix}"/include/libavutil/getenv_utf8.h
    overwrite_file "${ffmpeg_source_dir}"/libavutil/internal.h "${ffmpeg_install_prefix}"/include/libavutil/internal.h
    overwrite_file "${ffmpeg_source_dir}"/libavutil/libm.h "${ffmpeg_install_prefix}"/include/libavutil/libm.h
    overwrite_file "${ffmpeg_source_dir}"/libavutil/reverse.h "${ffmpeg_install_prefix}"/include/libavutil/reverse.h
    overwrite_file "${ffmpeg_source_dir}"/libavutil/thread.h "${ffmpeg_install_prefix}"/include/libavutil/thread.h
    overwrite_file "${ffmpeg_source_dir}"/libavutil/timer.h "${ffmpeg_install_prefix}"/include/libavutil/timer.h
    overwrite_file "${ffmpeg_source_dir}"/libavutil/x86/asm.h "${ffmpeg_install_prefix}"/include/libavutil/x86/asm.h
    overwrite_file "${ffmpeg_source_dir}"/libavutil/x86/timer.h "${ffmpeg_install_prefix}"/include/libavutil/x86/timer.h
    overwrite_file "${ffmpeg_source_dir}"/libavutil/arm/timer.h "${ffmpeg_install_prefix}"/include/libavutil/arm/timer.h
    overwrite_file "${ffmpeg_source_dir}"/libavutil/aarch64/timer.h "${ffmpeg_install_prefix}"/include/libavutil/aarch64/timer.h
    overwrite_file "${ffmpeg_source_dir}"/compat/w32pthreads.h "${ffmpeg_install_prefix}"/include/libavutil/compat/w32pthreads.h
    overwrite_file "${ffmpeg_source_dir}"/compat/stdbit/stdbit.h "${ffmpeg_install_prefix}"/include/stdbit/stdbit.h
    overwrite_file "${ffmpeg_source_dir}"/libavutil/wchar_filename.h "${ffmpeg_install_prefix}"/include/libavutil/wchar_filename.h
  } > >(redirect_output) 2>&1
  chmod -R a+rwx "$work_dir"
  echo -e "INFO: Done installing ffmpeg pkg-config" | tee -a "$LOG_FILE"
}

install_ffmpeg_kit() {
	echo -e "INFO: Installing ffmpeg kit to ${ffmpeg_kit_install}" | tee -a "$LOG_FILE"
  local touch_postfix="$(get_ffmpeg_kit_directory)"
  if iswindows; then
    cross_windres y
    unset RC
  elif isandroid; then
    CLANG_RT_DIR=$($CC -print-libgcc-file-name | xargs dirname)
    export LDFLAGS="${LDFLAGS} -Wl,--allow-multiple-definition -L$CLANG_RT_DIR -lclang_rt.builtins-$host_arch-android -Wl,--exclude-libs,libunwind.a"
    export LDFLAGS=$(echo "${LDFLAGS}" | sed -e 's/-Wl,--fatal-warnings//g')
  fi
  
  change_dir "${ffmpeg_kit_src_dir}/build" 1

  remove_path -rf "$ffmpeg_kit_install"
  
  do_make "PREFIX=$ffmpeg_kit_install" "${touch_postfix}" 1 || exit_message 1 "install_ffmpeg_kit: unable to make ffmpeg-kit. see $LOG_FILE for details."
  do_make_install "PREFIX=$ffmpeg_kit_install" "" "${touch_postfix}" 1 || exit_message 1 "install_ffmpeg_kit: unable to make install ffmpeg-kit. see $LOG_FILE for details."
	
  chmod -R a+rwx "$work_dir"
	echo -e "INFO: Done installing ffmpeg kit to ${ffmpeg_kit_install}" | tee -a "$LOG_FILE"
}

install_pkg_config_file() {
	local FILE_NAME="$1"
  local location_prefix="$2"
	local SOURCE="${install_pkgconfig_dir}/${FILE_NAME}"
	local DESTINATION="${FFMPEG_KIT_BUNDLE_PKG_CONFIG_DIRECTORY}/${FILE_NAME}"

	# DELETE OLD FILE
	if ! remove_path -rf "$DESTINATION" >>"$LOG_FILE"; then
		exit_message 1 "install_pkg_config_file: failed\n\nSee $LOG_FILE for details"
	fi

	# INSTALL THE NEW FILE
	if ! copy_path "$SOURCE" "$DESTINATION" >>"$LOG_FILE"; then
		exit_message 1 "install_pkg_config_file: failed\n\nSee $LOG_FILE for details"
	fi

	# UPDATE PATHS
	sed -i'.bak' -e "s|${ffmpeg_kit_install}|${location_prefix}|g" "$DESTINATION" || return 1
  sed -i'.bak' -e "s|libdir=${ffmpeg_kit_install}|libdir=\${prefix}/lib|g" "$DESTINATION" || return 1
  sed -i'.bak' -e "s|includedir=${ffmpeg_kit_install}|includedir=\${prefix}/include|g" "$DESTINATION" || return 1

	sed -i'.bak' -e "s|${ffmpeg_source_dir}|${location_prefix}|g" "$DESTINATION" || return 1
  sed -i'.bak' -e "s|libdir=${ffmpeg_source_dir}|libdir=\${prefix}/lib|g" "$DESTINATION" || return 1
  sed -i'.bak' -e "s|includedir=${ffmpeg_source_dir}|includedir=\${prefix}/include|g" "$DESTINATION" || return 1

  chmod -R a+rwx "$work_dir"
}

create_ffmpeg_kit_bundle() {
  if isandroid && truthy "$create_bundle"; then
    create_android_aar
  elif (isios || isiossimulator) && truthy "$create_bundle"; then
    create_ios_xcframework
  elif ismacos && truthy "$create_bundle"; then
    create_macos_xcframework
  elif [[ -d "${ffmpeg_kit_install}" ]] && truthy "$create_bundle"; then
    echo -e "INFO: Creating bundle" | tee -a "$LOG_FILE"
    local touch_postfix="$host_name"

    local touch_prefix="${touch_postfix}_already"

    remove_path -rf "${ffmpeg_kit_bundle}"
    echo "INFO: (Re-)create_ffmpeg_kit_bundle() because $touch_name not found with \"ffmpeg-kit-bundle $(get_bundle_directory)\"." >>"$LOG_FILE"
    
    create_dir "${ffmpeg_kit_bundle}/{include,lib/pkgconfig,bin}"
    
    {
      # COPY HEADERS
      [[ -d "${ffmpeg_kit_install}/include" ]] && cp -rfv "${ffmpeg_kit_install}/include" "${ffmpeg_kit_bundle}/" > >(redirect_output) 2>&1 || true
      [[ -d "${ffmpeg_install_prefix}/include" ]] && cp -rfv "${ffmpeg_install_prefix}/include" "${ffmpeg_kit_bundle}/" > >(redirect_output) 2>&1 || true
      # COPY LIBS
      [[ -d "${ffmpeg_kit_install}/lib" ]] && find "${ffmpeg_kit_install}/lib" -type f -exec cp -rfv {} "${ffmpeg_kit_bundle}/lib" \; > >(redirect_output) 2>&1 || true

      # COPY BINARIES
      [[ -d "${ffmpeg_kit_install}/bin" ]] && find "${ffmpeg_kit_install}/bin" -type f -exec cp -rfv {} "${ffmpeg_kit_bundle}/bin" \; > >(redirect_output) 2>&1 || true

      # COPY DEBUG PDB
      [[  -f "$ffmpeg_kit_src_dir/build/libffmpegkit.map" ]] && cp -rP "$ffmpeg_kit_src_dir/build/libffmpegkit.map" "${ffmpeg_kit_bundle}/bin"
    } > >(redirect_output) 2>&1

    find "${ffmpeg_kit_bundle}/lib/pkgconfig" -type f -name "*.pc" -exec sed -i'.bak' \
    -e "s|prefix=.*|prefix=${ffmpeg_kit_bundle}|g" \
    -e "s|exec_prefix=.*|exec_prefix=\${prefix}|g" \
    -e "s|libdir=.*|libdir=\${prefix}/lib|g" \
    -e "s|includedir=.*|includedir=\${prefix}/include|g" {} +

    local LICENSE_BASEDIR="${ffmpeg_kit_bundle}/licenses"

    create_dir "${LICENSE_BASEDIR}"
    
    get_licenses

    copy_path "${BASEDIR}"/LICENSE "${LICENSE_BASEDIR}"/ffmpeg-kit_license.txt

    create_touch_file 0 "$touch_name"
    echo -e "INFO: Done creating bundle at $ffmpeg_kit_bundle" | tee -a "$LOG_FILE"

    create_ffmpeg_kit_release
    
    chmod -R a+rwx "$work_dir"
  fi
}

create_ffmpeg_kit_release() {
  if [[ -n "$create_release" ]]; then
    echo -e "INFO: Creating release bundle" | tee -a "$LOG_FILE"
    create_dir "$work_dir/releases"
    local out_dir=$(basename "$ffmpeg_kit_bundle")
    zip_dir "$ffmpeg_kit_bundle" "$work_dir/releases/$out_dir"
    echo -e "INFO: Done creating release bundle at $work_dir/releases/$out_dir.zip" | tee -a "$LOG_FILE"
    truthy "$create_release_clean" && clean_builds "$create_release_clean_type"
    truthy "$create_release_clean" && clean_builds "$create_release_clean_type"
    if [[ "$create_release" == "remote" ]]; then
      create_github_release "$work_dir/releases/$out_dir.zip"
    fi
  fi
}

uninstall_manifest() {
  local manifest="$1"
  if [[ -f "$manifest" ]]; then
    echo "WARNING: found $manifest. Uninstalling files from $manifest if installed"
    sed -i'' -e '/^$/d' "$manifest" | xargs --verbose -r -d '\n' rm -rf
    echo
    remove_path -f "$manifest"
  else
    echo "WARNING: $manifest not found."
  fi
}
pick_gpu_support() {
    if truthy "$accept_defaults"; then
      export gpu_support=n
      return 0
    fi
    export gpu_support=${1:-gpu_support}
    while [[ ! "${gpu_support,,}" =~ ^([0-1]|yes|y|no|n)$ ]]; do
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
Do you want to enable GPU support for TensorFlow?
  1. yes
  2. no [default]
EOF
        local timeout=10
        export gpu_support=""
        echo -ne 'Input your choice [0-1] (defaulting to "no" in 10 seconds): '
        for ((i=timeout; i>0; i--)); do
            if read -r -t 1 gpu_support; then
                break
            fi
            if (( i > 1 )); then
                echo -ne "\rInput your choice [0-1] (defaulting to \"no\" in $((i-1)) seconds): "
            else
                echo -ne "\rInput your choice [0-1] (defaulting to \"no\" in 0 seconds): "
            fi
        done
        
        # Check if timeout occurred
        if [[ -z "$gpu_support" ]] && { (( i == 0 )) || truthy "$accept_defaults"; }; then
            echo "No input received within 10 seconds. Defaulting to 'no'."
            export gpu_support=n
        fi
    done
    case "${gpu_support,,}" in
        1|yes|y) 
            export gpu_support=y
            return 0
            ;;
        0|no|n|"") 
            export gpu_support=n
            return 1
            ;;
        *)
            echo -e 'Your choice was not valid, please try again.'
            echo
            ;;
    esac
}

# Minimal zip folder function - supports only .zip format
# Usage: zip_dir <input_folder> [output_name]
zip_dir() {
    # Check for zip command
    if ! command -v zip >/dev/null 2>&1; then
        echo "Error: 'zip' command not found. Install with: $INSTALL_COMMAND install zip / yum install zip / brew install zip" | tee -a "$LOG_FILE"
        return 1
    fi
    
    # Validate arguments
    if [[ $# -lt 1 ]] || [[ $# -gt 2 ]]; then
        echo "Usage: zip_folder <input_folder> [output_name]"
        return 1
    fi
    
    local input_folder="$1"
    local output_name="${2:-}"
    
    # Validate input folder exists
    if [[ ! -d "$input_folder" ]]; then
        exit_message 1 "Input folder '$input_folder' not found"
        return 1
    fi
    
    # Set default output name if not provided
    if [[ -z "$output_name" ]]; then
        local folder_name=$(basename "$input_folder")
        # Remove trailing slash if present
        folder_name="${folder_name%/}"
        output_name="${folder_name}.zip"
    fi
    
    # Ensure .zip extension
    if [[ "$output_name" != *.zip ]]; then
        output_name="${output_name}.zip"
    fi
    
    if [[ -f $output_name ]]; then
      echo "INFO: '$output_name' already exists. Deleting it first..."
      remove_path -f "$output_name"
    fi
    
    # Create the zip archive
    echo "INFO: Creating '$output_name' from '$input_folder'..."
    cd "$(validate_path "$input_folder")" || exit_message 1 "zip_dir: could not find $input_folder"
    local input_name=$(basename "$input_folder")
    cd ..
    if (zip -rq "$output_name" "$input_name"); then
        echo "INFO: [Success] Created '$output_name'"
        return 0
    else
        echo "DEBUG: [Error] Failed to create zip archive" | tee -a "$LOG_FILE"
        # Clean up partial output if created
        [[ -f "$output_name" ]] && rm -f "$output_name"
        return 1
    fi
}

LAST_TS=$(date +%s)

ts() {
  local NOW=$(date +%s)
  local DIFF=$((NOW - LAST_TS))
  LAST_TS=$NOW

  # Convert seconds to HH:MM:SS
  local ELAPSED=$(printf '%02d:%02d:%02d' $((DIFF/3600)) $((DIFF%3600/60)) $((DIFF%60)))
  
  echo "$(date +"[%Y-%m-%d %H:%M:%S]") (Elapsed: $ELAPSED)"
}

intro() {
  setup_build_environment
	cat <<EOL
     ##################### Welcome ######################
  Welcome to the ffmpeg and ffmpeg-kit builder-helper script.
  Downloads and builds will be installed to directories within: 
  Dependencies - $dependency_install_prefix
  Ffmpeg - $ffmpeg_install_prefix
  Ffmpeg-kit - $ffmpeg_kit_install
  Bundle - $ffmpeg_kit_bundle
  Note that once you build your compilers, you can no longer rename/move
  the $dependency_install_prefix directory, since it will have some 
  hard coded paths in there. You can, of course, rebuild ffmpeg 
  ffmpeg-kit and bundle.
EOL
	echo -e "$(ts)" | tee -a "$LOG_FILE"
	if [[ ! -d $WORKDIR ]]; then
		echo -e
		echo -e "Building in $WORKDIR, will use ~ 285GB space!" | tee -a "$LOG_FILE"
		echo -e
	fi
	change_dir "$WORKDIR" 1 || exit_message 1 "intro: could not change to $WORKDIR"
	echo -e "sit back, this may take awhile..." | tee -a "$LOG_FILE"
}

# Only adds step if it is UNIQUE and EXISTS
add_step() {
  local func="$1"
  if [[ "$1" != build_* ]]; then
    func="build_${1/-/_}"
  fi
  # Duplication Check
  if [[ -z "${BUILD_STEPS[$func]}" ]]; then
    BUILD_STEPS["$func"]=1
  fi
}

# Removes a step from the build order and uniqueness tracker if it exists
remove_step() {
  local func="$1"
  if [[ "$1" != build_* ]]; then
    func="build_${1/-/_}"
  fi
  # 1. Check if the step is currently in the build list
  if [[ -n "${BUILD_STEPS[$func]}" ]]; then
    # Remove from uniqueness tracker
    unset "BUILD_STEPS[$func]"
  fi
}

enable_library() {
  LIBRARY_NAME="$1"
  VAR_NAME="enable_${LIBRARY_NAME//-/_}"
  export "$VAR_NAME"=y
  VAR_NAME="disable_${LIBRARY_NAME//-/_}"
  export "$VAR_NAME"=n
  add_step "$LIBRARY_NAME"
  if iswindows && ! is_shared_library "$LIBRARY_NAME" ; then 
    sanitized="${LIBRARY_NAME//-/_}"
    export extra_ffmpeg_c_flags="$extra_ffmpeg_c_flags -D${sanitized^^}_NODLL "
  fi
  echo "  [CONFIG] Enabling: $LIBRARY_NAME" >>"$LOG_FILE"
}

disable_library() {
  LIBRARY_NAME="$1"
  VAR_NAME="enable_${LIBRARY_NAME//-/_}"
  export "$VAR_NAME"=n
  VAR_NAME="disable_${LIBRARY_NAME//-/_}"
  export "$VAR_NAME"=y
  remove_step "$LIBRARY_NAME"
  echo "  [CONFIG] Disabling: $LIBRARY_NAME" >>"$LOG_FILE"
}

is_library_enabled() {
  local LIBRARY_NAME="$1"
  local CLEAN_NAME="${LIBRARY_NAME//-/_}"
  
  local VAR_ENABLE="enable_${CLEAN_NAME}"
  local VAR_DISABLE="disable_${CLEAN_NAME}"
  
  if [[ "${!VAR_ENABLE}" == "1" && "${!VAR_DISABLE}" != "1" ]]; then
    return 0  # Library is Enabled
  else
    return 1  # Library is Disabled (or not set)
  fi
}

enable_preset() {
  local PRESET_STRING="$1"
  # Split string by space into array
  # This handles multiline strings correctly if they are unquoted or space-separated
  if [[ -n "$PRESET_STRING" ]]; then
    for FLAG in $PRESET_STRING; do
      local lib="${FLAG#--*-}"
      enable_library "$lib"
    done
  fi
}

disable_preset() {
  local PRESET_STRING="$1"
  # Split string by space into array
  # This handles multiline strings correctly if they are unquoted or space-separated
  if [[ -n "$PRESET_STRING" ]]; then
    for FLAG in $PRESET_STRING; do
      local lib="${FLAG#--*-}"
      disable_library "$lib"
    done
  fi
}

apply_preset() {
    local PRESET_STRING="$1"
    # Split string by space into array
    # This handles multiline strings correctly if they are unquoted or space-separated
    if [[ -n "$PRESET_STRING" ]]; then
      for FLAG in $PRESET_STRING; do
          if [[ "$FLAG" == --enable-* ]]; then
              local lib="${FLAG#--enable-}"
              enable_library "$lib"
          elif [[ "$FLAG" == --disable-* ]]; then
              local lib="${FLAG#--disable-}"
              local step="build_${lib/-/_}"
              disable_library "${FLAG#--disable-}"
          fi
      done
    fi
}

pick_clean_type() {
  if truthy "$accept_defaults"; then
    export clean_type="all"
    echo "$clean_type"
    return 0
  fi
  unknown_opts=()
  if [[ ! "$1" =~ ^([1-5]|all|ffmpeg|ffmpeg-kit|ffmpeg-kit-bundle|kit|bundle)$ ]]; then
     unknown_opts+=("$1")
   fi
	while [[ ! "$clean_type" =~ ^([1-5]|all|ffmpeg|ffmpeg-kit|ffmpeg-kit-bundle|kit|bundle)$ ]]; do
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
  1. all [default]
  2. ffmpeg
  3. ffmpeg-kit
  4. ffmpeg-kit-bundle
  5. Exit
EOF
		local timeout=10
    export clean_type=""
    echo -ne 'Input your choice [1-5] (defaulting to "all" in 10 seconds): '
    for ((i=timeout; i>0; i--)); do
        if read -r -t 1 clean_type; then
            break
        fi
        if (( i > 1 )); then
            echo -ne "\rInput your choice [1-5] (defaulting to \"all\" in $((i-1)) seconds): "
        else
            echo -ne "\rInput your choice [1-5] (defaulting to \"all\" in 0 seconds): "
        fi
    done
    
    # Check if timeout occurred
    if [[ -z "$clean_type" ]] && { (( i == 0 )) || truthy "$accept_defaults"; }; then
        echo "No input received within 10 seconds. Defaulting to 'all'."
        export clean_type="all"
    fi
	done
	case "$clean_type" in
	1|all) export clean_type="all" ;;
	2|ffmpeg) export clean_type="ffmpeg" ;;
	3|ffmpeg-kit|kit) export clean_type="ffmpeg-kit" ;;
	4|ffmpeg-kit-bundle|bundle) export clean_type="ffmpeg-kit-bundle" ;;
	5)
		exit_message 0 "pick_clean_type: exiting"
		;;
	*)
		echo -e 'Your choice was not valid, please try again.'
		echo
		;;
	esac
}

pick_host_platform() {
  set_linux() {
    export host_platform="linux"
    export toolchain_sys="linux"
    apply_preset "$CONFIG_LINUX"
  }
  set_windows() {
    export host_platform="windows"
    export toolchain_sys="windows"
    apply_preset "$CONFIG_WINDOWS"
  }
  set_android() {
    export host_platform="android"
    export toolchain_sys="android"
    apply_preset "$CONFIG_ANDROID"
  }
  set_macos() {
    export host_platform="macos"
    export toolchain_sys="macosx"
    apply_preset "$CONFIG_MACOS"
  }
  set_ios() {
    export host_platform="ios"
    export toolchain_sys="iphoneos"
    apply_preset "$CONFIG_IOS"
  }
  set_ios_simulator() {
    export host_platform="iphonesimulator"
    export toolchain_sys="iphonesimulator"
    apply_preset "$CONFIG_IOS"
  }
  set_tvos() {
    export host_platform="appletvos"
    export toolchain_sys="appletvos"
    apply_preset "$CONFIG_IOS"
  }
  set_tvos_simulator() {
    export host_platform="appletvsimulator"
    export toolchain_sys="appletvsimulator"
    apply_preset "$CONFIG_IOS"
  }
	if truthy "$accept_defaults" && [[ -z "$1" ]]; then
    set_linux
    return 0
  fi
  unknown_opts=()
  if [[ ! "$1" =~ ^([1-9]|linux|windows|android|mac(os)?|iphone(os|simulator)?|ios(-sim(ulator)?)?|iphonesim(ulator)?|tvos(-sim(ulator)?)?|appletvos|appletvsim(ulator)?)$ ]]; then
     unknown_opts+=("$1")
   fi
  export host_platform=${1:-host_platform}
	while [[ ! "${host_platform,,}" =~ ^([1-9]|linux|windows|android|mac(os)?|iphone(os|simulator)?|ios(-sim(ulator)?)?|iphonesim(ulator)?|tvos(-sim(ulator)?)?|appletvos|appletvsim(ulator)?)$ ]]; do
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
Which host platform are you trying to build, update, or clean for?
  1. Linux [default]
  2. Windows
  3. Android
  4. MacOS
  5. iOS
  6. iOS-Simulator
  7. Apple TV
  8. Apple TV-Simulator
  9. Exit
EOF
		echo -e -n 'Input your choice [1-9]: '
		read -r host_platform
	done
  if [[ -z "$host_platform" ]] && truthy "$accept_defaults"; then
      echo "Defaulting to 'linux'."
      set_linux
      return 0
  fi
	case "${host_platform,,}" in
	1|linux) set_linux
  return 0
  ;;
	2|win*) set_windows
  return 0
  ;;
	3|android) set_android
  return 0
  ;;
	4|mac*) set_macos
  return 0
  ;;
	5|ios|iphone|iphoneos) set_ios
  return 0
  ;;
	6|ios-sim*|iphonesim*|iphone-sim*) set_ios_simulator
  return 0
  ;;
  7|tvos|appletvos) set_tvos
  return 0
  ;;
  8|tvos-sim*|appletvsim*|appletv-sim*) set_tvos_simulator
  return 0
  ;;
	9)
  exit_message 0 "pick_host_platform: exiting"
  ;;
	*)
  unknown_opts+=("$host_platform")
  echo -e 'Your choice was not valid, please try again.'
  echo
  host_platform=""  # Reset to trigger loop again
  ;;
	esac
}

pick_host_arch() {
  function set_x86_64() {
    export host_arch="x86_64"
    export cmake_host_arch="x86_64"
    export bits_target=64
  }
  function set_i686() {
    export host_arch="i686"
    export cmake_host_arch="x86"
    export bits_target=32
  }
  function set_aarch64() {
    export host_arch="aarch64"
    export cmake_host_arch="aarch64"
    export bits_target=64
  }
  function set_armv7a() {
    export host_arch="armv7a"
    export cmake_host_arch="armv7-a"
    export bits_target=32
  }
	if truthy "$accept_defaults" && [[ -z "$1" ]]; then
    set_x86_64
    return 0
  fi
  unknown_opts=()
  if [[ ! "$1" =~ ^([1-5]|x86_64|x64|i386|i686|x86|x32|aarch64|arm64|arm64-v8a|armv7a|arm|armeabi-v7a)$ ]]; then
     unknown_opts+=("$1")
   fi
  export host_arch=${1:-host_arch}
	while [[ ! "${host_arch,,}" =~ ^([1-5]|"x86_64"|"x64"|"i386"|"i686"|"x86"|"x32"|"aarch64"|"arm64"|"arm64-v8a"|"armv7a"|"arm"|"armeabi-v7a")$ ]]; do
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
Which host platform are you trying to build, update, or clean for?
  1. x86_64 (64-bit AMD/Intel) [default]
  2. i686 (32-bit AMD/Intel)
  3. aarch64 (64-bit ARM)
  4. armv7a (32-bit ARM)
  5. Exit
EOF
		echo -e -n 'Input your choice [1-5]: '
		read -r host_arch
	done
  if [[ -z "$host_arch" ]] && truthy "$accept_defaults"; then
      echo "Defaulting to 'x86_64'."
      set_x86_64
      return 0
  fi
	case "${host_arch,,}" in
	1|"x86_64"|"x64") set_x86_64
  return 0
  ;;
	2|"i386"|"i686"|"x86"|"x32") set_i686
  return 0
  return 0
  ;;
	3|"aarch64"|"arm64"|"arm64-v8a") set_aarch64
  return 0
  ;;
	4|"armv7a"|"arm"|"armeabi-v7a") set_armv7a
  return 0
  ;;
	5|"exit")
		exit_message 0 "user picked exit"
		;;
	*)
		echo -e 'Your choice was not valid, please try again.'
		echo
		;;
	esac
}

pick_gpu_type() {
    if truthy "$accept_defaults"; then
      export gpu_type="cuda"
      return 0
    fi
    unknown_opts=()
    if [[ ! "$1" =~ ^([1-2]|cuda|nvdia|rocm|amd)$ ]]; then
       unknown_opts+=("$1")
     fi
    export gpu_type=${1:-gpu_type}
    while [[ ! "${gpu_type,,}" =~ ^([1-2]|cuda|nvdia|rocm|amd)$ ]]; do
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
Which GPU compute platform?
  1. CUDA (Nvidia) [default]
  2. ROCm (AMD)
EOF
        local timeout=10
        export gpu_type=""
        echo -ne 'Input your choice [1-2] (defaulting to "CUDA (Nvidia)" in 10 seconds): '
        for ((i=timeout; i>0; i--)); do
            if read -r -t 1 gpu_type; then
                break
            fi
            if (( i > 1 )); then
                echo -ne "\rInput your choice [1-2] (defaulting to \"CUDA (Nvidia)\" in $((i-1)) seconds): "
            else
                echo -ne "\rInput your choice [1-2] (defaulting to \"CUDA (Nvidia)\" in 0 seconds): "
            fi
        done
        
        # Check if timeout occurred
        if [[ -z "$gpu_type" ]] && { (( i == 0 )) || truthy "$accept_defaults"; }; then
            echo "No input received within 10 seconds. Defaulting to 'CUDA (Nvidia)'."
            export gpu_type="cuda"
        fi
    done
    case "${gpu_type,,}" in
        1|cuda|nvidia|"") 
            export gpu_type="cuda"
            return 0
            ;;
        2|rocm|amd) 
            export gpu_type="rocm"
            return 1
            ;;
        *)
            echo -e 'Your choice was not valid, please try again.'
            echo
            ;;
    esac
}

pick_ssl_type() {
  set_openssl() {
    export ssl_type="openssl"
    enable_library "openssl"
    disable_library "gnutls"
    disable_library "libtls"
    disable_library "mbedtls"
  }
  set_gnutls() {
    export ssl_type="gnutls"
    enable_library "gnutls"
    disable_library "openssl"
    disable_library "libtls"
    disable_library "mbedtls"
  }
  set_libtls() {
    export ssl_type="libtls"
    enable_library "libtls"
    disable_library "openssl"
    disable_library "gnutls"
    disable_library "mbedtls"
  }
  set_mbedtls() {
    export ssl_type="mbedtls"
    enable_library "mbedtls"
    disable_library "openssl"
    disable_library "gnutls"
    disable_library "libtls"
  }
  set_system() {
    if iswindows; then
      export ssl_type="system"
      enable_library "schannel"
    elif ismacos || isios; then
      export ssl_type="system"
      enable_library "securetransport"
    else
      set_openssl
    fi
  }
  if truthy "$accept_defaults"; then
    set_system
    return 0
  fi
  unknown_opts=()
  if [[ ! "$1" =~ ^([1-5]|openssl|gnutls|libtls|mbedtls|system|os|os-default)$ ]]; then
    unknown_opts+=("$1")
  fi
  export ssl_type=${1:-ssl_type}
    while [[ ! "${ssl_type,,}" =~ ^([1-6]|openssl|gnutls|libtls|mbedtls|system|os|os-default)$ ]]; do
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
Which TLS/SSL library needed for https do you want to include?
  1. openssl [default]
  2. gnutls
  3. libtls
  4. mbedtls
  5. os-default
  6. exit
EOF
        local timeout=10
        export ssl_type=""
        echo -ne 'Input your choice [1-6] (defaulting to "OpenSSL" in 10 seconds): '
        for ((i=timeout; i>0; i--)); do
            if read -r -t 1 ssl_type; then
                break
            fi
            if (( i > 1 )); then
                echo -ne "\rInput your choice [1-6] (defaulting to \"OpenSSL\" in $((i-1)) seconds): "
            else
                echo -ne "\rInput your choice [1-6] (defaulting to \"OpenSSL\" in 0 seconds): "
            fi
        done
        
        # Check if timeout occurred
        if [[ -z "$ssl_type" ]] && { (( i == 0 )) || truthy "$accept_defaults"; }; then
            echo "No input received within 10 seconds. Defaulting to OS default OR 'OpenSSL'."
            set_system
        fi
    done
    case "${ssl_type,,}" in
        1|openssl|"") set_openssl
            ;;
        2|gnutls) set_gnutls
            ;;
        3|libtls) set_libtls
            ;;
        4|mbedtls) set_mbedtls
            ;;
        5|system|os-default|os) set_system
            ;;
        6|exit) exit 0
            ;;
        *)
            echo -e 'Your choice was not valid, please try again.'
            echo
            ;;
    esac
}

pick_cryto_lib() {
    if truthy "$accept_defaults"; then
      export crypto_type="gcrypt"
      enable_library "gcrypt"
      disable_library "gmp"
      return 0
    fi
    unknown_opts=()
    if [[ ! "$1" =~ ^([1-2]|gcrypt|gmp)$ ]]; then
      unknown_opts+=("$1")
    fi
    export crypto_type=${1:-crypto_type}
    while [[ ! "${crypto_type,,}" =~ ^([1-2]|gcrypt|gmp)$ ]]; do
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
Which cryptography library needed for secure streaming do you want to include?
  1. gcrypt [default]
  2. gmp
EOF
        local timeout=10
        export crypto_type=""
        echo -ne 'Input your choice [1-2] (defaulting to "gcrypt" in 10 seconds): '
        for ((i=timeout; i>0; i--)); do
            if read -r -t 1 crypto_type; then
                break
            fi
            if (( i > 1 )); then
                echo -ne "\rInput your choice [1-2] (defaulting to \"gcrypt\" in $((i-1)) seconds): "
            else
                echo -ne "\rInput your choice [1-2] (defaulting to \"gcrypt\" in 0 seconds): "
            fi
        done
        
        # Check if timeout occurred
        if [[ -z "$crypto_type" ]] && { (( i == 0 )) || truthy "$accept_defaults"; }; then
            echo "No input received within 10 seconds. Defaulting to 'gcrypt'."
            enable_library "gcrypt"
            disable_library "gmp"
        fi
    done
    case "${crypto_type,,}" in
        1|gcrypt|"") 
            enable_library "gcrypt"
            disable_library "gmp"
            ;;
        2|gmp) 
            enable_library "gmp"
            disable_library "gcrypt"
            ;;
        *)
            echo -e 'Your choice was not valid, please try again.'
            echo
            ;;
    esac
}

pick_mq_lib() {
    if truthy "$accept_defaults"; then
      export mq_type="both"
      enable_library "librabbitmq"
      enable_library "libzmq"
      apply_preset "$CONFIG_MQ"
      return 0
    fi
    unknown_opts=()
    if [[ ! "$1" =~ ^([1-3]|rabbitmq|zeromq|librabbitmq|libzmq)$ ]]; then
      unknown_opts+=("$1")
    fi
    export mq_type=${1:-mq_type}
    while [[ ! "${mq_type,,}" =~ ^([1-3]|rabbitmq|zeromq|librabbitmq|libzmq)$ ]]; do
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
Which MQ library do you want to include?
  1. RabbitMQ 
  2. ZeroMQ
  3. Both [default]
EOF
        local timeout=10
        export mq_type=""
        echo -ne 'Input your choice [1-2] (defaulting to "Both" in 10 seconds): '
        for ((i=timeout; i>0; i--)); do
            if read -r -t 1 mq_type; then
                break
            fi
            if (( i > 1 )); then
                echo -ne "\rInput your choice [1-2] (defaulting to \"Both\" in $((i-1)) seconds): "
            else
                echo -ne "\rInput your choice [1-2] (defaulting to \"Both\" in 0 seconds): "
            fi
        done
        
        # Check if timeout occurred
        if [[ -z "$mq_type" ]] && { (( i == 0 )) || truthy "$accept_defaults"; }; then
            echo "No input received within 10 seconds. Defaulting to 'gcrypt'."
            enable_library "librabbitmq"
            enable_library "libzmq"
            apply_preset "$CONFIG_MQ"
        fi
    done
    case "${mq_type,,}" in
        1|librabbitmq|rabbitmq) 
            enable_library "librabbitmq"
            disable_library "libzmq"
            ;;
        2|libzmq|zeromq|zmq) 
            enable_library "libzmq"
            disable_library "librabbitmq"
            ;;
        3|both|"")
            enable_library "librabbitmq"
            enable_library "libzmq"
            apply_preset "$CONFIG_MQ"
            ;;
        *)
            echo -e 'Your choice was not valid, please try again.'
            echo
            ;;
    esac
}

print_build_steps() {
	echo -e "Avaliable build steps: ${#OPTIMIZED_BUILD_STEPS[@]}"
	for i in "${!OPTIMIZED_BUILD_STEPS[@]}"; do
		echo "Index $i: ${OPTIMIZED_BUILD_STEPS[i]}"
	done
  printf 'WORKFLOW_BUILD_STEPS=%s\n' "${OPTIMIZED_BUILD_STEPS[*]}"
}

check_and_resolve() {
    local PREF="$1"
    local REDUNDANT="$2"
    
    local VAR_PREF="enable_${PREF//-/_}"
    local VAR_REDUNDANT="enable_${REDUNDANT//-/_}"

    # If both are marked as enabled (1)
    if truthy "${!VAR_PREF}" && truthy "${!VAR_REDUNDANT}"; then
        echo "  [RESOLVE] Collision detected between $PREF and $REDUNDANT. Preferring $PREF." >> "$LOG_FILE"
        disable_library "$REDUNDANT"
    fi
}

resolve_collisions() {
    echo -e "\n  [CONFIG] Resolving library collisions and preferences..." >> "$LOG_FILE"

    check_and_resolve "libvpl" "libmfx"
    check_and_resolve "libshaderc" "libglslang"

    if is_library_enabled "openssl"; then
        is_library_enabled "gnutls" && disable_library "gnutls"
        is_library_enabled "mbedtls" && disable_library "mbedtls"
        is_library_enabled "libtls" && disable_library "libtls"
    elif is_library_enabled "gnutls"; then
        is_library_enabled "mbedtls" && disable_library "mbedtls"
        is_library_enabled "libtls" && disable_library "libtls"
    fi
}

get_pip_download_link() {
  local package="$1"
  local result
  
  # List of python versions to try (ordered from newest to oldest)
  local python_versions=("python3.13" "python3.12" "python3.11" "python3")
  
  for py in "${python_versions[@]}"; do
    # Check if the python binary exists
    if ! command -v "$py" &> /dev/null; then
      continue
    fi
    
    # Attempt the dry-run
    result=$("$py" -m pip install "$package" --dry-run --no-deps --ignore-installed --report - -q 2>/dev/null)
    
    # Check if this specific version found the package
    if [ $? -eq 0 ] && [ -n "$result" ]; then
      # Success: Parse and echo the URL, then return
      echo "$result" | "$py" -c "import sys, json; print(json.load(sys.stdin)['install'][0]['download_info']['url'])"
      return 0
    fi
  done
  
  echo "Error: Could not find package '$package' for any installed python version." >&2
  return 1
}

unversion_library() {
  while [[ $# -gt 0 ]]; do
      case "$1" in
          -t=*) TARGET_DIR="${1#*=}"; shift ;;
          # comma separated lists
          -e=*) EXCLUDE="${1#*=}"; shift ;;
          *) shift ;;
      esac
  done

  IFS=',' read -ra excludes <<< "$EXCLUDE"

  find "$TARGET_DIR" -maxdepth 1 \( -name "*.so.*" -o -name "*.a.*" \) | sort -Vr | while read -r full_path; do
    filename=$(basename "$full_path")
    # shellcheck disable=2001
    base_name=$(echo "$filename" | sed -e 's/\.so\..*/.so/')
    # check if excluded
    excluded=false
    for exclude_pattern in "${excludes[@]}"; do
        if [[ "$filename" == "$exclude_pattern" ]]; then
            excluded=true
            break
        fi
    done
    if [ "$excluded" = true ]; then
        echo "Skipping $filename -> Excluded." >>"$LOG_FILE"
        continue
    fi
    dest_path="$TARGET_DIR/$base_name"
    if [ -e "$dest_path" ]; then
        echo "Skipping $filename -> Target $base_name already exists." >>"$LOG_FILE"
    else
        echo "Renaming $filename -> $base_name" >>"$LOG_FILE"
        mv "$full_path" "$dest_path"
    fi
  done
}

check_gpl_libraries() {
  echo -e "\n  [CONFIG] Checling libraries for GPL conflicts..." >>"$LOG_FILE"
  if truthy "$build_all_gpl"; then
    enable_preset "$CONFIG_GPL"
  elif truthy "$build_gpl"; then
    truthy "$enable_libx264" && enable_library "libx264"
    truthy "$enable_libx265" && enable_library "libx265"
    truthy "$enable_libxvid" && enable_library "libxvid"
    truthy "$enable_frei0r" && enable_library "frei0r"
    truthy "$enable_libdvdread" && enable_library "libdvdread"
    truthy "$enable_v4l2_m2m" && enable_library "v4l2-m2m"
    truthy "$enable_avisynth" && enable_library "avisynth"
    truthy "$enable_libjack" && enable_library "libjack"
    truthy "$enable_libbs2b" && enable_library "libbs2b"
    truthy "$enable_libcdio" && enable_library "libcdio"
    truthy "$enable_libdvdnav" && enable_library "libdvdnav"
    truthy "$enable_librubberband" && enable_library "librubberband"
    truthy "$enable_libsmbclient" && enable_library "libsmbclient"
    truthy "$enable_libvidstab" && enable_library "libvidstab"
    truthy "$enable_libdavs2" && enable_library "libdavs2"
    truthy "$enable_libxavs" && enable_library "libxavs"
    truthy "$enable_libxavs2" && enable_library "libxavs2"
    truthy "$enable_libaribb24" && enable_library "libaribb24"
  else
    disable_preset "$CONFIG_GPL"
  fi
}

# disable libraries autodetected by default to prevent inadvertent bundling
disable_autodetected() {
  echo -e "\n  [CONFIG] Disabling libraries autodetected by default to prevent inadvertent bundling..." >>"$LOG_FILE"
  disable_preset "$CONFIG_AUTODETECT"
}

add_src_dir() {
  local dirs=()
  dirs+=("$@")
  local dir_file="$work_dir/pkgconfig/$(get_bundle_directory).txt"
  for dir in "${dirs[@]}"; do
    rm -fv "${dir}/*_src_state.touch" >>"$LOG_FILE" 2>&1
    create_touch_file 0 "$dir/$host_touch"
    if iswindows; then
      find "$dependency_install_prefix/lib" -name "*.la" -delete
      find "$install_pkgconfig_dir" -type f -name "*.pc" -exec sed -i'.bak' -e -E 's/[[:space:]]-lm\b//g' \
        -e 's|/usr/local/mingw-w64/[^ ]+/lib/lib([a-zA-Z0-9]+)\.a|-l\1|g' \
        -e 's|-L/opt/homebrew/opt/([a-zA-Z0-9_-]+(/[a-zA-Z0-9_-]+)*)/lib||g' \
        -e 's|-Wl,--export-dynamic||g' {} +
    elif ismacos || isios || isiossimulator; then
      find "$dependency_install_prefix/lib" -name "*.la" -delete
      find "$install_pkgconfig_dir" -type f -name "*.pc" -exec sed -i'.bak' -e 's|-Wl,--export-dynamic||g' \
        -e 's|-L/opt/homebrew/opt/([a-zA-Z0-9_-]+(/[a-zA-Z0-9_-]+)*)/lib||g' {} +
    else
      find "$dependency_install_prefix/lib" -type f -name "*.la" -exec sed -i'.bak' -e 's|=\/|/|g' {} +
    fi
    if [[ -f "$dir_file" ]]; then
      if ! grep -q "$dir" "$dir_file"; then
        echo "$dir" >> "$dir_file"
        echo "INFO: Added $dir to license src dir list $dir_file" >> "$LOG_FILE"
      fi
    else
      create_dir "$install_pkgconfig_dir"
      touch "$dir_file"
    fi
    chmod -R a+rwx "$dir"
  done
}

get_licenses() {
  local dir_file="$work_dir/pkgconfig/$(get_bundle_directory).txt"
  [[ ! -f "$dir_file" ]] && { echo -e "DEBUG: could not find license src dir list file $dir_file\n  No licenses copied."; return 1; }
  mapfile -t license_dir_list < "$dir_file"
  for dir in "${license_dir_list[@]}"; do
    [[ -z "$dir" ]] && continue
    [[ ! -d "$dir" ]] && continue
    bash "${SCRIPTDIR}/extract_licenses.sh" "${dir}" "${LICENSE_BASEDIR}/$(basename "$dir").txt" > >(redirect_output) 2>&1
  done
}

reset_and_clean() {
  local src_path="$1"
  local dirs=()
  if [[ "$#" -gt 1 ]]; then
    dirs+=("$@")
  elif [[ -z "$1" ]]; then
    shopt -s nullglob
    mapfile -t dirs < <(sudo find "$src_dir" -mindepth 1 -maxdepth 1 -type d | sort -u)
    shopt -u nullglob
  else
    dirs+=("$src_path")
  fi
  echo -e "INFO: Fully resetting touch files and build artifacts $1" | tee -a "$LOG_FILE"
  activate_meson
  for dir in "${dirs[@]}"; do
    if [[ -n "$dir" ]]; then
      reset_touch "$dir"
      cd "$dir" 2>/dev/null || continue
      mapfile -t sub_dirs < <(find "$dir" -name "Makefile" -exec dirname {} \; | sort -u 2>/dev/null)
      for sub_dir in "${sub_dirs[@]}"; do
        cd "$sub_dir" 2>/dev/null || continue
        if [[ -f Makefile ]]; then
          echo "Cleaning Makefile artifacts at $sub_dir..." > >(redirect_output)
          { nice make clean -j"$(get_concurrent_proc)" > >(redirect_output) 2>&1 || true; }
          { nice make distclean -j"$(get_concurrent_proc)" > >(redirect_output) 2>&1 || true; }
        fi
        cd "$dir" 2>/dev/null || continue
      done
      mapfile -t sub_dirs < <(find "$dir" -name "meson.build" -exec dirname {} \; | sort -u 2>/dev/null)
      if [[ -f meson.build ]] && [[ "${#sub_dirs[@]}" -gt 0 ]]; then
        echo "Cleaning meson artifacts at $sub_dir..." > >(redirect_output)
        { python3 "$local_meson" compile --clean -C build > >(redirect_output) 2>&1 || true; }
        { python3 "$local_meson" setup --wipe build > >(redirect_output) 2>&1 || true; }
      fi
      mapfile -t sub_dirs < <(find "$dir" -name "CMakeList.txt" -exec dirname {} \; | sort -u 2>/dev/null)
      for sub_dir in "${sub_dirs[@]}"; do
        cd "$sub_dir" 2>/dev/null || continue
        if [[ -f CMakeList.txt ]]; then
          echo "Cleaning CMake artifacts at $sub_dir..." > >(redirect_output)
          clean_cmake_cache "$(pwd)"
        fi
        cd "$dir" 2>/dev/null || continue
      done
      mapfile -t sub_dirs < <(find "$dir" -name "CMakeCache.txt" -exec dirname {} \; | sort -u 2>/dev/null)
      for sub_dir in "${sub_dirs[@]}"; do
        cd "$sub_dir" 2>/dev/null || continue
        if [[ -f CMakeCache.txt ]]; then
          echo "Cleaning CMake artifacts at $sub_dir..." > >(redirect_output)
          clean_cmake_cache "$(pwd)"
        fi
        cd "$dir" 2>/dev/null || continue
      done
      mapfile -t sub_dirs < <(find "$dir" -name "Cargo.toml" -exec dirname {} \; | sort -u 2>/dev/null)
      for sub_dir in "${sub_dirs[@]}"; do
        cd "$sub_dir" 2>/dev/null || continue
        if [[ -f Cargo.toml ]]; then
          echo "Cleaning Cargo artifacts at $sub_dir..." > >(redirect_output)
          { cargo clean --release > >(redirect_output) 2>&1 || true; }
        fi
        cd "$dir" 2>/dev/null || continue
      done
      mapfile -t sub_dirs < <(find "$dir" -name "build.ninja" -exec dirname {} \; | sort -u 2>/dev/null)
      if [[ -f build.ninja ]] && [[ "${#sub_dirs[@]}" -gt 0 ]]; then
        echo "Cleaning ninja artifacts at $sub_dir..." > >(redirect_output)
        { nice ninja -t clean >/dev/null 2>&1 || true; }
      fi
      mapfile -t sub_dirs < <(find "$dir" -name "waf" -exec dirname {} \; | sort -u 2>/dev/null)
      for sub_dir in "${sub_dirs[@]}"; do
        cd "$sub_dir" 2>/dev/null || continue
        if [[ -f waf ]]; then
          echo "Cleaning waf artifacts at $sub_dir..." > >(redirect_output)
          { eval "python3 ./waf clean" > >(redirect_output) 2>&1 || true; }
        fi
        cd "$dir" 2>/dev/null || continue
      done
    fi
  done
  echo
  echo -e "INFO: Done fully resetting touch files and build artifacts $1" | tee -a "$LOG_FILE"
}

reset_touch() {
  local touch_file="$2"
  shopt -s nullglob
  if [[ -n "$1" ]]; then
    if [[ -z "$touch_file" ]]; then
      echo -e "INFO: Resetting all touch files $1" >>"$LOG_FILE"
      find "$(validate_path "$1")" -maxdepth 3 \( -name "*.touch" -o -name "*already_*" \) -exec rm -rf {} + > >(redirect_output) 2>&1
    else
      echo -e "INFO: Resetting $touch_file touch file $1" >>"$LOG_FILE"
      find "$(validate_path "$1")" -maxdepth 3 \( -name "$touch_file" \) -exec rm -rf {} + > >(redirect_output) 2>&1
    fi
  else
    echo -e "INFO: No directory provided. Resetting all src directories in prebuilt/src/" >>"$LOG_FILE"
    if [[ -z "$touch_file" ]]; then
      echo -e "INFO: Resetting all touch files $1" >>"$LOG_FILE"
      find "$(validate_path "${BASEDIR}/prebuilt/src")" -maxdepth 3 \( -name "*.touch" -o -name "*already_*" \) -exec rm -rf {} + > >(redirect_output) 2>&1
    else
      echo -e "INFO: Resetting $touch_file touch file $1" >>"$LOG_FILE"
      find "$(validate_path "${BASEDIR}/prebuilt/src")" -maxdepth 3 \( -name "$touch_file" \) -exec rm -rf {} + > >(redirect_output) 2>&1
    fi
  fi
  echo -e "INFO: Done resetting source directories touch files." >>"$LOG_FILE"
  shopt -u nullglob
}

disable_nonessential() {
  local src_dir="$1"
  local cur_dir="$(pwd)"
  shift

  if [ -z "$src_dir" ] || [ ! -d "$src_dir" ]; then
    echo "ERROR: Please provide a valid source directory." >>"$LOG_FILE"
    return 1
  fi
  
  # --- STEP 1: Disable Junk Directories ---
  echo "INFO: Searching for non-essential Makefiles in: $src_dir" >>"$LOG_FILE"

  # Use an Array to build the find arguments
  local find_args=()
  
  # Start the grouping for logical OR
  find_args+=( \( )
  
  # Add default patterns
  find_args+=( -name "doc*" -o )
  find_args+=( -name "test*" -o )
  find_args+=( -name "example*" -o )
  find_args+=( -name "sample*" -o )
  find_args+=( -name "program*" -o )
  find_args+=( -name "app*" -o )

  # Add dynamic patterns passed as arguments
  for ptrn in "$@"; do
    find_args+=( -name "$ptrn" -o )
  done

  # Add the final pattern (no trailing -o)
  find_args+=( -name "tool*" )
  
  # Close the grouping
  find_args+=( \) )

  # Use Process Substitution to avoid subshell issues
  while IFS= read -r -d '' subdir; do
    disable_makefile "$subdir/Makefile"
    disable_meson "$subdir/meson.build"
  done < <(find "$src_dir" -type d "${find_args[@]}" -print0)
}

disable_makefile() {
  local mkfile="$1"
  if [ -f "$mkfile" ]; then
    echo "  Disabling: $mkfile" >>"$LOG_FILE"
    # Using a literal tab variable for clarity
    local tab
    tab="$(printf '\t')"

    # Use > to overwrite the file cleanly
    cat <<EOF > "$mkfile"
.SUFFIXES:
all install install-strip check test clean mostlyclean distclean realclean:
${tab}@echo "Target \$@ disabled: $mkfile"
.DEFAULT:
${tab}@echo "Target \$@ ignored: $mkfile"
EOF
  fi
}

disable_meson() {
  local mfile="$1"
  if [ -f "$mfile" ]; then
    echo "  Disabling Meson: $mfile" >>"$LOG_FILE"
    
    # Overwrite with a valid Meson script that just prints a message
    cat <<EOF > "$mfile"
message('Build disabled for being non-essential')
EOF
  fi
}

check_custom_install() {
  local install_dir="$1"
  local lib_name="$2"

  if [ -z "$install_dir" ] || [ -z "$lib_name" ]; then
      echo "Usage: check_custom_install /path/to/custom/location library_name"
      return 1
  fi

  local lib_path="$install_dir/lib"
  local pc_path="$lib_path/pkgconfig"
  local include_path="$install_dir/include"

  echo "INFO: --- Checking Installation for: $lib_name ---"

  # 1. Check for .pc file (The Metadata)
  if [ -f "$pc_path/$lib_name.pc" ]; then
      echo "  [OK] Found pkg-config file: $pc_path/$lib_name.pc"
  else
      echo "  [ERROR] Missing .pc file. pkg-config will not find this library."
  fi

  # 2. Check for Static Library (.a)
  # Note: Using find to account for versioned names or subdirs
  local static_lib=$(find "$lib_path" -name "lib${lib_name}.a" -o -name "lib${lib_name}-*.a" | head -n 1)
  if [ -n "$static_lib" ]; then
      echo "  [OK] Found static archive: $static_lib"
  else
      echo "  [ERROR] Could not find lib${lib_name}.a in $lib_path"
  fi

  # 3. Validate Dependencies via pkg-config
  echo "  [INFO] Querying dependencies for $lib_name..."
  
  # We set PKG_CONFIG_LIBDIR to force it to ONLY look in your custom folder
  # We use PKG_CONFIG_PATH as a secondary to ensure it finds everything
  local deps=$(PKG_CONFIG_LIBDIR="$pc_path" PKG_CONFIG_PATH="$pc_path" pkg-config --print-requires-private --static "$lib_name" 2>/dev/null)
  
  if [ $? -eq 0 ]; then
      echo "  [OK] Dependency tree resolved:"
      echo "     $deps"
      
      # Check if each dependency actually exists in our custom folder
      for dep in $deps; do
          # Remove version constraints (e.g., glib-2.0 >= 2.80 -> glib-2.0)
          dep_clean=$(echo "$dep" | awk '{print $1}')
          if [ ! -f "$pc_path/$dep_clean.pc" ]; then
              echo "     [!] WARNING: Dependency '$dep_clean' not found in custom pkgconfig folder."
          fi
      done
  else
      echo "  [ERROR] pkg-config failed to resolve dependencies for $lib_name."
      echo "        Ensure all required .pc files are in $pc_path"
  fi

  # 4. Check for Headers
  if [ -d "$include_path" ] && [ -n "$(ls -A "$include_path" 2>/dev/null)" ]; then
      echo "  [OK] Headers directory is not empty: $include_path"
  else
      echo "  [WARNING] Headers directory is missing or empty."
  fi
  echo ""
}

# Usage: copy_and_link <destination> <link_to> <source_file_1> [source_file_2 ...]
copy_and_link() {
    # 1. Log the call for debugging
    echo "DEBUG: copy_and_link - $*" >>"$LOG_FILE"
    
    local destination="$1"
    local link_to="$2"
    shift 2

    # 2. Validation
    if [[ -z "$destination" || -z "$link_to" ]]; then
        echo "ERROR: destination and link_to are required." >&2
        return 1
    fi

    # Ensure target directories exist
    create_dir "$destination" || return 1
    create_dir "$link_to" || return 1

    local error_count=0

    for file in "$@"; do
        # Handle glob fail or missing files
        if [[ ! -e "$file" && ! -L "$file" ]]; then
            echo "  [Error] Failed to find $file" >&2
            continue
        fi

        local filename
        filename=$(basename "$file")
        local dest_full_path="${destination}/${filename}"
        local link_full_path="${link_to}/${filename}"

        # 3. Copy
        # We copy everything (files and directories)
        if ! cp -rf "$file" "$destination/"; then
            echo "  [Error] Failed to copy $file" >&2
            ((error_count++))
            continue
        else
            echo "  [Installed] $dest_full_path" >&2
        fi

        # 4. Filter: Only create links for FILES
        # If the source was a directory, we are done with this item (we don't symlink dirs)
        if [[ -d "$file" ]]; then
            find "$dest_full_path" >&1
            echo "  [Warning] Skipping $file is a directory" >&2
            continue
        fi

        # 5. Safety Check: Clean ONLY valid/invalid symlinks
        if [[ -L "$link_full_path" ]]; then
            # It IS a symlink (either valid or broken). 
            # We are replacing it, so we delete it.
            rm -f "$link_full_path"
        elif [[ -e "$link_full_path" ]]; then
            # It exists, but it is NOT a symlink (it's a real file or dir).
            # We must PROTECT it. Do not overwrite.
            echo "$link_full_path" >&1
            echo "  [Warning] Skipping link creation for $filename: Target exists and is not a symlink." >&2
            continue
        fi

        # 6. Link
        # We checked safety above, so we can link. 
        # using 'ln -s' without -f is safe because we manually removed conflicting symlinks.
        if [[ "$dest_full_path" == "$link_full_path" ]]; then
          echo " [Warning] Not creating link because destination is the same as link - $dest_full_path == $link_full_path" >&2
          echo "$link_full_path" >&1
        elif ! ln -s "$dest_full_path" "$link_full_path"; then
             echo "  [Error] Failed to link $filename" >&2
             ((error_count++))
             continue
        fi

        # 7. Output to Manifest (Standard Output)
        echo "$dest_full_path" >&1
    done

    # 8. Final Exit Code Check
    if [[ "$error_count" -gt 0 ]]; then
        return 1
    fi
}

# Helper: Define complex libs that require shared linking
is_shared_library() {
  case "${1,,}" in
    *jack*|*openvino*|*cuda*|*tensorflow*|*torch*|*vdpau*|*nvcc*|*python*) return 0 ;;
    *) return 1 ;;
  esac
}
# shellcheck disable=2206
# Usage: static_link_check "/path/to/lib.pc" OR "/path/to/pkgconfig"
static_link_check() {
    # 0. Pre-check
    if truthy "$skip_validation"; then
        echo
        echo "WARNING: Skipping check for Static + PIC (Linker Test)"
        return 0
    fi
    local input_path="$1" map_file="$2"
    local use_map=false
    [[ -n "$map_file" && -f "$map_file" ]] && use_map=true
    # --------------------------------------------------------------------------
    # HELPER: Check System Pkg Fallback
    # --------------------------------------------------------------------------
    _slc_check_system_pkg() {
        local pc_file="$1" log_file="$2"
        local system_paths="/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig:/usr/local/lib/pkgconfig:/opt/python/cp312-cp312/lib/pkgconfig"
        export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$system_paths"
        pkg-config --static --libs "$pc_file" 2>>"$log_file"
    }
    # --------------------------------------------------------------------------
    # HELPER: Check if its Compiler Pkg
    # --------------------------------------------------------------------------
    _slc_is_compiler_pkg() {
      local lib="${1#-l}"
      [[ "$lib" =~ ^(mingw32|mingwex|gcc|gcc_s)$ ]] # |stdc\+\+
    }
    # --------------------------------------------------------------------------
    # HELPER: Check if its System Pkg
    # --------------------------------------------------------------------------
    _slc_is_system_pkg() {
      local lib="${1#-l}"
      if islinux && [[ "$lib" =~ ^(m|c|dl|rt|pthread|stdc\+\+|gcc|gcc_s|atomic|glu|gl|GLEW|X11|Xext)$ ]]; then
        return 0
      fi
      if iswindows && \
        [[ "$lib" =~ ^(ws2_32|gdi32|winmm|ole32|uuid|crypt32|advapi32|user32|kernel32|shell32|glu32)$ ]] || \
        [[ "$lib" =~ ^(iphlpapi|secur32|setupapi|mfuuid|strmiids|bcrypt|ncrypt|psapi|version|d2d1|windowscodecs)$ ]] || \
        [[ "$lib" =~ ^(shlwapi|wldap32|imagehlp|d3d11|dxgi|opengl32|imm32|oleaut32|mfplat|gomp|userenv|mingw32)$ ]] || \
        [[ "$lib" =~ ^(mfreadwrite|mf|dsound|ksuser|uuid|comdlg32|avrt|dnsapi|msimg32|ntdll|dwrite|mingwex)$ ]] || \
        _slc_is_compiler_pkg "$lib"; then
          return 0
      fi
      return 1
    }
    # --------------------------------------------------------------------------
    # HELPER: Find Targets (.pc and .a files)
    # --------------------------------------------------------------------------
    _slc_find_targets() {
        local path="$1"
        local -n targets_ref="$2"
        if [ -f "$path" ]; then
            if [[ "$path" == *.pc || "$path" == *.a ]]; then
                targets_ref+=("$path")
            else
                echo "ERROR: File '$path' is not a .pc or .a file." >&2
                return 1
            fi
        elif [ -d "$path" ]; then
            local pcfg_dir="$path"
            [ -d "$path/lib/pkgconfig" ] && pcfg_dir="$path/lib/pkgconfig"
            if [ -d "$pcfg_dir" ]; then
                while IFS= read -r -d '' f; do targets_ref+=("$f"); done < <(find "$pcfg_dir" -maxdepth 1 -name "*.pc" -print0)
            fi
            while IFS= read -r -d '' f; do targets_ref+=("$f"); done < <(find "$path" -type f -name "*.a" -print0)
        else
            echo "ERROR: Input '$path' is not a valid file or directory." >&2
            return 1
        fi
    }
    # --------------------------------------------------------------------------
    # HELPER: Resolve Libraries (Pkg-Config -> File Paths)
    # --------------------------------------------------------------------------
    _slc_resolve_libs() {
        local target="$1" log_file="$2"
        local -n res_libs="$3" res_stats="$4"
        # A. Handle Static Lib Direct
        if [[ "$target" == *.a || "$target" == *.lib ]]; then
            res_libs="$target"
            res_stats[0]=1 
            return 0
        fi
        # B. Handle Pkg-Config
        local pcfg_dir=$(dirname "$target")
        local pkg_basename=$(basename "$target" .pc)
        local fallback_base=$(dirname "$(dirname "$pcfg_dir")")
        local pkg_prefix=$(pkg-config --variable=prefix "$target" 2>/dev/null)
        local search_base="${pkg_prefix:-$fallback_base}"
        export PKG_CONFIG_PATH="$pcfg_dir:$PKG_CONFIG_PATH"
        local raw_flags
        if ! raw_flags=$(pkg-config --static --libs "$pkg_basename" 2>"$log_file"); then
            if ! raw_flags=$(_slc_check_system_pkg "$target" "$log_file"); then
                return 1 
            fi
        fi
        local search_paths=()
        local final_libs=""

        # If target is /abs/path/to/lib/pkgconfig/x.pc, we want /abs/path/to/lib
        local derived_lib_dir="$(dirname "$pcfg_dir")"
        if [ -d "$derived_lib_dir" ]; then
            search_paths+=("$derived_lib_dir")
            # Force linker to know this path in case resolution fails
            final_libs="$final_libs -L$derived_lib_dir"
        fi
        
        # Add default lib dir relative to prefix (Fallback)
        local pkg_prefix=$(pkg-config --variable=prefix "$pkg_basename" 2>/dev/null)
        if [ -n "$pkg_prefix" ]; then
            search_paths+=("${pkg_prefix}/lib")
        fi

        # Add paths from -L flags
        for flag in $raw_flags; do
            if [[ "$flag" == -L* ]]; then
                search_paths+=("${flag#-L}")
                final_libs="$final_libs $flag"
            fi
        done
        for flag in $raw_flags; do
            if [[ "$flag" == -L* ]]; then
                search_paths+=("${flag#-L}")
            elif [[ "$flag" == /*.a || "$flag" == /*.lib ]]; then
                final_libs="$final_libs $flag"
                res_stats[0]=$((res_stats[0] + 1))
            elif [[ "$flag" == -l* ]]; then
                local lib="${flag#-l}"
                if [[ "$lib" == /* ]]; then
                    final_libs="$final_libs $lib" # Add as absolute path, strip -l
                    continue
                fi
                # Check if this lib requires shared linking
                local force_shared=false
                if is_shared_library "$lib"; then
                    force_shared=true
                fi
                # Filter system libs
                if _slc_is_system_pkg "$lib"; then
                    if _slc_is_compiler_pkg "$lib"; then continue; fi
                    res_stats[2]=$((res_stats[2] + 1))
                    final_libs="$final_libs -l${lib}"
                    continue
                fi
                local found=false
                for path in "${search_paths[@]}"; do
                    # --- SHARED PRIORITY FOR COMPLEX LIBS ---
                    if [ "$force_shared" = true ]; then
                        # 1. MinGW Import Lib (.dll.a)
                        if [ -f "${path}/lib${lib}.dll.a" ]; then
                            final_libs="$final_libs ${path}/lib${lib}.dll.a"
                            res_stats[1]=$((res_stats[1] + 1)) # Count as shared
                            found=true; break
                        # 2. Raw DLL (.dll) - if supported by linker
                        elif [ -f "${path}/lib${lib}.dll" ]; then
                            final_libs="$final_libs ${path}/lib${lib}.dll"
                            res_stats[1]=$((res_stats[1] + 1))
                            found=true; break
                        # 3. Linux Shared Object (.so)
                        elif [ -f "${path}/lib${lib}.so" ]; then
                            final_libs="$final_libs ${path}/lib${lib}.so"
                            res_stats[1]=$((res_stats[1] + 1))
                            found=true; break
                        # 4. macOS Shared Object (.dylib)
                        elif [ -f "${path}/lib${lib}.dylib" ]; then
                            final_libs="$final_libs ${path}/lib${lib}.dylib"
                            res_stats[1]=$((res_stats[1] + 1))
                            found=true; break
                        fi
                    fi
                    # ----------------------------------------
                    # Standard Static Search (Default)
                    if [ -f "${path}/lib${lib}.dll.a" ]; then
                        final_libs="$final_libs ${path}/lib${lib}.dll.a"
                        res_stats[0]=$((res_stats[0] + 1))
                        found=true; break
                    elif [ -f "${path}/lib${lib}.a" ]; then
                        final_libs="$final_libs ${path}/lib${lib}.a"
                        res_stats[0]=$((res_stats[0] + 1))
                        found=true; break
                    elif [ -f "${path}/${lib}.lib" ]; then
                        final_libs="$final_libs ${path}/${lib}.lib"
                        res_stats[0]=$((res_stats[0] + 1))
                        found=true; break
                    elif [ -f "${path}/lib${lib}.lib" ]; then
                        final_libs="$final_libs ${path}/lib${lib}.lib"
                        res_stats[0]=$((res_stats[0] + 1))
                        found=true; break
                    elif v_lib=$(find "${path}" -maxdepth 1 -name "lib${lib}.a.*" 2>/dev/null | sort -V | tail -n 1) && [ -n "$v_lib" ]; then
                        final_libs="$final_libs $v_lib"
                        res_stats[0]=$((res_stats[0] + 1))
                        found=true; break
                    elif [ -f "${path}/lib${lib}.so" ]; then
                         # Fallback to shared if static is missing, but count it
                        final_libs="$final_libs ${path}/lib${lib}.so"
                        res_stats[1]=$((res_stats[1] + 1))
                        found=true; break
                    elif [ -f "${path}/lib${lib}.dylib" ]; then
                        final_libs="$final_libs ${path}/lib${lib}.dylib"
                        res_stats[1]=$((res_stats[1] + 1))
                        found=true; break
                    fi
                done
                if [ "$found" = false ]; then
                     echo "        | [WARNING]: Could not find library file for -l${lib} in search paths: ${search_paths[*]}" >>"$log_file"
                     final_libs="$final_libs -l${lib}"
                fi
            fi
        done
        final_libs=$(echo "$final_libs" | xargs -n1 | awk '!x[$0]++' | xargs)
        res_libs="$final_libs"
        return 0
    }
    # --------------------------------------------------------------------------
    # HELPER: Verify Binary (GCC/Clang Link Test) [UPDATED]
    # --------------------------------------------------------------------------
    _slc_verify_binary() {
        local libs="$1" name="$2" tmp="$3" log="$4"
        local ext="so"
        local sys_libs=""
        if iswindows; then 
          sys_libs="-lcrypt32 -lwindowscodecs -ldwrite -ld2d1 -lshlwapi -lole32 -lshell32 -luuid -lws2_32 -ladvapi32 -luser32 -lkernel32 -lmsvcrt -lwinmm"
          ext="dll"
        elif ismacos || isios; then
          ext="dylib"
        fi
        local out_bin="${tmp}/${name}.${ext}"
        local gcc_bin=g++
        if truthy "$build_cross_compile"; then gcc_bin=${cross_prefix}g++; fi
        local cmd=($gcc_bin -shared -fPIC -o "$out_bin")
        cmd+=("-DGLIB_STATIC_COMPILATION")
        # We split the string $libs into an array of arguments
        for lib in $libs; do
            # 1. Check for Static Archive (.a)
            if [[ "$lib" == *.a ]]; then
                # EXCEPTION A: Windows Import Libraries (.dll.a)
                # These are shared pointers, NOT static code. Do not merge.
                if [[ "$lib" == *.dll.a ]]; then
                    cmd+=("$lib")
                else
                    # It is a true static archive (Linux, Windows, or Mac). Force merge it.
                    if ismacos || isios; then
                        cmd+=("-Wl,-force_load" "$lib")
                    else
                        cmd+=("-Wl,--whole-archive" "$lib" "-Wl,--no-whole-archive")
                    fi
                fi
            # 2. Check for Shared Libraries explicitly
            # Linux (.so, .so.1), Windows (.dll), or Mac (.dylib)
            elif [[ "$lib" == *.so || "$lib" == *.so.* || "$lib" == *.dll || "$lib" == *.dylib ]]; then
                 cmd+=("$lib")
            # 3. Pass everything else (Flags -l, -L, -pthread, etc.) as-is
            else
                cmd+=("$lib")
            fi
        done
        if ! ismacos && ! isios; then
            cmd+=("-static" "-static-libgcc" "-static-libstdc++" "$stdcpp_path" "$stdgcc_path")
        fi
        if [ "$use_map" = true ] && ! ismacos && ! isios; then
            cmd+=("-Wl,--version-script=$map_file" "-Wl,-Bsymbolic")
        fi
        if ismacos || isios; then
            cmd+=("-undefined" "dynamic_lookup")
        else
            cmd+=("-Wl,--allow-multiple-definition" "-Wl,--unresolved-symbols=ignore-all")
        fi
        cmd+=($sys_libs)
        # Execute
        if "${cmd[@]}" > "$log" 2>&1 && [[ -f "$out_bin" ]]; then
            # Get binary size
            local bin_size=$(du -h "$out_bin" | cut -f1)
            
            # Check for shared libstdc++ and libgcc dependencies
            local shared_libs=$(_slc_check_shared_libs "$out_bin")
            
            if [[ -n "$shared_libs" ]]; then
                # Shared runtime libraries detected - return failure
                echo "fail:Shared runtime libraries detected: $shared_libs"
                return 0
            fi
            
            # Success - return size
            echo "success:$bin_size"
            return 0
        else
            # Linker failed
            echo "fail:Linker error"
            return 0
        fi
    }
        # --------------------------------------------------------------------------
    # HELPER: Check for shared libstdc++ and libgcc dependencies
    # --------------------------------------------------------------------------
    _slc_check_shared_libs() {
        local binary="$1"
        local shared_libs=""
        
        if iswindows; then
            # Windows: Use objdump to check for DLL imports
            if command -v "${cross_prefix}objdump" >/dev/null 2>&1; then
                # Check for libstdc++-6.dll and libgcc_s_*.dll
                if "${cross_prefix}objdump" -p "$binary" 2>/dev/null | grep -q "DLL Name: libstdc++-.*\.dll"; then
                    shared_libs+="libstdc++-6.dll "
                fi
                if "${cross_prefix}objdump" -p "$binary" 2>/dev/null | grep -q "DLL Name: libgcc_s_.*\.dll"; then
                    shared_libs+="libgcc_s.dll "
                fi
                if "${cross_prefix}objdump" -p "$binary" 2>/dev/null | grep -q "DLL Name: libgcc_.*\.dll"; then
                    shared_libs+="libgcc.dll "
                fi
            fi
        elif ismacos || isios; then
            # MacOS/iOS: Use otool to check for shared library dependencies
            if command -v otool >/dev/null 2>&1; then
                if otool -L "$binary" 2>/dev/null | grep -q "libstdc++.*\.dylib"; then
                    shared_libs+="libstdc++.dylib "
                fi
                if otool -L "$binary" 2>/dev/null | grep -q "libgcc_s.*\.dylib"; then
                    shared_libs+="libgcc_s.dylib "
                fi
            fi
        else
            # Linux: Use ldd to check for shared library dependencies
            if command -v ldd >/dev/null 2>&1; then
                # Check for libstdc++.so
                if ldd "$binary" 2>/dev/null | grep -q "libstdc++\.so"; then
                    shared_libs+="libstdc++.so "
                fi
                # Check for libgcc_s.so
                if ldd "$binary" 2>/dev/null | grep -q "libgcc_s\.so"; then
                    shared_libs+="libgcc_s.so "
                fi
            fi
        fi
        
        echo "$shared_libs"
    }
    # --------------------------------------------------------------------------
    # HELPER: Print Report
    # --------------------------------------------------------------------------
    _slc_print_report() {
        local -n succ="$1" skip="$2" fail="$3"
        if [ ${#succ[@]} -gt 0 ]; then
            echo -e "\n  [ VERIFIED PACKAGES ]"
            printf "  %-8s %-30s %-12s %-12s %-12s\n" "SIZE" "PACKAGE" "STATIC" "SHARED" "SYSTEM"
            echo "  --------------------------------------------------------------------------------"
            printf "%s\n" "${succ[@]}"
        fi
        if [ ${#skip[@]} -gt 0 ]; then
            echo -e "\n  [ SKIPPED PACKAGES ]"
            printf "  %-30s %s\n" "PACKAGE" "REASON"
            echo "  --------------------------------------------------------------------------------"
            printf "%s\n" "${skip[@]}"
        fi
        if [ ${#fail[@]} -gt 0 ]; then
            echo -e "\n  [ FAILED PACKAGES ]"
            echo "  --------------------------------------------------------------------------------"
            printf "%b\n" "${fail[@]}"
        fi
        echo -e "\n--------------------------------------------------------------------------------"
        local total=$((${#succ[@]} + ${#skip[@]} + ${#fail[@]}))
        if [ ${#fail[@]} -eq 0 ]; then
            echo "SUCCESS: Checked $total pkgs. Verified: ${#succ[@]}, Skipped: ${#skip[@]}, Failed: 0."
            return 0
        else
            echo "FAILURE: Checked $total pkgs. Verified: ${#succ[@]}, Skipped: ${#skip[@]}, Failed: ${#fail[@]}."
            return 1
        fi
    }
    # ==========================================================================
    # MAIN LOGIC
    # ==========================================================================
    {
        echo
        echo "VERIFYING BUILD: Checking for Static + PIC (Linker Test)"
        local targets=()
        if ! _slc_find_targets "$input_path" targets; then return 1; fi
        local tmp_dir=$(mktemp -d)
        local a_success=() a_skipped=() a_failed=()
        local total=${#targets[@]} count=0
        if [ "$total" -eq 0 ]; then
            echo "WARNING: No targets found in $input_path"
            rm -rf "$tmp_dir"
            return 0
        fi
        printf "\033[?25l"
        for target in "${targets[@]}"; do
            count=$((count + 1))
            local pkg_name=$(basename "$target")
            [[ "$target" == *.pc ]] && pkg_name=$(basename "$target" .pc)
            local log_file="${tmp_dir}/${pkg_name}_error.log"
            printf "\r\033[K[ %d / %d ] Checking: %s..." "$count" "$total" "$pkg_name" >&2
            local resolved_libs=""
            local -a stats=(0 0 0)
            if ! _slc_resolve_libs "$target" "$log_file" resolved_libs stats; then
                local err=$(sed -i'' -e 's|.*libraries/lib|...libraries/lib|' \
                -e 's/^/        | /' "$log_file")
                a_failed+=("  [FAIL] $pkg_name (Config Parse Error)\n$err")
                continue
            fi
            if [[ -z "$resolved_libs" ]]; then
                if [ "${stats[2]}" -gt 0 ]; then
                    a_skipped+=("$(printf "  %-30s %s" "$pkg_name" "System/External Libs Only (${stats[2]})")")
                else
                    a_skipped+=("$(printf "  %-30s %s" "$pkg_name" "Header-only / No Libs")")
                fi
                continue
            fi
            local bin_size
            local verify_result
            verify_result=$(_slc_verify_binary "$resolved_libs" "$pkg_name" "$tmp_dir" "$log_file")
            if [[ "$verify_result" == success:* ]]; then
                bin_size="${verify_result#success:}"
                a_success+=("$(printf "  %-8s %-30s %-12d %-12d %-12d" "$bin_size" "$pkg_name" "${stats[0]}" "${stats[1]}" "${stats[2]}")")
            else
                local reason="${verify_result#fail:}"
                local err=$(sed -i'' -e 's|.*libraries/lib|...libraries/lib|' \
                -e 's/^/        | /' "$log_file")
                a_failed+=("  [FAIL] $pkg_name ($reason)\n        Libraries: $resolved_libs\n$err")
            fi
        done
        printf "\r\033[K" >&2
        printf "\033[?25h"
        rm -rf "$tmp_dir"
        _slc_print_report a_success a_skipped a_failed

    } | tee -a "${LOG_FILE}"
}

create_linker_script() {
  local script="$ffmpeg_source_dir/ffmpeg-linker-script.map"
  if [[ ! -f "$script" ]]; then
  cat > "$script" << EOF
{
    global:
        av*;
        postproc_*;
        pp_*;
        swr_*;
        swresample_*;
        swscale_*;
        sws_*;
    local:
        *;
};
EOF
  fi
  echo "$script"
}

add_libs_to_pkg() {
    local pc="" pub_l=() priv_l=() pub_r=() priv_r=() cflags_l=()
    local mode="append" 
    while [[ $# -gt 0 ]]; do case "$1" in
        -t=*|--target=*) pc="${1#*=}" ;;
        -l=*|--libs=*)             IFS=' ' read -r -a _t <<< "${1#*=}"; pub_l+=("${_t[@]}") ;;
        -p=*|--private=*)          IFS=' ' read -r -a _t <<< "${1#*=}"; priv_l+=("${_t[@]}") ;;
        -r=*|--requires=*)         IFS=' ' read -r -a _t <<< "${1#*=}"; pub_r+=("${_t[@]}") ;;
        -rp=*|--requires-private=*) IFS=' ' read -r -a _t <<< "${1#*=}"; priv_r+=("${_t[@]}") ;;
        -c=*|--cflags=*)           IFS=' ' read -r -a _t <<< "${1#*=}"; cflags_l+=("${_t[@]}") ;;
        --prepend) mode="prepend" ;;  # Insert at START of line
        --) shift; break ;;
        *) echo "ERROR: Unknown option '$1'" >>"$LOG_FILE"; return 1 ;;
    esac; shift; done
    [[ -z "$pc" || ! -f "$pc" || "$pc" != /* ]] && { echo "ERROR: Invalid target '$pc'" >>"$LOG_FILE"; return 1; }
    _inject() {
        local field="$1" sanitize="$2"; shift 2; local items=("$@")
        [[ ${#items[@]} -eq 0 ]] && return
        grep -q "^$field:" "$pc" || echo "$field:" >> "$pc"
        local insertion_buffer=""
        for item in "${items[@]}"; do
            [[ -z "$item" ]] && continue
            local token="$item"
            if [[ $token == "/"* ]]; then
                token="$item"
            elif [[ "$sanitize" == "1" && "$token" != -* ]]; then
                local name="${token#-l}"; name="${name#lib}"; name="${name%.*}"
                token="-l$name"
            fi
            # shellcheck disable=2001
            local regex_token=$(echo "$token" | sed -e  's/[][()\.^$?*+{|}]/\\&/g')
            local sed_pattern="${regex_token//#/\\#}"
            if grep "^$field:" "$pc" | grep -E -q "(^|[[:space:]])${sed_pattern}($|[[:space:]])"; then
                sed -i'.bak' -e -E "s#([[:space:]]|^)${sed_pattern}([[:space:]]|$)# #g" "$pc"
            fi
            insertion_buffer="${insertion_buffer} ${token}"
        done
        if [[ -n "$insertion_buffer" ]]; then
            if [[ "$mode" == "prepend" ]]; then
                sed -i'.bak' -e "s|^$field:|&${insertion_buffer}|" "$pc"
            else
                sed -i'.bak' -e "s|^$field:.*|&${insertion_buffer}|" "$pc"
            fi
        fi
    }
    _inject "Requires"         0 "${pub_r[@]}"
    _inject "Requires.private" 0 "${priv_r[@]}"
    _inject "Libs"             1 "${pub_l[@]}"
    _inject "Libs.private"     1 "${priv_l[@]}"
    _inject "Cflags"           0 "${cflags_l[@]}"
}

# Usage: install_prebuilt_binary -n="libname" -v="1.0" -s="src_dir" -p="Install prefix" -I="include_path" -L="lib_path" -B="bin_path" -d="Library desc" -m="Install manifest"
install_prebuilt_binary() {
    local lib_name="" version="" src_root="" inc_sub="" lib_sub="" bin_sub="" 
    local desc="$lib_name Prebuilt Library"
    local manifest=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n=*) lib_name="${1#*=}"; shift ;;
            -v=*) version="${1#*=}"; shift ;;
            -s=*) src_root="${1#*=}"; shift ;;
            -p=*) install_dir="${1#*=}"; shift ;;
            -I=*) inc_sub="${1#*=}"; shift ;;
            -L=*) lib_sub="${1#*=}"; shift ;;
            -B=*) bin_sub="${1#*=}"; shift ;;
            -d=*) desc="${1#*=}"; shift ;;
            -m=*) manifest="${1#*=}"; shift ;;
            *) shift ;;
        esac
    done
    [[ -z "$install_dir" ]] && install_dir="$dependency_install_prefix"
    create_dir "$install_dir/{lib,bin,include}"
    local install_lib="$install_dir/lib"
    local install_bin="$install_dir/bin"
    local install_inc="$install_dir/include"
    [[ -z "$manifest" ]] && manifest="$install_pkgconfig_dir/${lib_name}_manifest"
    [[ ! -f "$manifest" ]] && touch "$manifest"
    echo "INFO: Installing Prebuilt $lib_name ($version)..." >>"$LOG_FILE"

    local gendef_tool="${cross_prefix}gendef"
    local dll_tool="${cross_prefix}dlltool"
    local objdump_tool="${cross_prefix}objdump"
    [[ ! -x "$(command -v "$gendef_tool")" ]] && gendef_tool="gendef"
    [[ ! -x "$(command -v "$dll_tool")" ]] && dll_tool="dlltool"
		
    # Use cross-objdump if available, otherwise llvm-objdump, otherwise system objdump
    if [[ ! -x "$(command -v "$objdump_tool")" ]]; then
        if command -v llvm-objdump >/dev/null 2>&1; then
            objdump_tool="llvm-objdump"
        else
            objdump_tool="objdump"
        fi
    fi
    local pkg_scan_dir=$(mktemp -d)
    # 1. Install Includes
    if [[ -d "$src_root/$inc_sub" && -n "$inc_sub" ]]; then
        cp -rf "$src_root/$inc_sub/"* "$install_inc/" 2>>"$LOG_FILE"
        find "$src_root/$inc_sub" -mindepth 1 -print0 | while IFS= read -r -d '' f; do
            local rel_path="${f#"$src_root/$inc_sub/"}"
            mkdir -p "$(dirname "$install_inc/$rel_path")"
            cp -rf "$f" "$install_inc/$rel_path" 2>>"$LOG_FILE"
            echo "$install_inc/$rel_path" >>"$manifest"
            echo "  [Installed]: $install_inc/$rel_path" >>"$LOG_FILE"
        done
    fi
    # 2. Install Binaries and Generate Import Libs
    if [[ -n "$bin_sub" && -d "$src_root/$bin_sub" ]]; then
        local tmp_def_dir=$(mktemp -d)
        find "$src_root/$bin_sub" -name "*.dll" -print0 | while IFS= read -r -d '' f; do
            local fname=$(basename "$f")
            local libname="${fname%.dll}"
            # Install the DLL to bin/
            cp -rf "$f" "$install_bin/" 2>>"$LOG_FILE"
            echo "$install_bin/$fname" >> "$manifest"
            echo "  [Installed]: $install_bin/$fname" >>"$LOG_FILE"
            pushd "$tmp_def_dir" >/dev/null || return 1
            local def_file="$tmp_def_dir/$libname.def"
            local def_generated=false
            # --- STRATEGY SELECTION (FILE SIZE) ---
            # gendef crashes on large files (>100MB). We check size safely.
            local prefer_objdump=false
            local fsize=0
            if command -v stat >/dev/null 2>&1; then
                fsize=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
            else
                fsize=$(wc -c < "$f" | tr -d ' ')
            fi
            # THRESHOLD: 50MB (52428800 bytes)
            if [ "$fsize" -gt 52428800 ]; then
                prefer_objdump=true
            fi
            # --- ATTEMPT 1: OBJDUMP (Prioritized for large libs) ---
            if [ "$prefer_objdump" = true ] && command -v "$objdump_tool" >/dev/null 2>&1; then
                echo "  [Warning]: File $fname is large ($((fsize/1024/1024)) MB). Skipping gendef to prevent crash. Using $objdump_tool..." >>"$LOG_FILE"
                echo "LIBRARY \"$fname\"" > "$def_file"
                echo "EXPORTS" >> "$def_file"
                # FIXED PARSING LOGIC: Exclude "Export RVA" and "Ordinal Base" garbage lines
                if "$objdump_tool" -p "$f" | grep "\[ *[0-9]*\]" | grep -v "Export RVA" | grep -v "Ordinal Base" | awk '{print $NF}' >> "$def_file"; then
                    if [[ -s "$def_file" ]]; then def_generated=true; fi
                fi
            fi
            # --- ATTEMPT 2: GENDEF (Standard) ---
            if [ "$def_generated" = false ]; then
                set +e
                ("$gendef_tool" "$f" >/dev/null 2>&1)
                local rc=$?
                set -e
                if [ "$rc" -eq 0 ] && [[ -f "$def_file" ]]; then
                    def_generated=true
                fi
            fi
            # --- ATTEMPT 3: OBJDUMP (Fallback) ---
            if [ "$def_generated" = false ] && [ "$prefer_objdump" = false ] && command -v "$objdump_tool" >/dev/null 2>&1; then
                echo "  [INFO]: gendef failed/crashed for $fname. Retrying with $objdump_tool..." >>"$LOG_FILE"
                echo "LIBRARY \"$fname\"" > "$def_file"
                echo "EXPORTS" >> "$def_file"
                # FIXED PARSING LOGIC: Same as above
                if "$objdump_tool" -p "$f" | grep "\[ *[0-9]*\]" | grep -v "Export RVA" | grep -v "Ordinal Base" | awk '{print $NF}' >> "$def_file"; then
                    if [[ -s "$def_file" ]]; then def_generated=true; fi
                fi
            fi
            # --- PROCESS RESULT ---
            if [ "$def_generated" = true ]; then
                echo "INFO: Generated MinGW import lib for $fname" >>"$LOG_FILE"
                "$dll_tool" -d "$def_file" -D "$fname" -l "$install_lib/lib$libname.dll.a"
                echo "$install_lib/lib$libname.dll.a" >> "$manifest"
                cp -rf "$install_lib/lib$libname.dll.a" "$pkg_scan_dir/" 2>>"$LOG_FILE"
                rm -f "$install_lib/lib$libname.a"
                echo "  [Installed]: $install_lib/lib$libname.dll.a" >>"$LOG_FILE"
            else
                echo "  [WARNING]: Failed to generate def file for $fname. Using direct DLL linking." >>"$LOG_FILE"
                cp -f "$f" "$install_lib/lib$libname.dll" 2>>"$LOG_FILE"
                echo "$install_lib/lib$libname.dll" >> "$manifest"
                cp -f "$f" "$pkg_scan_dir/lib$libname.dll" 2>>"$LOG_FILE"
            fi
            popd >/dev/null || return 1
        done
        rm -rf "$tmp_def_dir"
        find "$src_root/$bin_sub" -type f \( -not -name "*.dll" \) -print0 | while IFS= read -r -d '' f; do
            cp -rf "$f" "$install_bin/" 2>>"$LOG_FILE"
            echo "$install_bin/$(basename "$f")" >> "$manifest"
            echo "  [Installed]: $install_bin/$(basename "$f")" >>"$LOG_FILE"
        done
    fi
    # 3. Install Existing Libs (if any)
    if [[ -d "$src_root/$lib_sub" && -n "$lib_sub" ]]; then
        find "$src_root/$lib_sub" \( -name "*.lib" -o -name "*.dll.a" -o -name "*.a*" -o -name "*.so*" -o -name "*.dylib" \) -print0 | while IFS= read -r -d '' f; do
            local fname=$(basename "$f")
            local libname="${fname%.lib}"
            cp -rf "$f" "$install_lib/$fname" 2>>"$LOG_FILE"
            echo "$install_lib/$fname" >> "$manifest"
            echo "  [Installed]: $install_lib/$fname" >>"$LOG_FILE"
            if [[ "$fname" == *.lib ]]; then
                if [[ -f "$install_lib/lib$libname.dll.a" || -f "$install_lib/lib$libname.dll" ]]; then
                    : 
                else
                    echo "  [SKIP]: Skipping incompatible MSVC static library: $fname" >>"$LOG_FILE"
                    continue
                fi
            fi
            if [[ "$fname" == *.a* || "$fname" == *.so* ]]; then
              cp -f "$f" "$pkg_scan_dir/$fname" 2>>"$LOG_FILE"
            fi
        done
    fi
    generate_pkg_config -t="$pkg_scan_dir" \
        -o="$install_pkgconfig_dir/$lib_name.pc" \
        -i="$install_dir" \
        -v="$version" -n="$lib_name" -d="$desc" >/dev/null 2>&1
    rm -rf "$pkg_scan_dir"
    echo "$install_pkgconfig_dir/$lib_name.pc" >> "$manifest"
    echo "  [Installed]: $install_pkgconfig_dir/$lib_name.pc" >>"$LOG_FILE"
    return 0
}

# Function to resolve dependencies into an optimized build order
# Arguments: An array of requested build steps (e.g., "build_libtesseract" "build_ffmpeg")
# Output: A space-separated list of build steps in the correct order
optimize_dependencies() {
    local -a sorted_order=()
    local -A visited
    local -A processing
    # Helper function for recursive Topological Sort (DFS)
    visit() {
        local node=$1
        # If already fully processed and added to sorted_order, skip
        if [[ -n "${visited[$node]}" ]]; then
            return
        fi
        # Detect Circular Dependencies
        if [[ -n "${processing[$node]}" ]]; then
            exit_message 1 "Circular dependency detected at $node" | tee -a "$LOG_FILE"
        fi
        # Validation: Check if function is defined in current scope
        if ! declare -F "$node" >/dev/null; then
            echo "DEBUG: Skipping $node (not defined on $host_platform)" >>"$LOG_FILE"
            return
        fi
        # Mark as currently being processed (for cycle detection)
        processing[$node]=1
        # Retrieve sub-dependencies from the global SUB_DEPENDENCIES array
        local deps="${SUB_DEPENDENCIES[$node]}"
        # Recurse into sub-dependencies first
        for dep in $deps; do
            visit "$dep"
        done
        # Mark as finished and add to the final output array
        # shellcheck disable=2184,2086
        unset processing[$node]
        visited[$node]=1
        sorted_order+=("$node")
    }
    # Iterate through each initial requested build step
    for step in "${!BUILD_STEPS[@]}"; do
        if [[ -n "$step" ]]; then
            visit "$step"
        fi
    done
    # Output the final ordered array
    OPTIMIZED_BUILD_STEPS=("${sorted_order[@]}")
    if [[ " ${RUN_ARGS[*]} " =~ (^|[[:space:]])"--print-all-steps"($|[[:space:]]) ]]; then
      print_build_steps | tee -a "$LOG_FILE"
    fi
    if [[ " ${RUN_ARGS[*]} " =~ (^|[[:space:]])"--print-total-steps"($|[[:space:]]) ]]; then
      echo "INFO: Number of build steps: ${#OPTIMIZED_BUILD_STEPS[@]}" | tee -a "$LOG_FILE"
    fi
}

get_version() {
  local version_file="$BASEDIR/version"
  local version=$(cat "$version_file")
  echo "$version"
}

increment_version_patch() {
  local version_file="$BASEDIR/version"
  local version=$(cat "$version_file")
  local version_array=("${version//./ }")
  local version_major=${version_array[0]}
  local version_minor=${version_array[1]}
  local version_patch=${version_array[2]}
  version_patch=$((version_patch + 1))
  echo "$version_major.$version_minor.$version_patch" > "$version_file"
}

increment_version_minor() {
  local version_file="$BASEDIR/version"
  local version=$(cat "$version_file")
  local version_array=("${version//./ }")
  local version_major=${version_array[0]}
  local version_minor=${version_array[1]}
  local version_patch=${version_array[2]}
  version_minor=$((version_minor + 1))
  version_patch=0
  echo "$version_major.$version_minor.$version_patch" > "$version_file"
}

increment_version_major() {
  local version_file="$BASEDIR/version"
  local version=$(cat "$version_file")
  local version_array=("${version//./ }")
  local version_major=${version_array[0]}
  local version_minor=${version_array[1]}
  local version_patch=${version_array[2]}
  version_major=$((version_major + 1))
  version_minor=0
  version_patch=0
  echo "$version_major.$version_minor.$version_patch" > "$version_file"
}

set_version() {
  local version_file="$BASEDIR/version"
  local version="$1"
  echo "$version" > "$version_file"
}

get_latest_version_from_changelog() {
  local version_file="$BASEDIR/CHANGELOG.md"
  local version=$(awk '/## Version / && ++c==1 {print; exit}' "$version_file" | sed -e 's/## Version //')
  set_version "$version"
  echo "$version"
}

get_previous_version_from_changelog() {
  local version_file="$BASEDIR/CHANGELOG.md"
  if [[ ! -f "$version_file" ]]; then
    exit_message 1 "Changelog file not found" | tee -a "$LOG_FILE"
  fi
  local version=$(awk '/## Version / && ++c==2 {print; exit}' "$version_file" | sed -e 's/## Version //')
  echo "$version"
}

get_changes_from_changelog() {
  local changelog_file="$BASEDIR/CHANGELOG.md"
  local cur_version=$(get_latest_version_from_changelog)
  local prev_version=$(get_previous_version_from_changelog)

  if [[ -z "$cur_version" || -z "$prev_version" ]]; then
    echo "Internal Error: Could not determine version range." >&2
    return 1
  fi

  # Escape dots so they are treated literally in regex
  local cur_esc=$(echo "$cur_version" | sed 's/\./\\./g')
  local prev_esc=$(echo "$prev_version" | sed 's/\./\\./g')

  # Extract from current version header to line before previous version header
  # sed -n:    suppress automatic printing
  # /pat1/,/pat2/p: print the range (both headers included)
  # sed '$d':  delete last line (the previous version header) – works on macOS
  local changes=$(sed -n "/^## Version $cur_esc/,/^## Version $prev_esc/p" "$changelog_file" | sed '$d')

  # (Optional) Remove the current version header line if you only want the bullet points:
  # changes=$(echo "$changes" | sed '1d')

  # Trim leading/trailing blank lines (preserve your original trimming logic)
  echo "$changes" | sed -e '/./,$!d' -e :a -e '/^\n*$/{$d;N;ba' -e '}'
}

get_keystore(){
  # Ensure the script is running with sudo
  if [ -z "$SUDO_USER" ]; then
    ORIGINAL_USER=$(whoami)
    ORIGINAL_HOME=$(eval echo ~"$ORIGINAL_USER")
  else
    ORIGINAL_USER="$SUDO_USER"
    ORIGINAL_HOME=$(eval echo ~"$SUDO_USER")
  fi

  if [[ -d "$ORIGINAL_HOME/.config/keystore" ]]; then
    echo "$ORIGINAL_HOME/.config/keystore"
  elif [[ -d "$HOME/.config/keystore" ]]; then
    # $HOME is root's home when running with sudo; this matches original ~ expansion
    realpath "$HOME/.config/keystore"
  else
    exit_message 1 "Keystore directory not found" | tee -a "$LOG_FILE"
  fi
}

get_maven_keystore_file() {
  if [[ -f "$(realpath "$(get_keystore)"/maven/maven)" ]]; then
    echo "$(realpath "$(get_keystore)"/maven/maven)"
  else
    exit_message 1 "Keystore file not found. Please create a .env or $(get_keystore)/maven/maven file with the following format: \n\
    OSSRH_USERNAME=<your-maven-username>\n\
    OSSRH_PASSWORD=<your-maven-password>\n\
    OSSRH_BASE64=<your-maven-username:password-base64>" | tee -a "$LOG_FILE"
  fi
}

get_maven_username() {
  local keystore="$(get_maven_keystore_file)"
  if [[ -f "$keystore" ]]; then
    local maven_username=$(grep '^OSSRH_USERNAME=' "$keystore" | cut -d '=' -f2- | tr -d '\r')
    if [[ -z "$maven_username" ]]; then
      exit_message 1 "Maven username not found" | tee -a "$LOG_FILE"
    fi
    echo "$maven_username"
  else
    exit_message 1 "Maven keystore file not found" | tee -a "$LOG_FILE"
  fi
}

get_maven_password() {
  local keystore="$(get_maven_keystore_file)"
  if [[ -f "$keystore" ]]; then
    local maven_password=$(grep '^OSSRH_PASSWORD=' "$keystore" | cut -d '=' -f2- | tr -d '\r')
    if [[ -z "$maven_password" ]]; then
      exit_message 1 "Maven password not found" | tee -a "$LOG_FILE"
    fi
    echo "$maven_password"
  else
    exit_message 1 "Maven keystore file not found" | tee -a "$LOG_FILE"
  fi
}

get_maven_base64() {
  local keystore="$(get_maven_keystore_file)"
  if [[ -f "$keystore" ]]; then
    local maven_base64=$(grep '^OSSRH_BASE64=' "$keystore" | cut -d '=' -f2- | tr -d '\r')
    if [[ -z "$maven_base64" ]]; then
      exit_message 1 "Maven base64 not found" | tee -a "$LOG_FILE"
    fi
    echo "$maven_base64"
  else
    exit_message 1 "Maven keystore file not found" | tee -a "$LOG_FILE"
  fi
}

get_keystore_file() {
  if [[ -f .env ]]; then
    echo ".env"
  elif [[ -f "$(realpath "$(get_keystore)"/github)" ]]; then
    echo "$(realpath "$(get_keystore)"/github)"
  else
    exit_message 1 "Keystore file not found. Please create a .env or $(get_keystore)/github file with the following format: \n\
    GH_TOKEN=<your-github-token>\n\
    GH_TOKEN_CLASSIC=<your-github-token-classic>\n\
    GH_OWNER=<your-github-owner>\n\
    GH_REPO=<your-github-repo>" | tee -a "$LOG_FILE"
  fi
}

get_github_token() {
  local keystore="$(get_keystore_file)"
  if [[ -f "$keystore" ]]; then
    local github_token=$(grep '^GH_TOKEN=' "$keystore" | cut -d '=' -f2- | tr -d '\r')
    if [[ -z "$github_token" ]]; then
      exit_message 1 "GitHub token not found" | tee -a "$LOG_FILE"
    fi
    echo "$github_token"
  else
    exit_message 1 "GitHub keystore file not found" | tee -a "$LOG_FILE"
  fi
}

get_github_token_classic() {
  local keystore="$(get_keystore_file)"
  if [[ -f "$keystore" ]]; then
    local github_token=$(grep '^GH_TOKEN_CLASSIC=' "$keystore" | cut -d '=' -f2- | tr -d '\r')
    if [[ -z "$github_token" ]]; then
      exit_message 1 "GitHub classic token not found" | tee -a "$LOG_FILE"
    fi
    echo "$github_token"
  else
    exit_message 1 "GitHub keystore file not found" | tee -a "$LOG_FILE"
  fi
}

get_github_repo() {
  local keystore="$(get_keystore_file)"
  if [[ -f "$keystore" ]]; then
    local github_repo=$(grep '^GH_REPO=' "$keystore" | cut -d '=' -f2- | tr -d '\r')
    if [[ -z "$github_repo" ]]; then
      exit_message 1 "GitHub repo not found in $keystore" | tee -a "$LOG_FILE"
    fi
    echo "$github_repo"
  else
    exit_message 1 "GitHub keystore file not found" | tee -a "$LOG_FILE"
  fi
}

get_github_owner() {
  local keystore="$(get_keystore_file)"
  if [[ -f "$keystore" ]]; then
    local github_owner=$(grep '^GH_OWNER=' "$keystore" | cut -d '=' -f2- | tr -d '\r')
    if [[ -z "$github_owner" ]]; then
      exit_message 1 "GitHub owner not found in $keystore" | tee -a "$LOG_FILE"
    fi
    echo "$github_owner"
  else
    exit_message 1 "GitHub keystore file not found" | tee -a "$LOG_FILE"
  fi
}

authorize_github() {
  local github_token="$(get_github_token)"
  local github_repo="$(get_github_repo)"
  local github_owner="$(get_github_owner)"
  if curl -f --request GET \
    --url "https://api.github.com/octocat" \
    --header "Authorization: Bearer $github_token" \
    --header "X-GitHub-Api-Version: 2022-11-28" > /dev/null 2>&1; then
    echo "GitHub token is valid." | tee -a "$LOG_FILE"
    return 0
  else
    exit_message 1 "GitHub token is invalid." | tee -a "$LOG_FILE"
    return 1
  fi
}

create_github_release() {
  if ! authorize_github; then
    exit_message 1 "GitHub token is invalid." | tee -a "$LOG_FILE"
    return 1
  fi
  local attachment="$1"
  local version=$(get_version)
  local tag="v$version-$host_platform"
  local repo="$(get_github_repo)"
  local owner="$(get_github_owner)"
  local github_token="$(get_github_token)"
  # check if tag exists
  if git show-ref --verify --tags "refs/tags/$tag"; then
    echo "Tag $tag already exists." | tee -a "$LOG_FILE"
  else
    # create tag
    git tag "$tag"
    git push origin "$tag"
  fi
  # check if release exists
  if curl -f -v -s -H "Authorization: Bearer $github_token" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$owner/$repo/releases/tags/$tag" \
    >> "$LOG_FILE" 2>&1; then
    echo "Release $tag already exists." | tee -a "$LOG_FILE"
    # upload release asset
    upload_release_asset "$attachment"
  else
    # create release
    echo "Creating release $tag..." | tee -a "$LOG_FILE"
    local json_payload=$(jq -n \
        --arg tag "$tag" \
        --arg body "$(get_changes_from_changelog)" \
        '{
            tag_name: $tag,
            name: $tag,
            body: $body,
            draft: false,
            prerelease: true,
            discussion_category_name: "Releases",
            generate_release_notes: true,
            make_latest: "true"
        }')
    echo "$json_payload" >> "$LOG_FILE"
    if curl -f -v -s -H "Authorization: Bearer $github_token" \
        -H "Accept: application/vnd.github+json" \
        -d "$json_payload" \
        "https://api.github.com/repos/$owner/$repo/releases" \
        >> "$LOG_FILE" 2>&1; then
      echo "Release $tag created successfully." | tee -a "$LOG_FILE"
      upload_release_asset "$attachment"
    else
      echo "Failed to create release $tag." | tee -a "$LOG_FILE"
      return 1
    fi
  fi
}

upload_release_asset() {
  local attachment="$1"
  local asset_name=$(basename "$attachment")
  local version=$(get_version)
  local tag="v$version-$host_platform"
  local repo="$(get_github_repo)"
  local owner="$(get_github_owner)"
  local github_token="$(get_github_token)"

  # Retrieve release metadata
  local release_json=$(curl -f -s -H "Authorization: Bearer $github_token" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$owner/$repo/releases/tags/$tag")

  if [[ $? -ne 0 ]] || [[ -z "$release_json" ]]; then
    echo "Error: Could not find release for tag $tag" | tee -a "$LOG_FILE"
    return 1
  fi

  local release_id=$(echo "$release_json" | jq -r '.id')

  # Check for existing asset with the same name
  local existing_asset_id=$(echo "$release_json" | jq -r ".assets[] | select(.name == \"$asset_name\") | .id")

  if [[ -n "$existing_asset_id" && "$existing_asset_id" != "null" ]]; then
    echo "Asset $asset_name already exists (ID: $existing_asset_id). Deleting..." | tee -a "$LOG_FILE"
    curl -f -s -X DELETE \
      -H "Authorization: Bearer $github_token" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$owner/$repo/releases/assets/$existing_asset_id"
    
    if [[ $? -ne 0 ]]; then
      echo "Warning: Failed to delete existing asset. Upload might fail." | tee -a "$LOG_FILE"
    fi
  fi

  # Upload the asset
  echo "Uploading $attachment as release asset for $tag..." | tee -a "$LOG_FILE"
  if curl -f -s -H "Authorization: Bearer $github_token" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"$attachment" \
    "https://uploads.github.com/repos/$owner/$repo/releases/$release_id/assets?name=$asset_name" >> "$LOG_FILE" 2>&1; then
    echo "Uploaded $attachment successfully." | tee -a "$LOG_FILE"
  else
    exit_message 1 "Failed to upload $attachment. Please check the logs."
  fi
}

check_existing_package() {
  local package_name="$1"
  local package_version="$2"
  local owner="$(get_github_owner)"
  local github_token="$(get_github_token_classic)"
  local package_type="maven"

  echo "Checking for existing package $package_name version $package_version..." > >(redirect_output)

  # Retrieve package versions metadata
  local versions_json=$(curl -s \
    -H "Authorization: Bearer $github_token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/users/$owner/packages/$package_type/$package_name/versions")

  # 1. Safely check for error message ONLY if it's an object
  # If it's an array, error_msg will be empty
  local error_msg=$(echo "$versions_json" | jq -r 'if type == "object" then .message else empty end')
  
  if [[ -n "$error_msg" && "$error_msg" != "null" ]]; then
    # Return nothing and exit 1 so the caller knows it doesn't exist/error
    echo "Error: $error_msg" > >(redirect_output)
    return 1
  fi

  # 2. Extract version ID safely from the array
  local version_id=$(echo "$versions_json" | jq -r ".[]? | select(.name == \"$package_version\") | .id")

  if [[ -n "$version_id" && "$version_id" != "null" ]]; then
    echo "Found existing package version: $version_id" > >(redirect_output)
    echo "$version_id"
    return 0
  fi

  return 1
}

delete_existing_package() {
  local package_name="$1"
  local package_version="$2"
  local owner="$(get_github_owner)"
  local github_token="$(get_github_token_classic)"
  local package_type="maven"

  # 1. Get all versions for the package
  local versions_json=$(curl -s \
    -H "Authorization: Bearer $github_token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/users/$owner/packages/$package_type/$package_name/versions")

  # Check if package exists at all (404/error check)
  local error_msg=$(echo "$versions_json" | jq -r 'if type == "object" then .message else empty end')
  if [[ -n "$error_msg" && "$error_msg" != "null" ]]; then
    echo "Package $package_name does not exist in registry yet. Proceeding..." | tee -a "$LOG_FILE"
    return 0
  fi

  # 2. Count total versions and find target version ID
  local version_count=$(echo "$versions_json" | jq '. | length')
  local version_id=$(echo "$versions_json" | jq -r ".[] | select(.name == \"$package_version\") | .id")

  if [[ -z "$version_id" || "$version_id" == "null" ]]; then
    echo "Version $package_version not found. Proceeding..." | tee -a "$LOG_FILE"
    return 0
  fi

  # 3. Handle Deletion logic
  local delete_url
  if [[ "$version_count" -eq 1 ]]; then
    echo "Last version detected. Deleting entire package: $package_name..." | tee -a "$LOG_FILE"
    delete_url="https://api.github.com/users/$owner/packages/$package_type/$package_name"
  else
    echo "Multiple versions exist. Deleting specific version ID: $version_id..." | tee -a "$LOG_FILE"
    delete_url="https://api.github.com/users/$owner/packages/$package_type/$package_name/versions/$version_id"
  fi

  local http_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    -H "Authorization: Bearer $github_token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$delete_url")

  if [[ "$http_code" == "204" ]]; then
    echo "Successfully deleted." | tee -a "$LOG_FILE"
  else
    echo "Warning: Delete failed with HTTP $http_code. Conflict may occur." | tee -a "$LOG_FILE"
  fi
}

check_maven_package_status() {
  local package_name="$1"
  local package_version="$2"
  local username="$(get_maven_username)"
  local password="$(get_maven_password)"
  local endpoint="https://central.sonatype.com/api/v1/publisher/published"
  local namespace="io.github.akashskypatel.ffmpegkit"

  echo "Checking for existing package $package_name version $package_version on Maven Central..." > >(redirect_output)
  auth_token="$(echo -n "$username:$password" | base64)"
  # Retrieve package versions metadata
  local status_json=$(curl -X 'GET' \
    "$endpoint?namespace=$namespace&name=$package_name&version=$package_version" \
    -H 'accept: application/json' \
    -H "Authorization: Basic $auth_token") > >(redirect_output)

  # 1. Safely check for error message ONLY if it's an object
  # If it's an array, error_msg will be empty
  local error_msg=$(echo "$status_json" | jq -r 'if type == "object" then .message else empty end')
  
  if [[ -n "$error_msg" && "$error_msg" != "null" ]]; then
    # Return nothing and exit 1 so the caller knows it doesn't exist/error
    echo "Error checking package status: $error_msg body: $status_json" > >(redirect_output)
    return 1
  fi

  # extract satus from json
  local status=$(echo "$status_json" | jq -r '.published')

  if [[ -n "$status" && "$status" != "null" ]]; then
    echo "Package status: $status" > >(redirect_output)
    if [[ "$status" == "true" ]]; then
      return 0
    else
      return 1
    fi
  fi

  return 1
}
