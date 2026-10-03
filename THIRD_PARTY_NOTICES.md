# Third-party notices

Taskport's original project material is licensed under GNU GPL version 3 only (`GPL-3.0-only`); see [LICENSE](LICENSE). Third-party components retain their own licenses and copyrights. The license texts below are checked in under `LICENSES/` and included with this document in the app's `Contents/Resources/` directory. Texts are preserved from the pinned sources, including embedded notices; a final newline is added where absent.

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
- The producer builds arm64/x86_64 macOS static libraries with Sentry, custom shaders, and the inspector disabled. Its workflow requests Zig `0.16.0`; the exact compiler artifact/revision has not been independently reproduced.

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
| simdutf | Vendored header declares **9.0.0**; Ghostty's package manifest still says 5.2.8 | [MIT](LICENSES/simdutf/LICENSE-MIT), [Apache-2.0](LICENSES/simdutf/LICENSE-APACHE), [embedded PyTorch-derived BSD notice](LICENSES/simdutf/PYTORCH-BSD-LICENSE) |
| Wuffs | `7411f488fe2e2c205c3d3b3d28638b7356522930`, generated v0.4 C code | [MIT option](LICENSES/Wuffs/LICENSE-MIT) |
| stb_image / stb_image_resize | Vendored 2.28 / 0.97 in the pinned engine | [MIT option, identical notice in both headers](LICENSES/stb/LICENSE-MIT) |
| JetBrains Mono | 2.304 | [OFL-1.1](LICENSES/JetBrainsMono/OFL.txt), [authors](LICENSES/JetBrainsMono/AUTHORS.txt) |
| Symbols Nerd Font | SymbolsOnly 3.4.0 | [Archive's MIT notice](LICENSES/NerdFontsSymbolsOnly/LICENSE), [Ghostty-vendored Nerd Fonts licensing document](LICENSES/NerdFontsSymbolsOnly/NERD-FONTS-LICENSE); glyph audit remains open below |
| libxev | `9ce8e8e6ff89e583258a7f8e7adeeeaeae8611bf` | [MIT](LICENSES/libxev/LICENSE) |
| libvaxis | 0.6.0, `1dbbe575dff4586fe51e3217aa5c3fecdcbb6089` | [MIT](LICENSES/vaxis/LICENSE) |
| z2d | 0.12.1, `7dbae85c81784dba9988320bf9543ed9a81350c8` | [MPL-2.0](LICENSES/z2d/COPYING), [upstream notices including Cairo, Pixman, tiny-skia, and W3C](LICENSES/z2d/LICENSE) |
| zig-objc | `c8de82ff80281215ad92900866dab7103a8efa8b` | [MIT](LICENSES/zig-objc/LICENSE) |
| uucode | 0.2.0, `2826a37a4562284fdacd8fa029d49509cc9bffcd` | [MIT](LICENSES/uucode/LICENSE.md), [Unicode License V3](LICENSES/uucode/licenses/LICENSE_unicode), [Bjoern Hoehrmann UTF-8 decoder](LICENSES/uucode/licenses/LICENSE_Bjoern_Hoehrmann) |
| zf | 0.11.0, `c35c421f84895193246db06c40683c1a30e616ef` | [MIT](LICENSES/zf/LICENSE) |

This software is based in part on the work of the FreeType Team. Portions of this software are copyright © 2023 The FreeType Project (www.freetype.org). All rights reserved. Taskport selects the FreeType License (FTL); the separate embedded-code notices are also preserved.

Archive symbol inspection finds libintl, FreeType, libpng, zlib, Oniguruma, simdutf, Highway, and Wuffs functions. Zig-module notices above conservatively cover the imported source graph; this is not a claim that every imported function or platform-conditional dependency is in the binary. macOS uses CoreText by default, not the HarfBuzz/fontconfig backends. Excluded Linux/GTK libraries, disabled shader/inspector/Sentry components, and test-only dependencies are not treated as linked runtime components. The full z2d upstream notice is retained even where it describes its own test assets.

## Binary redistribution: remaining prerequisites

Bundling these files fixes notice packaging; it does **not** establish complete binary compliance. Do not distribute the development app as a release artifact until these items are resolved:

- Verify the exact corresponding source, producer patches, build inputs, and compiler/runtime license inventory for the downloaded artifact. The source links above record provenance, not a completed source distribution or source offer.
- Provide the applicable GPL corresponding-source, LGPL source/relinking materials for statically linked libintl, and MPL-covered source availability for z2d. Test the documented build/relink path rather than relying on download links alone.
- Finish the Symbols Nerd Font glyph-origin/attribution audit against the [pinned Nerd Fonts 3.4.0 license audit](https://github.com/ryanoasis/nerd-fonts/blob/v3.4.0/license-audit.md). An archive-level MIT notice does not by itself resolve every constituent glyph's terms. Verify embedded subcomponent notices, including the Fuchsia-derived simdutf code, against the actual source inputs.

`LICENSES/SHA256SUMS` records the checked-in license texts. `scripts/verify-licenses.sh` checks their integrity and byte-for-byte inclusion in the packaged app, including the original bash-preexec resource notice. It performs no network requests and is not a legal-clearance or privacy scanner.

Taskport's app icon in `Resources/Taskport-Pills.icon` uses original SVG artwork. Source publication checks and signing/notarization requirements are documented separately in `docs/public-source.md`.
