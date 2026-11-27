"""Fail-closed release packaging, CPU witnesses and CI-only version preparation."""

import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import tarfile
import tempfile
import time
import zipfile


REPOSITORY = os.environ.get("VPRO_REPOSITORY", "Boostao/vpro")
LEGACY_REPOSITORIES = frozenset({"Boostao/vpro_wails", "boostao/vpro_wails"})
ARCHES = ("amd64", "arm64")
R_SDK_GROUP = "r-sdk"
R_SDK_ASSET = "vpro-r-sdk.tar.gz"
VPRO64_BRIDGE_GROUP = "vpro64-bridge"
VPRO64_BRIDGE_ASSET = "vpro64-sqlite-bridge.zip"
VPRO64_BRIDGE_ENTRIES = (
    "Install-VPro64Bridge.ps1",
    "README.txt",
    "V7mdlImportSQLite.bas",
)
DESKTOP_GROUPS = ("windows-amd64", "windows-arm64", "macos-universal",
                  "linux-amd64", "linux-arm64")
GROUPS = (*DESKTOP_GROUPS, R_SDK_GROUP, VPRO64_BRIDGE_GROUP)
DESKTOP_ASSETS = {
    **{f"windows-{arch}": tuple(f"vpro-windows-{arch}{suffix}"
                              for suffix in (".exe", ".zip", "-installer.exe"))
       for arch in ARCHES},
    "macos-universal": ("vpro-macos-universal.dmg", "vpro-macos-universal.zip"),
    **{f"linux-{arch}": tuple(f"vpro-linux-{arch}{suffix}"
                            for suffix in (".deb", ".rpm", ".tar.gz"))
       for arch in ARCHES},
}
ASSETS = {
    **DESKTOP_ASSETS,
    R_SDK_GROUP: (R_SDK_ASSET,),
    VPRO64_BRIDGE_GROUP: (VPRO64_BRIDGE_ASSET,),
}
DESKTOP_REQUIRED = frozenset(name for names in DESKTOP_ASSETS.values() for name in names)
REQUIRED = DESKTOP_REQUIRED | {R_SDK_ASSET, VPRO64_BRIDGE_ASSET}
SCOPES = ("full", "r-only")
MANIFEST = "SHA256SUMS.txt"
RELEASE_MANIFEST = "release-manifest.json"
DEV_TAG_PREFIX = "dev-"
DEV_MAX_BUILDS = 5
DEV_BUILD_METADATA = "dev-build.json"
DEV_MANIFEST = "dev-manifest.json"
DEV_GROUPS = ("windows-amd64", "linux-amd64", VPRO64_BRIDGE_GROUP)
DEV_ASSETS = {
    "windows-amd64": ("vpro-windows-amd64-installer.exe",),
    "linux-amd64": ("vpro-linux-amd64.deb", "vpro-linux-amd64.rpm"),
    VPRO64_BRIDGE_GROUP: (VPRO64_BRIDGE_ASSET,),
}
DEV_OPTIONAL_ASSETS = ("vpro-macos-universal.dmg",)
DEV_CORE_REQUIRED = frozenset({
    "vpro-windows-amd64-installer.exe",
    "vpro-linux-amd64.deb",
    "vpro-linux-amd64.rpm",
})
DEV_REQUIRED = frozenset(name for names in DEV_ASSETS.values() for name in names)
DEV_ALLOWED_ASSETS = DEV_REQUIRED | frozenset(DEV_OPTIONAL_ASSETS) | {MANIFEST}
DEV_APP_TRIGGER_PREFIXES = ("app/", "docs-src/", "scripts/vpro64/")
DEV_APP_TRIGGER_FILES = frozenset({
    "scripts/release.py",
    "scripts/release-windows.ps1",
    ".github/workflows/dev-builds.yml",
})
DEFAULT_STANDARDS = {
    "becVersion": "BECdb v13 (2026-05-28)",
    "taxonomyVersion": "BCPlantTaxonomy v19 (2026-02-09)",
    "lmh25Edition": "LMH25 (2023)",
}
METADATA = ("app/build/config.yml", "app/build/windows/info.json",
            "app/build/windows/nsis/wails_tools.nsh", "app/build/darwin/Info.plist",
            "app/build/linux/nfpm/nfpm.yaml")
