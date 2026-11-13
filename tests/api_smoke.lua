-- AluzSpy testkit :: api_smoke.lua
-- Smoke test toàn bộ API công khai + đối chiếu hợp đồng API với README.
--
--   texlua tests/api_smoke.lua <bundle.lua>
--
-- Chạy độc lập (không nối vào bundle) — nó tự boot bundle trước.

local bundlePath = arg and arg[1] or "bundle.lua"
local root = (bundlePath:gsub("[^/\\]+$", ""))

dofile(root .. "tests/mock/env.lua")

local warns = {}
_G.warn = function(s) warns[#warns + 1] = tostring(s) end
local P = print

local chunk = assert(loadfile(bundlePath))
local c = assert(load(chunk, "=AluzSpy"))
pcall(c)

local A = _G.AluzSpy
P("AluzSpy present: " .. tostring(type(A)))

local hs = game:GetService("RunService").RunService.Heartbeat
for i = 1, 5 do hs:Fire(0.016) end

local results = {}
local function T(n, f, ...)
  local ok, r = pcall(f, ...)
  results[n] = ok
  if not ok then
    P(string.format("  [FAIL] %-22s %s", n, tostring(r):gsub("\n", " "):sub(1, 150)))
  end
end

P("\n=== API SURFACE ===")
T("help", A.help); T("stats", A.stats); T("errors", A.errors); T("modules", A.modules)
T("paths", A.paths); T("report", A.report); T("stageReport", A.stageReport)
T("health", A.health); T("debug", A.debug); T("top", A.top, 5); T("find", A.find, "x", 5)
T("watch", A.watch); T("alerts", A.alerts); T("schema", A.schema, "")
T("deobfReport", A.deobfReport); T("reverse", A.reverse, "status")
T("vip", A.vip, "status"); T("vipProfile", A.vip, "profile", "max")
T("vipSafe", A.vip, "safe"); T("vipReport", A.vip, "report"); T("vipRedact", A.vip, "redact")
T("dumpIndex", A.dumpIndex); T("fullDump", A.fullDump); T("dumpReport", A.dumpReport)
T("ext", A.ext); T("split", A.split, true); T("saveIndex", A.saveIndex)
T("gcmap", A.gcmap, false); T("scriptDiff", A.scriptDiff); T("tree", A.tree)
T("callgraph", A.callgraph); T("actors", A.actors); T("set", A.set, "autoDeobf", true)
T("protect", A.protect, "X"); T("threshold", A.threshold, "X", 2)
T("block", A.block, "X"); T("modify", A.modify, "X", function() end)
T("unblock", A.unblock, "X"); T("unmodify", A.unmodify, "X"); T("unprotect", A.unprotect, "X")
T("dump", A.dump, true); T("dumpScripts", A.dumpScripts); T("nc", A.nc, true)
T("mod", A.mod, "net", true); T("save", A.save); T("debugAll", A.debugAll)
T("deobf", A.deobf); T("deobfAll", A.deobfAll); T("deobfuscate", A.deobfuscate, "-- hi")
T("decode", A.decode, "local a = 1"); T("analyze", A.analyze, "local a = 1")
T("decodeAll", A.decodeAll); T("missing", A.missing); T("chain", A.chain)
T("reverseFind", A.reverseFind, "x"); T("whoCalls", A.whoCalls, "x"); T("reset", A.reset)

local fails, total = 0, 0
for _, v in pairs(results) do total = total + 1; if not v then fails = fails + 1 end end
P(string.format("\n=== API FAILURES: %d / %d", fails, total))

-- Hợp đồng API: các lệnh README quảng bá phải tồn tại.
P("\n=== README <-> API CONTRACT ===")
local documented = {
  "help", "save", "fullDump", "dumpIndex", "paths", "watch", "debugAll", "stageReport",
  "vip", "deobf", "deobfAll", "deobfReport", "reverse", "reverseFind",
  "protect", "threshold", "modules", "health", "set",
}
local missing = {}
for _, name in ipairs(documented) do
  if type(A[name]) ~= "function" then missing[#missing + 1] = name end
end
P("missing (documented but absent): " .. (#missing > 0 and table.concat(missing, ", ") or "none"))

if #warns > 0 then
  P("\n=== WARNINGS (" .. #warns .. "):")
  for _, w in ipairs(warns) do P("   " .. w:gsub("\n", " "):sub(1, 180)) end
end
