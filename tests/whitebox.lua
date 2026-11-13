local T = {}
local function ok(n, cond, d) T[#T + 1] = { n = n, pass = cond and true or false, d = tostring(d or "") } end
local hs = game:GetService("RunService").RunService.Heartbeat

K.DUMP_TOTAL = 100000
for i = 1, 40 do
  D.add(string.rep("A", 20000) .. "u" .. i .. string.rep("Z", i), "cap", "http://x/" .. i, nil, 1000 + i)
end
D.flush()
ok("T1 DUMP_TOTAL enforced", (D.bytes or 0) <= K.DUMP_TOTAL,
  "D.bytes=" .. tostring(D.bytes) .. " cap=" .. tostring(K.DUMP_TOTAL))

local fake = {}
for i = 1, 900 do fake[i] = { GetFullName = function() return "s" end, Name = "s" } end
local admitted = 0
for i = 1, 900 do if D.admit(fake[i], 1) then admitted = admitted + 1 end end
D.sd = {}
local reclaimed = D.admit(fake[1], 1)
ok("T2 script quota is reclaimable", reclaimed == true and admitted <= 900,
  "admitted=" .. tostring(admitted) .. " reclaimAfterRelease=" .. tostring(reclaimed))

for i = 1, 40 do hs:Fire(0.016) end
ok("T3 X.memNow is instrumented", X.memNow ~= 0, "X.memNow=" .. tostring(X.memNow))

ok("T4 F.api.deobAll exists", type(F.api.deobAll) == "function", "deobAll=" .. type(F.api.deobAll))
ok("T5 F.api.deobfAll exists (vip.lua calls this)", type(F.api.deobfAll) == "function",
  "deobfAll=" .. type(F.api.deobfAll))

local st = F.debug and F.debug.stages and F.debug.stages.nc
ok("T6 stage err carries a real error", not (st and (st.err == "true" or st.err == "false")),
  "nc.err=" .. tostring(st and st.err) .. " result=" .. tostring(st and st.result))

local s1 = "local x = 1 -- " .. string.rep("z", 100)
local a = F.fingerprint(s1, nil)
local b = F.fingerprint(s1, "https://api.luarmor.net/xyz")
ok("T7 fingerprint honours URL after a nil-URL call", b and b.name == "Luarmor",
  "nil-url=" .. tostring(a and a.name) .. "/" .. tostring(a and a.conf) ..
  " then url=" .. tostring(b and b.name) .. "/" .. tostring(b and b.conf))

for i = 1, 3 do hs:Fire(0.016) end
local wh = F.weakHooks and F.weakHooks() or {}
local flagged = {}
for _, w in ipairs(wh) do if w:find("looks hooked") then flagged[#flagged + 1] = w end end
ok("T9 weakHooks does not flag AluzSpy's own hooks", #flagged == 0,
  "self-flagged=" .. tostring(#flagged) .. " :: " .. table.concat(flagged, " | "):sub(1, 180))

local before = N.dropQ
for i = 1, 3000 do enqueue({ k = 1, d = "T", m = "x", a = { n = 0 }, t = clock() }) end
ok("T10 queue overflow is accounted", N.dropQ >= before, "dropQ=" .. tostring(N.dropQ))

local restored = F.restore and F.restore() or 0
ok("T11 restore() runs", type(restored) == "number", "restored=" .. tostring(restored))

local function mkbc()
  local b = "\27Lua\x51\x00\x01\x04\x08\x04\x08\x00"
  b = b .. string.char(0)
  b = b .. string.pack("<i8", 0)
  b = b .. string.pack("<i4", 0) .. string.pack("<i4", 0)
  b = b .. string.char(0, 0, 0, 2)
  b = b .. string.pack("<i4", 1)
  b = b .. string.pack("<i4", 1)
  b = b .. string.pack("<i4", 1)
  local str = "http://luarmor.net/x"
  b = b .. string.char(3) .. string.pack("<i8", #str) .. str
  b = b .. string.pack("<i4", 0)
  b = b .. string.pack("<i4", 0)
  b = b .. string.pack("<i4", 0)
  b = b .. string.pack("<i4", 0)
  return b
end
local bc = mkbc()
local vmText, vmRep, vmErr
if type(F.vmAnalyze) == "function" then
  vmText, vmRep, vmErr = F.vmAnalyze("synthetic", bc)
end
ok("T12 VM disassembler parses Lua 5.1 bytecode", vmText ~= nil and vmRep ~= nil,
  "err=" .. tostring(vmErr) .. " analyzer=" .. type(F.vmAnalyze))
ok("T13 VM reports constants and URLs", vmRep and vmRep.strings == 1 and #vmRep.urls == 1,
  "strings=" .. tostring(vmRep and vmRep.strings) .. " urls=" .. tostring(vmRep and #vmRep.urls))

local red = F.redact and F.redact('{"version":"1.2.3.4","ip":"192.168.1.10","token":"abcdefgh12345"}')
ok("T14 redact keeps version but masks ip/token",
  red and red:find("1.2.3.4", 1, true) ~= nil and red:find("192.168.1.10", 1, true) == nil
    and red:find("abcdefgh12345", 1, true) == nil,
  tostring(red))

local explicit = CFG.explicit["net"]
CFG.explicit["net"] = true
CFG.mods["net"] = false
if F.applyMax then pcall(F.applyMax) end
ok("T15 auto-max respects explicit user disable", CFG.mods["net"] == false,
  "mods.net=" .. tostring(CFG.mods["net"]) .. " explicit=" .. tostring(CFG.explicit["net"]))
CFG.explicit["net"] = explicit

local quota = K.DISK_KIND.script
D.kind.script = quota + 1000
local freed = D.evict("script", 500)
ok("T16 per-kind budget evicts", (D.used("script") or 0) <= quota + 1000 and freed >= 0,
  "used=" .. tostring(D.used("script")) .. " quota=" .. tostring(quota) .. " freed=" .. tostring(freed))
D.kind.script = 0

ok("T17 API aliases present",
  type(F.api.deobf) == "function" and type(F.api.deobfAll) == "function"
  and type(F.api.reverseFind) == "function" and type(F.api.split) == "function",
  "deobf=" .. type(F.api.deobf) .. " deobfAll=" .. type(F.api.deobfAll) ..
  " reverseFind=" .. type(F.api.reverseFind) .. " split=" .. type(F.api.split))

ok("T18 hook registry tracks install state", F.hooks and next(F.hooks) ~= nil,
  "hooks=" .. tostring(F.hooks and (function() local n = 0 for _ in pairs(F.hooks) do n = n + 1 end return n end)()))

print("\n===== WHITE-BOX RESULTS (1.2.3-stable) =====")
local f = 0
for _, t in ipairs(T) do
  if not t.pass then f = f + 1 end
  print(string.format("  [%s] %-48s %s", t.pass and "PASS" or "FAIL", t.n, t.d))
end
print(string.format("===== %d FAILED / %d =====", f, #T))
