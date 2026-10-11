do
	local SAMPLE = { 6, 12, 24 }
	local FLOOD = { 70, 40, 25 }
	local LOOPMIN = { 20, 12, 8 }

	local function spamClass(st, kind)
		local key = st.dir .. "|" .. st.full
		local c = X.spam[key]
		if not c then
			c = { r = st.full, d = st.dir, kind = kind, peak = 0, sup = 0, mutes = 0 }
			X.spam[key] = c
		end
		c.kind = kind
		return c
	end

	local function muteRemote(inst, st, dir, rate, why, now)
		local ttl = 5 * (2 ^ math.min(st.mutes, 3))
		st.mutes = st.mutes + 1
		local base = st.nsig >= 8 and 25 or 80
		local every = base * (X.load + 1)
		local mu = {
			key = inst, st = st, dir = dir, every = every, c = 0, lc = 0,
			t0 = now, exp = now + ttl, why = why, peak = rate, sup = 0,
		}
		if dir == "S2C" then mutedS[inst] = mu else mutedC[inst] = mu end
		st.mu = mu
		muteList[#muteList + 1] = mu
		local c = spamClass(st, why)
		if rate > c.peak then c.peak = rate end
		newRec("SPM", st.full, "mute", {
			why, string.format("%.0f/s", rate), "ttl " .. ttl .. "s", "1/" .. every,
		}, now)
	end

	function F.releaseMute(mu, idx, now, rate)
		if mu.dir == "S2C" then mutedS[mu.key] = nil else mutedC[mu.key] = nil end
		mu.st.mu = nil
		mu.st.ema = rate
		table.remove(muteList, idx)
		local c = spamClass(mu.st, mu.why)
		c.sup = c.sup + mu.sup
		c.mutes = c.mutes + 1
		newRec("SPM", mu.st.full, "unmute", {
			"suppressed " .. mu.sup, "dur " .. floor(now - mu.t0) .. "s", "peak " .. floor(mu.peak) .. "/s",
		}, now)
	end

	function F.spamList()
		local out = {}
		for _, c in pairs(X.spam) do
			out[#out + 1] = { r = c.r, d = c.d, kind = c.kind, peak = r2(c.peak), suppressed = c.sup, mutes = c.mutes }
		end
		table.sort(out, function(a, b) return a.suppressed > b.suppressed end)
		for i = #out, 51, -1 do out[i] = nil end
		return out
	end

	local function emit(st, e, strs, n, key, now, mode, samp)
		local rec = st.rec
		if (mode == "merge" or mode == "sample") and rec and rec.live and rec.sg == key and now - rec.t0 < WIN then
			rec.n = rec.n + 1
			rec.tl = r2(now - T0)
			st.merged = st.merged + 1
			N.merged = N.merged + 1
			X.dirty = true
			return
		end
		if mode == "sample" then
			st.sc = st.sc + 1
			if st.sc % samp ~= 0 then
				N.sampled = N.sampled + 1
				st.smp = st.smp + 1
				return
			end
		end
		if not takeToken(now) then
			N.bucket = N.bucket + 1
			return
		end
		local cname = nil
		if e.sc then
			local ok, v = pcall(function() return e.sc.Name end)
			if ok then cname = clean(tostring(v)) end
		end
		local rec2 = newRec(st.dir, st.full, e.m, strs, now, e.ex, cname)
		rec2.sg = key
		if e.d == "C2S" and CFG.code and e.a then
			local ok, code = pcall(F.replay, e.s, e.m, e.a)
			if ok then rec2.code = code end
		end
		if e.sc and CFG.callerDump and not e.ex then
			rec2.sref = e.sc
			F.callerDump(e.sc)
		end
		st.rec = rec2
		st.logged = st.logged + 1
		e.rec = rec2
	end

	F.h[1] = function(e, now)
		local inst = e.s
		if typeof(inst) ~= "Instance" then return end
		local dir = e.d
		local reg = dir == "S2C" and stS or stC
		local st = reg[inst]
		local first = false
		if not st then
			local i = getInfo(inst)
			if dir == "C2S" then
				local c = i.cls
				if e.m == "FireServer" then
					if c ~= "RemoteEvent" and c ~= "UnreliableRemoteEvent" then return end
				elseif c ~= "RemoteFunction" then
					return
				end
			end
			st = {
				nm = i.nm, full = i.full, dir = dir, m = e.m,
				n = 0, wc = 0, ws = now, ema = 0, peak = 0, lt = now, mi = 0, md = 0,
				rep = 0, ls = "", win = {}, nsig = 0, seen = {}, nseen = 0,
				shapes = {}, nshape = 0, shapeSeen = {}, nshapeSeen = 0, mean = 0, vr = 0, ticks = 0,
				logged = 0, merged = 0, smp = 0, sc = 0, supp = 0, mutes = 0, ret = false,
			}
			reg[inst] = st
			N.remotes = N.remotes + 1
			first = true
		end
		e.st = st
		N.total = N.total + 1
		st.n = st.n + 1
		st.wc = st.wc + 1
		if not st.act then
			st.act = true
			act[#act + 1] = st
		end
		local dt = now - st.lt
		st.lt = now
		if st.n > 2 and dt >= 0 and dt < 3 then
			st.mi = st.mi * 0.8 + dt * 0.2
			st.md = st.md * 0.8 + math.abs(dt - st.mi) * 0.2
		end
		local strs, n = packStr(e.a, 4)
		local sig = n .. "\31" .. table.concat(strs, "\31", 1, math.min(#strs, 3))
		local shape = (sig:gsub("%-?%d+%.?%d*", "#"))
		if sig == st.ls then
			st.rep = st.rep + 1
		else
			st.rep = 0
			st.ls = sig
		end
		if not st.win[sig] and st.nsig < 16 then
			st.win[sig] = true
			st.nsig = st.nsig + 1
		end
		if not st.shapes[shape] and st.nshape < 16 then
			st.shapes[shape] = true
			st.nshape = st.nshape + 1
		end
		local isNew, newShape = false, false
		if not st.seen[sig] and st.nseen < 24 then
			st.seen[sig] = true
			st.nseen = st.nseen + 1
			isNew = true
		end
		if not st.shapeSeen[shape] and st.nshapeSeen < 24 then
			st.shapeSeen[shape] = true
			st.nshapeSeen = st.nshapeSeen + 1
			newShape = true
		end
		local L = X.load
		if st.mu then
			emit(st, e, strs, n, sig, now, "smp", 1)
			e.a = nil
			return
		end
		local el = now - st.ws
		if el < 0.25 then el = 0.25 end
		local rate = st.wc / el
		if st.ema > rate then rate = st.ema end
		if rate > st.peak then st.peak = rate end
		local score = 0
		if first then score = score + 4 end
		if isNew then score = score + 3 end
		if newShape then score = score + 2 end
		if st.ret then score = score + 3 end
		if rate < 2 then score = score + 2 end
		local prot = score >= 4
		local periodic = st.n >= 10 and st.mi > 0 and (st.md / st.mi) < 0.3
		local stream = st.nsig >= 8 and st.nshape <= 2
		local z = 0
		if st.ticks >= 5 then z = (rate - st.mean) / (math.sqrt(st.vr) + 1) end
		if not prot then
			local kind = nil
			if rate >= FLOOD[L + 1] then
				kind = "flood"
			elseif rate >= LOOPMIN[L + 1] and st.rep >= 5 and (periodic or st.rep >= 12) then
				kind = "loop"
			elseif rate >= LOOPMIN[L + 1] + 5 and z > 4 and not stream then
				kind = "burst"
			end
			if kind then
				emit(st, e, strs, n, sig, now, "all", 1)
				muteRemote(inst, st, dir, rate, kind, now)
				e.a = nil
				return
			end
		end
		local mode, key
		if prot or rate < 6 then
			mode, key = "all", sig
		elseif stream then
			mode, key = "sample", shape
		elseif rate < 20 then
			mode, key = "merge", sig
		else
			mode, key = "sample", sig
		end
		if L == 2 and dir == "S2C" and not prot and rate >= 6 then
			N.sampled = N.sampled + 1
			e.a = nil
			return
		end
		emit(st, e, strs, n, key, now, mode, SAMPLE[L + 1])
		e.a = nil
	end

	F.h[2] = function(e)
		local ent = e.r
		if not ent then return end
		if ent.st then ent.st.ret = true end
		local rec = ent.rec
		if rec and rec.live then
			rec.ret = packStr(e.v, 3)
		end
	end

	F.onTick(function(now, dt)
		local nl = {}
		for i = 1, #act do
			local st = act[i]
			local el = now - st.ws
			if el < 0.5 then el = 0.5 end
			local rate = st.wc / el
			if not st.mu then
				local d = rate - st.mean
				st.mean = st.mean + 0.1 * d
				st.vr = 0.9 * (st.vr + 0.1 * d * d)
				st.ticks = st.ticks + 1
			end
			st.ema = st.ema * 0.5 + rate * 0.5
			st.wc = 0
			st.ws = now
			st.win = {}
			st.nsig = 0
			st.shapes = {}
			st.nshape = 0
			if st.ema > 0.3 or st.mu then
				nl[#nl + 1] = st
			else
				st.act = false
				st.ema = 0
			end
		end
		act = nl
		for i = #muteList, 1, -1 do
			local mu = muteList[i]
			local c = mu.c
			local dc = c - mu.lc
			mu.lc = c
			local pushedNow = floor(c / mu.every) - floor((c - dc) / mu.every)
			local sk = dc - pushedNow
			if sk < 0 then sk = 0 end
			N.total = N.total + sk
			N.supp = N.supp + sk
			mu.st.supp = mu.st.supp + sk
			mu.sup = mu.sup + sk
			local rate = dc / dt
			if rate > mu.peak then mu.peak = rate end
			if now >= mu.exp then
				if rate < 15 then
					F.releaseMute(mu, i, now, rate)
				else
					mu.exp = now + 3
				end
			end
		end
		local L = 0
		if X.fps < 30 or X.memNow > K.MEM_ABS * 0.7 then L = 1 end
		if X.fps < 15 or X.memNow > K.MEM_ABS * 0.9 then L = 2 end
		X.load = L
	end)
end
