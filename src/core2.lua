do local _ = "aluzspy@1.2.2-beta" if F and F.trace then F.trace("load core2") end end
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

	if not F.debugWrapped then
		F.debugWrapped = true
		local baseStage = F.stage
		F.stage = function(name, prio, fn)
			baseStage(name, prio, function(...)
				local args = pack(...)
				local t0 = clock()
				local r = pack(xpcall(function()
					return fn(unpack(args, 1, args.n))
				end, function(e)
					return tostring(e) .. "\n" .. debug.traceback()
				end))
				local dur = clock() - t0
				F.debug.stages[name] = {
					ok = r[1], dur = r2(dur), t = os.time(),
					err = r[1] and nil or tostring(r[2]):sub(1, 400),
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
		}
		F.debug.watch[#F.debug.watch + 1] = w
		if #F.debug.watch > 40 then table.remove(F.debug.watch, 1) end
		if X.stall or X.fps < 8 or X.memNow > K.MEM_ABS * 0.9 then
			pcall(FS.write, PATH.f("debug_watch.json"), F.enc({
				watch = F.debug.watch, stages = F.debug.stages, errors = errMap,
			}) or "{}")
		end
	end)

	F.api.debugAll = function()
		local out = {
			stages = F.debug.stages, watch = F.debug.watch, errors = errMap,
			stats = F.stats and F.stats() or nil, extra = F.ext(),
			missing = F.missing and F.missing() or nil,
		}
		pcall(FS.write, PATH.f("debug_all.json"), F.enc(out) or "{}")
		warn("[AluzSpy] debugAll saved")
		return out
	end

	F.api.stageReport = function()
		for k, v in pairs(F.debug.stages) do
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

	F.extra.debug = function()
		local n = 0
		for _ in pairs(F.debug.stages) do n = n + 1 end
		return { stages = n, watch = #F.debug.watch }
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okC2 then
	warn("[AluzSpy] core2 failed: " .. tostring(errC2))
end