R_METADATA = ("r/DESCRIPTION",)
WINDOWS_TOOLCHAINS = {
    # DuckDB's supported amd64 prebuilt archives require GNU libstdc++/pthread.
    "amd64": {
        "name": "gcc-16.2.0-ucrt",
        "url": "https://github.com/brechtsanders/winlibs_mingw/releases/download/"
               "16.2.0posix-23.1.3-14.0.0-ucrt-r3/"
               "winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r3.zip",
        "sha256": "3c69305081e4a647144339a936244fcf7d3d9e558319e1ad7be2cd2886d4b6a1",
        "directory": "mingw64",
        "cc": "gcc.exe",
        "cxx": "g++.exe",
    },
    "arm64": {
        "name": "llvm-mingw-20261104-ucrt-x86_64",
        "url": "https://github.com/mstorsjo/llvm-mingw/releases/download/20261104/"
               "llvm-mingw-20261104-ucrt-x86_64.zip",
        "sha256": "552191b5754c49a5a20723276a6fc56541ea1922c4c50b7b669022333fc1b40f",
        "directory": "llvm-mingw-20261104-ucrt-x86_64",
        "cc": "aarch64-w64-mingw32-clang.exe",
        "cxx": "aarch64-w64-mingw32-clang++.exe",
    },
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def windows_toolchain(arch):
    require(arch in WINDOWS_TOOLCHAINS, f"Unsupported Windows cgo target: {arch}")
    return dict(WINDOWS_TOOLCHAINS[arch])


def version(raw):
    require(isinstance(raw, str) and len(raw) <= 128, "Invalid release version")
    match = re.fullmatch(
        r"v?((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))"
        r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
        r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?", raw, re.ASCII)
    require(match is not None, "Expected SemVer, optionally prefixed with v")
    require(all(int(part) <= 65535 for part in match.groups()[1:4]),
            "Version components exceed the NSIS 16-bit limit")
    if match[5]:
        require(all(not part.isdigit() or part == "0" or not part.startswith("0")
                    for part in match[5].split(".")),
                "Numeric prerelease identifiers must not have leading zeroes")
    return raw.removeprefix("v"), match[1]


def release_scope(scope=None):
    resolved = (scope or os.environ.get("RELEASE_SCOPE") or "full").strip()
    require(resolved in SCOPES, f"Unsupported release scope: {resolved!r}")
    return resolved


def release_version(scope=None):
    raw = os.environ["RELEASE_VERSION"]
    resolved_scope = release_scope(scope)
    if resolved_scope == "r-only" and isinstance(raw, str) and raw.startswith("r-"):
        raw = raw.removeprefix("r-")
    return version(raw)


def infer_build_mode(full_version, *, prerelease=False):
    normalized, _ = version(full_version)
    core = normalized.split("+", 1)[0]
    if prerelease or "-" in core:
        return "alpha"
    return "release"


def validate_source_tag(output, tag, commit):
    require(re.fullmatch(r"[0-9a-f]{40}", commit) is not None,
            "Expected the exact GitHub checkout commit")
    name = f"refs/tags/{tag}"
    refs = {}
    for line in output.splitlines():
        fields = line.split("\t")
        require(len(fields) == 2 and re.fullmatch(r"[0-9a-f]{40}", fields[0]) is not None,
                "Malformed remote tag response")
        digest, ref = fields
        require(ref in (name, name + "^{}") and ref not in refs,
                "Unexpected or duplicate remote tag reference")
        refs[ref] = digest
    if not refs:
        return "absent"
    require(name in refs, "Annotated tag has no direct reference")
    require(refs.get(name + "^{}", refs[name]) == commit,
            "Existing release tag points to different source than the built checkout")
    return "matching"


def check_source_tag(scope=None):
    resolved_scope = release_scope(scope)
    full, _ = release_version(resolved_scope)
    tag = f"r-v{full}" if resolved_scope == "r-only" else f"v{full}"
    require(os.environ["RELEASE_TAG"] == tag, "Release tag differs from validated version")
    result = subprocess.run(
        ["git", "ls-remote", "--tags", "origin", f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}"],
        check=True, capture_output=True, text=True)
    print("Release source tag:", validate_source_tag(result.stdout, tag, os.environ["GITHUB_SHA"]))


def replace_once(text, pattern, replacement):
    result, count = re.subn(pattern, lambda _: replacement, text, flags=re.MULTILINE)
    require(count == 1, f"Expected one metadata field matching {pattern!r}, got {count}")
    return result


def prepare_metadata(root, *, target="app", scope=None):
    require(os.environ.get("GITHUB_ACTIONS") == "true" and
            os.environ.get("CI") == "true", "Metadata preparation is CI-only")
    require(root.resolve() == Path(os.environ["GITHUB_WORKSPACE"]).resolve(),
            "Metadata preparation must use the fresh Actions checkout")
    require(target in ("app", "r", "all"), f"Unsupported metadata target: {target!r}")
    full, numeric = release_version(scope)
    tracked = ()
    if target in ("app", "all"):
        tracked += METADATA
    if target in ("r", "all"):
        tracked += R_METADATA
    run("git", "diff", "--exit-code", "HEAD", "--", *tracked, cwd=root)
    changes = {}
    if target in ("app", "all"):
        for relative, pattern, replacement in (
            ("app/build/config.yml", r'^  version: "[^"]*" .*$', f'  version: "{numeric}" # CI release version'),
            ("app/build/linux/nfpm/nfpm.yaml", r'^version: "[^"]*"$', f'version: "{full}"'),
            ("app/build/windows/nsis/wails_tools.nsh",
             r'^    !define INFO_PRODUCTVERSION "[^"]*"$',
             f'    !define INFO_PRODUCTVERSION "{numeric}"'),
        ):
            path = root / relative
            changes[path] = replace_once(path.read_text(encoding="utf-8"), pattern, replacement)
        path = root / "app/build/windows/info.json"
        info = json.loads(path.read_text(encoding="utf-8"))
        require("file_version" in info["fixed"] and "ProductVersion" in info["info"]["0409"],
                "Missing Windows version metadata")
        info["fixed"]["file_version"] = numeric
        info["fixed"]["product_version"] = numeric
        info["info"]["0409"]["ProductVersion"] = full
        info["info"]["0409"]["FileVersion"] = numeric
        changes[path] = json.dumps(info, ensure_ascii=False, indent=2) + "\n"
        path = root / "app/build/darwin/Info.plist"
        info = plistlib.loads(path.read_bytes(), fmt=plistlib.FMT_XML)
        for key in ("CFBundleVersion", "CFBundleShortVersionString"):
            require(key in info, f"Missing macOS metadata: {key}")
            info[key] = numeric
        changes[path] = plistlib.dumps(info, sort_keys=False).decode("utf-8")
    if target in ("r", "all"):
        desc_path = root / "r/DESCRIPTION"
        changes[desc_path] = replace_once(
            desc_path.read_text(encoding="utf-8"),
            r"^Version:\s*[^\r\n]+$",
            f"Version: {numeric}",
        )
    for path, content in changes.items():
        path.write_text(content, encoding="utf-8")


def run(*args, cwd=None):
    subprocess.run(args, cwd=cwd, check=True)


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


WINDOWS_SYSTEM_DLLS = frozenset({
    "advapi32.dll", "bcrypt.dll", "bcryptprimitives.dll", "cfgmgr32.dll",
    "comctl32.dll", "comdlg32.dll", "crypt32.dll", "d2d1.dll", "d3d11.dll",
    "dbghelp.dll", "dnsapi.dll", "dwmapi.dll", "dwrite.dll", "dxgi.dll",
    "gdi32.dll", "gdiplus.dll", "imm32.dll", "iphlpapi.dll", "kernel32.dll",
    "kernelbase.dll", "msimg32.dll", "msvcrt.dll", "ncrypt.dll", "netapi32.dll",
    "ntdll.dll", "ole32.dll", "oleaut32.dll", "opengl32.dll", "powrprof.dll",
    "profapi.dll", "psapi.dll", "rpcrt4.dll", "rstrtmgr.dll", "secur32.dll",
    "setupapi.dll", "shcore.dll", "shell32.dll", "shlwapi.dll", "ucrtbase.dll",
    "user32.dll", "userenv.dll", "uxtheme.dll", "version.dll", "winhttp.dll",
    "wininet.dll", "winmm.dll", "winspool.drv", "ws2_32.dll", "wsock32.dll",
    "wtsapi32.dll",
})


def is_windows_system_dll(name):
    lower = name.lower()
    if lower in WINDOWS_SYSTEM_DLLS:
        return True
    return lower.startswith(("api-ms-win-", "ext-ms-win-")) and lower.endswith(".dll")


def pe_imports(data, offset=None):
    if offset is None:
        require(data[:2] == b"MZ" and len(data) >= 64, "Invalid PE executable")
        offset = struct.unpack_from("<I", data, 60)[0]
    require(offset + 26 <= len(data) and data[offset:offset + 4] == b"PE\0\0",
            "Missing PE header")
    require(struct.unpack_from("<H", data, offset + 24)[0] == 0x20B,
            "Expected PE32+ application")
    num_sections, = struct.unpack_from("<H", data, offset + 6)
    opt_size, = struct.unpack_from("<H", data, offset + 20)
    opt_offset = offset + 24
    sec_offset = opt_offset + opt_size
    require(sec_offset + num_sections * 40 <= len(data), "Truncated PE section table")
    if opt_size == 0 and num_sections == 0:
        return []
    require(opt_size >= 112, "Truncated PE32+ optional header")
    num_rva_and_sizes, = struct.unpack_from("<I", data, opt_offset + 108)
    require(num_rva_and_sizes <= (opt_size - 112) // 8,
            "Truncated PE32+ data directories")
    sections = []
    for index in range(num_sections):
        vsize, vrva, rsize, roff = struct.unpack_from("<IIII", data, sec_offset + index * 40 + 8)
        require(rsize == 0 or roff + rsize <= len(data), "Truncated PE section data")
        sections.append((vsize, vrva, rsize, roff))

    def rva_to_offset(rva):
        for vsize, vrva, rsize, roff in sections:
            span = max(vsize, rsize)
            if vrva <= rva < vrva + span:
                delta = rva - vrva
                require(delta < rsize, f"PE RVA {rva:#x} points outside raw section data")
                return roff + delta
        raise ValueError(f"Unmapped PE RVA: {rva:#x}")

    def read_dll_name(rva):
        pos = rva_to_offset(rva)
        end = data.find(b"\x00", pos)
        require(end != -1 and 0 < end - pos <= 256, "Malformed PE import DLL name")
        try:
            name = data[pos:end].decode("ascii")
        except UnicodeDecodeError as exc:
            raise ValueError("Non-ASCII PE import DLL name") from exc
        require(all(32 < ord(ch) < 127 for ch in name),
                "Control or whitespace character in PE import DLL name")
        return name

    dlls = []
    if num_rva_and_sizes > 1:
        imp_rva, imp_size = struct.unpack_from("<II", data, opt_offset + 112 + 8)
        if imp_rva != 0 or imp_size != 0:
            require(imp_rva != 0 and imp_size >= 20, "Malformed PE import directory")
            pos = rva_to_offset(imp_rva)
            while True:
                require(pos + 20 <= len(data), "Truncated PE import descriptor table")
                descriptor = struct.unpack_from("<IIIII", data, pos)
                if descriptor == (0, 0, 0, 0, 0):
                    break
                name_rva = descriptor[3]
                require(name_rva != 0, "PE import descriptor missing DLL name RVA")
                dlls.append(read_dll_name(name_rva))
                pos += 20
    if num_rva_and_sizes > 13:
        delay_rva, delay_size = struct.unpack_from("<II", data, opt_offset + 112 + 13 * 8)
        if delay_rva != 0 or delay_size != 0:
            require(delay_rva != 0 and delay_size >= 32, "Malformed PE delay-import directory")
            pos = rva_to_offset(delay_rva)
            while True:
                require(pos + 32 <= len(data), "Truncated PE delay-import descriptor table")
                fields = struct.unpack_from("<IIIIIIII", data, pos)
                if fields == (0,) * 8:
                    break
                attrs, name_rva = fields[0], fields[1]
                require((attrs & 1) != 0 and name_rva != 0,
                        "Invalid PE delay-import descriptor")
                dlls.append(read_dll_name(name_rva))
                pos += 32
    return dlls


def validate_pe_imports(data, offset=None):
    dlls = pe_imports(data, offset)
    non_system = sorted({name for name in dlls if not is_windows_system_dll(name)},
                        key=str.lower)
    require(not non_system,
            f"Non-system Windows DLL dependency in PE imports: {', '.join(non_system)}")


def cpu(data, kind, arch):
    require(arch in (*ARCHES, "universal"), f"Unsupported CPU: {arch}")
    if kind == "pe":
        require(arch in ARCHES and data[:2] == b"MZ" and len(data) >= 64,
                "Invalid PE executable")
        offset = struct.unpack_from("<I", data, 60)[0]
        require(offset + 26 <= len(data) and data[offset:offset + 4] == b"PE\0\0",
                "Missing PE header")
        machine, = struct.unpack_from("<H", data, offset + 4)
        require(machine == {"amd64": 0x8664, "arm64": 0xAA64}[arch],
                f"PE CPU mismatch: {machine:#x}, expected {arch}")
        require(struct.unpack_from("<H", data, offset + 24)[0] == 0x20B,
                "Expected PE32+ application")
        validate_pe_imports(data, offset)
    elif kind == "elf":
        require(arch in ARCHES and len(data) >= 64 and
                data[:6] == b"\x7fELF\x02\x01", "Expected little-endian ELF64")
        require(struct.unpack_from("<H", data, 18)[0] ==
                {"amd64": 62, "arm64": 183}[arch], f"ELF CPU mismatch: expected {arch}")
    elif kind == "macho":
        require(arch == "universal" and len(data) >= 8, "Expected universal Mach-O")
        formats = {b"\xca\xfe\xba\xbe": (">", False),
                   b"\xca\xfe\xba\xbf": (">", True),
                   b"\xbe\xba\xfe\xca": ("<", False),
                   b"\xbf\xba\xfe\xca": ("<", True)}
        require(data[:4] in formats, "Expected fat Mach-O, not a host-only app")
        endian, wide = formats[data[:4]]
        count, = struct.unpack_from(endian + "I", data, 4)
        require(count == 2, "Universal app must have exactly two CPU slices")
        stride = 32 if wide else 20
        require(len(data) >= 8 + count * stride, "Truncated fat Mach-O table")
        found, ranges = set(), []
        for index in range(count):
            entry = 8 + index * stride
            machine, = struct.unpack_from(endian + "I", data, entry)
            offset, size = struct.unpack_from(endian + ("QQ" if wide else "II"),
                                             data, entry + 8)
            require(size >= 32 and offset >= 8 + count * stride and
                    offset + size <= len(data), "Invalid Mach-O slice bounds")
            require(data[offset:offset + 4] == b"\xcf\xfa\xed\xfe" and
                    struct.unpack_from("<I", data, offset + 4)[0] == machine,
                    "Fat CPU table does not match its Mach-O slice")
            require(machine not in found, "Duplicate Mach-O CPU slice")
            found.add(machine)
            ranges.append((offset, offset + size))
        require(found == {0x01000007, 0x0100000C}, "Missing x86_64/arm64 universal slices")
        ranges.sort()
        require(ranges[0][1] <= ranges[1][0], "Overlapping Mach-O slices")
    else:
        raise ValueError(f"Unsupported executable format: {kind}")


def check_cpu(path, kind, arch):
    cpu(path.read_bytes(), kind, arch)


def exact_files(directory, expected):
    require(directory.is_dir(), f"Missing artifact directory: {directory}")
    entries = list(directory.iterdir())
    require(all(path.is_file() and not path.is_symlink() and path.stat().st_size > 0
                for path in entries), "Artifacts must be nonempty regular files")
    actual = {path.name for path in entries}
    require(actual == set(expected),
            f"Artifact set mismatch: missing={sorted(set(expected) - actual)}, "
            f"unexpected={sorted(actual - set(expected))}")


def tar_payload(data, name):
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as archive:
        matches = [entry for entry in archive.getmembers()
                   if entry.name.removeprefix("./") == name]
        require(len(matches) == 1 and matches[0].isfile(), f"Missing/duplicate tar file: {name}")
        require(matches[0].size <= 512 * 1024 * 1024, "Tar payload exceeds release limit")
        return archive.extractfile(matches[0]).read()


def deb_members(data):
    require(data[:8] == b"!<arch>\n", "Invalid deb/ar archive")
    members = {}
    offset = 8
    while offset < len(data):
        header = data[offset:offset + 60]
        require(len(header) == 60 and header[58:] == b"`\n", "Invalid ar member header")
        name = header[:16].decode("ascii").strip().removesuffix("/")
        size = int(header[48:58])
        start = offset + 60
        require(size >= 0 and start + size <= len(data) and name not in members,
                "Invalid/duplicate ar member")
        members[name] = data[start:start + size]
        offset = start + size + size % 2
    require(offset == len(data) and members.get("debian-binary") == b"2.0\n",
            "Invalid deb format version")
    return members


def validate_deb(path, arch, full_version):
    members = deb_members(path.read_bytes())
    control = [name for name in members if name.startswith("control.tar")]
    payload = [name for name in members if name.startswith("data.tar")]
    require(len(control) == len(payload) == 1, "Missing/duplicate deb control or data")
    text = tar_payload(members[control[0]], "control").decode("utf-8")
    # nFPM maps the SemVer prerelease separator to Debian's sorting separator.
    deb_version = full_version.replace("-", "~", 1) if "-" in full_version.split("+")[0] else full_version
    for key, expected in (("Architecture", arch),
                          ("Version", deb_version + "-1"), ("Package", "vpro")):
        values = re.findall(rf"^{key}: (.+)$", text, flags=re.MULTILINE)
        require(values == [expected], f"deb {key} mismatch: {values}, expected {expected}")
    cpu(tar_payload(members[payload[0]], "usr/bin/VPro"), "elf", arch)


RPM_HEADER_MAGIC = b"\x8e\xad\xe8\x01\x00\x00\x00\x00"


def rpm_version(full_version):
    core_and_pre, *meta = full_version.split("+", 1)
    if "-" in core_and_pre:
        core, pre = core_and_pre.split("-", 1)
        pre_norm = pre.replace("-", "_")
        core_and_pre = f"{core}~{pre_norm}"
    return f"{core_and_pre}+{meta[0]}" if meta else core_and_pre


def _rpm_header_strings(data, offset):
    if offset + 16 > len(data) or data[offset:offset + 8] != RPM_HEADER_MAGIC:
        return None, None, None
    nindex, hsize = struct.unpack_from(">II", data, offset + 8)
    require(nindex <= 4096 and hsize <= 16 * 1024 * 1024, "Oversized RPM header")
    store_start = offset + 16 + nindex * 16
    store_end = store_start + hsize
    require(store_end <= len(data), "Truncated RPM header")
    strings = {}
    for index in range(nindex):
        tag, kind, val_offset, _ = struct.unpack_from(">IIII", data, offset + 16 + index * 16)
        if kind == 6:  # RPM_STRING_TYPE
            require(val_offset < hsize, "Out-of-bounds RPM header string")
            end = data.find(b"\x00", store_start + val_offset, store_end)
            require(end != -1, "Unterminated RPM header string")
            strings[tag] = data[store_start + val_offset:end].decode("utf-8", errors="strict")
    next_aligned = store_start + ((hsize + 7) & ~7)
    return strings, next_aligned, store_end


def validate_rpm(path, arch, full_version):
    require(arch in ARCHES, f"Unsupported RPM CPU: {arch}")
    data = path.read_bytes()
    require(len(data) > 96 and data[:4] == b"\xed\xab\xee\xdb",
            f"Expected RPM package: {path}")
    require(b"\x00" in data[10:76],
            f"Unterminated 66-byte RPM lead name: {path}")
    require(b"\x8e\xad\xe8\x01" in data[96:1024],
            f"Missing RPM header magic: {path}")
    lead_name = data[10:76].split(b"\x00", 1)[0].decode("utf-8", errors="replace")
    rpm_arch = "x86_64" if arch == "amd64" else "aarch64"
    rpm_ver = rpm_version(full_version)
    expected_prefix = f"vpro-{rpm_ver}-1"
    lead_prefix = expected_prefix[:65]
    require(lead_name.startswith(lead_prefix),
            f"rpm lead name mismatch: {lead_name!r}, expected prefix {lead_prefix!r}")

    sig_strings, next_aligned, store_end = _rpm_header_strings(data, 96)
    meta_strings = None
    for candidate in (next_aligned, store_end):
        if candidate is not None:
            meta_strings, _, _ = _rpm_header_strings(data, candidate)
            if meta_strings is not None:
                break
    header_tags = meta_strings or sig_strings or {}

    if 1000 in header_tags:
        require(header_tags[1000] == "vpro",
                f"rpm header Package mismatch: {header_tags[1000]!r}, expected 'vpro'")
    if 1001 in header_tags:
        require(header_tags[1001] == rpm_ver,
                f"rpm header Version mismatch: {header_tags[1001]!r}, expected {rpm_ver!r}")
    if 1002 in header_tags:
        require(header_tags[1002] == "1",
                f"rpm header Release mismatch: {header_tags[1002]!r}, expected '1'")
    if 1014 in header_tags:
        require(header_tags[1014] == "Apache-2.0",
                f"rpm header License mismatch: {header_tags[1014]!r}, expected 'Apache-2.0'")
    if 1022 in header_tags:
        require(header_tags[1022] == rpm_arch,
                f"rpm header arch mismatch: {header_tags[1022]!r}, expected {rpm_arch!r}")

    # nFPM/rpmpack writes 'vpro-<ver>-1' without '.<arch>' in the 66-byte C char name[66]
    # lead (storing arch in RPMTAG_ARCH=1022), whereas rpmbuild appends '.<arch>' up to
    # the 65-char NUL-terminated lead limit.
    if lead_name == lead_prefix and 1022 in header_tags:
        return
    if len(expected_prefix) + 1 + len(rpm_arch) <= 65:
        require(lead_name == f"{expected_prefix}.{rpm_arch}",
                f"rpm lead arch mismatch: {lead_name!r}, expected .{rpm_arch}")
    else:
        expected_truncated = f"{expected_prefix}.{rpm_arch}"[:65]
        require(lead_name == expected_truncated,
                f"rpm lead arch mismatch: {lead_name!r}, expected {expected_truncated!r}")


def check_bundle(bundle, numeric):
    check_cpu(bundle / "Contents/MacOS/VPro", "macho", "universal")
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    require(info["CFBundleVersion"] == info["CFBundleShortVersionString"] == numeric,
            "macOS bundle version mismatch")


def validate_r_sdk(path, full):
    _, numeric = version(full)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size > 0,
            f"Missing or empty R SDK tarball: {path}")
    with tarfile.open(path, "r:gz") as archive:
        members = {m.name: m for m in archive.getmembers()}
        require("vpro/DESCRIPTION" in members and members["vpro/DESCRIPTION"].isfile(),
                "R SDK tarball is missing vpro/DESCRIPTION")
        extracted = archive.extractfile(members["vpro/DESCRIPTION"])
        require(extracted is not None, "Unable to read vpro/DESCRIPTION from R SDK tarball")
        desc = extracted.read().decode("utf-8")
    require(re.search(r"^Package:\s*vpro\s*$", desc, re.MULTILINE) is not None,
            "R SDK tarball DESCRIPTION has unexpected Package name")
    require(re.search(rf"^Version:\s*{re.escape(numeric)}\s*$", desc, re.MULTILINE) is not None,
            f"R SDK tarball DESCRIPTION Version does not match {numeric}")


def validate_vpro64_bridge(path):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size > 0,
            f"Missing or empty VPro64 bridge archive: {path}")
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(sorted(names) == list(VPRO64_BRIDGE_ENTRIES) and len(names) == len(VPRO64_BRIDGE_ENTRIES),
                f"Unexpected VPro64 bridge ZIP entries: {names!r}")
        bas_bytes = archive.read("V7mdlImportSQLite.bas")
        ps1_bytes = archive.read("Install-VPro64Bridge.ps1")
        readme_bytes = archive.read("README.txt")
    require(len(bas_bytes) > 0 and b"\r\n" in bas_bytes and b"ImportSQLiteProject" in bas_bytes,
            "VPro64 bridge archive V7mdlImportSQLite.bas must be CRLF-formatted and expose ImportSQLiteProject")
    require(len(ps1_bytes) > 0 and b"V7mdlImportSQLite.bas" in ps1_bytes,
            "VPro64 bridge archive Install-VPro64Bridge.ps1 is invalid")
    require(len(readme_bytes) > 0 and b"V7mdlImportSQLite.bas" in readme_bytes,
            "VPro64 bridge archive README.txt is invalid")


