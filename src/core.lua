do local _ = "aluzspy@1.2.2-max" if F and F.trace then F.trace("load core") end end
local SV = setmetatable({}, { __index = function(t, k)
	local v = game:GetService(k)
	rawset(t, k, v)
	return v
end })

local LP = SV.Players.LocalPlayer or SV.Players.PlayerAdded:Wait()

local genv
do
	local ok, g = pcall(getgenv)
	if ok and type(g) == "table" then genv = g else genv = _G end
end

do
	local prev = genv.AluzSpy
	if type(prev) == "table" and type(prev.shutdown) == "function" then
		pcall(prev.shutdown, true)
	end
end

local VERSION = "1.2.2-max"
local clock = os.clock
local pack = table.pack
local unpack = table.unpack or unpack
local floor = math.floor
local getnm = getnamecallmethod
local setnm = setnamecallmethod or function() end
local ckc = checkcaller or function() return false end
local HAS_W = type(writefile) == "function"

local CAP = {}
for _, n in ipairs({
	"hookfunction", "hookmetamethod", "clonefunction", "getcallbackvalue", "checkcaller", "getcallingscript",
	"newcclosure", "getnamecallmethod", "setnamecallmethod", "writefile", "readfile", "appendfile", "isfile",
	"makefolder", "isfolder", "delfile", "listfiles", "setclipboard", "decompile", "getscriptbytecode",
	"getnilinstances", "getscripts", "getloadedmodules", "request", "loadstring", "loadfile", "dofile",
	"getconnections", "firesignal", "fireclickdetector", "fireproximityprompt", "firetouchinterest",
	"setfenv", "getfenv", "getupvalues", "getconstants", "getprotos", "getscriptclosure", "getscripthash",
	"getgc", "getinstances", "getrawmetatable", "iscclosure",
}) do
	CAP[n] = type(genv[n]) == "function"
end
CAP.websocket = type(genv.WebSocket) == "table" or type(genv.websocket) == "table"
CAP.deobfuscate, CAP.reverse, CAP.vip = false, false, false

local PATH = { dir = "AluzSpy", dumpDir = "AluzSpy/Dump", ok = false }
do
	if type(makefolder) == "function" and type(isfolder) == "function" then
		local ok, res = pcall(function()
			if not isfolder(PATH.dir) then makefolder(PATH.dir) end
			if not isfolder(PATH.dumpDir) then makefolder(PATH.dumpDir) end
			return isfolder(PATH.dir) and isfolder(PATH.dumpDir)
		end)
		PATH.ok = ok and res == true
	end
end
function PATH.f(name)
	if PATH.ok then return PATH.dir .. "/" .. name end
	return "AluzSpy_" .. name
end
function PATH.d(name)
	if PATH.ok then return PATH.dumpDir .. "/" .. name end
	return "AluzDump_" .. name
end
PATH.flag = PATH.f(".boot")
PATH.cfg = PATH.f("config.json")
PATH.crash = PATH.f("crash.txt")
PATH.session = PATH.f("Save_" .. game.PlaceId .. "_" .. os.date("%Y%m%d_%H%M%S") .. ".json")
PATH.tag = os.date("%H%M%S")

local K = {
	LOGCAP = 4000, BUCKET_MAX = 800, BUCKET_RATE = 480, ATT_CAP = 800, RF_CAP = 500,
	DUMP_MAX = 800, DUMP_FILE_MAX = 16777216, DUMP_PEND_MAX = 50331648, DUMP_TOTAL = 134217728,
	MEM_ABS = 3000, MEM_GROW = 1200, SCRIPT_CAP = 800, SCRIPT_RESERVE = 200,
}
local QCAP, WIN = 3072, 1.2

local S = { nc = false, dump = true }
local MOD, INST = {}, {}
for _, n in ipairs({ "nc", "fn", "s2c", "sys", "net", "http", "ls", "cb", "ni", "rw", "ws", "req", "hx" }) do
	MOD[n] = false
	INST[n] = false
end
local CFG = {
	nc = true, dump = true, code = true, tree = true, callerDump = true, autoScripts = true, update = true,
	decode = true, sandbox = false, net = true,
	schema = 4, ver = "", profile = "max", autoDeobf = true, autoReverse = true,
	redact = true, redactIds = false, protected = {}, thr = {},
	mods = {}, crashes = {},
}
local alive, busy = true, false
local T0 = clock()

