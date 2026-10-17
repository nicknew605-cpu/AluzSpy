do local _ = "aluzspy@1.2.2-beta" if F and F.trace then F.trace("load reverse") end end
local okRV, errRV = xpcall(function()
	if not F.job then return end
	F.api = F.api or {}
	if CFG.autoReverse == nil then CFG.autoReverse = false end
	local RV = { last = nil, running = false, lastFile = nil }
	F.reverse = RV

	local function remoteSet()
		local set = {}
		for _, reg in ipairs({ stC, stS }) do
			for _, st in pairs(reg) do
				if type(st.nm) == "string" and #st.nm >= 3 then set[st.nm] = true end
				if type(st.full) == "string" and #st.full >= 3 then set[st.full] = true end
			end
		end
		for r, c in pairs(attached) do
			pcall(function()
				if type(r.Name) == "string" and #r.Name >= 3 then set[r.Name] = true end
			end)
		end
		for i = 1, #RF.list do
			pcall(function()
				if type(RF.list[i].Name) == "string" and #RF.list[i].Name >= 3 then set[RF.list[i].Name] = true end
			end)
		end
		return set
	end

	local function scan(mode)
		local remotes = remoteSet()
		local out = {
			mode = mode, t = os.time(), scripts = 0, closures = 0, constants = 0,
			remotes = {}, xref = {}, edges = {},
		}
		local remoteSeen, xrefMap, edgeSeen = {}, {}, {}

		local function hitRemote(v, src)
			local key = v .. "|" .. tostring(src)
			if not remoteSeen[key] and #out.remotes < 800 then
				remoteSeen[key] = true
				out.remotes[#out.remotes + 1] = { r = v, src = src }
			end
		end

		local function hitString(v, src)
			if #out.xref >= 2000 then return end
			local m = xrefMap[v]
			if not m then
				m = {}
				xrefMap[v] = m
				out.xref[#out.xref + 1] = { s = v, src = m }
			end
			if #m < 5 and src then
				for i = 1, #m do
					if m[i] == src then return end
				end
				m[#m + 1] = src
			end
		end

		local function hitEdge(a, b)
			if not a or not b or a == b then return end
			local key = a .. "|" .. b
			if not edgeSeen[key] and #out.edges < 1500 then
				edgeSeen[key] = true
				out.edges[#out.edges + 1] = { from = a, to = b }
			end
		end

		local function scanClosure(f, depth, parentSrc)
			if out.closures >= 12000 then return end
			out.closures = out.closures + 1
			local src
			if debug and debug.info then
				local ok, s = pcall(debug.info, f, "s")
				if ok and type(s) == "string" and s ~= "[C]" and s ~= "" then src = s end
			end
			if getconstants then
				local okc, cs = pcall(getconstants, f)
				if okc and type(cs) == "table" then
					local c = 0
					for _, v in pairs(cs) do
						if type(v) == "string" and #v >= 3 and #v <= 120 then
							c = c + 1
							out.constants = out.constants + 1
							hitString(v, src)
							if remotes[v] then hitRemote(v, src) end
							if c >= 80 then break end
						end
					end
				end
			end
			if parentSrc and src then hitEdge(parentSrc, src) end
			if depth < 2 and getprotos then
				local okp, ps = pcall(getprotos, f)
				if okp and type(ps) == "table" then
					for i = 1, math.min(#ps, 40) do
						scanClosure(ps[i], depth + 1, src or parentSrc)
					end
				end
			end
			if out.closures % 80 == 0 and F.Y then F.Y() end
		end

		local list = {}
		if getrunningscripts then
			local ok, l = pcall(getrunningscripts)
			if ok and type(l) == "table" then
				for i = 1, math.min(#l, 600) do list[#list + 1] = l[i] end
			end
		end
		if getscripts then
			local ok, l = pcall(getscripts)
			if ok and type(l) == "table" then
				for i = 1, math.min(#l, 600) do list[#list + 1] = l[i] end
			end
		end
		if getloadedmodules then
			local ok, l = pcall(getloadedmodules)
			if ok and type(l) == "table" then
				for i = 1, math.min(#l, 300) do list[#list + 1] = l[i] end
			end
		end

		for i = 1, #list do
			if getscriptclosure then
				local okcl, cl = pcall(getscriptclosure, list[i])
				if okcl and type(cl) == "function" then
					out.scripts = out.scripts + 1
					scanClosure(cl, 0, nil)
				end
			end
			if i % 40 == 0 and F.Y then F.Y() end
		end

		if mode == "deep" then
			local glist
			if type(filtergc) == "function" then
				local okf, l = pcall(filtergc, "function", { IgnoreExecutor = true }, false)
				if okf and type(l) == "table" then glist = l end
			end
			if not glist and type(getgc) == "function" then
				local okg, l = pcall(getgc)
				if okg and type(l) == "table" then glist = l end
			end
			if glist then
				local t0 = clock()
				for i = 1, math.min(#glist, 40000) do
					local f = glist[i]
					if type(f) == "function" and not (isexecutorclosure and isexecutorclosure(f)) then
						scanClosure(f, 2, nil)
					end
					if i % 200 == 0 and F.Y then F.Y() end
					if clock() - t0 > 20 then break end
				end
			end
		end

		return out
	end

	F.api.reverse = function(cmd)
		cmd = tostring(cmd or "status"):lower()
		if cmd == "scan" or cmd == "deep" then
			if RV.running then return false end
			RV.running = true
			local ok = F.job("reverse", function()
				return scan(cmd)
			end, function(res)
				RV.running = false
				RV.last = res
				if res then
					local name = "reverse_" .. os.date("%H%M%S") .. ".json"
					pcall(FS.write, PATH.d(name), F.enc(res) or "{}")
					RV.lastFile = name
				end
				if F.notify then F.notify("Reverse done") end
			end)
			if not ok then RV.running = false end
			return ok
		elseif cmd == "status" then
			return {
				running = RV.running, has = RV.last ~= nil, file = RV.lastFile,
				scripts = RV.last and RV.last.scripts or 0,
				closures = RV.last and RV.last.closures or 0,
				remotes = RV.last and #RV.last.remotes or 0,
				xref = RV.last and #RV.last.xref or 0,
				edges = RV.last and #RV.last.edges or 0,
			}
		elseif cmd == "remotes" then
			return RV.last and RV.last.remotes or {}
		elseif cmd == "graph" or cmd == "edges" then
			return RV.last and RV.last.edges or {}
		end
		return RV.last
	end

	F.extra.reverse = function()
		return F.api.reverse("status")
	end

	if CFG.autoReverse then
		task.delay(30, function()
			if alive and not RV.running then F.api.reverse("scan") end
		end)
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okRV then
	warn("[AluzSpy] reverse failed: " .. tostring(errRV))
end
