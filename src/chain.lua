do local _ = "aluzspy@1.2.2-beta" if F and F.trace then F.trace("load chain") end end
local okCH, errCH = xpcall(function()
	local CH = { nodes = {}, fetches = {}, alerts = 0 }
	F.CH = CH
	local VMN = {
		Luarmor = 1, Luraph = 1, MoonSec = 1, IronBrew = 1, Prometheus = 1, Hercules = 1,
		AstroProtect = 1, Boronide = 1, WeAreDevs = 1, AztupBrew = 1, SynapseXen = 1,
	}

	function F.isBin(s)
		return s:sub(1, 400):find("[\0-\8\14-\31]") ~= nil
	end

	local B64C = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	function F.b64enc(s)
		if type(crypt) == "table" and type(crypt.base64encode) == "function" then
			local ok, r = pcall(crypt.base64encode, s)
			if ok and type(r) == "string" then return r end
		end
		local out, o, byte = {}, 0, string.byte
		for i = 1, #s, 3 do
			local a, b, c = byte(s, i, i + 2)
			local n = a * 65536 + (b or 0) * 256 + (c or 0)
			local i1, i2, i3, i4 = floor(n / 262144), floor(n / 4096) % 64, floor(n / 64) % 64, n % 64
			o = o + 1
			out[o] = B64C:sub(i1 + 1, i1 + 1) .. B64C:sub(i2 + 1, i2 + 1)
				.. (b and B64C:sub(i3 + 1, i3 + 1) or "=") .. (c and B64C:sub(i4 + 1, i4 + 1) or "=")
		end
		return table.concat(out)
	end

	local function count(s, pat)
		local n = 0
		for _ in s:gmatch(pat) do
			n = n + 1
			if n > 500 then break end
		end
		return n
	end

	local lastSrc, lastFp
	function F.fingerprint(src, url)
		if src == lastSrc and lastFp then return lastFp end
		local n = #src
		local head = src:sub(1, 8000)
		local mid = n > 8000 and src:sub(1, math.min(n, 120000)) or head
		local lh = head:lower()
		local sc = {}
		local function add(nm, c, w)
			local s = sc[nm]
			if not s then
				s = { c = 0, w = {} }
				sc[nm] = s
			end
			s.c = s.c + c
			s.w[#s.w + 1] = w
		end
		if lh:find("luarmor", 1, true) then add("Luarmor", 45, "mentions luarmor") end
		if head:find("api%.luarmor%.net") then add("Luarmor", 60, "luarmor api url") end
		if type(url) == "string" and url:lower():find("luarmor", 1, true) then add("Luarmor", 60, "fetched from luarmor") end
		if mid:find("LRM_[%w_]+") then add("Luarmor", 55, "LRM_ globals") end
		if head:find("script_key") and head:find("loadstring", 1, true) then add("Luarmor", 20, "script_key + loadstring") end
		if lh:find("luraph", 1, true) then add("Luraph", 70, "luraph marker") end
		if head:find("LPH[%$%~%@%|%!%?]") then add("Luraph", 60, "LPH_ prefix") end
		if head:find("^%s*return%s*%(?%s*function%s*%(%.%.%.%)") then add("Luraph", 12, "return(function(...) wrapper") end
		if lh:find("prometheus", 1, true) then add("Prometheus", 70, "prometheus marker") end
		if lh:find("ironbrew", 1, true) then add("IronBrew", 80, "ironbrew marker") end
		local k = 0
		for _, w in ipairs({ "Stk", "Instr", "Deserialize", "Upvalues", "Wrap" }) do
			if mid:find(w, 1, true) then k = k + 1 end
		end
		if k >= 4 and n > 6000 then add("IronBrew", 45, "VM structure names (Stk/Instr/Deserialize)") end
		if lh:find("moonsec", 1, true) then add("MoonSec", 80, "moonsec marker") end
		if head:find("local%s+v0%s*=%s*string%.char") or head:find("v0=string%.char") then add("MoonSec", 50, "v0=string.char prologue") end
		if lh:find("wearedevs", 1, true) then add("WeAreDevs", 80, "wearedevs marker") end
		if lh:find("hercules", 1, true) then add("Hercules", 80, "hercules marker") end
		if lh:find("astroprotect", 1, true) or lh:find("astro protect", 1, true) then add("AstroProtect", 80, "astroprotect marker") end
		if lh:find("boronide", 1, true) then add("Boronide", 80, "boronide marker") end
		if lh:find("aztup", 1, true) then add("AztupBrew", 60, "aztup marker") end
		if lh:find("synapse xen", 1, true) then add("SynapseXen", 80, "synapse xen marker") end

		local m = {}
		local _, nl = mid:gsub("\n", "\n")
		m.lines = nl
		if n > 20000 and nl < n / 400 then m.vm = true end
		if count(mid, "\\%d%d?%d?") > 300 or count(mid, "string%.char") > 20 or count(mid, "bxor") > 5 then m.enc = true end
		if count(mid, "debug%.traceback") + count(mid, "string%.dump") + count(mid, "isexecutorclosure")
			+ count(mid, "islclosure") + count(mid, "checkcaller") > 2 then m.anti = true end
		if count(mid, "while%s+true%s+do") > 3 and count(mid, "if%s+[%w_]+%s*[<>=~]+%s*%d+%s+then") > 40 then m.cff = true end

		local best, bc, bw
		for nm, s in pairs(sc) do
			if s.c > (bc or 0) then best, bc, bw = nm, s.c, s.w end
		end
		local fp = { name = nil, conf = 0, why = {}, m = m }
		if best and bc >= 40 then
			fp.name = best
			fp.conf = math.min(100, bc)
			fp.why = bw
		elseif m.vm and (m.enc or m.anti) then
			fp.name = "VM-unknown"
			fp.conf = 35
			fp.why = { "heavy VM-like structure" }
		end
		lastSrc, lastFp = src, fp
		return fp
	end

	D.obf = function(src)
		return F.fingerprint(src, nil).name
	end

	local UIM = {
		"CreateWindow", "CreateTab", "AddToggle", "AddButton", "AddSlider", "AddDropdown", "ScreenGui",
		"UICorner", "TextButton", "TweenService", "UIListLayout", "Library", "Notify",
	}
	local function uiScore(head)
		local c = 0
		for i = 1, #UIM do
			if head:find(UIM[i], 1, true) then c = c + 1 end
		end
		return c
	end

	local function isNet(tag)
		return tag:find("request", 1, true) ~= nil or tag:find("Http", 1, true) ~= nil or tag:find("ws.", 1, true) ~= nil
	end

	function F.classify(ent, src, fp, bin)
		local tag = ent.tag or ""
		if tag:sub(1, 8) == "bytecode" or bin then return "bytecode" end
		if tag:sub(1, 7) == "script_" then return "game" end
		if isNet(tag) and not (F.looksOrig or D.looks)(src, ent.url) then return "payload" end
		local head = src:sub(1, 30000)
		if fp.name == "Luarmor" or head:find("script_key", 1, true)
			or (#src < 8000 and (head:find("HttpGet", 1, true) or head:find("loadstring", 1, true))) then
			return "loader"
		end
		if #src > 3000 and uiScore(head) >= 4 then return "ui" end
		if fp.name or #src > 3000 then return "feature" end
		return "other"
	end

	local baseAdd = D.add
	D.add = function(src, tag, url, parent, id)
		local ent = baseAdd(src, tag, url, parent, id)
		if ent and type(src) == "string" and not ent.dup then
			local ok, err = pcall(function()
				local fp = F.fingerprint(src, url)
				local bin = F.isBin(src)
				if fp.name then ent.fp = { name = fp.name, conf = fp.conf, why = fp.why } end
				ent.m = fp.m
				ent.bin = bin
				ent.cat = F.classify(ent, src, fp, bin)
				CH.nodes[#CH.nodes + 1] = ent
				if fp.name and VMN[fp.name] and fp.conf >= 60 then F.deepOn(fp.name .. " in " .. tostring(tag)) end
			end)
			if not ok then noteErr(err) end
		end
		return ent
	end

	local h3 = F.h[3]
	F.h[3] = function(e, now)
		local url = type(e.u) == "string" and e.u or tostring(e.u)
		if #CH.fetches < 400 then
			CH.fetches[#CH.fetches + 1] = {
				t = r2(clock() - T0), tag = e.tag, url = url:sub(1, 200), st = e.st,
				bytes = type(e.b) == "string" and #e.b or 0, par = e.par,
			}
		end
		return h3(e, now)
	end

	function F.structure(src)
		local fn, nm = {}, {}
		local s = src:sub(1, 300000)
		local c = 0
		for name in s:gmatch("function%s+([%w_%.:]+)%s*%(") do
			fn[name] = true
			c = c + 1
			if c > 2000 then break end
		end
		for name in s:gmatch("local%s+function%s+([%w_]+)") do fn[name] = true end
		for _, pat in ipairs({
			'GetService%(%s*["\']([%w_]+)["\']', 'FindFirstChild%(%s*["\']([^"\']+)["\']',
			'WaitForChild%(%s*["\']([^"\']+)["\']', "(https?://[%w%-%._~:/%?#@!%$&%*%+,;=%%]+)",
		}) do
			c = 0
			for v in s:gmatch(pat) do
				nm[v:sub(1, 80)] = true
				c = c + 1
				if c > 1000 then break end
			end
		end
		return { fn = fn, nm = nm }
	end

	function F.catSummary()
		local c = {}
		for _, n in ipairs(CH.nodes) do
			if not n.dup then
				local k = n.cat or "other"
				c[k] = (c[k] or 0) + 1
			end
		end
		return c
	end

	function F.chainText()
		local lines = {}
		local byId, kids = {}, {}
		for _, n in ipairs(CH.nodes) do byId[n.id] = n end
		for _, n in ipairs(CH.nodes) do
			local p = n.parent
			if p and not byId[p] then p = nil end
			local key = p or 0
			kids[key] = kids[key] or {}
			table.insert(kids[key], n)
		end
		local function line(n, depth)
			if #lines > 400 then return end
			local s = string.rep("  ", depth) .. string.format("[%s] %s %s (%db) [%s]",
				tostring(n.id), n.tag or "?", n.url and tostring(n.url):sub(1, 90) or "", n.bytes or 0, n.cat or "?")
			if n.fp then s = s .. " obf=" .. n.fp.name .. "(" .. n.fp.conf .. "%)" end
			if n.dup then s = s .. " dup-of " .. tostring(n.dup) end
			if n.f then s = s .. " -> " .. n.f end
			lines[#lines + 1] = s
			local r = X.res[n.id]
			if r then
				local x = r.ok and ("ran ok " .. r.dur .. "s") or (r.compile and "compile error" or ("error: " .. tostring(r.err)))
				if r.rets and #r.rets > 0 then x = x .. " returns " .. table.concat(r.rets, "; ") end
				if r.globals then x = x .. " +globals " .. table.concat(r.globals, ",") end
				lines[#lines + 1] = string.rep("  ", depth + 1) .. "= " .. x
			end
			local ks = kids[n.id]
			if ks and depth < 12 then
				for _, k in ipairs(ks) do line(k, depth + 1) end
			end
		end
		for _, n in ipairs(kids[0] or {}) do line(n, 0) end
		if #CH.fetches > 0 then
			lines[#lines + 1] = ""
			lines[#lines + 1] = "network fetches:"
			for i = 1, math.min(#CH.fetches, 60) do
				local f = CH.fetches[i]
				lines[#lines + 1] = string.format("  t=%s %s st=%s %db %s", tostring(f.t), f.tag, tostring(f.st), f.bytes, f.url:sub(1, 100))
			end
		end
		return lines
	end

	function F.missing()
		local out, seen = {}, {}
		local function add(sev, rule, text)
			local key = rule .. text
			if seen[key] or #out >= 25 then return end
			seen[key] = true
			out[#out + 1] = { sev = sev, rule = rule, text = text }
		end
		local execF, hasKid, fetchKid = {}, {}, {}
		for _, n in ipairs(CH.nodes) do
			if n.tag == "loadstring" and n.f then execF[n.f] = true end
			if n.parent then hasKid[n.parent] = true end
		end
		for _, f in ipairs(CH.fetches) do
			if f.par then fetchKid[f.par] = true end
		end
		local ui, feat = 0, 0
		for _, n in ipairs(CH.nodes) do
			if not n.dup then
				local c = n.cat
				if c == "ui" then ui = ui + 1 elseif c == "feature" or c == "game" then feat = feat + 1 end
				if isNet(n.tag or "") and (c == "loader" or c == "ui" or c == "feature") and n.f and not execF[n.f] then
					add("warn", "fetched-not-run", "fetched " .. tostring(n.url or "?"):sub(1, 80) .. " but no matching loadstring seen")
				end
				if n.fp and VMN[n.fp.name] and n.fp.conf >= 60 and not hasKid[n.id] and not fetchKid[n.id] then
					if c == "loader" then
						add("warn", "vm-loader-leaf", n.fp.name .. " loader " .. tostring(n.f) .. " has no deeper stage captured")
					else
						add("info", "vm-protected", n.fp.name .. " script " .. tostring(n.f) .. " is VM-protected, source not recoverable")
					end
				end
				if c == "payload" and not hasKid[n.id] then
					add("info", "encrypted-payload", "raw/encrypted payload " .. tostring(n.f) .. " captured, nothing consumed it")
				end
			end
		end
		local anyRemote = false
		for _, st in pairs(stC) do
			if st.logged > 0 then
				anyRemote = true
				break
			end
		end
		if ui > 0 and feat == 0 and not anyRemote then
			add("warn", "ui-only", "only UI library captured, feature code missing")
		end
		for _, f in ipairs(CH.fetches) do
			if f.url:lower():find("luarmor", 1, true) and f.bytes == 0 then
				add("warn", "luarmor-empty", "luarmor request without a captured response: " .. f.url:sub(1, 70))
			end
		end
		if D.skipped > 0 then add("warn", "dump-skipped", D.skipped .. " dumps skipped because of size/count limits") end
		if F.weakHooks then
			for _, w in ipairs(F.weakHooks()) do add("warn", "weak-hook", w) end
		end
		return out
	end

	local ADV = {
		["fetched-not-run"] = "Use the script's features for a while, then SAVE again; the payload may load lazily.",
		["vm-loader-leaf"] = "Stay in game 30-60s so deep mode can catch the next stage, check key/HWID, then SAVE again.",
		["vm-protected"] = "Source can't be recovered from a VM; use the remote logs and AluzSpy.analyze(file) for behavior.",
		["ui-only"] = "Toggle a few features in the UI so the feature code loads, then SAVE again.",
		["luarmor-empty"] = "Check the net hook status in the summary; the API response was not captured.",
		["dump-skipped"] = "Limits reached; use AluzSpy.split(true) or clear space and run again.",
		["encrypted-payload"] = "Needs the runtime key to decrypt; capture continues while the script runs.",
		["weak-hook"] = "Run AluzSpy.health() and re-execute if a hook stays failing.",
	}

	function F.advice(list)
		local out, done = {}, {}
		for _, m in ipairs(list) do
			if not done[m.rule] and ADV[m.rule] then
				done[m.rule] = true
				out[#out + 1] = m.rule .. ": " .. ADV[m.rule]
			end
		end
		return out
	end

	local lastAlert, alerted = 0, {}
	F.onTick(function(now)
		if now - lastAlert < 30 or #D.jobs > 0 then return end
		lastAlert = now
		local list = F.missing()
		local w = 0
		for _, m in ipairs(list) do
			if m.sev == "warn" then w = w + 1 end
		end
		F.warnN = w
		if CH.alerts >= 3 or not F.notify then return end
		for _, m in ipairs(list) do
			if m.sev == "warn" and not alerted[m.rule] then
				alerted[m.rule] = true
				CH.alerts = CH.alerts + 1
				F.notify("Missing: " .. m.rule)
				break
			end
		end
	end)

	F.api = F.api or {}
	F.api.missing = function()
		local list = F.missing()
		for _, m in ipairs(list) do warn("[AluzSpy] " .. m.sev .. " " .. m.rule .. ": " .. m.text) end
		return list
	end
	F.api.chain = function()
		local lines = F.chainText()
		for i = 1, math.min(#lines, 60) do warn("[AluzSpy] " .. lines[i]) end
		return lines
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okCH then
	warn("[AluzSpy] chain failed: " .. tostring(errCH))
end
