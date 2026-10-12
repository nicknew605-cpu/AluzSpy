local okC2, errC2 = xpcall(function()
	F.extra = {}
	F.extraChips = {}
	F.api = F.api or {}

	local defs = { hash = true, lz4 = false }
	for k, v in pairs(defs) do
		if CFG[k] == nil then CFG[k] = v end
	end
	for _, n in ipairs({ "ac", "hc", "sd" }) do
		MOD[n] = false
		INST[n] = false
		F.defMods[n] = true
		if CFG.mods[n] == nil then CFG.mods[n] = true end
	end
	F.cfgLoad()
	if BAN.safe then
		for _, n in ipairs({ "ac", "sd" }) do
			if not BAN.set[n] then
				BAN.set[n] = true
				BAN.list[#BAN.list + 1] = n
			end
		end
		table.sort(BAN.list)
	end

	function F.ext()
		local out = {}
		for name, fn in pairs(F.extra) do
			local ok, res = pcall(fn)
			if ok and res ~= nil then out[name] = res end
		end
		return out
	end

	function F.fullName(inst)
		local ok, n = pcall(inst.GetFullName, inst)
		if ok and type(n) == "string" then return n end
		return "?"
	end

	local J = { cur = nil, queue = {}, ss = 0, inJob = false, name = nil }
	F.J = J

	function F.Y(slice)
		if J.inJob and clock() - J.ss > (slice or 0.003) then
			coroutine.yield()
		end
	end

	function F.job(name, fn, onDone)
		if #J.queue >= 16 then return false end
		J.queue[#J.queue + 1] = { name = name, co = coroutine.create(fn), done = onDone }
		return true
	end

	conns[#conns + 1] = SV.RunService.Heartbeat:Connect(function()
		if not alive then return end
		if not J.cur then J.cur = table.remove(J.queue, 1) end
		local j = J.cur
		if not j then return end
		local prev = busy
		busy = true
		J.inJob = true
		J.ss = clock()
		J.name = j.name
		local ok, res = coroutine.resume(j.co)
		J.inJob = false
		busy = prev
		if not ok then
			J.cur = nil
			noteErr("job_" .. tostring(j.name) .. ":" .. tostring(res))
		elseif coroutine.status(j.co) == "dead" then
			J.cur = nil
			if j.done then
				local ok2, err2 = pcall(j.done, res)
				if not ok2 then noteErr(err2) end
			end
		end
	end)

	F.extra.jobs = function()
		return { running = J.name, queued = #J.queue }
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okC2 then
	warn("[AluzSpy] core2 failed: " .. tostring(errC2))
end
