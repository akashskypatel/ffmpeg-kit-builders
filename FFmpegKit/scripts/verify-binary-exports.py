#!/usr/bin/env python3
"""Inspect final FFmpegKit dynamic exports for the full GPL acceptance build."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import struct
import subprocess
import sys
from types import SimpleNamespace


class VerificationError(Exception):
    pass


def run(command):
    try:
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, check=False)
    except OSError as exc:
        raise VerificationError(f"cannot run {command[0]}: {exc}") from exc
    if result.returncode:
        raise VerificationError(f"{' '.join(command)} exited {result.returncode}: {result.stderr[-600:]}")
    return result.stdout


def tool(name):
    found = shutil.which(name)
    if not found and name == "wasm-dis":
        candidate = Path("/usr/local/emsdk/upstream/bin/wasm-dis")
        found = str(candidate) if candidate.is_file() else None
    if not found:
        raise VerificationError(f"required inspection tool missing: {name}")
    return found


def elf_tool(name, android):
    if android:
        root = os.environ.get("LLVM_TOOLCHAIN")
        paths = [Path(root) / "bin" / name] if root else []
        paths.extend(sorted(Path("/usr/local/android-sdk/ndk").glob(
            f"*/toolchains/llvm/prebuilt/*/bin/{name}"), reverse=True))
        paths.extend(sorted(Path.home().glob(
            f"Android/Sdk/ndk/*/toolchains/llvm/prebuilt/*/bin/{name}"), reverse=True))
        for path in paths:
            if path.is_file():
                return str(path)
        return tool(name)
    return tool(name.replace("llvm-", ""))


def read_uleb(data, offset):
    result = shift = 0
    while True:
        if offset >= len(data) or shift > 35:
            raise VerificationError("malformed WASM LEB128 value")
        byte = data[offset]
        offset += 1
        result |= (byte & 127) << shift
        if byte < 128:
            return result, offset
        shift += 7


def wasm_exports(data):
    if data[:8] != b"\x00asm\x01\x00\x00\x00":
        raise VerificationError("not a supported WebAssembly module")
    position = 8
    exports = []
    while position < len(data):
        section = data[position]
        size, position = read_uleb(data, position + 1)
        end = position + size
        if end > len(data):
            raise VerificationError("truncated WASM section")
        if section == 7:
            count, position = read_uleb(data, position)
            for _ in range(count):
                length, position = read_uleb(data, position)
                if position + length + 1 > end:
                    raise VerificationError("truncated WASM export")
                name = data[position:position + length].decode("utf-8")
                position += length
                kind = data[position]
                _, position = read_uleb(data, position + 1)
                if kind not in (0, 1, 2, 3, 4):
                    raise VerificationError(f"invalid WASM export kind {kind}")
                exports.append(name)
            if position != end:
                raise VerificationError("malformed WASM export section")
        position = end
    if not exports:
        raise VerificationError("WASM module has no exports")
    return sorted(set(exports))


def parse_elf_symbols(output):
    exports = {}
    in_dynsym = False
    for line in output.splitlines():
        if line.startswith("Symbol table '"):
            in_dynsym = line.startswith("Symbol table '.dynsym'")
            continue
        if not in_dynsym or not re.match(r"^\s*\d+:", line):
            continue
        fields = line.split(maxsplit=7)
        if len(fields) < 8 or fields[4] not in ("GLOBAL", "WEAK") or fields[5] not in ("DEFAULT", "PROTECTED") or fields[6] in ("UND", "ABS"):
            continue
        raw = fields[7].split(" (", 1)[0]
        if not raw or raw == "0":
            raise VerificationError(f"malformed ELF dynamic symbol: {line}")
        logical = raw.split("@", 1)[0]
        exports.setdefault(logical, set()).add(raw)
    if not exports:
        raise VerificationError("no defined global ELF dynamic exports")
    return exports


def parse_pe_exports(output):
    marker = "[Ordinal/Name Pointer] Table"
    if marker not in output:
        raise VerificationError("PE Export Table name directory missing")
    result = []
    for line in output.split(marker, 1)[1].splitlines()[1:]:
        match = re.match(r"^\s*\[\s*\d+\]\s+\+base\[\s*\d+\]\s+[0-9a-fA-F]+\s+(\S+)", line)
        if match:
            result.append(match.group(1))
        elif result:
            break
    if not result:
        raise VerificationError("PE Export Table has no named exports")
    return {name: {name} for name in result}


def identify(data, platform, arch):
    if platform in ("linux", "android"):
        if data[:4] != b"\x7fELF" or data[5] not in (1, 2):
            raise VerificationError("expected ELF binary")
        machine = int.from_bytes(data[18:20], "little" if data[5] == 1 else "big")
        expected = {"x86_64": 62, "aarch64": 183, "arm64": 183, "armv7a": 40}.get(arch)
        if expected is None or machine != expected:
            raise VerificationError(f"ELF machine {machine} does not match {arch}")
        return f"ELF-{machine}"
    if platform == "windows":
        if data[:2] != b"MZ" or len(data) < 64:
            raise VerificationError("expected PE/COFF DLL")
        offset = struct.unpack_from("<I", data, 0x3c)[0]
        if data[offset:offset + 4] != b"PE\0\0":
            raise VerificationError("invalid PE signature")
        machine = struct.unpack_from("<H", data, offset + 4)[0]
        if arch != "x86_64" or machine != 0x8664:
            raise VerificationError(f"PE machine {machine:#x} does not match {arch}")
        return "PE-x86_64"
    if platform == "wasm":
        if arch != "wasm32" or data[:8] != b"\0asm\1\0\0\0":
            raise VerificationError("expected wasm32 module")
        return "wasm32"
    if platform == "apple":
        if data[:4] not in (b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
            raise VerificationError("expected Mach-O dylib")
        return "Mach-O"
    raise VerificationError(f"unsupported platform {platform}")


def inspect(args, data):
    platform = args.platform
    binary = str(args.binary)
    if platform in ("linux", "android"):
        name = "llvm-readelf" if platform == "android" else "readelf"
        command = [elf_tool(name, platform == "android"), "--dyn-syms", "--wide", binary]
        exports = parse_elf_symbols(run(command))
    elif platform == "windows":
        command = [tool("x86_64-w64-mingw32-objdump"), "-p", binary]
        exports = parse_pe_exports(run(command))
        # LLVM independently reads the PE export directory, never the import table.
        llvm = elf_tool("llvm-readobj", True)
        cross = run([llvm, "--coff-exports", binary])
        count = len(re.findall(r"^\s*Export \{", cross, re.MULTILINE))
        if count != len(exports):
            raise VerificationError(f"PE export inspectors disagree: {len(exports)} versus {count}")
    elif platform == "apple":
        wanted = "arm64" if args.arch in ("aarch64", "arm64") else args.arch
        archs = run([tool("xcrun"), "lipo", "-archs", binary]).split()
        if wanted not in archs:
            raise VerificationError(f"Mach-O architectures {archs} omit {wanted}")
        command = [tool("xcrun"), "nm", "-arch", wanted, "-gUj", binary]
        names = run(command).splitlines()
        if not names or any(not name.startswith("_") for name in names):
            raise VerificationError("empty or malformed Mach-O external defined symbol list")
        exports = {name: {name} for name in names}
        build = run([tool("xcrun"), "vtool", "-show-build", "-arch", wanted, binary])
        expected = {"macos": "MACOS", "ios": "IOS", "ios-simulator": "IOSSIMULATOR", "tvos": "TVOS", "tvos-simulator": "TVOSSIMULATOR"}.get(args.apple_platform)
        if not expected or not re.search(r"^\s*platform\s+" + expected + r"\b", build, re.MULTILINE):
            raise VerificationError(f"Mach-O platform does not match {args.apple_platform}: {build[-500:]}")
    else:
        command = [tool("wasm-dis"), binary, "-o", "/dev/null"]
        run(command)  # Established decoder validates the section parser's input.
        names = wasm_exports(data)
        exports = {name: {name} for name in names}
    return exports, command


def forbidden_owned_metadata(names):
    candidates = [name for name in names if re.match(r"^_ZT[ISV](?:St|NSt|N10__gnu_debug)", name) and ("ffmpegkit" in name or "4Json" in name)]
    if not candidates:
        return []
    demangler = tool("c++filt")
    output = run([demangler, *candidates]).splitlines()
    if len(output) != len(candidates):
        raise VerificationError("C++ demangler output count mismatch")
    return [raw for raw, demangled in zip(candidates, output)
            if re.match(r"^(?:typeinfo(?: name)? for|vtable for) (?:std::|__gnu_debug::)", demangled)
            and ("ffmpegkit::" in demangled or "Json::" in demangled)]


def anchors(args):
    if args.platform == "wasm":
        return []
    prefix = "_" if args.platform == "apple" else ""
    required = ["ffmpeg_kit_initialize", "ffmpeg_kit_execute", "ffmpeg_kit_set_log_callback"]
    if args.platform in ("linux", "android"):
        required += ["avcodec_version", "avformat_version", "avutil_version", "swresample_version", "swscale_version"]
    if args.platform == "android":
        required += ["JNI_OnLoad"]
    return [prefix + name for name in required]


WASM_API = (
    "malloc", "free", "ffmpeg_kit_initialize", "ffplay_kit_execute_async",
    "ffplay_kit_create_session", "ffplay_kit_close_session",
    "ffplay_kit_session_execute_async", "ffplay_kit_session_seek",
    "ffplay_kit_session_start", "ffplay_kit_session_pause",
    "ffplay_kit_session_resume", "ffplay_kit_session_stop",
    "ffplay_kit_session_get_position", "ffplay_kit_session_get_duration",
    "ffplay_kit_session_is_playing", "ffplay_kit_session_is_paused",
    "ffplay_kit_session_set_volume", "ffplay_kit_session_get_volume",
    "ffplay_kit_session_get_video_width", "ffplay_kit_session_get_video_height",
    "ffplay_kit_get_frame_buffer_size", "ffplay_kit_copy_frame",
)


def wasm_api_checks(binary, names):
    # Emscripten minifies WASM export names. Verify the loader's public-name
    # mapping points to real entries in the module's Export section.
    loader = binary.with_suffix(".mjs")
    if not loader.is_file():
        raise VerificationError(f"WASM loader missing beside module: {loader}")
    source = loader.read_text()
    checks = {}
    for name in WASM_API:
        match = re.search(r'Module\["_' + re.escape(name) + r'"\]=_' + re.escape(name) + r'=wasmExports\["([^"]+)"\]', source)
        checks[name] = match.group(1) if match and match.group(1) in names else None
    return checks, sorted(set(re.findall(r'Module\["_([^\"]*test_(?:emit|process)[^\"]*)"\]', source)))


def apple_target_from_plist(entry):
    platform = entry.get("SupportedPlatform")
    variant = entry.get("SupportedPlatformVariant")
    if platform not in ("ios", "tvos", "macos") or variant not in (None, "simulator"):
        raise VerificationError(f"unsupported XCFramework platform/variant: {platform}/{variant}")
    return platform + ("-simulator" if variant else "")


def expected_apple_targets(family, arches):
    if family not in ("ios", "macos", "appletvos"):
        raise VerificationError("XCFramework target family is required")
    base = "tvos" if family == "appletvos" else family
    expected = set()
    for token in arches.split(","):
        simulator = token.startswith("sim:")
        arch = token[4:] if simulator else token
        if arch not in ("aarch64", "x86_64"):
            raise VerificationError(f"unsupported expected XCFramework arch {arch}")
        expected.add((base + ("-simulator" if simulator else ""), arch))
    if not expected:
        raise VerificationError("XCFramework expected architecture set is empty")
    return expected


def apple_source_binary(root, target, arch, bundle, license_name):
    platform = {"ios": "ios", "ios-simulator": "iphonesimulator", "tvos": "appletvos",
                "tvos-simulator": "appletvsimulator", "macos": "macos"}[target]
    directory = root / f"{platform}-{arch}" / f"ffmpeg-kit-{bundle}-{platform}-{arch}-shared-{license_name}" / "lib"
    binary = directory / "libffmpegkit.dylib"
    if not binary.is_file():
        raise VerificationError(f"prepackage linked binary missing: {binary}")
    return binary


def uuid_set(path, arch):
    output = run([tool("xcrun"), "dwarfdump", "--uuid", str(path)])
    return set(re.findall(r"UUID: ([0-9A-Fa-f-]+) \(" + re.escape(arch) + r"\)", output))


def has_compile_unit(path):
    command = [tool("xcrun"), "dwarfdump", "--debug-info", str(path)]
    try:
        process = subprocess.Popen(command, text=True, stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL)
    except OSError as exc:
        raise VerificationError(f"cannot run dwarfdump: {exc}") from exc
    try:
        for line in process.stdout:
            if "DW_TAG_compile_unit" in line:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired as exc:
                    process.kill()
                    process.wait()
                    raise VerificationError(f"dwarfdump did not stop after finding a compile unit: {path}") from exc
                return True
        if process.wait() != 0:
            raise VerificationError(f"dwarfdump could not inspect {path}")
        return False
    finally:
        process.stdout.close()
        if process.poll() is None:
            process.kill()
            process.wait()


def inspect_xcframework(args):
    report = {"platform": "apple", "phase": "xcframework", "xcframework": str(args.xcframework),
              "bundle": args.bundle, "license": args.license, "size": args.size,
              "build_flags": shlex.split(os.environ.get("FFMPEGKIT_BUILD_FLAGS", "")),
              "expected_targets": [], "slices": [], "errors": []}
    try:
        if not args.xcframework.is_absolute() or not args.xcframework.is_dir():
            raise VerificationError("XCFramework must be an existing absolute directory")
        expected = expected_apple_targets(args.target_family, args.expected_archs)
        report["expected_targets"] = sorted([list(item) for item in expected])
        report["inspection_tool_version"] = run([tool("xcrun"), "--version"]).strip()
        info_path = args.xcframework / "Info.plist"
        with info_path.open("rb") as stream:
            entries = plistlib.load(stream)["AvailableLibraries"]
        if not isinstance(entries, list) or not entries:
            raise VerificationError("XCFramework Info.plist has no AvailableLibraries")
        seen = set()
        for entry in entries:
            target = apple_target_from_plist(entry)
            identifier = entry["LibraryIdentifier"]
            framework = args.xcframework / identifier / entry["LibraryPath"]
            binary = framework / "ffmpegkit"
            archs = entry["SupportedArchitectures"]
            for mach_arch in archs:
                arch = "aarch64" if mach_arch == "arm64" else mach_arch
                key = (target, arch)
                seen.add(key)
                item = {"target": target, "arch": arch, "library_identifier": identifier,
                        "binary": str(binary), "errors": []}
                report["slices"].append(item)
                try:
                    if key not in expected:
                        raise VerificationError(f"unexpected XCFramework slice {key}")
                    if not binary.is_file() or binary.stat().st_size == 0:
                        raise VerificationError(f"final framework binary missing: {binary}")
                    data = binary.read_bytes()
                    identify(data, "apple", arch)
                    slice_args = SimpleNamespace(platform="apple", binary=binary, arch=arch, apple_platform=target)
                    exports, command = inspect(slice_args, data)
                    names = sorted(exports)
                    item["sha256"] = hashlib.sha256(data).hexdigest()
                    item["export_count"] = len(names)
                    item["fingerprint"] = hashlib.sha256("\n".join(names).encode()).hexdigest()
                    item["inspection_command"] = command
                    item["lipo_architectures"] = run([tool("xcrun"), "lipo", "-archs", str(binary)]).split()
                    for anchor in anchors(slice_args):
                        if anchor not in exports:
                            item["errors"].append(f"missing public export {anchor}")
                    leaked = forbidden_owned_metadata(names)
                    if leaked:
                        item["errors"].append(f"STL-owned RTTI exports: {leaked}")
                    tests = [name for name in names if re.search(r"test_emit|clearLogsForTesting|test_process_wasm_callback_queue", name, re.I)]
                    if tests:
                        item["errors"].append(f"test-only exports: {tests}")
                    if target in ("ios", "ios-simulator"):
                        lzma = [name for name in names if name.startswith("_lzma_")]
                        item["unprefixed_lzma_exports"] = len(lzma)
                        if lzma:
                            item["errors"].append(f"unprefixed iOS LZMA exports: {lzma[:10]}")
                    if args.prepackage_root:
                        source = apple_source_binary(args.prepackage_root, target, arch, args.bundle, args.license)
                        linked_args = SimpleNamespace(platform="apple", binary=source, arch=arch, apple_platform=target)
                        linked, _ = inspect(linked_args, source.read_bytes())
                        item["prepackage_binary"] = str(source)
                        item["prepackage_export_count"] = len(linked)
                        missing = sorted(set(linked) - set(names))
                        added = sorted(set(names) - set(linked))
                        item["prepackage_delta"] = {"removed": missing, "added": added}
                        if missing or added:
                            item["errors"].append(f"packaging changed exports: -{len(missing)} +{len(added)}")
                    else:
                        item["errors"].append("prepackage root missing; cannot check A01")
                    debug_symbols_path = entry.get("DebugSymbolsPath", "dSYMs")
                    dsym = args.xcframework / identifier / debug_symbols_path / "ffmpegkit.framework.dSYM"
                    item["dsym_path"] = str(dsym)
                    if not dsym.is_dir():
                        item["errors"].append(f"framework dSYM missing: {dsym}")
                    else:
                        item["binary_uuid"] = sorted(uuid_set(binary, mach_arch))
                        item["dsym_uuid"] = sorted(uuid_set(dsym, mach_arch))
                        if not item["binary_uuid"] or item["binary_uuid"] != item["dsym_uuid"]:
                            item["errors"].append("framework and dSYM UUIDs differ")
                        item["dsym_has_compile_units"] = has_compile_unit(dsym)
                        if not item["dsym_has_compile_units"]:
                            item["errors"].append("dSYM has no compile units")
                    try:
                        run([tool("codesign"), "--verify", "--verbose=2", str(framework)])
                        item["codesign_verified"] = True
                    except VerificationError as exc:
                        item["codesign_verified"] = False
                        item["errors"].append(str(exc))
                    identity = run([tool("xcrun"), "otool", "-D", str(binary)])
                    item["install_name"] = identity.strip().splitlines()[-1]
                    if "@rpath/ffmpegkit.framework/ffmpegkit" not in identity:
                        item["errors"].append("unexpected LC_ID_DYLIB")
                    loads = run([tool("xcrun"), "otool", "-l", str(binary)])
                    rpaths = re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (\S+)", loads)
                    item["rpaths"] = rpaths
                    if any(path.startswith("/") for path in rpaths):
                        item["errors"].append("absolute build-machine LC_RPATH")
                    slice_root = args.xcframework / identifier
                    item["dylib_references"] = {}
                    item["dependency_signatures"] = {}
                    for inspected in [binary, *sorted(slice_root.glob("*.dylib"))]:
                        if inspected != binary:
                            try:
                                run([tool("codesign"), "--verify", "--verbose=2", str(inspected)])
                                item["dependency_signatures"][str(inspected)] = True
                            except VerificationError as exc:
                                item["dependency_signatures"][str(inspected)] = False
                                item["errors"].append(str(exc))
                        otool_output = run([tool("xcrun"), "otool", "-L", str(inspected)])
                        # Fat Mach-O output repeats unindented architecture headers;
                        # only indented lines are actual install/dependency names.
                        refs = [
                            line.strip().split(" ", 1)[0]
                            for line in otool_output.splitlines()
                            if line[:1].isspace() and line.strip()
                        ]
                        item["dylib_references"][str(inspected)] = refs
                        for ref in refs:
                            if ref == "@rpath/ffmpegkit.framework/ffmpegkit":
                                continue
                            if ref.startswith("@rpath/"):
                                if not (slice_root / Path(ref).name).exists():
                                    item["errors"].append(f"{inspected.name}: unresolved bundled dylib reference: {ref}")
                            elif ref.startswith("@loader_path/"):
                                if not (inspected.parent / ref[len("@loader_path/"):]).exists():
                                    item["errors"].append(f"{inspected.name}: unresolved loader-path reference: {ref}")
                            elif ref.startswith("/") and not (ref.startswith("/usr/lib/") or ref.startswith("/System/Library/")):
                                item["errors"].append(f"{inspected.name}: absolute non-system dylib reference: {ref}")
                    raw_path = args.report.with_name(args.report.stem + f"-{target}-{arch}.exports.txt")
                    raw_path.parent.mkdir(parents=True, exist_ok=True)
                    raw_path.write_text("\n".join(names) + "\n")
                    item["raw_exports_path"] = str(raw_path)
                except (VerificationError, ValueError, KeyError, OSError, UnicodeError) as exc:
                    item["errors"].append(str(exc))
                report["errors"].extend(f"{target}/{arch}: {error}" for error in item["errors"])
        if seen != expected:
            report["errors"].append(f"Info.plist slices differ: missing {sorted(expected - seen)}, extra {sorted(seen - expected)}")
        report["source_commit"] = run([tool("git"), "rev-parse", "HEAD"]).strip()
        if args.require_acceptance_profile and (args.bundle, args.license, args.size) != ("full", "gpl", "not-small"):
            report["errors"].append("acceptance profile is not full/gpl/not-small")
    except (VerificationError, ValueError, KeyError, OSError, UnicodeError) as exc:
        report["errors"].append(str(exc))
    report["pass"] = not report["errors"]
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    for error in report["errors"]:
        print(f"FAIL: {error}", file=sys.stderr)
    print(f"{'PASS' if report['pass'] else 'FAIL'}: XCFramework {args.xcframework}; {args.report}")
    return 0 if report["pass"] else 1


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("linux", "android", "windows", "apple", "wasm"), required=True)
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--xcframework", type=Path)
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--license", required=True)
    parser.add_argument("--size", required=True)
    parser.add_argument("--phase", choices=("linked", "xcframework"), required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--arch")
    parser.add_argument("--target-family")
    parser.add_argument("--expected-archs")
    parser.add_argument("--prepackage-root", type=Path)
    parser.add_argument("--apple-platform", choices=("macos", "ios", "ios-simulator", "tvos", "tvos-simulator"))
    parser.add_argument("--baseline-exports", type=Path)
    parser.add_argument("--capture-baseline", type=Path)
    parser.add_argument("--expected-policy", type=Path)
    parser.add_argument("--link-command", type=Path)
    parser.add_argument("--export-control", type=Path)
    parser.add_argument("--ffmpeg-config", type=Path)
    parser.add_argument("--cmake-cache", type=Path)
    parser.add_argument("--bundle-manifest", type=Path)
    parser.add_argument("--require-acceptance-profile", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    if args.xcframework:
        if args.phase != "xcframework" or args.platform != "apple" or not args.expected_archs:
            raise SystemExit("--xcframework requires Apple xcframework phase and expected architecture list")
        return inspect_xcframework(args)
    if not args.binary or not args.arch:
        raise SystemExit("--binary and --arch are required for linked-binary verification")
    report = {"platform": args.platform, "arch": args.arch, "apple_platform": args.apple_platform,
              "phase": args.phase, "bundle": args.bundle, "license": args.license,
              "size": args.size, "binary": str(args.binary), "checks": {}, "errors": []}
    report["build_flags"] = shlex.split(os.environ.get("FFMPEGKIT_BUILD_FLAGS", ""))
    exports = {}
    try:
        if not args.binary.is_absolute() or not args.binary.is_file() or args.binary.stat().st_size == 0:
            raise VerificationError("binary must be an existing nonempty absolute path")
        data = args.binary.read_bytes()
        allowed_names = {"linux": {"libffmpegkit.so"}, "android": {"libffmpegkit.so"},
                         "windows": {"libffmpegkit.dll", "ffmpegkit.dll"},
                         "wasm": {"ffmpegkit.wasm"},
                         "apple": {"libffmpegkit.dylib"} if args.phase == "linked" else {"ffmpegkit"}}
        if args.binary.name not in allowed_names[args.platform]:
            raise VerificationError(f"wrong final FFmpegKit artifact name: {args.binary.name}")
        report["sha256"] = hashlib.sha256(data).hexdigest()
        report["format"] = identify(data, args.platform, args.arch)
        exports, command = inspect(args, data)
        report["inspection_command"] = command
        report["inspection_tool_version"] = run([command[0], "--version"]).splitlines()[0] if args.platform != "apple" else run([tool("xcrun"), "nm", "--version"]).splitlines()[0]
        names = sorted(exports)
        report["export_count"] = len(names)
        report["elf_versions"] = {key: sorted(value) for key, value in exports.items() if value != {key}}
        report["fingerprint"] = hashlib.sha256("\n".join(names).encode()).hexdigest()
        report["checks"]["required"] = {name: name in exports for name in anchors(args)}
        for name, found in report["checks"]["required"].items():
            if not found:
                report["errors"].append(f"missing required export: {name}")
        if args.platform == "wasm":
            mapping, test_mapping = wasm_api_checks(args.binary, set(names))
            report["checks"]["wasm_public_api_to_export"] = mapping
            for name, target in mapping.items():
                if not target:
                    report["errors"].append(f"missing WASM public API mapping/export: {name}")
            if test_mapping:
                report["errors"].append(f"test-only WASM loader exports: {test_mapping}")
        if args.platform == "android" and not any(name.startswith("Java_") for name in names):
            report["errors"].append("missing Android Java_* JNI export")
        owned = forbidden_owned_metadata(names)
        report["checks"]["stl_owned_metadata"] = owned
        if owned:
            report["errors"].append(f"STL-owned FFmpegKit/Json RTTI or vtable exports: {len(owned)}")
        test_exports = [name for name in names if re.search(r"test_emit|clearLogsForTesting|test_process_wasm_callback_queue", name, re.I)]
        report["checks"]["test_only_exports"] = test_exports
        if test_exports:
            report["errors"].append(f"test-only production exports: {test_exports}")
        if args.expected_policy:
            policy = json.loads(args.expected_policy.read_text())
            denied = sorted(set(names).intersection(policy["forbidden_exports"]))
            report["checks"]["policy_forbidden"] = denied
            if denied:
                report["errors"].append(f"policy-forbidden exports: {denied}")
        if args.baseline_exports:
            baseline = json.loads(args.baseline_exports.read_text())
            previous = set(baseline["exports"])
            removed = sorted(previous - set(names))
            added = sorted(set(names) - previous)
            permitted = set(forbidden_owned_metadata(removed))
            # This baseline-only test hook is deliberately removed from all
            # production binaries under B08; keep the exception exact so no
            # other public C ABI removal is implicitly approved.
            permitted.update(
                name
                for name in removed
                if name in {
                    "ffmpeg_kit_test_emit_unattributed_log",
                    "_ffmpeg_kit_test_emit_unattributed_log",
                }
            )
            report["baseline"] = {"path": str(args.baseline_exports), "sha256": baseline.get("sha256"),
                                  "added": added, "removed": removed, "permitted_removals": sorted(permitted)}
            unexpected = sorted(set(removed) - permitted)
            if unexpected:
                report["errors"].append(f"unreviewed baseline removals: {len(unexpected)}: {unexpected[:12]}")
        if args.capture_baseline:
            if args.capture_baseline.exists():
                raise VerificationError("baseline capture refuses to overwrite an existing file")
            args.capture_baseline.parent.mkdir(parents=True, exist_ok=True)
            args.capture_baseline.write_text(json.dumps({"sha256": report["sha256"], "exports": names}, indent=2) + "\n")
        if args.link_command:
            link = args.link_command.read_text()
            control = args.export_control.read_text() if args.export_control else ""
            mode = {"linux": "--version-script", "android": "--version-script",
                    "windows": "--exclude-libs", "apple": "-exported_symbols_list",
                    "wasm": "-sEXPORTED_FUNCTIONS"}[args.platform]
            report["link_control"] = {"command_path": str(args.link_command), "control_path": str(args.export_control),
                                      "expected_option": mode, "option_present": mode in link,
                                      "control_sha256": hashlib.sha256(control.encode()).hexdigest() if control else None}
            if mode not in link:
                report["errors"].append(f"link command lacks {mode}")
            if args.platform in ("linux", "android"):
                expected_patterns = ("_ZTIN9ffmpegkit*;", "_ZTSN9ffmpegkit*;", "_ZTVN9ffmpegkit*;",
                                     "_ZTIN4Json*;", "_ZTSN4Json*;", "_ZTVN4Json*;")
                if any(pattern not in control for pattern in expected_patterns) or "typeinfo*for*" in control or "vtable*for*" in control:
                    report["errors"].append("ELF export map lacks narrow raw namespace RTTI patterns")
        if args.ffmpeg_config:
            config = args.ffmpeg_config.read_text()
            feature_flags = dict(re.findall(r"^#define (CONFIG_[A-Z0-9_]+) ([01])$", config, re.M))
            report["ffmpeg_config"] = {"path": str(args.ffmpeg_config), "sha256": hashlib.sha256(config.encode()).hexdigest(),
                                       "gpl": bool(re.search(r"^#define CONFIG_GPL 1$", config, re.M)),
                                       "nonfree": bool(re.search(r"^#define CONFIG_NONFREE 1$", config, re.M)),
                                       "enabled_features": sorted(name for name, value in feature_flags.items() if value == "1"),
                                       "disabled_features": sorted(name for name, value in feature_flags.items() if value == "0")}
            if not report["ffmpeg_config"]["gpl"] or report["ffmpeg_config"]["nonfree"]:
                if args.require_acceptance_profile:
                    report["errors"].append("FFmpeg config is not GPL/nonfree-disabled")
        if args.cmake_cache:
            cache = args.cmake_cache.read_text()
            values = dict(re.findall(r"^([A-Za-z_][A-Za-z_0-9]*):[^=]*=(.*)$", cache, re.M))
            report["cmake_cache"] = {key: values.get(key) for key in
                ("CMAKE_BUILD_TYPE", "BUILD_TESTS", "BUILD_SHARED_LIBS", "FFMPEG_KIT_BUNDLE_TYPE",
                 "CMAKE_INSTALL_PREFIX", "FFMPEGKIT_VERIFY_BINARY_EXPORTS", "FFMPEGKIT_VERIFY_FULL_GPL_ACCEPTANCE")}
            if args.require_acceptance_profile and (values.get("BUILD_TESTS") != "OFF" or
                    values.get("FFMPEGKIT_VERIFY_BINARY_EXPORTS") != "ON" or
                    (args.platform != "wasm" and values.get("BUILD_SHARED_LIBS") != "ON")):
                report["errors"].append("CMake cache does not reflect an accepted production export-verification build")
        if args.bundle_manifest:
            if args.bundle_manifest.is_file():
                report["bundled_shared_dependencies"] = [line.strip() for line in args.bundle_manifest.read_text().splitlines() if line.strip()]
            else:
                report["bundled_shared_dependencies"] = []
            report["bundle_manifest_path"] = str(args.bundle_manifest)
            report["bundle_manifest_exists"] = args.bundle_manifest.is_file()
        report["source_commit"] = run([tool("git"), "rev-parse", "HEAD"]).strip()
        if args.require_acceptance_profile and (args.bundle != "full" or args.license != "gpl" or args.size != "not-small"):
            report["errors"].append("acceptance profile is not full/gpl/not-small")
    except (VerificationError, ValueError, KeyError, OSError, UnicodeError) as exc:
        report["errors"].append(str(exc))
    report["pass"] = not report["errors"]
    if exports:
        report["raw_exports_path"] = str(args.report.with_suffix(".exports.txt"))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    if exports:
        args.report.with_suffix(".exports.txt").write_text("\n".join(sorted(exports)) + "\n")
    for error in report["errors"]:
        print(f"FAIL: {error}", file=sys.stderr)
    print(f"{'PASS' if report['pass'] else 'FAIL'}: {args.platform}/{args.arch}: {report.get('export_count', 0)} exports; {args.report}")
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
