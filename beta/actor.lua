local okAC, errAC = xpcall(function()
	if not F.job then return end

	local AC = { id = nil, ev = nil, n = 0, msgs = 0, failed = 0, notes = {}, map = {}, mapn = 0, last = 0, done = setmetatable({}, weak) }

	local PAYLOAD = [==[
local ID = __ID__
local AX = __AX__
local okc, ch = pcall(get_comm_channel, tonumber(ID) or ID)
if not okc or not ch then return end
local pack, unpack, clock = table.pack, table.unpack or unpack, os.clock
local function fire(...)
	return (pcall(ch.Fire, ch, ...))
end
fire("H", AX, "start")
if not (hookmetamethod and getnamecallmethod) then
	fire("H", AX, "nohook")
	return
end
local setnm = setnamecallmethod or function() end
local ck = checkcaller or function() return false end
local seq, last, lastT = 0, nil, 0
local function send(kind, id, m, self, n, ...)
	if fire(kind, AX, id, m, self, n, ...) then return end
	local args = pack(...)
	local lim = math.min(args.n, 6)
	local s = {}
	for i = 1, lim do
		local ok, v = pcall(tostring, args[i])
		s[i] = "~" .. (ok and v or "?")
	end
	fire(kind, AX, id, m, self, n, unpack(s, 1, lim))
end
local old
local function hook(self, ...)
	local m = getnamecallmethod()
	if (m == "FireServer" or m == "InvokeServer") and not ck() then
		seq = seq + 1
		local id = seq
		last, lastT = self, clock()
		if m == "InvokeServer" then
			send("C", id, m, self, select("#", ...), ...)
			setnm(m)
			local r = pack(old(self, ...))
			send("R", id, m, nil, r.n, unpack(r, 1, r.n))
			return unpack(r, 1, r.n)
		end
		send("C", id, m, self, select("#", ...), ...)
	end
	setnm(m)
	return old(self, ...)
end
local okh, o = pcall(hookmetamethod, game, "__namecall", newcclosure and newcclosure(hook) or hook)
if okh and type(o) == "function" then
	old = o
	fire("H", AX, "hooked")
else
	fire("H", AX, "failed")
	return
end
pcall(function()
	if not hookfunction then return end
	local re = Instance.new("RemoteEvent")
	local fn = re.FireServer
	local oldf
	oldf = hookfunction(fn, function(self, ...)
		if typeof(self) == "Instance" and not ck() and not (last == self and clock() - lastT < 0.004) then
			seq = seq + 1
			send("C", seq, "FireServer", self, select("#", ...), ...)
		end
		return oldf(self, ...)
	end)
end)
]==]

	local function onMsg(kind, ax, id, m, self, n, ...)
		if not (MOD.ac and alive) then return end
		AC.msgs = AC.msgs + 1
		if kind == "C" then
			if not S.nc or typeof(self) ~= "Instance" then return end
			local mu = mutedC[self]
			if mu then
				local c = mu.c + 1
				mu.c = c
				if c % mu.every ~= 0 then return end
			end
			local a = pack(...)
			if type(n) == "number" and n >= 0 and n <= 255 then a.n = n end
			local ent = enqueue({ k = 1, d = "C2S", s = self, m = m, a = a, t = clock(), ex = false })
			if ent and m == "InvokeServer" then
				AC.map[tostring(ax) .. ":" .. tostring(id)] = ent
				AC.mapn = AC.mapn + 1
				if AC.mapn > 600 then
					AC.map = {}
					AC.mapn = 0
				end
			end
		elseif kind == "R" then
			local key = tostring(ax) .. ":" .. tostring(id)
			local ent = AC.map[key]
			if ent then
				AC.map[key] = nil
				enqueue({ k = 2, r = ent, v = pack(...) })
			end
		elseif kind == "H" then
			if #AC.notes < 30 then AC.notes[#AC.notes + 1] = "actor " .. tostring(ax) .. ": " .. tostring(id) end
		end
	end

	local function inject(actor, ax)
		local lit = string.format("%q", tostring(AC.id))
		local code = PAYLOAD:gsub("__ID__", function() return lit end)
		code = code:gsub("__AX__", function() return tostring(ax) end)
		return (pcall(run_on_actor, actor, code))
	end

	local function poll()
		if not (MOD.ac and INST.ac) then return end
		local ok, list = pcall(getactors)
		if not ok or type(list) ~= "table" then return end
		for i = 1, math.min(#list, 24) do
			local a = list[i]
			if not AC.done[a] then
				AC.done[a] = true
				AC.n = AC.n + 1
				if not inject(a, AC.n) then AC.failed = AC.failed + 1 end
			end
		end
	end

	IN.ac = function()
		if INST.ac then
			MOD.ac = true
			return true
		end
		if type(getactors) ~= "function" or type(run_on_actor) ~= "function" or type(create_comm_channel) ~= "function" then
			return false
		end
		local a, b = create_comm_channel()
		local id, ev = a, b
		if typeof(a) == "Instance" then id, ev = b, a end
		if id == nil or ev == nil then return false end
		local sig = ev.Event or ev
		local okc = pcall(function() AC.conn = sig:Connect(onMsg) end)
		if not okc then return false end
		AC.id, AC.ev = id, ev
		INST.ac = true
		MOD.ac = true
		poll()
		return true
	end

	F.onTick(function(now)
		if MOD.ac and INST.ac and now - AC.last >= 6 then
			AC.last = now
			poll()
		end
	end)

	F.stage("ac", 14, IN.ac)

	F.api.actors = function()
		local out = { enabled = MOD.ac, injected = AC.n, failed = AC.failed, messages = AC.msgs, notes = AC.notes }
		warn("[AluzSpy] actors: " .. tostring(F.enc(out)))
		return out
	end
	F.extra.actors = function()
		return { enabled = MOD.ac, injected = AC.n, failed = AC.failed, messages = AC.msgs, notes = AC.notes }
	end
	F.extraChips[#F.extraChips + 1] = { "ACT", function() return MOD.ac end, function(v) return F.setMod("ac", v) end }
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okAC then
	warn("[AluzSpy] actor failed: " .. tostring(errAC))
end