def build_vpro64_bridge_zip(root, dest_zip):
    src_dir = root / "scripts/vpro64"
    for entry in VPRO64_BRIDGE_ENTRIES:
        src_file = src_dir / entry
        require(src_file.is_file() and not src_file.is_symlink() and src_file.stat().st_size > 0,
                f"Missing required VPro64 bridge source file: {src_file}")
    # Enforce byte-for-byte parity with Desktop embedded resources when present.
    embedded_dir = root / "app/resources/vpro64"
    for mirrored in ("V7mdlImportSQLite.bas", "README.txt"):
        embedded_file = embedded_dir / mirrored
        if embedded_file.is_file():
            require(embedded_file.read_bytes() == (src_dir / mirrored).read_bytes(),
                    f"Embedded {embedded_file} drifted from {src_dir / mirrored}")
    with zipfile.ZipFile(dest_zip, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for entry in VPRO64_BRIDGE_ENTRIES:
            info = zipfile.ZipInfo(entry, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, (src_dir / entry).read_bytes())
    validate_vpro64_bridge(dest_zip)


def unique_output(app_root, suffix):
    paths = list((app_root / "bin").glob(f"*{suffix}"))
    require(len(paths) == 1 and paths[0].is_file() and not paths[0].is_symlink(),
            f"Expected exactly one app/bin/*{suffix}, found {len(paths)}")
    return paths[0]


def expected_architectures(group):
    if group == R_SDK_GROUP:
        return ["source"]
    if group == VPRO64_BRIDGE_GROUP:
        return ["windows"]
    if group == "macos-universal":
        return list(ARCHES)
    return [group.split("-")[1]]


def active_release_set(scope=None):
    resolved_scope = release_scope(scope)
    if resolved_scope == "r-only":
        return (R_SDK_GROUP,), frozenset({R_SDK_ASSET})
    return GROUPS, REQUIRED


def package(root, platform, *, scope=None):
    full, numeric = release_version(scope)
    if platform == "vpro64":
        group = VPRO64_BRIDGE_GROUP
        destination = root / "scripts/vpro64/dist-artifacts"
        destination.mkdir(parents=True)
        build_vpro64_bridge_zip(root, destination / VPRO64_BRIDGE_ASSET)
        exact_files(destination, ASSETS[group])
        validate_portable(destination, group, full)
        witness = {
            "schema": 1, "group": group, "version": full, "commit": os.environ["GITHUB_SHA"],
            "architectures": expected_architectures(group),
            "sha256": {VPRO64_BRIDGE_ASSET: sha256(destination / VPRO64_BRIDGE_ASSET)},
        }
        (destination / f"release-witness-{group}.json").write_text(
            json.dumps(witness, sort_keys=True) + "\n", encoding="utf-8")
        return
    if platform == "r":
        group = R_SDK_GROUP
        r_root = root / "r"
        destination = r_root / "dist-artifacts"
        destination.mkdir(parents=True)
        candidates = [
            p for search_dir in (r_root, root)
            if search_dir.is_dir()
            for p in search_dir.glob(f"vpro_{numeric}.tar.gz")
            if p.is_file() and not p.is_symlink()
        ]
        unique_candidates = list(dict.fromkeys(p.resolve() for p in candidates))
        require(len(unique_candidates) == 1,
                f"Expected exactly one built vpro_{numeric}.tar.gz, found {len(unique_candidates)}")
        validate_r_sdk(unique_candidates[0], full)
        shutil.copyfile(unique_candidates[0], destination / R_SDK_ASSET)
        exact_files(destination, ASSETS[group])
        validate_portable(destination, group, full)
        witness = {
            "schema": 1, "group": group, "version": full, "commit": os.environ["GITHUB_SHA"],
            "architectures": expected_architectures(group),
            "sha256": {R_SDK_ASSET: sha256(destination / R_SDK_ASSET)},
        }
        (destination / f"release-witness-{group}.json").write_text(
            json.dumps(witness, sort_keys=True) + "\n", encoding="utf-8")
        return

    arch = "universal" if platform == "macos" else os.environ["RELEASE_ARCH"]
    group = f"{platform}-{arch}"
    require(group in DESKTOP_ASSETS, f"Unsupported release target: {group}")
    app_root = root / "app"
    destination = app_root / "dist-artifacts"
    destination.mkdir(parents=True)  # Refuse stale outputs from a previous attempt.
    binary = app_root / "bin/VPro"
    if platform == "windows":
        binary = binary.with_suffix(".exe")
        check_cpu(binary, "pe", arch)
        installer = app_root / f"bin/VPro-{arch}-installer.exe"
        require(installer.is_file(), f"Missing exact NSIS output: {installer}")
        # NSIS has an x86 launcher even for ARM64; inspect the installed payload.
        with tempfile.TemporaryDirectory() as temporary:
            run("7z", "x", "-y", str(installer), f"-o{temporary}")
            payloads = list(Path(temporary).rglob("VPro.exe"))
            require(len(payloads) == 1, "Missing/ambiguous NSIS application payload")
            check_cpu(payloads[0], "pe", arch)
            require(sha256(payloads[0]) == sha256(binary), "NSIS payload differs from built EXE")
        shutil.copyfile(binary, destination / ASSETS[group][0])
        with zipfile.ZipFile(destination / ASSETS[group][1], "w", zipfile.ZIP_DEFLATED) as archive:
            archive.write(binary, "VPro.exe")
        shutil.copyfile(installer, destination / ASSETS[group][2])
    elif platform == "linux":
        check_cpu(binary, "elf", arch)
        deb = unique_output(app_root, ".deb")
        validate_deb(deb, arch, full)
        rpm = unique_output(app_root, ".rpm")
        validate_rpm(rpm, arch, full)
        shutil.copyfile(deb, destination / ASSETS[group][0])
        shutil.copyfile(rpm, destination / ASSETS[group][1])
        with tarfile.open(destination / ASSETS[group][2], "w:gz") as archive:
            archive.add(binary, arcname="VPro")
    else:
        bundle = app_root / "bin/VPro.app"
        check_bundle(bundle, numeric)
        dmg = app_root / "bin/VPro.dmg"
        require(dmg.is_file(), "Missing exact DMG output")
        with tempfile.TemporaryDirectory() as temporary:
            mount = Path(temporary) / "mount"
            mount.mkdir()
            run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(dmg))
            try:
                check_bundle(mount / "VPro.app", numeric)
                require(sha256(mount / "VPro.app/Contents/MacOS/VPro") ==
                        sha256(bundle / "Contents/MacOS/VPro"), "DMG payload differs")
            finally:
                run("hdiutil", "detach", str(mount))
        shutil.copyfile(dmg, destination / ASSETS[group][0])
        run("ditto", "-c", "-k", "--keepParent", str(bundle), str(destination / ASSETS[group][1]))
    exact_files(destination, ASSETS[group])
    validate_portable(destination, group, full)
    witness = {
        "schema": 1, "group": group, "version": full, "commit": os.environ["GITHUB_SHA"],
        "architectures": expected_architectures(group),
        "sha256": {name: sha256(destination / name) for name in ASSETS[group]},
    }
    (destination / f"release-witness-{group}.json").write_text(
        json.dumps(witness, sort_keys=True) + "\n", encoding="utf-8")