local q, qh, qt = {}, 0, 0
local oldNc, lastNcSelf, lastNcT = nil, nil, 0

local weak = { __mode = "k" }
local N = {
	total = 0, logged = 0, merged = 0, sampled = 0, supp = 0, bucket = 0, remotes = 0,
	dropQ = 0, err = 0, seq = 0, att = 0, netCount = 0, srcCount = 0,
}
local X = {
	dirty = false, lastAuto = -10, lastTick = clock(), lastMem = -100, lastRf = 0, lastWd = 0, lastFps = -100,
	mem = {}, stall = false, reason = "none", flagUntil = 0, flagNext = 0, tokens = K.BUCKET_MAX, tokT = clock(),
	sysM = nil, sysT = 0, httpUrl = nil, netRecs = {}, srcRecs = {}, chunk = 0, cof = setmetatable({}, weak),
	nb = {}, nbq = {}, rules = false, block = {}, mod = {}, probe = nil, probeSelf = nil, probeHit = false,
	wdFail = 0, wdN = 0, fps = 60, load = 0, memNow = 0, lowN = 0, spam = {}, recovered = nil, dt = 1,
}
local logs = {}
local stC, stS, info = setmetatable({}, weak), setmetatable({}, weak), setmetatable({}, weak)
local mutedC, mutedS, muteList, act = {}, {}, {}, {}
local seenFn, errMap, faults, conns, attached = {}, {}, {}, {}, {}
local RF = {
	list = {}, seen = setmetatable({}, weak), wrap = setmetatable({}, weak),
	isW = setmetatable({}, weak), count = setmetatable({}, weak), n = 0,
}
local D = {
	seen = {}, n = 0, list = {}, q = {}, h = 1, t = 0, pending = 0, skipped = 0, fail = 0,
	files = {}, bytes = 0, jobs = {}, sd = setmetatable({}, weak), sdf = setmetatable({}, weak), sdn = 0, sq = {},
	sqp = setmetatable({}, weak), fails = {},
}
local BAN = { set = {}, list = {}, safe = false, disabled = {} }
local FS = {}
local saveNow, handle, uiCount
local IN = {}
local OBS, REG = {}, {}
local F = { h = {}, ticks = {}, stages = {}, defMods = {
	fn = true, s2c = true, sys = true, net = true, http = true, ls = true, cb = true, ni = true, rw = true, ws = true,
	req = true, hx = true,
} }

for k, v in pairs(F.defMods) do CFG.mods[k] = v end

function FS.write(name, data)
	if not HAS_W then return false end
	return (pcall(writefile, name, data))
end
function FS.exists(name)
	if type(isfile) ~= "function" then return false end
	local ok, r = pcall(isfile, name)
	return ok and r == true
end
function FS.read(name)
	if type(readfile) ~= "function" then return nil end
	local ok, r = pcall(readfile, name)
	if ok then return r end
	return nil
end
function FS.del(name)
	if type(delfile) == "function" then
		pcall(delfile, name)
	end
end

function F.enc(t)
	local ok, js = pcall(SV.HttpService.JSONEncode, SV.HttpService, t)
	if ok then return js end
	return nil
end
function F.dec(s)
	local ok, t = pcall(SV.HttpService.JSONDecode, SV.HttpService, s)
	if ok then return t end
	return nil
end

function F.cfgLoad()
	local txt = FS.read(PATH.cfg)
	local t = type(txt) == "string" and F.dec(txt) or nil
	if type(t) ~= "table" then return end
	for k, v in pairs(CFG) do
		local nv = t[k]
		if type(v) == "table" then
			if type(nv) == "table" then
				for kk, vv in pairs(nv) do v[kk] = vv end
			end
		elseif type(nv) == type(v) then
			CFG[k] = nv
		end
	end
end

function F.cfgSave()
	FS.write(PATH.cfg, F.enc(CFG) or "{}")
end

function F.reset()
	CFG.crashes = {}
	CFG.mods = {}
	for k, v in pairs(F.defMods) do CFG.mods[k] = v end
	F.cfgSave()
end

local function r2(x)
	return floor(x * 100 + 0.5) / 100
end

local function nc(f)
	if newcclosure then
		local ok, r = pcall(newcclosure, f)
		if ok and type(r) == "function" then return r end
	end
	return f
end

