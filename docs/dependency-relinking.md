# Taskport source and libintl relinking materials

Distribute `Taskport-0.0.1-source-relink.tar.gz` and its checksum beside the matching app ZIP, with the same free access. GitHub's automatic source archive alone omits the dependency sources and relinking library provided here.

The archive includes Taskport's working source and build scripts, both pinned Swift packages, the exact Ghostty source and producer patches, the fetched Zig dependency source graph, complete gettext 0.24 and z2d source, and Zig's runtime/library sources. Upstream licenses, notices, and source headers remain intact. `SOURCE-MANIFEST.json` records the original download hashes and package revisions. Taskport is GPL-3.0-only; third-party components retain their listed licenses.

## Rebuild Taskport with a modified libintl

Use an Apple silicon Mac, the documented Xcode 27.x / Swift 6.4.x toolchain, Python 3, and the official arm64 macOS Zig 0.16.0 compiler. The compiler archive URL and SHA-256 are in `SOURCE-MANIFEST.json`; unpack it locally. No global Zig installation, Apple Developer membership, signing certificate, or Metal Toolchain is needed for this relinking path.

Extract the source/relink archive. From its top-level directory, run:

```sh
python3 app/scripts/relink-libintl.py "$PWD" /path/to/zig/zig /path/to/fresh/Taskport.app
```

Edit `deps/gettext/gettext-runtime/intl/` or `deps/ghostty/pkg/libintl/` before running the command to build your modified, interface-compatible libintl. The script compiles the library from the bundled sources, combines it with the arm64 engine objects that exclude all 30 original libintl objects, and builds Taskport and its Swift dependencies from source. It changes only temporary copies of package manifests to use the included local dependencies. It ad-hoc signs and verifies the resulting app, and never installs or launches it.

For an automated modification check, choose another fresh output path and add `--verify-modification`. That mode changes only a temporary copy of `bindtextdomain`: a special test domain returns a verification string. It compiles and runs a small command-line function test, relinks Taskport, and requires that string in the app executable. Normal domains retain their behavior. The published app does not contain this test modification.

Bundled `relink/engine-without-libintl.a` contains the other upstream engine objects and their preserved notices; it is not a substitute for the included source. The LGPL library remains replaceable. System frameworks and the system C++ runtime come from macOS/Xcode. No personal signing key or activation service is required to use a rebuilt app.

## Build the whole engine from source

The exact producer scripts are under `deps/producer/`; patched Ghostty and its fetched dependencies are under `deps/ghostty/`. With Zig 0.16.0 on a command-scoped PATH, run the producer's `Script/build-ghostty.sh` with the Ghostty path, `aarch64-macos`, and a fresh output path. Set `BUILD_CACHE_ROOT`, `ZIG_GLOBAL_CACHE_DIR`, and `CLANG_MODULE_CACHE_ROOT` inside your working directory. This separate route compiles Ghostty's built-in GPU shaders and requires Apple's free Metal Toolchain component. Recipients running the app do not need it.

Full engine compilation remains unverified and is distinct from the tested libintl replacement path. The supplied source archive does not claim byte-identical engine reproduction.
