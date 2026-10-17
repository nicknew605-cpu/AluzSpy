do local _ = "aluzspy@1.2.2-max" if F and F.trace then F.trace("load dumpmax") end end
local okDM, errDM = xpcall(function()
	if type(D) ~= "table" or type(D.add) ~= "function" then return end
	if CFG.autoDeobf == nil then CFG.autoDeobf = true end
	if CFG.dumpSpill == nil then CFG.dumpSpill = true end

	local DM = { spilled = 0, auto = 0 }
	F.dumpmax = DM

	local baseAdd = D.add
	D.add = function(src, tag, url, parent, id)
		local ent = baseAdd(src, tag, url, parent, id)
		if ent and CFG.autoDeobf and F.deob and F.deob.queue and type(src) == "string" then
			local isBin = F.isBin and F.isBin(src) or false
			if not isBin then
				if pcall(F.deob.queue, ent, src) then
					DM.auto = DM.auto + 1
				end
			end
		end
		return ent
	end

	function D.forceSpill(limit)
		if not HAS_W then return 0 end
		limit = tonumber(limit) or 60
		local n = 0
		for f, s in pairs(D.store or {}) do
			if n >= limit then break end
			if type(s) == "string" then
				if pcall(writefile, PATH.d(f), s) then
					D.spilled[f] = #s
					D.storeBytes = math.max(0, (D.storeBytes or 0) - #s)
					D.store[f] = nil
					n = n + 1
				end
			end
		end
		DM.spilled = DM.spilled + n
		return n
	end

	local lastSpill = 0
	F.onTick(function(now)
		if not CFG.dumpSpill then return end
		if now - lastSpill < 2 then return end
		if X.memNow > K.MEM_ABS * 0.75 or (D.storeBytes or 0) > 14 * 1024 * 1024 then
			lastSpill = now
			task.defer(D.forceSpill, 20)
		end
	end)

	F.api.dumpReport = function()
		local out = {
			dumps = D.n, pending = D.pending, skipped = D.skipped, fail = D.fail,
			store_mb = floor((D.storeBytes or 0) / 1048576),
			spilled = next(D.spilled) ~= nil, diffs = D.diffN,
			autoDeobfQueued = DM.auto, forcedSpill = DM.spilled,
		}
		warn("[AluzSpy] dumpReport: " .. tostring(F.enc(out)))
		return out
	end

	
	function D.writeFull(reason)
		if not HAS_W then return nil end
		local parts = {}
		parts[#parts + 1] = "-- AluzSpy FullScripts " .. tostring(VERSION or "1.2.2-max") .. " place=" .. tostring(game.PlaceId) .. " " .. os.date("%Y-%m-%d %H:%M:%S") .. " reason=" .. tostring(reason or "manual")
		parts[#parts + 1] = "-- all captured script sources this session"
		parts[#parts + 1] = ""
		local n = 0
		local total = 0
		for i = 1, #(D.list or {}) do
			local e = D.list[i]
			if e then
				local src = nil
				if type(e.src) == "string" and #e.src > 0 then
					src = e.src
				elseif e.file and D.store and type(D.store[e.file]) == "string" then
					src = D.store[e.file]
				elseif e.file and type(readfile) == "function" then
					local ok, body = pcall(readfile, PATH.d(e.file))
					if ok and type(body) == "string" then src = body end
				end
				if type(src) == "string" and #src > 0 then
					n = n + 1
					total = total + #src
					parts[#parts + 1] = string.format("-- ===== [%d] %s | %db | tag=%s | url=%s =====",
						n, tostring(e.file or e.id or n), #src, tostring(e.tag or ""), tostring(e.url or ""):sub(1, 120))
					parts[#parts + 1] = src
					parts[#parts + 1] = ""
				end
			end
		end
		parts[#parts + 1] = string.format("-- END FullScripts count=%d bytes=%d", n, total)
		local name = "FullScripts_" .. tostring(game.PlaceId) .. "_" .. os.date("%Y%m%d_%H%M%S") .. ".lua"
		local path = PATH.f(name)
		local body = table.concat(parts, "\n")
		if FS.write(path, body) then
			D.fullPath = path
			D.fullN = n
			D.fullBytes = total
			return path, n, total
		end
		return nil
	end

	F.api = F.api or {}
	F.api.fullDump = function()
		local path, n, b = D.writeFull("api")
		warn("[AluzSpy] fullDump: " .. tostring(path) .. " scripts=" .. tostring(n) .. " bytes=" .. tostring(b))
		return path, n, b
	end


	F.extra.dumpmax = function()
		return { autoDeobfQueued = DM.auto, forcedSpill = DM.spilled }
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okDM then
	warn("[AluzSpy] dumpmax failed: " .. tostring(errDM))
end
