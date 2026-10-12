local ROOT = "https://raw.githubusercontent.com/nicknew605-cpu/AluzSpy/refs/heads/main/src/"
local CACHE = "AluzSpy/bundle.lua"
local ORDER = {
	{ "core", true }, { "core2", false }, { "dump", true }, { "decode", false }, { "dump2", false },
	{ "hooks", true }, { "hooks2", false }, { "deep", false }, { "health", false }, { "actor", false },
	{ "ai", true }, { "chain", false }, { "analysis", false }, { "hybrid", false },
	{ "save", true }, { "ui", true }, { "runtime", true },
}

local function notify(title, text)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", { Title = title, Text = tostring(text), Duration = 6 })
	end)
end
local function fail(msg)
	warn("[AluzSpy loader] " .. tostring(msg))
	notify("AluzSpy FAIL", tostring(msg):sub(1, 90))
end
local function readCache()
	if type(isfile) == "function" and type(readfile) == "function" then
		local ok, has = pcall(isfile, CACHE)
		if ok and has then
			local ok2, body = pcall(readfile, CACHE)
			if ok2 and type(body) == "string" and #body > 1000 then return body end
		end
	end
	return nil
end

pcall(function()
	if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder("AluzSpy") then makefolder("AluzSpy") end
end)

local mods = {}
for _, m in ipairs(ORDER) do
	mods[#mods + 1] = { name = m[1], required = m[2], url = ROOT .. m[1] .. ".lua" }
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
	local cached = readCache()
	if not cached then fail("missing: " .. table.concat(missing, ", ")) return end
	warn("[AluzSpy loader] offline, using cached bundle")
	fn, err = loadstring(cached, "=AluzSpy")
	fromCache = true
else
	for _ = 1, 6 do
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

if not fromCache and type(writefile) == "function" then
	local parts = {}
	for _, m in ipairs(active) do parts[#parts + 1] = m.src end
	pcall(writefile, CACHE, table.concat(parts, "\n"))
end

local ok, runErr = xpcall(fn, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
if not ok then fail("run: " .. tostring(runErr)) end
