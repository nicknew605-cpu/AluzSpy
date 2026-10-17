do local _ = "aluzspy@1.2.2-max" if F and F.trace then F.trace("load hooks2") end end
local okHX, errHX = xpcall(function()
	MOD.hx = false
	INST.hx = false
	F.defMods.hx = true
	if CFG.mods.hx == nil then CFG.mods.hx = true end
	local HX = { net = 0, sys = 0, mode = "exec" }
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
	IN.hx = function()
		if INST.hx then
			MOD.hx = true
			return true
		end
		for i = 1, #EXEC do pcall(hookExec, EXEC[i]) end
		pcall(hookFile, "loadfile")
		pcall(hookFile, "dofile")
		INST.hx = true
		MOD.hx = true
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
