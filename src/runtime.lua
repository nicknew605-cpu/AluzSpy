local okRT, errRT = xpcall(function()
	local LOADER = "https://raw.githubusercontent.com/nicknew605-cpu/AluzSpy/refs/heads/main/Stable"

	conns[#conns + 1] = SV.RunService.Heartbeat:Connect(function(dt)
		if not alive then return end
		if dt > 3.5 then X.stall = true end
		if dt > 0 then X.fps = X.fps * 0.95 + (1 / dt) * 0.05 end
		busy = true
		local budget = (qt - qh) > QCAP / 2 and 0.006 or 0.0025
		local ok, err = pcall(F.process, budget)
		if not ok then noteErr(err) end
		if D.jobs[1] or D.h <= D.t then
			local okd, errd = pcall(D.pump)
			if not okd then noteErr(errd) end
		end
		local now = clock()
		if now - X.lastTick >= 1 then
			local ok2, err2 = pcall(F.tick, now)
			if not ok2 then noteErr(err2) end
		end
		busy = false
	end)

	conns[#conns + 1] = SV.Players.PlayerRemoving:Connect(function(p)
		if p == LP then pcall(saveNow, "close") end
	end)

	pcall(function()
		game:BindToClose(function()
			pcall(saveNow, "close")
		end)
	end)

	local function shutdown(quiet)
		if not alive then return end
		if not quiet then pcall(saveNow, "close") end
		alive = false
		S.nc = false
		for i = 1, #conns do
			pcall(conns[i].Disconnect, conns[i])
		end
		for _, c in pairs(attached) do
			if c then pcall(c.Disconnect, c) end
		end
		FS.del(PATH.flag)
		if F.gui then pcall(function() F.gui:Destroy() end) end
		if genv.AluzSpy and genv.AluzSpy.shutdown == shutdown then
			genv.AluzSpy = nil
		end
	end

	local function rules()
		X.rules = next(X.block) ~= nil or next(X.mod) ~= nil
	end

	local api = {
		version = VERSION,
		nc = F.setNC,
		mod = F.setMod,
		save = function() return saveNow("manual") end,
		dump = function(b)
			S.dump = b ~= false
			CFG.dump = S.dump
			F.cfgSave()
		end,
		dumpScripts = F.scanScripts,
		block = function(n) X.block[n] = true rules() end,
		unblock = function(n) X.block[n] = nil rules() end,
		modify = function(n, f) X.mod[n] = f rules() end,
		unmodify = function(n) X.mod[n] = nil rules() end,
		reset = F.reset,
		shutdown = shutdown,
		stats = F.stats,
		errors = function() return errMap end,
		debug = function()
			local js = F.enc({
				stats = F.stats(), errors = errMap, banned = BAN.list, disabled = BAN.disabled,
				recovered = X.recovered, capabilities = CAP,
			})
			warn("[AluzSpy] " .. tostring(js))
			return js
		end,
		find = function(text, limit)
			text = tostring(text or ""):lower()
			limit = limit or 20
			local out = {}
			for s = N.seq, math.max(1, N.seq - K.LOGCAP + 1), -1 do
				local r = logs[(s - 1) % K.LOGCAP + 1]
				if r and r.i == s then
					local hay = (tostring(r.r) .. " " .. tostring(r.m) .. " " .. table.concat(r.a or {}, " ")):lower()
					if hay:find(text, 1, true) then
						out[#out + 1] = { i = r.i, t = r.t, d = r.d, r = r.r, m = r.m, n = r.n, a = r.a, code = r.code }
						if #out >= limit then break end
					end
				end
			end
			for i = 1, #out do
				local o = out[i]
				warn(string.format("[AluzSpy] #%d %s %s %s (%s)", o.i, o.d, o.r, o.m, table.concat(o.a or {}, ", ")))
			end
			return out
		end,
		top = function(n)
			n = n or 10
			local out = {}
			for _, reg in ipairs({ stC, stS }) do
				for _, st in pairs(reg) do
					out[#out + 1] = { d = st.dir, r = st.full, calls = st.n + st.supp, peak = r2(st.peak), muted = st.mu ~= nil }
				end
			end
			table.sort(out, function(a, b) return a.calls > b.calls end)
			for i = #out, n + 1, -1 do out[i] = nil end
			for i = 1, #out do
				local o = out[i]
				warn(string.format("[AluzSpy] %s %s calls=%d peak=%s/s%s", o.d, o.r, o.calls, tostring(o.peak), o.muted and " muted" or ""))
			end
			return out
		end,
		reload = function()
			shutdown(true)
			local ok, src = pcall(function() return game:HttpGet(LOADER .. "?v=" .. os.time(), true) end)
			if not ok or type(src) ~= "string" then return false end
			local f = loadstring(src)
			if f then task.defer(f) end
			return f ~= nil
		end,
		help = function()
			warn("[AluzSpy] nc(bool) mod(name,bool) save() dump(bool) dumpScripts(filter) find(text,n) top(n) stats() debug() errors()")
			warn("[AluzSpy] decode(file) analyze(file,net) decodeAll() set(key,bool) block(name) modify(name,fn) reset() reload() shutdown()")
		end,
	}
	for k, v in pairs(F.api or {}) do api[k] = v end
	genv.AluzSpy = api

	if F.notify then F.notify("Loaded " .. VERSION) end
	warn("[AluzSpy] loaded " .. VERSION .. " (AluzSpy.help() for commands)")

	task.spawn(F.boot)

	if CFG.autoScripts then
		task.delay(12, function()
			if alive then F.scanScripts() end
		end)
	end

	if CFG.update then
		task.spawn(function()
			task.wait(8)
			local ok, txt = pcall(function()
				return game:HttpGet("https://raw.githubusercontent.com/nicknew605-cpu/AluzSpy/refs/heads/main/version.txt")
			end)
			if ok and type(txt) == "string" then
				local v = txt:match("^%s*(%S+)")
				if v and v ~= VERSION and F.notify then F.notify("Update available: " .. v) end
			end
		end)
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okRT then
	warn("[AluzSpy] fatal runtime: " .. tostring(errRT))
	pcall(function()
		SV.StarterGui:SetCore("SendNotification", {
			Title = "Aluz Spy", Text = "Fatal: " .. tostring(errRT):sub(1, 120), Duration = 8,
		})
	end)
end