def validate_portable(directory, group, full):
    if group == R_SDK_GROUP:
        validate_r_sdk(directory / R_SDK_ASSET, full)
    elif group == VPRO64_BRIDGE_GROUP:
        validate_vpro64_bridge(directory / VPRO64_BRIDGE_ASSET)
    elif group.startswith("windows-"):
        arch = group.removeprefix("windows-")
        binary = (directory / ASSETS[group][0]).read_bytes()
        cpu(binary, "pe", arch)
        with zipfile.ZipFile(directory / ASSETS[group][1]) as archive:
            require(archive.namelist() == ["VPro.exe"], "Unexpected Windows ZIP entries")
            require(archive.read("VPro.exe") == binary, "Windows ZIP payload differs")
    elif group.startswith("linux-"):
        arch = group.removeprefix("linux-")
        validate_deb(directory / ASSETS[group][0], arch, full)
        validate_rpm(directory / ASSETS[group][1], arch, full)
        cpu(tar_payload((directory / ASSETS[group][2]).read_bytes(), "VPro"), "elf", arch)
    else:
        with zipfile.ZipFile(directory / ASSETS[group][1]) as archive:
            names = archive.namelist()
            executable = "VPro.app/Contents/MacOS/VPro"
            info_path = "VPro.app/Contents/Info.plist"
            require(names.count(executable) == names.count(info_path) == 1,
                    "Missing/duplicate macOS ZIP bundle entries")
            cpu(archive.read(executable), "macho", "universal")
            info = plistlib.loads(archive.read(info_path))
            numeric = version(full)[1]
            require(info["CFBundleVersion"] == info["CFBundleShortVersionString"] == numeric,
                    "macOS ZIP version mismatch")


def manifest(directory, *, scope=None):
    full, _ = release_version(scope)
    active_groups, active_required = active_release_set(scope)
    witnesses = {f"release-witness-{group}.json" for group in active_groups}
    exact_files(directory, active_required | witnesses)
    for group in active_groups:
        witness = json.loads((directory / f"release-witness-{group}.json").read_text(encoding="utf-8"))
        expected = {
            "schema": 1, "group": group, "version": full, "commit": os.environ["GITHUB_SHA"],
            "architectures": expected_architectures(group),
            "sha256": {name: sha256(directory / name) for name in ASSETS[group]},
        }
        require(witness == expected, f"Invalid provenance/CPU witness: {group}")
        validate_portable(directory, group, full)
    content = "".join(f"{sha256(directory / name)}  {name}\n" for name in sorted(active_required))
    (directory / MANIFEST).write_text(content, encoding="ascii", newline="\n")
    Path("release-assets.txt").write_text(
        "".join(f"{directory / name}\n" for name in sorted(active_required | {MANIFEST})),
        encoding="utf-8", newline="\n")


def parse_manifest(content, *, expected_names=REQUIRED):
    lines = content.splitlines()
    require(len(lines) == len(expected_names), "Checksum manifest has the wrong number of entries")
    entries = {}
    for line in lines:
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9._-]+)", line)
        require(match is not None, "Malformed checksum manifest line")
        digest, name = match.groups()
        require(name in expected_names and name not in entries, "Unexpected/duplicate checksum entry")
        entries[name] = digest
    require(set(entries) == expected_names, "Incomplete checksum manifest")
    return entries


def verify(directory, trusted_manifest, *, release_manifest_path=None, scope=None):
    _, active_required = active_release_set(scope)
    content = trusted_manifest.read_text(encoding="ascii")
    expected = parse_manifest(content, expected_names=active_required)
    expected_set = active_required | {MANIFEST}
    if release_manifest_path is not None:
        expected_set = expected_set | {RELEASE_MANIFEST}
    exact_files(directory, expected_set)
    require((directory / MANIFEST).read_bytes() == trusted_manifest.read_bytes(),
            "Downloaded checksum manifest differs from validated manifest")
    for name, digest in expected.items():
        require(sha256(directory / name) == digest, f"SHA256 mismatch: {name}")
    if release_manifest_path is not None:
        trusted_bytes = release_manifest_path.read_bytes()
        require((directory / RELEASE_MANIFEST).read_bytes() == trusted_bytes,
                "Downloaded release-manifest.json differs from validated manifest")
        validate_release_manifest(json.loads(trusted_bytes.decode("utf-8")))


def remote(path, *, require_release_manifest=False, scope=None):
    _, active_required = active_release_set(scope)
    assets = json.loads(path.read_text(encoding="utf-8"))["assets"]
    names = [asset["name"] for asset in assets]
    require(len(names) == len(set(names)), "Remote release has duplicate asset names")
    base_expected = active_required | {MANIFEST}
    with_portal_manifest = base_expected | {RELEASE_MANIFEST}
    if require_release_manifest:
        require(set(names) == with_portal_manifest,
                "Remote release is missing release-manifest.json or has unexpected assets")
    else:
        require(set(names) in (base_expected, with_portal_manifest),
                "Remote release has missing, duplicate or unexpected assets")


def standards_metadata(root=None):
    base = (root or Path(__file__).resolve().parents[1]) / "app/resources/standards-2026-provenance.json"
    standards = dict(DEFAULT_STANDARDS)
    if base.is_file():
        provenance = json.loads(base.read_text(encoding="utf-8"))
        for source in provenance.get("sources", ()):
            label = source.get("version", "")
            if label.startswith("BECdb_v13_2026"):
                date_suffix = label.split("(", 1)[1].rstrip(")") if "(" in label else "2026"
                standards["becVersion"] = f"BECdb v13 ({date_suffix})"
            elif label.startswith("BCPlantTaxa_v19"):
                date_suffix = label.split("(", 1)[1].rstrip(")") if "(" in label else "2026"
                standards["taxonomyVersion"] = f"BCPlantTaxonomy v19 ({date_suffix})"
    return standards


def normalize_legacy_manifest(doc, repository=REPOSITORY):
    if not isinstance(doc, dict):
        return doc
    raw_repo = doc.get("repository")
    if not isinstance(raw_repo, str) or raw_repo not in LEGACY_REPOSITORIES:
        return doc
    legacy_prefixes = tuple(f"https://github.com/{legacy}/releases/download/"
                            for legacy in LEGACY_REPOSITORIES)
    canonical_prefix = f"https://github.com/{repository}/releases/download/"

    def rewrite_url(value):
        if not isinstance(value, str):
            return value
        for prefix in legacy_prefixes:
            if value.startswith(prefix):
                return canonical_prefix + value[len(prefix):]
        return value

    normalized = dict(doc)
    normalized["repository"] = repository
    channels = doc.get("channels")
    if isinstance(channels, dict):
        new_channels = {}
        for ch_name, entry in channels.items():
            if isinstance(entry, dict):
                ch_copy = dict(entry)
                if "sha256sumsUrl" in ch_copy:
                    ch_copy["sha256sumsUrl"] = rewrite_url(ch_copy["sha256sumsUrl"])
                if isinstance(ch_copy.get("assets"), list):
                    new_assets = []
                    for asset in ch_copy["assets"]:
                        if isinstance(asset, dict):
                            a_copy = dict(asset)
                            if "url" in a_copy:
                                a_copy["url"] = rewrite_url(a_copy["url"])
                            new_assets.append(a_copy)
                        else:
                            new_assets.append(asset)
                    ch_copy["assets"] = new_assets
                new_channels[ch_name] = ch_copy
            else:
                new_channels[ch_name] = entry
        normalized["channels"] = new_channels
    return normalized


