do local _ = "aluzspy@1.2.3-stable" if F and F.trace then F.trace("load dump") end end
do
	local OBF = {
		{ "Luraph", "Luraph" }, { "LPH[%$%~%@%|]", "Luraph" }, { "LPH_", "Luraph" },
		{ "MoonSec", "MoonSec" }, { "Moon%-?Sec", "MoonSec" },
		{ "IronBrew", "IronBrew" }, { "IronBrewV%d", "IronBrew" },
		{ "Prometheus", "Prometheus" }, { "PSU_CRYPT", "Prometheus" },
		{ "Synapse Xen", "SynapseXen" }, { "SynapseXen", "SynapseXen" },
		{ "WeAreDevs", "WeAreDevs" }, { "Boronide", "Boronide" },
		{ "Aztup", "AztupBrew" }, { "AztupBrew", "AztupBrew" },
		{ "Luarmor", "Luarmor" }, { "script_key", "Luarmor" },
		{ "Hercules", "Hercules" }, { "AstroProtect", "AstroProtect" },
		{ "PSU_LOADER", "PSU" }, { "Fluxus", "Fluxus" },
		{ "Xor%d%d", "XorVM" }, { "vm_execute", "VM" },
		{ "bytecode", "Bytecode" }, { "string%.dump", "Bytecode" },
	}

	local function domain(url)
		if type(url) ~= "string" then return nil end
		local d = url:match("^%a+://([^/%?#]+)")
		if not d then return nil end
		return (d:gsub("[^%w]", ""))
	end

	function D.obf(src)
		local head = src:sub(1, 1200)
		for i = 1, #OBF do
			if head:find(OBF[i][1]) then return OBF[i][2] end
		end
		local sample = src:sub(1, 2000)
		local _, nl = sample:gsub("\n", "\n")
		local _, esc = sample:gsub("\\%d%d?%d?", "")
		if #sample >= 500 and ((nl < 3 and #src > 5000) or esc > 80) then return "obfuscated?" end
		return nil
	end

	function D.looks(body, url)
		if #body < 16 then return false end
		local c = body:sub(1, 1)
		if c == "{" or c == "[" or c == "<" then return false end
		if url and url:lower():find("%.lua") then return true end
		local head = body:sub(1, 4000)
		if head:find("local ", 1, true) or head:find("function", 1, true) or head:find("game", 1, true)
			or head:find("loadstring", 1, true) or head:find("return", 1, true) or head:find("--", 1, true) then
			return true
		end
		return false
	end

	function D.kindOf(tag, url, src)
		tag = tostring(tag or "other")
		if tag:sub(1, 8) == "bytecode" then return "bytecode" end
		if tag:sub(1, 9) == "layer" or tag:sub(1, 5) == "layer" then return "layer" end
		if tag:find("deob", 1, true) then return "deob" end
		if tag:sub(1, 7) == "script_" then return "script" end
		if tag == "loadstring" or tag == "loadfile" or tag == "dofile" then return "script" end
		if url and url:lower():find("%.lua") then return "script" end
		if type(src) == "string" and D.looks(src, url) then return "script" end
		return "other"
	end

	local function step(job, maxBytes)
		local s = job.s
		local n = #s
		local stop = job.pos + maxBytes - 1
		if stop > n then stop = n end
		local h1, h2 = job.h1, job.h2
		local byte = string.byte
		for i = job.pos, stop do
			local b = byte(s, i)
			h1 = (h1 * 31 + b) % 2147483647
			h2 = (h2 * 33 + b) % 4294967291
		end
		job.h1, job.h2, job.pos = h1, h2, stop + 1
		return stop >= n
	end

	local function finish(job)
		local ent = job.ent
		local n = #job.s
		local key = job.h1 .. ":" .. job.h2 .. ":" .. n
		local ex = D.seen[key]
		if ex then
			ent.dup = ex.id
			ent.f = ex.f
			ent.bytes = 0
			D.pending = D.pending - n
			job.s = nil
			N.dup = N.dup + 1
			return
		end
		D.seen[key] = ent
		ent.hash = key
		D.t = D.t + 1
		D.q[D.t] = { f = ent.f, s = job.s, k = ent.kind, id = ent.id }
		job.s = nil
	end

	function D.add(src, tag, url, parent, id)
		if not id then
			id = X.chunk + 1
			X.chunk = id
		end
		if not (S.dump and HAS_W) then return nil end
		local n = #src
		if n < 16 then return nil end
		if D.n >= K.DUMP_MAX or n > K.DUMP_FILE_MAX or D.pending + n > K.DUMP_PEND_MAX then
			D.skipped = D.skipped + 1
			return nil
		end
		D.n = D.n + 1
		local dom = domain(url)
		local tg = tag:gsub("[^%w]", "")
		local kind = D.kindOf(tag, url, src)
		local fname = string.format("%s_%03d_%s%s.lua", PATH.tag, D.n, tg, dom and ("_" .. dom) or "")
		local ent = {
			id = id, f = fname, tag = tag, url = url, bytes = n, parent = parent, kind = kind,
			obf = D.obf(src), t = r2(clock() - T0),
		}
		D.list[#D.list + 1] = ent
		D.pending = D.pending + n
		local job = { s = src, ent = ent, pos = 1, h1 = n, h2 = 5381 }
		if n <= 32768 then
			step(job, n)
			finish(job)
		else
			D.jobs[#D.jobs + 1] = job
		end
		return ent
	end

	function D.quota(kind)
		return K.DISK_KIND[kind] or K.DISK_KIND.other or 8388608
	end

	function D.used(kind)
		return D.kind[kind] or 0
	end

	function D.evict(kind, need)
		local freed, removed = 0, 0
		local function evictFrom(k, amount)
			local over = D.used(k) + amount - D.quota(k)
			if over <= 0 then return end
			for i = 1, #D.files do
				local f = D.files[i]
				if f and f.k == k and not f.gone then
					f.gone = true
					D.kind[k] = (D.kind[k] or 0) - f.n
					D.bytes = (D.bytes or 0) - f.n
					FS.del(PATH.d(f.f))
					freed = freed + f.n
					removed = removed + 1
					N.evict = N.evict + 1
					over = over - f.n
					if over <= 0 then return end
				end
			end
		end
		evictFrom(kind, need)
		if D.used(kind) + need > D.quota(kind) then
			evictFrom("other", need)
		end
		if D.used(kind) + need > D.quota(kind) then
			evictFrom("layer", need)
		end
		return freed
	end

	function D.evictTotal(need)
		local over = (D.bytes or 0) + need - K.DUMP_TOTAL
		if over <= 0 then return 0 end
		local freed = 0
		for i = 1, #D.files do
			local f = D.files[i]
			if f and not f.gone then
				f.gone = true
				D.kind[f.k] = (D.kind[f.k] or 0) - f.n
				D.bytes = (D.bytes or 0) - f.n
				FS.del(PATH.d(f.f))
				freed = freed + f.n
				N.evict = N.evict + 1
				over = over - f.n
				if over <= 0 then break end
			end
		end
		return freed
	end

	function D.emit(name, content, kind)
		if not HAS_W or type(content) ~= "string" then return false end
		D.pending = D.pending + #content
		D.t = D.t + 1
		D.q[D.t] = { f = name, s = content, k = kind or "other" }
		X.dirty = true
		return true
	end

	function D.writeOne()
		if D.h > D.t then return false end
		local it = D.q[D.h]
		D.q[D.h] = nil
		D.h = D.h + 1
		if not it then return true end
		local n = #it.s
		if n >= D.pending then D.pending = 0 else D.pending = D.pending - n end
		local kind = it.k or "other"
		if D.used(kind) + n > D.quota(kind) then D.evict(kind, n) end
		if (D.bytes or 0) + n > K.DUMP_TOTAL then D.evictTotal(n) end
		local ok = pcall(writefile, PATH.d(it.f), it.s)
		if ok then
			D.files[#D.files + 1] = { f = it.f, n = n, k = kind, id = it.id, t = os.time() }
			D.bytes = (D.bytes or 0) + n
			D.kind[kind] = (D.kind[kind] or 0) + n
			if #D.files > 4000 then
				local old = table.remove(D.files, 1)
				if old and not old.gone then
					D.kind[old.k] = (D.kind[old.k] or 0) - old.n
					D.bytes = (D.bytes or 0) - old.n
					FS.del(PATH.d(old.f))
					N.evict = N.evict + 1
				end
			end
		else
			D.fail = D.fail + 1
		end
		D.dirtyDump = true
		X.dirty = true
		return true
	end

	function D.flush()
		return D.flushBudgeted(4000)
	end

	function D.flushBudgeted(maxJobs)
		maxJobs = tonumber(maxJobs) or 200
		local guard = 0
		while D.jobs[1] and guard < maxJobs do
			guard = guard + 1
			local j = table.remove(D.jobs, 1)
			local stepBytes = 131072
			while not step(j, math.min(stepBytes, #j.s - j.pos + 1)) do
				guard = guard + 1
				if guard >= maxJobs then return false end
				stepBytes = stepBytes * 2
				if stepBytes > 4194304 then stepBytes = 4194304 end
			end
			finish(j)
		end
		guard = 0
		while D.writeOne() and guard < maxJobs do guard = guard + 1 end
		return true
	end

	function D.pump()
		local j = D.jobs[1]
		if j and step(j, 32768) then
			table.remove(D.jobs, 1)
			finish(j)
		end
		D.writeOne()
	end

	function D.queueScript(sc, prio)
		if not (CAP.decompile and S.dump) or not D.admit(sc, prio) then return end
		D.push(sc, prio)
		if D.running then return end
		D.running = true
		task.spawn(function()
			while alive and #D.sq > 0 do
				local s = D.pop()
				local ok, src = pcall(decompile, s)
				if ok and type(src) == "string" and #src > 16 then
					local okn, nm = pcall(function() return s.Name end)
					local okf, full = pcall(s.GetFullName, s)
					local ent = D.add(src, "script_" .. (okn and nm or "x"), okf and full or nil, nil)
					if ent then D.sdf[s] = ent.f end
				end
				task.wait(1.5)
			end
			D.running = false
		end)
	end
	F.callerDump = function(sc) return D.queueScript(sc, 1) end

	local function scanList(list, filter)
		if type(list) ~= "table" then return 0 end
		local c = 0
		for i = 1, #list do
			local s = list[i]
			local ok, full = pcall(s.GetFullName, s)
			if ok and not full:find("CoreGui", 1, true) and not full:find("RobloxGui", 1, true)
				and (not filter or full:lower():find(filter, 1, true)) then
				D.queueScript(s, 3)
				c = c + 1
				if c >= 500 then break end
			end
		end
		return c
	end

	function F.scanScripts(filter)
		if not (CAP.getscripts and CAP.decompile) then return 0 end
		if filter then filter = filter:lower() end
		local c = 0
		local ok, l = pcall(getscripts)
		if ok then c = c + scanList(l, filter) end
		if CAP.getloadedmodules then
			local ok2, l2 = pcall(getloadedmodules)
			if ok2 then c = c + scanList(l2, filter) end
		end
		if CAP.getrunningscripts then
			local ok3, l3 = pcall(getrunningscripts)
			if ok3 then c = c + scanList(l3, filter) end
		end
		return c
	end

	F.h[3] = function(e, now)
		armFlag(now)
		local url = e.u
		local us = type(url) == "string" and url or tostring(url)
		us = clean(us:sub(1, 200))
		local body = e.b
		local blen, head, ent = 0, "", nil
		if type(body) == "string" then
			blen = #body
			head = clean(body:sub(1, 120))
			if S.dump and D.looks(body, us) then
				ent = D.add(body, e.tag, us, e.par)
			end
		end
		local key = e.tag .. "|" .. us
		local rec = X.netRecs[key]
		if rec and rec.live and now - rec.t0 < WIN then
			rec.n = rec.n + 1
			N.merged = N.merged + 1
			return
		end
		if not takeToken(now) then
			N.bucket = N.bucket + 1
			return
		end
		local a = { us }
		if e.mth then a[#a + 1] = clean(tostring(e.mth)) end
		if e.st then a[#a + 1] = "st=" .. clean(tostring(e.st)) end
		a[#a + 1] = blen .. "b"
		if head ~= "" then a[#a + 1] = head end
		if type(e.sent) == "string" and #e.sent > 0 then
			local sent = clean(e.sent:sub(1, 180))
			if F.mask then sent = F.mask(sent) end
			a[#a + 1] = "sent: " .. sent
		end
		if type(e.hd) == "string" and #e.hd > 0 then a[#a + 1] = "hdr: " .. clean(e.hd:sub(1, 180)) end
		if ent then
			a[#a + 1] = "-> " .. ent.f
			if ent.obf then a[#a + 1] = ent.obf end
		end
		rec = newRec("NET", us, e.tag, a, now)
		rec.f = ent and ent.f or nil
		rec.did = ent and ent.id or nil
		rec.par = e.par
		X.netRecs[key] = rec
		N.netCount = N.netCount + 1
		if N.netCount > 300 then
			X.netRecs = {}
			N.netCount = 0
		end
	end

	F.h[7] = function(e, now)
		local src = e.src
		if type(src) ~= "string" then src = tostring(src) end
		local tag = e.tag
		local isLS = tag == "loadstring"
		if isLS then armFlag(now) end
		local ent = nil
		if tag ~= "setclipboard" then
			ent = D.add(src, tag, e.url or X.nb[src], e.par, e.id)
		end
		local head = clean(src:sub(1, 120))
		local key = tag .. "|" .. #src .. "|" .. head:sub(1, 40)
		local rec = X.srcRecs[key]
		if rec and rec.live and now - rec.t0 < WIN * 5 then
			rec.n = rec.n + 1
			N.merged = N.merged + 1
			return
		end
		if not takeToken(now) then
			N.bucket = N.bucket + 1
			return
		end
		local a = { #src .. "b", head }
		if ent then
			a[#a + 1] = "-> " .. ent.f
			if ent.obf then a[#a + 1] = ent.obf end
		end
		rec = newRec(isLS and "LS" or "SYS", tag, tag, a, now)
		rec.f = ent and ent.f or nil
		rec.did = e.id
		rec.par = e.par
		X.srcRecs[key] = rec
		N.srcCount = N.srcCount + 1
		if N.srcCount > 300 then
			X.srcRecs = {}
			N.srcCount = 0
		end
	end

	IN.ls = function()
		if INST.ls then
			MOD.ls = true
			return true
		end
		local fn = genv.loadstring or loadstring
		local ok = F.hookWith(fn, function(holder)
			return function(src, ...)
				if MOD.ls and alive and not busy and type(src) == "string" then
					local id = X.chunk + 1
					X.chunk = id
					pcall(F.capSrc, "loadstring", src, id, X.cof[coroutine.running()], nil)
					local f, err = holder.old(src, ...)
					if CFG.tree and type(f) == "function" then
						local orig = f
						f = function(...)
							local co = coroutine.running()
							local prev = X.cof[co]
							X.cof[co] = id
							local r = pack(pcall(orig, ...))
							X.cof[co] = prev
							if not r[1] then error(r[2], 0) end
							return unpack(r, 2, r.n)
						end
					end
					return f, err
				end
				return holder.old(src, ...)
			end
		end, true, "ls")
		if not ok then return false end
		INST.ls = true
		MOD.ls = true
		local prev = busy
		busy = true
		local okT, f = pcall(loadstring, "return 41+1")
		busy = prev
		if not (okT and type(f) == "function") then
			MOD.ls = false
			return false
		end
		local okR, v = pcall(f)
		if not okR or v ~= 42 then
			MOD.ls = false
			return false
		end
		return true
	end

	IN.rw = function()
		if INST.rw then
			MOD.rw = true
			return true
		end
		local any = false
		local function ours(p)
			return type(p) ~= "string" or p:find("^AluzSpy") ~= nil or p:find("^AluzDump") ~= nil
		end
		local function hk(fn, tag, isRead)
			local ok = F.hookWith(fn, function(holder)
				if isRead then
					return function(path, ...)
						local r = holder.old(path, ...)
						if MOD.rw and alive and not busy and not ours(path) and type(r) == "string"
							and #r >= 24 and D.looks(r, path) then
							pcall(F.capSrc, tag, r, nil, X.cof[coroutine.running()], path)
						end
						return r
					end
				end
				return function(path, data, ...)
					if MOD.rw and alive and not busy and not ours(path) and type(data) == "string" and #data >= 24
						and (path:lower():find("%.lua$") or D.looks(data, path)) then
						pcall(F.capSrc, tag, data, nil, X.cof[coroutine.running()], path)
					end
					return holder.old(path, data, ...)
				end
			end, true, "rw_" .. tag)
			if ok then any = true end
		end
		hk(genv.readfile, "readfile", true)
		hk(genv.writefile, "writefile", false)
		hk(genv.appendfile, "appendfile", false)
		INST.rw = true
		MOD.rw = true
		local st = F.reg("rw")
		st.installed = any
		st.kind = "function"
		st.target = "readfile/writefile"
		return any
	end

	F.stage("rw", 10, IN.rw)
	F.stage("ls", 11, IN.ls)
end
