do local _ = "aluzspy@1.2.2-beta" if F and F.trace then F.trace("load health") end end
local okH, errH = xpcall(function()
	if not F.job then return end

	local H = { status = {}, integrity = {}, reinstalls = 0, fallback = false, runs = 0, t = 0, per = {}, nextTry = {}, conflict = nil }
	F.H = H
	local lastHc = 0

	local function setStatus(name, ok)
		if ok == nil then return end
		local s = H.status[name]
		if not s then
			s = { good = 0, bad = 0, miss = 0, state = "n/a" }
			H.status[name] = s
		end
		if ok then
			s.good = s.good + 1
			s.miss = 0
			s.state = "ok"
		else
			s.bad = s.bad + 1
			s.miss = s.miss + 1
			s.state = s.miss >= 2 and "failing" or "degraded"
		end
	end

	local function probeEvent(form)
		if not getrawmetatable then return true end
		local ok, mt = pcall(getrawmetatable, game)
		if not ok or not mt then return true end
		local ncHook = rawget(mt, "__namecall")
		if not ncHook then return false end
		local isC = false
		if iscclosure then pcall(function() isC = iscclosure(ncHook) end) end
		return isC == false
	end

	local function probeLS()
		local before = qt
		local ok = pcall(loadstring, "return 41 --aluz_hc")
		return ok and qt > before
	end

	local h7 = F.h[7]
	F.h[7] = function(e, now)
		if type(e.src) == "string" and e.src:find("aluz_hc", 1, true) then return end
		return h7(e, now)
	end

	local function inspect(f)
		if type(f) ~= "function" then return nil end
		local r = {}
		if iscclosure then
			local ok, v = pcall(iscclosure, f)
			if ok then r.c = v end
		end
		if debug and debug.info then
			local ok, v = pcall(debug.info, f, "s")
			if ok then r.src = v end
		end
		r.exposed = (r.src ~= nil and r.src ~= "[C]") or r.c == false
		return r
	end

	local function integrity()
		local out = {}
		local function add(name, f)
			local r = inspect(f)
			if r then out[name] = r end
		end
		pcall(function()
			add("FireServer", Instance.new("RemoteEvent").FireServer)
			add("InvokeServer", Instance.new("RemoteFunction").InvokeServer)
			add("Kick", LP.Kick)
		end)
		add("loadstring", genv.loadstring)
		add("request", genv.request)
		pcall(function() add("HttpGet", game.HttpGet) end)
		return out
	end

	local function canReinstall(name)
		if (H.per[name] or 0) >= 3 then return false end
		return clock() >= (H.nextTry[name] or 0)
	end

	local function noteReinstall(name)
		H.per[name] = (H.per[name] or 0) + 1
		H.reinstalls = H.reinstalls + 1
		H.nextTry[name] = clock() + 20 * H.per[name]
	end

	local function conflictCheck()
		if not (getrawmetatable and F.ncWrap and INST.nc) then return nil end
		local ok, mt = pcall(getrawmetatable, game)
		if not ok or not mt then return nil end
		local cur = rawget(mt, "__namecall")
		if cur == nil then return "missing" end
		if cur ~= F.ncWrap then return "replaced" end
		return nil
	end

	local function check()
		if not alive or busy then return end
		H.runs = H.runs + 1
		H.t = os.time()
		if INST.nc and S.nc and MOD.nc then setStatus("namecall", probeEvent("nc")) end
		if INST.fn and S.nc and MOD.fn then setStatus("direct", probeEvent("fn")) end
		if INST.ls and MOD.ls then setStatus("loadstring", probeLS()) end
		if INST.s2c and MOD.s2c and N.att > 0 then setStatus("s2c", true) end
		H.integrity = integrity()
		local nc2 = H.status.namecall
		H.conflict = conflictCheck()
		if nc2 and nc2.state == "failing" and canReinstall("nc") then
			noteReinstall("nc")
			INST.nc = false
			pcall(IN.nc)
			nc2.miss = 0
		end
		local ls = H.status.loadstring
		if ls and ls.state == "failing" and canReinstall("ls") then
			noteReinstall("ls")
			seenFn[genv.loadstring or loadstring] = nil
			INST.ls = false
			pcall(IN.ls)
			ls.miss = 0
		end
		if X.tripped then
			local now = clock()
			for mod, t in pairs(X.tripped) do
				if now - t > 60 then
					faults[mod] = 0
					if INST[mod] then MOD[mod] = true end
					X.tripped[mod] = nil
				end
			end
		end
	end

	local baseNc = IN.nc
	if baseNc then
		IN.nc = function()
			local ok, res = pcall(baseNc)
			if ok and res then return true end
			if INST.nc then return false end
			if not (getrawmetatable and getnm) then return false end
			local okf = pcall(function()
				local mt = getrawmetatable(game)
				local ro = isreadonly and isreadonly(mt)
				if setreadonly then
					setreadonly(mt, false)
				elseif make_writeable then
					make_writeable(mt)
				end
				local old = rawget(mt, "__namecall")
				if type(old) ~= "function" then error("no __namecall") end
				local wrap = nc(F.ncHook)
				F.ncWrap = wrap
				rawset(mt, "__namecall", wrap)
				oldNc = old
				if setreadonly and ro then setreadonly(mt, true) end
			end)
			if okf then
				INST.nc = true
				MOD.nc = true
				H.fallback = true
				return true
			end
			return false
		end
	end

	IN.hc = function()
		MOD.hc = true
		INST.hc = true
		task.delay(5, check)
		return true
	end
	F.stage("hc", 90, IN.hc)

	F.onTick(function(now)
		if now - lastHc >= 20 then
			lastHc = now
			task.defer(check)
		end
	end)

	function F.weakHooks()
		local out = {}
		for k, s in pairs(H.status) do
			if s.state == "degraded" or s.state == "failing" then out[#out + 1] = k .. " " .. s.state end
		end
		for k, v in pairs(H.integrity) do
			if v.exposed then out[#out + 1] = k .. " looks hooked if the game inspects it" end
		end
		table.sort(out)
		return out
	end

	function F.hookLine()
		local t = {}
		for k, s in pairs(H.status) do t[#t + 1] = k:sub(1, 3) .. ":" .. s.state:sub(1, 1) end
		table.sort(t)
		return #t > 0 and table.concat(t, " ") or "checking"
	end

	F.api = F.api or {}
	F.api.health = function()
		check()
		warn("[AluzSpy] health: " .. tostring(F.enc({ status = H.status, reinstalls = H.reinstalls, fallback = H.fallback })))
		return H
	end
	F.extra.health = function()
		return { status = H.status, integrity = H.integrity, reinstalls = H.reinstalls, per = H.per, fallback = H.fallback, runs = H.runs, conflict = H.conflict }
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okH then
	warn("[AluzSpy] health failed: " .. tostring(errH))
end
