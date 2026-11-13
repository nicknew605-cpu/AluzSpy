do local _ = "aluzspy@1.2.3-stable" if F and F.trace then F.trace("load core2") end end
local okC2, errC2 = xpcall(function()
	F.extra = {}
	F.extraChips = {}
	F.api = F.api or {}
	F.debug = F.debug or { stages = {}, watch = {}, started = os.time() }

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

	function F.applyMax()
		CFG.profile = "max"
		for k, v in pairs(F.defMods) do
			if v ~= false and CFG.explicit[k] ~= true then CFG.mods[k] = true end
		end
		CFG.dump = true
		CFG.code = true
		CFG.tree = true
		CFG.callerDump = true
		CFG.autoScripts = true
		CFG.decode = true
		CFG.autoDeobf = true
		CFG.autoReverse = true
		CFG.redact = true
		CFG.net = true
		CFG.update = true
		CFG.deob = true
		CFG.bytecode = true
		CFG.vmdump = true
		CFG.strings = true
		CFG.dumpSpill = true
		CFG.selfTune = true
		CFG.autoMax = true
		F.cfgSave()
		return CFG
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

	function F.job(name, fn, onDone, timeout, prio)
		if type(timeout) == "table" then
			local o = timeout
			timeout = o.timeout
			prio = o.prio or prio
		end
		if #J.queue >= K.JOB_QUEUE then return false end
		local job = {
			name = tostring(name or "job"), co = coroutine.create(fn), done = onDone,
			timeout = tonumber(timeout), prio = tonumber(prio) or 50,
		}
		local i = #J.queue
		while i > 0 and (J.queue[i].prio or 50) < job.prio do i = i - 1 end
		table.insert(J.queue, i + 1, job)
		return true
	end

	if not F.debugWrapped then
		F.debugWrapped = true
		local baseStage = F.stage
		F.stage = function(name, prio, fn)
			baseStage(name, prio, function(...)
				local target = fn
				for i = 1, #F.stages do
					local e = F.stages[i]
					if e[1] == name and e[4] then target = e[4] end
				end
				local args = pack(...)
				local t0 = clock()
				local r = pack(xpcall(function()
					return target(unpack(args, 1, args.n))
				end, function(e)
					return tostring(e) .. "\n" .. debug.traceback()
				end))
				local dur = clock() - t0
				local errTxt = nil
				if not r[1] then errTxt = tostring(r[2]):sub(1, 400) end
				local resTxt = "ok"
				if not r[1] then resTxt = "error"
				elseif r[2] ~= nil then resTxt = tostring(r[2]) end
				F.debug.stages[name] = {
					ok = r[1], dur = r2(dur), t = os.time(),
					err = errTxt, result = resTxt,
				}
				if not r[1] then error(r[2]) end
				return unpack(r, 2, r.n)
			end)
		end
	end

	local lastWatch = 0
	F.onTick(function(now)
		if now - lastWatch < 2 then return end
		lastWatch = now
		local w = {
			t = os.time(), fps = r2(X.fps), mem = r2(X.memNow), q = qt - qh,
			dumpJobs = #D.jobs, dumpPending = D.pending, busy = busy, load = X.load,
			disk = D.bytes or 0, evicted = N.evict, dropQ = N.dropQ, tune = X.tune and X.tune.level or 0,
		}
		F.debug.watch[#F.debug.watch + 1] = w
		if #F.debug.watch > 60 then table.remove(F.debug.watch, 1) end
		if X.stall or X.fps < 8 or X.memNow > K.MEM_ABS * 0.9 then
			pcall(FS.write, PATH.h("debug_watch.json"), F.enc({
				watch = F.debug.watch, stages = F.debug.stages, errors = errMap,
			}) or "{}")
		end
	end)

	F.api.debugAll = function()
		local out = {
			stages = F.debug.stages, watch = F.debug.watch, errors = errMap,
			stats = F.stats and F.stats() or nil, extra = F.ext(),
			missing = F.missing and F.missing() or nil,
			hooks = F.modules and F.modules().hooks or nil,
		}
		pcall(FS.write, PATH.h("debug_all.json"), F.enc(out) or "{}")
		warn("[AluzSpy] debugAll saved: " .. tostring(PATH.h("debug_all.json")))
		return out
	end

	F.api.stageReport = function()
		local names = {}
		for k in pairs(F.debug.stages) do names[#names + 1] = k end
		table.sort(names)
		for _, k in ipairs(names) do
			local v = F.debug.stages[k]
			warn(string.format("[AluzSpy] stage %s ok=%s dur=%s err=%s",
				k, tostring(v.ok), tostring(v.dur), tostring(v.err)))
		end
		return F.debug.stages
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
		if not j.started then
			j.started = clock()
			if j.timeout then j.deadline = j.started + j.timeout end
		end
		if j.deadline and clock() > j.deadline then
			J.cur = nil
			J.inJob = false
			busy = prev
			noteErr("job_timeout_" .. tostring(j.name))
			if type(coroutine.close) == "function" then pcall(coroutine.close, j.co) end
			if j.done then
				local okc, errc = pcall(j.done, nil, "timeout")
				if not okc then noteErr(errc) end
			end
			return
		end
		local ok, res = coroutine.resume(j.co)
		J.inJob = false
		busy = prev
		if not ok then
			J.cur = nil
			noteErr("job_" .. tostring(j.name) .. ":" .. tostring(res))
			if j.done then
				local okc, errc = pcall(j.done, nil, tostring(res))
				if not okc then noteErr(errc) end
			end
		elseif coroutine.status(j.co) == "dead" then
			J.cur = nil
			if j.done then
				local ok2, err2 = pcall(j.done, res)
				if not ok2 then noteErr(err2) end
			end
		end
	end)

	local tuneWindow, tuneCount, tuneSum = {}, 0, 0

	F.onTick(function(now)
		if not CFG.selfTune then return end
		if now - (X.lastTune or 0) < 3 then return end
		X.lastTune = now
		local n = 0
		for _ in pairs(tuneWindow) do n = n + 1 end
		if n == 0 then return end
		local avg = tuneSum / n
		local lvl = X.tune.level or 0
		if avg > 0.0026 and lvl < 3 then
			lvl = lvl + 1
		elseif avg < 0.0012 and lvl > 0 then
			lvl = lvl - 1
		end
		X.tune.level = lvl
		X.tune.samples = n
		X.tune.avg = r2(avg * 1000)
		tuneWindow = {}
		tuneCount, tuneSum = 0, 0
		F.budgetScale = lvl >= 2 and 0.5 or (lvl == 1 and 0.75 or 1)
	end)

	F.onTick(function(now)
		if now - (X.lastLearn or 0) < 45 then return end
		X.lastLearn = now
		if F.learn then pcall(F.learn) end
		if F.retryHooks then pcall(F.retryHooks) end
		if F.gcStale then pcall(F.gcStale) end
	end)

	F.extra.jobs = function()
		return { running = J.name, queued = #J.queue }
	end

	F.extra.debug = function()
		local n = 0
		for _ in pairs(F.debug.stages) do n = n + 1 end
		return { stages = n, watch = #F.debug.watch, tune = X.tune and X.tune.level or 0 }
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okC2 then
	warn("[AluzSpy] core2 failed: " .. tostring(errC2))
end
