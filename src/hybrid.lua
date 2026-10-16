do local _ = "aluzspy@1.2.1-max" if F and F.trace then F.trace("load hybrid") end end
local okHY, errHY = xpcall(function()
	if not (F.job and F.fingerprint) then return end

	local baseDC = F.decodeCore
	if baseDC then
		F.decodeCore = function(src)
			local text, rep, stats = baseDC(src)
			if type(rep) == "table" then
				local fp = F.fingerprint(src)
				local extra, why = 0, {}
				if fp.m.vm then
					extra = extra + 20
					why[#why + 1] = "heavy VM"
				end
				if fp.m.enc then
					extra = extra + 10
					why[#why + 1] = "constant encryption"
				end
				if fp.m.anti then
					extra = extra + 10
					why[#why + 1] = "anti-tamper checks"
				end
				if fp.m.cff then
					extra = extra + 10
					why[#why + 1] = "control-flow flattening"
				end
				if fp.name then
					extra = extra + 15
					why[#why + 1] = fp.name .. " (" .. fp.conf .. "%)"
				end
				if extra > 0 then
					local score = math.min(100, (rep.risk or 0) + extra)
					rep.risk = score
					rep.flags = rep.flags or {}
					for i = #rep.flags, 1, -1 do
						if rep.flags[i]:find("^risk score") then table.remove(rep.flags, i) end
					end
					table.insert(rep.flags, 1, string.format("risk score %d/100 (%s) - %s",
						score, score >= 60 and "high" or (score >= 30 and "medium" or "low"), table.concat(why, ", ")))
				end
			end
			return text, rep, stats
		end
	end

	local pairMode = setmetatable({}, weak)

	local function tryDecompile(s, timeout)
		local res
		task.spawn(function()
			local ok, r = pcall(decompile, s)
			res = { ok = ok, r = r }
		end)
		local t0 = clock()
		while not res and clock() - t0 < timeout do task.wait(0.15) end
		return res
	end

	local function badText(src)
		if type(src) ~= "string" then return true end
		local head = src:sub(1, 400):lower()
		return head:find("failed to decompile", 1, true) ~= nil or head:find("decompilation failed", 1, true) ~= nil
			or head:find("not supported", 1, true) ~= nil or head:find("decompiler error", 1, true) ~= nil
	end

	D.queueScript = function(sc, prio)
		if not S.dump or not D.admit(sc, prio) then return end
		if not CAP.decompile and not CAP.getscriptbytecode then return end
		D.push(sc, prio)
		if D.running then return end
		D.running = true
		task.spawn(function()
			while alive and #D.sq > 0 do
				local s = D.pop()
				local okn, nm = pcall(function() return s.Name end)
				local okf, full = pcall(s.GetFullName, s)
				full = okf and full or nil
				local name = (okn and tostring(nm) or "x"):gsub("[^%w]", "")
				local res = CAP.decompile and tryDecompile(s, 25) or nil
				local okb, bc = false, nil
				if CAP.getscriptbytecode then okb, bc = pcall(getscriptbytecode, s) end
				local srcText = (res and res.ok and type(res.r) == "string" and #res.r >= 40 and not badText(res.r)) and res.r or nil
				local bcOk = okb and type(bc) == "string" and #bc >= 16 and #bc <= 2097152
				if not srcText then
					local reason
					if not CAP.decompile then
						reason = "no_decompile_api"
					elseif not res then
						reason = "timeout"
					elseif not res.ok then
						reason = "error"
					elseif type(res.r) ~= "string" or #res.r < 40 then
						reason = "empty"
					elseif badText(res.r) then
						reason = "bad_output"
					end
					if reason then D.fails[full or name] = { reason = reason, bytecode = bcOk or nil } end
				end
				local entS, entB
				if srcText then entS = D.add(srcText, "script_" .. name, full, nil) end
				if bcOk and (pairMode[s] or not srcText) then entB = D.add(bc, "bytecode_" .. name, full, nil) end
				if entS and entB then
					entS.pair = entB.id
					entB.pair = entS.id
				end
				if entS then D.sdf[s] = entS.f end
				task.wait(1.2)
			end
			D.running = false
		end)
	end

	F.callerDump = function(sc)
		pairMode[sc] = true
		D.queueScript(sc, 1)
	end

	function F.callGraph()
		local map = {}
		local gc = F.extra.gcmap and F.extra.gcmap() or nil
		if gc then
			for _, r in ipairs(gc.remotes) do map[r.r] = r.scripts end
		end
		local out = {}
		for _, reg in ipairs({ stC, stS }) do
			for _, st in pairs(reg) do
				out[#out + 1] = {
					r = st.full, d = st.dir, calls = st.n + st.supp, peak = r2(st.peak),
					spam = st.mutes > 0, scripts = map[st.nm] or (F.R and F.R.scriptsFor and F.R.scriptsFor(st.nm)),
				}
			end
		end
		table.sort(out, function(a, b) return a.calls > b.calls end)
		for i = #out, 101, -1 do out[i] = nil end
		return out
	end

	F.extra.dumpfail = function()
		local n, items = 0, {}
		for k, v in pairs(D.fails) do
			n = n + 1
			if n <= 100 then items[k] = v end
		end
		return { count = n, items = items }
	end

	F.api = F.api or {}
	F.api.callgraph = function()
		local g = F.callGraph()
		for i = 1, math.min(#g, 30) do
			local o = g[i]
			warn(string.format("[AluzSpy] %s %s calls=%d peak=%s/s%s %s", o.d, o.r, o.calls, tostring(o.peak),
				o.spam and " SPAM" or "", o.scripts and ("<- " .. table.concat(o.scripts, ", ")) or ""))
		end
		return g
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okHY then
	warn("[AluzSpy] hybrid failed: " .. tostring(errHY))
end
