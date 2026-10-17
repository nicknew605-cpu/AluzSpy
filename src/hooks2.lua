local okHX, errHX = xpcall(function()
	MOD.hx = false
	INST.hx = false
	F.defMods.hx = true
	if CFG.mods.hx == nil then CFG.mods.hx = true end

	local HX = { net = 0, sys = 0 }
	local EXTRA = {
		GetObjects = true, LoadAsset = true, LoadAssetVersion = true,
		PromptPurchase = true, PromptProductPurchase = true, PromptGamePassPurchase = true,
		PromptBundlePurchase = true, PromptPremiumPurchase = true, PromptSubscriptionPurchase = true,
		PerformPurchase = true, OpenBrowserWindow = true, OpenNativeOverlay = true, PromptGameInvite = true,
	}
	local NETM = {
		Http
	}
	local EXEC = { "firesignal", "fireclickdetector", "fireproximityprompt", "firetouchinterest", "replicatesignal" }

	local recs, rn = {}, 0
	F.h[8] = function(e, now)
		local strs = packStr(e.a, 3)
		local key = e.tag .. "|" .. table.concat(strs, "\31")
		local rec = recs[key]
		if rec and rec.live and now - rec.t0 < WIN then
			rec.n = rec.n + 1
			N.merged = N.merged + 1
			return
		end
		if not takeToken(now) then
			N.bucket = N.bucket + 1
			return
		end
		recs[key] = newRec("SYS", "exec", e.tag, strs, now)
		rn = rn + 1
		if rn > 200 then
			recs = {}
			rn = 0
		end
	end

	local function hookExec(name)
		F.hookWith(genv[name], function(holder)
			return function(...)
				if MOD.hx and alive and not busy then
					enqueue({ k = 8, tag = name, a = pack(...), t = clock() })
				end
				return holder.old(...)
			end
		end, true)
	end

	local function hookFile(name)
		F.hookWith(genv[name], function(holder)
			return function(path, ...)
				if MOD.hx and alive and not busy and type(path) == "string" and not path:find("^AluzSpy") then
					local prev = busy
					busy = true
					local ok, body = pcall(readfile, path)
					busy = prev
					if ok and type(body) == "string" and #body >= 24 then
						pcall(F.capSrc, name, body, nil, X.cof[coroutine.running()], path)
					end
				end
				return holder.old(path, ...)
			end
		end, false)
	end

	IN.hx = function()
		if INST.hx then
			MOD.hx = true
			return true
		end
		if not (hookmetamethod and getnm) then return false end
		local old
		local ok, o = pcall(hookmetamethod, game, "__namecall", nc(function(self, ...)
			local m = getnm()
			if MOD.hx and alive and not busy and m then
				if NETM[m] then
					setnm(m)
					local r = pack(old(self, ...))
					pcall(function()
						local a = pack(...)
						local url = a[1]
						if type(url) == "table" then url = url.Url or url.url end
						if F.capNet then F.capNet("nc:" .. tostring(m), url, m, r[1]) end
						HX.net = HX.net + 1
					end)
					return unpack(r, 1, r.n)
				elseif EXTRA[m] then
					pcall(function()
						if F.capSys then F.capSys(self, "x:" .. m, ...) end
						HX.sys = HX.sys + 1
					end)
				end
			end
			setnm(m)
			return old(self, ...)
		end))
		if not ok or type(o) ~= "function" then return false end
		old = o
		INST.hx = true
		MOD.hx = true
		for i = 1, #EXEC do pcall(hookExec, EXEC[i]) end
		pcall(hookFile, "loadfile")
		pcall(hookFile, "dofile")
		return true
	end

	F.stage("hx", 13, IN.hx)

	F.extra.hooks2 = function()
		return { net = HX.net, sys = HX.sys, enabled = MOD.hx, installed = INST.hx }
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okHX then
	warn("[AluzSpy] hooks2 module failed: " .. tostring(errHX))
end
