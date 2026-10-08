#!/usr/bin/env python3
"""Rebuild libintl and Taskport from the accompanying source/relink archive."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def run(*args, cwd=None, env=None):
    """Fail immediately when a compiler, archive tool, or verification fails."""
    return subprocess.run(args, cwd=cwd, env=env, check=True, text=True,
                          stdout=subprocess.PIPE).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_root", type=Path)
    parser.add_argument("zig", type=Path, help="official Zig 0.16.0 executable")
    parser.add_argument("output_app", type=Path, help="a fresh Taskport.app path")
    parser.add_argument("--verify-modification", action="store_true",
                        help="test a harmless modified-library branch and check it reaches the app")
    args = parser.parse_args()
    source = args.source_root.resolve()
    zig = args.zig.resolve()
    output = args.output_app.absolute()
    if output.exists() or output.is_symlink():
        parser.error("the output app already exists")
    if run(str(zig), "version").strip() != "0.16.0":
        parser.error("Zig 0.16.0 is required")
    for name in ("app", "deps/ghostty/pkg/libintl", "deps/gettext",
                 "deps/libghostty-spm", "deps/MSDisplayLink", "relink"):
        if not (source / name).is_dir():
            parser.error("source/relink archive is incomplete")

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".taskport-relink-", dir=output.parent) as temp:
        work = Path(temp)
        app = work / "app"
        deps = app / "ReleaseDependencies"
        ignore = shutil.ignore_patterns(".git", ".build", "build", "zig-pkg", "zig-out", ".zig-cache")
        shutil.copytree(source / "app", app, ignore=ignore)
        for name in ("libghostty-spm", "MSDisplayLink", "gettext"):
            shutil.copytree(source / "deps" / name, deps / name, ignore=ignore)
        for name in ("libintl", "apple-sdk"):
            shutil.copytree(source / "deps/ghostty/pkg" / name, deps / name, ignore=ignore)

        # Resolve the bundled gettext source locally; never fetch an unpinned substitute.
        zon = deps / "libintl/build.zig.zon"
        text = zon.read_text()
        text, count = re.subn(r'\.url = "https://deps\.files\.ghostty\.org/gettext-0\.24\.tar\.gz",\s*'
                             r'\.hash = "[^"]+",', '.path = "../gettext",', text)
        if count != 1:
            raise RuntimeError("unexpected libintl dependency manifest")
        zon.write_text(text)

        probe = "Taskport modified libintl verification"
        if args.verify_modification:
            # Only the temporary test copy changes. Normal domain names keep their behavior.
            file = deps / "gettext/gettext-runtime/intl/bindtextdom.c"
            text = file.read_text()
            text, count = re.subn(r'(BINDTEXTDOMAIN\s*\(const char \*domainname, const char \*dirname\)\s*\{)',
                                 r'\1\n  if (domainname && strcmp(domainname, "TASKPORT_RELINK_PROBE") == 0)\n'
                                 '    return "' + probe + '";\n', text)
            if count != 1:
                raise RuntimeError("unexpected bindtextdomain source")
            file.write_text(text)

        env = dict(os.environ, ZIG_GLOBAL_CACHE_DIR=str(work / "zig-global"),
                   ZIG_LOCAL_CACHE_DIR=str(work / "zig-local"),
                   CLANG_MODULE_CACHE_PATH=str(work / "clang-cache"))
        run(str(zig), "build", "-Dtarget=aarch64-macos.14.0", "-Doptimize=ReleaseFast",
            "--prefix", str(work / "intl"), cwd=deps / "libintl", env=env)
        library = work / "intl/lib/libintl.a"
        # Apple's linker requires eight-byte Mach-O archive alignment. Repack Zig's
        # archive with native libtool, which also regenerates its symbol index.
        objects = work / "intl-objects"
        objects.mkdir()
        run("ar", "-x", str(library), cwd=objects)
        object_files = sorted(objects.glob("*.o"))
        if len(object_files) != 30:
            raise RuntimeError("unexpected rebuilt libintl object inventory")
        for file in object_files:
            file.chmod(0o644)  # Zig archives do not preserve usable member permissions.
        library = work / "libintl-native.a"
        run("xcrun", "libtool", "-static", "-o", str(library),
            *[str(file) for file in object_files])
        if args.verify_modification:
            # A small command-line program tests the modified function without launching Taskport.
            test = work / "probe.c"
            test.write_text('#include <string.h>\n#include <libintl.h>\nint main(void) {\n'
                            'return strcmp(bindtextdomain("TASKPORT_RELINK_PROBE", 0), "' + probe + '");\n}\n')
            run("xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=14.0",
                "-I", str(deps / "libintl"), str(test), str(library),
                "-framework", "CoreFoundation", "-o", str(work / "probe"))
            run(str(work / "probe"))

        framework = deps / "libghostty-spm/GhosttyKit.xcframework"
        shutil.copytree(source / "relink/GhosttyKit.xcframework", framework)
        engine = framework / "macos-arm64/libghostty.a"
        run("xcrun", "libtool", "-static", "-no_warning_for_no_symbols", "-o", str(engine),
            str(source / "relink/engine-without-libintl.a"), str(library))

        # Only temporary manifests change; distributed originals retain their exact pins.
        manifest = deps / "libghostty-spm/Package.swift"
        text = manifest.read_text()
        text, count = re.subn(r'\.package\(url: "https://github.com/Lakr233/MSDisplayLink.git", from: "2.2.0"\)',
                             '.package(path: "../MSDisplayLink")', text)
        if count != 1:
            raise RuntimeError("unexpected wrapper dependency manifest")
        text, count = re.subn(r'\.binaryTarget\(\s*name: "libghostty",\s*url: "[^"]+",\s*checksum: "[^"]+"\s*\)',
                             '.binaryTarget(name: "libghostty", path: "GhosttyKit.xcframework")', text)
        if count != 1:
            raise RuntimeError("unexpected binary target manifest")
        manifest.write_text(text)
        manifest = app / "Package.swift"
        text, count = re.subn(r'\.package\(url: "https://github.com/Lakr233/libghostty-spm.git", exact: "1.6.20260909"\)',
                             '.package(path: "ReleaseDependencies/libghostty-spm")', manifest.read_text())
        if count != 1:
            raise RuntimeError("unexpected Taskport dependency manifest")
        manifest.write_text(text)
        (app / "Package.resolved").unlink()
        run("bash", "scripts/build.sh", "--package", str(output), cwd=app, env=env)
        if args.verify_modification and probe.encode() not in (output / "Contents/MacOS/Taskport").read_bytes():
            shutil.rmtree(output)
            raise RuntimeError("the modified libintl did not reach the app")
        print("Modified-library function test and Taskport relink passed." if args.verify_modification
              else "Taskport relink passed.")
        print("No app was installed or launched. Audit the output before sharing it.")


if __name__ == "__main__":
    main()
