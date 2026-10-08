#!/usr/bin/env python3
"""Prepare exact dependency sources and an arm64 libintl relinking archive locally."""
import hashlib
import gzip
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
INPUTS = {
    "libghostty-spm": ("https://codeload.github.com/Lakr233/libghostty-spm/tar.gz/7e45d27160f9b34aca9ca5c9820e9207482f9f04",
                      "a95db4a004a5b274f2223aefd7401ee5ffa899f9a966e6c37baad3a210791e59"),
    "MSDisplayLink": ("https://codeload.github.com/Lakr233/MSDisplayLink/tar.gz/87eb0af130744c8cbe2e31b6e1a5bcd659f1c220",
                      "5b16b8ca4e6e0d77ac64674fc6d2a9c76177b9febf569c6d1fc3835b6082a4ff"),
    "ghostty": ("https://codeload.github.com/ghostty-org/ghostty/tar.gz/82938b633ba646db38591d969c3c526332bd7e65",
                "6c43388617aa0b2d1ffcca1402c3114545a325a00b66aa75ce40c4edf032e3a7"),
    "producer": ("https://codeload.github.com/Lakr233/libghostty-spm/tar.gz/a5e6f9407b27825e406e66e70b80fbae7f7205ae",
                 "34fded6537b67f16d4bde8a9dbb7cf91cddae8fd29c16bfe386f70cf8e40a541"),
    "gettext": ("https://deps.files.ghostty.org/gettext-0.24.tar.gz",
                "c918503d593d70daf4844d175a13d816afacb667c06fba1ec9dcd5002c1518b7"),
    "z2d": ("https://deps.files.ghostty.org/z2d-7dbae85c81784dba9988320bf9543ed9a81350c8.tar.gz",
            "e55c9d0b156edaddfea32fb1c0e3597e1b6306b9a4ec1888e2f8008c598bced8"),
    "zig": ("https://ziglang.org/download/0.16.0/zig-aarch64-macos-0.16.0.tar.xz",
            "b23d70deaa879b5c2d486ed3316f7eaa53e84acf6fc9cc747de152450d401489"),
}
PINS = {"libghostty-spm": "7e45d27160f9b34aca9ca5c9820e9207482f9f04",
        "MSDisplayLink": "87eb0af130744c8cbe2e31b6e1a5bcd659f1c220"}


def run(*args, cwd=None, env=None):
    """Capture tool output without saving local paths in release materials."""
    return subprocess.run(args, cwd=cwd, env=env, check=True,
                          stdout=subprocess.PIPE, text=True).stdout


