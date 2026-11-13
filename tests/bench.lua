-- AluzSpy testkit :: bench.lua
-- Benchmark các hot-path. File này được NỐI VÀO CUỐI bundle.
--
--   cat bundle.lua tests/bench.lua > bundle_perf.lua
--   texlua tests/harness.lua bundle_perf.lua

local function bench(name, fn, reps)
  local t0 = os.clock()
  for i = 1, reps do fn(i) end
  local dt = os.clock() - t0
  print(string.format("  %-42s %8.1f ms total  %7.2f ms/op", name, dt * 1000, dt * 1000 / reps))
end

local big = string.rep("local function f(a) return a + 1 end\n", 2000)  -- ~90 KB
local mid = string.rep("local function f(a) return a + 1 end\n", 300)   -- ~13 KB

print("\n===== PERF HOT PATHS =====")
bench("F.fingerprint (90KB source)", function() F.fingerprint(big .. tostring(math.random()), nil) end, 10)
bench("D.obf (90KB source)", function() D.obf(big .. tostring(math.random())) end, 10)
bench("F.decodeCore (13KB source)", function() F.decodeCore(mid .. tostring(math.random())) end, 5)
bench("F.decodeCore (90KB source)", function() F.decodeCore(big .. tostring(math.random())) end, 3)
bench("D.add + hash (13KB source)", function() D.add(mid .. tostring(math.random()), "p", nil, nil, nil) end, 10)
bench("F.redact (200KB json-ish)", function() F.redact(string.rep('{"a":"b"},', 10000)) end, 5)
bench("ser (args table)", function() ser({1, "two", {3, 4}, {a = 1}}, 0, {}) end, 2000)
bench("enqueue x1000", function() for i = 1, 1000 do enqueue({ k = 1, d = "B", m = "x", a = { n = 0 }, t = clock() }) end end, 3)
