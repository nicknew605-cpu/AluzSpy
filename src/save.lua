local okSV, errSV = xpcall(function()
	PATH.session = PATH.f("Session_" .. game.PlaceId .. "_" .. os.date("%Y%m%d_%H%M%S") .. ".txt")
	local INLINE_MAX = 30 * 1024 * 1024
	local CATS = {
		{ "loader", "1. LOADER CHAIN" }, { "ui", "2. UI LIBRARIES" }, { "feature", "3. FEATURE / PROTECTED SCRIPTS" },
		{ "game", "4. GAME SCRIPTS" }, { "bytecode", "5. BYTECODE" }, { "payload", "6. ENCRYPTED / RAW PAYLOADS" },
		{ "other", "7. OTHER" },
	}

	local function collectRecs()
		local out = {}
		local first = N.seq - K.LOGCAP + 1
		if first < 1 then first = 1 end
		for s = first, N.seq do
			local r = logs[(s - 1) % K.LOGCAP + 1]
			if r and r.i == s then out[#out + 1] = r end
		end
		return out
	end

	local function remList()
		local out = {}
		for _, reg in ipairs({ stC, stS }) do
			for _, st in pairs(reg) do
				out[#out + 1] = {
					d = st.dir, r = st.full, m = st.m, calls = st.n + st.supp, logged = st.logged,
					merged = st.merged, sampled = st.smp, suppressed = st.supp, mutes = st.mutes,
					peak = r2(st.peak), ret = st.ret or nil, muted = st.mu and true or nil,
				}
			end
		end
		table.sort(out, function(a, b) return a.calls > b.calls end)
		for i = #out, 101, -1 do out[i] = nil end
		return out
	end

	local function recOut(r)
		return {
			i = r.i, t = r.t, tl = r.tl, d = r.d, n = r.n, r = r.r, m = r.m, c = r.c,
			x = r.ex and true or nil, a = r.a, ret = r.ret, f = r.f, did = r.did, par = r.par,
			code = r.code, cf = r.sref and D.sdf[r.sref] or nil,
		}
	end

	function F.stats()
		return {
			total = N.total, logged = N.logged, merged = N.merged, sampled = N.sampled,
			suppressed = N.supp, bucketDropped = N.bucket, queueDropped = N.dropQ,
			errors = N.err, remotes = N.remotes, muted = #muteList, dumps = D.n,
			fps = floor(X.fps), mem = floor(X.memNow), load = X.load,
			hooks = {
				nc = INST.nc, fn = INST.fn, s2c = INST.s2c, cb = INST.cb, ni = INST.ni, sys = INST.sys,
				net = INST.net, http = INST.http, ls = INST.ls, rw = INST.rw, ws = INST.ws, req = INST.req,
				hx = INST.hx, ac = INST.ac,
			},
		}
	end

	function F.summaryLines()
		local L = {}
		L[#L + 1] = string.format("calls %d | logged %d | merged %d | suppressed %d | remotes %d | errors %d",
			N.total, N.logged, N.merged, N.supp, N.remotes, N.err)
		local cs, parts = F.catSummary and F.catSummary() or {}, {}
		for _, c in ipairs(CATS) do
			if cs[c[1]] then parts[#parts + 1] = c[1] .. " " .. cs[c[1]] end
		end
		L[#L + 1] = "dumps: " .. D.n .. " (" .. (#parts > 0 and table.concat(parts, ", ") or "none") .. "), skipped " .. D.skipped
		L[#L + 1] = "hooks: " .. (F.hookLine and F.hookLine() or "n/a")
		if F.deep and F.deep.hits > 0 then L[#L + 1] = "deep dump triggered " .. F.deep.hits .. "x: " .. table.concat(F.deep.why, ", ") end
		if X.recovered then L[#L + 1] = "previous session crashed at stage " .. tostring(X.recovered.stage) end
		local miss = F.missing and F.missing() or {}
		if #miss == 0 then
			L[#L + 1] = "missing payload: none detected"
		else
			L[#L + 1] = "missing payload / warnings:"
			for _, m in ipairs(miss) do L[#L + 1] = "  [" .. m.sev .. "] " .. m.rule .. ": " .. m.text end
			L[#L + 1] = "next steps:"
			for _, a in ipairs(F.advice and F.advice(miss) or {}) do L[#L + 1] = "  - " .. a end
		end
		return L
	end

	function F.report()
		local L = F.summaryLines()
		for i = 1, math.min(#L, 40) do warn("[AluzSpy] " .. L[i]) end
		return L
	end

	local function section(P, title)
		P[#P + 1] = "\n==================== " .. title .. " ===================="
	end

	local function addEntry(P, e, st)
		local h = { "----- [" .. tostring(e.id) .. "] " .. tostring(e.f), "tag=" .. tostring(e.tag), tostring(e.bytes) .. "b" }
		if e.url then h[#h + 1] = "url=" .. tostring(e.url):sub(1, 140) end
		if e.fp then h[#h + 1] = "obf=" .. e.fp.name .. "(" .. e.fp.conf .. "%)" end
		if e.parent then h[#h + 1] = "parent=" .. tostring(e.parent) end
		if e.pair then h[#h + 1] = "pair=" .. tostring(e.pair) end
		if e.variantOf then h[#h + 1] = "variant-of=" .. tostring(e.variantOf) end
		if e.seenBefore then h[#h + 1] = "seen-before(session " .. tostring(e.seenBefore) .. ")" end
		if e.changed then h[#h + 1] = "CHANGED-vs-previous" end
		if e.dup then
			P[#P + 1] = table.concat(h, " | ") .. " | duplicate of " .. tostring(e.dup)
			return
		end
		P[#P + 1] = table.concat(h, " | ") .. " -----"
		local body = e.f and D.store[e.f] or nil
		if body and not CFG.split and st.used + #body <= INLINE_MAX then
			st.used = st.used + #body
			if F.isBin and F.isBin(body) then
				P[#P + 1] = "[binary, base64]"
				P[#P + 1] = F.b64enc and F.b64enc(body) or "(encode failed)"
			else
				P[#P + 1] = body
			end
			local base = e.f:gsub("%.lua$", "")
			local dec = D.store[base .. ".dec.lua"]
			if dec and st.used + #dec <= INLINE_MAX then
				st.used = st.used + #dec
				P[#P + 1] = "----- decoded view -----"
				P[#P + 1] = dec
			end
			local sb = D.store[base .. ".sandbox.txt"]
			if sb and st.used + #sb <= INLINE_MAX then
				st.used = st.used + #sb
				P[#P + 1] = "----- sandbox report -----"
				P[#P + 1] = sb
			end
		elseif D.spilled[e.f or ""] or CFG.split then
			P[#P + 1] = "(stored separately: " .. PATH.d(e.f or "?") .. ")"
		elseif body then
			P[#P + 1] = "(omitted: size cap)"
		else
			P[#P + 1] = "(content not available)"
		end
		P[#P + 1] = "----- end [" .. tostring(e.id) .. "] -----"
	end

	local function importantRemotes(P, recs)
		local by = {}
		for _, r in ipairs(recs) do
			if r.d == "C2S" or r.d == "S2C" then
				local l = by[r.r]
				if not l then
					l = {}
					by[r.r] = l
				end
				if #l < 3 then
					l[#l + 1] = r
				else
					l[4] = r
				end
			end
		end
		local arr = {}
		for _, reg in ipairs({ stC, stS }) do
			for _, st in pairs(reg) do
				if st.logged > 0 and by[st.full] then
					local score = (st.ret and 5 or 0) + math.min(st.logged, 20) / 4 + (st.mutes == 0 and 2 or -2)
						+ (st.nshapeSeen and st.nshapeSeen >= 2 and 1 or 0) + (st.dir == "C2S" and 1 or 0)
					arr[#arr + 1] = { st = st, score = score }
				end
			end
		end
		table.sort(arr, function(a, b) return a.score > b.score end)
		for i = 1, math.min(#arr, 25) do
			local st = arr[i].st
			P[#P + 1] = string.format("[%s] %s calls=%d peak=%s/s%s%s", st.dir, st.full, st.n + st.supp, tostring(r2(st.peak)),
				st.ret and " returns" or "", st.mutes > 0 and " SPAM" or "")
			for _, r in ipairs(by[st.full]) do
				P[#P + 1] = string.format("   t=%s x%d (%s)%s", tostring(r.t), r.n, table.concat(r.a or {}, ", "), r.code and ("  " .. r.code) or "")
			end
		end
		local spam = F.spamList and F.spamList() or {}
		if #spam > 0 then
			P[#P + 1] = "spam classes (muted):"
			for i = 1, math.min(#spam, 15) do
				P[#P + 1] = string.format("   %s %s %s peak=%s/s suppressed=%d", spam[i].d, spam[i].r, spam[i].kind, tostring(spam[i].peak), spam[i].suppressed)
			end
		end
	end

	local function buildSession(reason)
		local recs = collectRecs()
		local exec = "unknown"
		pcall(function()
			if identifyexecutor then
				local n, v = identifyexecutor()
				exec = tostring(n) .. (v and (" " .. tostring(v)) or "")
			end
		end)
		local meta = {
			tool = "Aluz Spy", version = VERSION, executor = exec, place = game.PlaceId, job = game.JobId,
			exported = os.date("%Y-%m-%d %H:%M:%S"), reason = reason, session_file = PATH.session,
			uptime = r2(clock() - T0), safe_boot = BAN.safe, banned = BAN.list, recovered = X.recovered,
			capabilities = CAP, stats = F.stats(), categories = F.catSummary and F.catSummary() or nil,
			missing = F.missing and F.missing() or nil, health = F.extra.health and F.extra.health() or nil,
			ext = F.ext and F.ext() or nil, last_errors = errMap, split = CFG.split,
		}
		local P = {}
		P[#P + 1] = string.format("ALUZSPY SESSION  v%s  reason=%s  %s  place=%s  executor=%s", VERSION, tostring(reason), os.date("%Y-%m-%d %H:%M:%S"), tostring(game.PlaceId), exec)
		section(P, "SUMMARY")
		for _, l in ipairs(F.summaryLines()) do P[#P + 1] = l end
		section(P, "STAGE TRACKING (loading chain)")
		for _, l in ipairs(F.chainText and F.chainText() or {}) do P[#P + 1] = l end
		local st = { used = 0 }
		for _, c in ipairs(CATS) do
			local list = {}
			for _, e in ipairs(D.list) do
				if (e.cat or "other") == c[1] then list[#list + 1] = e end
			end
			if #list > 0 then
				section(P, c[2] .. " (" .. #list .. ")")
				for _, e in ipairs(list) do addEntry(P, e, st) end
			end
		end
		section(P, "8. IMPORTANT REMOTES")
		importantRemotes(P, recs)
		local diffs = {}
		for name in pairs(D.store) do
			if name:find("%.diff%.txt$") then diffs[#diffs + 1] = name end
		end
		table.sort(diffs)
		if #diffs > 0 then
			section(P, "9. CHANGES / DIFFS")
			for _, name in ipairs(diffs) do
				P[#P + 1] = "----- " .. name .. " -----"
				P[#P + 1] = D.store[name]
			end
		end
		section(P, "APPENDIX: META (json)")
		P[#P + 1] = F.enc(meta) or "{}"
		section(P, "APPENDIX: REMOTES (json)")
		P[#P + 1] = F.enc(remList()) or "[]"
		section(P, "APPENDIX: LOGS (json lines)")
		for _, r in ipairs(recs) do
			local js = F.enc(recOut(r))
			if js then P[#P + 1] = js end
		end
		return table.concat(P, "\n")
	end

	saveNow = function(reason)
		if not HAS_W then return false, "no writefile" end
		local manual = reason == "manual"
		if not manual then
			local now = clock()
			if now - X.lastAuto < 2.5 then return true, "skip" end
			X.lastAuto = now
		end
		local prev = busy
		busy = true
		local ok, res = pcall(function()
			F.process(0.05)
			D.flush()
			if not manual and not X.dirty then return "clean" end
			local body = buildSession(reason)
			writefile(PATH.session, body)
			if manual and type(setclipboard) == "function" and #body < 300000 then pcall(setclipboard, body) end
			if F.spoolReset then F.spoolReset() end
			X.dirty = false
			X.reason = reason
			return PATH.session
		end)
		busy = prev
		if ok then return true, res end
		noteErr(res)
		return false, tostring(res)
	end

	F.onTick(function(now)
		local okm, mb = pcall(function() return SV.Stats:GetTotalMemoryUsageMb() end)
		if okm and type(mb) == "number" then
			X.memNow = mb
			local mem = X.mem
			mem[#mem + 1] = mb
			if #mem > 10 then table.remove(mem, 1) end
			if (mb > K.MEM_ABS or mb - mem[1] > K.MEM_GROW) and now - X.lastMem > 30 then
				X.lastMem = now
				task.defer(saveNow, "memory")
			end
		end
		if X.stall then
			X.stall = false
			task.defer(saveNow, "stall")
		end
		if X.fps < 8 then X.lowN = X.lowN + 1 else X.lowN = 0 end
		if X.lowN >= 3 and now - X.lastFps > 30 then
			X.lastFps = now
			task.defer(saveNow, "fps")
		end
	end)

	if X.recovered then
		FS.write(PATH.crash, F.enc({
			version = VERSION, time = os.date("%Y-%m-%d %H:%M:%S"), place = game.PlaceId,
			stage = X.recovered.stage, age = X.recovered.age, banned = BAN.list, capabilities = CAP,
		}) or "")
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okSV then
	warn("[AluzSpy] save failed: " .. tostring(errSV))
end