def validate_download_url(url, name, tag, repository=REPOSITORY):
    require(isinstance(url, str) and "?" not in url and "#" not in url,
            f"Invalid download URL for {name}")
    expected = f"https://github.com/{repository}/releases/download/{tag}/{name}"
    require(url == expected, f"Unexpected download URL for {name}: {url} != {expected}")
    return url


def validate_channel_entry(entry, channel_name, repository=REPOSITORY):
    require(isinstance(entry, dict), f"Channel {channel_name} must be an object or null")
    full_ver = entry.get("version")
    require(isinstance(full_ver, str), f"Channel {channel_name} is missing version")
    normalized, _ = version(full_ver)
    require(normalized == full_ver, f"Channel {channel_name} version must not carry leading v")
    tag = entry.get("tag")
    require(tag == f"v{full_ver}", f"Channel {channel_name} tag must match v{full_ver}")
    published_at = entry.get("publishedAt")
    require(isinstance(published_at, str) and re.fullmatch(
        r"\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)?", published_at) is not None,
        f"Channel {channel_name} has invalid ISO-8601 publishedAt")
    prerelease = entry.get("prerelease")
    expected_prerelease = channel_name == "preview"
    require(type(prerelease) is bool and prerelease is expected_prerelease,
            f"Channel {channel_name} prerelease must be {expected_prerelease}")
    require(type(entry.get("unsignedNotice")) is bool,
            f"Channel {channel_name} unsignedNotice must be boolean")
    validate_download_url(entry.get("sha256sumsUrl"), MANIFEST, tag, repository)
    standards = entry.get("standards")
    require(isinstance(standards, dict), f"Channel {channel_name} standards must be an object")
    for key in ("becVersion", "taxonomyVersion", "lmh25Edition"):
        require(isinstance(standards.get(key), str) and len(standards[key].strip()) > 0,
                f"Channel {channel_name} standards.{key} must be a non-empty string")
    assets = entry.get("assets")
    require(isinstance(assets, list) and len(assets) > 0,
            f"Channel {channel_name} assets must be a non-empty list")
    # Legacy desktop-only manifests contain DESKTOP_REQUIRED + SHA256SUMS.txt;
    # unified monorepo releases additionally attach vpro-r-sdk.tar.gz.
    allowed_names = REQUIRED | {MANIFEST}
    seen = set()
    for asset in assets:
        require(isinstance(asset, dict), f"Channel {channel_name} contains malformed asset")
        name = asset.get("name")
        require(isinstance(name, str) and name in allowed_names and name not in seen,
                f"Channel {channel_name} contains unexpected or duplicate asset: {name!r}")
        seen.add(name)
        validate_download_url(asset.get("url"), name, tag, repository)
        digest = asset.get("sha256")
        require(isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest) is not None,
                f"Channel {channel_name} asset {name} has invalid sha256")
        size_bytes = asset.get("sizeBytes")
        require(type(size_bytes) is int and size_bytes > 0,
                f"Channel {channel_name} asset {name} has invalid sizeBytes")
    require(DESKTOP_REQUIRED.issubset(seen),
            f"Channel {channel_name} is missing required desktop release assets")


def validate_release_manifest(doc, *, repository=REPOSITORY):
    require(isinstance(doc, dict), "Release manifest must be a JSON object")
    require(set(doc) == {"schemaVersion", "repository", "defaultChannel", "channels"},
            "Unexpected top-level keys in release-manifest.json")
    require(type(doc.get("schemaVersion")) is int and doc["schemaVersion"] == 1,
            "Unsupported release-manifest.json schemaVersion")
    require(doc.get("repository") == repository,
            f"Unexpected release-manifest.json repository: {doc.get('repository')!r}")
    require(doc.get("defaultChannel") in ("stable", "preview"),
            "defaultChannel must be 'stable' or 'preview'")
    channels = doc.get("channels")
    require(isinstance(channels, dict) and "stable" in channels and
            set(channels).issubset({"stable", "preview"}),
            "channels must contain 'stable' and optional 'preview' only")
    for channel_name in ("stable", "preview"):
        entry = channels.get(channel_name)
        if entry is not None:
            validate_channel_entry(entry, channel_name, doc["repository"])
    return doc


def release_manifest(directory, output, *, channel=None, published_at=None,
                     base_manifest=None, default_channel=None, root=None,
                     repository=REPOSITORY):
    full, _ = release_version("full")
    tag = f"v{full}"
    manifest_file = directory / MANIFEST
    require(manifest_file.is_file() and not manifest_file.is_symlink() and
            manifest_file.stat().st_size > 0, f"Missing validated {MANIFEST} in {directory}")
    expected_hashes = parse_manifest(manifest_file.read_text(encoding="ascii"),
                                     expected_names=REQUIRED)
    for name in REQUIRED:
        asset_path = directory / name
        require(asset_path.is_file() and not asset_path.is_symlink() and
                asset_path.stat().st_size > 0, f"Missing or empty release asset: {name}")
        require(sha256(asset_path) == expected_hashes[name],
                f"Asset {name} does not match {MANIFEST}")
    env_prerelease = os.environ.get("RELEASE_PRERELEASE", "").strip().lower()
    inferred_prerelease = env_prerelease == "true" or "-" in full.split("+", 1)[0]
    if channel is None:
        target_channel = "preview" if inferred_prerelease else "stable"
    else:
        require(channel in ("stable", "preview"), f"Unsupported release channel: {channel}")
        if channel == "stable":
            require(not inferred_prerelease,
                    "Prerelease version or RELEASE_PRERELEASE=true cannot publish to stable channel")
        target_channel = channel
    timestamp = published_at or os.environ.get("RELEASE_PUBLISHED_AT") or (
        datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    )
    doc = {
        "schemaVersion": 1,
        "repository": repository,
        "defaultChannel": "stable",
        "channels": {"stable": None, "preview": None},
    }
    if base_manifest is not None and base_manifest.is_file():
        raw_existing = json.loads(base_manifest.read_text(encoding="utf-8"))
        existing = validate_release_manifest(
            normalize_legacy_manifest(raw_existing, repository=repository),
            repository=repository,
        )
        doc["defaultChannel"] = existing["defaultChannel"]
        doc["channels"]["stable"] = existing["channels"].get("stable")
        doc["channels"]["preview"] = existing["channels"].get("preview")
    if default_channel is not None:
        require(default_channel in ("stable", "preview"), "Invalid default_channel")
        doc["defaultChannel"] = default_channel
    asset_names = sorted(REQUIRED | {MANIFEST})
    doc["channels"][target_channel] = {
        "tag": tag,
        "version": full,
        "publishedAt": timestamp,
        "prerelease": target_channel == "preview",
        "unsignedNotice": True,
        "sha256sumsUrl": f"https://github.com/{repository}/releases/download/{tag}/{MANIFEST}",
        "standards": standards_metadata(root),
        "assets": [
            {
                "name": name,
                "url": f"https://github.com/{repository}/releases/download/{tag}/{name}",
                "sha256": sha256(directory / name),
                "sizeBytes": (directory / name).stat().st_size,
            }
            for name in asset_names
        ],
    }
    validate_release_manifest(doc, repository=repository)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8", newline="\n")
    return doc


def sync_release_manifest(output, *, base_manifest=None, releases_json=None,
                          asset_loader=None, repository=REPOSITORY):
    default_channel = "stable"
    if base_manifest is not None and base_manifest.is_file():
        raw_existing = json.loads(base_manifest.read_text(encoding="utf-8"))
        existing = validate_release_manifest(
            normalize_legacy_manifest(raw_existing, repository=repository),
            repository=repository,
        )
        default_channel = existing["defaultChannel"]
    if releases_json is not None:
        releases = json.loads(releases_json.read_text(encoding="utf-8"))
    else:
        result = subprocess.run(
            ["gh", "api", f"repos/{repository}/releases?per_page=50"],
            check=True, capture_output=True, text=True,
        )
        releases = json.loads(result.stdout)
    require(isinstance(releases, list), "Expected GitHub releases JSON array")

    # Legacy desktop-only releases carry DESKTOP_REQUIRED; unified releases also carry R_SDK_ASSET.
    required_remote = DESKTOP_REQUIRED | {MANIFEST, RELEASE_MANIFEST}
    matched = {}
    for rel in releases:
        if not isinstance(rel, dict) or rel.get("draft") is not False:
            continue
        is_prerelease = rel.get("prerelease")
        if type(is_prerelease) is not bool:
            continue
        channel_name = "preview" if is_prerelease else "stable"
        if channel_name in matched:
            continue
        tag = rel.get("tag_name")
        assets = rel.get("assets")
        if not isinstance(tag, str) or not tag.startswith("v") or not isinstance(assets, list):
            continue
        asset_names = {a.get("name") for a in assets if isinstance(a, dict)}
        if not required_remote.issubset(asset_names):
            continue
        matched[channel_name] = tag
        if "stable" in matched and "preview" in matched:
            break

    doc = {
        "schemaVersion": 1,
        "repository": repository,
        "defaultChannel": default_channel,
        "channels": {"stable": None, "preview": None},
    }
    for channel_name, tag in matched.items():
        if asset_loader is not None:
            raw = asset_loader(tag, RELEASE_MANIFEST)
        else:
            with tempfile.TemporaryDirectory() as tmp:
                run("gh", "release", "download", tag, "--repo", repository,
                    "--pattern", RELEASE_MANIFEST, "--dir", tmp)
                raw = (Path(tmp) / RELEASE_MANIFEST).read_text(encoding="utf-8")
        normalized_remote = normalize_legacy_manifest(json.loads(raw), repository=repository)
        remote_doc = validate_release_manifest(normalized_remote, repository=repository)
        entry = remote_doc["channels"].get(channel_name)
        require(entry is not None and entry.get("tag") == tag,
                f"Downloaded {RELEASE_MANIFEST} for {tag} is missing matching {channel_name} channel")
        doc["channels"][channel_name] = entry

    validate_release_manifest(doc, repository=repository)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8", newline="\n")
    return doc


def validate_whats_new(root, *, scope=None):
    resolved_scope = release_scope(scope)
    if resolved_scope == "r-only":
        return
    full, numeric = release_version(resolved_scope)
    whats_new_path = root / "docs-src/whats_new.json"
    help_bundle_path = root / "app/resources/help_bundle.json"
    require(whats_new_path.is_file(), f"Missing {whats_new_path}")
    require(help_bundle_path.is_file(), f"Missing {help_bundle_path}")
    whats_new = json.loads(whats_new_path.read_text(encoding="utf-8"))
    require(isinstance(whats_new, list) and len(whats_new) >= 1 and isinstance(whats_new[0], dict),
            "docs-src/whats_new.json must contain at least one release entry object")
    latest = whats_new[0]
    latest_version = latest.get("version")
    require(latest_version in (full, numeric),
            f"docs-src/whats_new.json[0].version is {latest_version!r}, "
            f"expected {full!r} or {numeric!r} before tagging a desktop release")
    highlights = latest.get("highlights")
    require(isinstance(highlights, list) and len(highlights) >= 1 and
            all(isinstance(item, str) and item.strip() for item in highlights),
            "docs-src/whats_new.json[0].highlights must be a non-empty list of strings")
    bundle = json.loads(help_bundle_path.read_text(encoding="utf-8"))
    require(isinstance(bundle, dict) and bundle.get("whatsNew") == whats_new,
            "app/resources/help_bundle.json whatsNew is out of sync with docs-src/whats_new.json")


