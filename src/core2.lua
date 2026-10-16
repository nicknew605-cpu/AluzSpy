do local _ = "aluzspy@1.2.1-max" end
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

	local J = {
		cur = nil, queue = {}, ss = 0, inJob = false, name = nil, paused = false,
		done = 0, failed = 0, timeouts = 0, cap = 24, spent = 0,
	}
	F.J = J

	function F.Y(slice)
		if J.inJob and clock() - J.ss > (slice or 0.003) then
			coroutine.yield()
		end
	end

	function F.job(name, fn, onDone, opts)
		if #J.queue >= J.cap then return false end
		opts = opts or {}
		local j = {
			name = name, co = coroutine.create(fn), done = onDone,
			prio = opts.prio or 2, timeout = opts.timeout or 30, t0 = nil,
		}
		local q = J.queue
		local i = #q
		while i > 0 and q[i].prio > j.prio do i = i - 1 end
		table.insert(q, i + 1, j)
		return true, j
	end

	function F.jobPause(on)
		J.paused = on ~= false
		return J.paused
	end

	function F.jobCancel(name)
		local c = 0
		for i = #J.queue, 1, -1 do
			if J.queue[i].name == name then
				table.remove(J.queue, i)
				c = c + 1
			end
		end
		if J.cur and J.cur.name == name then
			J.cur = nil
			c = c + 1
		end
		return c
	end

	conns[#conns + 1] = SV.RunService.Heartbeat:Connect(function()
		if not alive or J.paused then return end
		if not J.cur then J.cur = table.remove(J.queue, 1) end
		local j = J.cur
		if not j then return end
		local now = clock()
		if not j.t0 then j.t0 = now end
		if now - j.t0 > j.timeout then
			J.cur = nil
			J.timeouts = J.timeouts + 1
			noteErr("job_" .. tostring(j.name) .. ":timeout")
			return
		end
		local prev = busy
		busy = true
		J.inJob = true
		J.ss = now
		J.name = j.name
		local ok, res = coroutine.resume(j.co)
		J.inJob = false
		busy = prev
		J.spent = J.spent + (clock() - now)
		if not ok then
			J.cur = nil
			J.failed = J.failed + 1
			noteErr("job_" .. tostring(j.name) .. ":" .. tostring(res))
		elseif coroutine.status(j.co) == "dead" then
			J.cur = nil
			J.done = J.done + 1
			if j.done then
				local ok2, err2 = pcall(j.done, res)
				if not ok2 then noteErr(err2) end
			end
		end
	end)

	F.extra.jobs = function()
		return {
			running = J.name, queued = #J.queue, paused = J.paused, done = J.done,
			failed = J.failed, timeouts = J.timeouts, ms = math.floor(J.spent * 1000),
		}
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okC2 then
	warn("[AluzSpy] core2 failed: " .. tostring(errC2))
end
