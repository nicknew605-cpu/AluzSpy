local okD2, errD2 = xpcall(function()
	if not F.job then return end

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

	local IDXP = PATH.d("index.json")
	local IDX = { hashes = {}, urls = {}, dirty = false, cross = 0, diffs = 0, lz = 0 }
	do
		local txt = FS.read(IDXP)
		local t = type(txt) == "string" and F.dec(txt) or nil
		if type(t) == "table" then
			if type(t.hashes) == "table" then IDX.hashes = t.hashes end
			if type(t.urls) == "table" then IDX.urls = t.urls end
		end
	end

	local function saveIndex()
		if not IDX.dirty then return end
		local n = 0
		for _ in pairs(IDX.hashes) do n = n + 1 end
		if n > 6000 then
			local arr = {}
			for h, r in pairs(IDX.hashes) do arr[#arr + 1] = { h, r.t or 0 } end
			table.sort(arr, function(a, b) return a[2] > b[2] end)
			local keep = {}
			for i = 1, 4000 do keep[arr[i][1]] = IDX.hashes[arr[i][1]] end
			IDX.hashes = keep
		end
		local js = F.enc({ hashes = IDX.hashes, urls = IDX.urls })
		if js and FS.write(IDXP, js) then IDX.dirty = false end
	end
	F.saveIdx = saveIndex

	local lastSave = 0
	F.onTick(function(now)
		if IDX.dirty and now - lastSave >= 20 then
			lastSave = now
			saveIndex()
		end
	end)

	local function emitFile(name, text)
		D.pending = D.pending + #text
		D.t = D.t + 1
		D.q[D.t] = { f = name, s = text }
	end

	local function splitLines(s)
		local t, n = {}, 0
		for line in (s .. "\n"):gmatch("([^\n]*)\n") do
			n = n + 1
			t[n] = line
			if n % 400 == 0 then F.Y() end
		end
		return t
	end

	local function queueDiff(prevF, ent, src, url)
		if #src > 400000 then return end
		local oldTxt = FS.read(PATH.d(prevF))
		if type(oldTxt) ~= "string" or #oldTxt > 400000 then return end
		F.job("diff", function()
			local a, b = splitLines(oldTxt), splitLines(src)
			local ca, cb = {}, {}
			for i = 1, #a do ca[a[i]] = (ca[a[i]] or 0) + 1 end
			F.Y()
			for i = 1, #b do cb[b[i]] = (cb[b[i]] or 0) + 1 end
			F.Y()
			local remAvail, addAvail = {}, {}
			for k, v in pairs(cb) do remAvail[k] = v end
			for k, v in pairs(ca) do addAvail[k] = v end
			local removed, added, nr, na = {}, {}, 0, 0
			for i = 1, #a do
				local l = a[i]
				local av = remAvail[l]
				if av and av > 0 then
					remAvail[l] = av - 1
				else
					nr = nr + 1
					if nr <= 300 then removed[#removed + 1] = string.format("%5d: %s", i, l:sub(1, 200)) end
				end
				if i % 500 == 0 then F.Y() end
			end
			for i = 1, #b do
				local l = b[i]
				local av = addAvail[l]
				if av and av > 0 then
					addAvail[l] = av - 1
				else
					na = na + 1
					if na <= 300 then added[#added + 1] = string.format("%5d: %s", i, l:sub(1, 200)) end
				end
				if i % 500 == 0 then F.Y() end
			end
			local out = {
				"AluzSpy script diff",
				"url: " .. tostring(url),
				"old: " .. prevF .. " (" .. #a .. " lines)",
				"new: " .. ent.f .. " (" .. #b .. " lines)",
				"removed " .. nr .. ", added " .. na,
				"--- removed",
			}
			for i = 1, #removed do out[#out + 1] = removed[i] end
			out[#out + 1] = "--- added"
			for i = 1, #added do out[#out + 1] = added[i] end
			return table.concat(out, "\n")
		end, function(text)
			if type(text) ~= "string" then return end
			local name = ent.f:gsub("%.lua$", "") .. ".diff.txt"
			emitFile(name, text)
			IDX.diffs = IDX.diffs + 1
			newRec("SYS", "script-changed", "diff", { tostring(url):sub(1, 120), "-> " .. name }, clock())
		end)
	end

	local baseAdd = D.add
	D.add = function(src, tag, url, parent, id)
		if not (CFG.hash and HASHFN and S.dump and HAS_W) or type(src) ~= "string" or #src < 16 then
			return baseAdd(src, tag, url, parent, id)
		end
		local okh, h = pcall(HASHFN, src)
		if not okh or type(h) ~= "string" then
			return baseAdd(src, tag, url, parent, id)
		end
		local rec = IDX.hashes[h]
		if rec and rec.f and FS.exists(PATH.d(rec.f)) then
			IDX.cross = IDX.cross + 1
			rec.n = (rec.n or 1) + 1
			IDX.dirty = true
			return { id = id or 0, f = rec.f, tag = tag, url = url, bytes = #src, dup = rec.f, hash = h, cross = true, parent = parent }
		end
		local ent = baseAdd(src, tag, url, parent, id)
		if ent and not ent.dup then
			IDX.hashes[h] = { f = ent.f, tag = tag, url = url, bytes = #src, t = os.time(), n = 1 }
			if type(url) == "string" and url ~= "" then
				local prev = IDX.urls[url]
				if prev and prev.hash ~= h and prev.f then queueDiff(prev.f, ent, src, url) end
				IDX.urls[url] = { hash = h, f = ent.f }
			end
			IDX.dirty = true
		end
		return ent
	end

	local baseWrite = D.writeOne
	D.writeOne = function()
		if CFG.lz4 and type(lz4compress) == "function" then
			local it = D.q[D.h]
			if it and not it.lz and #it.s > 262144 then
				local old = #it.s
				local ok, c = pcall(lz4compress, it.s)
				if ok and type(c) == "string" and #c < old then
					it.s = "ALUZLZ4:" .. old .. "\n" .. c
					it.f = it.f .. ".lz4"
					it.lz = true
					D.pending = D.pending - old + #it.s
					IDX.lz = IDX.lz + 1
				end
			end
		end
		return baseWrite()
	end

	F.api.unlz4 = function(name)
		if type(lz4decompress) ~= "function" then return nil, "no lz4decompress" end
		local data = FS.read(PATH.d(name))
		if not data then return nil, "no file" end
		local size, body = data:match("^ALUZLZ4:(%d+)\n(.*)$")
		if not size then return nil, "not an AluzSpy lz4 file" end
		local ok, raw = pcall(lz4decompress, body, tonumber(size))
		if not ok or type(raw) ~= "string" then return nil, tostring(raw) end
		local out = name:gsub("%.lz4$", "")
		FS.write(PATH.d(out), raw)
		return out
	end
	F.api.saveIndex = saveIndex

	F.extra.dump2 = function()
		local n = 0
		for _ in pairs(IDX.hashes) do n = n + 1 end
		return { hash = HASHFN ~= nil, indexed = n, cross_dups = IDX.cross, diffs = IDX.diffs, lz4_files = IDX.lz }
	end

	F.extraChips[#F.extraChips + 1] = { "HASH", function() return CFG.hash end, function(v) CFG.hash = v F.cfgSave() return v end }
	F.extraChips[#F.extraChips + 1] = { "LZ4", function() return CFG.lz4 end, function(v) CFG.lz4 = v F.cfgSave() return v end }
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okD2 then
	warn("[AluzSpy] dump2 failed: " .. tostring(errD2))
end
