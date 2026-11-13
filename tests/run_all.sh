#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
LUA="${LUA:-}"
if [ -z "$LUA" ]; then
  if command -v lua5.3 >/dev/null 2>&1; then LUA=lua5.3
  elif command -v lua >/dev/null 2>&1; then LUA=lua
  elif command -v texlua >/dev/null 2>&1; then LUA=texlua
  else echo "Lua 5.3+ not found (set LUA=...)"; exit 1; fi
fi
echo "== lua: $LUA"
echo; echo "== 1/4 build bundle =="
bash tests/build_bundle.sh
echo; echo "== 2/4 boot harness =="
"$LUA" tests/harness.lua bundle.lua
echo; echo "== 3/4 white-box test =="
cat bundle.lua tests/whitebox.lua > bundle_test.lua
"$LUA" tests/harness.lua bundle_test.lua
echo; echo "== 4/4 api smoke test + benchmark =="
"$LUA" tests/api_smoke.lua bundle.lua
cat bundle.lua tests/bench.lua > bundle_perf.lua
"$LUA" tests/harness.lua bundle_perf.lua
echo; echo "== done =="
