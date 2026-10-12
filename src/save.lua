do
	local function collectRecs()
		local out = {}
		local first = N.seq - K.LOGCAP + 1
		if first < 1 then first = 1 end
		for s = first, N.seq do
			local r = logs[(s - 1) % K.LOGCAP + 1]
			if r and r.i == s then out[#out + 1] = r end
		end
		return out
	end

	local function remList()
		local out = {}
		local function add(reg)
			for _, st in pairs(reg) do
				out[#out + 1] = {
					d = st.dir, r = st.full, m = st.m, calls = st.n + st.supp, logged = st.logged,
					merged = st.merged, sampled = st.smp, suppressed = st.supp, mutes = st.mutes,
					peak = r2(st.peak), ret = st.ret or nil, muted = st.mu and true or nil,
				}
			end
		end
		add(stC)
		add(stS)
		table.sort(out, function(a, b) return a.calls > b.calls end)
		for i = #out, 101, -1 do out[i] = nil end
		return out
	end

	local function recOut(r)
		return {
			i = r.i, t = r.t, tl = r.tl, d = r.d, n = r.n, r = r.r, m = r.m, c = r.c,
			x = r.ex and true or nil, a = r.a, ret = r.ret, f = r.f, did = r.did, par = r.par,
			code = r.code, cf = r.sref and D.sdf[r.sref] or nil,
		}
	end

	function F.stats()
		return {
			total = N.total, logged = N.logged, merged = N.merged, sampled = N.sampled,
			suppressed = N.supp, bucketDropped = N.bucket, queueDropped = N.dropQ,
			errors = N.err, remotes = N.remotes, muted = #muteList, dumps = D.n,
			fps = floor(X.fps), mem = floor(X.memNow), load = X.load,
			hooks = {
				nc = INST.nc, fn = INST.fn, s2c = INST.s2c, cb = INST.cb, ni = INST.ni, sys = INST.sys,
				net = INST.net, http = INST.http, ls = INST.ls, rw = INST.rw, ws = INST.ws, req = INST.req,
			},
		}
	end

	local function buildJSON(reason)
		local recs = collectRecs()
		local exec = "unknown"
		pcall(function()
			if identifyexecutor then
				local n, v = identifyexecutor()
				exec = tostring(n) .. (v and (" " .. tostring(v)) or "")
			end
		end)
		local meta = {
			tool = "Aluz Spy", version = VERSION, schema = 4, executor = exec,
			place = game.PlaceId, job = game.JobId, exported = os.date("%Y-%m-%d %H:%M:%S"),
			reason = reason, session_file = PATH.session, uptime = r2(clock() - T0),
			safe_boot = BAN.safe, banned = BAN.list, disabled = BAN.disabled, recovered = X.recovered,
			capabilities = CAP, config = CFG,
			hooks = {
				namecall = INST.nc and MOD.nc, namecall_on = S.nc and MOD.nc, direct = INST.fn and MOD.fn,
				s2c = INST.s2c and MOD.s2c, callbacks = INST.cb and MOD.cb, newindex = INST.ni and MOD.ni,
				sys = INST.sys and MOD.sys, net = INST.net and MOD.net, http = INST.http and MOD.http,
				loadstring = INST.ls and MOD.ls, rw = INST.rw and MOD.rw, ws = INST.ws and MOD.ws,
				require = INST.req and MOD.req, watchdog_reinstalls = X.wdN,
			},
			stats = {
				total = N.total, logged = N.logged, merged = N.merged, sampled_out = N.sampled,
				suppressed = N.supp, bucket_dropped = N.bucket, queue_dropped = N.dropQ, errors = N.err,
				remotes = N.remotes, muted_now = #muteList, attached = N.att, callbacks_wrapped = RF.n,
				entries = #recs, fps = floor(X.fps), mem = floor(X.memNow), load = X.load,
			},
			dump = {
				enabled = S.dump, files = D.n, pending = D.t - D.h + 1, skipped = D.skipped, failed = D.fail,
				folder = PATH.ok and PATH.dumpDir or "root", scripts = D.sdn, list = D.list,
			},
			spam = F.spamList(),
			last_errors = errMap,
			ext = F.ext and F.ext() or nil,
		}
		local head = '{"schema":4,"meta":' .. (F.enc(meta) or "{}") .. ',"remotes":' .. (F.enc(remList()) or "[]") .. ',"logs":['
		local lines = {}
		for i = 1, #recs do
			local js = F.enc(recOut(recs[i]))
			if js then lines[#lines + 1] = js end
		end
		return head .. "\n" .. table.concat(lines, ",\n") .. "\n]}"
	end

	saveNow = function(reason)
		if not HAS_W then return false, "no writefile" end
		local manual = reason == "manual"
		if not manual then
			local now = clock()
			if now - X.lastAuto < 2.5 then return true, "skip" end
			X.lastAuto = now
		end
		local prev = busy
		busy = true
		local ok, res = pcall(function()
			F.process(0.05)
			D.flush()
			if not manual and not X.dirty then return "clean" end
			local body = buildJSON(reason)
			writefile(PATH.session, body)
			if manual and type(setclipboard) == "function" and #body < 1500000 then
				pcall(setclipboard, body)
			end
			X.dirty = false
			X.reason = reason
			return PATH.session
		end)
		busy = prev
		if ok then return true, res end
		noteErr(res)
		return false, tostring(res)
	end

	F.onTick(function(now)
		local okm, mb = pcall(function() return SV.Stats:GetTotalMemoryUsageMb() end)
		if okm and type(mb) == "number" then
			X.memNow = mb
			local mem = X.mem
			mem[#mem + 1] = mb
			if #mem > 10 then table.remove(mem, 1) end
			if (mb > K.MEM_ABS or mb - mem[1] > K.MEM_GROW) and now - X.lastMem > 30 then
				X.lastMem = now
				task.defer(saveNow, "memory")
			end
		end
		if X.stall then
			X.stall = false
			task.defer(saveNow, "stall")
		end
		if X.fps < 8 then X.lowN = X.lowN + 1 else X.lowN = 0 end
		if X.lowN >= 3 and now - X.lastFps > 30 then
			X.lastFps = now
			task.defer(saveNow, "fps")
		end
	end)

	if X.recovered then
		FS.write(PATH.crash, F.enc({
			version = VERSION, time = os.date("%Y-%m-%d %H:%M:%S"), place = game.PlaceId,
			stage = X.recovered.stage, age = X.recovered.age, banned = BAN.list,
			disabled = BAN.disabled, capabilities = CAP,
		}) or "")
	end
end
