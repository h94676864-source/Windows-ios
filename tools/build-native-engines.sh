#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MADEIRA="$ROOT/Vendor/Madeira"
OUT="$ROOT/dist/native-engine"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
export ROOT JOBS

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || die "Native engine compilation requires macOS + Xcode."
command -v xcodebuild >/dev/null || die "Xcode is missing."
command -v brew >/dev/null || die "Homebrew is missing."
[[ -d "$MADEIRA/.git" || -f "$MADEIRA/.git" ]] || die "Vendor/Madeira submodule is not checked out."

# The app deployment target is a release invariant; do not silently change it
# to match the upstream engine's lower minimum deployment settings.
grep -A2 -E '^[[:space:]]*deploymentTarget:' "$ROOT/project.yml" | grep -Eq 'iOS:[[:space:]]*"18\.5"' ||
  die "project.yml must keep iOS deployment target 18.5."
grep -q 'IPHONEOS_DEPLOYMENT_TARGET: "18.5"' "$ROOT/project.yml" ||
  die "IPHONEOS_DEPLOYMENT_TARGET must remain 18.5."

log "Toolchain"
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
brew install cmake ninja meson pkg-config autoconf automake libtool bison flex sevenzip llvm
export PATH="$(brew --prefix bison)/bin:$(brew --prefix llvm)/bin:$PATH"

log "Resolve pinned Madeira engine sources"
git -C "$MADEIRA" submodule sync --recursive
git -C "$MADEIRA" submodule update --init --recursive --depth 1
git -C "$MADEIRA" submodule status --recursive

log "Install checksum-pinned LLVM-MinGW toolchain"
bash "$MADEIRA/tools/build/setup-llvm-mingw.sh"

log "Configure Wine host headers and ARM64EC build tree"
"$MADEIRA/tools/build/build-wine.sh"

log "Build FEX native iOS ARM64 core"
"$MADEIRA/tools/build/build-fex-ios.sh"

log "Build FEX ARM64EC guest translator"
bash "$MADEIRA/build/fex-arm64ec/build.sh"

log "Build Wine cryptography and media dependencies"
bash "$MADEIRA/build/gnutls-ios/build.sh"
"$MADEIRA/tools/build/sync-gnutls-libs.sh"
bash "$MADEIRA/build/ffmpeg/build.sh"
"$MADEIRA/tools/build/build-freetype-ios.sh"

log "Build Wine in-process server and iOS Unix side"
bash "$MADEIRA/build/wineserver/build.sh"
bash "$MADEIRA/build/ntdll-unix/build.sh"
bash "$MADEIRA/build/win32u-unix/build.sh"

log "Build LLVM support and Metal shader headers for DXMT"
"$MADEIRA/tools/build/build-llvm-ios.sh"
xcodebuild -downloadComponent MetalToolchain
"$MADEIRA/tools/build/build-shader-headers.sh"
bash "$MADEIRA/build/dxmt-ios/build.sh"

log "Build Wine ARM64EC PE runtime"
bash "$MADEIRA/build/wine-pe/build-ntdll.sh"
bash "$MADEIRA/build/wine-pe/build-modules.sh" cryptsp d3dx11_43 msvcp110 msvcr110 xaudio2_7

log "Validate required engine outputs"
required=(
  "$MADEIRA/FEX/build-ios/FEXCore/Source/libFEXCore.a"
  "$MADEIRA/FEX/build-ios/FEXCore/Source/libFEXCore_Base.a"
  "$MADEIRA/FEX/build-arm64ec/Bin/libarm64ecfex.dll"
  "$MADEIRA/app/Madeira/libwineserver.a"
  "$MADEIRA/app/Madeira/libntdll_unix.a"
  "$MADEIRA/app/Madeira/libwin32u_unix.a"
  "$MADEIRA/build/dxmt-ios/libdxmt_unix.a"
  "$MADEIRA/app/Madeira/arm64ec-windows/ntdll.dll"
)
for f in "${required[@]}"; do
  [[ -s "$f" ]] || die "Expected native output missing or empty: $f"
done

log "Stage reproducible engine-source build artifact"
rm -rf "$OUT"
mkdir -p "$OUT"
{
  printf 'repository_commit=%s\n' "$(git -C "$ROOT" rev-parse HEAD)"
  printf 'madeira_commit=%s\n' "$(git -C "$MADEIRA" rev-parse HEAD)"
  printf 'ios_deployment_target=18.5\n'
  printf 'xcode_version=%s\n' "$(xcodebuild -version | tr '\n' ' ')"
  printf 'iphoneos_sdk=%s\n' "$(xcrun --sdk iphoneos --show-sdk-version)"
  printf 'fex_native=compiled\n'
  printf 'fex_arm64ec=compiled\n'
  printf 'wine_unix_and_server=compiled\n'
  printf 'wine_arm64ec_pe_core=compiled\n'
  printf 'dxmt_ios_unix_side=compiled\n'
  printf 'app_framework_abi_adapter=not_yet_linked\n'
} > "$OUT/build-manifest.txt"
cp "${required[@]}" "$OUT/"
ditto "$MADEIRA/FEX/build-ios/FEXCore/Source/libFEXCore.a" "$OUT/libFEXCore.a"
ditto "$MADEIRA/FEX/build-ios/FEXCore/Source/libFEXCore_Base.a" "$OUT/libFEXCore_Base.a"
ditto "$MADEIRA/FEX/build-arm64ec/Bin/libarm64ecfex.dll" "$OUT/libarm64ecfex.dll"
ditto "$MADEIRA/app/Madeira/libwineserver.a" "$OUT/libwineserver.a"
ditto "$MADEIRA/app/Madeira/libntdll_unix.a" "$OUT/libntdll_unix.a"
ditto "$MADEIRA/app/Madeira/libwin32u_unix.a" "$OUT/libwin32u_unix.a"
ditto "$MADEIRA/build/dxmt-ios/libdxmt_unix.a" "$OUT/libdxmt_unix.a"
ditto "$MADEIRA/app/Madeira/arm64ec-windows/ntdll.dll" "$OUT/ntdll-arm64ec.dll"
for name in cryptsp d3dx11_43 msvcp110 msvcr110 xaudio2_7; do
  ditto "$MADEIRA/app/Madeira/arm64ec-windows/$name.dll" "$OUT/$name-arm64ec.dll"
done
(cd "$OUT" && shasum -a 256 * > SHA256SUMS)
mkdir -p "$ROOT/dist"
tar -czf "$ROOT/dist/WinlatorIOS-Native-Engine-Sources.tar.gz" -C "$OUT" .
shasum -a 256 "$ROOT/dist/WinlatorIOS-Native-Engine-Sources.tar.gz"
