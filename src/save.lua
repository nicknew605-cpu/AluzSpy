do local _ = "aluzspy@1.2.2-max" if F and F.trace then F.trace("load save") end end
local okSV, errSV = xpcall(function()
	CAP.save = true
	F.register("save", { ver = "1.2.2-max" })

	local CATS = {
		{ "loader", "1. LOADER CHAIN" },
		{ "ui", "2. UI LIBRARIES" },
		{ "feature", "3. FEATURE / PROTECTED SCRIPTS" },
		{ "game", "4. GAME SCRIPTS" },
		{ "bytecode", "5. BYTECODE" },
		{ "payload", "6. ENCRYPTED / RAW PAYLOADS" },
		{ "other", "7. OTHER" },
	}

	local function section(P, title)
		P[#P + 1] = ""
		P[#P + 1] = "===== " .. title .. " ====="
	end

	local function collectRecs()
		local recs = {}
		for i = 1, #(D.list or {}) do
			local e = D.list[i]
			if e then
				recs[#recs + 1] = {
					id = e.id or e.hash or i,
					cat = e.cat or "other",
					tag = e.tag,
					url = e.url,
					len = e.len or (type(e.src) == "string" and #e.src) or 0,
					hash = e.hash,
					obf = e.obf,
					file = e.file,
					parent = e.parent,
				}
			end
		end
		return recs
	end

	local function spillStore()
		if type(D.forceSpill) == "function" then
			pcall(D.forceSpill, 40)
		end
		if D.q and D.h and D.t then
			while D.h <= D.t do
				local job = D.q[D.h]
				D.h = D.h + 1
				if job and job.f and job.s and HAS_W then
					pcall(writefile, PATH.d(job.f), job.s)
				end
			end
		end
	end

	local function buildSession(reason)
		spillStore()
		local recs = collectRecs()
		local exec = "unknown"
		pcall(function()
			if identifyexecutor then
				local n, v = identifyexecutor()
				exec = tostring(n) .. (v and (" " .. tostring(v)) or "")
			end
		end)

		local meta = {
			tool = "Aluz Spy",
			version = VERSION or "1.2.2-max",
			executor = exec,
			place = game.PlaceId,
			job = game.JobId,
			exported = os.date("%Y-%m-%d %H:%M:%S"),
			reason = reason or "manual",
			session_file = PATH.session,
			uptime = r2(clock() - T0),
			safe_boot = BAN.safe,
			banned = BAN.list,
			recovered = X.recovered,
			capabilities = CAP,
			stats = F.stats and F.stats() or {
				dumps = #D.list, bytes = D.bytes or 0,
				calls = N.total, logged = N.logged, merged = N.merged,
				supp = N.supp, remotes = N.remotes, errors = N.err,
			},
			categories = F.catSummary and F.catSummary() or nil,
			missing = F.missing and F.missing() or nil,
			health = F.extra and F.extra.health and F.extra.health() or nil,
			modules = F.modules and F.modules() or nil,
			vip = F.vipStatus and F.vipStatus() or nil,
			deobf = F.deobfReport and F.deobfReport() or nil,
			reverse = F.reverseSummary and F.reverseSummary() or nil,
			ext = F.ext and F.ext() or nil,
			last_errors = errMap,
			split = CFG.split,
			profile = CFG.profile,
		}

		local P = {}
		P[#P + 1] = string.format(
			"ALUZSPY SESSION  v%s  reason=%s  %s  place=%s  executor=%s",
			tostring(meta.version), tostring(reason), meta.exported, tostring(game.PlaceId), exec
		)
		section(P, "SUMMARY")
		if F.summaryLines then
			for _, l in ipairs(F.summaryLines()) do P[#P + 1] = l end
		else
			local s = meta.stats
			P[#P + 1] = string.format(
				"dumps %d | bytes %d | calls %d | logged %d | merged %d | supp %d | remotes %d | err %d",
				s.dumps or 0, s.bytes or 0, s.calls or 0, s.logged or 0,
				s.merged or 0, s.supp or 0, s.remotes or 0, s.errors or 0
			)
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
				for _, a in ipairs(F.advice(miss) or {}) do
					P[#P + 1] = "  - " .. a
				end
			end
		end

		section(P, "MODULES")
		if meta.modules then
			local js = F.enc(meta.modules)
			P[#P + 1] = js and js:sub(1, 4000) or tostring(meta.modules)
		end

		section(P, "DUMP INDEX")
		for _, c in ipairs(CATS) do
			local list = {}
			for _, e in ipairs(recs) do
				if (e.cat or "other") == c[1] then list[#list + 1] = e end
			end
			if #list > 0 then
				P[#P + 1] = ""
				P[#P + 1] = c[2] .. " (" .. #list .. ")"
				for i = 1, math.min(#list, 80) do
					local e = list[i]
					P[#P + 1] = string.format(
						"  [%s] %s  len=%s  tag=%s  url=%s",
						tostring(e.id):sub(1, 12),
						tostring(e.hash or ""):sub(1, 16),
						tostring(e.len),
						tostring(e.tag or ""),
						tostring(e.url or ""):sub(1, 80)
					)
				end
				if #list > 80 then
					P[#P + 1] = "  ... +" .. (#list - 80) .. " more"
				end
			end
		end

		section(P, "REMOTE LOG TAIL")
		local shown = 0
		for s = N.seq, math.max(1, N.seq - 60), -1 do
			local r = logs[(s - 1) % K.LOGCAP + 1]
			if r and r.i == s then
				shown = shown + 1
				P[#P + 1] = string.format(
					"#%d %s %s.%s n=%s a=%s",
					r.i, tostring(r.d), tostring(r.r), tostring(r.m),
					tostring(r.n), table.concat(r.a or {}, " | "):sub(1, 200)
				)
			end
		end
		if shown == 0 then P[#P + 1] = "(no remote logs yet)" end

		local sessionJson = {
			meta = meta,
			dumps = recs,
			logs_tail = {},
		}
		for s = N.seq, math.max(1, N.seq - 120), -1 do
			local r = logs[(s - 1) % K.LOGCAP + 1]
			if r and r.i == s then
				sessionJson.logs_tail[#sessionJson.logs_tail + 1] = {
					i = r.i, t = r.t, d = r.d, r = r.r, m = r.m, n = r.n, a = r.a, code = r.code,
				}
			end
		end

		return table.concat(P, "\n"), sessionJson
	end

	function F.summaryLines()
		local L = {}
		local s = F.stats and F.stats() or {}
		L[#L + 1] = string.format(
			"calls %d | logged %d | merged %d | suppressed %d | remotes %d | errors %d",
			s.calls or N.total, s.logged or N.logged, s.merged or N.merged,
			s.supp or N.supp, s.remotes or N.remotes, s.errors or N.err
		)
		L[#L + 1] = string.format(
			"dumps %d | bytes %s | uptime %.1fs | profile %s",
			#D.list, tostring(D.bytes or 0), clock() - T0, tostring(CFG.profile)
		)
		local cs = F.catSummary and F.catSummary() or {}
		local parts = {}
		for _, c in ipairs(CATS) do
			if cs[c[1]] then parts[#parts + 1] = c[1] .. "=" .. cs[c[1]] end
		end
		if #parts > 0 then L[#L + 1] = "cats: " .. table.concat(parts, " ") end
		if F.vipLine then L[#L + 1] = "vip: " .. F.vipLine() end
		if F.hookLine then L[#L + 1] = "hooks: " .. F.hookLine() end
		return L
	end

	function F.report()
		local L = F.summaryLines()
		for i = 1, math.min(#L, 40) do
			warn("[AluzSpy] " .. L[i])
		end
		return L
	end

	saveNow = function(reason)
		reason = reason or "manual"
		if not HAS_W then
			return false, "no writefile"
		end
		local ok, packRes = pcall(function()
			local t, j = buildSession(reason)
			return { t, j }
		end)
		if not ok then
			N.err = N.err + 1
			errMap["save"] = tostring(packRes)
			return false, tostring(packRes)
		end
		local body = packRes[1]
		local meta = packRes[2]

		PATH.session = PATH.f("Save_" .. game.PlaceId .. "_" .. os.date("%Y%m%d_%H%M%S") .. ".json")
		local txtPath = PATH.session:gsub("%.json$", ".txt")

		local js = F.enc(meta)
		if CFG.redact and F.redact and type(js) == "string" then
			local okr, r = pcall(F.redact, js)
			if okr and type(r) == "string" then js = r end
		end

		local wroteJson = js and FS.write(PATH.session, js)
		local wroteTxt = FS.write(txtPath, body or "")

		local fullPath = nil
		if type(D.writeFull) == "function" then
			local okf, p = pcall(D.writeFull, reason)
			if okf and type(p) == "string" then fullPath = p end
		end

		if wroteJson or wroteTxt or fullPath then
			if F.notify then
				local msg = fullPath or PATH.session
				F.notify("Saved " .. (tostring(msg):match("[^/\\]+$") or tostring(msg)))
			end
			return true, fullPath or PATH.session
		end
		return false, "write failed"
	end

	F.api = F.api or {}
	F.api.save = function()
		local ok, res = saveNow("manual")
		warn("[AluzSpy] save: " .. tostring(ok) .. " " .. tostring(res))
		return ok, res
	end
	F.api.report = F.report

	F.extra.save = function()
		return { session = PATH.session, hasWrite = HAS_W }
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okSV then
	warn("[AluzSpy] save module error: " .. tostring(errSV))
end