def main():
    version = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise RuntimeError("unexpected release version")
    destination = ROOT / "build/release-candidate" / f"Taskport-{version}-source-relink.tar.gz"
    if destination.exists() or destination.is_symlink() or destination.parent.is_symlink():
        raise RuntimeError("source candidate already exists; inspect it before replacing it")
    resolved = {pin["identity"]: pin["state"]["revision"]
                for pin in json.loads((ROOT / "Package.resolved").read_text())["pins"]}
    if resolved != {name.lower(): pin for name, pin in PINS.items()}:
        raise RuntimeError("source recipe does not match Package.resolved")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".source-release-", dir=ROOT / "build") as temp:
        work = Path(temp)
        bundle = work / f"Taskport-{version}-source-relink"
        (bundle / "deps").mkdir(parents=True)
        tools = {}
        for name, (url, digest) in INPUTS.items():
            archive = work / f"{name}.archive"
            run("curl", "--fail", "--location", "--silent", "--show-error", url, "-o", str(archive))
            if hashlib.sha256(archive.read_bytes()).hexdigest() != digest:
                raise RuntimeError("source archive checksum mismatch")
            unpack = work / f"unpack-{name}"
            unpack.mkdir()
            # Verified public archives are extracted in disposable project-local directories.
            run("tar", "-xf", str(archive), "-C", str(unpack))
            entries = list(unpack.iterdir())
            if len(entries) != 1 or not entries[0].is_dir():
                raise RuntimeError("unexpected source archive layout")
            target = work / "zig" if name == "zig" else bundle / "deps" / name
            shutil.move(str(entries[0]), target)
            tools[name] = target

        app = bundle / "app"
        app.mkdir()
        # Exact working source, including release scripts, without VCS/account metadata or caches.
        paths = run("git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", cwd=ROOT).split("\0")
        for name in sorted(set(paths) - {""}):
            source = ROOT / name
            if not source.is_file() or source.is_symlink():
                raise RuntimeError("unexpected Taskport source entry")
            target = app / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            target.chmod(0o755 if os.access(source, os.X_OK) else 0o644)

        env = dict(os.environ, PATH=str(work / "zig") + os.pathsep + os.environ["PATH"],
                   ZIG_GLOBAL_CACHE_DIR=str(work / "zig-global"),
                   ZIG_LOCAL_CACHE_DIR=str(work / "zig-local"),
                   CLANG_MODULE_CACHE_PATH=str(work / "clang-cache"))
        run(str(tools["producer"] / "Script/apply-patches.sh"), str(tools["ghostty"]), env=env)
        run(str(work / "zig/zig"), "build", "--fetch=all", cwd=tools["ghostty"], env=env)
        # Include Zig's compiler/runtime/library sources and license; the compiler executable
        # is a general-purpose build tool downloaded separately by recipients.
        shutil.copytree(work / "zig/lib", bundle / "toolchain-src/zig-lib", symlinks=True)
        shutil.copyfile(work / "zig/LICENSE", bundle / "toolchain-src/Zig-LICENSE")

        relink = bundle / "relink"
        framework = relink / "GhosttyKit.xcframework"
        slice_dir = framework / "macos-arm64"
        slice_dir.mkdir(parents=True)
        original = ROOT / ".build/artifacts/libghostty-spm/libghostty/GhosttyKit.xcframework/macos-arm64_x86_64"
        shutil.copytree(original / "Headers", slice_dir / "Headers")
        engine = relink / "engine-without-libintl.a"
        run("lipo", str(original / "libghostty.a"), "-thin", "arm64", "-output", str(engine))
        # Remove every libintl object specified by the pinned build recipe, including gnulib.
        build = (tools["ghostty"] / "pkg/libintl/build.zig").read_text()
        names = re.findall(r'^\s*"([^"\n]+\.c)",', build, re.MULTILINE)
        objects = [Path(name).with_suffix(".o").name for name in names]
        members = run("ar", "-t", str(engine)).splitlines()
        if len(objects) != 30 or any(members.count(name) != 1 for name in objects):
            raise RuntimeError("libintl object inventory does not match the pinned engine")
        run("ar", "-d", str(engine), *objects)
        run("xcrun", "ranlib", str(engine))
        run("strip", "-S", str(engine))
        definitions = run("xcrun", "nm", "-gU", str(engine))
        if re.search(r"\b[TDS] _+libintl_", definitions):
            raise RuntimeError("a libintl definition remains in the relinking engine")
        shutil.copyfile(engine, slice_dir / "libghostty.a")
        (framework / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundlePackageType": "XFWK", "XCFrameworkFormatVersion": "1.0",
            "AvailableLibraries": [{"LibraryIdentifier": "macos-arm64", "LibraryPath": "libghostty.a",
                                    "HeadersPath": "Headers", "SupportedArchitectures": ["arm64"],
                                    "SupportedPlatform": "macos"}]}))
        manifest = {"source_archives": {name: {"url": url, "sha256": digest}
                                        for name, (url, digest) in INPUTS.items()},
                    "swift_package_revisions": PINS, "removed_libintl_objects": objects,
                    "engine_without_libintl_sha256": hashlib.sha256(engine.read_bytes()).hexdigest()}
        (bundle / "SOURCE-MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
        shutil.copyfile(ROOT / "docs/dependency-relinking.md", bundle / "README.md")

        # Source files remain verbatim. Archive ownership and timestamps disclose no local metadata.
        def neutral(info):
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            info.mtime = 946684800
            info.pax_headers = {}
            return info
        archive = work / destination.name
        with archive.open("wb") as raw:
            with gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=946684800) as compressed:
                with tarfile.open(fileobj=compressed, mode="w|", format=tarfile.PAX_FORMAT) as tar:
                    tar.add(bundle, arcname=bundle.name, filter=neutral)
        print(run(sys.executable, str(ROOT / "scripts/check-source-release.py"), str(archive)), end="")
        shutil.move(str(archive), destination)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    destination.with_name(destination.name + ".sha256").write_text(f"{digest}  {destination.name}\n")
    print("Prepared source/relink candidate:", destination.name)
    print("Test its extracted relink path and audit it before publication.")


if __name__ == "__main__":
    main()
