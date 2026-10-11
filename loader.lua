local BASE = "https://raw.githubusercontent.com/nicknew605-cpu/AluzSpy/refs/heads/main/src/"
local CACHE = "AluzSpy/bundle.lua"
local ORDER = {
	{ "core", true }, { "dump", true }, { "decode", false }, { "hooks", true }, { "hooks2", false },
	{ "ai", true }, { "save", true }, { "ui", true }, { "runtime", true },
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

local stamp = tostring(os.time())
local results, pending = {}, #ORDER
for i = 1, #ORDER do
	task.spawn(function()
		for _ = 1, 2 do
			local ok, body = pcall(function()
				return game:HttpGet(BASE .. ORDER[i][1] .. ".lua?v=" .. stamp, true)
			end)
			if ok and type(body) == "string" and #body > 20 then
				results[i] = body
				break
			end
			task.wait(0.4)
		end
		pending = pending - 1
	end)
end

local t0 = os.clock()
while pending > 0 and os.clock() - t0 < 25 do
	task.wait(0.05)
end

local parts, missing = {}, {}
for i = 1, #ORDER do
	if results[i] then
		parts[#parts + 1] = results[i]
	elseif ORDER[i][2] then
		missing[#missing + 1] = ORDER[i][1]
	else
		warn("[AluzSpy loader] optional module skipped: " .. ORDER[i][1])
	end
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

local src, fromCache
if #missing == 0 then
	src = table.concat(parts, "\n")
else
	src = readCache()
	fromCache = true
	if not src then
		fail("missing: " .. table.concat(missing, ", "))
		return
	end
	warn("[AluzSpy loader] offline, using cached bundle (missing: " .. table.concat(missing, ", ") .. ")")
end

local fn, err = loadstring(src, "=AluzSpy")
if not fn then
	for i = 1, #ORDER do
		if results[i] then
			local f, e = loadstring(results[i], "=" .. ORDER[i][1])
			if not f then
				fail("syntax in " .. ORDER[i][1] .. ": " .. tostring(e))
				return
			end
		end
	end
	fail("bundle compile: " .. tostring(err))
	return
end

if not fromCache and type(writefile) == "function" then
	pcall(function()
		if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder("AluzSpy") then
			makefolder("AluzSpy")
		end
		writefile(CACHE, src)
	end)
end

local ok, runErr = xpcall(fn, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)
if not ok then
	fail("run: " .. tostring(runErr))
end
