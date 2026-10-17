do local _ = "aluzspy@1.2.1-max" if F and F.trace then F.trace("load dump2") end end
local okD2, errD2 = xpcall(function()
	F.api = F.api or {}
	 if CFG.decode == nil then CFG.decode = true end
if CFG.sandbox == nil then CFG.sandbox = false end
	local STORE_MAX = 24 * 1024 * 1024
	local byte = string.byte
	D.store, D.spilled, D.storeBytes = {}, {}, 0
	D.diffs, D.diffN, D.dirtyDump = {}, 0, false
	PATH.spool = PATH.f(".spool")

	local function fastKey(src)
		local n = #src
		local h = 5381
		local step = 1
		if n > 4096 then step = floor(n / 2048) end
		for i = 1, n, step do
			h = ((h * 33) + byte(src, i)) % 4294967291
		end
		return "f" .. h .. ":" .. n
	end

	local HASHFN
	if type(crypt) == "table" and type(crypt.hash) == "function" then
		local forms = {
			function(s) return crypt.hash(s, "sha256") end,
			function(s) return crypt.hash(s, "sha1") end,
			function(s) return crypt.hash(s, "md5") end,
			function(s) return crypt.hash(s) end,
		}
		for i = 1, #forms do
			local f = forms[i]
			local ok1, a = pcall(f, "abc")
			local ok2, b = pcall(f, "abd")
			local ok3, c = pcall(f, "abc")
			if ok1 and ok2 and ok3 and type(a) == "string" and #a >= 16 and a ~= b and a == c then
				HASHFN = f
				break
			end
		end
	end

	local function hash(s)
		if HASHFN then
			local ok, h = pcall(HASHFN, s)
			if ok and type(h) == "string" then return h end
		end
		return fastKey(s)
	end

	local function normKey(src)
		local s = src:sub(1, 120000)
		s = s:gsub("[%w%+/=_%-]+", function(w)
			if #w >= 40 then return "B" end
		end)
		s = s:gsub("%d%d%d%d%d+", "N")
		s = s:gsub("%s+", "")
		return hash(s) .. ":" .. floor(math.log(#src + 1, 2) * 2)
	end

	local function urlKey(url)
		if type(url) ~= "string" or url == "" then return nil end
		local id = url:match("script_id=([%w_%-]+)") or url:match("/loaders/([%w]+)") or url:match("/files/[%w]+/([%w]+)%.lua")
		if id then return "id:" .. id end
		return (url:gsub("[%?#].*$", ""))
	end

	local CDIR = PATH.dir .. "/.cache"
	local cacheOk = false
	if PATH.ok and type(makefolder) == "function" and type(isfolder) == "function" then
		pcall(function()
			if not isfolder(CDIR) then makefolder(CDIR) end
			cacheOk = isfolder(CDIR)
		end)
	end

	local IDXP = PATH.f(".index.json")
	local IDX = { hashes = {}, urls = {}, norm = {}, cache = {}, sess = {}, sessL = {}, dirty = false, diffs = 0, seen = 0, vars = 0 }
	do
		local txt = FS.read(IDXP)
		local t = type(txt) == "string" and F.dec(txt) or nil
		if type(t) == "table" then
			for _, k in ipairs({ "hashes", "urls", "norm", "cache" }) do
				if type(t[k]) == "table" then IDX[k] = t[k] end
			end
		end
	end

	local function cpath(uk)
		local h = 5381
		for i = 1, #uk do h = (h * 33 + byte(uk, i)) % 4294967291 end
		return CDIR .. "/" .. string.format("%08x", h) .. ".lua"
	end

	local function cacheGet(uk)
		if not cacheOk then return nil end
		return FS.read(cpath(uk))
	end

	local function cachePut(uk, src)
		if not cacheOk or #src > 200000 then return end
		local p = cpath(uk)
		if not FS.write(p, src) then return end
		IDX.cache[p] = os.time()
		local n, oldest, ot = 0, nil, math.huge
		for k, t in pairs(IDX.cache) do
			n = n + 1
			if t < ot then oldest, ot = k, t end
		end
		if n > 60 and oldest and oldest ~= p then
			FS.del(oldest)
			IDX.cache[oldest] = nil
		end
	end

	local function trim(t, cap)
		local n = 0
		for _ in pairs(t) do n = n + 1 end
		if n <= cap then return end
		local arr = {}
		for k, v in pairs(t) do arr[#arr + 1] = { k, type(v) == "table" and (v.t or 0) or 0 } end
		table.sort(arr, function(a, b) return a[2] > b[2] end)
		local keep = {}
		for i = 1, floor(cap * 0.7) do keep[arr[i][1]] = true end
		for k in pairs(t) do
			if not keep[k] then t[k] = nil end
		end
	end

	local function saveIndex()
		if not IDX.dirty then return end
		trim(IDX.hashes, 6000)
		trim(IDX.norm, 4000)
		trim(IDX.urls, 2000)
		local js = F.enc({ hashes = IDX.hashes, urls = IDX.urls, norm = IDX.norm, cache = IDX.cache })
		if js and FS.write(IDXP, js) then IDX.dirty = false end
	end
	F.saveIdx = saveIndex

	local lastIdx = 0
	F.onTick(function(now)
		if IDX.dirty and now - lastIdx >= 20 then
			lastIdx = now
			saveIndex()
		end
	end)

	local function splitLines(s)
		local t, n = {}, 0
		for line in (s .. "\n"):gmatch("([^\n]*)\n") do
			n = n + 1
			t[n] = line
			if n % 400 == 0 and F.Y then F.Y() end
		end
		return t
	end

	local function structDelta(a, b)
		if not F.structure then return nil end
		local sa, sb = F.structure(a), F.structure(b)
		local out = {}
		local function cmp(kind, x, y)
			local add, rem = {}, {}
			for k in pairs(y) do
				if not x[k] then add[#add + 1] = k end
			end
			for k in pairs(x) do
				if not y[k] then rem[#rem + 1] = k end
			end
			table.sort(add)
			table.sort(rem)
			out[#out + 1] = string.format("%s: +%d -%d", kind, #add, #rem)
			for i = 1, math.min(#add, 20) do out[#out + 1] = "  + " .. add[i] end
			for i = 1, math.min(#rem, 20) do out[#out + 1] = "  - " .. rem[i] end
		end
		cmp("functions", sa.fn, sb.fn)
		cmp("names/urls", sa.nm, sb.nm)
		return table.concat(out, "\n")
	end

	local function queueDiff(oldSrc, ent, newSrc, url)
		if not F.job or #oldSrc > 400000 or #newSrc > 400000 then return end
		F.job("diff", function()
			local a, b = splitLines(oldSrc), splitLines(newSrc)
			local ca, cb = {}, {}
			for i = 1, #a do ca[a[i]] = (ca[a[i]] or 0) + 1 end
			F.Y()
			for i = 1, #b do cb[b[i]] = (cb[b[i]] or 0) + 1 end
			F.Y()
			local ra, rb = {}, {}
			for k, v in pairs(cb) do ra[k] = v end
			for k, v in pairs(ca) do rb[k] = v end
			local rem, add, nr, na = {}, {}, 0, 0
			for i = 1, #a do
				local l = a[i]
				local av = ra[l]
				if av and av > 0 then
					ra[l] = av - 1
				else
					nr = nr + 1
					if nr <= 60 then rem[#rem + 1] = string.format("%5d: %s", i, l:sub(1, 140)) end
				end
				if i % 500 == 0 then F.Y() end
			end
			for i = 1, #b do
				local l = b[i]
				local av = rb[l]
				if av and av > 0 then
					rb[l] = av - 1
				else
					na = na + 1
					if na <= 60 then add[#add + 1] = string.format("%5d: %s", i, l:sub(1, 140)) end
				end
				if i % 500 == 0 then F.Y() end
			end
			local out = { string.format("old %d lines, new %d lines, removed %d, added %d", #a, #b, nr, na) }
			local sd = structDelta(oldSrc, newSrc)
			if sd then out[#out + 1] = sd end
			out[#out + 1] = "--- removed"
			for i = 1, #rem do out[#out + 1] = rem[i] end
			out[#out + 1] = "--- added"
			for i = 1, #add do out[#out + 1] = add[i] end
			return table.concat(out, "\n")
		end, function(text)
			if type(text) ~= "string" then return end
			if D.diffN < 20 then
				D.diffN = D.diffN + 1
				D.diffs[#D.diffs + 1] = { id = ent.id, f = ent.f, url = url, text = text:sub(1, 5000) }
			end
			IDX.diffs = IDX.diffs + 1
			X.dirty = true
		end)
	end

	local baseAdd = D.add
	D.add = function(src, tag, url, parent, id)
		local ent = baseAdd(src, tag, url, parent, id)
		if not (ent and not ent.dup and type(src) == "string") then return ent end
		local ok, err = pcall(function()
			local h = hash(src)
			ent.h = h
			local prev = IDX.hashes[h]
			if prev then
				ent.seenBefore = prev.s
				IDX.seen = IDX.seen + 1
			else
				IDX.hashes[h] = { s = PATH.tag, t = os.time() }
			end
			local nk = normKey(src)
			local b = IDX.norm[nk]
			if b and b.h ~= h then
				ent.variantOf = b.id
				IDX.vars = IDX.vars + 1
			elseif not b then
				IDX.norm[nk] = { h = h, id = ent.id, s = PATH.tag, t = os.time() }
			end
			local uk = urlKey(url)
			if uk then
				local pu = IDX.urls[uk]
				if pu and pu.h ~= h then
					ent.changed = true
					local oldSrc = IDX.sess[uk] or cacheGet(uk)
					if oldSrc then queueDiff(oldSrc, ent, src, url) end
				end
				if not pu or pu.h ~= h then
					cachePut(uk, src)
					IDX.urls[uk] = { h = h, s = PATH.tag, t = os.time() }
				end
				if not IDX.sess[uk] then
					IDX.sessL[#IDX.sessL + 1] = uk
					if #IDX.sessL > 40 then IDX.sess[table.remove(IDX.sessL, 1)] = nil end
				end
				IDX.sess[uk] = src
			end
			IDX.dirty = true
		end)
		if not ok then noteErr(err) end
		return ent
	end

	local spoolBytes = 0
	local function spoolAppend(f, body)
		if type(appendfile) ~= "function" or spoolBytes > STORE_MAX then return end
		local kind = "raw"
		if F.isBin and F.isBin(body) then
			kind = "b64"
			body = F.b64enc and F.b64enc(body) or ""
		end
		spoolBytes = spoolBytes + #body
		pcall(appendfile, PATH.spool, string.format("\n##ALUZ-DUMP|%s|%d|%s\n", f, #body, kind) .. body .. "\n##ALUZ-END\n")
	end

	function F.spoolReset()
		spoolBytes = 0
		FS.del(PATH.spool)
	end

	if HAS_W and FS.exists(PATH.spool) then
		F.trace("spool recovery start")
		local data = FS.read(PATH.spool)
		if type(data) == "string" and #data > 40 then
			local out, n, pos = { "-- AluzSpy recovered dumps from a crashed session. Not runnable: scripts are separated by '-- =====' lines." }, 0, 1
			while true do
				local s, e, f, len, kind = data:find("\n##ALUZ%-DUMP|([^|\n]+)|(%d+)|(%w+)\n", pos)
				if not s then break end
				len = tonumber(len)
				local body = data:sub(e + 1, e + len)
				n = n + 1
				out[#out + 1] = "-- ===== recovered " .. f .. " | " .. len .. "b | " .. kind .. " ====="
				if kind == "b64" then
					out[#out + 1] = "--[==[BASE64\n" .. body .. "\n]==]"
				else
					out[#out + 1] = body
				end
				pos = e + len + 1
			end
			if n > 0 then
				local name = PATH.f("Recovered_" .. os.date("%Y%m%d_%H%M%S") .. ".lua")
				if FS.write(name, table.concat(out, "\n")) then F.recoveredFile = name end
			end
		end
		FS.del(PATH.spool)
		F.trace("spool recovery done")
	end

	D.writeOne = function()
		if D.h > D.t then return false end
		local it = D.q[D.h]
		D.q[D.h] = nil
		D.h = D.h + 1
		local f, n = it.f, #it.s
		D.pending = D.pending - n
		if f:find("%.dec%.lua$") or f:find("%.diff%.txt$") or f:find("%.sandbox%.txt$") or f:find("%.report%.txt$") then
			return true
		end
		if D.storeBytes + n <= STORE_MAX then
			D.store[f] = it.s
			D.storeBytes = D.storeBytes + n
			spoolAppend(f, it.s)
		elseif pcall(writefile, PATH.d(f), it.s) then
			D.spilled[f] = n
		else
			D.fail = D.fail + 1
		end
		D.dirtyDump = true
		X.dirty = true
		return true
	end

	local baseRead = FS.read
	local pfx = PATH.ok and (PATH.dumpDir .. "/") or "AluzDump_"
	FS.read = function(name)
		local v = baseRead(name)
		if v ~= nil then return v end
		if type(name) == "string" and name:sub(1, #pfx) == pfx then return D.store[name:sub(#pfx + 1)] end
		return nil
	end

	F.api.split = function() return false end
	F.api.saveIndex = saveIndex

	F.extra.dump2 = function()
		return {
			hash = HASHFN ~= nil, store_mb = floor(D.storeBytes / 1048576), spilled = next(D.spilled) ~= nil,
			seen_before = IDX.seen, variants = IDX.vars, diffs = IDX.diffs,
		}
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okD2 then
	warn("[AluzSpy] dump2 failed: " .. tostring(errD2))
end
