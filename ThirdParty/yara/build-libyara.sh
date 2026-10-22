#!/bin/zsh
#
# Builds a universal (arm64 + x86_64) static libyara for JoClean.
#
# YARA (https://github.com/VirusTotal/yara) is BSD-3-Clause licensed; see LICENSE in this folder.
# The "hash" module uses Apple's CommonCrypto, so no OpenSSL is needed. Process scanning is
# disabled (USE_NO_PROC) because JoClean only scans files.
#
# Usage: ./build-libyara.sh            (re-run to update; outputs include/ and lib/libyara.a)
set -euo pipefail

YARA_VERSION="4.5.8"
YARA_SHA256="c322414975ff6f701149856613afdcd92a7e6939c284c798ae3c85618197efaa"
MIN_MACOS="14.0"

HERE="${0:A:h}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "→ Downloading YARA $YARA_VERSION"
curl -sSL -o "$WORK/yara.tar.gz" "https://github.com/VirusTotal/yara/archive/refs/tags/v$YARA_VERSION.tar.gz"
echo "$YARA_SHA256  $WORK/yara.tar.gz" | shasum -a 256 -c -
tar xzf "$WORK/yara.tar.gz" -C "$WORK"
SRC="$WORK/yara-$YARA_VERSION"

SOURCES=(
  libyara/ahocorasick.c libyara/arena.c libyara/atoms.c libyara/base64.c libyara/bitmask.c
  libyara/compiler.c libyara/endian.c libyara/exec.c libyara/exefiles.c libyara/filemap.c
  libyara/grammar.c libyara/hash.c libyara/hex_grammar.c libyara/hex_lexer.c libyara/lexer.c
  libyara/libyara.c libyara/mem.c libyara/modules.c libyara/notebook.c libyara/object.c
  libyara/parser.c libyara/proc.c libyara/re.c libyara/re_grammar.c libyara/re_lexer.c
  libyara/rules.c libyara/scan.c libyara/scanner.c libyara/simple_str.c libyara/sizedstr.c
  libyara/stack.c libyara/stopwatch.c libyara/strutils.c libyara/stream.c libyara/threading.c
  libyara/tlshc/tlsh.c libyara/tlshc/tlsh_impl.c libyara/tlshc/tlsh_util.c
  libyara/proc/none.c
  libyara/modules/tests/tests.c libyara/modules/elf/elf.c libyara/modules/math/math.c
  libyara/modules/time/time.c libyara/modules/pe/pe.c libyara/modules/pe/pe_utils.c
  libyara/modules/console/console.c libyara/modules/string/string.c
  libyara/modules/hash/hash.c libyara/modules/macho/macho.c libyara/modules/dotnet/dotnet.c
)

CFLAGS=(
  -O2 -DNDEBUG -pthread -w
  -mmacosx-version-min=$MIN_MACOS
  -DUSE_NO_PROC -DHAVE_SCAN_PROC_IMPL=0
  -DHASH_MODULE -DHAVE_COMMONCRYPTO_COMMONCRYPTO_H
  -DMACHO_MODULE -DDOTNET_MODULE
  -DBUCKETS_128=1 -DCHECKSUM_1B=1
  -I"$SRC/libyara/include" -I"$SRC/libyara"
)

for ARCH in arm64 x86_64; do
  echo "→ Compiling for $ARCH"
  OBJ="$WORK/obj-$ARCH"
  mkdir -p "$OBJ"
  for file in $SOURCES; do
    clang -arch $ARCH $CFLAGS -c "$SRC/$file" -o "$OBJ/${${file//\//_}%.c}.o"
  done
  libtool -static -o "$WORK/libyara-$ARCH.a" "$OBJ"/*.o
done

echo "→ Installing headers and universal library"
rm -rf "$HERE/include" "$HERE/lib"
mkdir -p "$HERE/include" "$HERE/lib"
cp "$SRC/libyara/include/yara.h" "$HERE/include/"
cp -R "$SRC/libyara/include/yara" "$HERE/include/"
lipo -create "$WORK/libyara-arm64.a" "$WORK/libyara-x86_64.a" -output "$HERE/lib/libyara.a"
cp "$SRC/COPYING" "$HERE/LICENSE"

# Swift module so app code can `import CYara`.
cat > "$HERE/include/module.modulemap" <<'MAP'
module CYara [system] {
    header "yara.h"
    link "yara"
    export *
}
MAP

lipo -info "$HERE/lib/libyara.a"
echo "✓ libyara $YARA_VERSION ready"