local function noteErr(err)
	N.err = N.err + 1
	local msg = tostring(err):sub(1, 90)
	if errMap[msg] ~= nil then
		errMap[msg] = errMap[msg] + 1
	else
		local n = 0
		for _ in pairs(errMap) do n = n + 1 end
		if n < 20 then errMap[msg] = 1 end
	end
end

local function fault(mod)
	N.err = N.err + 1
	faults[mod] = (faults[mod] or 0) + 1
	if faults[mod] >= 30 and MOD[mod] then
		MOD[mod] = false
		X.tripped = X.tripped or {}
		X.tripped[mod] = clock()
	end
end

local function touchFlag(stage, secs)
	FS.write(PATH.flag, stage .. "\n" .. os.time())
	local u = clock() + secs
	if u > X.flagUntil then X.flagUntil = u end
end

local function armFlag(now)
	if now >= X.flagNext then
		X.flagNext = now + 6
		touchFlag("net-active", 20)
	end
end

do
	F.cfgLoad()
	S.dump = CFG.dump
	if FS.exists(PATH.flag) then
		local txt = FS.read(PATH.flag)
		local stage = type(txt) == "string" and txt:match("^([%w%-_]+)") or nil
		local ts = type(txt) == "string" and tonumber(txt:match("\n(%d+)")) or nil
		if not ts or math.abs(os.time() - ts) < 900 then
			-- 1.2.2-stable: soft recovery — only throttle the exact culprit once.
			-- Do NOT ban the whole risk set (that left only s2c/fn alive).
			local culprit = stage
			if stage == "net-active" then culprit = "net" end
			if stage == "nc" or stage == "namecall" then culprit = "nc" end
			if culprit and culprit ~= "boot" and culprit ~= "net-active" then
				CFG.crashes[culprit] = (CFG.crashes[culprit] or 0) + 1
				-- only hard-disable after 3 crashes of the SAME module
				if CFG.crashes[culprit] >= 3 then
					CFG.mods[culprit] = false
					BAN.set[culprit] = true
					BAN.disabled[culprit] = true
					BAN.safe = true
				else
					-- soft: delay install, still allow module
					BAN.safe = false
				end
			end
			X.recovered = { stage = stage or "?", age = ts and (os.time() - ts) or -1 }
			for k in pairs(BAN.set) do BAN.list[#BAN.list + 1] = k end
			table.sort(BAN.list)
			F.cfgSave()
		end
		FS.del(PATH.flag)
	end
end

local function clean(s)
	if type(s) ~= "string" then s = tostring(s) end
	if utf8 and utf8.len and not utf8.len(s) then
		s = s:gsub("[\128-\255]", function(c) return string.format("\\x%02x", c:byte()) end)
	end
	s = s:gsub("%c", " ")
	return s
end

local function ser(v, d, seen)
	local t = typeof(v)
	if t == "string" then
		local s = v
		if #s > 64 then s = s:sub(1, 64) .. ".." end
		return '"' .. clean(s) .. '"'
	elseif t == "number" then
		if v ~= v then return "nan" end
		if v == math.huge then return "inf" end
		if v == -math.huge then return "-inf" end
		return tostring(v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "nil" then
		return "nil"
	elseif t == "Instance" then
		local ok, full = pcall(v.GetFullName, v)
		local cn = v.ClassName
		if not ok then full = v.Name end
		if #full > 60 then full = ".." .. full:sub(-58) end
		return "<" .. cn .. " " .. clean(full) .. ">"
	elseif t == "table" then
		if d >= 2 or seen[v] then return "{..}" end
		seen[v] = true
		local parts, cnt = {}, 0
		for k, val in pairs(v) do
			cnt = cnt + 1
			if cnt > 6 then
				parts[#parts + 1] = ".."
				break
			end
			parts[#parts + 1] = "[" .. ser(k, d + 1, seen) .. "]=" .. ser(val, d + 1, seen)
		end
		seen[v] = nil
		local out = "{" .. table.concat(parts, ",") .. "}"
		if #out > 200 then out = out:sub(1, 200) .. "..}" end
		return clean(out)
	elseif t == "function" then
		return "<fn>"
	end
	local ok, s = pcall(tostring, v)
	if not ok then s = "?" end
	if #s > 60 then s = s:sub(1, 60) end
	return t .. ":" .. clean(s)
end

local function packStr(p, maxn)
	local out = {}
	local n = p and p.n or 0
	local lim = n < maxn and n or maxn
	for i = 1, lim do
		local ok, s = pcall(ser, p[i], 0, {})
		out[i] = ok and s or "<err>"
	end
	if n > lim then out[lim + 1] = "+" .. (n - lim) .. " more" end
	return out, n
end

local function getCS()
	if not getcallingscript then return nil end
	local ok, v = pcall(getcallingscript)
	if ok then return v end
	return nil
end

local function getInfo(inst)
	local i = info[inst]
	if i then return i end
	local nm, cls, par = "?", "?", true
	pcall(function()
		nm = inst.Name
		cls = inst.ClassName
		par = inst.Parent ~= nil
	end)
	local ok, f = pcall(inst.GetFullName, inst)
	local full = clean(ok and f or nm)
	if not par then full = "[nil]." .. full end
	i = { nm = nm, cls = cls, full = full }
	info[inst] = i
	return i
end

local function takeToken(now)
	X.tokens = X.tokens + (now - X.tokT) * K.BUCKET_RATE
	if X.tokens > K.BUCKET_MAX then X.tokens = K.BUCKET_MAX end
	X.tokT = now
	if X.tokens >= 1 then
		X.tokens = X.tokens - 1
		return true
	end
	return false
end

local function newRec(dir, remote, method, args, now, ex, caller)
	N.seq = N.seq + 1
	local idx = (N.seq - 1) % K.LOGCAP + 1
	local old = logs[idx]
	if old then old.live = false end
	local rec = {
		i = N.seq, t = r2(now - T0), t0 = now, d = dir, r = remote, m = method,
		n = 1, a = args, live = true, ex = ex, c = caller,
	}
	logs[idx] = rec
	N.logged = N.logged + 1
	X.dirty = true
	return rec
end

local function enqueue(e)
	if qt - qh >= QCAP then
		N.dropQ = N.dropQ + 1
		return nil
	end
	qt = qt + 1
	q[qt % QCAP + 1] = e
	return e
end

function F.nbPush(body, url)
	X.nb[body] = url
	local qn = X.nbq
	qn[#qn + 1] = body
	if #qn > 16 then
		local old = table.remove(qn, 1)
		X.nb[old] = nil
	end
end

function F.capSrc(tag, src, id, parent, url)
	enqueue({ k = 7, tag = tag, src = src, id = id, par = parent, url = url, t = clock() })
end

function F.capNet(tag, url, meth, res)
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
	enqueue({ k = 3, tag = tag, u = url, mth = meth, b = body, st = status, par = X.cof[coroutine.running()], t = clock() })
end

function F.hookWith(fn, make, useNc)
	if type(fn) ~= "function" or seenFn[fn] or not hookfunction then return false end
	seenFn[fn] = true
	local holder = {}
	if clonefunction then
		local okc, c = pcall(clonefunction, fn)
		if okc and type(c) == "function" then holder.old = c end
	end
	local h = make(holder)
	if useNc then h = nc(h) end
	local ok, o = pcall(hookfunction, fn, h)
	if not ok then return false end
	if type(o) == "function" then holder.old = o end
	return holder.old ~= nil
end

handle = function(e, now)
	local k = e.k
	local ob = OBS[k]
	if ob then
		for i = 1, #ob do
			local o = ob[i]
			if o.on then
				local ok, err = pcall(o.fn, e, e.t or now)
				if not ok then
					o.err = o.err + 1
					noteErr("obs_" .. tostring(o.name) .. ":" .. tostring(err))
					if o.err >= 25 then o.on = false end
				end
			end
		end
	end
	local h = F.h[k]
	if h then h(e, e.t or now) end
end

function F.process(budget)
	local t1 = clock()
	local n = 0
	while qh < qt do
		qh = qh + 1
		local idx = qh % QCAP + 1
		local e = q[idx]
		q[idx] = nil
		if e then handle(e, t1) end
		n = n + 1
		if n % 16 == 0 and clock() - t1 > budget then break end
	end
end

function F.fmt(n)
	if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
	if n >= 1000 then return string.format("%.1fk", n / 1000) end
	return tostring(n)
end

function F.onTick(fn)
	F.ticks[#F.ticks + 1] = fn
end

function F.trace(msg)
	if genv.AluzSpyTrace == true and type(appendfile) == "function" then
		pcall(appendfile, "AluzSpy/trace.log", string.format("%.2f %s\n", clock(), tostring(msg)))
	end
end

function F.on(kind, name, fn, prio)
	local list = OBS[kind]
	if not list then
		list = {}
		OBS[kind] = list
	end
	local o = { name = name, fn = fn, prio = prio or 50, on = true, err = 0 }
	local i = #list
	while i > 0 and list[i].prio > o.prio do i = i - 1 end
	table.insert(list, i + 1, o)
	return o
end

function F.budget()
	local fill = (qt - qh) / QCAP
	if fill > 0.5 then return 0.006 end
	if X.fps < 20 then return 0.0015 end
	return 0.0025
end

function F.register(name, info)
	local r = REG[name]
	if not r then
		r = { name = name, state = "loaded", err = 0 }
		REG[name] = r
	end
	if type(info) == "table" then
		for k, v in pairs(info) do r[k] = v end
	end
	return r
end

function F.modules()
	local out = {}
	for n, r in pairs(REG) do out[n] = { state = r.state, ver = r.ver, err = r.err, note = r.note } end
	local stages = {}
	for i = 1, #F.stages do stages[F.stages[i][1]] = F.stages[i].state or "pending" end
	local m = genv.AluzSpyManifest
	return { registry = out, stages = stages, manifest = type(m) == "table" and m or nil }
end

function F.apiMerge(t)
	F.api = F.api or {}
	for k, v in pairs(t) do F.api[k] = v end
end

function F.migrate()
	if CFG.ver == VERSION and (CFG.schema or 0) >= 4 then return nil end
	local prev = CFG.ver
	for k, v in pairs(F.defMods) do
		if CFG.mods[k] == nil then CFG.mods[k] = v end
	end
	if (CFG.schema or 0) < 4 then
		CFG.decode = true
		CFG.autoDeobf = true
		CFG.autoReverse = true
		CFG.net = true
		CFG.profile = CFG.profile or "max"
	end
	CFG.ver = VERSION
	CFG.schema = 4
	F.cfgSave()
	return prev
end

function D.admit(sc, p)
	if D.sd[sc] then return false end
	local cap = K.SCRIPT_CAP
	if p == 1 then cap = cap + K.SCRIPT_RESERVE end
	return D.sdn < cap
end

function D.push(sc, p)
	p = p or 2
	D.sd[sc] = true
	D.sdn = D.sdn + 1
	D.sqp[sc] = p
	local sq = D.sq
	local i = #sq
	while i > 0 and (D.sqp[sq[i]] or 2) > p do i = i - 1 end
	table.insert(sq, i + 1, sc)
end

function D.pop()
	return table.remove(D.sq, 1)
end

function F.tick(now)
	local dt = now - X.lastTick
	if dt < 0.5 then dt = 0.5 end
	X.dt = dt
	X.lastTick = now
	for i = 1, #F.ticks do
		local ok, err = pcall(F.ticks[i], now, dt)
		if not ok then noteErr(err) end
	end
	if X.flagUntil > 0 and now > X.flagUntil then
		FS.del(PATH.flag)
		X.flagUntil = 0
		local changed = false
		for k in pairs(CFG.crashes) do
			if not BAN.set[k] then
				CFG.crashes[k] = nil
				changed = true
			end
		end
		if changed then F.cfgSave() end
	end
	uiCount()
end

function F.stage(name, prio, fn)
	F.stages[#F.stages + 1] = { name, fn, prio }
end

function F.boot()
	touchFlag("boot", 10)
	table.sort(F.stages, function(a, b) return a[3] < b[3] end)
	for i = 1, #F.stages do
		local s = F.stages[i]
		local name = s[1]
		if not alive then return end
		if BAN.set[name] or CFG.mods[name] == false then
			MOD[name] = false
			s.state = "off"
		else
			touchFlag(name, 10)
			F.trace("stage " .. name .. " start")
			local ok, err = pcall(s[2])
			if not ok then
				s.state = "error"
				noteErr("boot_" .. name .. ":" .. tostring(err))
				warn("[AluzSpy] stage " .. name .. " failed: " .. tostring(err))
			else
				s.state = err == false and "unsupported" or "ok"
			end
			F.trace("stage " .. name .. " " .. s.state)
			task.wait(0.12)
		end
	end
end

function F.setMod(name, on)
	CFG.mods[name] = on and true or false
	if on then
		if IN[name] then
			local ok, res = pcall(IN[name])
			if not ok then noteErr(res) end
		end
	else
		MOD[name] = false
	end
	F.cfgSave()
	return MOD[name]
end
