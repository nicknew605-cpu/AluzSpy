local okDP, errDP = xpcall(function()
	if CFG.ver == nil then CFG.ver = "" end
	if CFG.split == nil then CFG.split = false end
	F.cfgLoad()
	F.defMods.req = true
	if CFG.ver ~= "1.2.1-max" then
		CFG.ver = "1.2.1-max"
		for k in pairs(F.defMods) do CFG.mods[k] = true end
		F.cfgSave()
	end
	CFG.nc = true

	local DP = { untilT = 0, hits = 0, why = {}, second = false }
	F.deep = DP
	F.looksOrig = D.looks
	local baseLooks = D.looks
	D.looks = function(body, url)
		if baseLooks(body, url) then return true end
		return clock() < DP.untilT and #body >= 64 and #body <= K.DUMP_FILE_MAX and body:sub(1, 1) ~= "<"
	end

	function F.deepActive()
		return clock() < DP.untilT
	end

	function F.deepOn(why)
		DP.untilT = clock() + 60
		DP.hits = DP.hits + 1
		if #DP.why < 12 then DP.why[#DP.why + 1] = why end
		if not DP.second then
			DP.second = true
			task.delay(20, function()
				if not alive then return end
				if F.gcMap then pcall(F.gcMap, false) end
				if F.scriptDiff then pcall(F.scriptDiff) end
			end)
		end
	end

	X.res = {}

	local function snap()
		local t = {}
		for k, v in pairs(genv) do t[k] = v end
		return t
	end

	local function describe(v)
		local t = typeof(v)
		if t == "table" then
			local keys, n = {}, 0
			pcall(function()
				for k in pairs(v) do
					n = n + 1
					if #keys < 12 and type(k) == "string" then keys[#keys + 1] = k:sub(1, 24) end
				end
			end)
			return "table(" .. n .. ")[" .. table.concat(keys, ",") .. "]"
		elseif t == "function" then
			local ups = 0
			if type(getupvalues) == "function" then
				local ok, u = pcall(getupvalues, v)
				if ok and type(u) == "table" then ups = #u end
			end
			return "function(upv=" .. ups .. ")"
		elseif t == "string" then
			return "string(" .. #v .. ")"
		end
		return t
	end

	function F.deepResult(meta, r, dur, before)
		local rec = { ok = r[1] and true or false, dur = r2(dur) }
		if meta.name then rec.name = tostring(meta.name):sub(1, 40) end
		if r[1] then
			local rets = {}
			for i = 2, math.min(r.n, 4) do rets[#rets + 1] = describe(r[i]) end
			rec.rets = rets
		else
			rec.err = tostring(r[2]):sub(1, 160)
		end
		if before then
			local added = {}
			for k in pairs(genv) do
				if before[k] == nil and #added < 30 then added[#added + 1] = tostring(k):sub(1, 30) end
			end
			if #added > 0 then rec.globals = added end
		end
		X.res[meta.id] = rec
	end

	local function shouldWrap(src)
		return #src >= 1500 or src:find("HttpGet", 1, true) ~= nil or src:find("loadstring", 1, true) ~= nil
	end

	IN.ls = function()
		if INST.ls then
			MOD.ls = true
			return true
		end
		local fn = genv.loadstring or loadstring
		local ok = F.hookWith(fn, function(holder)
			return function(src, name, ...)
				if MOD.ls and alive and not busy and type(src) == "string" then
					local id = X.chunk + 1
					X.chunk = id
					pcall(F.capSrc, "loadstring", src, id, X.cof[coroutine.running()], nil)
					local f, err = holder.old(src, name, ...)
					if f == nil then
						X.res[id] = { ok = false, compile = true, err = tostring(err):sub(1, 160) }
					elseif CFG.tree and type(f) == "function" and shouldWrap(src) then
						local orig = f
						local meta = { id = id, name = name, calls = 0 }
						f = function(...)
							local co = coroutine.running()
							local prev = X.cof[co]
							X.cof[co] = id
							meta.calls = meta.calls + 1
							local before = meta.calls <= 3 and snap() or nil
							local t0 = clock()
							local r = pack(pcall(orig, ...))
							X.cof[co] = prev
							if before then pcall(F.deepResult, meta, r, clock() - t0, before) end
							if not r[1] then error(r[2], 0) end
							return unpack(r, 2, r.n)
						end
					end
					return f, err
				end
				return holder.old(src, name, ...)
			end
		end, true)
		if not ok then return false end
		INST.ls = true
		MOD.ls = true
		local prev = busy
		busy = true
		local okT, f = pcall(loadstring, "return 41+1")
		busy = prev
		if not (okT and type(f) == "function") then
			MOD.ls = false
			return false
		end
		local okR, v = pcall(f)
		if not okR or v ~= 42 then
			MOD.ls = false
			return false
		end
		return true
	end
	for _, s in ipairs(F.stages) do
		if s[1] == "ls" then s[2] = IN.ls end
	end

	local h4 = F.h[4]
	local seenReq = setmetatable({}, weak)
	F.h[4] = function(e, now)
		if e.m == "require" and typeof(e.s) == "Instance" then
			if seenReq[e.s] then return end
			seenReq[e.s] = true
		end
		if h4 then return h4(e, now) end
	end

	F.extra.deep = function()
		return { hits = DP.hits, reasons = DP.why, active = F.deepActive() }
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okDP then
	warn("[AluzSpy] deep failed: " .. tostring(errDP))
end
