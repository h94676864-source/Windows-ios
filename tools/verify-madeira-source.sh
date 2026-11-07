#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

EXPECTED_MADEIRA="8b52c1810a0b77614238001ed86199978865afd1"
ACTUAL_MADEIRA="$(git -C Vendor/Madeira rev-parse HEAD 2>/dev/null || true)"
if [[ "$ACTUAL_MADEIRA" != "$EXPECTED_MADEIRA" ]]; then
  echo "::error::Madeira source mismatch: expected $EXPECTED_MADEIRA, got ${ACTUAL_MADEIRA:-missing}"
  exit 1
fi

# Ensure the upstream engine graph is pinned to the exact tested source commits.
declare -A EXPECTED=(
  [FEX]="1dc6ed4932bd231df1c53dd7b8043ffdee0ac34a"
  [wine]="ddf92babc5ba71f4586cc4713f5a8eb39f63d39b"
  [dxmt]="3d62913b75fb8b21ad6494f9d9f9853b19d9a014"
  [madeira-dock]="67780ba92e60dbfac4fe80eaf2ce34b9ea1a1c60"
)
for path in "${!EXPECTED[@]}"; do
  entry="$(git -C Vendor/Madeira ls-tree HEAD -- "$path")"
  actual="$(awk '{print $3}' <<<"$entry")"
  type="$(awk '{print $2}' <<<"$entry")"
  if [[ "$type" != "commit" || "$actual" != "${EXPECTED[$path]}" ]]; then
    echo "::error::Unexpected upstream pin for $path: type=$type sha=${actual:-missing}"
    exit 1
  fi
  echo "Verified $path -> $actual"
done

TARGET="$(sed -n 's/^[[:space:]]*iOS: "\([0-9.]*\)"/\1/p' project.yml | head -n1)"
if [[ "$TARGET" != "18.5" ]]; then
  echo "::error::iOS deployment target changed unexpectedly: $TARGET"
  exit 1
fi

if ! grep -q 'No Wine engine is bundled in this IPA' apps/iOS/Sources/Services/WinlatorWineRuntimeAdapter.swift; then
  echo "::error::Wine runtime status must explicitly report missing engine payload."
  exit 1
fi

echo "Madeira source graph verified. This audit does not build or bundle Wine/FEX/DXMT and does not prove iOS 18.5 compatibility."
