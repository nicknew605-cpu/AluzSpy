local okH, errH = xpcall(function()
	if not F.job then return end

	local H = { t = 0, probes = {}, integrity = {}, notes = {}, fallback = false, bad = 0 }

	local function probeEvent(form)
		local p = X.probe
		if not p then
			local ok, inst = pcall(Instance.new, "RemoteEvent")
			if not ok then return nil end
			p = inst
			X.probe = p
		end
		X.probeSelf = p
		X.probeHit = false
		if form == "nc" then
			pcall(function() p:FireServer("aluz_hc") end)
		else
			pcall(function() p.FireServer(p, "aluz_hc") end)
		end
		local hit = X.probeHit
		X.probeSelf = nil
		return hit
	end

	local function probeLS()
		local before = qt
		local ok = pcall(loadstring, "return 41")
		return ok and qt > before
	end

	local function inspect(f)
		if type(f) ~= "function" then return nil end
		local r = {}
		if iscclosure then
			local ok, v = pcall(iscclosure, f)
			if ok then r.c = v end
		end
		if isexecutorclosure then
			local ok, v = pcall(isexecutorclosure, f)
			if ok then r.exec = v end
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
		add("setclipboard", genv.setclipboard)
		pcall(function() add("HttpGet", game.HttpGet) end)
		pcall(function()
			local mt = getrawmetatable(game)
			add("__namecall", rawget(mt, "__namecall"))
		end)
		return out
	end

	local function run()
		if not alive then return end
		H.t = os.time()
		H.notes = {}
		H.probes = {}
		if INST.nc and S.nc and MOD.nc then H.probes.namecall = probeEvent("nc") end
		if INST.fn and S.nc and MOD.fn then H.probes.direct = probeEvent("fn") end
		if INST.ls and MOD.ls then H.probes.loadstring = probeLS() end
		H.integrity = integrity()
		local bad = 0
		for k, v in pairs(H.probes) do
			if v == false then
				bad = bad + 1
				H.notes[#H.notes + 1] = k .. " hook not receiving calls"
			end
		end
		for k, v in pairs(H.integrity) do
			if v.exposed then H.notes[#H.notes + 1] = k .. " looks hooked to a game that inspects it" end
		end
		H.bad = bad
		if F.notify then F.notify(bad == 0 and "Health OK" or ("Health: " .. bad .. " hook(s) failing")) end
		return H
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
				rawset(mt, "__namecall", nc(F.ncHook))
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
		task.delay(5, run)
		return true
	end
	F.stage("hc", 90, IN.hc)

	F.api.health = function()
		local r = run()
		warn("[AluzSpy] health: " .. tostring(F.enc(H)))
		return r
	end
	F.extra.health = function() return H end
	F.extraChips[#F.extraChips + 1] = { "HLTH", function() return false end, function() run() return false end }
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okH then
	warn("[AluzSpy] health failed: " .. tostring(errH))
end
