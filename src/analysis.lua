do local _ = "aluzspy@1.2.2-beta" if F and F.trace then F.trace("load analysis") end end
local okAN, errAN = xpcall(function()
	if not F.job then return end

	local AN = { gc = nil, sd = nil, tree = nil }
	local function note(t)
		if F.notify then F.notify(t) end
	end

	local baseDC = F.decodeCore
	if baseDC then
		local W = {
			{ "discord webhook", 30 }, { "telegram", 30 }, { "ROBLOSECURITY", 40 }, { "ip lookup", 10 },
			{ "sends data to a webhook", 25 }, { "queue_on_teleport", 10 }, { "clipboard", 5 }, { "file write", 8 },
			{ "hooks functions", 5 }, { "environment access", 5 }, { "Kick", 5 }, { "outbound http", 10 },
			{ "remote loadstring", 15 }, { "fires remotes", 3 },
		}
		F.decodeCore = function(src)
			local text, rep, stats = baseDC(src)
			if type(rep) == "table" and type(rep.flags) == "table" then
				local score = 0
				for _, fl in ipairs(rep.flags) do
					for _, w in ipairs(W) do
						if fl:find(w[1], 1, true) then
							score = score + w[2]
							break
						end
					end
				end
				if score > 100 then score = 100 end
				if score > 0 then
					local lvl = score >= 60 and "high" or (score >= 30 and "medium" or "low")
					table.insert(rep.flags, 1, string.format("risk score %d/100 (%s)", score, lvl))
				end
				rep.risk = score
			end
			return text, rep, stats
		end
	end

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
		if not CAP.decompile and type(getscriptbytecode) ~= "function" then return end
		D.push(sc, prio)
		if D.running then return end
		D.running = true
		task.spawn(function()
			while alive and #D.sq > 0 do
				local s = D.pop()
				local okn, nm = pcall(function() return s.Name end)
				local okf, full = pcall(s.GetFullName, s)
				local name = okn and nm or "x"
				local res = CAP.decompile and tryDecompile(s, 25) or nil
				local okb, bc = false, nil
				if type(getscriptbytecode) == "function" then okb, bc = pcall(getscriptbytecode, s) end
				local src, tag
				if res and res.ok and type(res.r) == "string" and #res.r >= 40 and not badText(res.r) then
					src, tag = res.r, "script_" .. name
				elseif res and res.ok and type(res.r) == "string" and #res.r >= 8 and not badText(res.r)
					and okb and type(bc) == "string" and #bc < 200 then
					src, tag = res.r, "script_" .. name
				elseif okb and type(bc) == "string" and #bc >= 16 then
					src, tag = bc, "bytecode_" .. name
				end
				if src then
					local ent = D.add(src, tag, okf and full or nil, nil)
					if ent then D.sdf[s] = ent.f end
				end
				task.wait(1.2)
			end
			D.running = false
		end)
	end
	F.callerDump = function(sc) return D.queueScript(sc, 1) end

	local SKIP = { Players = 1, Workspace = 1, Event = 1, Remote = 1, Name = 1, Value = 1, Humanoid = 1, Character = 1, Part = 1 }

	local function remoteNames()
		local set, n = {}, 0
		local function add(nm)
			if type(nm) == "string" and #nm >= 3 and #nm <= 60 and not set[nm] and not SKIP[nm] and n < 4000 then
				set[nm] = true
				n = n + 1
			end
		end
		for _, reg in ipairs({ stC, stS }) do
			for _, st in pairs(reg) do add(st.nm) end
		end
		for r, c in pairs(attached) do
			if c then pcall(function() add(r.Name) end) end
		end
		for i = 1, #RF.list do
			pcall(function() add(RF.list[i].Name) end)
		end
		return set
	end

	function F.gcMap(deep)
		if type(getconstants) ~= "function" or type(getscriptclosure) ~= "function" then return false end
		return F.job("gcmap", function()
			local rn = remoteNames()
			local map = {}
			local scriptsSeen, protoSeen = 0, 0
			local function hit(const, src)
				local m = map[const]
				if not m then
					m = { n = 0, s = {} }
					map[const] = m
				end
				if not m.s[src] and m.n < 8 then
					m.s[src] = true
					m.n = m.n + 1
				end
			end
			local function scanFn(f, src, depth)
				local okc, cs = pcall(getconstants, f)
				if okc and type(cs) == "table" then
					for _, v in pairs(cs) do
						if type(v) == "string" and rn[v] then hit(v, src) end
					end
				end
				protoSeen = protoSeen + 1
				if depth < 3 and protoSeen < 40000 and type(getprotos) == "function" then
					local okp, ps = pcall(getprotos, f)
					if okp and type(ps) == "table" then
						for i = 1, math.min(#ps, 80) do scanFn(ps[i], src, depth + 1) end
					end
				end
				if protoSeen % 40 == 0 then F.Y() end
			end
			local okr, running = pcall(getrunningscripts)
			if okr and type(running) == "table" then
				for i = 1, math.min(#running, 600) do
					local s = running[i]
					local full = F.fullName(s)
					if not full:find("CoreGui", 1, true) and not full:find("RobloxGui", 1, true) then
						local okcl, cl = pcall(getscriptclosure, s)
						if okcl and type(cl) == "function" then
							scriptsSeen = scriptsSeen + 1
							scanFn(cl, full, 0)
						end
					end
					F.Y()
				end
			end
			if deep then
				local list
				if type(filtergc) == "function" then
					local okf, l = pcall(filtergc, "function", { IgnoreExecutor = true }, false)
					if okf and type(l) == "table" then list = l end
				end
				if not list and type(getgc) == "function" then
					local okg, l = pcall(getgc)
					if okg and type(l) == "table" then list = l end
				end
				if list then
					local t0 = clock()
					for i = 1, math.min(#list, 150000) do
						local f = list[i]
						if type(f) == "function" and not (isexecutorclosure and isexecutorclosure(f)) then
							local oki, src = pcall(debug.info, f, "s")
							if oki and type(src) == "string" and src ~= "[C]" and src ~= "" then
								scanFn(f, src, 2)
							end
						end
						if i % 150 == 0 then F.Y() end
						if clock() - t0 > 30 then break end
					end
					list = nil
				end
			end
			local out = {}
			for nm, m in pairs(map) do
				local ss = {}
				for s in pairs(m.s) do ss[#ss + 1] = s end
				table.sort(ss)
				out[#out + 1] = { r = nm, scripts = ss }
			end
			table.sort(out, function(a, b) return a.r < b.r end)
			for i = #out, 201, -1 do out[i] = nil end
			return { remotes = out, scripts = scriptsSeen, protos = protoSeen, deep = deep and true or false, t = os.time() }
		end, function(res)
			AN.gc = res
			if res then note("MAP done: " .. #res.remotes .. " remotes") end
		end)
	end

	local SIP = PATH.f("scripts_" .. game.PlaceId .. ".json")

	function F.scriptDiff()
		if type(getscripts) ~= "function" or type(getscripthash) ~= "function" then return false end
		return F.job("scriptdiff", function()
			local old, first = {}, true
			local txt = FS.read(SIP)
			local t = type(txt) == "string" and F.dec(txt) or nil
			if type(t) == "table" and type(t.s) == "table" then
				old = t.s
				first = false
			end
			local all = {}
			local okS, list = pcall(getscripts)
			if okS and type(list) == "table" then
				for i = 1, #list do all[#all + 1] = list[i] end
			end
			if type(getloadedmodules) == "function" then
				local okM, ml = pcall(getloadedmodules)
				if okM and type(ml) == "table" then
					for i = 1, #ml do all[#all + 1] = ml[i] end
				end
			end
			local new, changed, added, refs = {}, {}, {}, {}
			for i = 1, math.min(#all, 4000) do
				local s = all[i]
				local full = F.fullName(s)
				if not full:find("CoreGui", 1, true) and not full:find("RobloxGui", 1, true) then
					local okh, h = pcall(getscripthash, s)
					if okh and type(h) == "string" then
						new[full] = h
						if not first then
							if old[full] == nil then
								added[#added + 1] = full
								if #refs < 40 then refs[#refs + 1] = s end
							elseif old[full] ~= h then
								changed[#changed + 1] = full
								if #refs < 40 then refs[#refs + 1] = s end
							end
						end
					end
				end
				if i % 50 == 0 then F.Y() end
			end
			if HAS_W then FS.write(SIP, F.enc({ s = new, t = os.time() }) or "{}") end
			local total = 0
			for _ in pairs(new) do total = total + 1 end
			return { total = total, first = first, changed = changed, added = added, refs = refs, t = os.time() }
		end, function(res)
			if not res then return end
			local refs = res.refs
			res.refs = nil
			for i = #res.changed, 61, -1 do res.changed[i] = nil end
			for i = #res.added, 61, -1 do res.added[i] = nil end
			AN.sd = res
			if #res.changed + #res.added > 0 then
				newRec("SYS", "scripts", "diff", { "changed " .. #res.changed, "added " .. #res.added }, clock())
				if S.dump then
					for i = 1, #refs do D.queueScript(refs[i], 1) end
				end
			end
			note(res.first and "script baseline saved" or ("scripts: " .. #res.changed .. " changed, " .. #res.added .. " new"))
		end)
	end

	function F.tree()
		return F.job("tree", function()
			local out = { place = game.PlaceId, remotes = {}, scripts = {}, guis = {}, nil_remotes = 0, counts = {} }
			local okl, list = pcall(function() return game:GetDescendants() end)
			if not okl then return nil end
			local nR, nS = 0, 0
			for i = 1, #list do
				local inst = list[i]
				local cn = inst.ClassName
				out.counts[cn] = (out.counts[cn] or 0) + 1
				if cn == "RemoteEvent" or cn == "RemoteFunction" or cn == "UnreliableRemoteEvent"
					or cn == "BindableEvent" or cn == "BindableFunction" then
					if nR < 3000 then
						local full = F.fullName(inst)
						if not full:find("^CoreGui") and not full:find("RobloxGui", 1, true) then
							nR = nR + 1
							out.remotes[nR] = { c = cn, p = full }
						end
					end
				elseif cn == "ModuleScript" or cn == "LocalScript" or cn == "Script" then
					if nS < 3000 then
						local full = F.fullName(inst)
						if not full:find("^CoreGui") and not full:find("RobloxGui", 1, true) then
							nS = nS + 1
							out.scripts[nS] = { c = cn, p = full }
						end
					end
				end
				if i % 1200 == 0 then F.Y() end
			end
			if type(getnilinstances) == "function" then
				local okn, nl = pcall(getnilinstances)
				if okn and type(nl) == "table" then
					for i = 1, math.min(#nl, 20000) do
						local cn = nl[i].ClassName
						if cn == "RemoteEvent" or cn == "RemoteFunction" or cn == "UnreliableRemoteEvent" then
							out.nil_remotes = out.nil_remotes + 1
							if #out.remotes < 3200 then out.remotes[#out.remotes + 1] = { c = cn, p = "[nil]." .. nl[i].Name } end
						end
						if i % 1500 == 0 then F.Y() end
					end
				end
			end
			pcall(function()
				local pg = LP:FindFirstChildOfClass("PlayerGui")
				if pg then
					for _, g in ipairs(pg:GetChildren()) do out.guis[#out.guis + 1] = { c = g.ClassName, n = g.Name } end
				end
			end)
			local arr = {}
			for cn, c in pairs(out.counts) do arr[#arr + 1] = { cn, c } end
			table.sort(arr, function(a, b) return a[2] > b[2] end)
			local top = {}
			for i = 1, math.min(#arr, 60) do top[arr[i][1]] = arr[i][2] end
			out.counts = top
			return out
		end, function(out)
			if not out then return end
			local name = "game_tree_" .. PATH.tag .. ".json"
			local js = F.enc(out)
			if js and FS.write(PATH.d(name), js) then
				AN.tree = { file = name, remotes = #out.remotes, scripts = #out.scripts, nil_remotes = out.nil_remotes }
				note("tree saved: " .. name)
			end
		end)
	end

	IN.sd = function()
		MOD.sd = true
		INST.sd = true
		task.delay(15, function()
			if alive and MOD.sd then F.scriptDiff() end
		end)
		return true
	end
	F.stage("sd", 95, IN.sd)

	F.api.gcmap = function(deep) return F.gcMap(deep == true) end
	F.api.whoCalls = function(name)
		local out = {}
		if AN.gc then
			for _, r in ipairs(AN.gc.remotes) do
				if r.r == name or tostring(r.r):lower():find(tostring(name):lower(), 1, true) then out[#out + 1] = r end
			end
		end
		for _, r in ipairs(out) do warn("[AluzSpy] " .. r.r .. " <- " .. table.concat(r.scripts, ", ")) end
		if #out == 0 then warn("[AluzSpy] no result, run AluzSpy.gcmap() first") end
		return out
	end
	F.api.scriptDiff = F.scriptDiff
	F.api.tree = F.tree
	F.api.ext = F.ext
	F.api.help2 = function()
		warn("[AluzSpy] gcmap(deep) whoCalls(name) scriptDiff() tree() health() actors() unlz4(file) saveIndex() ext()")
	end

	F.extra.gcmap = function() return AN.gc end
	F.extra.scripts = function() return AN.sd end
	F.extra.tree = function() return AN.tree end

	local function act(label, fn)
		return { label, function() return false end, function() fn() return false end }
	end
	F.extraChips[#F.extraChips + 1] = { "SD", function() return MOD.sd end, function(v) return F.setMod("sd", v) end }
	F.extraChips[#F.extraChips + 1] = act("MAP", function() note(F.gcMap(false) and "MAP started" or "MAP unavailable") end)
	F.extraChips[#F.extraChips + 1] = act("SNAP", function() note(F.tree() and "SNAP started" or "busy") end)
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okAN then
	warn("[AluzSpy] analysis failed: " .. tostring(errAN))
end
