do local _ = "aluzspy@1.2.3-stable" if F and F.trace then F.trace("load dumpmax") end end
local okDM, errDM = xpcall(function()
	if type(D) ~= "table" or type(D.add) ~= "function" then return end
	if CFG.autoDeobf == nil then CFG.autoDeobf = true end
	if CFG.dumpSpill == nil then CFG.dumpSpill = true end

	local DM = { spilled = 0, auto = 0, indexed = 0 }
	F.dumpmax = DM

	local baseAdd = D.add
	D.add = function(src, tag, url, parent, id)
		local ent = baseAdd(src, tag, url, parent, id)
		if ent and CFG.autoDeobf and F.deob and F.deob.queue and type(src) == "string" and X.fps > 28 and DM.auto < 120 then
			local isBin = F.isBin and F.isBin(src) or false
			if not isBin then
				task.defer(function()
					if not alive or X.fps < 22 then return end
					if pcall(F.deob.queue, ent, src) then
						DM.auto = DM.auto + 1
					end
				end)
			end
		end
		return ent
	end

	function D.forceSpill(limit)
		limit = tonumber(limit) or 60
		local n = 0
		for f in pairs(D.store or {}) do
			if n >= limit then break end
			D.store[f] = nil
			n = n + 1
		end
		D.storeBytes = 0
		DM.spilled = DM.spilled + n
		return n
	end

	local lastSpill = 0
	F.onTick(function(now)
		if not CFG.dumpSpill then return end
		if now - lastSpill < 2 then return end
		if X.memNow > K.MEM_SOFT then
			lastSpill = now
			task.defer(D.forceSpill, 40)
		end
	end)

	F.api.dumpReport = function()
		local extra = 0
		for _ in pairs(D.extraFiles or {}) do extra = extra + 1 end
		local kinds = {}
		for k, v in pairs(D.kind or {}) do kinds[k] = v end
		local out = {
			dumps = D.n, files = #D.files, pending = D.pending, skipped = D.skipped, fail = D.fail,
			disk = D.bytes or 0, disk_mb = floor((D.bytes or 0) / 1048576),
			quota_mb = floor(K.DISK_TOTAL / 1048576),
			kind = kinds, evicted = N.evict, dupes = N.dup,
			autoDeobfQueued = DM.auto, forcedSpill = DM.spilled,
			extra_files = extra, extra_bytes = D.extraBytes or 0, index = D.indexPath,
		}
		warn("[AluzSpy] dumpReport: " .. tostring(F.enc(out)))
		return out
	end

	local function sourceFor(e)
		local f = e.f or e.file
		if not f then return nil end
		if D.store and type(D.store[f]) == "string" then return D.store[f] end
		if type(readfile) == "function" then
			local ok, body = pcall(readfile, PATH.d(f))
			if ok and type(body) == "string" then return body end
		end
		return nil
	end

	local function collectIndex(reason)
		local recs, seen, total = {}, {}, 0
		for i = 1, #(D.list or {}) do
			local e = D.list[i]
			local f = e and (e.f or e.file)
			if e and f and not e.dup and not seen[f] then
				seen[f] = true
				local bytes = e.bytes or 0
				recs[#recs + 1] = {
					id = e.id, file = f, bytes = bytes, tag = e.tag, url = e.url,
					parent = e.parent, obf = e.obf, hash = e.hash or e.h,
					cat = e.cat, kind = e.kind, changed = e.changed, variantOf = e.variantOf,
					seenBefore = e.seenBefore, t = e.t, fp = e.fp,
				}
				total = total + bytes
			end
		end
		local extra = {}
		for f, n in pairs(D.extraFiles or {}) do extra[#extra + 1] = { file = f, bytes = n } end
		table.sort(extra, function(a, b) return a.file < b.file end)
		return {
			tool = "AluzSpy", version = VERSION or "1.2.3-stable", place = game.PlaceId,
			job = game.JobId, exported = os.date("%Y-%m-%d %H:%M:%S"), reason = reason or "manual",
			scripts = #recs, bytes = total, extra = extra, extra_bytes = D.extraBytes or 0,
			pending = D.pending, skipped = D.skipped, fail = D.fail,
			evicted = N.evict, dupes = N.dup, kind = D.kind,
		}, recs
	end

	function D.writeIndex(reason)
		if not HAS_W then return nil end
		local meta, recs = collectIndex(reason)
		local name = "Index_" .. tostring(game.PlaceId) .. "_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
		local path = PATH.d(name)
		local js = F.enc({ meta = meta, scripts = recs }) or "{}"
		if CFG.redact and F.redact then
			local okr, r = pcall(F.redact, js)
			if okr and type(r) == "string" then js = r end
		end
		if not FS.write(path, js) then return nil end
		local lines = {
			"ALUZSPY DUMP INDEX v" .. tostring(meta.version) .. " place=" .. tostring(meta.place),
			"exported=" .. meta.exported .. " reason=" .. tostring(meta.reason),
			"scripts=" .. meta.scripts .. " bytes=" .. meta.bytes .. " extra=" .. #meta.extra ..
			" evicted=" .. tostring(meta.evicted) .. " dupes=" .. tostring(meta.dupes),
		}
		for _, r in ipairs(recs) do
			lines[#lines + 1] = string.format(
				"%s | %db | kind=%s | tag=%s | obf=%s | url=%s",
				tostring(r.file), r.bytes, tostring(r.kind or "-"), tostring(r.tag), tostring(r.obf or "-"), tostring(r.url or ""):sub(1, 160)
			)
		end
		local txtPath = path:gsub("%.json$", ".txt")
		FS.write(txtPath, table.concat(lines, "\n"))
		for i, d in ipairs(D.diffs or {}) do
			local dname = "Diff_" .. tostring(d.id or i) .. "_" .. i .. ".txt"
			local body = "id=" .. tostring(d.id) .. " file=" .. tostring(d.f) .. " url=" .. tostring(d.url)
				.. "\n\n" .. tostring(d.text or "")
			FS.write(PATH.d(dname), body)
		end
		D.indexPath, D.indexTxt = path, txtPath
		DM.indexed = DM.indexed + 1
		return path
	end

	function D.writeFull(reason)
		if not HAS_W then return nil end
		local meta, recs = collectIndex(reason)
		local parts = {
			"-- AluzSpy FullScripts " .. tostring(VERSION or "1.2.3-stable")
				.. " place=" .. tostring(game.PlaceId) .. " " .. os.date("%Y-%m-%d %H:%M:%S")
				.. " reason=" .. tostring(reason or "manual"),
			"-- all captured script sources this session",
			"",
		}
		local n, total = 0, 0
		for i = 1, #recs do
			local r = recs[i]
			local src = sourceFor({ f = r.file })
			if type(src) == "string" and #src > 0 then
				n = n + 1
				total = total + #src
				parts[#parts + 1] = string.format("-- ===== [%d] %s | %db | kind=%s | tag=%s | url=%s =====",
					n, tostring(r.file), #src, tostring(r.kind or "-"), tostring(r.tag or ""), tostring(r.url or ""):sub(1, 120))
				parts[#parts + 1] = src
				parts[#parts + 1] = ""
			end
		end
		parts[#parts + 1] = string.format("-- END FullScripts count=%d bytes=%d", n, total)
		local name = "FullScripts_" .. tostring(game.PlaceId) .. "_" .. os.date("%Y%m%d_%H%M%S") .. ".lua"
		local path = PATH.d(name)
		local body = table.concat(parts, "\n")
		local wrote = FS.write(path, body)
		local idx = D.writeIndex(reason)
		D.indexPath = idx
		if wrote then
			D.fullPath, D.fullN, D.fullBytes = path, n, total
			return path, n, total, idx
		end
		return nil, n, total, idx
	end

	F.api = F.api or {}
	F.api.fullDump = function()
		local path, n, b, idx = D.writeFull("api")
		warn("[AluzSpy] fullDump: " .. tostring(path) .. " scripts=" .. tostring(n)
			.. " bytes=" .. tostring(b) .. " index=" .. tostring(idx))
		return path, n, b
	end
	F.api.dumpIndex = function()
		local path = D.writeIndex("api")
		warn("[AluzSpy] dumpIndex: " .. tostring(path))
		return path
	end

	F.extra.dumpmax = function()
		return { autoDeobfQueued = DM.auto, forcedSpill = DM.spilled, indexed = DM.indexed }
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okDM then
	warn("[AluzSpy] dumpmax failed: " .. tostring(errDM))
end
