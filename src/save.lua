do local _ = "aluzspy@1.2.1-max" end
local okSV, errSV = xpcall(function()
	D.store = D.store or {}
	D.spilled = D.spilled or {}
	D.diffs = D.diffs or {}
	local stamp = os.date("%Y%m%d_%H%M%S")
	PATH.session = PATH.f("Session_" .. game.PlaceId .. "_" .. stamp .. ".json")
	PATH.dumpfile = PATH.f("Dump_" .. game.PlaceId .. "_" .. stamp .. ".lua")

	local CATS = {
		{ "loader", "LOADER CHAIN" }, { "ui", "UI LIBRARIES" }, { "feature", "FEATURE / PROTECTED SCRIPTS" },
		{ "game", "GAME SCRIPTS" }, { "other", "OTHER" }, { "bytecode", "BYTECODE" },
		{ "payload", "RAW / ENCRYPTED PAYLOADS" },
	}
	local RANK = {}
	for i, c in ipairs(CATS) do RANK[c[1]] = i end

	local function plain(x)
		return (tostring(x):gsub("%c", " "))
	end

	local function murl(u)
		if not u then return nil end
		if F.maskUrl then return F.maskUrl(tostring(u)) end
		return tostring(u)
	end

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
					schema = F.schemaStr and F.schemaStr(st.dir, st.full) or nil,
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
				hx = INST.hx, ac = INST.ac, ps = INST.ps, tc = INST.tc,
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
		if F.alerts and #F.alerts > 0 then
			L[#L + 1] = "ALERTS:"
			for i = 1, math.min(#F.alerts, 10) do
				L[#L + 1] = "  " .. F.alerts[i].reason .. " -> " .. tostring(F.alerts[i].url):sub(1, 90)
			end
		end
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

	local function computeActions(recs)
		local groups, cur, lastT = {}, {}, nil
		for _, r in ipairs(recs) do
			if r.d == "C2S" then
				if lastT and r.t - lastT > 0.4 and #cur > 0 then
					groups[#groups + 1] = cur
					cur = {}
				end
				cur[#cur + 1] = tostring(r.r):match("([^%.]+)$") or tostring(r.r)
				lastT = r.t
			end
		end
		if #cur > 0 then groups[#groups + 1] = cur end
		local counts = {}
		for _, g in ipairs(groups) do
			local seq = {}
			for i = 1, math.min(#g, 4) do seq[i] = g[i] end
			local key = table.concat(seq, " > ")
			counts[key] = (counts[key] or 0) + 1
		end
		local arr = {}
		for k, v in pairs(counts) do arr[#arr + 1] = { seq = k, n = v } end
		table.sort(arr, function(a, b) return a.n > b.n end)
		for i = #arr, 26, -1 do arr[i] = nil end
		return arr
	end

	local function importantRemotes(recs)
		local by = {}
		for _, r in ipairs(recs) do
			if r.d == "C2S" or r.d == "S2C" then
				local l = by[r.r]
				if not l then
					l = {}
					by[r.r] = l
				end
				if #l < 3 then l[#l + 1] = { t = r.t, n = r.n, a = r.a, code = r.code } end
			end
		end
		local arr = {}
		for _, reg in ipairs({ stC, stS }) do
			for _, st in pairs(reg) do
				if st.logged > 0 and by[st.full] then
					local score = (st.ret and 5 or 0) + math.min(st.logged, 20) / 4 + (st.mutes == 0 and 2 or -2)
						+ (st.nshapeSeen and st.nshapeSeen >= 2 and 1 or 0) + (st.dir == "C2S" and 1 or 0)
					arr[#arr + 1] = {
						score = score, r = st.full, d = st.dir, calls = st.n + st.supp, peak = r2(st.peak),
						ret = st.ret or nil, spam = st.mutes > 0 or nil, samples = by[st.full],
					}
				end
			end
		end
		table.sort(arr, function(a, b) return a.score > b.score end)
		for i = #arr, 26, -1 do arr[i] = nil end
		return arr
	end

	local function dumpIndex()
		local out = {}
		for i = 1, math.min(#D.list, 400) do
			local e = D.list[i]
			out[#out + 1] = {
				id = e.id, f = e.f, cat = e.cat, tag = e.tag, bytes = e.bytes, url = murl(e.url),
				obf = e.fp and e.fp.name or nil, conf = e.fp and e.fp.conf or nil, parent = e.parent, pair = e.pair,
				variant_of = e.variantOf, seen_before = e.seenBefore, changed = e.changed, dup = e.dup,
			}
		end
		return out
	end

	local function buildJSON(reason)
		local recs = collectRecs()
		local exec = "unknown"
		pcall(function()
			if identifyexecutor then
				local n, v = identifyexecutor()
				exec = tostring(n) .. (v and (" " .. tostring(v)) or "")
			end
		end)
		local meta = {
			tool = "Aluz Spy", version = VERSION, schema = 6, executor = exec, place = game.PlaceId, job = game.JobId,
			exported = os.date("%Y-%m-%d %H:%M:%S"), reason = reason, session_file = PATH.session,
			dump_file = (D.n > 0) and PATH.dumpfile or nil, uptime = r2(clock() - T0), safe_boot = BAN.safe,
			banned = BAN.list, recovered = X.recovered, capabilities = CAP, stats = F.stats(),
			categories = F.catSummary and F.catSummary() or nil, health = F.extra.health and F.extra.health() or nil,
			ext = F.ext and F.ext() or nil, last_errors = errMap,
			redaction = F.redactStats and F.redactStats() or { on = false },
		}
		local chain = F.chainText and F.chainText() or {}
		for i = #chain, 201, -1 do chain[i] = nil end
		for i = 1, #chain do chain[i] = murl(chain[i]) end
		local head = '{"schema":6,"meta":' .. (F.enc(meta) or "{}")
			.. ',"summary":' .. (F.enc(F.summaryLines()) or "[]")
			.. ',"alerts":' .. (F.enc(F.alerts or {}) or "[]")
			.. ',"missing":' .. (F.enc(F.missing and F.missing() or {}) or "[]")
			.. ',"chain":' .. (F.enc(chain) or "[]")
			.. ',"dumps":' .. (F.enc(dumpIndex()) or "[]")
			.. ',"changes":' .. (F.enc(D.diffs) or "[]")
			.. ',"actions":' .. (F.enc(computeActions(recs)) or "[]")
			.. ',"important":' .. (F.enc(importantRemotes(recs)) or "[]")
			.. ',"spam":' .. (F.enc(F.spamList and F.spamList() or {}) or "[]")
			.. ',"modules":' .. (F.enc(F.modules and F.modules() or {}) or "{}")
			.. ',"deobf":' .. (F.enc(F.deobfReport and F.deobfReport() or {}) or "{}")
			.. ',"reverse":' .. (F.enc(F.reverseSummary and F.reverseSummary() or {}) or "{}")
			.. ',"vip":' .. (F.enc(F.vipStatus and F.vipStatus() or {}) or "{}")
			.. ',"dumpfail":' .. (F.enc(F.extra.dumpfail and F.extra.dumpfail() or {}) or "{}")
			.. ',"remotes":' .. (F.enc(remList()) or "[]") .. ',"logs":['
		local lines = {}
		for i = 1, #recs do
			local js = F.enc(recOut(recs[i]))
			if js then lines[#lines + 1] = js end
		end
		local out = head .. "\n" .. table.concat(lines, ",\n") .. "\n]}"
		if CFG.redact and F.redact then
			local okr, res = pcall(F.redact, out)
			if okr and type(res) == "string" then out = res end
		end
		return out
	end

	local function writeDump()
		local entries = {}
		for _, e in ipairs(D.list) do
			if not e.dup and e.f and (D.store[e.f] or D.spilled[e.f]) then entries[#entries + 1] = e end
		end
		if #entries == 0 then return false end
		table.sort(entries, function(a, b)
			local ra, rb = RANK[a.cat or "other"] or 5, RANK[b.cat or "other"] or 5
			if ra ~= rb then return ra < rb end
			return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
		end)
		local exec = "unknown"
		pcall(function()
			if identifyexecutor then exec = tostring((identifyexecutor())) end
		end)
		local useAppend = type(appendfile) == "function"
		local chunks, size, first, okAll = {}, 0, true, true
		local function flush()
			if #chunks == 0 then return end
			local data = table.concat(chunks, "\n") .. "\n"
			chunks, size = {}, 0
			if first then
				first = false
				if not pcall(writefile, PATH.dumpfile, data) then okAll = false end
			elseif not pcall(appendfile, PATH.dumpfile, data) then
				okAll = false
			end
		end
		local function push(s)
			chunks[#chunks + 1] = s
			size = size + #s
			if useAppend and size >= 262144 then flush() end
		end
		push(string.format("-- AluzSpy dump | place %s | %s | %d scripts | %s", tostring(game.PlaceId), os.date("%Y-%m-%d %H:%M:%S"), #entries, exec))
		push("-- sources only. Not a runnable file: every script starts at its '-- =====' line.")
		push("-- index:")
		for _, e in ipairs(entries) do
			push(string.format("--   [%s] %s | %s | %db | %s%s", tostring(e.id), e.cat or "other", plain(e.tag), e.bytes or 0,
				e.fp and (e.fp.name .. " ") or "", e.url and plain(murl(e.url)):sub(1, 110) or ""))
		end
		local chain = F.chainText and F.chainText() or {}
		if #chain > 0 then
			push("-- loading chain:")
			for i = 1, math.min(#chain, 50) do push("--   " .. plain(murl(chain[i]))) end
		end
		for _, e in ipairs(entries) do
			local body = D.store[e.f]
			if not body and D.spilled[e.f] then body = FS.read(PATH.d(e.f)) end
			local h = { string.format("-- ===== [%s] %s | %s | %db", tostring(e.id), e.cat or "other", plain(e.tag), e.bytes or 0) }
			if e.url then h[#h + 1] = "url=" .. plain(murl(e.url)):sub(1, 140) end
			if e.fp then h[#h + 1] = "obf=" .. e.fp.name .. "(" .. e.fp.conf .. "%)" end
			if e.parent then h[#h + 1] = "parent=" .. tostring(e.parent) end
			if e.pair then h[#h + 1] = "pair=" .. tostring(e.pair) end
			if e.variantOf then h[#h + 1] = "variant-of=" .. tostring(e.variantOf) end
			if e.changed then h[#h + 1] = "CHANGED" end
			push(table.concat(h, " | ") .. " =====")
			if not body then
				push("-- (content unavailable)")
			elseif (F.isBin and F.isBin(body)) or e.cat == "bytecode" then
				if #body <= 262144 and F.b64enc then
					push("--[==[BASE64")
					push(F.b64enc(body))
					push("]==]")
				else
					push("-- (binary " .. #body .. "b omitted)")
				end
			else
				push(body)
			end
		end
		if useAppend then
			flush()
		else
			local ok = pcall(writefile, PATH.dumpfile, table.concat(chunks, "\n") .. "\n")
			okAll = ok
		end
		return okAll
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
			local wrote = false
			if (manual or D.dirtyDump) and D.n > 0 then
				wrote = writeDump()
				if wrote then
					D.dirtyDump = false
					if F.spoolReset then F.spoolReset() end
				end
			end
			if not manual and not X.dirty and not wrote then return "clean" end
			local body = buildJSON(reason)
			writefile(PATH.session, body)
			if manual and type(setclipboard) == "function" and #body < 1500000 then pcall(setclipboard, body) end
			if wrote and manual and F.notify then F.notify("Dump: " .. (PATH.dumpfile:match("[^/]+$") or "ok")) end
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
