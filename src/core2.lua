do local _ = "aluzspy@1.2.1-max" if F and F.trace then F.trace("load core2") end end
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

	local function ci(w)
		return (w:gsub("%a", function(c) return "[" .. c:lower() .. c:upper() .. "]" end))
	end

	local function escPat(s)
		return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
	end

	local GROUPS = {
		{ pat = ci("api[_%-]?key"), plain = { "api_key", "api-key", "apikey" } },
		{ pat = ci("token"), plain = { "token" } },
		{ pat = ci("secret"), plain = { "secret" } },
		{ pat = ci("passwd"), plain = { "passwd" } },
		{ pat = ci("password"), plain = { "password" } },
		{ pat = ci("authorization"), plain = { "authorization" } },
		{ pat = ci("cookie"), plain = { "cookie" } },
		{ pat = ci("sessionid"), plain = { "sessionid" } },
	}

	local RS = { calls = 0, bytes = 0 }
	local LONG = ("%w"):rep(56)

	local function redact(s)
		if type(s) ~= "string" or #s == 0 or #s > 20000000 then return s end
		RS.calls = RS.calls + 1
		RS.bytes = RS.bytes + #s
		local low = s:lower()
		if low:find("warning:", 1, true) then
			s = s:gsub("_|WARNING:%-DO%-NOT%-SHARE[^%s\\\"';,]*", "[ROBLOSECURITY masked]")
		end
		if low:find("/api/webhooks/", 1, true) then
			s = s:gsub("(discord%w*%.com/api/webhooks/%d+/)([%w_%-]+)", "%1[masked]")
		end
		if low:find("api.telegram.org/bot", 1, true) then
			s = s:gsub("(api%.telegram%.org/bot)([%w:_%-]+)", "%1[masked]")
		end
		if low:find("bearer", 1, true) then
			s = s:gsub("([Bb]earer%s+)([%w%-%._~%+/]+=*)", "%1[masked]")
		end
		if s:find("eyJ", 1, true) then
			s = s:gsub("eyJ[%w_%-]+%.[%w_%-]+%.[%w_%-]+", "[jwt masked]")
		end
		for i = 1, #GROUPS do
			local g = GROUPS[i]
			local hit = false
			for j = 1, #g.plain do
				if low:find(g.plain[j], 1, true) then
					hit = true
					break
				end
			end
			if hit then
				s = s:gsub("(" .. g.pat .. ")([\\\"']*%s*[:=]%s*[\\\"']*)([%w%-%._~%+/=]+)", function(k, sep, v)
					if #v >= 8 then return k .. sep .. "[masked]" end
				end)
			end
		end
		if low:find("@", 1, true) then
			s = s:gsub("[%w%._%%%+%-]+@[%w%-]+%.[%w%.%-]+", "[email]")
		end
		if s:find("%d+%.%d+%.%d+%.%d+") then
			s = s:gsub("(%d+)%.(%d+)%.(%d+)%.(%d+)", function(a, b, c, d)
				a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
				if a and b and c and d and a > 0 and a <= 255 and b <= 255 and c <= 255 and d <= 255 then return "[ip]" end
			end)
		end
		if low:find("users", 1, true) then
			s = s:gsub("([A-Za-z]:[\\/]+[Uu]sers[\\/]+)([^\\/\"'%s]+)", "%1[user]")
			s = s:gsub("(/[Uu]sers/)([^/\"'%s]+)", "%1[user]")
		end
		if low:find("/home/", 1, true) then
			s = s:gsub("(/home/)([^/\"'%s]+)", "%1[user]")
		end
		if #s <= 1500000 and s:find(LONG) then
			s = s:gsub("%f[%w]%w+%f[%W]", function(w)
				if #w >= 56 and w:find("%d") and w:find("%a") then return "[blob " .. #w .. "]" end
			end)
		end
		if CFG.redactIds and LP then
			local okn, nm = pcall(function() return LP.Name end)
			local okd, dn = pcall(function() return LP.DisplayName end)
			local oki, id = pcall(function() return LP.UserId end)
			if okn and type(nm) == "string" and #nm >= 3 then s = s:gsub(escPat(nm), "[player]") end
			if okd and type(dn) == "string" and #dn >= 3 then s = s:gsub(escPat(dn), "[player]") end
			if oki and id and id ~= 0 then s = s:gsub("%f[%d]" .. tostring(id) .. "%f[%D]", "[userid]") end
		end
		return s
	end
	F.redact = redact
	F.redactStats = function() return { calls = RS.calls, bytes = RS.bytes, on = CFG.redact == true, ids = CFG.redactIds == true } end

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
