do local _ = "aluzspy@1.2.2-max" if F and F.trace then F.trace("load runtime") end end
local okRT, errRT = xpcall(function()
	local LOADER = "https://raw.githubusercontent.com/nicknew605-cpu/AluzSpy/refs/heads/main/loader.lua"

	conns[#conns + 1] = SV.RunService.Heartbeat:Connect(function(dt)
		if not alive then return end
		if dt > 3.5 then X.stall = true end
		if dt > 0 then X.fps = X.fps * 0.95 + (1 / dt) * 0.05 end
		busy = true
		local budget = F.budget()
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
		report = F.report,
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
		modules = F.modules,
		protect = function(n) CFG.protected[tostring(n)] = true F.cfgSave() return CFG.protected end,
		unprotect = function(n) CFG.protected[tostring(n)] = nil F.cfgSave() return CFG.protected end,
		threshold = function(n, m) CFG.thr[tostring(n)] = tonumber(m) F.cfgSave() return CFG.thr end,
		shutdown = shutdown,
		stats = F.stats,
		errors = function() return errMap end,
		debug = function()
			local js = F.enc({
				stats = F.stats(), errors = errMap, banned = BAN.list, recovered = X.recovered,
				capabilities = CAP, health = F.extra.health and F.extra.health() or nil,
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
			warn("[AluzSpy] save() report() missing() chain() split(bool) find(text,n) top(n) stats() debug() errors() modules()")
			warn("[AluzSpy] decode(file) analyze(file,net) decodeAll() deobf(file) deobfAll() deobfReport() set(key,bool)")
			warn("[AluzSpy] reverse(opts) reverseFind(text) gcmap(deep) whoCalls(name) callgraph() tree() scriptDiff()")
			warn("[AluzSpy] vip() vip(\"scan\"|\"report\"|\"redact\"|\"safe\"|\"profile\", name) protect(name) threshold(name,mult)")
			warn("[AluzSpy] health() actors() dump(bool) dumpScripts(filter) block(name) modify(name,fn) reset() reload() shutdown()")
		end,
	}
	for k, v in pairs(F.api or {}) do
		if api[k] == nil then api[k] = v end
	end
	genv.AluzSpy = api

	if F.notify then F.notify("Loaded " .. VERSION) end
	if F.recoveredFile and F.notify then F.notify("Recovered dumps: " .. tostring(F.recoveredFile):match("[^/]+$")) end
	warn("[AluzSpy] loaded " .. VERSION .. " (AluzSpy.help() for commands)")

	pcall(F.migrate)
	F.trace("runtime boot")
	task.spawn(F.boot)

	if CFG.autoScripts then
		task.delay(12, function()
			if alive and F.scanScripts then F.scanScripts() end
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
