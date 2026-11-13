#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/bundle.lua}"
ORDER="core core2 dump decode dump2 deobfuscate dumpmax vm hooks hooks2 deep health actor ai chain analysis reverse hybrid watch save vip ui runtime"
: > "$OUT"
for m in $ORDER; do
  if [ ! -f "$ROOT/src/$m.lua" ]; then echo "missing module: src/$m.lua" >&2; exit 1; fi
  cat "$ROOT/src/$m.lua" >> "$OUT"
  echo "" >> "$OUT"
done
echo "bundle written: $OUT ($(wc -l < "$OUT") lines, 23 modules)"
