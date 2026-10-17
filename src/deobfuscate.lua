local okDE, errDE = xpcall(function()
	F.api = F.api or {}
	if CFG.deob == nil then CFG.deob = true end
	if CFG.autoDeobf == nil then CFG.autoDeobf = false end
	F.deob = F.deob or {}
	local DE = F.deob
	DE.stats = { runs = 0, ok = 0, fail = 0, strings = 0, urls = 0, flags = 0, layers = 0, auto = 0 }
	DE.pending = DE.pending or {}
	DE.busy = false
	local unpack = table.unpack or unpack
	local floor = math.floor
	local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local B64INV = {}
	for i = 1, #B64 do B64INV[B64:sub(i, i)] = i - 1 end

	local FLAGW = {
		loadstring = 15, HttpGet = 10, HttpPost = 10, request = 8, http_request = 8,
		websocket = 8, getfenv = 5, setfenv = 5, hookfunction = 10, hookmetamethod = 10,
		getrawmetatable = 8, setreadonly = 6, checkcaller = 5, isexecutorclosure = 5,
		["string.dump"] = 8, ["debug.traceback"] = 4, Kick = 4, ROBLOSECURITY = 25,
		webhooks = 20, telegram = 18, grabify = 15, iplogger = 15,
	}

	local function add(t, v, cap)
		if #t >= cap then return end
		t[#t + 1] = v
	end

	local function b64decode(s)
		if type(crypt) == "table" and type(crypt.base64decode) == "function" then
			local ok, r = pcall(crypt.base64decode, s)
			if ok and type(r) == "string" then return r end
		end
		s = s:gsub("[^%w%+/=]", "")
		local n = #s
		if n < 4 or n % 4 ~= 0 then return nil end
		local out = {}
		local i = 1
		while i <= n do
			local c1 = B64INV[s:sub(i, i)]
			local c2 = B64INV[s:sub(i + 1, i + 1)]
			if not c1 or not c2 then return nil end
			local p3 = s:sub(i + 2, i + 2)
			local p4 = s:sub(i + 3, i + 3)
			local c3 = p3 ~= "=" and B64INV[p3] or nil
			local c4 = p4 ~= "=" and B64INV[p4] or nil
			if p3 ~= "=" and not c3 then return nil end
			if p4 ~= "=" and not c4 then return nil end
			local num = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)
			out[#out + 1] = string.char(floor(num / 65536) % 256)
			if p3 ~= "=" then out[#out + 1] = string.char(floor(num / 256) % 256) end
			if p4 ~= "=" then out[#out + 1] = string.char(num % 256) end
			i = i + 4
		end
		return table.concat(out)
	end

	local function looksLua(s)
		if type(s) ~= "string" or #s < 16 then return false end
		local head = s:sub(1, 800)
		return head:find("local ", 1, true) ~= nil or head:find("function", 1, true) ~= nil
			or head:find("return", 1, true) ~= nil or head:find("game", 1, true) ~= nil
			or head:find("loadstring", 1, true) ~= nil
	end

	local function unescape(s)
		s = s:gsub("\\(%d%d?%d?)", function(d)
			local n = tonumber(d)
			if n and n >= 32 and n <= 126 then return string.char(n) end
			return "\\" .. d
		end)
		s = s:gsub("\\n", "\n")
		s = s:gsub("\\t", "\t")
		s = s:gsub("\\r", "\r")
		s = s:gsub('\\"', '"')
		s = s:gsub("\\'", "'")
		s = s:gsub("\\\\", "\\")
		return s
	end

	local function foldChar(s)
		local changed = true
		local pass = 0
		while changed and pass < 6 do
			changed = false
			pass = pass + 1
			s = s:gsub("string%.char%s*%(([%d%s%,]-)%)", function(args)
				local nums = {}
				for n in args:gmatch("%d+") do
					local v = tonumber(n)
					if not v or v < 0 or v > 255 then return nil end
					nums[#nums + 1] = v
					if #nums > 4096 then return nil end
				end
				if #nums == 0 then return nil end
				local ok, str = pcall(string.char, unpack(nums))
				if not ok or type(str) ~= "string" then return nil end
				changed = true
				return string.format("%q", str)
			end)
		end
		return s
	end

	local function foldConcat(s)
		local changed = true
		local pass = 0
		while changed and pass < 6 do
			changed = false
			pass = pass + 1
			s = s:gsub('"([^"\\]*)"%.%.%"([^"\\]*)"', function(a, b)
				changed = true
				return '"' .. a .. b .. '"'
			end)
			s = s:gsub("'([^'\\]*)'%.%.'([^'\\]*)'", function(a, b)
				changed = true
				return "'" .. a .. b .. "'"
			end)
		end
		return s
	end

	local function extractStrings(s, out, cap)
		for q in s:gmatch('"([^"\n]-)"') do add(out, q, cap) end
		for q in s:gmatch("'([^'\n]-)'") do add(out, q, cap) end
	end

	local function collectUrls(s, out)
		for u in s:gmatch("https?://[%w%-%._~:/%?#@!%$&%*%+,;=%%]+") do
			out[u] = true
		end
	end

	local function addLayer(layers, seen, via, s)
		if type(s) ~= "string" or #s < 16 or #layers >= 8 then return false end
		local k = via .. "|" .. #s .. "|" .. s:sub(1, 80)
		if seen[k] then return false end
		seen[k] = true
		layers[#layers + 1] = { via = via, bytes = #s, src = s:sub(1, 200000) }
		return true
	end

	local function decodeQuotedBase64(src, layers, seen)
		local changed = false
		for q in src:gmatch('"([A-Za-z0-9+/=]+)"') do
			if #q >= 40 and #q <= 200000 then
				local d = b64decode(q)
				if d and #d >= 16 and addLayer(layers, seen, "base64", d) then changed = true end
			end
		end
		for q in src:gmatch("'([A-Za-z0-9+/=]+)'") do
			if #q >= 40 and #q <= 200000 then
				local d = b64decode(q)
				if d and #d >= 16 and addLayer(layers, seen, "base64", d) then changed = true end
			end
		end
		return changed
	end

	local function extractLoadstring(src, layers, seen)
		local changed = false
		for q in src:gmatch('loadstring%s*%(%s*"([^"\n]-)"') do
			local u = unescape(q)
			if addLayer(layers, seen, "loadstring", u) then changed = true end
			local d = b64decode(u)
			if d and addLayer(layers, seen, "loadstring_b64", d) then changed = true end
		end
		for q in src:gmatch("loadstring%s*%(%s*'([^'\n]-)'") do
			local u = unescape(q)
			if addLayer(layers, seen, "loadstring", u) then changed = true end
			local d = b64decode(u)
			if d and addLayer(layers, seen, "loadstring_b64", d) then changed = true end
		end
		return changed
	end

	local function collectFlags(s, rep, seen)
		for k, w in pairs(FLAGW) do
			if s:find(k, 1, true) and not seen[k] then
				seen[k] = true
				rep.flags[#rep.flags + 1] = k
				rep.score = rep.score + w
			end
		end
	end

	function DE.run(src)
		DE.stats.runs = DE.stats.runs + 1
		local rep = { strings = {}, urls = {}, flags = {}, layers = {}, score = 0 }
		local urlSet, layerSeen, flagSeen = {}, {}, {}
		local text = src
		for pass = 1, 8 do
			local prev = text
			text = unescape(text)
			text = foldChar(text)
			text = foldConcat(text)
			local changed = text ~= prev
			if changed then addLayer(rep.layers, layerSeen, "static", text) end
			local c1 = decodeQuotedBase64(text, rep.layers, layerSeen)
			local c2 = extractLoadstring(text, rep.layers, layerSeen)
			if not changed and not c1 and not c2 then break end
		end
		extractStrings(text, rep.strings, 500)
		for _, l in ipairs(rep.layers) do
			extractStrings(l.src, rep.strings, 500)
		end
		collectUrls(text, urlSet)
		for _, l in ipairs(rep.layers) do collectUrls(l.src, urlSet) end
		for _, s in ipairs(rep.strings) do collectUrls(s, urlSet) end
		for u in pairs(urlSet) do add(rep.urls, u, 250) end
		collectFlags(text, rep, flagSeen)
		for _, l in ipairs(rep.layers) do collectFlags(l.src, rep, flagSeen) end
		if rep.score > 100 then rep.score = 100 end
		DE.stats.ok = DE.stats.ok + 1
		DE.stats.strings = DE.stats.strings + #rep.strings
		DE.stats.urls = DE.stats.urls + #rep.urls
		DE.stats.flags = DE.stats.flags + #rep.flags
		DE.stats.layers = DE.stats.layers + #rep.layers
		return text, rep
	end

	function DE.queue(ent, src)
		if not CFG.autoDeobf or not CFG.deob then return false end
		if ent.deobQ or #DE.pending >= 30 or type(src) ~= "string" then return false end
		if #src < 64 or #src > 400000 then return false end
		if F.isBin and F.isBin(src) then return false end
		ent.deobQ = true
		DE.pending[#DE.pending + 1] = { ent = ent, src = src }
		if not DE.busy then task.delay(1, DE.pump) end
		return true
	end

	function DE.pump()
		if DE.busy or not alive or #DE.pending == 0 then return end
		if X.fps < 18 or X.memNow > K.MEM_ABS * 0.82 then
			task.delay(2, DE.pump)
			return
		end
		local job = table.remove(DE.pending, 1)
		DE.busy = true
		local ok = F.job("deobAuto", function()
			local text, rep = DE.run(job.src)
			return { text = text, rep = rep, f = job.ent and job.ent.f or nil }
		end, function(res)
			DE.busy = false
			if type(res) == "table" and res.text then
				DE.stats.auto = DE.stats.auto + 1
				local base = (res.f or "dump"):gsub("%.lua$", "")
				pcall(FS.write, PATH.d(base .. ".deob.lua"), res.text)
				pcall(FS.write, PATH.d(base .. ".deob.json"), F.enc(res.rep) or "{}")
			end
			if #DE.pending > 0 then task.delay(1.2, DE.pump) end
		end)
		if not ok then DE.busy = false end
	end

	F.api.deobfuscate = function(x)
		if not CFG.deob then return nil, "disabled" end
		local src, nm
		if type(x) == "string" then
			if #x < 260 and not x:find("\n", 1, true) then
				src = FS.read(PATH.d(x)) or FS.read(x)
				nm = x
			else
				src = x
				nm = "inline"
			end
		end
		if type(src) ~= "string" or #src == 0 then return nil, "no source" end
		local ok, text, rep = pcall(DE.run, src)
		if not ok then
			DE.stats.fail = DE.stats.fail + 1
			return nil, tostring(text)
		end
		local base = nm == "inline" and ("inline_" .. os.time()) or (nm:match("([^/]+)$") or "inline"):gsub("%.lua$", "")
		pcall(FS.write, PATH.d(base .. ".deob.lua"), text)
		pcall(FS.write, PATH.d(base .. ".deob.json"), F.enc(rep) or "{}")
		for i, l in ipairs(rep.layers) do
			if l.src and #l.src >= 16 then
				pcall(FS.write, PATH.d(base .. ".layer" .. i .. ".lua"), l.src)
			end
		end
		return text, base, rep
	end

	F.api.deobAll = function(limit)
		if not CFG.deob or not F.job then return false end
		limit = tonumber(limit) or 50
		local jobs = {}
		for _, ent in ipairs(D.list or {}) do
			if #jobs >= limit then break end
			if not ent.dup and ent.f then
				local body = D.store and D.store[ent.f] or FS.read(PATH.d(ent.f))
				if body and #body >= 64 and #body <= 800000 and not (F.isBin and F.isBin(body)) then
					jobs[#jobs + 1] = { ent = ent, src = body }
				end
			end
		end
		if #jobs == 0 then return false end
		return F.job("deobAll", function()
			local out = {}
			for i = 1, #jobs do
				local j = jobs[i]
				local ok, text, rep = pcall(DE.run, j.src)
				if ok then
					local base = (j.ent.f or "dump"):gsub("%.lua$", "")
					pcall(FS.write, PATH.d(base .. ".deob.lua"), text)
					pcall(FS.write, PATH.d(base .. ".deob.json"), F.enc(rep) or "{}")
					out[#out + 1] = base
				end
				if F.Y then F.Y() end
			end
			return out
		end, function(res)
			if F.notify then F.notify("Deobfuscate done: " .. tostring(res and #res or 0)) end
		end)
	end

	F.api.deob = function(cmd)
		cmd = tostring(cmd or "status"):lower()
		if cmd == "on" then
			CFG.deob = true
			F.cfgSave()
			return true
		elseif cmd == "off" then
			CFG.deob = false
			F.cfgSave()
			return false
		elseif cmd == "auto" then
			CFG.autoDeobf = not CFG.autoDeobf
			F.cfgSave()
			return CFG.autoDeobf
		elseif cmd == "status" then
			return { deob = CFG.deob, auto = CFG.autoDeobf, pending = #DE.pending, stats = DE.stats }
		end
		return false
	end

	F.extra.deobfuscate = function()
		return { stats = DE.stats, pending = #DE.pending, auto = CFG.autoDeobf }
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okDE then
	warn("[AluzSpy] deobfuscate failed: " .. tostring(errDE))
end