def _release_sort_key(rel):
    return str(rel.get("published_at") or rel.get("created_at") or "")


def _is_dev_release(rel):
    if not isinstance(rel, dict):
        return False
    tag = rel.get("tag_name")
    return (
        rel.get("draft") is False
        and rel.get("prerelease") is True
        and isinstance(tag, str)
        and tag.startswith(DEV_TAG_PREFIX)
        and len(tag) > len(DEV_TAG_PREFIX)
    )


def _sanitize_commit_subject(raw):
    cleaned = " ".join(str(raw or "").split())
    if len(cleaned) > 140:
        cleaned = cleaned[:137].rstrip() + "..."
    return cleaned or "Development snapshot"


def next_dev_numeric(root):
    whats_new_path = root / "docs-src/whats_new.json"
    require(whats_new_path.is_file(), f"Missing {whats_new_path}")
    whats_new = json.loads(whats_new_path.read_text(encoding="utf-8"))
    require(isinstance(whats_new, list) and len(whats_new) >= 1 and isinstance(whats_new[0], dict),
            "docs-src/whats_new.json must contain at least one release entry object")
    _, base_numeric = version(str(whats_new[0].get("version", "")))
    major, minor, patch = (int(part) for part in base_numeric.split("."))
    if patch < 65535:
        patch += 1
    else:
        minor += 1
        patch = 0
    require(minor <= 65535, "Next dev version exceeds NSIS 16-bit limit")
    return f"{major}.{minor}.{patch}"


def make_dev_identity(root, *, commit_sha, run_number, now=None):
    require(re.fullmatch(r"[0-9a-f]{40}", commit_sha) is not None,
            "Expected a 40-character lowercase Git commit SHA")
    run_int = int(run_number)
    require(run_int >= 1, "GITHUB_RUN_NUMBER must be a positive integer")
    stamp = (now or datetime.now(timezone.utc)).strftime("%Y%m%d")
    short_sha = commit_sha[:7]
    numeric = next_dev_numeric(root)
    full_ver = f"{numeric}-dev.{stamp}.{run_int}.g{short_sha}"
    version(full_ver)
    tag = f"{DEV_TAG_PREFIX}{stamp}-r{run_int}-g{short_sha}"
    return {
        "version": full_ver,
        "numeric": numeric,
        "tag": tag,
        "build_mode": "alpha",
        "commit": commit_sha,
        "short_commit": short_sha,
    }


def _has_desktop_changes(paths):
    for rel_path in paths:
        norm = str(rel_path).strip().replace("\\", "/")
        if not norm:
            continue
        if norm in DEV_APP_TRIGGER_FILES or any(norm.startswith(prefix) for prefix in DEV_APP_TRIGGER_PREFIXES):
            return True
    return False


def dev_plan(root, *, commit_sha=None, commit_subject=None, run_number=None,
             force=False, skip_ci_check=False, ci_runs_json=None,
             releases_json=None, changed_files=None, now=None,
             repository=REPOSITORY):
    sha = commit_sha or os.environ["GITHUB_SHA"]
    require(re.fullmatch(r"[0-9a-f]{40}", sha) is not None,
            "Expected a 40-character lowercase Git commit SHA")
    run_num = run_number if run_number is not None else os.environ.get("GITHUB_RUN_NUMBER", "1")

    if not skip_ci_check:
        if ci_runs_json is not None:
            runs_payload = json.loads(ci_runs_json.read_text(encoding="utf-8"))
        else:
            res = subprocess.run(
                ["gh", "api", f"repos/{repository}/actions/workflows/ci.yml/runs?head_sha={sha}&per_page=20"],
                check=True, capture_output=True, text=True,
            )
            runs_payload = json.loads(res.stdout)
        runs = runs_payload.get("workflow_runs") if isinstance(runs_payload, dict) else None
        require(isinstance(runs, list), "Malformed workflow_runs response from GitHub API")
        ci_passed = any(
            isinstance(run_item, dict)
            and run_item.get("status") == "completed"
            and run_item.get("conclusion") == "success"
            for run_item in runs
        )
        if not ci_passed:
            return {
                "should_build": False,
                "reason": f"No passing CI workflow run found for commit {sha[:7]}",
            }

    if not force:
        if releases_json is not None:
            releases = json.loads(releases_json.read_text(encoding="utf-8"))
        else:
            res = subprocess.run(
                ["gh", "api", f"repos/{repository}/releases?per_page=30"],
                check=True, capture_output=True, text=True,
            )
            releases = json.loads(res.stdout)
        require(isinstance(releases, list), "Expected GitHub releases JSON array")
        dev_releases = sorted((r for r in releases if _is_dev_release(r)), key=_release_sort_key, reverse=True)
        if dev_releases:
            latest = dev_releases[0]
            prev_sha = latest.get("target_commitish")
            if not (isinstance(prev_sha, str) and re.fullmatch(r"[0-9a-f]{40}", prev_sha)):
                prev_tag = latest["tag_name"]
                lookup = subprocess.run(
                    ["git", "rev-list", "-n", "1", f"refs/tags/{prev_tag}"],
                    cwd=root, capture_output=True, text=True,
                )
                prev_sha = lookup.stdout.strip() if lookup.returncode == 0 else ""
            if prev_sha == sha:
                return {
                    "should_build": False,
                    "reason": f"Latest dev build ({latest['tag_name']}) already covers commit {sha[:7]}",
                }
            if isinstance(prev_sha, str) and re.fullmatch(r"[0-9a-f]{40}", prev_sha):
                if changed_files is not None:
                    diff_paths = list(changed_files)
                else:
                    exists = subprocess.run(
                        ["git", "cat-file", "-e", f"{prev_sha}^{{commit}}"],
                        cwd=root, capture_output=True, text=True,
                    )
                    if exists.returncode == 0:
                        diff_res = subprocess.run(
                            ["git", "diff", "--name-only", f"{prev_sha}..{sha}"],
                            cwd=root, check=True, capture_output=True, text=True,
                        )
                        diff_paths = [line for line in diff_res.stdout.splitlines() if line.strip()]
                    else:
                        diff_paths = None
                if diff_paths is not None and not _has_desktop_changes(diff_paths):
                    return {
                        "should_build": False,
                        "reason": f"No desktop app changes since {latest['tag_name']} ({prev_sha[:7]}..{sha[:7]})",
                    }

    if commit_subject is None:
        subj_res = subprocess.run(
            ["git", "log", "-1", "--pretty=%s", sha],
            cwd=root, check=True, capture_output=True, text=True,
        )
        raw_subject = subj_res.stdout
    else:
        raw_subject = commit_subject

    identity = make_dev_identity(root, commit_sha=sha, run_number=run_num, now=now)
    return {
        "should_build": True,
        "reason": f"Ready to build {identity['tag']} for commit {sha[:7]}",
        "commit_subject": _sanitize_commit_subject(raw_subject),
        **identity,
    }


def dev_package(root, platform):
    full, _ = release_version("full")
    if platform == "vpro64":
        group = VPRO64_BRIDGE_GROUP
        destination = root / "scripts/vpro64/dist-artifacts"
        destination.mkdir(parents=True)
        build_vpro64_bridge_zip(root, destination / VPRO64_BRIDGE_ASSET)
        exact_files(destination, DEV_ASSETS[group])
        witness = {
            "schema": 1,
            "mode": "dev",
            "group": group,
            "version": full,
            "commit": os.environ["GITHUB_SHA"],
            "architectures": expected_architectures(group),
            "sha256": {VPRO64_BRIDGE_ASSET: sha256(destination / VPRO64_BRIDGE_ASSET)},
        }
        (destination / f"release-witness-{group}.json").write_text(
            json.dumps(witness, sort_keys=True) + "\n", encoding="utf-8")
        return
    arch = os.environ["RELEASE_ARCH"]
    group = f"{platform}-{arch}"
    require(group in DEV_ASSETS, f"Unsupported dev release target: {group}")
    app_root = root / "app"
    destination = app_root / "dist-artifacts"
    destination.mkdir(parents=True)
    binary = app_root / "bin/VPro"
    if platform == "windows":
        binary = binary.with_suffix(".exe")
        check_cpu(binary, "pe", arch)
        installer = app_root / f"bin/VPro-{arch}-installer.exe"
        require(installer.is_file(), f"Missing exact NSIS output: {installer}")
        with tempfile.TemporaryDirectory() as temporary:
            run("7z", "x", "-y", str(installer), f"-o{temporary}")
            payloads = list(Path(temporary).rglob("VPro.exe"))
            require(len(payloads) == 1, "Missing/ambiguous NSIS application payload")
            check_cpu(payloads[0], "pe", arch)
            require(sha256(payloads[0]) == sha256(binary), "NSIS payload differs from built EXE")
        shutil.copyfile(installer, destination / DEV_ASSETS[group][0])
    elif platform == "linux":
        check_cpu(binary, "elf", arch)
        deb = unique_output(app_root, ".deb")
        validate_deb(deb, arch, full)
        rpm = unique_output(app_root, ".rpm")
        validate_rpm(rpm, arch, full)
        shutil.copyfile(deb, destination / DEV_ASSETS[group][0])
        shutil.copyfile(rpm, destination / DEV_ASSETS[group][1])
    else:
        raise ValueError(f"Unsupported dev platform: {platform}")
    exact_files(destination, DEV_ASSETS[group])
    witness = {
        "schema": 1,
        "mode": "dev",
        "group": group,
        "version": full,
        "commit": os.environ["GITHUB_SHA"],
        "architectures": expected_architectures(group),
        "sha256": {name: sha256(destination / name) for name in DEV_ASSETS[group]},
    }
    (destination / f"release-witness-{group}.json").write_text(
        json.dumps(witness, sort_keys=True) + "\n", encoding="utf-8")


