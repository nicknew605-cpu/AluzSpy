do local _ = "aluzspy@1.2.3-stable" if F and F.trace then F.trace("load save") end end
local okSV, errSV = xpcall(function()
	CAP.save = true
	F.register("save", { ver = "1.2.3-stable" })

	local CATS = {
		{ "loader", "LOADER CHAIN" },
		{ "ui", "UI LIBRARIES" },
		{ "feature", "FEATURE / PROTECTED SCRIPTS" },
		{ "game", "GAME SCRIPTS" },
		{ "bytecode", "BYTECODE" },
		{ "payload", "ENCRYPTED / RAW PAYLOADS" },
		{ "other", "OTHER" },
	}

	local function section(P, title)
		P[#P + 1] = ""
		P[#P + 1] = "===== " .. title .. " ====="
	end

	local function stamp()
		return os.date("%Y%m%d_%H%M%S") .. "_" .. string.format("%03d", floor((clock() % 1) * 1000))
	end

	local function dumpRecs()
		local recs = {}
		for i = 1, #(D.list or {}) do
			local e = D.list[i]
			if e then
				recs[#recs + 1] = {
					id = e.id or e.hash or i,
					cat = e.cat or "other",
					kind = e.kind or "other",
					tag = e.tag,
					url = e.url,
					bytes = e.bytes or (type(e.src) == "string" and #e.src) or 0,
					hash = e.hash or e.h,
					obf = e.obf,
					fp = e.fp,
					vm = e.vm,
					vmStrings = e.vmStrings,
					file = e.f or e.file,
					parent = e.parent,
					dup = e.dup,
					changed = e.changed,
					variantOf = e.variantOf,
					seenBefore = e.seenBefore,
				}
			end
		end
		return recs
	end

	local function spillStore()
		if type(D.forceSpill) == "function" then pcall(D.forceSpill, 80) end
		if D.q and D.h and D.t and type(D.writeOne) == "function" then
			local n = 0
			while D.h <= D.t and n < 200 do
				local ok = pcall(D.writeOne)
				if not ok then break end
				n = n + 1
			end
		end
	end

	local function collectLogs()
		local out = {}
		for s = N.seq, math.max(1, N.seq - K.LOGCAP + 1), -1 do
			local r = logs[(s - 1) % K.LOGCAP + 1]
			if r and r.i == s then
				out[#out + 1] = {
					i = r.i, t = r.t, d = r.d, r = r.r, m = r.m, n = r.n,
					a = r.a, code = r.code, ex = r.ex, c = r.c,
				}
				if #out >= K.LOGCAP then break end
			end
		end
		return out
	end

	local function moduleStates()
		local out = {}
		for i = 1, #F.stages do
			local s = F.stages[i]
			local st = s.state or "pending"
			local h = F.hooks and F.hooks[s[1]]
			out[s[1]] = {
				state = st,
				on = MOD[s[1]] == true,
				installed = h and h.installed or false,
				attempts = h and h.attempts or 0,
				err = h and h.lastErr or nil,
			}
		end
		return out
	end

	local function buildMeta(reason)
		local exec = "unknown"
		pcall(function()
			if identifyexecutor then
				local n, v = identifyexecutor()
				exec = tostring(n) .. (v and (" " .. tostring(v)) or "")
			end
		end)
		local stats = F.stats and F.stats() or {}
		return {
			tool = "Aluz Spy",
			version = VERSION or "1.2.3-stable",
			executor = exec,
			place = game.PlaceId,
			job = game.JobId,
			exported = os.date("%Y-%m-%d %H:%M:%S"),
			reason = reason or "manual",
			session_file = PATH.session,
			hooks_dir = PATH.hooksDir,
			dump_dir = PATH.dumpDir,
			uptime = r2(clock() - T0),
			safe_boot = BAN.safe,
			banned = BAN.list,
			recovered = X.recovered,
			capabilities = CAP,
			stats = stats,
			categories = F.catSummary and F.catSummary() or nil,
			missing = F.missing and F.missing() or nil,
			health = F.extra and F.extra.health and F.extra.health() or nil,
			modules = F.modules and F.modules() or nil,
			module_state = moduleStates(),
			vip = F.vipStatus and F.vipStatus() or nil,
			deobf = F.deobfReport and F.deobfReport() or nil,
			reverse = F.reverseSummary and F.reverseSummary() or nil,
			watch = F.extra and F.extra.watch and F.extra.watch() or nil,
			vm = F.extra and F.extra.vm and F.extra.vm() or nil,
			ext = F.ext and F.ext() or nil,
			last_errors = errMap,
			split = true,
			profile = CFG.profile,
			redact = CFG.redact == true,
			hooks = #logs,
			files = #D.files,
			budget = { total = K.DISK_TOTAL, kinds = K.DISK_KIND, used = D.kind, used_total = D.bytes or 0 },
		}
	end

	local function buildHooks(reason)
		spillStore()
		local meta = buildMeta(reason)
		local records = collectLogs()
		local P = {}
		P[#P + 1] = string.format(
			"ALUZSPY HOOKS  v%s  reason=%s  %s  place=%s  executor=%s",
			tostring(meta.version), tostring(reason), meta.exported, tostring(game.PlaceId), tostring(meta.executor)
		)
		section(P, "SUMMARY")
		for _, l in ipairs(F.summaryLines()) do P[#P + 1] = l end
		P[#P + 1] = "hooks " .. #records .. " | alerts " .. #(F.alerts or {}) .. " | dump files " .. #D.files
		section(P, "MODULE STATE")
		local ms = meta.module_state or {}
		local names = {}
		for k in pairs(ms) do names[#names + 1] = k end
		table.sort(names)
		for _, k in ipairs(names) do
			local v = ms[k]
			P[#P + 1] = string.format("%-6s state=%-10s on=%-5s installed=%-5s attempts=%s%s",
				k, tostring(v.state), tostring(v.on), tostring(v.installed), tostring(v.attempts),
				v.err and (" err=" .. tostring(v.err)) or "")
		end
		section(P, "STAGE TRACKING (loading chain)")
		if F.chainText then
			for _, l in ipairs(F.chainText()) do P[#P + 1] = l end
		else
			P[#P + 1] = "(chain module not loaded)"
		end
		section(P, "MISSING / ADVICE")
		local miss = meta.missing or {}
		if #miss == 0 then
			P[#P + 1] = "none"
		else
			for _, m in ipairs(miss) do
				P[#P + 1] = (m.sev or "?") .. " " .. (m.rule or "") .. ": " .. tostring(m.text)
			end
			if F.advice then
				P[#P + 1] = "next steps:"
				for _, a in ipairs(F.advice(miss) or {}) do P[#P + 1] = "  - " .. a end
			end
		end
		section(P, "ALERTS")
		if F.alerts and #F.alerts > 0 then
			for _, a in ipairs(F.alerts) do
				P[#P + 1] = string.format("t=%s %s -> %s", tostring(a.t), tostring(a.reason), tostring(a.url))
			end
		else
			P[#P + 1] = "none"
		end
		section(P, "HOOK / REMOTE CAPTURE")
		if #records == 0 then
			P[#P + 1] = "(no hook records yet)"
		else
			for i = 1, #records do
				local r = records[i]
				P[#P + 1] = string.format(
					"#%d t=%.2f %s %s.%s n=%s c=%s a=%s",
					r.i, r.t or 0, tostring(r.d), tostring(r.r), tostring(r.m),
					tostring(r.n), tostring(r.c or "-"), table.concat(r.a or {}, " | "):sub(1, 400)
				)
				if r.code then P[#P + 1] = "  code: " .. tostring(r.code):sub(1, 400) end
			end
		end
		section(P, "DUMPS")
		P[#P + 1] = string.format("dumps %d | bytes %s | files %d | pending %s | skipped %s | fail %s | evicted %s | dupes %s",
			#D.list, tostring(D.bytes or 0), #D.files, tostring(D.pending), tostring(D.skipped), tostring(D.fail), tostring(N.evict), tostring(N.dup))
		for _, c in ipairs(CATS) do
			local n = 0
			for _, e in ipairs(D.list or {}) do
				if (e.cat or "other") == c[1] then n = n + 1 end
			end
			if n > 0 then P[#P + 1] = "  " .. c[1] .. " " .. n end
		end
		local kinds = {}
		for k in pairs(D.kind or {}) do kinds[#kinds + 1] = k end
		table.sort(kinds)
		for _, k in ipairs(kinds) do
			P[#P + 1] = string.format("  kind %-10s %s bytes (quota %s)", k, tostring(D.kind[k]), tostring(K.DISK_KIND[k] or 0))
		end
		section(P, "VM / BYTECODE")
		local vm = meta.vm
		if vm then
			P[#P + 1] = string.format("runs %s ok %s fail %s strings %s captures %s protos %s instructions %s",
				tostring(vm.runs), tostring(vm.ok), tostring(vm.fail), tostring(vm.strings),
				tostring(vm.captures), tostring(vm.protos), tostring(vm.instructions))
		else
			P[#P + 1] = "(vm module not loaded)"
		end
		section(P, "REDACTION")
		local rs = F.redactStats and F.redactStats() or {}
		P[#P + 1] = string.format("on=%s ids=%s calls=%s bytes=%s chunks=%s",
			tostring(rs.on), tostring(rs.ids), tostring(rs.calls), tostring(rs.bytes), tostring(rs.chunks))
		section(P, "LAST ERRORS")
		local en = 0
		for k, v in pairs(errMap or {}) do
			en = en + 1
			P[#P + 1] = tostring(k) .. ": " .. tostring(v):sub(1, 300)
			if en >= 40 then break end
		end
		if en == 0 then P[#P + 1] = "none" end

		local json = {
			meta = meta,
			hooks = records,
			alerts = F.alerts or {},
			errors = errMap,
			categories = meta.categories,
			missing = meta.missing,
			modules = meta.modules,
			module_state = meta.module_state,
			health = meta.health,
			deobf = meta.deobf,
			reverse = meta.reverse,
			watch = meta.watch,
			vm = meta.vm,
			dumps = dumpRecs(),
		}
		return table.concat(P, "\n"), json
	end

	function F.summaryLines()
		local L = {}
		local s = F.stats and F.stats() or {}
		L[#L + 1] = string.format(
			"calls %d | logged %d | merged %d | suppressed %d | remotes %d | errors %d | drops %d",
			s.calls or N.total, s.logged or N.logged, s.merged or N.merged,
			s.supp or N.supp, s.remotes or N.remotes, s.errors or N.err, s.drops or N.dropQ
		)
		L[#L + 1] = string.format(
			"dumps %d | bytes %s | files %d | evicted %d | dupes %d | uptime %.1fs | profile %s",
			#D.list, tostring(D.bytes or 0), #D.files, N.evict, N.dup, clock() - T0, tostring(CFG.profile)
		)
		L[#L + 1] = string.format(
			"fps %s | mem %sMB | queue %s | tune %s | version %s",
			tostring(s.fps), tostring(s.mem), tostring(s.queue), tostring(X.tune and X.tune.level or 0), tostring(VERSION)
		)
		local cs = F.catSummary and F.catSummary() or {}
		local parts = {}
		for _, c in ipairs(CATS) do
			if cs[c[1]] then parts[#parts + 1] = c[1] .. "=" .. cs[c[1]] end
		end
		if #parts > 0 then L[#L + 1] = "cats: " .. table.concat(parts, " ") end
		if F.vipLine then L[#L + 1] = "vip: " .. F.vipLine() end
		if F.hookLine then L[#L + 1] = "hooks: " .. F.hookLine() end
		if F.extra and F.extra.vm then
			local vm = F.extra.vm()
			L[#L + 1] = string.format("vm: runs=%s ok=%s strings=%s captures=%s", tostring(vm.runs), tostring(vm.ok), tostring(vm.strings), tostring(vm.captures))
		end
		if F.extra and F.extra.watch then
			local ok, w = pcall(F.extra.watch)
			if ok and type(w) == "table" then
				L[#L + 1] = string.format("watch: alerts=%s schemas=%s property=%s chat=%s",
					tostring(w.alerts), tostring(w.schemas), tostring(w.property), tostring(w.chat))
			end
		end
		return L
	end

	function F.report()
		local L = F.summaryLines()
		for i = 1, math.min(#L, 40) do warn("[AluzSpy] " .. L[i]) end
		return L
	end

	saveNow = function(reason)
		reason = reason or "manual"
		if not HAS_W then return false, "no writefile" end
		local tag = stamp()
		PATH.session = PATH.h("Hooks_" .. game.PlaceId .. "_" .. tag .. ".json")
		PATH.sessionTxt = PATH.h("Hooks_" .. game.PlaceId .. "_" .. tag .. ".txt")
		local ok, packRes = pcall(function()
			local t, j = buildHooks(reason)
			return { t, j }
		end)
		if not ok then
			N.err = N.err + 1
			errMap["save"] = tostring(packRes)
			return false, tostring(packRes)
		end
		local body = packRes[1]
		local meta = packRes[2]
		local js = F.enc(meta) or "{}"
		if CFG.redact and F.redact then
			local red = F.redactChunked or F.redact
			local okr, r = pcall(red, js)
			if okr and type(r) == "string" then js = r end
			okr, r = pcall(red, body)
			if okr and type(r) == "string" then body = r end
		end
		local wroteJson = FS.write(PATH.session, js)
		local wroteTxt = FS.write(PATH.sessionTxt, body or "")
		local dumpPath, dumpN, dumpBytes = nil, 0, 0
		if type(D.writeFull) == "function" then
			local okf, p, n, b = pcall(D.writeFull, reason)
			if okf and type(p) == "string" then
				dumpPath, dumpN, dumpBytes = p, n or 0, b or 0
			end
		end
		if not dumpPath then
			local recs = dumpRecs()
			local name = "Index_" .. tostring(game.PlaceId) .. "_" .. tag .. ".json"
			local path = PATH.d(name)
			local idx = F.enc({ meta = { version = VERSION, place = game.PlaceId, exported = os.date("%Y-%m-%d %H:%M:%S"), reason = reason, scripts = #recs, bytes = D.bytes or 0 }, scripts = recs }) or "{}"
			if CFG.redact and F.redact then
				local red = F.redactChunked or F.redact
				local okr, r = pcall(red, idx)
				if okr and type(r) == "string" then idx = r end
			end
			if FS.write(path, idx) then dumpPath = path end
		end
		F.lastSave = {
			hooks = PATH.session, hooks_txt = PATH.sessionTxt, dump = dumpPath,
			hooks_ok = wroteJson or wroteTxt, dump_ok = dumpPath ~= nil,
			dump_scripts = dumpN, dump_bytes = dumpBytes,
		}
		if wroteJson or wroteTxt or dumpPath then
			if F.notify then
				local msg = PATH.session:match("[^/\\]+$") or PATH.session
				F.notify("Saved hooks " .. tostring(msg))
			end
			return true, dumpPath or PATH.session
		end
		return false, "write failed"
	end

	F.api = F.api or {}
	F.api.save = function()
		local ok, res = saveNow("manual")
		warn("[AluzSpy] save: " .. tostring(ok) .. " " .. tostring(res))
		local last = F.lastSave or {}
		warn("[AluzSpy] hooks: " .. tostring(last.hooks) .. " | dump: " .. tostring(last.dump))
		return ok, res
	end
	F.api.report = F.report
	F.api.paths = function()
		return {
			root = PATH.dir, hooks = PATH.hooksDir, dump = PATH.dumpDir,
			session = PATH.session, dump_index = D.indexPath,
		}
	end

	F.extra.save = function()
		local last = F.lastSave or {}
		return {
			session = PATH.session, hooks = last.hooks, dump = last.dump,
			hasWrite = HAS_W, dump_scripts = last.dump_scripts or 0,
		}
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okSV then
	warn("[AluzSpy] save module error: " .. tostring(errSV))
end
