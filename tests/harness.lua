local bundlePath = arg and arg[1] or "bundle.lua"
local root = (bundlePath:gsub("[^/\\]+$", ""))
dofile(root .. "tests/mock/env.lua")
local warns = {}
_G.warn = function(s) warns[#warns+1] = tostring(s) end
local P = print
local chunk = assert(loadfile(bundlePath))
local c = assert(load(chunk, "=AluzSpy"))
local ok, rerr = pcall(c)
P(string.format("=== boot ok=%s%s", tostring(ok), ok and "" or ("  err=" .. tostring(rerr):sub(1,400))))
if #warns > 0 then
  P("=== warnings (" .. #warns .. "):")
  for _, w in ipairs(warns) do P("   " .. w:gsub("\n"," "):sub(1,220)) end
end
if not ok then os.exit(1) end