def validate_dev_build(entry, *, repository=REPOSITORY):
    require(isinstance(entry, dict), "Dev build entry must be a JSON object")
    expected_keys = {
        "schemaVersion", "repository", "tag", "version", "publishedAt",
        "commit", "shortCommit", "commitSubject", "unsignedNotice",
        "sha256sumsUrl", "assets",
    }
    require(set(entry) == expected_keys, "Unexpected keys in dev-build.json")
    require(type(entry.get("schemaVersion")) is int and entry["schemaVersion"] == 1,
            "Unsupported dev-build.json schemaVersion")
    require(entry.get("repository") == repository,
            f"Unexpected dev-build.json repository: {entry.get('repository')!r}")
    tag = entry.get("tag")
    require(isinstance(tag, str) and tag.startswith(DEV_TAG_PREFIX) and
            re.fullmatch(r"dev-[0-9A-Za-z._-]+", tag) is not None,
            f"Invalid dev build tag: {tag!r}")
    full_ver = entry.get("version")
    require(isinstance(full_ver, str), "Dev build is missing version")
    normalized, _ = version(full_ver)
    require(normalized == full_ver and "-" in full_ver.split("+", 1)[0],
            "Dev build version must be a prerelease SemVer without leading v")
    published_at = entry.get("publishedAt")
    require(isinstance(published_at, str) and re.fullmatch(
        r"\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)?", published_at) is not None,
        "Dev build has invalid ISO-8601 publishedAt")
    commit = entry.get("commit")
    require(isinstance(commit, str) and re.fullmatch(r"[0-9a-f]{40}", commit) is not None,
            "Dev build has invalid commit SHA")
    short_commit = entry.get("shortCommit")
    require(isinstance(short_commit, str) and short_commit == commit[:7],
            "Dev build shortCommit does not match commit prefix")
    subject = entry.get("commitSubject")
    require(isinstance(subject, str) and len(subject.strip()) > 0 and "\n" not in subject and "\r" not in subject,
            "Dev build commitSubject must be a non-empty single-line string")
    require(type(entry.get("unsignedNotice")) is bool,
            "Dev build unsignedNotice must be boolean")
    validate_download_url(entry.get("sha256sumsUrl"), MANIFEST, tag, repository)
    assets = entry.get("assets")
    require(isinstance(assets, list) and len(assets) > 0, "Dev build assets must be non-empty")
    seen = set()
    for asset in assets:
        require(isinstance(asset, dict), "Dev build contains malformed asset")
        name = asset.get("name")
        require(isinstance(name, str) and name in DEV_ALLOWED_ASSETS and name not in seen,
                f"Dev build contains unexpected or duplicate asset: {name!r}")
        seen.add(name)
        validate_download_url(asset.get("url"), name, tag, repository)
        digest = asset.get("sha256")
        require(isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest) is not None,
                f"Dev build asset {name} has invalid sha256")
        size_bytes = asset.get("sizeBytes")
        require(type(size_bytes) is int and size_bytes > 0,
                f"Dev build asset {name} has invalid sizeBytes")
    require(DEV_CORE_REQUIRED.issubset(seen), "Dev build is missing required x64 packages")
    return entry


def validate_dev_manifest(doc, *, repository=REPOSITORY):
    require(isinstance(doc, dict), "Dev manifest must be a JSON object")
    require(set(doc) == {"schemaVersion", "repository", "maxBuilds", "builds"},
            "Unexpected top-level keys in dev-manifest.json")
    require(type(doc.get("schemaVersion")) is int and doc["schemaVersion"] == 1,
            "Unsupported dev-manifest.json schemaVersion")
    require(doc.get("repository") == repository,
            f"Unexpected dev-manifest.json repository: {doc.get('repository')!r}")
    max_builds = doc.get("maxBuilds")
    require(type(max_builds) is int and 1 <= max_builds <= 20,
            "dev-manifest.json maxBuilds must be between 1 and 20")
    builds = doc.get("builds")
    require(isinstance(builds, list) and len(builds) <= max_builds,
            "dev-manifest.json builds must be a list within maxBuilds")
    seen_tags = set()
    for entry in builds:
        validate_dev_build(entry, repository=repository)
        tag = entry["tag"]
        require(tag not in seen_tags, f"Duplicate dev build tag in dev-manifest.json: {tag}")
        seen_tags.add(tag)
    return doc


def dev_manifest(directory, *, tag=None, commit_subject=None, published_at=None,
                 repository=REPOSITORY):
    full, _ = release_version("full")
    dev_tag = tag or os.environ["DEV_TAG"]
    commit = os.environ["GITHUB_SHA"]
    witnesses = {f"release-witness-{group}.json" for group in DEV_GROUPS}
    exact_files(directory, DEV_REQUIRED | witnesses)
    for group in DEV_GROUPS:
        witness = json.loads((directory / f"release-witness-{group}.json").read_text(encoding="utf-8"))
        expected = {
            "schema": 1,
            "mode": "dev",
            "group": group,
            "version": full,
            "commit": commit,
            "architectures": expected_architectures(group),
            "sha256": {name: sha256(directory / name) for name in DEV_ASSETS[group]},
        }
        require(witness == expected, f"Invalid dev provenance/CPU witness: {group}")
    validate_deb(directory / "vpro-linux-amd64.deb", "amd64", full)
    validate_rpm(directory / "vpro-linux-amd64.rpm", "amd64", full)
    validate_vpro64_bridge(directory / VPRO64_BRIDGE_ASSET)

    checksum_lines = "".join(f"{sha256(directory / name)}  {name}\n" for name in sorted(DEV_REQUIRED))
    (directory / MANIFEST).write_text(checksum_lines, encoding="ascii", newline="\n")

    timestamp = published_at or os.environ.get("DEV_PUBLISHED_AT") or (
        datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    )
    subject = _sanitize_commit_subject(commit_subject or os.environ.get("DEV_COMMIT_SUBJECT") or "")
    asset_names = sorted(DEV_REQUIRED | {MANIFEST})
    metadata = {
        "schemaVersion": 1,
        "repository": repository,
        "tag": dev_tag,
        "version": full,
        "publishedAt": timestamp,
        "commit": commit,
        "shortCommit": commit[:7],
        "commitSubject": subject,
        "unsignedNotice": True,
        "sha256sumsUrl": f"https://github.com/{repository}/releases/download/{dev_tag}/{MANIFEST}",
        "assets": [
            {
                "name": name,
                "url": f"https://github.com/{repository}/releases/download/{dev_tag}/{name}",
                "sha256": sha256(directory / name),
                "sizeBytes": (directory / name).stat().st_size,
            }
            for name in asset_names
        ],
    }
    validate_dev_build(metadata, repository=repository)
    (directory / DEV_BUILD_METADATA).write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8", newline="\n")
    attach_names = sorted(DEV_REQUIRED | {MANIFEST, DEV_BUILD_METADATA})
    Path("dev-assets.txt").write_text(
        "".join(f"{directory / name}\n" for name in attach_names),
        encoding="utf-8", newline="\n")
    return metadata


def dev_remote(path):
    assets = json.loads(path.read_text(encoding="utf-8"))["assets"]
    names = [asset["name"] for asset in assets]
    require(len(names) == len(set(names)), "Remote dev release has duplicate asset names")
    expected = DEV_REQUIRED | {MANIFEST, DEV_BUILD_METADATA}
    require(set(names) == expected,
            "Remote dev release has missing or unexpected assets")


def dev_verify(directory, trusted_manifest, trusted_build_meta, *, repository=REPOSITORY):
    content = trusted_manifest.read_text(encoding="ascii")
    expected = parse_manifest(content, expected_names=DEV_REQUIRED)
    expected_set = DEV_REQUIRED | {MANIFEST, DEV_BUILD_METADATA}
    exact_files(directory, expected_set)
    require((directory / MANIFEST).read_bytes() == trusted_manifest.read_bytes(),
            "Downloaded dev checksum manifest differs from validated manifest")
    for name, digest in expected.items():
        require(sha256(directory / name) == digest, f"Dev SHA256 mismatch: {name}")
    trusted_bytes = trusted_build_meta.read_bytes()
    require((directory / DEV_BUILD_METADATA).read_bytes() == trusted_bytes,
            "Downloaded dev-build.json differs from validated metadata")
    validate_dev_build(json.loads(trusted_bytes.decode("utf-8")), repository=repository)


def sync_dev_manifest(output, *, keep=DEV_MAX_BUILDS, releases_json=None,
                      asset_loader=None, repository=REPOSITORY):
    require(type(keep) is int and 1 <= keep <= 20, "keep must be between 1 and 20")
    if releases_json is not None:
        releases = json.loads(releases_json.read_text(encoding="utf-8"))
    else:
        result = subprocess.run(
            ["gh", "api", f"repos/{repository}/releases?per_page=50"],
            check=True, capture_output=True, text=True,
        )
        releases = json.loads(result.stdout)
    require(isinstance(releases, list), "Expected GitHub releases JSON array")

    candidates = []
    for rel in releases:
        if not _is_dev_release(rel):
            continue
        assets = rel.get("assets")
        if not isinstance(assets, list):
            continue
        asset_names = {a.get("name") for a in assets if isinstance(a, dict)}
        if not {MANIFEST, DEV_BUILD_METADATA}.issubset(asset_names):
            continue
        candidates.append(rel)
    candidates.sort(key=_release_sort_key, reverse=True)

    builds = []
    for rel in candidates[:keep]:
        tag = rel["tag_name"]
        if asset_loader is not None:
            raw = asset_loader(tag, DEV_BUILD_METADATA)
        else:
            with tempfile.TemporaryDirectory() as tmp:
                run("gh", "release", "download", tag, "--repo", repository,
                    "--pattern", DEV_BUILD_METADATA, "--dir", tmp)
                raw = (Path(tmp) / DEV_BUILD_METADATA).read_text(encoding="utf-8")
        entry = validate_dev_build(json.loads(raw), repository=repository)
        require(entry["tag"] == tag, f"Downloaded {DEV_BUILD_METADATA} tag mismatch for {tag}")
        builds.append(entry)

    doc = {
        "schemaVersion": 1,
        "repository": repository,
        "maxBuilds": keep,
        "builds": builds,
    }
    validate_dev_manifest(doc, repository=repository)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8", newline="\n")
    return doc


def prune_dev_releases(*, keep=DEV_MAX_BUILDS, releases_json=None,
                       dry_run=False, deleter=None, repository=REPOSITORY):
    require(type(keep) is int and 1 <= keep <= 20, "keep must be between 1 and 20")
    if releases_json is not None:
        releases = json.loads(releases_json.read_text(encoding="utf-8"))
    else:
        result = subprocess.run(
            ["gh", "api", f"repos/{repository}/releases?per_page=100"],
            check=True, capture_output=True, text=True,
        )
        releases = json.loads(result.stdout)
    require(isinstance(releases, list), "Expected GitHub releases JSON array")

    dev_releases = sorted((r for r in releases if _is_dev_release(r)), key=_release_sort_key, reverse=True)
    kept = [r["tag_name"] for r in dev_releases[:keep]]
    to_delete = [r["tag_name"] for r in dev_releases[keep:]]
    for tag in to_delete:
        require(tag.startswith(DEV_TAG_PREFIX), f"Refusing to prune non-dev tag: {tag}")
        if dry_run:
            continue
        if deleter is not None:
            deleter(tag)
        else:
            run("gh", "release", "delete", tag, "--repo", repository, "--cleanup-tag", "--yes")
    return {"kept": kept, "deleted": to_delete}


