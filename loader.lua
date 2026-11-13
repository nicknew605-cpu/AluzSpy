local VERSION = "1.2.3-stable"
local ENV = (type(getgenv) == "function" and getgenv()) or _G
local REF = (type(ENV.AluzSpyRef) == "string" and ENV.AluzSpyRef ~= "") and ENV.AluzSpyRef or "main"
local ROOT = "https://raw.githubusercontent.com/nicknew605-cpu/AluzSpy/" .. REF .. "/src/"
local CACHE = "AluzSpy/bundle_" .. VERSION .. ".lua"
local DISABLED = type(ENV.AluzSpyDisable) == "table" and ENV.AluzSpyDisable or {}

local ORDER = {
	{ "core", true }, { "core2", false }, { "dump", true }, { "decode", false }, { "dump2", false },
	{ "deobfuscate", false }, { "dumpmax", false }, { "vm", false },
	{ "hooks", true }, { "hooks2", false }, { "deep", false }, { "health", false }, { "actor", false },
	{ "ai", true }, { "chain", false }, { "analysis", false }, { "reverse", false }, { "hybrid", false },
	{ "watch", true }, { "save", true }, { "vip", false }, { "ui", true }, { "runtime", true },
}

local DEPS = {
	core2 = { "core" },
	dump = { "core" },
	decode = { "core", "core2" },
	dump2 = { "core", "dump" },
	deobfuscate = { "core" },
	dumpmax = { "core", "dump" },
	vm = { "core" },
	hooks = { "core" },
	hooks2 = { "core" },
	deep = { "core", "dump" },
	health = { "core" },
	actor = { "core", "core2" },
	ai = { "core" },
	chain = { "core", "core2" },
	analysis = { "core", "core2" },
	reverse = { "core", "core2" },
	hybrid = { "core", "core2", "chain" },
	watch = { "core" },
	save = { "core" },
	vip = { "core", "core2" },
	ui = { "core" },
	runtime = { "core", "core2" },
}

local manifest = {
	version = VERSION, ref = REF, loaded = {}, failed = {}, disabled = {}, unversioned = {},
	missing_dep = {}, fromCache = false, order = {},
}
ENV.AluzSpyManifest = manifest

local function notify(title, text)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", { Title = title, Text = tostring(text), Duration = 6 })
	end)
end

local function fail(msg)
	manifest.fatal = tostring(msg)
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

local function headerVersion(src)
	return src:sub(1, 200):match("aluzspy@([%w%.%-]+)")
end

local function hashOf(s)
	local h = 5381
	for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967291 end
	return string.format("%08x", h)
end

pcall(function()
	if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder("AluzSpy") then makefolder("AluzSpy") end
end)

local function trace(msg)
	if ENV.AluzSpyTrace == true and type(appendfile) == "function" then
		pcall(appendfile, "AluzSpy/trace.log", string.format("%.2f loader %s\n", os.clock(), msg))
	end
end

if ENV.AluzSpyTrace == true and type(writefile) == "function" then pcall(writefile, "AluzSpy/trace.log", "") end
trace("start " .. VERSION)

local mods = {}
for _, m in ipairs(ORDER) do
	manifest.order[#manifest.order + 1] = m[1]
	if DISABLED[m[1]] and not m[2] then
		manifest.disabled[#manifest.disabled + 1] = m[1]
	else
		mods[#mods + 1] = { name = m[1], required = m[2], url = ROOT .. m[1] .. ".lua" }
	end
end

local stamp, pending, nextIdx = tostring(os.time()), #mods, 0
for _ = 1, math.min(6, #mods) do
	task.spawn(function()
		while true do
			nextIdx = nextIdx + 1
			local m = mods[nextIdx]
			if not m then return end
			for _ = 1, 2 do
				local ok, body = pcall(function() return game:HttpGet(m.url .. "?v=" .. stamp, true) end)
				if ok and type(body) == "string" and #body > 20 then
					m.src = body
					break
				end
				task.wait(0.4)
			end
			pending = pending - 1
		end
	end)
end

local t0 = os.clock()
while pending > 0 and os.clock() - t0 < 25 do task.wait(0.05) end
trace("downloaded, pending " .. pending)

local present = {}
for _, m in ipairs(mods) do if m.src then present[m.name] = true end end

local function depsOk(name)
	local d = DEPS[name]
	if not d then return true, nil end
	for _, dep in ipairs(d) do
		if not present[dep] then return false, dep end
	end
	return true, nil
end

local active, missing = {}, {}
for _, m in ipairs(mods) do
	if m.src then
		local ver = headerVersion(m.src)
		if ver and ver ~= VERSION then
			manifest.failed[m.name] = "version " .. ver
			m.src = nil
		elseif not ver then
			manifest.unversioned[#manifest.unversioned + 1] = m.name
		end
	end
	if m.src then
		local okd, dep = depsOk(m.name)
		if not okd then
			manifest.failed[m.name] = "missing dependency " .. tostring(dep)
			manifest.missing_dep[#manifest.missing_dep + 1] = m.name .. "->" .. tostring(dep)
			warn("[AluzSpy loader] skipped " .. m.name .. " (missing dependency " .. tostring(dep) .. ")")
			m.src = nil
		end
	end
	if m.src then
		active[#active + 1] = m
	else
		manifest.failed[m.name] = manifest.failed[m.name] or "download"
		if m.required then
			missing[#missing + 1] = m.name
		else
			warn("[AluzSpy loader] optional module skipped: " .. m.name .. " (" .. manifest.failed[m.name] .. ")")
		end
	end
end

local fn, err
if #missing > 0 then
	local cached = readCache()
	if not cached then
		fail("missing: " .. table.concat(missing, ", "))
		return
	end
	warn("[AluzSpy loader] required module missing, using cached bundle")
	fn, err = loadstring(cached, "=AluzSpy")
	manifest.fromCache = true
else
	for _ = 1, #active do
		local parts = {}
		for _, m in ipairs(active) do parts[#parts + 1] = m.src end
		fn, err = loadstring(table.concat(parts, "\n"), "=AluzSpy")
		if fn then break end

		local bad
		for i, m in ipairs(active) do
			local f, e = loadstring(m.src, "=" .. m.name)
			if not f then
				bad = i
				manifest.failed[m.name] = "syntax"
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

local bundleBody = table.concat((function()
	local t = {}
	for _, m in ipairs(active) do t[#t + 1] = m.src end
	return t
end)(), "\n")
manifest.hash = hashOf(bundleBody)
manifest.modules = #active

if not manifest.fromCache then
	for _, m in ipairs(active) do manifest.loaded[#manifest.loaded + 1] = m.name end
	if type(writefile) == "function" then
		pcall(writefile, CACHE, bundleBody)
		pcall(writefile, "AluzSpy/manifest.json", (function()
			local t = {}
			t[#t + 1] = '{"version":"' .. VERSION .. '"'
			t[#t + 1] = ',"ref":"' .. tostring(REF) .. '"'
			t[#t + 1] = ',"hash":"' .. tostring(manifest.hash) .. '"'
			t[#t + 1] = ',"modules":' .. tostring(#active)
			t[#t + 1] = ',"loaded":['
			for i, n in ipairs(manifest.loaded) do
				if i > 1 then t[#t + 1] = "," end
				t[#t + 1] = '"' .. n .. '"'
			end
			t[#t + 1] = ']}'
			return table.concat(t)
		end)())
	end
end

trace("compiled, running")
local ok, runErr = xpcall(fn, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
trace("run finished " .. tostring(ok))
if not ok then
	manifest.runError = tostring(runErr)
	fail("run: " .. tostring(runErr))
end
