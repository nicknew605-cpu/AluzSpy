local okDM, errDM = xpcall(function()
	if type(D) ~= "table" or type(D.add) ~= "function" then return end
	if CFG.autoDeobf == nil then CFG.autoDeobf = false end
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
		limit = tonumber(limit) or 20
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
		if now - lastSpill < 5 then return end
		if X.memNow > K.MEM_ABS * 0.82 or (D.storeBytes or 0) > 18 * 1024 * 1024 then
			lastSpill = now
			task.defer(D.forceSpill, 10)
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

	F.extra.dumpmax = function()
		return { autoDeobfQueued = DM.auto, forcedSpill = DM.spilled }
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okDM then
	warn("[AluzSpy] dumpmax failed: " .. tostring(errDM))
end