def wait_pages_artifact(
    *,
    artifact_id,
    artifact_name="github-pages",
    run_id=None,
    repository=None,
    attempts=20,
    interval_seconds=2.0,
    settle_seconds=3.0,
    fetcher=None,
    sleeper=time.sleep,
):
    raw_id = str(artifact_id or "").strip()
    require(raw_id.isdigit() and int(raw_id) > 0,
            f"Expected positive integer Pages artifact ID, got {artifact_id!r}")
    expected_id = int(raw_id)
    require(isinstance(artifact_name, str) and artifact_name.strip() == artifact_name and len(artifact_name) > 0,
            f"Invalid Pages artifact name: {artifact_name!r}")
    resolved_run_id = str(run_id if run_id is not None else os.environ.get("GITHUB_RUN_ID", "")).strip()
    require(resolved_run_id.isdigit() and int(resolved_run_id) > 0,
            f"Expected positive integer GITHUB_RUN_ID, got {resolved_run_id!r}")
    resolved_repo = repository or os.environ.get("GITHUB_REPOSITORY") or REPOSITORY
    require(type(attempts) is int and 1 <= attempts <= 60, "attempts must be between 1 and 60")
    require(interval_seconds >= 0 and settle_seconds >= 0, "sleep durations must be non-negative")

    endpoint = f"repos/{resolved_repo}/actions/runs/{resolved_run_id}/artifacts?name={artifact_name}&per_page=10"
    for attempt in range(1, attempts + 1):
        if fetcher is not None:
            payload = fetcher(endpoint)
        else:
            result = subprocess.run(
                ["gh", "api", endpoint],
                check=True, capture_output=True, text=True,
            )
            payload = json.loads(result.stdout)
        require(isinstance(payload, dict), "Malformed GitHub Actions artifacts payload")
        artifacts = payload.get("artifacts")
        require(isinstance(artifacts, list), "Malformed artifacts list in GitHub API response")
        for item in artifacts:
            if (
                isinstance(item, dict)
                and item.get("id") == expected_id
                and item.get("name") == artifact_name
                and item.get("expired") is False
            ):
                if settle_seconds > 0:
                    sleeper(settle_seconds)
                return item
        if attempt < attempts and interval_seconds > 0:
            sleeper(interval_seconds)
    raise ValueError(
        f"Timed out waiting for {artifact_name!r} artifact {expected_id} "
        f"in workflow run {resolved_run_id} after {attempts} attempt(s)"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    ver_cmd = commands.add_parser("version")
    ver_cmd.add_argument("--scope", choices=SCOPES)
    whats_new_cmd = commands.add_parser("whats-new")
    whats_new_cmd.add_argument("--scope", choices=SCOPES)
    whats_new_cmd.add_argument("--root", type=Path)
    src_cmd = commands.add_parser("source-tag")
    src_cmd.add_argument("--scope", choices=SCOPES)
    meta_cmd = commands.add_parser("metadata")
    meta_cmd.add_argument("--target", choices=("app", "r", "all"), default="app")
    meta_cmd.add_argument("--scope", choices=SCOPES)
    toolchain = commands.add_parser("toolchain")
    toolchain.add_argument("--arch", choices=ARCHES, required=True)
    packaging = commands.add_parser("package")
    packaging.add_argument("platform", choices=("windows", "macos", "linux", "r", "vpro64"))
    packaging.add_argument("--scope", choices=SCOPES)
    architecture = commands.add_parser("cpu")
    architecture.add_argument("path", type=Path)
    architecture.add_argument("--format", choices=("pe", "elf", "macho"), required=True)
    architecture.add_argument("--arch", choices=(*ARCHES, "universal"), required=True)
    portal_manifest = commands.add_parser("release-manifest")
    portal_manifest.add_argument("path", type=Path)
    portal_manifest.add_argument("--output", type=Path, required=True)
    portal_manifest.add_argument("--channel", choices=("stable", "preview"))
    portal_manifest.add_argument("--published-at")
    portal_manifest.add_argument("--base-manifest", type=Path)
    portal_manifest.add_argument("--default-channel", choices=("stable", "preview"))
    sync_manifest = commands.add_parser("sync-release-manifest")
    sync_manifest.add_argument("--output", type=Path, required=True)
    sync_manifest.add_argument("--base-manifest", type=Path)
    sync_manifest.add_argument("--releases-json", type=Path)
    dev_plan_cmd = commands.add_parser("dev-plan")
    dev_plan_cmd.add_argument("--root", type=Path)
    dev_plan_cmd.add_argument("--force", action="store_true")
    dev_plan_cmd.add_argument("--skip-ci-check", action="store_true")
    dev_plan_cmd.add_argument("--ci-runs-json", type=Path)
    dev_plan_cmd.add_argument("--releases-json", type=Path)
    dev_pkg_cmd = commands.add_parser("dev-package")
    dev_pkg_cmd.add_argument("platform", choices=("windows", "linux", "vpro64"))
    dev_manifest_cmd = commands.add_parser("dev-manifest")
    dev_manifest_cmd.add_argument("path", type=Path)
    dev_manifest_cmd.add_argument("--tag")
    dev_manifest_cmd.add_argument("--commit-subject")
    dev_manifest_cmd.add_argument("--published-at")
    dev_remote_cmd = commands.add_parser("dev-remote")
    dev_remote_cmd.add_argument("path", type=Path)
    dev_verify_cmd = commands.add_parser("dev-verify")
    dev_verify_cmd.add_argument("path", type=Path)
    dev_verify_cmd.add_argument("--manifest", type=Path, required=True)
    dev_verify_cmd.add_argument("--dev-build", type=Path, required=True)
    sync_dev_cmd = commands.add_parser("sync-dev-manifest")
    sync_dev_cmd.add_argument("--output", type=Path, required=True)
    sync_dev_cmd.add_argument("--keep", type=int, default=DEV_MAX_BUILDS)
    sync_dev_cmd.add_argument("--releases-json", type=Path)
    prune_dev_cmd = commands.add_parser("prune-dev")
    prune_dev_cmd.add_argument("--keep", type=int, default=DEV_MAX_BUILDS)
    prune_dev_cmd.add_argument("--releases-json", type=Path)
    prune_dev_cmd.add_argument("--dry-run", action="store_true")
    wait_pages_cmd = commands.add_parser("wait-pages-artifact")
    wait_pages_cmd.add_argument("--artifact-id", required=True)
    wait_pages_cmd.add_argument("--artifact-name", default="github-pages")
    wait_pages_cmd.add_argument("--run-id")
    wait_pages_cmd.add_argument("--attempts", type=int, default=20)
    wait_pages_cmd.add_argument("--interval", type=float, default=2.0)
    wait_pages_cmd.add_argument("--settle", type=float, default=3.0)
    for command in ("manifest", "remote", "verify"):
        subparser = commands.add_parser(command)
        subparser.add_argument("path", type=Path)
        subparser.add_argument("--scope", choices=SCOPES)
        if command == "remote":
            subparser.add_argument("--require-release-manifest", action="store_true")
        if command == "verify":
            subparser.add_argument("--manifest", type=Path, required=True)
            subparser.add_argument("--release-manifest", type=Path)
    args = parser.parse_args()
    if args.command == "version":
        resolved_scope = release_scope(args.scope)
        full, numeric = release_version(resolved_scope)
        env_prerelease = os.environ.get("RELEASE_PRERELEASE", "").strip().lower() == "true"
        mode = infer_build_mode(full, prerelease=env_prerelease)
        tag = f"r-v{full}" if resolved_scope == "r-only" else f"v{full}"
        with Path(os.environ["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as output:
            output.write(f"version={full}\ntag={tag}\nbuild_mode={mode}\n")
            if args.scope is not None or "RELEASE_SCOPE" in os.environ:
                output.write(f"numeric={numeric}\nscope={resolved_scope}\n")
    elif args.command == "whats-new":
        validate_whats_new(args.root or Path.cwd(), scope=args.scope)
    elif args.command == "toolchain":
        print(json.dumps(windows_toolchain(args.arch), sort_keys=True))
    elif args.command == "source-tag":
        check_source_tag(args.scope)
    elif args.command == "metadata":
        prepare_metadata(Path.cwd(), target=args.target, scope=args.scope)
    elif args.command == "package":
        package(Path.cwd(), args.platform, scope=args.scope)
    elif args.command == "cpu":
        check_cpu(args.path, args.format, args.arch)
    elif args.command == "manifest":
        manifest(args.path, scope=args.scope)
    elif args.command == "release-manifest":
        release_manifest(
            args.path,
            args.output,
            channel=args.channel,
            published_at=args.published_at,
            base_manifest=args.base_manifest,
            default_channel=args.default_channel,
        )
    elif args.command == "sync-release-manifest":
        sync_release_manifest(
            args.output,
            base_manifest=args.base_manifest,
            releases_json=args.releases_json,
        )
    elif args.command == "dev-plan":
        plan = dev_plan(
            args.root or Path.cwd(),
            force=args.force,
            skip_ci_check=args.skip_ci_check,
            ci_runs_json=args.ci_runs_json,
            releases_json=args.releases_json,
        )
        print(plan["reason"])
        if "GITHUB_OUTPUT" in os.environ:
            with Path(os.environ["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as output:
                output.write(f"should_build={'true' if plan['should_build'] else 'false'}\n")
                output.write(f"reason={_sanitize_commit_subject(plan['reason'])}\n")
                if plan["should_build"]:
                    for key in ("version", "numeric", "tag", "build_mode", "commit", "short_commit", "commit_subject"):
                        output.write(f"{key}={plan[key]}\n")
    elif args.command == "dev-package":
        dev_package(Path.cwd(), args.platform)
    elif args.command == "dev-manifest":
        dev_manifest(
            args.path,
            tag=args.tag,
            commit_subject=args.commit_subject,
            published_at=args.published_at,
        )
    elif args.command == "dev-remote":
        dev_remote(args.path)
    elif args.command == "dev-verify":
        dev_verify(args.path, args.manifest, args.dev_build)
    elif args.command == "sync-dev-manifest":
        sync_dev_manifest(
            args.output,
            keep=args.keep,
            releases_json=args.releases_json,
        )
    elif args.command == "prune-dev":
        summary = prune_dev_releases(
            keep=args.keep,
            releases_json=args.releases_json,
            dry_run=args.dry_run,
        )
        print(f"Kept {len(summary['kept'])} dev release(s); deleted {len(summary['deleted'])}.")
    elif args.command == "wait-pages-artifact":
        found = wait_pages_artifact(
            artifact_id=args.artifact_id,
            artifact_name=args.artifact_name,
            run_id=args.run_id,
            attempts=args.attempts,
            interval_seconds=args.interval,
            settle_seconds=args.settle,
        )
        print(f"Pages artifact {found['name']} (id={found['id']}) is visible.")
    elif args.command == "remote":
        remote(args.path, require_release_manifest=args.require_release_manifest, scope=args.scope)
    else:
        verify(args.path, args.manifest, release_manifest_path=args.release_manifest, scope=args.scope)


if __name__ == "__main__":
    main()
