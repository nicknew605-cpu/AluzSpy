do local _ = "aluzspy@1.2.2-beta" if F and F.trace then F.trace("load hooks") end end
do
	local HS = SV.HttpService
	local INTEREST = {
		FireServer = 1, InvokeServer = 2,
		Kick = 3, Shutdown = 3, Teleport = 3, TeleportToPlaceInstance = 3, TeleportAsync = 3,
		TeleportToSpawnByName = 3, TeleportPartyAsync = 3, TeleportToPrivateServer = 3,
		HttpGet = 4, HttpGetAsync = 4, HttpPost = 4, HttpPostAsync = 4,
		GetAsync = 4, PostAsync = 4, RequestAsync = 4,
	}

	local function sysReason(m)
		if m == "Kick" then return "kick" end
		if m == "Shutdown" then return "shutdown" end
		return "teleport"
	end

	local function instExpr(inst)
		local names, cur, n = {}, inst, 0
		while typeof(cur) == "Instance" and cur ~= game and n < 16 do
			table.insert(names, 1, cur.Name)
			cur = cur.Parent
			n = n + 1
		end
		if cur ~= game then return "nil" end
		local out = "game"
		for i = 1, #names do
			out = out .. "[" .. string.format("%q", names[i]) .. "]"
		end
		return out
	end

	local function repr(v, d, seen)
		local t = typeof(v)
		if t == "string" then
			return string.format("%q", #v > 300 and v:sub(1, 300) or v)
		elseif t == "number" then
			if v ~= v then return "(0/0)" end
			if v == math.huge then return "math.huge" end
			if v == -math.huge then return "-math.huge" end
			return tostring(v)
		elseif t == "boolean" then
			return tostring(v)
		elseif t == "nil" then
			return "nil"
		elseif t == "Instance" then
			return instExpr(v)
		elseif t == "Vector3" then
			return string.format("Vector3.new(%s, %s, %s)", v.X, v.Y, v.Z)
		elseif t == "Vector2" then
			return string.format("Vector2.new(%s, %s)", v.X, v.Y)
		elseif t == "CFrame" then
			return "CFrame.new(" .. table.concat({ v:GetComponents() }, ", ") .. ")"
		elseif t == "Color3" then
			return string.format("Color3.new(%s, %s, %s)", v.R, v.G, v.B)
		elseif t == "UDim2" then
			return string.format("UDim2.new(%s, %s, %s, %s)", v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
		elseif t == "UDim" then
			return string.format("UDim.new(%s, %s)", v.Scale, v.Offset)
		elseif t == "EnumItem" then
			return tostring(v)
		elseif t == "BrickColor" then
			return "BrickColor.new(" .. string.format("%q", v.Name) .. ")"
		elseif t == "table" then
			if d >= 3 or seen[v] then return "{}" end
			seen[v] = true
			local parts, n = {}, 0
			local len = #v
			for i = 1, math.min(len, 24) do
				n = n + 1
				parts[n] = repr(v[i], d + 1, seen)
			end
			if len == 0 then
				for k, val in pairs(v) do
					if n >= 24 then break end
					n = n + 1
					local ks = type(k) == "string" and ("[" .. string.format("%q", k) .. "]") or ("[" .. repr(k, d + 1, seen) .. "]")
					parts[n] = ks .. " = " .. repr(val, d + 1, seen)
				end
			end
			seen[v] = nil
			return "{" .. table.concat(parts, ", ") .. "}"
		end
		return "nil"
	end

	function F.replay(inst, m, a)
		local parts = {}
		for i = 1, math.min(a.n or 0, 12) do parts[i] = repr(a[i], 0, {}) end
		local code = instExpr(inst) .. ":" .. m .. "(" .. table.concat(parts, ", ") .. ")"
		if #code > 700 then return nil end
		return code
	end

	function F.rule(self, m, ...)
		if typeof(self) ~= "Instance" then return 0 end
		local nm = self.Name
		if X.block[nm] then
			enqueue({ k = 4, s = self, m = "BLOCKED " .. m, a = pack(...), t = clock() })
			return 1
		end
		local f = X.mod[nm]
		if f then
			local a = pack(...)
			local ok, res = pcall(f, a)
			if ok and res == false then return 1 end
			if ok then
				if type(res) == "table" then
					if not res.n then res.n = #res end
					return 2, res
				end
				return 2, a
			end
		end
		return 0
	end

	function F.capCall(self, m, ex, ...)
		if self == X.probeSelf then
			X.probeHit = true
			return nil
		end
		lastNcSelf = self
		lastNcT = clock()
		local mu = mutedC[self]
		if mu then
			local c = mu.c + 1
			mu.c = c
			if c % mu.every ~= 0 then return nil end
		end
		local sc = nil
		if not ex then sc = getCS() end
		return enqueue({ k = 1, d = "C2S", s = self, m = m, a = pack(...), t = clock(), sc = sc, ex = ex })
	end

	function F.capSys(self, m, ...)
		enqueue({ k = 4, s = self, m = m, a = pack(...), t = clock() })
	end

	local capCall, capSys, capNet = F.capCall, F.capSys, F.capNet

	function F.ncHook(self, ...)
		local m = getnm()
		local kind = INTEREST[m]
		if kind == nil or busy or not alive then
			return oldNc(self, ...)
		end
		if kind <= 2 then
			if X.rules then
				local act2, a = F.rule(self, m, ...)
				if act2 == 1 then return nil end
				if act2 == 2 then
					setnm(m)
					return oldNc(self, unpack(a, 1, a.n))
				end
			end
			if S.nc and MOD.nc then
				local ok, ent = pcall(capCall, self, m, ckc(), ...)
				if kind == 2 and ok and ent then
					setnm(m)
					local r = pack(oldNc(self, ...))
					enqueue({ k = 2, r = ent, v = r })
					return unpack(r, 1, r.n)
				elseif not ok then
					fault("nc")
				end
			end
			setnm(m)
			return oldNc(self, ...)
		elseif kind == 3 then
			pcall(capSys, self, m, ...)
			if m ~= "Kick" or self == LP then
				pcall(saveNow, sysReason(m))
			end
			X.sysM = m
			X.sysT = clock()
			setnm(m)
			return oldNc(self, ...)
		else
			if (MOD.net or MOD.http) and (self == game or self == HS) then
				local a1 = ...
				X.httpUrl = a1
				setnm(m)
				local r = pack(oldNc(self, ...))
				X.httpUrl = nil
				pcall(capNet, m, a1, nil, r[1])
				return unpack(r, 1, r.n)
			end
			setnm(m)
			return oldNc(self, ...)
		end
	end

	function F.wrapInvoke(rf, cb)
		if RF.isW[cb] then return cb end
		local w = function(...)
			if MOD.cb and alive and not busy then
				local ent = enqueue({ k = 1, d = "S2C", s = rf, m = "OnClientInvoke", a = pack(...), t = clock() })
				if ent then
					local r = pack(cb(...))
					enqueue({ k = 2, r = ent, v = r })
					return unpack(r, 1, r.n)
				end
			end
			return cb(...)
		end
		RF.isW[w] = true
		return w
	end

	local function wrapCb(rf)
		if type(getcallbackvalue) ~= "function" then return end
		local ok, cb = pcall(getcallbackvalue, rf, "OnClientInvoke")
		if not ok or type(cb) ~= "function" then return end
		if RF.isW[cb] or RF.wrap[rf] == cb then return end
		local cnt = RF.count[rf] or 0
		if cnt >= 4 then return end
		local w = F.wrapInvoke(rf, cb)
		if pcall(function() rf.OnClientInvoke = w end) then
			RF.wrap[rf] = w
			RF.count[rf] = cnt + 1
			RF.n = RF.n + 1
		end
	end

	function F.trackRF(rf)
		if RF.seen[rf] or #RF.list >= K.RF_CAP then return end
		local ok, u = pcall(rf.IsDescendantOf, rf, SV.CoreGui)
		if ok and u then return end
		RF.seen[rf] = true
		RF.list[#RF.list + 1] = rf
		if MOD.cb then
			task.delay(0.5, function()
				if alive and MOD.cb then pcall(wrapCb, rf) end
			end)
		end
	end

	local function makeFire(holder)
		return function(self, ...)
			if MOD.fn and S.nc and alive and not busy
				and not (lastNcSelf == self and clock() - lastNcT < 0.004) then
				local ok = pcall(capCall, self, "FireServer", ckc(), ...)
				if not ok then fault("fn") end
			end
			return holder.old(self, ...)
		end
	end

	local function makeInvoke(holder)
		return function(self, ...)
			if MOD.fn and S.nc and alive and not busy
				and not (lastNcSelf == self and clock() - lastNcT < 0.004) then
				local ok, ent = pcall(capCall, self, "InvokeServer", ckc(), ...)
				if ok and ent then
					local r = pack(holder.old(self, ...))
					enqueue({ k = 2, r = ent, v = r })
					return unpack(r, 1, r.n)
				elseif not ok then
					fault("fn")
				end
			end
			return holder.old(self, ...)
		end
	end

	IN.nc = function()
		if INST.nc then
			MOD.nc = true
			return true
		end
		if not (hookmetamethod and getnm) then return false end
		touchFlag("nc", 30)
		local wrap = nc(F.ncHook)
		F.ncWrap = wrap
		local ok, old = pcall(hookmetamethod, game, "__namecall", wrap)
		if ok and type(old) == "function" then
			oldNc = old
			INST.nc = true
			MOD.nc = true
			return true
		end
		return false
	end

	IN.fn = function()
		if INST.fn then
			MOD.fn = true
			return true
		end
		if not hookfunction then return false end
		local any = false
		local function try(cls, method, make, useNc)
			local ok, inst = pcall(Instance.new, cls)
			if not ok or typeof(inst) ~= "Instance" then return end
			local okf, fn = pcall(function() return inst[method] end)
			pcall(inst.Destroy, inst)
			if okf and F.hookWith(fn, make, useNc) then any = true end
		end
		try("RemoteEvent", "FireServer", makeFire, true)
		try("UnreliableRemoteEvent", "FireServer", makeFire, true)
		try("RemoteFunction", "InvokeServer", makeInvoke, false)
		if any then
			INST.fn = true
			MOD.fn = true
		end
		return any
	end

	local function attach(r)
		if attached[r] ~= nil or N.att >= K.ATT_CAP then return end
		local ok, u = pcall(r.IsDescendantOf, r, SV.CoreGui)
		if ok and u then
			attached[r] = false
			return
		end
		local okc, conn = pcall(function()
			return r.OnClientEvent:Connect(function(...)
				if not (MOD.s2c and alive) then return end
				local mu = mutedS[r]
				if mu then
					local c = mu.c + 1
					mu.c = c
					if c % mu.every ~= 0 then return end
				end
				enqueue({ k = 1, d = "S2C", s = r, m = "OnClientEvent", a = pack(...), t = clock() })
			end)
		end)
		if not okc or not conn then return end
		attached[r] = conn
		N.att = N.att + 1
		pcall(function()
			local dconn
			dconn = r.Destroying:Connect(function()
				pcall(conn.Disconnect, conn)
				pcall(dconn.Disconnect, dconn)
				if attached[r] then
					attached[r] = nil
					N.att = N.att - 1
				end
			end)
		end)
	end

	local function consider(inst)
		local cn = inst.ClassName
		if cn == "RemoteEvent" or cn == "UnreliableRemoteEvent" then
			attach(inst)
		elseif cn == "RemoteFunction" then
			F.trackRF(inst)
		end
	end

	IN.s2c = function()
		if INST.s2c then
			MOD.s2c = true
			return true
		end
		INST.s2c = true
		MOD.s2c = true
		conns[#conns + 1] = game.DescendantAdded:Connect(consider)
		task.spawn(function()
			task.wait(0.5)
			pcall(function()
				local list = game:GetDescendants()
				for i = 1, #list do
					if not alive then return end
					consider(list[i])
					if i % 1500 == 0 then task.wait() end
				end
			end)
			if CAP.getnilinstances then
				pcall(function()
					local l = getnilinstances()
					for i = 1, math.min(#l, 4000) do consider(l[i]) end
				end)
			end
		end)
		return true
	end

	IN.cb = function()
		if INST.cb then
			MOD.cb = true
			return true
		end
		if type(getcallbackvalue) ~= "function" then return false end
		INST.cb = true
		MOD.cb = true
		for i = 1, #RF.list do pcall(wrapCb, RF.list[i]) end
		return true
	end

	IN.ni = function()
		if INST.ni then
			MOD.ni = true
			return true
		end
		if not hookmetamethod then return false end
		local old
		local ok, o = pcall(hookmetamethod, game, "__newindex", nc(function(self, k, v)
			if k == "OnClientInvoke" and MOD.ni and alive and not busy and type(v) == "function"
				and typeof(self) == "Instance" then
				v = F.wrapInvoke(self, v)
			end
			return old(self, k, v)
		end))
		if not ok or type(o) ~= "function" then return false end
		old = o
		INST.ni = true
		MOD.ni = true
		return true
	end

	IN.sys = function()
		if INST.sys then
			MOD.sys = true
			return true
		end
		local any = false
		local function wrap(fn, tag)
			local ok = F.hookWith(fn, function(holder)
				return function(a, ...)
					if MOD.sys and alive and not busy then pcall(F.capSrc, tag, a) end
					return holder.old(a, ...)
				end
			end, true)
			if ok then any = true end
		end
		wrap(genv.queue_on_teleport, "queue_on_teleport")
		wrap(genv.queueonteleport, "queue_on_teleport")
		if type(genv.syn) == "table" then wrap(genv.syn.queue_on_teleport, "queue_on_teleport") end
		wrap(genv.setclipboard, "setclipboard")
		wrap(genv.toclipboard, "setclipboard")
		wrap(genv.set_clipboard, "setclipboard")
		local function direct(inst, method)
			local okf, fn = pcall(function() return inst[method] end)
			if not okf then return end
			local ok = F.hookWith(fn, function(holder)
				return function(self, ...)
					if MOD.sys and alive and not busy
						and not (X.sysM == method and clock() - X.sysT < 0.05) then
						pcall(capSys, self, method, ...)
						if method ~= "Kick" or self == LP then
							pcall(saveNow, sysReason(method))
						end
					end
					return holder.old(self, ...)
				end
			end, false)
			if ok then any = true end
		end
		direct(LP, "Kick")
		local okT, ts = pcall(game.GetService, game, "TeleportService")
		if okT and ts then
			for _, nm in ipairs({ "Teleport", "TeleportToPlaceInstance", "TeleportAsync", "TeleportToSpawnByName", "TeleportPartyAsync", "TeleportToPrivateServer" }) do
				direct(ts, nm)
			end
		end
		conns[#conns + 1] = SV.GuiService.ErrorMessageChanged:Connect(function(msg)
			if type(msg) == "string" and msg ~= "" then
				local prev = busy
				busy = true
				pcall(newRec, "SYS", "GuiService", "ErrorMessage", { clean(msg:sub(1, 200)) }, clock())
				busy = prev
				pcall(saveNow, "error")
			end
		end)
		conns[#conns + 1] = LP.OnTeleport:Connect(function(state)
			if state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress then
				pcall(saveNow, "teleport")
			end
		end)
		INST.sys = true
		MOD.sys = true
		return any
	end

	IN.net = function()
		if INST.net then
			MOD.net = true
			return true
		end
		local any = false
		local function hookReq(fn, tag)
			local ok = F.hookWith(fn, function(holder)
				return function(opts, ...)
					if MOD.net and alive and not busy then
						local url, meth
						if type(opts) == "table" then
							url = opts.Url or opts.url or opts.URL
							meth = opts.Method or opts.method
						elseif type(opts) == "string" then
							url = opts
						end
						local r = pack(holder.old(opts, ...))
						pcall(capNet, tag, url, meth, r[1])
						return unpack(r, 1, r.n)
					end
					return holder.old(opts, ...)
				end
			end, false)
			if ok then any = true end
		end
		hookReq(genv.request, "request")
		hookReq(genv.http_request, "http_request")
		hookReq(genv.httprequest, "httprequest")
		if type(genv.syn) == "table" then hookReq(genv.syn.request, "syn.request") end
		if type(genv.http) == "table" then hookReq(genv.http.request, "http.request") end
		if type(genv.fluxus) == "table" then hookReq(genv.fluxus.request, "fluxus.request") end
		INST.net = true
		MOD.net = true
		return any
	end

	IN.http = function()
		if INST.http then
			MOD.http = true
			return true
		end
		local any = false
		for _, name in ipairs({ "HttpGet", "HttpGetAsync" }) do
			local okf, fn = pcall(function() return game[name] end)
			if okf then
				local ok = F.hookWith(fn, function(holder)
					return function(self, url, ...)
						if MOD.http and alive and not busy and not (X.httpUrl ~= nil and X.httpUrl == url) then
							local r = pack(holder.old(self, url, ...))
							pcall(capNet, name, url, nil, r[1])
							return unpack(r, 1, r.n)
						end
						return holder.old(self, url, ...)
					end
				end, false)
				if ok then any = true end
			end
		end
		INST.http = true
		MOD.http = true
		return any
	end

	IN.ws = function()
		if INST.ws then
			MOD.ws = true
			return true
		end
		local W = genv.WebSocket or genv.websocket
		if type(W) ~= "table" or type(W.connect) ~= "function" then return false end
		local ok = F.hookWith(W.connect, function(holder)
			return function(url, ...)
				local ws = holder.old(url, ...)
				if MOD.ws and alive and not busy then
					pcall(capNet, "ws.connect", url, nil, nil)
					if type(ws) == "table" and type(ws.Send) == "function" then
						local send = ws.Send
						pcall(function()
							ws.Send = function(s, msg, ...)
								if MOD.ws and alive and not busy then pcall(capNet, "ws.send", url, nil, msg) end
								return send(s, msg, ...)
							end
						end)
					end
				end
				return ws
			end
		end, false)
		INST.ws = true
		MOD.ws = ok
		return ok
	end

	IN.req = function()
		if INST.req then
			MOD.req = true
			return true
		end
		local ok = F.hookWith(genv.require or require, function(holder)
			return function(m, ...)
				if MOD.req and alive and not busy and typeof(m) == "Instance" then
					enqueue({ k = 4, s = m, m = "require", a = pack(), full = true, t = clock() })
				end
				return holder.old(m, ...)
			end
		end, false)
		INST.req = true
		MOD.req = ok
		return ok
	end

	F.h[4] = function(e, now)
		local nm = "?"
		if typeof(e.s) == "Instance" then
			local i = getInfo(e.s)
			nm = e.full and i.full or i.nm
		end
		newRec("SYS", nm, e.m, (packStr(e.a, 3)), now)
	end

	F.onTick(function(now)
		if MOD.cb and now - X.lastRf >= 8 then
			X.lastRf = now
			for i = 1, #RF.list do pcall(wrapCb, RF.list[i]) end
		end
		if now - X.lastWd < 10 or not (INST.nc and S.nc and MOD.nc) or X.wdN >= 2 then return end
		X.lastWd = now
		task.defer(function()
			if not alive or busy then return end
			if not X.probe then
				local okp, p = pcall(Instance.new, "RemoteEvent")
				if okp then X.probe = p end
			end
			local p = X.probe
			if not p then return end
			X.probeSelf = p
			X.probeHit = false
			pcall(function() p:FireServer("aluz_probe") end)
			X.probeSelf = nil
			if X.probeHit then
				X.wdFail = 0
			else
				X.wdFail = X.wdFail + 1
				if X.wdFail >= 2 then
					X.wdFail = 0
					X.wdN = X.wdN + 1
					INST.nc = false
					IN.nc()
				end
			end
		end)
	end)

	F.stage("nc", 1, function()
		if IN.nc() and CFG.nc then S.nc = true end
	end)
	F.stage("fn", 2, IN.fn)
	F.stage("s2c", 3, IN.s2c)
	F.stage("sys", 4, IN.sys)
	F.stage("net", 5, IN.net)
	F.stage("http", 6, IN.http)
	F.stage("ni", 7, IN.ni)
	F.stage("ws", 8, IN.ws)
	F.stage("req", 9, IN.req)
	F.stage("cb", 12, IN.cb)
end
