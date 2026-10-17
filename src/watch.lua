do local _ = "aluzspy@1.2.2-max" if F and F.trace then F.trace("load watch") end end
local okWT, errWT = xpcall(function()
	F.api = F.api or {}
	F.alerts = {}
	for _, n in ipairs({ "ps", "tc" }) do
		MOD[n] = false
		INST[n] = false
		F.defMods[n] = false
		if CFG.mods[n] == nil then CFG.mods[n] = false end
	end

	local function mask(s)
		if type(s) ~= "string" then return s end
		s = s:gsub("_|WARNING:%-DO%-NOT%-SHARE[^%s\"';,]*", "[ROBLOSECURITY masked]")
		s = s:gsub("[%w_%-%.]+", function(w)
			if #w >= 28 then return w:sub(1, 6) .. ".." .. #w end
		end)
		return s
	end

	local function maskUrl(u)
		if type(u) ~= "string" then return u end
		u = u:gsub("([%?&][%w_%-%.]+=)([^&#]+)", function(k, v)
			if #v >= 16 then return k .. v:sub(1, 4) .. ".." .. #v end
		end)
		u = u:gsub("(/webhooks/%d+/)([%w_%-]+)", "%1[masked]")
		u = u:gsub("(api%.telegram%.org/bot)([%w:_%-]+)", "%1[masked]")
		return u
	end
	F.mask, F.maskUrl = mask, maskUrl

	local function ci(w)
		return (w:gsub("%a", function(c) return "[" .. c:lower() .. c:upper() .. "]" end))
	end

	local function escPat(s)
		return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
	end

	local KEYS = {}
	for _, w in ipairs({ "api[_%-]?key", "token", "secret", "passwd", "password", "authorization", "cookie", "sessionid" }) do
		KEYS[#KEYS + 1] = ci(w)
	end

	local RS = { calls = 0, bytes = 0 }

	local function redact(s)
		if type(s) ~= "string" or #s == 0 then return s end
		RS.calls = RS.calls + 1
		RS.bytes = RS.bytes + #s
		s = s:gsub("_|WARNING:%-DO%-NOT%-SHARE[^%s\\\"';,]*", "[ROBLOSECURITY masked]")
		s = s:gsub("(discord%w*%.com/api/webhooks/%d+/)([%w_%-]+)", "%1[masked]")
		s = s:gsub("(api%.telegram%.org/bot)([%w:_%-]+)", "%1[masked]")
		s = s:gsub("([Bb]earer%s+)([%w%-%._~%+/]+=*)", "%1[masked]")
		s = s:gsub("eyJ[%w_%-]+%.[%w_%-]+%.[%w_%-]+", "[jwt masked]")
		for i = 1, #KEYS do
			s = s:gsub("(" .. KEYS[i] .. ")([\\\"']*%s*[:=]%s*[\\\"']*)([%w%-%._~%+/=]+)", function(k, sep, v)
				if #v >= 8 then return k .. sep .. "[masked]" end
			end)
		end
		s = s:gsub("[%w%._%%%+%-]+@[%w%-]+%.[%w%.%-]+", "[email]")
		s = s:gsub("(%d+)%.(%d+)%.(%d+)%.(%d+)", function(a, b, c, d)
			a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
			if a and b and c and d and a > 0 and a <= 255 and b <= 255 and c <= 255 and d <= 255 then return "[ip]" end
		end)
		s = s:gsub("([A-Za-z]:[\\/]+[Uu]sers[\\/]+)([^\\/\"'%s]+)", "%1[user]")
		s = s:gsub("(/[Uu]sers/)([^/\"'%s]+)", "%1[user]")
		s = s:gsub("(/home/)([^/\"'%s]+)", "%1[user]")
		s = s:gsub("%f[%w]%w+%f[%W]", function(w)
			if #w >= 56 and w:find("%d") and w:find("%a") then return "[blob " .. #w .. "]" end
		end)
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

	local SCH, schN = {}, 0
	local function noteSchema(inst, dir, a)
		local key = (dir == "S2C" and "S:" or "C:") .. getInfo(inst).full
		local s = SCH[key]
		if not s then
			if schN >= 700 then return end
			schN = schN + 1
			s = { min = 255, max = 0, pos = {}, n = 0 }
			SCH[key] = s
		end
		s.n = s.n + 1
		local n = a.n or 0
		if n < s.min then s.min = n end
		if n > s.max then s.max = n end
		for i = 1, math.min(n, 6) do
			local t = typeof(a[i])
			local p = s.pos[i]
			if not p then
				p = { c = 0 }
				s.pos[i] = p
			end
			if not p[t] and p.c < 3 then
				p[t] = true
				p.c = p.c + 1
			end
		end
	end

	function F.schemaStr(dir, full)
		local s = SCH[(dir == "S2C" and "S:" or "C:") .. tostring(full)]
		if not s then return nil end
		local parts = {}
		for i = 1, math.min(s.max, 6) do
			local p, ts = s.pos[i], {}
			if p then
				for t in pairs(p) do
					if t ~= "c" then ts[#ts + 1] = t end
				end
			end
			table.sort(ts)
			parts[i] = #ts > 0 and table.concat(ts, "|") or "nil"
		end
		local str = "(" .. table.concat(parts, ", ") .. ")"
		if s.min ~= s.max then str = str .. " argc " .. s.min .. "-" .. s.max end
		return str
	end

	local h1 = F.h[1]
	if h1 then
		F.h[1] = function(e, now)
			local a, inst = e.a, e.s
			if a and typeof(inst) == "Instance" then pcall(noteSchema, inst, e.d, a) end
			return h1(e, now)
		end
	end

	local EXFIL = {
		{ "discord%.com/api/webhooks", "discord webhook" }, { "discordapp%.com/api/webhooks", "discord webhook" },
		{ "api%.telegram%.org/bot", "telegram bot" }, { "ROBLOSECURITY", ".ROBLOSECURITY cookie" },
		{ "_|WARNING:%-DO%-NOT%-SHARE", ".ROBLOSECURITY cookie" }, { "grabify", "ip logger" },
		{ "iplogger", "ip logger" }, { "ipify%.org", "ip lookup" }, { "pastebin%.com/api", "pastebin api" },
	}
	local alerted = {}
	local function alert(reason, url, now)
		local mu = tostring(maskUrl(url))
		local key = reason .. "|" .. mu:sub(1, 80)
		if alerted[key] then return end
		alerted[key] = true
		if #F.alerts < 50 then F.alerts[#F.alerts + 1] = { t = r2(now - T0), reason = reason, url = mu } end
		newRec("ALERT", mu:sub(1, 120), "exfil?", { reason }, now)
		if F.notify then F.notify("ALERT: " .. reason) end
	end

	local h3 = F.h[3]
	if h3 then
		F.h[3] = function(e, now)
			h3(e, now)
			pcall(function()
				local url = type(e.u) == "string" and e.u or ""
				local rec = X.netRecs[tostring(e.tag) .. "|" .. clean(url:sub(1, 200))]
				if rec and rec.live and rec.t0 == now then
					if e.sent then rec.a[#rec.a + 1] = "sent: " .. mask(clean(e.sent:sub(1, 200))) end
					if e.hd then rec.a[#rec.a + 1] = "hdr: " .. e.hd end
					rec.r = maskUrl(rec.r)
					rec.a[1] = maskUrl(rec.a[1])
				end
				local sent = type(e.sent) == "string" and e.sent or ""
				local hay = url .. " " .. sent
				for i = 1, #EXFIL do
					if hay:find(EXFIL[i][1]) then
						if sent ~= "" or e.mth == "POST" or e.mth == "post" then alert(EXFIL[i][2], url, now) end
						break
					end
				end
				if sent ~= "" and #sent < 4000 and url:find("webhooks", 1, true) then
					local low = sent:lower()
					if low:find(LP.Name:lower(), 1, true) or low:find(tostring(LP.UserId), 1, true) then
						alert("sends player identity to a webhook", url, now)
					end
				end
			end)
		end
	end

	local function wtNet(tag, url, meth, res, sent, hdr)
		if type(url) == "table" then
			meth = meth or url.Method
			url = url.Url or url.url
		end
		if type(url) == "string" and url:find("AluzSpy", 1, true) and url:find("version", 1, true) then return end
		local body, status
		if type(res) == "table" then
			body = res.Body or res.body
			status = res.StatusCode or res.status_code or res.Status
		elseif type(res) == "string" then
			body = res
		end
		if type(body) == "string" and #body > 24 and type(url) == "string" then F.nbPush(body, url) end
		local hd
		if type(hdr) == "table" then
			local t = {}
			pcall(function()
				for k, v in pairs(hdr) do
					if #t < 8 then t[#t + 1] = tostring(k):sub(1, 30) .. "=" .. mask(clean(tostring(v):sub(1, 60))) end
				end
			end)
			if #t > 0 then hd = table.concat(t, "; ") end
		end
		if sent ~= nil and type(sent) ~= "string" then sent = tostring(sent) end
		enqueue({
			k = 3, tag = tag, u = url, mth = meth, b = body, st = status, sent = sent, hd = hd,
			par = X.cof[coroutine.running()], t = clock(),
		})
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
						local url, meth, sent, hdr
						if type(opts) == "table" then
							url = opts.Url or opts.url or opts.URL
							meth = opts.Method or opts.method
							sent = opts.Body or opts.body
							hdr = opts.Headers or opts.headers
						elseif type(opts) == "string" then
							url = opts
						end
						local r = pack(holder.old(opts, ...))
						pcall(wtNet, tag, url, meth, r[1], sent, hdr)
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
	for _, s in ipairs(F.stages) do
		if s[1] == "net" then s[2] = IN.net end
	end

	local PROPS = {
		WalkSpeed = true, JumpPower = true, JumpHeight = true, HipHeight = true, Health = true, MaxHealth = true,
		Gravity = true, CFrame = true, Position = true, Anchored = true, PlatformStand = true,
	}
	local SENS = {
		WalkSpeed = true, JumpPower = true, JumpHeight = true, HipHeight = true, Health = true, MaxHealth = true, Gravity = true,
	}

	local function mine(self)
		local ch = LP.Character
		if not ch then return false end
		local p = self
		for _ = 1, 4 do
			if p == ch then return true end
			p = p.Parent
			if not p then return false end
		end
		return false
	end

	local precs, pn = {}, 0
	F.h[9] = function(e, now)
		local nm = "?"
		if typeof(e.s) == "Instance" then nm = getInfo(e.s).full end
		local key = e.p .. "|" .. nm .. "|" .. tostring(e.x)
		local val = select(2, pcall(ser, e.v, 0, {}))
		local rec = precs[key]
		if rec and rec.live and now - rec.t0 < WIN * 3 then
			rec.n = rec.n + 1
			rec.a[1] = val
			N.merged = N.merged + 1
			return
		end
		if not takeToken(now) then
			N.bucket = N.bucket + 1
			return
		end
		precs[key] = newRec("PROP", nm, e.p, { val }, now, e.x)
		pn = pn + 1
		if pn > 200 then
			precs = {}
			pn = 0
		end
	end

	IN.ps = function()
		if INST.ps then
			MOD.ps = true
			return true
		end
		if not hookmetamethod then return false end
		local old
		local ok, o = pcall(hookmetamethod, game, "__newindex", nc(function(self, k, v)
			if PROPS[k] and MOD.ps and alive and not busy then
				local ex = ckc()
				if ex or (SENS[k] and (self == workspace or mine(self))) then
					enqueue({ k = 9, s = self, p = k, v = v, x = ex, t = clock() })
				end
			end
			return old(self, k, v)
		end))
		if not ok or type(o) ~= "function" then return false end
		old = o
		INST.ps = true
		MOD.ps = true
		return true
	end

	IN.tc = function()
		if INST.tc then
			MOD.tc = true
			return true
		end
		local okI, ch = pcall(Instance.new, "TextChannel")
		if not okI or typeof(ch) ~= "Instance" then return false end
		local okf, fn = pcall(function() return ch.SendAsync end)
		pcall(ch.Destroy, ch)
		if not okf then return false end
		local ok = F.hookWith(fn, function(holder)
			return function(self, text, ...)
				if MOD.tc and alive and not busy and type(text) == "string" then
					enqueue({ k = 8, tag = "chat:SendAsync", a = pack(text), t = clock() })
				end
				return holder.old(self, text, ...)
			end
		end, false)
		INST.tc = true
		MOD.tc = ok
		return ok
	end

	F.stage("ps", 15, IN.ps)
	F.stage("tc", 16, IN.tc)

	F.api.alerts = function()
		for _, a in ipairs(F.alerts) do warn("[AluzSpy] ALERT " .. a.reason .. " -> " .. tostring(a.url)) end
		return F.alerts
	end
	F.api.schema = function(name)
		name = tostring(name or ""):lower()
		local out = {}
		for key in pairs(SCH) do
			if key:lower():find(name, 1, true) then
				local dir, full = key:sub(1, 1) == "S" and "S2C" or "C2S", key:sub(3)
				out[#out + 1] = { r = full, schema = F.schemaStr(dir, full) }
			end
		end
		table.sort(out, function(a, b) return a.r < b.r end)
		for i = 1, math.min(#out, 25) do warn("[AluzSpy] " .. out[i].r .. " " .. tostring(out[i].schema)) end
		return out
	end
	F.extra.watch = function()
		return { alerts = #F.alerts, schemas = schN }
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okWT then
	warn("[AluzSpy] watch failed: " .. tostring(errWT))
end
