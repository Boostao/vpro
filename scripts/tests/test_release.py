import contextlib
import hashlib
import importlib.util
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
import unittest
from unittest.mock import patch
import zipfile


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("release", ROOT / "scripts/release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)

# Independent ordered release contract, not generated from the implementation.
DESKTOP_EXPECTED = (
    "vpro-linux-amd64.deb", "vpro-linux-amd64.rpm", "vpro-linux-amd64.tar.gz",
    "vpro-linux-arm64.deb", "vpro-linux-arm64.rpm", "vpro-linux-arm64.tar.gz",
    "vpro-macos-universal.dmg", "vpro-macos-universal.zip",
    "vpro-windows-amd64-installer.exe", "vpro-windows-amd64.exe", "vpro-windows-amd64.zip",
    "vpro-windows-arm64-installer.exe", "vpro-windows-arm64.exe", "vpro-windows-arm64.zip",
)
EXPECTED = tuple(sorted((*DESKTOP_EXPECTED, "vpro-r-sdk.tar.gz", "vpro64-sqlite-bridge.zip")))


def pe(arch, imports=("KERNEL32.dll", "api-ms-win-crt-runtime-l1-1-0.dll"), delay_imports=()):
    pe_offset = 128
    opt_offset = pe_offset + 24
    opt_size = 240
    sec_offset = opt_offset + opt_size
    rdata_rva = 0x1000
    rdata_raw = 512

    section_payload = bytearray()
    imp_rva = imp_size = 0
    if imports:
        imp_rva = rdata_rva + len(section_payload)
        imp_size = (len(imports) + 1) * 20
        desc_start = len(section_payload)
        section_payload.extend(b"\x00" * imp_size)
        for index, dll in enumerate(imports):
            name_rva = rdata_rva + len(section_payload)
            section_payload.extend(dll.encode("ascii") + b"\x00")
            struct.pack_into("<IIIII", section_payload, desc_start + index * 20,
                             0, 0, 0, name_rva, 0)

    delay_rva = delay_size = 0
    if delay_imports:
        if len(section_payload) % 4:
            section_payload.extend(b"\x00" * (4 - len(section_payload) % 4))
        delay_rva = rdata_rva + len(section_payload)
        delay_size = (len(delay_imports) + 1) * 32
        desc_start = len(section_payload)
        section_payload.extend(b"\x00" * delay_size)
        for index, dll in enumerate(delay_imports):
            name_rva = rdata_rva + len(section_payload)
            section_payload.extend(dll.encode("ascii") + b"\x00")
            struct.pack_into("<IIIIIIII", section_payload, desc_start + index * 32,
                             1, name_rva, 0, 0, 0, 0, 0, 0)

    raw_size = max(64, ((len(section_payload) + 15) // 16) * 16)
    section_payload.extend(b"\x00" * (raw_size - len(section_payload)))

    data = bytearray(rdata_raw + len(section_payload))
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 60, pe_offset)
    data[pe_offset:pe_offset + 4] = b"PE\0\0"
    struct.pack_into("<HH", data, pe_offset + 4,
                     0x8664 if arch == "amd64" else 0xAA64, 1)
    struct.pack_into("<H", data, pe_offset + 20, opt_size)
    struct.pack_into("<H", data, opt_offset, 0x20B)
    struct.pack_into("<I", data, opt_offset + 108, 16)
    struct.pack_into("<II", data, opt_offset + 112 + 8, imp_rva, imp_size)
    struct.pack_into("<II", data, opt_offset + 112 + 13 * 8, delay_rva, delay_size)
    data[sec_offset:sec_offset + 6] = b".rdata"
    struct.pack_into("<IIII", data, sec_offset + 8,
                     len(section_payload), rdata_rva, raw_size, rdata_raw)
    data[rdata_raw:rdata_raw + len(section_payload)] = section_payload
    return bytes(data)


def rpm(arch, version="2.3.4"):
    rpm_arch = "x86_64" if arch == "amd64" else "aarch64"
    data = bytearray(256)
    data[:4] = b"\xed\xab\xee\xdb"
    name = f"vpro-{version}-1.{rpm_arch}".encode("utf-8")[:65]
    data[10:10 + len(name)] = name
    data[96:100] = b"\x8e\xad\xe8\x01"
    return bytes(data)


def _rpm_header_block(string_tags):
    index = bytearray()
    store = bytearray()
    for tag, value in sorted(string_tags.items()):
        offset = len(store)
        store.extend(value.encode("utf-8") + b"\x00")
        index.extend(struct.pack(">IIII", tag, 6, offset, 1))
    header = bytearray(b"\x8e\xad\xe8\x01\x00\x00\x00\x00")
    header.extend(struct.pack(">II", len(string_tags), len(store)))
    header.extend(index)
    header.extend(store)
    return bytes(header)


def nfpm_rpm(arch, rpm_ver="2.3.4", *, license_name="Apache-2.0", pkg_name="vpro", rel="1"):
    rpm_arch = "x86_64" if arch == "amd64" else "aarch64"
    lead = bytearray(96)
    lead[:4] = b"\xed\xab\xee\xdb"
    lead_str = f"{pkg_name}-{rpm_ver}-{rel}".encode("utf-8")[:65]
    lead[10:10 + len(lead_str)] = lead_str
    sig = _rpm_header_block({273: "0" * 64})
    pad = ((len(sig) + 7) & ~7) - len(sig)
    meta = _rpm_header_block({
        1000: pkg_name,
        1001: rpm_ver,
        1002: rel,
        1014: license_name,
        1022: rpm_arch,
    })
    return bytes(lead) + sig + (b"\x00" * pad) + meta + b"\x00" * 32


def elf(arch, appimage=False):
    data = bytearray(128)
    data[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<H", data, 18, 62 if arch == "amd64" else 183)
    if appimage:
        data[8:11] = b"AI\x02"
    return bytes(data)


def universal():
    data = bytearray(256)
    struct.pack_into(">II", data, 0, 0xCAFEBABE, 2)
    for index, (machine, offset) in enumerate(((0x01000007, 128), (0x0100000C, 192))):
        struct.pack_into(">IIIII", data, 8 + index * 20, machine, 0, offset, 64, 0)
        data[offset:offset + 4] = b"\xcf\xfa\xed\xfe"
        struct.pack_into("<I", data, offset + 4, machine)
    return bytes(data)


def tar_bytes(entries):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz") as archive:
        for name, data in entries:
            entry = tarfile.TarInfo(name)
            entry.size = len(data)
            archive.addfile(entry, io.BytesIO(data))
    return output.getvalue()


def deb(arch, version="2.3.4"):
    control = f"Package: vpro\nVersion: {version}-1\nArchitecture: {arch}\n".encode()
    entries = (("debian-binary", b"2.0\n"),
               ("control.tar.gz", tar_bytes([("./control", control)])),
               ("data.tar.gz", tar_bytes([("./usr/bin/VPro", elf(arch))])))
    data = bytearray(b"!<arch>\n")
    for name, content in entries:
        header = f"{name + '/':<16}{0:<12}{0:<6}{0:<6}{'100644':<8}{len(content):<10}`\n"
        data.extend(header.encode("ascii"))
        data.extend(content)
        if len(content) % 2:
            data.extend(b"\n")
    return bytes(data)


def bundle_info(numeric="2.3.4"):
    return plistlib.dumps({"CFBundleVersion": numeric, "CFBundleShortVersionString": numeric})


def r_tarball(numeric="2.3.4"):
    desc = f"Package: vpro\nTitle: VPro R Companion SDK\nVersion: {numeric}\n".encode("utf-8")
    return tar_bytes([("vpro/DESCRIPTION", desc), ("vpro/NAMESPACE", b"# roxygen2\n")])


def asset_fixture(directory, full_version="2.3.4"):
    numeric = full_version.split("-", 1)[0].split("+", 1)[0]
    core_pre, *meta = full_version.split("+", 1)
    deb_ver = (core_pre.replace("-", "~", 1) if "-" in core_pre else core_pre) + (f"+{meta[0]}" if meta else "")
    if "-" in core_pre:
        c_part, p_part = core_pre.split("-", 1)
        rpm_ver = f"{c_part}~{p_part.replace('-', '_')}" + (f"+{meta[0]}" if meta else "")
    else:
        rpm_ver = full_version
    for arch in ("amd64", "arm64"):
        (directory / f"vpro-windows-{arch}.exe").write_bytes(pe(arch))
        (directory / f"vpro-windows-{arch}-installer.exe").write_bytes(b"installer fixture")
        with zipfile.ZipFile(directory / f"vpro-windows-{arch}.zip", "w") as archive:
            archive.writestr("VPro.exe", pe(arch))
        (directory / f"vpro-linux-{arch}.deb").write_bytes(deb(arch, deb_ver))
        (directory / f"vpro-linux-{arch}.rpm").write_bytes(nfpm_rpm(arch, rpm_ver))
        (directory / f"vpro-linux-{arch}.tar.gz").write_bytes(tar_bytes([("VPro", elf(arch))]))
    (directory / "vpro-macos-universal.dmg").write_bytes(b"DMG fixture")
    with zipfile.ZipFile(directory / "vpro-macos-universal.zip", "w") as archive:
        archive.writestr("VPro.app/Contents/MacOS/VPro", universal())
        archive.writestr("VPro.app/Contents/Info.plist", bundle_info(numeric))
    (directory / "vpro-r-sdk.tar.gz").write_bytes(r_tarball(numeric))
    with zipfile.ZipFile(directory / "vpro64-sqlite-bridge.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("Install-VPro64Bridge.ps1", b"# V7mdlImportSQLite.bas installer\r\n")
        archive.writestr("README.txt", b"Import V7mdlImportSQLite.bas into VPro64.accdb\n")
        archive.writestr("V7mdlImportSQLite.bas", b"Attribute VB_Name = \"V7mdlImportSQLite\"\r\nPublic Sub ImportSQLiteProject()\r\nEnd Sub\r\n")
    for group in ("windows-amd64", "windows-arm64", "macos-universal", "linux-amd64", "linux-arm64"):
        names = [name for name in DESKTOP_EXPECTED if name.startswith("vpro-" + group)]
        witness = {"schema": 1, "group": group, "version": full_version, "commit": "abc123",
                   "architectures": ["amd64", "arm64"] if group == "macos-universal" else [group.split("-")[1]],
                   "sha256": {name: hashlib.sha256((directory / name).read_bytes()).hexdigest() for name in names}}
        (directory / f"release-witness-{group}.json").write_text(json.dumps(witness), encoding="utf-8")
    r_witness = {
        "schema": 1,
        "group": "r-sdk",
        "version": full_version,
        "commit": "abc123",
        "architectures": ["source"],
        "sha256": {"vpro-r-sdk.tar.gz": hashlib.sha256((directory / "vpro-r-sdk.tar.gz").read_bytes()).hexdigest()},
    }
    (directory / "release-witness-r-sdk.json").write_text(json.dumps(r_witness), encoding="utf-8")
    vpro64_witness = {
        "schema": 1,
        "group": "vpro64-bridge",
        "version": full_version,
        "commit": "abc123",
        "architectures": ["windows"],
        "sha256": {"vpro64-sqlite-bridge.zip": hashlib.sha256((directory / "vpro64-sqlite-bridge.zip").read_bytes()).hexdigest()},
    }
    (directory / "release-witness-vpro64-bridge.json").write_text(json.dumps(vpro64_witness), encoding="utf-8")


@contextlib.contextmanager
def working_directory(path):
    previous = Path.cwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(previous)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.environment = patch.dict(os.environ, {"RELEASE_VERSION": "v2.3.4", "GITHUB_SHA": "abc123"})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def test_windows_cgo_toolchains_preserve_supported_duckdb_abi(self):
        amd64 = release.windows_toolchain("amd64")
        self.assertEqual(amd64["cc"], "gcc.exe")
        self.assertEqual(amd64["cxx"], "g++.exe")
        self.assertEqual(amd64["directory"], "mingw64")
        self.assertEqual(amd64["sha256"],
                         "3c69305081e4a647144339a936244fcf7d3d9e558319e1ad7be2cd2886d4b6a1")
        self.assertEqual(amd64["url"],
                         "https://github.com/brechtsanders/winlibs_mingw/releases/download/"
                         "16.2.0posix-23.1.3-14.0.0-ucrt-r3/"
                         "winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r3.zip")
        arm64 = release.windows_toolchain("arm64")
        self.assertEqual(arm64["cc"], "aarch64-w64-mingw32-clang.exe")
        self.assertEqual(arm64["cxx"], "aarch64-w64-mingw32-clang++.exe")
        self.assertEqual(arm64["directory"], "llvm-mingw-20261104-ucrt-x86_64")
        self.assertEqual(arm64["sha256"],
                         "552191b5754c49a5a20723276a6fc56541ea1922c4c50b7b669022333fc1b40f")
        for arch in ("386", "AMD64", "", "arm64;bad"):
            with self.subTest(arch=arch), self.assertRaises(ValueError):
                release.windows_toolchain(arch)
        amd64["cc"] = "clang.exe"
        self.assertEqual(release.windows_toolchain("amd64")["cc"], "gcc.exe")

    def test_toolchain_cli_is_shared_with_powershell_setup(self):
        for arch, expected in (("amd64", "gcc.exe"), ("arm64", "aarch64-w64-mingw32-clang.exe")):
            output = io.StringIO()
            with patch("sys.argv", ["release.py", "toolchain", "--arch", arch]), \
                    contextlib.redirect_stdout(output):
                release.main()
            self.assertEqual(json.loads(output.getvalue())["cc"], expected)
        setup = (ROOT / "scripts/release-windows.ps1").read_text()
        self.assertIn("python scripts/release.py toolchain --arch $env:RELEASE_ARCH", setup)
        self.assertIn("if ($LASTEXITCODE -ne 0) { throw 'Target toolchain selection failed' }", setup)
        self.assertIn("Join-Path $bin $toolchain.cc", setup)
        self.assertIn("Join-Path $bin $toolchain.cxx", setup)
        self.assertIn("Get-FileHash $archive -Algorithm SHA256", setup)
        self.assertIn("& $cc -static $probe -o $output", setup)
        self.assertIn("static __thread int tls_probe", setup)
        self.assertIn("python scripts/release.py cpu $output --format pe --arch $env:RELEASE_ARCH", setup)

    def test_windows_static_runtime_linkage_and_pe_import_allowlist(self):
        access_reader = (ROOT / "app/internal/accessreader/reader.go").read_text(encoding="utf-8")
        self.assertIn("#cgo windows LDFLAGS: -static -lm", access_reader)
        win_taskfile = (ROOT / "app/build/windows/Taskfile.yml").read_text(encoding="utf-8")
        self.assertEqual(win_taskfile.count("-extldflags=-static"), 2)
        cross_docker = (ROOT / "app/build/docker/Dockerfile.cross").read_text(encoding="utf-8")
        self.assertIn('-H windowsgui -extldflags=-static', cross_docker)

        # Standard inbox Win32 + UCRT API-set DLLs pass on both amd64 and arm64.
        for arch in ("amd64", "arm64"):
            clean = pe(arch, imports=(
                "KERNEL32.dll", "USER32.dll", "ole32.dll", "msvcrt.dll", "ucrtbase.dll",
                "api-ms-win-crt-runtime-l1-1-0.dll", "ext-ms-win-ntuser-window-l1-1-0.dll",
            ))
            release.cpu(clean, "pe", arch)

        # MinGW / LLVM / VC++ redistributable / third-party runtime DLLs fail closed.
        for forbidden in (
            "libwinpthread-1.dll", "libgcc_s_seh-1.dll", "libstdc++-6.dll",
            "libc++.dll", "libunwind.dll", "vcruntime140.dll", "sqlite3.dll", "duckdb.dll",
        ):
            with self.subTest(forbidden=forbidden):
                pattern = rf"Non-system Windows DLL.*{re.escape(forbidden)}"
                leaked = pe("amd64", imports=("KERNEL32.dll", forbidden))
                with self.assertRaisesRegex(ValueError, pattern):
                    release.cpu(leaked, "pe", "amd64")
                delayed = pe("arm64", imports=("KERNEL32.dll",), delay_imports=(forbidden,))
                with self.assertRaisesRegex(ValueError, pattern):
                    release.cpu(delayed, "pe", "arm64")

        # Packaging rejects NSIS payload or standalone EXE leaking libwinpthread-1.dll.
        (self.root / "app/bin").mkdir(parents=True)
        (self.root / "app/bin/VPro.exe").write_bytes(
            pe("amd64", imports=("KERNEL32.dll", "libwinpthread-1.dll"))
        )
        (self.root / "app/bin/VPro-amd64-installer.exe").write_bytes(b"NSIS")
        with patch.dict(os.environ, {"RELEASE_ARCH": "amd64"}):
            with self.assertRaisesRegex(ValueError, "libwinpthread-1.dll"):
                release.package(self.root, "windows")
        self.assertEqual(list((self.root / "app/dist-artifacts").iterdir()), [])

        # Corrupted / truncated import directory RVA fails closed.
        corrupted = bytearray(pe("amd64"))
        struct.pack_into("<II", corrupted, 128 + 24 + 112 + 8, 0x9999, 40)
        with self.assertRaisesRegex(ValueError, "Unmapped PE RVA"):
            release.cpu(bytes(corrupted), "pe", "amd64")

    def test_windows_target_goarch_reaches_dependencies_without_cross_building_cli(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        windows = workflow.split("  build-windows:", 1)[1].split("  build-macos:", 1)[0]
        job_environment = windows.split("    steps:", 1)[0]
        self.assertNotIn("GOARCH:", job_environment)
        cli = windows.split("      - name: Install Wails CLI", 1)[1].split("      - name:", 1)[0]
        self.assertIn("CGO_ENABLED: '0'", cli)
        self.assertNotIn("GOARCH:", cli)
        build = windows.split("      - name: Build binary and NSIS installer with cgo", 1)[1]
        build = build.split("      - uses:", 1)[0]
        self.assertIn("        env:\n          GOARCH: ${{ matrix.arch }}\n", build)
        self.assertIn('task windows:create:nsis:installer "ARCH=$env:RELEASE_ARCH" CGO_ENABLED=1', build)

    def test_safe_versions(self):
        for raw, expected in (("v2.3.4", ("2.3.4", "2.3.4")),
                              ("0.0.0", ("0.0.0", "0.0.0")),
                              ("65535.1.2", ("65535.1.2", "65535.1.2")),
                              ("v1.2.3-rc.1+build-7", ("1.2.3-rc.1+build-7", "1.2.3"))):
            with self.subTest(raw=raw):
                self.assertEqual(release.version(raw), expected)
        for raw in ("", " v1.2.3", "v1.2.3\n", "01.2.3", "1.2.3-01", "1.2", "65536.0.0",
                    "1.2.3;echo x", '1.2.3"$(touch x)', "1.2.3/other", "1.2.3-",
                    "1.2.3+a..b", "1.2.3-\u00e9", "1.2.3\ninjected=true", "v" + "9" * 129):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                release.version(raw)

    def test_version_outputs_have_no_shell_interpolation(self):
        output = self.root / "outputs"
        with patch.dict(os.environ, {"GITHUB_OUTPUT": str(output)}), \
                patch("sys.argv", ["release.py", "version"]):
            release.main()
        self.assertEqual(output.read_text(), "version=2.3.4\ntag=v2.3.4\nbuild_mode=release\n")

        alpha_output = self.root / "alpha-outputs"
        with patch.dict(os.environ, {"GITHUB_OUTPUT": str(alpha_output), "RELEASE_VERSION": "v2.1.0-alpha.1"}), \
                patch("sys.argv", ["release.py", "version"]):
            release.main()
        self.assertEqual(
            alpha_output.read_text(),
            "version=2.1.0-alpha.1\ntag=v2.1.0-alpha.1\nbuild_mode=alpha\n",
        )
        prerelease_flag_output = self.root / "pre-flag-outputs"
        with patch.dict(os.environ, {"GITHUB_OUTPUT": str(prerelease_flag_output), "RELEASE_VERSION": "v2.1.0", "RELEASE_PRERELEASE": "true"}), \
                patch("sys.argv", ["release.py", "version"]):
            release.main()
        self.assertEqual(
            prerelease_flag_output.read_text(),
            "version=2.1.0\ntag=v2.1.0\nbuild_mode=alpha\n",
        )
        # Release script never emits 'dev' build_mode for CI release artifacts.
        self.assertEqual(release.infer_build_mode("2.0.0-dev"), "alpha")
        self.assertEqual(release.infer_build_mode("2.1.0-rc.2+build.1"), "alpha")
        self.assertEqual(release.infer_build_mode("2.1.0", prerelease=True), "alpha")
        self.assertEqual(release.infer_build_mode("2.1.0"), "release")

    def test_taskfiles_inject_build_identity_ldflags_across_platforms(self):
        for rel in (
            "app/build/windows/Taskfile.yml",
            "app/build/linux/Taskfile.yml",
            "app/build/darwin/Taskfile.yml",
            "app/build/Taskfile.yml",
        ):
            text = (ROOT / rel).read_text(encoding="utf-8")
            with self.subTest(taskfile=rel):
                self.assertIn("-X github.com/boostao/vpro/app/internal/lifecycle.appVersion=", text)
                self.assertIn("-X github.com/boostao/vpro/app/internal/lifecycle.buildMode=", text)
                self.assertIn("-X github.com/boostao/vpro/app/internal/lifecycle.gitCommit=", text)
                if rel != "app/build/Taskfile.yml":
                    self.assertIn('-e RELEASE_VERSION="{{.EFFECTIVE_VERSION}}"', text)
                    self.assertIn('-e RELEASE_BUILD_MODE="{{.EFFECTIVE_BUILD_MODE}}"', text)
                    self.assertIn('-e GITHUB_SHA="{{.EFFECTIVE_COMMIT}}"', text)
        cfg = (ROOT / "app/build/config.yml").read_text(encoding="utf-8")
        self.assertIn('version: "2.0.0"', cfg)
        self.assertNotIn("My Other Data", cfg)

    def test_cpu_witnesses_and_wrong_architectures(self):
        for arch in ("amd64", "arm64"):
            for kind, data in (("pe", pe(arch)), ("elf", elf(arch))):
                release.cpu(data, kind, arch)
                with self.assertRaises(ValueError):
                    release.cpu(data, kind, "arm64" if arch == "amd64" else "amd64")
                for invalid in (b"", data[:20]):
                    with self.assertRaises(ValueError):
                        release.cpu(invalid, kind, arch)
        release.cpu(universal(), "macho", "universal")
        for offset, fmt, value in ((4, ">I", 1), (28, ">I", 0x01000007),
                                   (36, ">I", 128), (132, "<I", 0x0100000C),
                                   (16, ">I", 1000)):
            broken = bytearray(universal())
            struct.pack_into(fmt, broken, offset, value)
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                release.cpu(bytes(broken), "macho", "universal")
        with self.assertRaises(ValueError):
            release.cpu(universal()[128:192], "macho", "universal")

    def test_metadata_is_ci_only_and_versions_reach_all_consumers(self):
        for name in (*release.METADATA, *release.R_METADATA):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, path)
        before = {name: (self.root / name).read_bytes() for name in (*release.METADATA, *release.R_METADATA)}
        with patch.dict(os.environ, {"CI": "false", "GITHUB_ACTIONS": "false"}):
            with self.assertRaisesRegex(ValueError, "CI-only"):
                release.prepare_metadata(self.root)
        self.assertEqual(before, {name: (self.root / name).read_bytes() for name in (*release.METADATA, *release.R_METADATA)})
        with patch.dict(os.environ, {"CI": "true", "GITHUB_ACTIONS": "true",
                                    "GITHUB_WORKSPACE": str(self.root),
                                    "RELEASE_VERSION": "v2.3.4-rc.1+build.7"}), \
                patch.object(release, "run") as command:
            release.prepare_metadata(self.root)
            command.assert_called_once_with("git", "diff", "--exit-code", "HEAD", "--",
                                            *release.METADATA, cwd=self.root)
            release.prepare_metadata(self.root, target="r")
        self.assertIn('version: "2.3.4"', (self.root / "app/build/config.yml").read_text())
        self.assertIn('version: "2.3.4-rc.1+build.7"',
                      (self.root / "app/build/linux/nfpm/nfpm.yaml").read_text())
        self.assertIn('INFO_PRODUCTVERSION "2.3.4"',
                      (self.root / "app/build/windows/nsis/wails_tools.nsh").read_text(encoding="utf-8"))
        info = json.loads((self.root / "app/build/windows/info.json").read_text(encoding="utf-8"))
        self.assertEqual(info["fixed"]["file_version"], "2.3.4")
        self.assertEqual(info["fixed"]["product_version"], "2.3.4")
        self.assertEqual(info["info"]["0409"]["ProductVersion"], "2.3.4-rc.1+build.7")
        self.assertEqual(info["info"]["0409"]["FileVersion"], "2.3.4")
        info = plistlib.loads((self.root / "app/build/darwin/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleVersion"], "2.3.4")
        self.assertEqual(info["CFBundleShortVersionString"], "2.3.4")
        self.assertEqual(info["CFBundleExecutable"], "VPro")
        self.assertIn("Version: 2.3.4\n", (self.root / "r/DESCRIPTION").read_text(encoding="utf-8"))

    def test_metadata_fails_before_writing_on_drift(self):
        with patch.dict(os.environ, {"CI": "true", "GITHUB_ACTIONS": "true",
                                    "GITHUB_WORKSPACE": str(self.root)}), \
                patch.object(release, "run", side_effect=subprocess.CalledProcessError(1, "git")):
            with self.assertRaises(subprocess.CalledProcessError):
                release.prepare_metadata(self.root)
        self.assertEqual(list(self.root.iterdir()), [])
        with self.assertRaises(ValueError):
            release.replace_once('version: "1"\nversion: "2"', r'^version: .*$', 'version: "3"')

    def test_deb_version_cpu_and_container_validation(self):
        path = self.root / "app.deb"
        path.write_bytes(deb("arm64"))
        release.validate_deb(path, "arm64", "2.3.4")
        for arch, full in (("amd64", "2.3.4"), ("arm64", "0.1.0")):
            with self.assertRaises(ValueError):
                release.validate_deb(path, arch, full)
        path.write_bytes(deb("arm64", "2.3.4~rc.1+build-7"))
        release.validate_deb(path, "arm64", "2.3.4-rc.1+build-7")
        for data in (b"", deb("arm64")[:-4], deb("arm64") + b"junk"):
            with self.assertRaises((ValueError, UnicodeError)):
                release.deb_members(data)

    def test_rpm_prerelease_tilde_arch_lead_truncation_and_license(self):
        nfpm_cfg = (ROOT / "app/build/linux/nfpm/nfpm.yaml").read_text(encoding="utf-8")
        self.assertIn('license: "Apache-2.0"', nfpm_cfg)
        self.assertNotIn('license: "MIT"', nfpm_cfg)

        cases = (
            ("2.0.0", "2.0.0"),
            ("2.1.0-alpha.1", "2.1.0~alpha.1"),
            ("2.1.0-alpha-2.1", "2.1.0~alpha_2.1"),
            ("2.3.4-rc.1+build.7", "2.3.4~rc.1+build.7"),
            ("2.3.4-rc.1+build-7", "2.3.4~rc.1+build-7"),
            ("2.3.4+build-7", "2.3.4+build-7"),
        )
        rpm_path = self.root / "pkg.rpm"
        for semver_in, expected_rpm_ver in cases:
            self.assertEqual(release.rpm_version(semver_in), expected_rpm_ver)
            for arch in ("amd64", "arm64"):
                other_arch = "arm64" if arch == "amd64" else "amd64"
                # 1) nFPM/rpmpack format (lead without .arch, metadata header with RPMTAG_ARCH=1022)
                rpm_path.write_bytes(nfpm_rpm(arch, expected_rpm_ver))
                release.validate_rpm(rpm_path, arch, semver_in)
                with self.assertRaisesRegex(ValueError, "rpm header arch mismatch"):
                    release.validate_rpm(rpm_path, other_arch, semver_in)

                # 2) rpmbuild lead format (lead with .x86_64 / .aarch64)
                rpm_path.write_bytes(rpm(arch, expected_rpm_ver))
                release.validate_rpm(rpm_path, arch, semver_in)
                with self.assertRaisesRegex(ValueError, "rpm lead arch mismatch"):
                    release.validate_rpm(rpm_path, other_arch, semver_in)

        # Un-normalized SemVer hyphen in prerelease RPM lead must fail closed.
        rpm_path.write_bytes(rpm("amd64", "2.1.0-alpha.1"))
        with self.assertRaisesRegex(ValueError, "rpm lead name mismatch"):
            release.validate_rpm(rpm_path, "amd64", "2.1.0-alpha.1")

        # Wrong RPMTAG_LICENSE (e.g. MIT) must fail closed.
        rpm_path.write_bytes(nfpm_rpm("amd64", "2.1.0~alpha.1", license_name="MIT"))
        with self.assertRaisesRegex(ValueError, "rpm header License mismatch"):
            release.validate_rpm(rpm_path, "amd64", "2.1.0-alpha.1")

        # Lead without .arch AND without RPMTAG_ARCH header must fail closed.
        no_arch_lead = bytearray(256)
        no_arch_lead[:4] = b"\xed\xab\xee\xdb"
        no_arch_lead[10:30] = b"vpro-2.1.0~alpha.1-1"
        no_arch_lead[96:100] = b"\x8e\xad\xe8\x01"
        rpm_path.write_bytes(bytes(no_arch_lead))
        with self.assertRaisesRegex(ValueError, "rpm lead arch mismatch"):
            release.validate_rpm(rpm_path, "amd64", "2.1.0-alpha.1")

        # 66-byte RPM lead size & truncation guards:
        # a) File truncated at or before 96-byte lead boundary fails closed.
        valid_nfpm = nfpm_rpm("amd64", "2.1.0~alpha.1")
        for cut in (0, 10, 66, 76, 96):
            rpm_path.write_bytes(valid_nfpm[:cut])
            with self.assertRaisesRegex(ValueError, "Expected RPM package"):
                release.validate_rpm(rpm_path, "amd64", "2.1.0-alpha.1")

        # b) Non-NUL-terminated 66-byte lead name buffer (data[10:76]) fails closed.
        overflow_lead = bytearray(valid_nfpm)
        overflow_lead[10:76] = b"v" * 66
        rpm_path.write_bytes(bytes(overflow_lead))
        with self.assertRaisesRegex(ValueError, "Unterminated 66-byte RPM lead name"):
            release.validate_rpm(rpm_path, "amd64", "2.1.0-alpha.1")

        # c) Long prerelease (>65-char prefix) preserves 65-char lead truncation guard while
        #    checking full RPMTAG_VERSION and strict RPMTAG_ARCH.
        long_ver = "2.1.0-alpha." + ("x" * 60)
        long_rpm_ver = "2.1.0~alpha." + ("x" * 60)
        rpm_path.write_bytes(nfpm_rpm("arm64", long_rpm_ver))
        release.validate_rpm(rpm_path, "arm64", long_ver)
        with self.assertRaisesRegex(ValueError, "rpm header arch mismatch"):
            release.validate_rpm(rpm_path, "amd64", long_ver)
        rpm_path.write_bytes(rpm("amd64", long_rpm_ver))
        release.validate_rpm(rpm_path, "amd64", long_ver)

        # d) Boundary version (len(expected_prefix) == 62 -> '.x8' vs '.aa' at 65 chars).
        boundary_ver = "2.1.0-alpha." + ("b" * 43)
        boundary_rpm_ver = "2.1.0~alpha." + ("b" * 43)
        rpm_path.write_bytes(rpm("amd64", boundary_rpm_ver))
        release.validate_rpm(rpm_path, "amd64", boundary_ver)
        with self.assertRaisesRegex(ValueError, "rpm lead arch mismatch"):
            release.validate_rpm(rpm_path, "arm64", boundary_ver)

        # e) Real wails3 nFPM end-to-end packaging check when wails3 is installed locally.
        wails_bin = (
            shutil.which("wails3")
            or str(Path.home() / "go/bin/wails3")
            if (Path.home() / "go/bin/wails3").is_file()
            else shutil.which("wails3")
        )
        if wails_bin:
            pkg_dir = self.root / "wails3-nfpm"
            (pkg_dir / "bin").mkdir(parents=True)
            (pkg_dir / "build/linux/nfpm/scripts").mkdir(parents=True)
            shutil.copyfile(ROOT / "app/build/appicon.png", pkg_dir / "build/appicon.png")
            shutil.copyfile(ROOT / "app/build/linux/VPro.desktop", pkg_dir / "build/linux/VPro.desktop")
            shutil.copyfile(
                ROOT / "app/build/linux/nfpm/scripts/postinstall.sh",
                pkg_dir / "build/linux/nfpm/scripts/postinstall.sh",
            )
            stamped_nfpm = nfpm_cfg.replace('version: "2.0.0"', 'version: "2.1.0-alpha.1"', 1)
            (pkg_dir / "nfpm.yaml").write_text(stamped_nfpm, encoding="utf-8")
            for arch in ("amd64", "arm64"):
                (pkg_dir / "bin/VPro").write_bytes(elf(arch))
                (pkg_dir / "bin/VPro").chmod(0o755)
                out_dir = pkg_dir / f"out-{arch}"
                out_dir.mkdir()
                env = {
                    **os.environ,
                    "GOARCH": arch,
                    "GIT_COMMITTER_NAME": "VPro",
                    "GIT_COMMITTER_EMAIL": "noreply@github.com",
                }
                for fmt in ("rpm", "deb"):
                    subprocess.run(
                        [wails_bin, "tool", "package", "-name", "VPro", "-format", fmt, "-config", "./nfpm.yaml", "-out", str(out_dir)],
                        cwd=pkg_dir,
                        env=env,
                        check=True,
                        stdout=subprocess.DEVNULL,
                    )
                built_rpm = next(out_dir.glob("*.rpm"))
                built_deb = next(out_dir.glob("*.deb"))
                release.validate_rpm(built_rpm, arch, "2.1.0-alpha.1")
                release.validate_deb(built_deb, arch, "2.1.0-alpha.1")
                other = "arm64" if arch == "amd64" else "amd64"
                with self.assertRaisesRegex(ValueError, "arch mismatch"):
                    release.validate_rpm(built_rpm, other, "2.1.0-alpha.1")

    def test_manifest_exact_contract_and_download_verification(self):
        asset_fixture(self.root)
        self.assertEqual(release.REQUIRED, set(EXPECTED))
        with working_directory(self.root):
            release.manifest(self.root)
        content = (self.root / "SHA256SUMS.txt").read_text()
        self.assertEqual(list(release.parse_manifest(content)), list(EXPECTED))
        for line, name in zip(content.splitlines(), EXPECTED):
            self.assertEqual(line, hashlib.sha256((self.root / name).read_bytes()).hexdigest() + "  " + name)
        paths = (self.root / "release-assets.txt").read_text().splitlines()
        self.assertEqual({Path(path).name for path in paths}, set(EXPECTED) | {"SHA256SUMS.txt"})
        download = self.root / "download"
        download.mkdir()
        for name in (*EXPECTED, "SHA256SUMS.txt"):
            shutil.copyfile(self.root / name, download / name)
        release.verify(download, self.root / "SHA256SUMS.txt")
        (download / EXPECTED[0]).write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
            release.verify(download, self.root / "SHA256SUMS.txt")

    def test_missing_extra_empty_and_stale_witnesses_block_manifest(self):
        for problem in ("missing", "extra", "empty", "commit", "version", "cpu", "hash"):
            with self.subTest(problem=problem), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                asset_fixture(directory)
                if problem == "missing":
                    (directory / EXPECTED[0]).unlink()
                elif problem == "extra":
                    (directory / "unwanted.zip").write_bytes(b"x")
                elif problem == "empty":
                    (directory / EXPECTED[0]).write_bytes(b"")
                else:
                    path = directory / "release-witness-windows-arm64.json"
                    witness = json.loads(path.read_text())
                    key = {"cpu": "architectures", "hash": "sha256"}.get(problem, problem)
                    witness[key] = "wrong"
                    path.write_text(json.dumps(witness))
                with self.assertRaises(ValueError), working_directory(directory):
                    release.manifest(directory)
                self.assertFalse((directory / "SHA256SUMS.txt").exists())
                self.assertFalse((directory / "release-assets.txt").exists())

    def test_forged_receipt_does_not_hide_wrong_portable_cpu(self):
        asset_fixture(self.root)
        path = self.root / "vpro-linux-arm64.tar.gz"
        path.write_bytes(tar_bytes([("VPro", elf("amd64"))]))
        receipt = self.root / "release-witness-linux-arm64.json"
        witness = json.loads(receipt.read_text())
        witness["sha256"][path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        receipt.write_text(json.dumps(witness))
        with self.assertRaisesRegex(ValueError, "ELF CPU mismatch"):
            release.manifest(self.root)

    def test_release_tag_source_absent_lightweight_and_annotated(self):
        commit = "a" * 40
        tag = "refs/tags/v2.3.4"
        self.assertEqual(release.validate_source_tag("", "v2.3.4", commit), "absent")
        self.assertEqual(release.validate_source_tag(f"{commit}\t{tag}\n", "v2.3.4", commit), "matching")
        annotated = f"{'b' * 40}\t{tag}\n{commit}\t{tag}^{{}}\n"
        self.assertEqual(release.validate_source_tag(annotated, "v2.3.4", commit), "matching")
        for output in (f"{'c' * 40}\t{tag}\n",
                       f"{commit}\t{tag}\n{'c' * 40}\t{tag}^{{}}\n"):
            with self.assertRaisesRegex(ValueError, "different source"):
                release.validate_source_tag(output, "v2.3.4", commit)

    def test_release_tag_source_malformed_or_ambiguous_refuses(self):
        commit = "a" * 40
        tag = "refs/tags/v2.3.4"
        for output in ("bad", f"invalid\t{tag}\n", f"{commit}\trefs/tags/v1.0.0\n",
                       f"{commit}\t{tag}^{{}}\n",
                       f"{commit}\t{tag}\n{commit}\t{tag}\n"):
            with self.assertRaises(ValueError):
                release.validate_source_tag(output, "v2.3.4", commit)
        with self.assertRaisesRegex(ValueError, "checkout commit"):
            release.validate_source_tag("", "v2.3.4", "unknown")

    def test_release_tag_source_lookup_failure_and_version_mismatch_refuse(self):
        with patch.dict(os.environ, {"RELEASE_TAG": "v2.3.4"}), \
                patch.object(release.subprocess, "run",
                             side_effect=subprocess.CalledProcessError(1, "git")):
            with self.assertRaises(subprocess.CalledProcessError):
                release.check_source_tag()
        with patch.dict(os.environ, {"RELEASE_TAG": "v2.3.3"}), \
                patch.object(release.subprocess, "run") as lookup:
            with self.assertRaisesRegex(ValueError, "validated version"):
                release.check_source_tag()
            lookup.assert_not_called()
        with patch.dict(os.environ, {"RELEASE_TAG": "v2.3.4", "GITHUB_SHA": "a" * 40}), \
                patch.object(release.subprocess, "run",
                             return_value=subprocess.CompletedProcess([], 0, stdout="", stderr="")) as lookup, \
                contextlib.redirect_stdout(io.StringIO()):
            release.check_source_tag()
            self.assertEqual(lookup.call_args.args[0],
                             ["git", "ls-remote", "--tags", "origin",
                              "refs/tags/v2.3.4", "refs/tags/v2.3.4^{}"])
            self.assertTrue(lookup.call_args.kwargs["check"])

    def test_strict_manifest_and_remote_assets(self):
        content = "".join("a" * 64 + "  " + name + "\n" for name in EXPECTED)
        for broken in (content + content.splitlines()[0] + "\n",
                       content.replace(EXPECTED[0], EXPECTED[1]),
                       content.replace(EXPECTED[0], "../secret"),
                       content.replace("a" * 64, "not-a-hash", 1)):
            with self.assertRaises(ValueError):
                release.parse_manifest(broken)
        path = self.root / "remote.json"
        names = [*EXPECTED, "SHA256SUMS.txt"]
        path.write_text(json.dumps({"assets": [{"name": name} for name in names]}))
        release.remote(path)
        for bad in (names[:-1], names + ["unknown"], names[:-1] + [names[0]]):
            path.write_text(json.dumps({"assets": [{"name": name} for name in bad]}))
            with self.assertRaises(ValueError):
                release.remote(path)

    def test_windows_inspects_nsis_payload_not_launcher_cpu(self):
        (self.root / "app/bin").mkdir(parents=True)
        (self.root / "app/bin/VPro.exe").write_bytes(pe("arm64"))
        (self.root / "app/bin/VPro-arm64-installer.exe").write_bytes(b"x86 NSIS launcher")

        def extract(*args, **kwargs):
            self.assertEqual(args[:3], ("7z", "x", "-y"))
            self.assertTrue(args[3].endswith("VPro-arm64-installer.exe"))
            (Path(args[4][2:]) / "VPro.exe").write_bytes(pe("arm64"))

        with patch.dict(os.environ, {"RELEASE_ARCH": "arm64"}), patch.object(release, "run", side_effect=extract):
            release.package(self.root, "windows")
        self.assertEqual({path.name for path in (self.root / "app/dist-artifacts").iterdir()},
                         {"vpro-windows-arm64.exe", "vpro-windows-arm64.zip",
                          "vpro-windows-arm64-installer.exe", "release-witness-windows-arm64.json"})

    def test_packaging_command_failure_never_creates_witness(self):
        (self.root / "app/bin").mkdir(parents=True)
        (self.root / "app/bin/VPro.exe").write_bytes(pe("amd64"))
        (self.root / "app/bin/VPro-amd64-installer.exe").write_bytes(b"NSIS")
        with patch.dict(os.environ, {"RELEASE_ARCH": "amd64"}), \
                patch.object(release, "run", side_effect=subprocess.CalledProcessError(1, "7z")):
            with self.assertRaises(subprocess.CalledProcessError):
                release.package(self.root, "windows")
        self.assertEqual(list((self.root / "app/dist-artifacts").iterdir()), [])

    def test_linux_native_packaging_requires_all_formats(self):
        (self.root / "app/bin").mkdir(parents=True)
        (self.root / "app/bin/VPro").write_bytes(elf("arm64"))
        (self.root / "app/bin/VPro.deb").write_bytes(deb("arm64"))
        (self.root / "app/bin/VPro.rpm").write_bytes(rpm("arm64"))

        with patch.dict(os.environ, {"RELEASE_ARCH": "arm64"}):
            release.package(self.root, "linux")
        self.assertEqual({path.name for path in (self.root / "app/dist-artifacts").iterdir()},
                         {"vpro-linux-arm64.deb", "vpro-linux-arm64.rpm",
                          "vpro-linux-arm64.tar.gz", "release-witness-linux-arm64.json"})

    def test_linux_invalid_rpm_is_fatal(self):
        (self.root / "app/bin").mkdir(parents=True)
        (self.root / "app/bin/VPro").write_bytes(elf("amd64"))
        (self.root / "app/bin/VPro.deb").write_bytes(deb("amd64"))
        (self.root / "app/bin/VPro.rpm").write_bytes(b"not-an-rpm")
        with patch.dict(os.environ, {"RELEASE_ARCH": "amd64"}):
            with self.assertRaisesRegex(ValueError, "Expected RPM package"):
                release.package(self.root, "linux")
        self.assertEqual(list((self.root / "app/dist-artifacts").iterdir()), [])

    def test_missing_or_ambiguous_linux_output_is_fatal(self):
        app_root = self.root / "app"
        (app_root / "bin").mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, "exactly one"):
            release.unique_output(app_root, ".deb")
        for name in ("one.deb", "two.deb"):
            (app_root / "bin" / name).write_bytes(b"x")
        with self.assertRaisesRegex(ValueError, "exactly one"):
            release.unique_output(app_root, ".deb")

    def test_mac_dmg_payload_and_detach_even_on_validation_failure(self):
        bundle = self.root / "app/bin/VPro.app/Contents"
        (bundle / "MacOS").mkdir(parents=True)
        (bundle / "MacOS/VPro").write_bytes(universal())
        (bundle / "Info.plist").write_bytes(bundle_info())
        (self.root / "app/bin/VPro.dmg").write_bytes(b"dmg")

        def mount(*args, **kwargs):
            if args[1] == "attach":
                directory = Path(args[args.index("-mountpoint") + 1])
                (directory / "VPro.app/Contents/MacOS").mkdir(parents=True)
                (directory / "VPro.app/Contents/MacOS/VPro").write_bytes(pe("amd64"))

        with patch.object(release, "run", side_effect=mount) as commands:
            with self.assertRaisesRegex(ValueError, "fat Mach-O"):
                release.package(self.root, "macos")
        self.assertEqual(commands.call_args_list[-1].args[:2], ("hdiutil", "detach"))
        self.assertEqual(list((self.root / "app/dist-artifacts").iterdir()), [])

    def test_mac_success_validates_both_archives_and_detach_failure_is_fatal(self):
        bundle = self.root / "app/bin/VPro.app/Contents"
        (bundle / "MacOS").mkdir(parents=True)
        (bundle / "MacOS/VPro").write_bytes(universal())
        (bundle / "Info.plist").write_bytes(bundle_info())
        (self.root / "app/bin/VPro.dmg").write_bytes(b"dmg")

        def tools(*args, **kwargs):
            if args[0:2] == ("hdiutil", "attach"):
                mount = Path(args[args.index("-mountpoint") + 1])
                shutil.copytree(bundle.parent, mount / "VPro.app")
            elif args[0] == "ditto":
                with zipfile.ZipFile(args[-1], "w") as archive:
                    archive.writestr("VPro.app/Contents/MacOS/VPro", universal())
                    archive.writestr("VPro.app/Contents/Info.plist", bundle_info())

        with patch.object(release, "run", side_effect=tools):
            release.package(self.root, "macos")
        self.assertEqual({path.name for path in (self.root / "app/dist-artifacts").iterdir()},
                         {"vpro-macos-universal.dmg", "vpro-macos-universal.zip",
                          "release-witness-macos-universal.json"})
        for path in (self.root / "app/dist-artifacts").iterdir():
            path.unlink()
        (self.root / "app/dist-artifacts").rmdir()

        def detach_failure(*args, **kwargs):
            if args[:2] == ("hdiutil", "detach"):
                raise subprocess.CalledProcessError(1, "hdiutil")
            tools(*args, **kwargs)

        with patch.object(release, "run", side_effect=detach_failure):
            with self.assertRaises(subprocess.CalledProcessError):
                release.package(self.root, "macos")
        self.assertEqual(list((self.root / "app/dist-artifacts").iterdir()), [])

    def test_r_sdk_packaging_and_r_only_scope(self):
        (self.root / "r").mkdir(parents=True)
        (self.root / "r/vpro_2.3.4.tar.gz").write_bytes(r_tarball("2.3.4"))
        with patch.dict(os.environ, {"RELEASE_VERSION": "r-v2.3.4", "RELEASE_SCOPE": "r-only"}):
            release.package(self.root, "r", scope="r-only")
            dist_dir = self.root / "r/dist-artifacts"
            self.assertEqual(
                {p.name for p in dist_dir.iterdir()},
                {"vpro-r-sdk.tar.gz", "release-witness-r-sdk.json"},
            )
            with working_directory(dist_dir):
                release.manifest(dist_dir, scope="r-only")
            remote_json = self.root / "r-remote.json"
            remote_json.write_text(json.dumps({
                "assets": [{"name": "vpro-r-sdk.tar.gz"}, {"name": "SHA256SUMS.txt"}],
            }))
            release.remote(remote_json, scope="r-only")
            downloaded = self.root / "r-downloaded"
            downloaded.mkdir()
            for name in ("vpro-r-sdk.tar.gz", "SHA256SUMS.txt"):
                shutil.copyfile(dist_dir / name, downloaded / name)
            release.verify(downloaded, dist_dir / "SHA256SUMS.txt", scope="r-only")

    def test_release_manifest_generation_channel_merging_and_validation(self):
        asset_fixture(self.root)
        with working_directory(self.root):
            release.manifest(self.root)
        stable_path = self.root / "release-manifest.json"
        doc = release.release_manifest(
            self.root,
            stable_path,
            published_at="2026-11-12T12:00:00Z",
            root=ROOT,
        )
        self.assertEqual(doc["schemaVersion"], 1)
        self.assertEqual(doc["repository"], "Boostao/vpro")
        self.assertEqual(doc["defaultChannel"], "stable")
        self.assertIsNone(doc["channels"]["preview"])
        stable = doc["channels"]["stable"]
        self.assertEqual(stable["tag"], "v2.3.4")
        self.assertEqual(stable["version"], "2.3.4")
        self.assertIs(stable["prerelease"], False)
        self.assertIs(stable["unsignedNotice"], True)
        self.assertEqual(
            stable["sha256sumsUrl"],
            "https://github.com/Boostao/vpro/releases/download/v2.3.4/SHA256SUMS.txt",
        )
        self.assertIn("BECdb v13", stable["standards"]["becVersion"])
        self.assertIn("BCPlantTaxonomy v19", stable["standards"]["taxonomyVersion"])
        self.assertEqual(stable["standards"]["lmh25Edition"], "LMH25 (2023)")
        self.assertEqual([a["name"] for a in stable["assets"]], sorted([*EXPECTED, "SHA256SUMS.txt"]))
        for entry in stable["assets"]:
            expected_bytes = (self.root / entry["name"]).read_bytes()
            self.assertEqual(entry["sizeBytes"], len(expected_bytes))
            self.assertEqual(entry["sha256"], hashlib.sha256(expected_bytes).hexdigest())

        # Verify remote & downloaded release verification with release-manifest.json attached.
        remote_json = self.root / "remote-with-manifest.json"
        remote_names = [*EXPECTED, "SHA256SUMS.txt", "release-manifest.json"]
        remote_json.write_text(json.dumps({"assets": [{"name": n} for n in remote_names]}))
        release.remote(remote_json, require_release_manifest=True)
        remote_without = self.root / "remote-without-manifest.json"
        remote_without.write_text(json.dumps({"assets": [{"name": n} for n in remote_names[:-1]]}))
        with self.assertRaisesRegex(ValueError, "missing release-manifest.json"):
            release.remote(remote_without, require_release_manifest=True)

        downloaded = self.root / "downloaded-with-manifest"
        downloaded.mkdir()
        for name in remote_names:
            shutil.copyfile(self.root / name, downloaded / name)
        release.verify(downloaded, self.root / "SHA256SUMS.txt", release_manifest_path=stable_path)
        (downloaded / "release-manifest.json").write_text("{}", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "differs from validated manifest"):
            release.verify(downloaded, self.root / "SHA256SUMS.txt", release_manifest_path=stable_path)

        # Merge a preview RC release on top of the existing stable release-manifest.json via CLI.
        rc_dir = self.root / "rc-assets"
        rc_dir.mkdir()
        with patch.dict(os.environ, {"RELEASE_VERSION": "v2.4.0-rc.1", "RELEASE_PRERELEASE": "true"}):
            asset_fixture(rc_dir, "2.4.0-rc.1")
            with working_directory(rc_dir):
                release.manifest(rc_dir)
            with self.assertRaisesRegex(ValueError, "cannot publish to stable"):
                release.release_manifest(rc_dir, self.root / "bad.json", channel="stable")
            merged_path = self.root / "merged-manifest.json"
            with patch("sys.argv", [
                "release.py", "release-manifest", str(rc_dir),
                "--output", str(merged_path),
                "--base-manifest", str(stable_path),
                "--published-at", "2026-11-13T08:30:00Z",
            ]):
                release.main()
        merged = json.loads(merged_path.read_text(encoding="utf-8"))
        release.validate_release_manifest(merged)
        self.assertEqual(merged["channels"]["stable"]["tag"], "v2.3.4")
        self.assertIs(merged["channels"]["stable"]["prerelease"], False)
        self.assertEqual(merged["channels"]["preview"]["tag"], "v2.4.0-rc.1")
        self.assertIs(merged["channels"]["preview"]["prerelease"], True)

        # Repository site/release-manifest.json must satisfy strict schema validation.
        repo_manifest = json.loads((ROOT / "site/release-manifest.json").read_text(encoding="utf-8"))
        release.validate_release_manifest(repo_manifest)

    def test_sync_release_manifest_hydrates_non_draft_channels_and_skips_drafts(self):
        asset_fixture(self.root)
        with working_directory(self.root):
            release.manifest(self.root)
        stable_manifest = self.root / "stable-release-manifest.json"
        release.release_manifest(
            self.root,
            stable_manifest,
            published_at="2026-11-13T17:00:00Z",
            root=ROOT,
        )

        rc_dir = self.root / "sync-rc"
        rc_dir.mkdir()
        with patch.dict(os.environ, {"RELEASE_VERSION": "v2.4.0-rc.1", "RELEASE_PRERELEASE": "true"}):
            asset_fixture(rc_dir, "2.4.0-rc.1")
            with working_directory(rc_dir):
                release.manifest(rc_dir)
            rc_manifest = self.root / "rc-release-manifest.json"
            release.release_manifest(
                rc_dir,
                rc_manifest,
                published_at="2026-11-13T18:00:00Z",
                root=ROOT,
            )

        complete_assets = [{"name": n} for n in (*EXPECTED, "SHA256SUMS.txt", "release-manifest.json")]
        desktop_only_assets = [{"name": n} for n in (*DESKTOP_EXPECTED, "SHA256SUMS.txt", "release-manifest.json")]
        releases_feed = self.root / "releases-feed.json"
        releases_feed.write_text(json.dumps([
            {"tag_name": "v9.9.9-draft", "draft": True, "prerelease": False, "assets": complete_assets},
            {"tag_name": "r-v2.4.1", "draft": False, "prerelease": False, "assets": [{"name": "vpro-r-sdk.tar.gz"}, {"name": "SHA256SUMS.txt"}]},
            {"tag_name": "v2.5.0-incomplete", "draft": False, "prerelease": False, "assets": [{"name": "SHA256SUMS.txt"}]},
            {"tag_name": "v2.4.0-rc.1", "draft": False, "prerelease": True, "assets": complete_assets},
            {"tag_name": "v2.3.4", "draft": False, "prerelease": False, "assets": desktop_only_assets},
        ]), encoding="utf-8")

        # Simulate legacy desktop-only manifest from Boostao/vpro_wails without R tarball.
        legacy_stable_doc = json.loads(stable_manifest.read_text(encoding="utf-8"))
        legacy_stable_doc["repository"] = "Boostao/vpro_wails"
        legacy_stable_doc["channels"]["stable"]["sha256sumsUrl"] = (
            legacy_stable_doc["channels"]["stable"]["sha256sumsUrl"].replace("Boostao/vpro/", "Boostao/vpro_wails/")
        )
        legacy_stable_doc["channels"]["stable"]["assets"] = [
            {**a, "url": a["url"].replace("Boostao/vpro/", "Boostao/vpro_wails/")}
            for a in legacy_stable_doc["channels"]["stable"]["assets"]
            if a["name"] != "vpro-r-sdk.tar.gz"
        ]

        manifests_by_tag = {
            "v2.3.4": json.dumps(legacy_stable_doc),
            "v2.4.0-rc.1": rc_manifest.read_text(encoding="utf-8"),
        }
        synced_out = self.root / "synced-release-manifest.json"
        synced = release.sync_release_manifest(
            synced_out,
            base_manifest=ROOT / "site/release-manifest.json",
            releases_json=releases_feed,
            asset_loader=lambda tag, _: manifests_by_tag[tag],
        )
        self.assertEqual(synced["repository"], "Boostao/vpro")
        self.assertEqual(synced["channels"]["stable"]["tag"], "v2.3.4")
        self.assertTrue(synced["channels"]["stable"]["sha256sumsUrl"].startswith("https://github.com/Boostao/vpro/"))
        self.assertEqual(synced["channels"]["preview"]["tag"], "v2.4.0-rc.1")

        # Empty/draft-only feed clears channels cleanly instead of leaving dead download URLs.
        draft_only_feed = self.root / "draft-only.json"
        draft_only_feed.write_text(json.dumps([
            {"tag_name": "v0.1.0-demo", "draft": True, "prerelease": False, "assets": complete_assets},
        ]), encoding="utf-8")
        cleared_out = self.root / "cleared-release-manifest.json"
        cleared = release.sync_release_manifest(
            cleared_out,
            base_manifest=synced_out,
            releases_json=draft_only_feed,
            asset_loader=lambda tag, _: manifests_by_tag[tag],
        )
        self.assertIsNone(cleared["channels"]["stable"])
        self.assertIsNone(cleared["channels"]["preview"])

    def test_whats_new_gate_for_full_and_r_only_scopes(self):
        repo_fixture = self.root / "whats-new-repo"
        (repo_fixture / "docs-src").mkdir(parents=True)
        (repo_fixture / "app/resources").mkdir(parents=True)
        entries = [
            {
                "version": "2.1.0-alpha.1",
                "date": "2026-11-19",
                "channel": "preview",
                "highlights": ["Updated field plot validation before cloud sync."],
            }
        ]
        (repo_fixture / "docs-src/whats_new.json").write_text(json.dumps(entries), encoding="utf-8")
        (repo_fixture / "app/resources/help_bundle.json").write_text(
            json.dumps({"schemaVersion": 1, "whatsNew": entries}),
            encoding="utf-8",
        )
        with patch.dict(os.environ, {"RELEASE_VERSION": "v2.1.0-alpha.1", "RELEASE_SCOPE": "full"}):
            release.validate_whats_new(repo_fixture, scope="full")
            with patch("sys.argv", ["release.py", "whats-new", "--scope", "full", "--root", str(repo_fixture)]):
                release.main()

        # Numeric entry ("2.1.0") also satisfies prerelease "2.1.0-alpha.1".
        numeric_entries = [{**entries[0], "version": "2.1.0"}]
        (repo_fixture / "docs-src/whats_new.json").write_text(json.dumps(numeric_entries), encoding="utf-8")
        (repo_fixture / "app/resources/help_bundle.json").write_text(
            json.dumps({"schemaVersion": 1, "whatsNew": numeric_entries}),
            encoding="utf-8",
        )
        with patch.dict(os.environ, {"RELEASE_VERSION": "v2.1.0-alpha.1", "RELEASE_SCOPE": "full"}):
            release.validate_whats_new(repo_fixture, scope="full")

        # Stale version at index 0 fails closed on full desktop release, but r-only skips desktop whats_new.
        with patch.dict(os.environ, {"RELEASE_VERSION": "v2.2.0", "RELEASE_SCOPE": "full"}):
            with self.assertRaisesRegex(ValueError, r"whats_new\.json\[0\]\.version"):
                release.validate_whats_new(repo_fixture, scope="full")
        with patch.dict(os.environ, {"RELEASE_VERSION": "r-v2.2.0", "RELEASE_SCOPE": "r-only"}):
            release.validate_whats_new(repo_fixture, scope="r-only")

        # Drift between docs-src/whats_new.json and app/resources/help_bundle.json fails closed.
        (repo_fixture / "app/resources/help_bundle.json").write_text(
            json.dumps({"schemaVersion": 1, "whatsNew": []}),
            encoding="utf-8",
        )
        with patch.dict(os.environ, {"RELEASE_VERSION": "v2.1.0-alpha.1", "RELEASE_SCOPE": "full"}):
            with self.assertRaisesRegex(ValueError, "out of sync"):
                release.validate_whats_new(repo_fixture, scope="full")

    def test_linux_and_windows_taskfile_signing_and_once_invariants(self):
        nsi = (ROOT / "app/build/windows/nsis/project.nsi").read_text(encoding="utf-8")
        self.assertIn('OutFile "..\\..\\..\\bin\\${INFO_PROJECTNAME}-${ARCH}-installer.exe"', nsi)
        win_tf = (ROOT / "app/build/windows/Taskfile.yml").read_text(encoding="utf-8")
        sign_installer = win_tf.split("  sign:installer:", 1)[1]
        self.assertNotIn("build/windows/nsis/{{.APP_NAME}}-installer.exe", win_tf)
        self.assertIn('--input "bin/{{.APP_NAME}}-{{.ARCH}}-installer.exe"', sign_installer)
        self.assertIn("ARCH: '{{.ARCH | default ARCH}}'", sign_installer)

        linux_tf = (ROOT / "app/build/linux/Taskfile.yml").read_text(encoding="utf-8")
        linux_build = linux_tf.split("  build:", 1)[1].split("  build:native:", 1)[0]
        self.assertIn("    run: once\n", linux_build)
        create_rpm = linux_tf.split("  create:rpm:", 1)[1].split("  create:aur:", 1)[0]
        for forwarded in (
            "ARCH: '{{.ARCH}}'",
            "VERSION: '{{.VERSION}}'",
            "BUILD_MODE: '{{.BUILD_MODE}}'",
            "GIT_COMMIT: '{{.GIT_COMMIT}}'",
            "EXTRA_TAGS: '{{.EXTRA_TAGS}}'",
        ):
            self.assertIn(forwarded, create_rpm)

        # Ensure scripts/release.py contains no Python 3.12-only nested quotes inside f-strings,
        # remaining valid on Python 3.10-3.13.
        release_src = (ROOT / "scripts/release.py").read_text(encoding="utf-8")
        for line_no, line in enumerate(release_src.splitlines(), 1):
            for match in re.finditer(r'\bf"([^"]*)"', line):
                # Inside f"...", any double quote before the closing quote would have split match.group(1)
                # leaving unclosed '{' inside group(1).
                expr = match.group(1)
                self.assertEqual(
                    expr.count("{") - expr.count("{{"),
                    expr.count("}") - expr.count("}}"),
                    f"Nested double-quote inside double-quoted f-string at release.py:{line_no}: {line}",
                )

    def test_workflow_contract(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        self.assertNotIn("|| true", workflow)
        self.assertNotIn("continue-on-error", workflow)
        self.assertNotIn("AppImage", workflow)
        self.assertIn("Linux amd64/arm64 rpm, deb and tar.gz", workflow)
        self.assertNotIn("darwin:package:dmg", workflow)
        self.assertNotIn("macos-14", workflow)
        self.assertIn("runs-on: macos-15-intel", workflow)
        self.assertNotIn("go-version: '1.26'", workflow)
        self.assertEqual(workflow.count("go-version: '1.27.4'"), 4)
        validate_job = workflow.split("  validate:", 1)[1].split("  build-windows:", 1)[0]
        self.assertIn("python3 scripts/check-dep-lockstep.py --strict-brand", validate_job)
        self.assertIn("python3 scripts/check-okf-hygiene.py", validate_job)
        self.assertIn("node scripts/build-docs-src.mjs", validate_job)
        self.assertIn("git diff --exit-code -- docs-src app/resources/help_bundle.json", validate_job)
        self.assertIn('python3 scripts/release.py whats-new --scope "$RELEASE_SCOPE"', validate_job)
        self.assertIn("npm test", validate_job)
        self.assertIn("npm run check", validate_job)
        self.assertIn("go test -skip 'Scale|Perf|71k'", validate_job)
        deploy_pages_job = workflow.split("  deploy-pages:", 1)[1]
        self.assertIn("RELEASE_VERSION: ${{ needs.validate.outputs.version }}", deploy_pages_job)
        self.assertIn("python scripts/release.py metadata --target r --scope r-only", deploy_pages_job)
        self.assertIn("python scripts/release.py metadata --target r --scope full", deploy_pages_job)
        self.assertIn("task darwin:package:universal", workflow)
        self.assertIn("task darwin:create:dmg", workflow)
        self.assertIn("runner: ubuntu-24.04-arm", workflow)
        self.assertIn("windows:create:nsis:installer", workflow)
        self.assertIn('CGO_ENABLED=1', workflow)
        self.assertIn("task linux:create:deb linux:create:rpm", workflow)
        self.assertNotIn("${{ inputs.version }}", workflow.split("run:", 1)[-1])
        self.assertEqual(workflow.count("contents: write"), 1)
        self.assertIn("contents: read", workflow)
        self.assertIn("python scripts/release.py sync-release-manifest", workflow)
        self.assertIn("python scripts/release.py manifest release-assets", workflow)
        self.assertIn("python scripts/release.py release-manifest release-assets --output release-assets/release-manifest.json", workflow)
        self.assertIn("python scripts/release.py remote release-remote.json --require-release-manifest", workflow)
        self.assertIn("python scripts/release.py verify release-downloaded --manifest release-assets/SHA256SUMS.txt --release-manifest release-assets/release-manifest.json", workflow)
        self.assertIn("  build-r:", workflow)
        self.assertIn("scope:", workflow)
        self.assertIn("pkgdown::build_site()", workflow)
        self.assertIn("name: github-pages", workflow)
        self.assertIn("actions/configure-pages@v6", workflow)
        pages = (ROOT / ".github/workflows/pages.yml").read_text()
        self.assertNotIn("enablement: true", pages)
        self.assertNotIn("path: 'docs'", pages)
        self.assertIn("node-version: '24'", pages)
        self.assertIn("python scripts/release.py sync-release-manifest", pages)
        self.assertIn("node scripts/build-docs-src.mjs && node site/build.mjs", pages)
        self.assertIn("pkgdown::build_site()", pages)
        self.assertIn("path: 'site/dist'", pages)
        ci = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn("dorny/paths-filter@v4", ci)
        self.assertIn("postgres:16", ci)
        self.assertIn("rsidecar-integration:", ci)
        self.assertIn("test -s site/dist/dev/index.html", ci)
        self.assertIn("python scripts/release.py sync-dev-manifest --output site/dev-manifest.json --keep 5", pages)
        self.assertIn("test -s site/dist/dev/index.html", pages)
        self.assertIn("python scripts/release.py sync-dev-manifest --output site/dev-manifest.json --keep 5", deploy_pages_job)

    def test_dev_plan_ci_gate_app_change_filter_and_force_override(self):
        from datetime import datetime, timezone

        # Leading-zero commit SHA proves the 'g' prefix prevents SemVer numeric leading-zero rejection.
        head_sha = "0123456789abcdef0123456789abcdef01234567"
        prev_sha = "fedcba9876543210fedcba9876543210fedcba98"
        fixed_now = datetime(2026, 11, 20, 9, 0, 0, tzinfo=timezone.utc)

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            failing_ci = tmp_path / "ci-fail.json"
            failing_ci.write_text(json.dumps({
                "workflow_runs": [{"status": "completed", "conclusion": "failure"}],
            }), encoding="utf-8")
            passing_ci = tmp_path / "ci-pass.json"
            passing_ci.write_text(json.dumps({
                "workflow_runs": [{"status": "completed", "conclusion": "success"}],
            }), encoding="utf-8")
            releases_same = tmp_path / "rel-same.json"
            releases_same.write_text(json.dumps([{
                "tag_name": "dev-20261119-r10-g0123456",
                "draft": False,
                "prerelease": True,
                "published_at": "2026-11-19T09:05:00Z",
                "target_commitish": head_sha,
            }]), encoding="utf-8")
            releases_prev = tmp_path / "rel-prev.json"
            releases_prev.write_text(json.dumps([{
                "tag_name": "dev-20261119-r10-gfedcba9",
                "draft": False,
                "prerelease": True,
                "published_at": "2026-11-19T09:05:00Z",
                "target_commitish": prev_sha,
            }]), encoding="utf-8")

            # 1. Failing CI blocks nightly build.
            blocked = release.dev_plan(
                ROOT, commit_sha=head_sha, commit_subject="feat: plot cache\nextra line",
                run_number=11, force=False, ci_runs_json=failing_ci,
                releases_json=releases_prev, changed_files=["app/main.go"], now=fixed_now,
            )
            self.assertFalse(blocked["should_build"])
            self.assertIn("No passing CI", blocked["reason"])

            # 2. Identical commit skips nightly build when force=False.
            unchanged = release.dev_plan(
                ROOT, commit_sha=head_sha, commit_subject="feat: plot cache",
                run_number=11, force=False, ci_runs_json=passing_ci,
                releases_json=releases_same, now=fixed_now,
            )
            self.assertFalse(unchanged["should_build"])
            self.assertIn("already covers", unchanged["reason"])

            # 3. Non-desktop changes only (okf/ or r/ or site/) skip nightly build.
            non_app = release.dev_plan(
                ROOT, commit_sha=head_sha, commit_subject="docs: update okf",
                run_number=11, force=False, ci_runs_json=passing_ci,
                releases_json=releases_prev, changed_files=["okf/00_index.md", "r/R/read.R", "README.md"],
                now=fixed_now,
            )
            self.assertFalse(non_app["should_build"])
            self.assertIn("No desktop app changes", non_app["reason"])

            # 4. Desktop change with passing CI builds with SemVer-safe tag/version and sanitized subject.
            ready = release.dev_plan(
                ROOT, commit_sha=head_sha, commit_subject="feat(app): batch PlotBundle\nbody line",
                run_number=11, force=False, ci_runs_json=passing_ci,
                releases_json=releases_prev, changed_files=["app/internal/datasheet/service.go"],
                now=fixed_now,
            )
            self.assertTrue(ready["should_build"])
            self.assertEqual(ready["tag"], "dev-20261120-r11-g0123456")
            self.assertEqual(ready["build_mode"], "alpha")
            self.assertTrue(ready["version"].endswith("-dev.20261120.11.g0123456"))
            self.assertEqual(ready["commit_subject"], "feat(app): batch PlotBundle body line")
            self.assertEqual(release.version(ready["version"])[0], ready["version"])

            # 5. Manual force=True rebuilds even when commit matches latest dev release.
            forced = release.dev_plan(
                ROOT, commit_sha=head_sha, commit_subject="manual test drive",
                run_number=12, force=True, ci_runs_json=passing_ci,
                releases_json=releases_same, now=fixed_now,
            )
            self.assertTrue(forced["should_build"])
            self.assertEqual(forced["tag"], "dev-20261120-r12-g0123456")

    def test_dev_package_manifest_remote_and_verify_x64(self):
        commit = "0123456789abcdef0123456789abcdef01234567"
        full_ver = "2.0.2-dev.20261120.42.g0123456"
        dev_tag = "dev-20261120-r42-g0123456"
        deb_ver = "2.0.2~dev.20261120.42.g0123456"
        rpm_ver = release.rpm_version(full_ver)

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            win_root = tmp_path / "win"
            (win_root / "app/bin").mkdir(parents=True)
            win_exe = pe("amd64")
            (win_root / "app/bin/VPro.exe").write_bytes(win_exe)
            (win_root / "app/bin/VPro-amd64-installer.exe").write_bytes(b"nsis-dev-installer")

            def fake_7z(*args, **_kwargs):
                out_arg = [a for a in args if str(a).startswith("-o")][0]
                out_dir = Path(out_arg[2:])
                (out_dir / "VPro.exe").write_bytes(win_exe)

            with patch.dict(os.environ, {
                "RELEASE_VERSION": full_ver,
                "RELEASE_ARCH": "amd64",
                "GITHUB_SHA": commit,
            }):
                with patch.object(release, "run", side_effect=fake_7z):
                    release.dev_package(win_root, "windows")
                win_out = sorted(p.name for p in (win_root / "app/dist-artifacts").iterdir())
                self.assertEqual(win_out, [
                    "release-witness-windows-amd64.json",
                    "vpro-windows-amd64-installer.exe",
                ])

                lin_root = tmp_path / "lin"
                (lin_root / "app/bin").mkdir(parents=True)
                (lin_root / "app/bin/VPro").write_bytes(elf("amd64"))
                (lin_root / "app/bin/vpro_amd64.deb").write_bytes(deb("amd64", deb_ver))
                (lin_root / "app/bin/vpro_amd64.rpm").write_bytes(nfpm_rpm("amd64", rpm_ver))
                release.dev_package(lin_root, "linux")
                lin_out = sorted(p.name for p in (lin_root / "app/dist-artifacts").iterdir())
                self.assertEqual(lin_out, [
                    "release-witness-linux-amd64.json",
                    "vpro-linux-amd64.deb",
                    "vpro-linux-amd64.rpm",
                ])

                bridge_root = tmp_path / "bridge"
                shutil.copytree(ROOT / "scripts/vpro64", bridge_root / "scripts/vpro64")
                shutil.copytree(ROOT / "app/resources/vpro64", bridge_root / "app/resources/vpro64")
                release.dev_package(bridge_root, "vpro64")
                bridge_out = sorted(p.name for p in (bridge_root / "scripts/vpro64/dist-artifacts").iterdir())
                self.assertEqual(bridge_out, [
                    "release-witness-vpro64-bridge.json",
                    "vpro64-sqlite-bridge.zip",
                ])

                merged = tmp_path / "merged"
                merged.mkdir()
                for src_dir in (
                    win_root / "app/dist-artifacts",
                    lin_root / "app/dist-artifacts",
                    bridge_root / "scripts/vpro64/dist-artifacts",
                ):
                    for item in src_dir.iterdir():
                        shutil.copyfile(item, merged / item.name)

                prev_cwd = Path.cwd()
                try:
                    os.chdir(tmp_path)
                    meta = release.dev_manifest(
                        merged,
                        tag=dev_tag,
                        commit_subject="feat(spatial): 3D map basemaps",
                        published_at="2026-11-20T09:05:00Z",
                    )
                finally:
                    os.chdir(prev_cwd)

                self.assertEqual(meta["tag"], dev_tag)
                self.assertEqual(meta["shortCommit"], "0123456")
                attach_lines = (tmp_path / "dev-assets.txt").read_text(encoding="utf-8").splitlines()
                self.assertEqual(len(attach_lines), 6)

                remote_json = tmp_path / "remote.json"
                remote_json.write_text(json.dumps({
                    "assets": [{"name": Path(p).name} for p in attach_lines],
                }), encoding="utf-8")
                release.dev_remote(remote_json)

                downloaded = tmp_path / "downloaded"
                downloaded.mkdir()
                for p in attach_lines:
                    shutil.copyfile(p, downloaded / Path(p).name)
                release.dev_verify(downloaded, merged / "SHA256SUMS.txt", merged / "dev-build.json")

                # Tampering a downloaded binary must fail verification.
                (downloaded / "vpro-linux-amd64.rpm").write_bytes(b"corrupted")
                with self.assertRaises(ValueError):
                    release.dev_verify(downloaded, merged / "SHA256SUMS.txt", merged / "dev-build.json")

    def test_sync_dev_manifest_caps_at_5_and_isolated_from_official_channels(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            dev_payloads = {}
            releases_list = []
            for idx in range(1, 8):
                tag = f"dev-202611{10 + idx:02d}-r{idx}-g{idx:07x}"
                commit = f"{idx:040x}"
                ver = f"2.0.2-dev.202611{10 + idx:02d}.{idx}.g{commit[:7]}"
                published = f"2026-11-{10 + idx:02d}T09:05:00Z"
                assets = []
                for name in sorted(release.DEV_REQUIRED | {release.MANIFEST}):
                    assets.append({
                        "name": name,
                        "url": f"https://github.com/{release.REPOSITORY}/releases/download/{tag}/{name}",
                        "sha256": f"{idx:064x}",
                        "sizeBytes": 1024 * idx,
                    })
                dev_payloads[tag] = json.dumps({
                    "schemaVersion": 1,
                    "repository": release.REPOSITORY,
                    "tag": tag,
                    "version": ver,
                    "publishedAt": published,
                    "commit": commit,
                    "shortCommit": commit[:7],
                    "commitSubject": f"Dev build #{idx}",
                    "unsignedNotice": True,
                    "sha256sumsUrl": f"https://github.com/{release.REPOSITORY}/releases/download/{tag}/SHA256SUMS.txt",
                    "assets": assets,
                })
                releases_list.append({
                    "tag_name": tag,
                    "draft": False,
                    "prerelease": True,
                    "published_at": published,
                    "assets": [{"name": a["name"]} for a in assets] + [{"name": release.DEV_BUILD_METADATA}],
                })
            # Draft dev release and official stable/preview releases must not interfere.
            releases_list.append({
                "tag_name": "dev-20261199-r99-gabcdef0",
                "draft": True,
                "prerelease": True,
                "published_at": "2026-11-30T09:05:00Z",
                "assets": [{"name": release.MANIFEST}, {"name": release.DEV_BUILD_METADATA}],
            })
            releases_list.append({
                "tag_name": "v2.0.1",
                "draft": False,
                "prerelease": False,
                "published_at": "2026-11-19T12:00:00Z",
                "assets": [{"name": name} for name in sorted(release.REQUIRED | {release.MANIFEST, release.RELEASE_MANIFEST})],
            })
            releases_json = tmp_path / "releases.json"
            releases_json.write_text(json.dumps(releases_list), encoding="utf-8")

            dev_out = tmp_path / "dev-manifest.json"
            dev_doc = release.sync_dev_manifest(
                dev_out, keep=5, releases_json=releases_json,
                asset_loader=lambda tag, _name: dev_payloads[tag],
            )
            self.assertEqual(dev_doc["maxBuilds"], 5)
            self.assertEqual(len(dev_doc["builds"]), 5)
            # Newest-first ordering: #7 down to #3.
            self.assertEqual(
                [b["tag"] for b in dev_doc["builds"]],
                [f"dev-202611{10 + i:02d}-r{i}-g{i:07x}" for i in (7, 6, 5, 4, 3)],
            )

            # Official sync_release_manifest must completely ignore dev-* prereleases.
            official_out = tmp_path / "release-manifest.json"
            stable_manifest = {
                "schemaVersion": 1,
                "repository": release.REPOSITORY,
                "defaultChannel": "stable",
                "channels": {
                    "stable": {
                        "tag": "v2.0.1",
                        "version": "2.0.1",
                        "publishedAt": "2026-11-19T12:00:00Z",
                        "prerelease": False,
                        "unsignedNotice": True,
                        "sha256sumsUrl": f"https://github.com/{release.REPOSITORY}/releases/download/v2.0.1/SHA256SUMS.txt",
                        "standards": dict(release.DEFAULT_STANDARDS),
                        "assets": [
                            {
                                "name": name,
                                "url": f"https://github.com/{release.REPOSITORY}/releases/download/v2.0.1/{name}",
                                "sha256": "a" * 64,
                                "sizeBytes": 2048,
                            }
                            for name in sorted(release.REQUIRED | {release.MANIFEST})
                        ],
                    },
                    "preview": None,
                },
            }
            official_doc = release.sync_release_manifest(
                official_out, releases_json=releases_json,
                asset_loader=lambda tag, _name: json.dumps(stable_manifest) if tag == "v2.0.1" else (_ for _ in ()).throw(AssertionError(f"Unexpected tag {tag}")),
            )
            self.assertEqual(official_doc["channels"]["stable"]["tag"], "v2.0.1")
            self.assertIsNone(official_doc["channels"]["preview"])

    def test_prune_dev_releases_keeps_newest_5_and_never_touches_official_tags(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            releases_list = [
                {"tag_name": "v2.0.0", "draft": False, "prerelease": False, "published_at": "2026-11-01T00:00:00Z"},
                {"tag_name": "v2.0.1", "draft": False, "prerelease": False, "published_at": "2026-11-19T00:00:00Z"},
                {"tag_name": "v2.1.0-alpha.1", "draft": False, "prerelease": True, "published_at": "2026-11-02T00:00:00Z"},
                {"tag_name": "r-v2.0.1", "draft": False, "prerelease": False, "published_at": "2026-11-03T00:00:00Z"},
            ]
            for idx in range(1, 9):
                releases_list.append({
                    "tag_name": f"dev-202611{idx:02d}-r{idx}-gaaaaaaa",
                    "draft": False,
                    "prerelease": True,
                    "published_at": f"2026-11-{idx:02d}T09:00:00Z",
                })
            releases_json = tmp_path / "releases.json"
            releases_json.write_text(json.dumps(releases_list), encoding="utf-8")

            deleted = []
            summary = release.prune_dev_releases(
                keep=5, releases_json=releases_json, deleter=deleted.append,
            )
            self.assertEqual(len(summary["kept"]), 5)
            self.assertEqual(summary["kept"][0], "dev-20261108-r8-gaaaaaaa")
            self.assertEqual(summary["kept"][-1], "dev-20261104-r4-gaaaaaaa")
            self.assertEqual(deleted, [
                "dev-20261103-r3-gaaaaaaa",
                "dev-20261102-r2-gaaaaaaa",
                "dev-20261101-r1-gaaaaaaa",
            ])

    def test_dev_builds_workflow_contract(self):
        dev_wf = (ROOT / ".github/workflows/dev-builds.yml").read_text(encoding="utf-8")
        self.assertNotIn("|| true", dev_wf)
        self.assertNotIn("continue-on-error", dev_wf)
        self.assertNotIn("macos-", dev_wf)
        self.assertIn("schedule:", dev_wf)
        self.assertIn("cron:", dev_wf)
        self.assertIn("workflow_dispatch:", dev_wf)
        self.assertIn("cancel-in-progress: true", dev_wf)
        self.assertEqual(dev_wf.count("go-version: '1.27.4'"), 2)
        self.assertEqual(dev_wf.count("wails3@v3.1.0"), 2)
        self.assertEqual(dev_wf.count("retention-days: 1"), 3)
        self.assertIn("INSTALL_SCOPE=user", dev_wf)
        self.assertIn("python3 scripts/release.py dev-plan", dev_wf)
        self.assertIn("python scripts/release.py dev-package windows", dev_wf)
        self.assertIn("python scripts/release.py dev-package linux", dev_wf)
        self.assertIn("python3 scripts/release.py dev-package vpro64", dev_wf)
        self.assertIn("python3 scripts/release.py dev-manifest dev-assets", dev_wf)
        self.assertIn("python3 scripts/release.py dev-remote dev-remote.json", dev_wf)
        self.assertIn("python3 scripts/release.py dev-verify dev-downloaded", dev_wf)
        self.assertIn("python3 scripts/release.py prune-dev --keep 5", dev_wf)
        self.assertIn("python3 scripts/release.py sync-dev-manifest --output site/dev-manifest.json --keep 5", dev_wf)
        self.assertIn("--prerelease", dev_wf)
        self.assertEqual(dev_wf.count("contents: write"), 1)

    def test_package_vpro64_bridge_deterministic_and_parity_enforced(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp) / "repo"
            shutil.copytree(ROOT / "scripts/vpro64", work / "scripts/vpro64")
            shutil.copytree(ROOT / "app/resources/vpro64", work / "app/resources/vpro64")
            release.package(work, "vpro64")
            out_dir = work / "scripts/vpro64/dist-artifacts"
            self.assertEqual(
                sorted(p.name for p in out_dir.iterdir()),
                ["release-witness-vpro64-bridge.json", "vpro64-sqlite-bridge.zip"],
            )
            release.validate_vpro64_bridge(out_dir / "vpro64-sqlite-bridge.zip")

            # Verify drift between scripts/vpro64 and app/resources/vpro64 fails closed.
            (work / "app/resources/vpro64/README.txt").write_text("drifted\n", encoding="utf-8")
            shutil.rmtree(out_dir)
            with self.assertRaisesRegex(ValueError, "drifted"):
                release.package(work, "vpro64")


if __name__ == "__main__":
    unittest.main()
