local FORCE = nil

local ROOT = "https://raw.githubusercontent.com/nicknew605-cpu/AluzSpy/refs/heads/main/"
local CFGP, BOOTP = "AluzSpy/channel.json", "AluzSpy/.boot"
local ORDER = {
	{ "core", "src", true }, { "core2", "beta", false }, { "dump", "src", true }, { "decode", "src", false },
	{ "dump2", "beta", false }, { "hooks", "src", true }, { "hooks2", "src", false }, { "health", "beta", false },
	{ "actor", "beta", false }, { "ai", "src", true }, { "save", "src", true }, { "analysis", "beta", false },
	{ "ui", "src", true }, { "runtime", "src", true },
}

local genv
do
	local ok, g = pcall(getgenv)
	genv = (ok and type(g) == "table") and g or _G
end
local HS = game:GetService("HttpService")

local function notify(title, text)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", { Title = title, Text = tostring(text), Duration = 6 })
	end)
end
local function fail(msg)
	warn("[AluzSpy loader] " .. tostring(msg))
	notify("AluzSpy FAIL", tostring(msg):sub(1, 90))
end
local function fexists(p)
	if type(isfile) ~= "function" then return false end
	local ok, r = pcall(isfile, p)
	return ok and r == true
end
local function fread(p)
	if type(readfile) ~= "function" or not fexists(p) then return nil end
	local ok, r = pcall(readfile, p)
	if ok and type(r) == "string" then return r end
	return nil
end
local function fwrite(p, d)
	if type(writefile) == "function" then pcall(writefile, p, d) end
end

pcall(function()
	if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder("AluzSpy") then makefolder("AluzSpy") end
end)

local cfg = { channel = "Stable", crashes = 0 }
do
	local txt = fread(CFGP)
	if txt then
		local ok, t = pcall(HS.JSONDecode, HS, txt)
		if ok and type(t) == "table" then
			if t.channel == "Beta" or t.channel == "Stable" then cfg.channel = t.channel end
			cfg.crashes = tonumber(t.crashes) or 0
		end
	end
end

local channel = FORCE or genv.AluzChannel or cfg.channel
if channel ~= "Beta" then channel = "Stable" end

if channel == "Beta" then
	if fexists(BOOTP) and not genv.AluzSpy then
		local ts = tonumber((fread(BOOTP) or ""):match("\n(%d+)"))
		if ts and math.abs(os.time() - ts) < 1800 then cfg.crashes = cfg.crashes + 1 end
		if cfg.crashes >= 2 then
			channel = "Stable"
			cfg.crashes = 0
			notify("AluzSpy", "Beta crashed twice, back to Stable")
		end
	elseif not fexists(BOOTP) then
		cfg.crashes = 0
	end
end
cfg.channel = FORCE or channel
if FORCE == nil and channel == "Stable" and (genv.AluzChannel == "Beta" or cfg.channel == "Beta") then cfg.channel = "Stable" end
fwrite(CFGP, HS:JSONEncode(cfg))
genv.AluzChannel = channel

local mods = {}
for _, m in ipairs(ORDER) do
	if m[2] == "src" or channel == "Beta" then
		mods[#mods + 1] = { name = m[1], url = ROOT .. m[2] .. "/" .. m[1] .. ".lua", required = m[3] }
	end
end

local stamp, pending = tostring(os.time()), #mods
for i = 1, #mods do
	task.spawn(function()
		for _ = 1, 2 do
			local ok, body = pcall(function() return game:HttpGet(mods[i].url .. "?v=" .. stamp, true) end)
			if ok and type(body) == "string" and #body > 20 then
				mods[i].src = body
				break
			end
			task.wait(0.4)
		end
		pending = pending - 1
	end)
end
local t0 = os.clock()
while pending > 0 and os.clock() - t0 < 25 do task.wait(0.05) end

local CACHE = "AluzSpy/bundle_" .. channel .. ".lua"
local active, missing = {}, {}
for _, m in ipairs(mods) do
	if m.src then
		active[#active + 1] = m
	elseif m.required then
		missing[#missing + 1] = m.name
	else
		warn("[AluzSpy loader] optional module skipped: " .. m.name)
	end
end

local fn, err, fromCache
if #missing > 0 then
	local cached = fread(CACHE)
	if not cached then fail("missing: " .. table.concat(missing, ", ")) return end
	warn("[AluzSpy loader] offline, using cached bundle")
	fn, err = loadstring(cached, "=AluzSpy")
	fromCache = true
else
	for _ = 1, 5 do
		local parts = {}
		for _, m in ipairs(active) do parts[#parts + 1] = m.src end
		fn, err = loadstring(table.concat(parts, "\n"), "=AluzSpy")
		if fn then break end
		local bad
		for i, m in ipairs(active) do
			local f, e = loadstring(m.src, "=" .. m.name)
			if not f then
				bad = i
				warn("[AluzSpy loader] syntax in " .. m.name .. ": " .. tostring(e))
				break
			end
		end
		if not bad then break end
		if active[bad].required then
			fail("syntax in " .. active[bad].name)
			return
		end
		notify("AluzSpy", "dropped module: " .. active[bad].name)
		table.remove(active, bad)
	end
end
if not fn then
	fail("compile: " .. tostring(err))
	return
end

if not fromCache then
	local parts = {}
	for _, m in ipairs(active) do parts[#parts + 1] = m.src end
	fwrite(CACHE, table.concat(parts, "\n"))
end

local ok, runErr = xpcall(fn, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
if not ok then fail("run: " .. tostring(runErr)) end
