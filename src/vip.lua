do local _ = "aluzspy@1.2.2-beta" if F and F.trace then F.trace("load vip") end end
local okVP, errVP = xpcall(function()
	CAP.vip = true
	F.register("vip", { ver = "1.2.2-beta" })

	local RISK = { "net", "http", "ls", "cb", "ni", "rw", "ws", "req", "hx", "ac", "sd", "ps", "tc" }
	local ALL = { "fn", "s2c", "sys", "net", "http", "ls", "cb", "ni", "rw", "ws", "req", "hx", "ac", "hc", "sd", "ps", "tc" }

	local function modset(on, off)
		local t = {}
		for _, k in ipairs(ALL) do t[k] = on end
		for _, k in ipairs(off or {}) do t[k] = not on end
		return t
	end

	local PROFILES = {
		lite = {
			mods = modset(false, { "fn", "hc" }),
			cfg = { decode = false, sandbox = false, net = false, autoDeobf = false, autoReverse = false, autoScripts = false, callerDump = false, code = false, tree = false },
		},
		standard = {
			mods = modset(true, { "ps", "tc" }),
			cfg = { decode = false, sandbox = false, net = false, autoDeobf = false, autoReverse = false, autoScripts = false, callerDump = true, code = true, tree = true },
		},
		max = {
			mods = modset(true, { "ps", "tc" }),
			cfg = { decode = true, sandbox = false, net = true, autoDeobf = true, autoReverse = true, autoScripts = true, callerDump = true, code = true, tree = true, dumpSpill = true, deob = true },
		},
		safe = {
			mods = (function()
				local t = modset(false, { "fn", "s2c", "hc" })
				for _, k in ipairs(RISK) do t[k] = false end
				return t
			end)(),
			cfg = { decode = false, sandbox = false, net = false, autoDeobf = false, autoReverse = false, autoScripts = false, callerDump = false },
		},
	}

	local V = { scanning = false, lastScan = nil, lastReport = nil, redacted = {}, busyRedact = false }

	local function note(t)
		if F.notify then F.notify(t) end
		warn("[AluzSpy] " .. tostring(t))
	end

	local function apply(name)
		local p = PROFILES[name]
		if not p then return false, "unknown profile" end
		for k, v in pairs(p.cfg) do CFG[k] = v end
		S.dump = CFG.dump
		for _, k in ipairs(ALL) do
			local want = p.mods[k]
			if want ~= nil and not BAN.set[k] then
				if want then
					if CFG.mods[k] == false or not MOD[k] then F.setMod(k, true) end
				elseif CFG.mods[k] ~= false or MOD[k] then
					F.setMod(k, false)
				end
			end
		end
		CFG.profile = name
		F.cfgSave()
		return true
	end

	function F.vipOn()
		return CFG.profile == "max"
	end

	function F.vipLine()
		local on, total = 0, #ALL
		for _, k in ipairs(ALL) do
			if MOD[k] then on = on + 1 end
		end
		return string.format("%s %d/%d", tostring(CFG.profile), on, total)
	end

	function F.vipStatus()
		local mods = {}
		for _, k in ipairs(ALL) do
			mods[k] = BAN.set[k] and "banned" or (MOD[k] and "on" or "off")
		end
		return {
			profile = CFG.profile, modules = mods, line = F.vipLine(), warnings = F.warnN or 0,
			deobf = F.deobfReport and { runs = F.deobfReport().runs, auto = CFG.autoDeobf == true } or nil,
			reverse = F.reverseSummary and F.reverseSummary() and { scans = F.reverseSummary().scans, auto = CFG.autoReverse == true } or nil,
			redaction = F.redactStats and F.redactStats() or { on = false },
			scanning = V.scanning, last_scan = V.lastScan, last_report = V.lastReport, safe_boot = BAN.safe,
		}
	end

	local function scan()
		if V.scanning then return "running" end
		V.scanning = true
		task.spawn(function()
			S.dump = true
			CFG.dump = true
			local n = F.scanScripts and F.scanScripts() or 0
			note("vip scan: " .. n .. " scripts queued")
			local t0 = clock()
			while alive and (D.running or #D.sq > 0) and clock() - t0 < 90 do task.wait(1) end
			if F.api.decodeAll then pcall(F.api.decodeAll) end
			if F.api.deobfAll then pcall(F.api.deobfAll) end
			task.wait(3)
			if F.api.reverse then pcall(F.api.reverse) end
			V.scanning = false
			V.lastScan = os.time()
			note("vip scan: finished")
		end)
		return "started"
	end

	local function report()
		local ok, res = false, nil
		if saveNow then ok, res = saveNow("manual") end
		local summary = {
			tool = "Aluz Spy", version = VERSION, exported = os.date("%Y-%m-%d %H:%M:%S"), place = game.PlaceId,
			status = F.vipStatus(), modules = F.modules and F.modules() or nil,
			deobf = F.deobfReport and F.deobfReport() or nil, reverse = F.reverseSummary and F.reverseSummary() or nil,
			dumpfail = F.extra.dumpfail and F.extra.dumpfail() or nil, health = F.extra.health and F.extra.health() or nil,
		}
		local js = F.enc(summary)
		if js then
			if CFG.redact and F.redact then
				local okr, r = pcall(F.redact, js)
				if okr and type(r) == "string" then js = r end
			end
			local f = "vip_" .. os.date("%H%M%S") .. ".json"
			D.pending = D.pending + #js
			D.t = D.t + 1
			D.q[D.t] = { f = f, s = js }
			V.lastReport = f
		end
		note("vip report: session " .. tostring(PATH.session))
		return { saved = ok, session = PATH.session, summary = V.lastReport }
	end

	local function redactFile(path)
		if type(isfile) ~= "function" or not isfile(path) then return false end
		local okr, body = pcall(readfile, path)
		if not okr or type(body) ~= "string" then return false end
		if #body > 25000000 then return false end
		local parts, buf, size = {}, {}, 0
		for line in body:gmatch("[^\n]*\n?") do
			if line ~= "" then
				buf[#buf + 1] = line
				size = size + #line
				if size >= 262144 then
					parts[#parts + 1] = F.redact(table.concat(buf))
					buf, size = {}, 0
					F.Y()
				end
			end
		end
		if #buf > 0 then parts[#parts + 1] = F.redact(table.concat(buf)) end
		local out = path:gsub("(%.[%w]+)$", ".redacted%1")
		if out == path then out = path .. ".redacted" end
		return pcall(writefile, out, table.concat(parts)) and out or false
	end

	local function redact()
		if not F.redact then
			warn("[AluzSpy] redact: watch module missing")
			return nil
		end
		if V.busyRedact then return "running" end
		local files = {}
		if PATH.session then files[#files + 1] = PATH.session end
		if D.n > 0 and PATH.dumpfile then files[#files + 1] = PATH.dumpfile end
		local ok = F.job("redact", function()
			local done = {}
			for _, p in ipairs(files) do
				local o = redactFile(p)
				if o then done[#done + 1] = o end
			end
			return done
		end, function(done)
			V.busyRedact = false
			V.redacted = done or {}
			note("vip redact: " .. #V.redacted .. " file(s) written")
		end, { prio = 3, timeout = 120 })
		if not ok then return nil end
		V.busyRedact = true
		return "queued"
	end

	F.apiMerge({
		vip = function(cmd, arg)
			if cmd == nil or cmd == "status" then
				local s = F.vipStatus()
				warn("[AluzSpy] vip " .. s.line .. (s.scanning and " scanning" or ""))
				return s
			end
			if cmd == "profile" then
				if arg == nil then
					local names = {}
					for k in pairs(PROFILES) do names[#names + 1] = k end
					table.sort(names)
					return names
				end
				local ok, why = apply(tostring(arg))
				if ok then note("vip profile: " .. tostring(arg)) else warn("[AluzSpy] vip: " .. tostring(why)) end
				return ok
			end
			if cmd == "scan" then return scan() end
			if cmd == "report" then return report() end
			if cmd == "redact" then return redact() end
			if cmd == "safe" then
				local ok = apply("safe")
				note("vip safe mode")
				return ok
			end
			warn("[AluzSpy] vip commands: status, profile, scan, report, redact, safe")
			return nil
		end,
	})

	F.extra.vip = function()
		return { profile = CFG.profile, line = F.vipLine() }
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okVP then
	warn("[AluzSpy] vip failed: " .. tostring(errVP))
end
