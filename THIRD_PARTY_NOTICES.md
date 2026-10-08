# Third-party notices

Taskport's original project material is licensed under GNU GPL version 3 only (`GPL-3.0-only`); see [LICENSE](LICENSE). Third-party components retain their own licenses and copyrights. The license texts below are checked in under `LICENSES/` and included with this document in the app's `Contents/Resources/` directory. Upstream license wording and embedded notices are preserved. Authored provenance notes are identified separately.

## Integration and provenance

| Component | Source pin | License text |
| --- | --- | --- |
| libghostty-spm / GhosttyTerminal | [1.6.20260909, commit 7e45d27160f9b34aca9ca5c9820e9207482f9f04](https://github.com/Lakr233/libghostty-spm/tree/7e45d27160f9b34aca9ca5c9820e9207482f9f04) | [MIT, © 2026 @Lakr233](LICENSES/libghostty-spm/LICENSE) |
| Ghostty engine | [82938b633ba646db38591d969c3c526332bd7e65](https://github.com/ghostty-org/ghostty/tree/82938b633ba646db38591d969c3c526332bd7e65), with wrapper patches | [MIT, © 2024 Mitchell Hashimoto and Ghostty contributors](LICENSES/Ghostty/LICENSE) |
| MSDisplayLink | [2.2.0, commit 87eb0af130744c8cbe2e31b6e1a5bcd659f1c220](https://github.com/Lakr233/MSDisplayLink/tree/87eb0af130744c8cbe2e31b6e1a5bcd659f1c220) | [MIT, © 2024 Lakr Aream](LICENSES/MSDisplayLink/LICENSE) |
| bash-preexec, vendored shell resource | [Wrapper's pinned copy](https://github.com/Lakr233/libghostty-spm/tree/7e45d27160f9b34aca9ca5c9820e9207482f9f04/Sources/GhosttyTerminal/Resources/Ghostty/shell-integration/bash) | [MIT, © 2017 Ryan Caloras and contributors](LICENSES/bash-preexec/LICENSE.md) |

Only the wrapper's `GhosttyTerminal` product is linked. Package revisions are retained in `Package.resolved`. This community wrapper is not an official Ghostty Swift package. Its shell-integration resource bundle, including the original bash-preexec notice, is preserved.

The downloaded engine was produced from a **different wrapper revision** than the Swift package:

- Producer recipe and patches: [a5e6f9407b27825e406e66e70b80fbae7f7205ae](https://github.com/Lakr233/libghostty-spm/tree/a5e6f9407b27825e406e66e70b80fbae7f7205ae), identified by the [artifact release](https://github.com/Lakr233/libghostty-spm/releases/tag/upstream.82938b633ba6).
- Artifact: [GhosttyKit.xcframework.zip](https://github.com/Lakr233/libghostty-spm/releases/download/upstream.82938b633ba6/GhosttyKit.xcframework.zip).
- SHA-256: `2d9a26e80c3836c450f03ea2cf9d191841d9093d4f61c1cea466d2fc8e215dbb`, verified by SwiftPM during resolution.
- The producer builds arm64/x86_64 macOS static libraries with Sentry, custom shaders, and the inspector disabled. Its workflow requests Zig `0.16.0`. The official arm64 macOS compiler archive has been independently downloaded and checked against Zig's published SHA-256: `b23d70deaa879b5c2d486ed3316f7eaa53e84acf6fc9cc747de152450d401489`. This verifies the compiler input, not reproduction of the released engine artifact.

## Native libraries, fonts, and embedded code

Versions below come from the pinned Ghostty source and its dependency archives, not current upstream releases. The [dependency manifest](https://github.com/ghostty-org/ghostty/blob/82938b633ba646db38591d969c3c526332bd7e65/build.zig.zon) and [build graph](https://github.com/ghostty-org/ghostty/blob/82938b633ba646db38591d969c3c526332bd7e65/src/build/SharedDeps.zig) specify the source inputs. License directories retain upstream copyrights and attribution.

| Component | Pin / origin | License texts |
| --- | --- | --- |
| GNU gettext / libintl | 0.24, `gettext-runtime/intl` and its gnulib helpers; copyright Free Software Foundation, Inc. | [LGPL-2.1-or-later](LICENSES/libintl/COPYING.LIB), [authors](LICENSES/libintl/AUTHORS), [generated Bison parser GPL-3.0-or-later notice with skeleton exception](LICENSES/libintl/BISON-NOTICE); GPL text in root `LICENSE` |
| FreeType | 2.13.2 | [FTL](LICENSES/FreeType/FTL.TXT), [license selection and embedded-code summary](LICENSES/FreeType/LICENSE.TXT), [BDF](LICENSES/FreeType/BDF-LICENSE), [PCF](LICENSES/FreeType/PCF-LICENSE), [hash code](LICENSES/FreeType/FTHASH-LICENSE), [HarfBuzz-derived portions](LICENSES/FreeType/HARFBUZZ-PORTIONS-LICENSE), [vendored zlib](LICENSES/FreeType/ZLIB-LICENSE) |
| libpng | 1.6.43 | [PNG license and attributions](LICENSES/libpng/LICENSE) |
| zlib | 1.3.1; FreeType separately vendors 1.2.13 | [Zlib license](LICENSES/zlib/LICENSE) |
| Oniguruma | 6.9.9 | [BSD-2-Clause](LICENSES/Oniguruma/COPYING) |
| Highway | 1.2.0, `66486a10623fa0d72fe91260f96c892e41aceb06` | [Apache-2.0](LICENSES/Highway/LICENSE), [BSD-3-Clause](LICENSES/Highway/LICENSE-BSD3) |
| simdutf | Vendored header declares **9.0.0**; Ghostty's package manifest still says 5.2.8 | [MIT](LICENSES/simdutf/LICENSE-MIT), [Apache-2.0](LICENSES/simdutf/LICENSE-APACHE), [embedded PyTorch-derived BSD notice](LICENSES/simdutf/PYTORCH-BSD-LICENSE), [embedded Fuchsia attribution](LICENSES/simdutf/FUCHSIA-NOTICE) |
| Wuffs | `7411f488fe2e2c205c3d3b3d28638b7356522930`, generated v0.4 C code | [MIT option](LICENSES/Wuffs/LICENSE-MIT) |
| stb_image / stb_image_resize | Vendored 2.28 / 0.97 in the pinned engine | [MIT option, identical notice in both headers](LICENSES/stb/LICENSE-MIT) |
| JetBrains Mono | 2.304 | [OFL-1.1](LICENSES/JetBrainsMono/OFL.txt), [authors](LICENSES/JetBrainsMono/AUTHORS.txt) |
| Symbols Nerd Font | SymbolsOnly 3.4.0 | [Archive's MIT notice](LICENSES/NerdFontsSymbolsOnly/LICENSE), [Ghostty-vendored Nerd Fonts licensing document](LICENSES/NerdFontsSymbolsOnly/NERD-FONTS-LICENSE); constituent attributions below |
| libxev | `9ce8e8e6ff89e583258a7f8e7adeeeaeae8611bf` | [MIT](LICENSES/libxev/LICENSE) |
| libvaxis | 0.6.0, `1dbbe575dff4586fe51e3217aa5c3fecdcbb6089` | [MIT](LICENSES/vaxis/LICENSE) |
| z2d | 0.12.1, `7dbae85c81784dba9988320bf9543ed9a81350c8` | [MPL-2.0](LICENSES/z2d/COPYING), [upstream notices including Cairo, Pixman, tiny-skia, and W3C](LICENSES/z2d/LICENSE) |
| zig-objc | `c8de82ff80281215ad92900866dab7103a8efa8b` | [MIT](LICENSES/zig-objc/LICENSE) |
| uucode | 0.2.0, `2826a37a4562284fdacd8fa029d49509cc9bffcd` | [MIT](LICENSES/uucode/LICENSE.md), [Unicode License V3](LICENSES/uucode/licenses/LICENSE_unicode), [Bjoern Hoehrmann UTF-8 decoder](LICENSES/uucode/licenses/LICENSE_Bjoern_Hoehrmann) |
| zf | 0.11.0, `c35c421f84895193246db06c40683c1a30e616ef` | [MIT](LICENSES/zf/LICENSE) |
| Zig compiler/runtime | Official 0.16.0 distribution | [MIT, © Zig contributors](LICENSES/Zig/LICENSE) |
| LLVM C++/unwind runtime sources supplied with Zig | License texts from the same Zig 0.16.0 archive | [libc++](LICENSES/LLVM/libcxx-LICENSE.TXT), [libc++abi](LICENSES/LLVM/libcxxabi-LICENSE.TXT), [libunwind](LICENSES/LLVM/libunwind-LICENSE.TXT), including Apache-2.0 with LLVM exceptions and legacy terms |

This software is based in part on the work of the FreeType Team. Portions of this software are copyright © 2023 The FreeType Project (www.freetype.org). All rights reserved. Taskport selects the FreeType License (FTL); the separate embedded-code notices are also preserved.

Archive symbol inspection finds libintl, FreeType, libpng, zlib, Oniguruma, simdutf, Highway, and Wuffs functions. Zig-module notices above conservatively cover the imported source graph; this is not a claim that every imported function or platform-conditional dependency is in the binary. macOS uses CoreText by default, not the HarfBuzz/fontconfig backends. Excluded Linux/GTK libraries, disabled shader/inspector/Sentry components, and test-only dependencies are not treated as linked runtime components. The full z2d upstream notice is retained even where it describes its own test assets.

## Symbols Nerd Font constituent attributions

The SymbolsOnly archive SHA-256 is `1164d1b956d4bde248d7b2f0998c43cc94f5202431a1564a793895b1e73b0d04`. Glyph inputs are mapped by the [Nerd Fonts 3.4.0 patcher](https://github.com/ryanoasis/nerd-fonts/blob/fa7b859994228a9c8759f99c55a8d31ee92a1b5e/font-patcher); their individual terms are retained, not replaced by Taskport's GPL or the archive-level MIT label. Nerd Fonts modifies glyph positioning, scaling, names, and codepoint mappings. Taskport embeds the packaged font without further font modifications.

| Glyph source / attribution | Retained notice |
| --- | --- |
| [Codicons, Microsoft](https://github.com/ryanoasis/nerd-fonts/tree/fa7b859994228a9c8759f99c55a8d31ee92a1b5e/src/glyphs/codicons) | [CC-BY-4.0](LICENSES/NerdFontsSymbolsOnly/glyphs/codicons-LICENSE.txt) |
| Devicon, konpa and contributors; 2.16.0 custom input | [MIT](LICENSES/NerdFontsSymbolsOnly/glyphs/devicon-LICENSE) |
| [Font Awesome, Fonticons, Inc.](https://github.com/ryanoasis/nerd-fonts/tree/fa7b859994228a9c8759f99c55a8d31ee92a1b5e/src/glyphs/font-awesome) | [Asset-specific CC-BY-4.0 / OFL-1.1 / MIT terms](LICENSES/NerdFontsSymbolsOnly/glyphs/font-awesome-LICENSE.txt) |
| Font Awesome Extension, André Luiz Gava | [MIT](LICENSES/NerdFontsSymbolsOnly/glyphs/font-awesome-extension-LICENCE) |
| Font Logos 1.3.0, Lukas W. | [Unlicense from the original release](LICENSES/NerdFontsSymbolsOnly/glyphs/font-logos-LICENSE) |
| IEC Power Symbols, Joe Loughry | [MIT](LICENSES/NerdFontsSymbolsOnly/glyphs/iec-LICENSE.txt) |
| Material Design Icons, Pictogram / Austin Andrews and contributors | [Apache-2.0](LICENSES/NerdFontsSymbolsOnly/glyphs/materialdesign-LICENSE) |
| Seti-UI, Jesse Weed; Nerd Fonts' modified original-source input and custom glyphs, Ryan L McIntyre | [Seti MIT](LICENSES/NerdFontsSymbolsOnly/glyphs/seti-LICENSE.md) and the Nerd Fonts MIT notice above |
| Octicons, GitHub, Inc. | [MIT](LICENSES/NerdFontsSymbolsOnly/glyphs/octicons-LICENSE) |
| Pomicons, Gabriele Lana | [OFL-1.1](LICENSES/NerdFontsSymbolsOnly/glyphs/pomicons-LICENSE) |
| Powerline Extra Symbols, Ryan L McIntyre | [MIT](LICENSES/NerdFontsSymbolsOnly/glyphs/powerline-extra-LICENSE) |
| Powerline Symbols, Kim Silkebækken and contributors | [Upstream permissive font license](LICENSES/NerdFontsSymbolsOnly/glyphs/powerline-symbols-LICENSE.txt) |
| Weather Icons, Erik Flowers | [OFL-1.1](LICENSES/NerdFontsSymbolsOnly/glyphs/weather-icons-OFL.txt) |

Most glyph notices come directly from the pinned Nerd Fonts tree. Missing upstream texts were obtained from Devicon 2.16.0, Font Awesome Extension commit `09d80249058ee8018a45da30add4339289dbb466`, [IEC Power Symbols](https://github.com/jloughry/Unicode/blob/master/LICENSE.txt), and Seti-UI commit `2d6c5e68b4ded73c92dac291845ee44e1182d511`. The pinned Nerd Fonts audit labels Font Logos “Unlicensed”; its actual [1.3.0 release](https://github.com/lukas-w/font-logos/releases/tag/v1.3.0) contains the Unlicense. The release's font and Nerd Fonts' input match byte-for-byte (SHA-256 `7f0b055275bb3710afee586519884f3e302ec295a2f4ff4158daacf437c49852`). Brand glyphs remain their owners' trademarks; their inclusion does not imply endorsement.

## Binary redistribution materials

The matching `Taskport-0.0.1-source-relink.tar.gz` must accompany the app ZIP with the same free download access. It contains Taskport's corresponding source/build scripts, the exact Swift dependencies, patched Ghostty and its producer recipe, the fetched dependency source graph, complete gettext 0.24 and MPL-covered z2d source, and Zig's runtime/library sources. `SOURCE-MANIFEST.json` records source download hashes, package revisions, and the relinking engine hash. GitHub's automatic repository source archive does not include these additional materials.

The arm64 engine archive contains 166 code objects, including 30 libintl/gnulib objects, `compiler_rt.o`, and the producer's `libcxx-verbose-abort-compat.o`. Runtime source and notices are retained for Zig's builtins and the compatibility shim. C++ runtime dynamic references resolve to macOS's system libc++; the LLVM source notices remain conservatively included for the compiler-supplied headers/runtime material.

The relinking instructions at `app/docs/dependency-relinking.md` in the accompanying source describe the script. Verification rebuilt libintl from the bundled source, removed all 30 original library objects, inserted a harmless modified `bindtextdomain` branch, tested that function in a command-line program, and rebuilt/relinked Taskport from its Swift source and bundled local dependencies. The modified string was present in the resulting app, whose signature and privacy checks passed. The published app does not contain this verification modification. No personal signing key, paid Apple account, or Metal Toolchain is required for this path.

Whole-engine source compilation and byte-identical reproduction remain unverified. That separate route needs Apple's Metal Toolchain to compile built-in GPU shaders. The source and exact producer patches are supplied; the tested libintl replacement path uses the supplied engine objects for the other components.

The Fuchsia-derived simdutf credit remains verbatim. Source-history inspection traces it through [simdutf's initial source](https://github.com/simdutf/simdutf/blob/9180c9ef4c295c897d3da9330935a7b8b7c24552/src/fallback/implementation.cpp) and the [simdjson attribution addition](https://github.com/simdjson/simdjson/commit/2bb101bd1938b0f48a67c585a4afe70e789e753f). Those sources identify it as Apache-licensed but do not name the original Fuchsia revision or copyright header. The available upstream attribution and Apache text are retained; no missing author/revision is invented. This is the boundary of the available provenance evidence, not a claim that a new original notice was recovered.

Notice integrity and a successful relink are not a general legal or security certification.

`LICENSES/SHA256SUMS` records the checked-in license texts. `scripts/verify-licenses.sh` checks their integrity and byte-for-byte inclusion in the packaged app, including the original bash-preexec resource notice. It performs no network requests and is not a legal-clearance or privacy scanner.

Taskport's app icon in `Resources/Taskport-Pills.icon` uses original SVG artwork. Source publication checks and signing/notarization requirements are documented separately in `docs/public-source.md`.
