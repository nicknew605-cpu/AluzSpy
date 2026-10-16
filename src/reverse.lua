do local _ = "aluzspy@1.2.1-max" end
local okRV, errRV = xpcall(function()
	if not F.job then return end
	CAP.reverse = true
	F.register("reverse", { ver = "1.2.1-max" })

	local gUp = type(getupvalues) == "function" and getupvalues or (debug and debug.getupvalues)
	local gCo = type(getconstants) == "function" and getconstants or (debug and debug.getconstants)
	local gPr = type(getprotos) == "function" and getprotos or (debug and debug.getprotos)
	local gCl = type(getscriptclosure) == "function" and getscriptclosure or (type(getscriptfunction) == "function" and getscriptfunction or nil)
	local gGc = type(getgc) == "function" and getgc or nil
	local gEnv = type(getfenv) == "function" and getfenv or nil

	local LIM = { closures = 600, consts = 200, ups = 100, depth = 3, seconds = 6, deepSeconds = 3, gcObjects = 60000, gcFuncs = 2500, links = 400, edges = 300 }
	local R = { callers = {}, cn = {}, ncallers = 0, last = nil, scanning = false, runs = 0, byRemote = {}, index = {}, nindex = 0 }
	F.R = R

	local COMMON = { Event = 1, Remote = 1, Name = 1, Value = 1, Function = 1, Fire = 1, Invoke = 1, Data = 1, Info = 1, Update = 1 }

	local function r2f(x) return floor(x * 100 + 0.5) / 100 end

	F.on(1, "reverse", function(e)
		if e.d ~= "C2S" or not e.sc or typeof(e.s) ~= "Instance" then return end
		local okS, full = pcall(function() return getInfo(e.s).full end)
		if not okS or type(full) ~= "string" then return end
		local sn = F.fullName(e.sc)
		local m = R.callers[full]
		if not m then
			if R.ncallers >= 500 then return end
			m = {}
			R.callers[full] = m
			R.cn[full] = 0
			R.ncallers = R.ncallers + 1
		end
		if m[sn] then
			m[sn] = m[sn] + 1
		elseif R.cn[full] < 8 then
			m[sn] = 1
			R.cn[full] = R.cn[full] + 1
		end
	end, 90)

	local function remoteSet()
		local byName = {}
		for _, reg in ipairs({ stC, stS }) do
			for _, st in pairs(reg) do
				if st.nm and #st.nm >= 3 then
					local l = byName[st.nm]
					if not l then
						l = {}
						byName[st.nm] = l
					end
					l[#l + 1] = st.full
				end
			end
		end
		return byName
	end

	local function scriptList()
		local out, seen = {}, {}
		local function add(l)
			if type(l) ~= "table" then return end
			for i = 1, #l do
				local s = l[i]
				if not seen[s] then
					seen[s] = true
					out[#out + 1] = s
				end
			end
		end
		if CAP.getscripts then
			local ok, l = pcall(getscripts)
			if ok then add(l) end
		end
		if CAP.getloadedmodules then
			local ok, l = pcall(getloadedmodules)
			if ok then add(l) end
		end
		return out
	end

	local function harvest(fn, depth, acc)
		if acc.n >= LIM.closures or clock() > acc.deadline then
			acc.truncated = true
			return
		end
		acc.n = acc.n + 1
		acc.owner[fn] = acc.script
		F.Y()
		if gCo then
			local ok, cs = pcall(gCo, fn)
			if ok and type(cs) == "table" then
				local c = 0
				for _, v in pairs(cs) do
					if type(v) == "string" and #v >= 3 and #v <= 120 then
						acc.strings[v] = (acc.strings[v] or 0) + 1
						c = c + 1
						if c >= LIM.consts then break end
					end
				end
			end
		end
		if gUp then
			local ok, ups = pcall(gUp, fn)
			if ok and type(ups) == "table" then
				local c = 0
				for _, v in pairs(ups) do
					c = c + 1
					if c > LIM.ups then break end
					local tv = type(v)
					acc.up[tv] = (acc.up[tv] or 0) + 1
					if tv == "function" then
						acc.fnups[#acc.fnups + 1] = v
					elseif tv == "string" and #v >= 3 and #v <= 120 then
						acc.strings[v] = (acc.strings[v] or 0) + 1
					end
				end
			end
		end
		if depth < LIM.depth and gPr then
			local ok, ps = pcall(gPr, fn)
			if ok and type(ps) == "table" then
				for i = 1, math.min(#ps, 40) do
					if type(ps[i]) == "function" then harvest(ps[i], depth + 1, acc) end
				end
			end
		end
	end

	local function indexStrings(name, strings)
		for s in pairs(strings) do
			local l = R.index[s]
			if not l then
				if R.nindex >= 8000 then break end
				l = {}
				R.index[s] = l
				R.nindex = R.nindex + 1
			end
			if #l < 4 then
				local dup = false
				for i = 1, #l do if l[i] == name then dup = true break end end
				if not dup then l[#l + 1] = name end
			end
		end
	end

	local function runScan(opts)
		opts = opts or {}
		local t0 = clock()
		R.scanning = true
		R.index, R.nindex = {}, 0
		local res = {
			scripts = 0, closures = 0, strings = 0, no_closure = 0, links = {}, edges = {}, truncated = false,
			limits = LIM, caps = { getscriptclosure = gCl ~= nil, getconstants = gCo ~= nil, getupvalues = gUp ~= nil, getprotos = gPr ~= nil, getgc = gGc ~= nil },
		}
		local acc = {
			n = 0, owner = {}, deadline = t0 + (opts.seconds or LIM.seconds), strings = {}, up = {}, fnups = {}, truncated = false, script = nil,
		}
		local perScript = {}
		local list = scriptList()
		for i = 1, #list do
			local s = list[i]
			local full = F.fullName(s)
			if not full:find("CoreGui", 1, true) and not full:find("RobloxGui", 1, true) then
				if gCl then
					local ok, fn = pcall(gCl, s)
					if ok and type(fn) == "function" then
						acc.script = full
						acc.strings = {}
						acc.fnups = {}
						acc.up = {}
						local before = acc.n
						harvest(fn, 0, acc)
						perScript[full] = { strings = acc.strings, fnups = acc.fnups, up = acc.up, closures = acc.n - before }
						indexStrings(full, acc.strings)
						res.scripts = res.scripts + 1
					else
						res.no_closure = res.no_closure + 1
					end
				end
				if acc.truncated then break end
			end
			F.Y()
		end
		res.closures = acc.n
		res.truncated = acc.truncated

		local byName = remoteSet()
		local nameHits = {}
		local linkMap = {}
		local function addLink(remote, script, conf, ev)
			local key = remote .. "|" .. script
			local l = linkMap[key]
			if not l then
				l = { remote = remote, script = script, confidence = 0, evidence = {} }
				linkMap[key] = l
			end
			if conf > l.confidence then l.confidence = conf end
			l.evidence[#l.evidence + 1] = ev
		end
		for full, ps in pairs(perScript) do
			for nm, fulls in pairs(byName) do
				if ps.strings[nm] then
					nameHits[nm] = (nameHits[nm] or 0) + 1
				end
			end
		end
		for full, ps in pairs(perScript) do
			for nm, fulls in pairs(byName) do
				if ps.strings[nm] then
					local base = 0.4
					if COMMON[nm] then base = 0.15 end
					if #nm < 5 then base = base * 0.8 end
					local spread = nameHits[nm] or 1
					base = base / (1 + 0.12 * (spread - 1))
					for _, rf in ipairs(fulls) do addLink(rf, full, r2f(base), "constant") end
				end
			end
			F.Y()
		end
		for rf, m in pairs(R.callers) do
			for sn, n in pairs(m) do
				local conf = 0.7
				if n >= 3 then conf = 0.8 end
				addLink(rf, sn, conf, "observed call x" .. n)
				local l = linkMap[rf .. "|" .. sn]
				local nm = rf:match("([^%.]+)$") or rf
				if perScript[sn] and perScript[sn].strings[nm] then
					l.confidence = r2f(math.min(0.98, l.confidence + 0.2))
					local has = false
					for q = 1, #l.evidence do if l.evidence[q] == "constant" then has = true end end
					if not has then l.evidence[#l.evidence + 1] = "constant" end
				end
			end
		end

		if opts.deep and gGc and gEnv and gCo then
			local d0 = clock()
			local okg, objs = pcall(gGc, true)
			local seen, inspected = 0, 0
			local known = {}
			for nm in pairs(byName) do known[nm] = true end
			if okg and type(objs) == "table" then
				for i = 1, math.min(#objs, LIM.gcObjects) do
					local f = objs[i]
					if type(f) == "function" and (not islclosure or islclosure(f)) then
						seen = seen + 1
						if inspected < LIM.gcFuncs then
							local oke, env = pcall(gEnv, f)
							local sc = oke and type(env) == "table" and rawget(env, "script") or nil
							if sc ~= nil then
								inspected = inspected + 1
								local okc, cs = pcall(gCo, f)
								if okc and type(cs) == "table" then
									local sn = F.fullName(sc)
									for _, v in pairs(cs) do
										if type(v) == "string" and known[v] then
											for _, rf in ipairs(byName[v]) do addLink(rf, sn, 0.45, "gc constant") end
										end
									end
								end
							end
						end
					end
					if i % 200 == 0 then
						F.Y()
						if clock() - d0 > LIM.deepSeconds then break end
					end
				end
			end
			res.deep = { objects = seen, inspected = inspected, ms = floor((clock() - d0) * 1000) }
		end

		local links = {}
		for _, l in pairs(linkMap) do links[#links + 1] = l end
		table.sort(links, function(a, b)
			if a.confidence ~= b.confidence then return a.confidence > b.confidence end
			return a.remote < b.remote
		end)
		for i = #links, LIM.links + 1, -1 do links[i] = nil end
		res.links = links

		local byR = {}
		for _, l in ipairs(links) do
			if l.confidence >= 0.5 then
				local t = byR[l.remote]
				if not t then
					t = {}
					byR[l.remote] = t
				end
				t[#t + 1] = l.script
			end
		end
		R.byRemote = byR

		local edges, emap = {}, {}
		for full, ps in pairs(perScript) do
			for _, f in ipairs(ps.fnups) do
				local own = acc.owner[f]
				if own and own ~= full then
					local key = full .. ">" .. own
					local e = emap[key]
					if not e then
						e = { from = full, to = own, kind = "upvalue", n = 0 }
						emap[key] = e
						edges[#edges + 1] = e
					end
					e.n = e.n + 1
				end
			end
		end
		for _, l in ipairs(links) do
			if l.confidence >= 0.5 and #edges < LIM.edges * 2 then
				edges[#edges + 1] = { from = l.script, to = l.remote, kind = "remote", n = 1, confidence = l.confidence }
			end
		end
		table.sort(edges, function(a, b) return a.n > b.n end)
		for i = #edges, LIM.edges + 1, -1 do edges[i] = nil end
		res.edges = edges

		local ns = 0
		for _ in pairs(R.index) do ns = ns + 1 end
		res.strings = ns
		res.ms = floor((clock() - t0) * 1000)
		res.t = os.time()
		R.last = res
		R.runs = R.runs + 1
		R.scanning = false
		return res
	end

	function R.scriptsFor(nm)
		local out = {}
		for rf, list in pairs(R.byRemote) do
			if rf == nm or (rf:match("([^%.]+)$") or rf) == nm then
				for i = 1, #list do out[#out + 1] = list[i] end
			end
		end
		if #out == 0 then return nil end
		table.sort(out)
		for i = #out, 9, -1 do out[i] = nil end
		return out
	end

	function F.reverseSummary()
		local l = R.last
		if not l then return { scans = R.runs, callers_tracked = R.ncallers } end
		local top = {}
		for i = 1, math.min(#l.links, 40) do top[i] = l.links[i] end
		return {
			scans = R.runs, scripts = l.scripts, closures = l.closures, strings = l.strings, no_closure = l.no_closure,
			links = #l.links, edges = #l.edges, truncated = l.truncated, ms = l.ms, deep = l.deep, caps = l.caps,
			callers_tracked = R.ncallers, top = top,
		}
	end
	F.extra.reverse = function()
		local l = R.last
		return { scans = R.runs, scripts = l and l.scripts or 0, links = l and #l.links or 0, truncated = l and l.truncated or nil }
	end

	local function emit(res)
		local js = F.enc(res)
		if not js then return nil end
		if CFG.redact and F.redact then
			local ok, r = pcall(F.redact, js)
			if ok and type(r) == "string" then js = r end
		end
		local f = "reverse_" .. os.date("%H%M%S") .. ".json"
		D.pending = D.pending + #js
		D.t = D.t + 1
		D.q[D.t] = { f = f, s = js }
		return f
	end

	local function start(opts)
		if R.scanning then return "running" end
		if not (gCl or gCo) then
			warn("[AluzSpy] reverse: executor lacks getscriptclosure/getconstants")
			return nil
		end
		local ok = F.job("reverse", function() return runScan(opts) end, function(res)
			R.scanning = false
			if type(res) == "table" then
				local f = emit(res)
				warn(string.format("[AluzSpy] reverse: %d scripts, %d closures, %d links%s -> %s", res.scripts, res.closures, #res.links, res.truncated and " (truncated)" or "", tostring(f)))
			end
		end, { prio = 3, timeout = 90 })
		if not ok then return nil end
		R.scanning = true
		return "queued"
	end

	local function find(text)
		if type(text) ~= "string" or #text < 2 then return {} end
		local out = {}
		text = text:lower()
		for s, l in pairs(R.index) do
			if s:lower():find(text, 1, true) then
				out[#out + 1] = { string = s, scripts = l }
				if #out >= 50 then break end
			end
		end
		return out
	end

	F.apiMerge({
		reverse = function(opts)
			if opts == "last" then return F.reverseSummary() end
			return start(type(opts) == "table" and opts or nil)
		end,
		reverseFind = find,
	})

	if CFG.autoReverse then
		task.delay(30, function()
			if alive and CFG.autoReverse and not R.last then start(nil) end
		end)
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okRV then
	warn("[AluzSpy] reverse failed: " .. tostring(errRV))
end
