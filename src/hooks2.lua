do local _ = "aluzspy@1.2.2-max" if F and F.trace then F.trace("load hooks2") end end
local okHX, errHX = xpcall(function()
	MOD.hx = false
	INST.hx = false
	F.defMods.hx = true
	if CFG.mods.hx == nil then CFG.mods.hx = true end
	local HX = { net = 0, sys = 0, mode = "chain" }
	local EXTRA = {
		GetObjects = true, LoadAsset = true, LoadAssetVersion = true,
		PromptPurchase = true, PromptProductPurchase = true, PromptGamePassPurchase = true,
		PromptBundlePurchase = true, PromptPremiumPurchase = true, PromptSubscriptionPurchase = true,
		PerformPurchase = true, OpenBrowserWindow = true, OpenNativeOverlay = true, PromptGameInvite = true,
		InsertService = true,
	}
	local NETM = {
		HttpGet = true, HttpGetAsync = true, HttpPost = true, HttpPostAsync = true,
		GetAsync = true, PostAsync = true, RequestAsync = true,
	}
	local EXEC = {
		"firesignal", "fireclickdetector", "fireproximityprompt",
		"firetouchinterest", "replicatesignal",
	}
	local recs, rn = {}, 0
	F.h[8] = function(e, now)
		local strs = packStr(e.a, 3)
		local key = tostring(e.tag) .. "|" .. table.concat(strs, "|")
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
		if type(genv[name]) ~= "function" then return end
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
		if type(genv[name]) ~= "function" then return end
		F.hookWith(genv[name], function(holder)
			return function(path, ...)
				if MOD.hx and alive and not busy and type(path) == "string" and not path:find("AluzSpy", 1, true) then
					local prev = busy
					busy = true
					local ok, body = pcall(readfile, path)
					busy = prev
					if ok and type(body) == "string" and #body >= 16 then
						pcall(F.capSrc, name, body, nil, X.cof[coroutine.running()], path)
					end
				end
				return holder.old(path, ...)
			end
		end, false)
	end
	local function hxExtra(self, m, ...)
		if not m then return false end
		if NETM[m] then
			setnm(m)
			local r = pack(oldNc(self, ...))
			pcall(function()
				local a = pack(...)
				local url = a[1]
				if type(url) == "table" then url = url.Url or url.url end
				if F.capNet then F.capNet("hx:" .. tostring(m), url, m, r[1]) end
				HX.net = HX.net + 1
			end)
			return true, unpack(r, 1, r.n)
		end
		if EXTRA[m] then
			pcall(function()
				if F.capSys then F.capSys(self, "x:" .. m, ...) end
				HX.sys = HX.sys + 1
			end)
			return false
		end
		return false
	end
	IN.hx = function()
		if INST.hx then
			MOD.hx = true
			return true
		end
		F.ncExtras = F.ncExtras or {}
		local already = false
		for i = 1, #F.ncExtras do
			if F.ncExtras[i] and F.ncExtras[i].mod == "hx" then already = true break end
		end
		if not already then
			F.ncExtras[#F.ncExtras + 1] = { mod = "hx", fn = hxExtra }
		end
		for i = 1, #EXEC do pcall(hookExec, EXEC[i]) end
		pcall(hookFile, "loadfile")
		pcall(hookFile, "dofile")
		INST.hx = true
		MOD.hx = true
		HX.mode = "chain"
		return true
	end
	F.stage("hx", 13, IN.hx)
	F.extra.hooks2 = function()
		return { net = HX.net, sys = HX.sys, enabled = MOD.hx, installed = INST.hx, mode = HX.mode }
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)
if not okHX then
	warn("[AluzSpy] hooks2 module failed: " .. tostring(errHX))
end
