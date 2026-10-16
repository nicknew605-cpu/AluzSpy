do local _ = "aluzspy@1.2.1-max" end
local okDC, errDC = xpcall(function()
	if CFG.decode == nil then CFG.decode = true end
	if CFG.sandbox == nil then CFG.sandbox = false end
	if CFG.net == nil then CFG.net = false end
	F.cfgLoad()

	local byte, sub, find, char = string.byte, string.sub, string.find, string.char
	local DEC = {
		jobs = {}, cur = nil, inJob = false, ss = 0, done = 0, fail = 0,
		depth = setmetatable({}, weak), nextDepth = 0,
	}

	local function Y()
		if DEC.inJob and clock() - DEC.ss > 0.0025 then
			coroutine.yield()
		end
	end

	local ESC = { n = "\n", t = "\t", r = "\r", a = "\a", b = "\b", f = "\f", v = "\v", ["\\"] = "\\", ['"'] = '"', ["'"] = "'", ["\n"] = "\n" }

	local function unescape(body)
		if not find(body, "\\", 1, true) then return body end
		local out, o, i, n = {}, 0, 1, #body
		while i <= n do
			local e = find(body, "\\", i, true)
			if not e then
				o = o + 1
				out[o] = sub(body, i)
				break
			end
			if e > i then
				o = o + 1
				out[o] = sub(body, i, e - 1)
			end
			local c = sub(body, e + 1, e + 1)
			local nx = e + 2
			local piece
			if ESC[c] then
				piece = ESC[c]
			elseif c == "x" then
				local h = sub(body, e + 2, e + 3)
				if h:match("^%x%x$") then
					piece = char(tonumber(h, 16))
					nx = e + 4
				else
					piece = "x"
				end
			elseif c == "z" then
				local _, e2 = find(body, "^%s*", e + 2)
				piece = ""
				nx = e2 + 1
			elseif c:match("^%d$") then
				local d = body:match("^%d%d?%d?", e + 1)
				piece = char(tonumber(d) % 256)
				nx = e + 1 + #d
			elseif c == "u" and sub(body, e + 2, e + 2) == "{" then
				local h, after = body:match("^{(%x+)}()", e + 2)
				if h then
					local okc, ch = pcall(utf8.char, tonumber(h, 16))
					piece = okc and ch or "?"
					nx = after
				else
					piece = "u"
				end
			else
				piece = c
			end
			o = o + 1
			out[o] = piece
			i = nx
		end
		return table.concat(out)
	end

	local function quote(raw)
		local valid = utf8 and utf8.len and utf8.len(raw) ~= nil
		local pat = valid and '[\\"%c]' or '[\\"%c\128-\255]'
		local r = raw:gsub(pat, function(ch)
			if ch == "\\" then return "\\\\" end
			if ch == '"' then return '\\"' end
			if ch == "\n" then return "\\n" end
			if ch == "\r" then return "\\r" end
			if ch == "\t" then return "\\t" end
			return string.format("\\%03d", byte(ch))
		end)
		return '"' .. r .. '"'
	end

	local B64 = {}
	do
		local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		for i = 1, 64 do B64[byte(chars, i)] = i - 1 end
	end

	local function b64decode(s)
		s = s:gsub("[^%w%+/]", "")
		local out, o, bits, nb = {}, 0, 0, 0
		for i = 1, #s do
			if i % 4096 == 0 then Y() end
			local v = B64[byte(s, i)]
			if not v then return nil end
			bits = bits * 64 + v
			nb = nb + 6
			if nb >= 8 then
				nb = nb - 8
				local p = 2 ^ nb
				local b = floor(bits / p)
				bits = bits % p
				o = o + 1
				out[o] = char(b)
			end
		end
		return table.concat(out)
	end

	local function hexdecode(v)
		return (v:gsub("%x%x", function(h) return char(tonumber(h, 16)) end))
	end

	local OP3 = { ["..."] = true, ["..="] = true, ["//="] = true }
	local OP2 = {
		["=="] = true, ["~="] = true, ["<="] = true, [">="] = true, [".."] = true, ["::"] = true, ["->"] = true,
		["+="] = true, ["-="] = true, ["*="] = true, ["/="] = true, ["%="] = true, ["^="] = true, ["//"] = true,
	}
	local KW = {}
	for w in ("and break do else elseif end false for function if in local nil not or repeat return then true until while"):gmatch("%a+") do
		KW[w] = true
	end

	local function tokenize(s)
		local toks, n, i, len = {}, 0, 1, #s
		while i <= len do
			if n % 256 == 0 then Y() end
			local c = byte(s, i)
			if c == 32 or c == 9 or c == 10 or c == 13 then
				local _, e = find(s, "^[ \t\r\n]+", i)
				i = e + 1
			elseif c == 45 and byte(s, i + 1) == 45 then
				local lvl = s:match("^%-%-%[(=*)%[", i)
				if lvl then
					local _, e = find(s, "]" .. lvl .. "]", i + 4 + #lvl, true)
					e = e or len
					n = n + 1
					toks[n] = { t = "comment", s = sub(s, i, e) }
					i = e + 1
				else
					local e = find(s, "\n", i, true)
					e = e and e - 1 or len
					local txt = sub(s, i, e)
					if byte(txt, #txt) == 13 then txt = sub(txt, 1, -2) end
					n = n + 1
					toks[n] = { t = "lcomment", s = txt }
					i = e + 1
				end
			elseif c == 34 or c == 39 then
				local pat = c == 34 and '[\\\n"]' or "[\\\n']"
				local j = i + 1
				while true do
					local e = find(s, pat, j)
					if not e then
						j = len + 1
						break
					end
					local ch = byte(s, e)
					if ch == 92 then
						j = e + 2
					elseif ch == 10 then
						j = e
						break
					else
						j = e + 1
						break
					end
				end
				n = n + 1
				toks[n] = { t = "string", s = sub(s, i, j - 1), q = c }
				i = j
			elseif c == 96 then
				local j = i + 1
				while true do
					local e = find(s, "[\\`]", j)
					if not e then
						j = len + 1
						break
					end
					if byte(s, e) == 92 then
						j = e + 2
					else
						j = e + 1
						break
					end
				end
				n = n + 1
				toks[n] = { t = "string", s = sub(s, i, j - 1), q = 96 }
				i = j
			elseif c == 91 and s:match("^%[=*%[", i) then
				local lvl = s:match("^%[(=*)%[", i)
				local _, e = find(s, "]" .. lvl .. "]", i + 2 + #lvl, true)
				e = e or len
				n = n + 1
				toks[n] = { t = "string", s = sub(s, i, e), q = 0 }
				i = e + 1
			elseif (c >= 48 and c <= 57) or (c == 46 and (byte(s, i + 1) or 0) >= 48 and (byte(s, i + 1) or 0) <= 57) then
				local e
				local c2 = byte(s, i + 1)
				if c == 48 and (c2 == 120 or c2 == 88) then
					local _, ee = find(s, "^0[xX][%x_]*", i)
					e = ee
				elseif c == 48 and (c2 == 98 or c2 == 66) then
					local _, ee = find(s, "^0[bB][01_]*", i)
					e = ee
				else
					local _, e1 = find(s, "^[%d_]*%.?[%d_]*", i)
					local _, e2 = find(s, "^[eE][%+%-]?%d+", e1 + 1)
					e = e2 or e1
				end
				n = n + 1
				toks[n] = { t = "num", s = sub(s, i, e) }
				i = e + 1
			elseif (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 then
				local _, e = find(s, "^[%w_]*", i + 1)
				local txt = sub(s, i, e)
				n = n + 1
				toks[n] = { t = KW[txt] and "kw" or "name", s = txt }
				i = e + 1
			else
				local o3, o2 = sub(s, i, i + 2), sub(s, i, i + 1)
				local op
				if OP3[o3] then op = o3 elseif OP2[o2] then op = o2 else op = sub(s, i, i) end
				n = n + 1
				toks[n] = { t = "op", s = op }
				i = i + #op
			end
		end
		return toks
	end

	local function passA(toks, stats)
		for i = 1, #toks do
			if i % 512 == 0 then Y() end
			local t = toks[i]
			if t.t == "string" then
				if t.q == 34 or t.q == 39 then
					local s = t.s
					if #s >= 2 and byte(s, #s) == t.q then
						local raw = unescape(sub(s, 2, -2))
						local ns = quote(raw)
						if ns ~= s then stats.unesc = stats.unesc + 1 end
						t.v = raw
						t.s = ns
						t.q = 34
					end
				elseif t.q == 0 then
					local body = t.s:match("^%[=*%[(.*)%]=*%]$")
					if body then
						if byte(body, 1) == 10 then body = sub(body, 2) end
						t.lv = body
					end
				end
			elseif t.t == "num" then
				local txt = t.s:gsub("_", "")
				if txt:match("^0[xX]%x+$") then
					local v = tonumber(txt)
					if v and v < 9007199254740992 then t.s = string.format("%d", v) end
				elseif txt:match("^0[bB][01]+$") then
					local v = tonumber(txt:sub(3), 2)
					if v and v < 9007199254740992 then t.s = string.format("%d", v) end
				end
			end
		end
	end

	local AFTER_BAD = {
		[":"] = 1, ["."] = 1, ["("] = 1, ["["] = 1, ["{"] = 1, ["^"] = 1, ["*"] = 1,
		["/"] = 1, ["//"] = 1, ["%"] = 1, ["+"] = 1, ["-"] = 1,
	}
	local PREV_BAD = { ["#"] = 1, ["-"] = 1, ["not"] = 1 }

	local function passB(toks, stats)
		local out, n, i, m = {}, 0, 1, #toks
		while i <= m do
			if i % 512 == 0 then Y() end
			local t = toks[i]
			local t1, t2, t3 = toks[i + 1], toks[i + 2], toks[i + 3]
			local done = false
			if t.t == "name" and t.s == "string" and t1 and t1.s == "." and t2 and t2.s == "char" and t3 and t3.s == "(" then
				local prev = out[n]
				if not (prev and prev.t == "op" and (prev.s == "." or prev.s == ":")) then
					local j, parts, ok = i + 4, {}, true
					while true do
						local a = toks[j]
						local v = a and a.t == "num" and tonumber(a.s) or nil
						if v and v >= 0 and v <= 255 and v % 1 == 0 then
							parts[#parts + 1] = char(v)
							local b = toks[j + 1]
							if b and b.s == "," then
								j = j + 2
							elseif b and b.s == ")" then
								j = j + 1
								break
							else
								ok = false
								break
							end
						else
							ok = false
							break
						end
					end
					if ok and #parts > 0 and #parts <= 4096 then
						local raw = table.concat(parts)
						local nt = toks[j + 1]
						local st = { t = "string", s = quote(raw), v = raw, q = 34 }
						if nt and nt.t == "op" and (nt.s == ":" or nt.s == "." or nt.s == "[" or nt.s == "(") then
							out[n + 1] = { t = "op", s = "(" }
							out[n + 2] = st
							out[n + 3] = { t = "op", s = ")" }
							n = n + 3
						else
							n = n + 1
							out[n] = st
						end
						stats.fold = stats.fold + 1
						i = j + 1
						done = true
					end
				end
			end
			if not done and t.t == "string" and t.v and t1 and t1.t == "op" and t1.s == ".." and t2 and t2.t == "string" and t2.v
				and #t.v + #t2.v < 20000 then
				local prev = out[n]
				local okPrev = not (prev and PREV_BAD[prev.s] and (prev.t == "op" or prev.t == "kw"))
				local okNext = not (t3 and ((t3.t == "op" and AFTER_BAD[t3.s]) or t3.t == "string"))
				if okPrev and okNext then
					local raw = t.v .. t2.v
					toks[i + 2] = { t = "string", s = quote(raw), v = raw, q = 34 }
					stats.fold = stats.fold + 1
					i = i + 2
					done = true
				end
			end
			if not done then
				n = n + 1
				out[n] = t
				i = i + 1
			end
		end
		return out
	end

	local function weird(nm)
		local L = #nm
		if L >= 4 and nm:match("^[Il1]+$") then return true end
		if L >= 6 and nm:match("^[IlO0o1_]+$") then return true end
		if nm:match("^l_%d+_%d+$") or nm:match("^%a_%d+_%d+$") then return true end
		return false
	end

	local function prevSig(toks, i)
		local k = i - 1
		while k >= 1 do
			local t = toks[k]
			if t.t ~= "comment" and t.t ~= "lcomment" then return t end
			k = k - 1
		end
		return nil
	end

	local function nextSig(toks, i)
		local k = i + 1
		local n = #toks
		while k <= n do
			local t = toks[k]
			if t.t ~= "comment" and t.t ~= "lcomment" then return t end
			k = k + 1
		end
		return nil
	end

	local function renamePass(toks, stats)
		local count, order, used, strs = {}, {}, {}, {}
		local isVar = {}
		local brace = {}
		for i = 1, #toks do
			if i % 1024 == 0 then Y() end
			local t = toks[i]
			if t.t == "op" then
				local s = t.s
				if s == "{" or s == "(" or s == "[" then
					brace[#brace + 1] = s
				elseif s == "}" or s == ")" or s == "]" then
					brace[#brace] = nil
				end
			elseif t.t == "name" then
				used[t.s] = true
				local p, nx = prevSig(toks, i), nextSig(toks, i)
				local member = p and p.t == "op" and (p.s == "." or p.s == ":")
				if not member and p and p.t == "op" and (p.s == "{" or p.s == "," or p.s == ";") and brace[#brace] == "{"
					and nx and nx.t == "op" and nx.s == "=" then
					member = true
				end
				if not member then
					isVar[i] = true
					if weird(t.s) then
						if not count[t.s] then
							count[t.s] = 0
							order[#order + 1] = t.s
						end
						count[t.s] = count[t.s] + 1
					end
				end
			elseif t.t == "string" then
				local v = t.v or t.lv
				if v and #v <= 64 and weird(v) then strs[v] = true end
			end
		end
		local map, k = {}, 0
		for _, nm in ipairs(order) do
			if count[nm] >= 2 and not strs[nm] then
				repeat k = k + 1 until not used["v" .. k]
				map[nm] = "v" .. k
				stats.rename = stats.rename + 1
			end
		end
		if next(map) == nil then return end
		for i = 1, #toks do
			local t = toks[i]
			if isVar[i] and map[t.s] then t.s = map[t.s] end
		end
	end

	local VALEND_KW = { ["end"] = true, ["nil"] = true, ["true"] = true, ["false"] = true }
	local function valEnd(t)
		if not t then return false end
		local tt = t.t
		if tt == "name" or tt == "num" or tt == "string" then return true end
		if tt == "kw" then return VALEND_KW[t.s] == true end
		if tt == "op" then return t.s == ")" or t.s == "]" or t.s == "}" or t.s == "..." end
		return false
	end

	local BOUNDARY_KW = { ["then"] = true, ["do"] = true, ["else"] = true, ["repeat"] = true }
	local function boundary(prev)
		if not prev then return true end
		if prev.t == "lcomment" or prev.t == "comment" then return true end
		if prev.t == "op" and prev.s == ";" then return true end
		if prev.t == "kw" and BOUNDARY_KW[prev.s] then return true end
		return valEnd(prev)
	end

	local NOSP_BEFORE = { [","] = 1, [";"] = 1, [")"] = 1, ["]"] = 1, ["}"] = 1, ["."] = 1, [":"] = 1 }
	local NOSP_AFTER = { ["("] = 1, ["["] = 1, ["{"] = 1, ["."] = 1, [":"] = 1, ["#"] = 1 }
	local NOBREAK_END = {
		[")"] = 1, [","] = 1, [";"] = 1, ["}"] = 1, ["]"] = 1, ["."] = 1, [":"] = 1, [".."] = 1,
		["and"] = 1, ["or"] = 1, ["=="] = 1, ["~="] = 1, ["+"] = 1, ["-"] = 1, ["*"] = 1, ["/"] = 1,
	}

	local function needSpace(prev, tk, prevUnary)
		if not prev then return false end
		local ps, ts = prev.s, tk.s
		if ps == "[" and sub(ts, 1, 1) == "[" then return true end
		if ps == "-" and sub(ts, 1, 1) == "-" then return true end
		if prevUnary then return false end
		if tk.t == "op" and NOSP_BEFORE[ts] then return false end
		if prev.t == "op" and NOSP_AFTER[ps] then return false end
		if tk.t == "op" and ts == "(" then
			if prev.t == "name" or prev.t == "string" then return false end
			if prev.t == "op" and (ps == ")" or ps == "]" or ps == "}") then return false end
			if prev.t == "kw" and ps == "function" then return false end
			return true
		end
		if tk.t == "op" and ts == "[" then
			if prev.t == "name" or prev.t == "string" then return false end
			if prev.t == "op" and (ps == ")" or ps == "]" or ps == "}") then return false end
			return true
		end
		return true
	end

	local function formatToks(toks)
		local lines, nl, cur, ncur = {}, 0, {}, 0
		local ind, lineInd = 0, 0
		local stack, ns = {}, 0
		local pendLoop = 0
		local prev, prevUnary = nil, false
		local function flush()
			if ncur > 0 then
				nl = nl + 1
				lines[nl] = string.rep("\t", lineInd) .. table.concat(cur, "", 1, ncur)
				cur, ncur = {}, 0
			end
		end
		for i = 1, #toks do
			if i % 512 == 0 then Y() end
			local tk = toks[i]
			local ts, tt = tk.s, tk.t
			local top = ns > 0 and stack[ns] or nil
			local isIfExpr = false
			local nlBefore = false
			if tt == "kw" then
				if ts == "if" then
					isIfExpr = prev ~= nil and not boundary(prev)
					nlBefore = not isIfExpr and boundary(prev)
				elseif ts == "end" or ts == "until" then
					nlBefore = true
				elseif ts == "else" or ts == "elseif" then
					nlBefore = top ~= "ifx"
				elseif ts == "local" or ts == "return" or ts == "break" or ts == "for" or ts == "while" or ts == "repeat" or ts == "function" then
					nlBefore = boundary(prev)
				end
			end
			if nlBefore then flush() end
			local dedented = false
			if tt == "kw" and (ts == "end" or ts == "until") then
				while ns > 0 and stack[ns] == "ifx" do
					stack[ns] = nil
					ns = ns - 1
				end
				if ns > 0 then
					stack[ns] = nil
					ns = ns - 1
					if ind > 0 then ind = ind - 1 end
				end
			elseif tt == "kw" and (ts == "else" or ts == "elseif") then
				if top == "ifx" then
					if ts == "else" then
						stack[ns] = nil
						ns = ns - 1
					end
				else
					if ind > 0 then ind = ind - 1 end
					dedented = true
				end
			end
			if ncur == 0 then lineInd = ind end
			if ncur > 0 and needSpace(prev, tk, prevUnary) then
				ncur = ncur + 1
				cur[ncur] = " "
			end
			ncur = ncur + 1
			cur[ncur] = ts
			prevUnary = (tt == "op" and ts == "-" and not valEnd(prev))
			if tt == "kw" then
				if ts == "function" then
					ns = ns + 1
					stack[ns] = "func"
					ind = ind + 1
				elseif ts == "if" then
					ns = ns + 1
					if isIfExpr then
						stack[ns] = "ifx"
					else
						stack[ns] = "if"
						ind = ind + 1
					end
				elseif ts == "for" or ts == "while" then
					pendLoop = pendLoop + 1
					ns = ns + 1
					stack[ns] = "loop"
					ind = ind + 1
				elseif ts == "do" then
					if pendLoop > 0 then
						pendLoop = pendLoop - 1
					else
						ns = ns + 1
						stack[ns] = "do"
						ind = ind + 1
					end
				elseif ts == "repeat" then
					ns = ns + 1
					stack[ns] = "repeat"
					ind = ind + 1
				elseif dedented then
					ind = ind + 1
				end
			end
			local nlAfter = false
			if tt == "lcomment" then
				nlAfter = true
			elseif tt == "kw" then
				if ts == "then" or ts == "else" then
					nlAfter = stack[ns] == "if"
				elseif ts == "do" or ts == "repeat" then
					nlAfter = true
				elseif ts == "end" then
					local nx = toks[i + 1]
					nlAfter = not (nx and NOBREAK_END[nx.s] and (nx.t == "op" or nx.t == "kw"))
				end
			elseif tt == "op" and ts == ";" then
				nlAfter = true
			end
			if nlAfter then flush() end
			prev = tk
		end
		flush()
		return table.concat(lines, "\n") .. "\n"
	end

	local function analyze(toks)
		local rep = { urls = {}, services = {}, names = {}, flags = {}, layers = {} }
		local seenU, seenS, seenN, flagSet, nameSet = {}, {}, {}, {}, {}
		local function flag(f)
			if not flagSet[f] then
				flagSet[f] = true
				rep.flags[#rep.flags + 1] = f
			end
		end
		local function layer(src, via)
			if #rep.layers < 8 and type(src) == "string" and #src >= 24 then
				rep.layers[#rep.layers + 1] = { src = src, via = via }
			end
		end
		local n = #toks
		for i = 1, n do
			if i % 512 == 0 then Y() end
			local t = toks[i]
			local tt = t.t
			if tt == "name" then
				nameSet[t.s] = true
				local nx, s2 = toks[i + 1], toks[i + 2]
				if t.s == "GetService" and nx and nx.s == "(" and s2 and s2.v and not seenS[s2.v] then
					seenS[s2.v] = true
					rep.services[#rep.services + 1] = s2.v
				elseif (t.s == "FindFirstChild" or t.s == "WaitForChild" or t.s == "FindFirstChildOfClass")
					and nx and nx.s == "(" and s2 and s2.v and not seenN[s2.v] and #rep.names < 60 then
					seenN[s2.v] = true
					rep.names[#rep.names + 1] = s2.v
				elseif t.s == "loadstring" and nx and nx.s == "(" then
					if s2 and s2.t == "string" and (s2.v or s2.lv) and toks[i + 3] and toks[i + 3].s == ")" then
						layer(s2.v or s2.lv, "loadstring literal")
					else
						for k = i + 2, math.min(i + 10, n) do
							if toks[k].s == "HttpGet" or toks[k].s == "HttpGetAsync" then
								flag("remote loadstring (downloads and runs code)")
								break
							end
						end
					end
				end
			elseif tt == "string" then
				local v = t.v or t.lv
				if v and #v > 0 and #v <= 200000 then
					if #v <= 20000 then
						if #rep.urls < 40 then
							for u in v:gmatch("https?://[%w%-%._~:/%?#@!%$&'%*%+,;=%%]+") do
								if not seenU[u] and #rep.urls < 40 then
									seenU[u] = true
									rep.urls[#rep.urls + 1] = u
								end
							end
						end
						local lv = v:lower()
						if lv:find("discord%.com/api/webhooks") or lv:find("discordapp%.com/api/webhooks") then flag("discord webhook") end
						if lv:find("api%.telegram%.org/bot") then flag("telegram bot api") end
						if v:find("ROBLOSECURITY", 1, true) then flag("references .ROBLOSECURITY cookie") end
						if lv:find("ipify") or lv:find("ip%-api") or lv:find("ipinfo") then flag("ip lookup") end
					end
					if #v >= 64 and #rep.layers < 8 then
						if #v % 2 == 0 and v:match("^%x+$") then
							local d = hexdecode(v)
							if D.looks(d, nil) then layer(d, "hex blob") end
						elseif #v >= 80 and v:match("^[%w%+/=%s]+$") then
							local d = b64decode(v)
							if d and #d >= 24 and D.looks(d, nil) then layer(d, "base64 blob") end
						end
					end
				end
			end
		end
		if nameSet.setclipboard or nameSet.toclipboard then flag("clipboard write") end
		if nameSet.queue_on_teleport or nameSet.queueonteleport then flag("queue_on_teleport (persists across servers)") end
		if nameSet.writefile or nameSet.appendfile then flag("file write") end
		if nameSet.hookfunction or nameSet.hookmetamethod then flag("hooks functions/metamethods") end
		if nameSet.getfenv or nameSet.setfenv or nameSet.getrenv or nameSet.getrawmetatable then flag("environment access") end
		if nameSet.Kick then flag("Kick call") end
		if nameSet.FireServer or nameSet.InvokeServer then flag("fires remotes") end
		local out = nameSet.request or nameSet.http_request or nameSet.HttpPost or nameSet.HttpPostAsync or nameSet.syn
		if out then flag("outbound http") end
		if flagSet["discord webhook"] and out then flag("likely sends data to a webhook") end
		return rep
	end

	F.tok = { tokenize = tokenize, unescape = unescape, quote = quote, b64 = b64decode, hex = hexdecode, format = formatToks, kw = KW }
	F.decInJob = function() return DEC.inJob end

	function F.decodeCore(src)
		local stats = { unesc = 0, fold = 0, rename = 0 }
		local toks = tokenize(src)
		passA(toks, stats)
		toks = passB(toks, stats)
		local rep = analyze(toks)
		renamePass(toks, stats)
		local ok, text = pcall(formatToks, toks)
		if not ok or type(text) ~= "string" then text = src end
		return text, rep, stats
	end

	local function runSandbox(src, opts)
		opts = opts or {}
		local st = {
			ops = 0, total = 0, waits = 0, dead = false, log = {}, nlog = 0, globals = {},
			urls = {}, layers = {}, pending = {}, errors = {}, remotes = 0,
		}
		local OPCAP, WAITCAP, LOGMAX, TOTCAP = 30000, 300, 600, 300000
		local MOCKP = setmetatable({}, weak)
		local CH = setmetatable({}, weak)

		local function tickOp()
			st.ops = st.ops + 1
			st.total = st.total + 1
			if st.ops > OPCAP or st.total > TOTCAP then st.dead = true end
			if st.dead then error("aluz-sandbox-limit", 0) end
		end

		local function logf(s)
			if st.nlog < LOGMAX then
				st.nlog = st.nlog + 1
				st.log[st.nlog] = s
			end
		end

		local function fmtv(v)
			local t = type(v)
			if t == "string" then
				local s = v
				if #s > 70 then s = sub(s, 1, 70) .. ".." end
				return '"' .. clean(s) .. '"'
			elseif t == "number" or t == "boolean" or t == "nil" then
				return tostring(v)
			elseif t == "function" then
				return "<fn>"
			elseif t == "table" then
				if MOCKP[v] then return MOCKP[v] end
				local u = rawget(v, "Url") or rawget(v, "url")
				if type(u) == "string" then return "{Url=" .. fmtv(u) .. "}" end
				return "{..}"
			end
			return "<" .. t .. ">"
		end

		local function isUrl(s)
			return type(s) == "string" and s:find("^https?://") ~= nil
		end

		local fetches = 0
		local function netOk(u)
			if fetches >= 3 then return false end
			local host = u:match("^https?://([^/:%?#]+)")
			if not host then return false end
			host = host:lower()
			if host == "localhost" or host:find("^127%.") or host:find("^10%.") or host:find("^192%.168%.") or host:find("^169%.254%.")
				or host:find("^172%.[123]%d%.") or host:find("%.local$") or host:find("%.internal$") or host:find("^0%.") then
				return false
			end
			fetches = fetches + 1
			logf("fetch " .. u)
			return true
		end

		local mockMT = { __metatable = "locked" }
		local function mkmock(path)
			local m = setmetatable({}, mockMT)
			MOCKP[m] = path
			return m
		end

		local function queueCb(args, from)
			for i = 1, args.n do
				if type(args[i]) == "function" and #st.pending < 120 then
					st.pending[#st.pending + 1] = { args[i], from }
				end
			end
		end

		mockMT.__index = function(self, k)
			tickOp()
			local ch = CH[self]
			if not ch then
				ch = {}
				CH[self] = ch
			end
			local key = type(k) == "string" and k or fmtv(k)
			local c = ch[key]
			if not c then
				local p = MOCKP[self]
				c = mkmock(type(k) == "string" and (p .. "." .. k) or (p .. "[" .. key .. "]"))
				ch[key] = c
			end
			return c
		end

		mockMT.__newindex = function(self, k, v)
			tickOp()
			logf("set " .. MOCKP[self] .. "." .. tostring(k) .. " = " .. fmtv(v))
			if type(v) == "function" and #st.pending < 120 then
				st.pending[#st.pending + 1] = { v, MOCKP[self] .. "." .. tostring(k) }
			end
		end

		mockMT.__call = function(self, ...)
			tickOp()
			local args = pack(...)
			local p = MOCKP[self]
			local parts = {}
			for i = 1, math.min(args.n, 5) do parts[i] = fmtv(args[i]) end
			logf(p .. "(" .. table.concat(parts, ", ") .. ")")
			queueCb(args, p)
			local name = p:match("([%w_]+)$") or ""
			local a1, a2 = args[1], args[2]
			local selfIsMock = type(a1) == "table" and MOCKP[a1] ~= nil
			local first = selfIsMock and a2 or a1
			if name == "HttpGet" or name == "HttpGetAsync" or name == "HttpPost" or name == "HttpPostAsync" then
				if isUrl(first) then st.urls[#st.urls + 1] = first end
				if opts.net and isUrl(first) and netOk(first) then
					local ok, body = pcall(function() return game:HttpGet(first) end)
					if ok and type(body) == "string" then
						if #body > 524288 then body = body:sub(1, 524288) end
						return body
					end
				end
				return "return nil"
			elseif name == "GetService" and type(first) == "string" then
				return mkmock("S:" .. first)
			elseif (name == "FindFirstChild" or name == "WaitForChild" or name == "FindFirstChildOfClass" or name == "FindFirstChildWhichIsA")
				and type(first) == "string" and selfIsMock then
				return mockMT.__index(a1, first)
			elseif name == "FireServer" or name == "InvokeServer" then
				st.remotes = st.remotes + 1
			end
			return mkmock(p .. "()")
		end

		mockMT.__tostring = function(self) return "<" .. MOCKP[self] .. ">" end
		mockMT.__len = function() return 0 end
		mockMT.__concat = function(a, b)
			tickOp()
			local function s(x)
				if type(x) == "string" or type(x) == "number" then return tostring(x) end
				return "<" .. (MOCKP[x] or type(x)) .. ">"
			end
			return s(a) .. s(b)
		end
		for _, ev in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__idiv" }) do
			mockMT[ev] = function()
				tickOp()
				return 1
			end
		end
		mockMT.__lt = function() return false end
		mockMT.__le = function() return false end

		local env = {}

		local function sandboxed(f)
			if type(f) ~= "function" then return false end
			if not pcall(setfenv, f, env) then return false end
			local ok, e = pcall(getfenv, f)
			return ok and e == env
		end

		local function sp(f, ...)
			local r = pack(pcall(f, ...))
			if st.dead then error("aluz-sandbox-limit", 0) end
			return unpack(r, 1, r.n)
		end

		local function waitf()
			tickOp()
			st.waits = st.waits + 1
			if st.waits > WAITCAP then
				st.dead = true
				error("aluz-sandbox-limit", 0)
			end
			return 0.03, 0
		end

		local function defer(f, ...)
			if type(f) == "function" and #st.pending < 120 then
				st.pending[#st.pending + 1] = { f, "task", pack(...) }
			end
			return mkmock("thread")
		end

		local function delayf(_, f, ...)
			return defer(f, ...)
		end

		local function prn(...)
			local a = pack(...)
			local parts = {}
			for i = 1, math.min(a.n, 6) do parts[i] = fmtv(a[i]) end
			logf("print(" .. table.concat(parts, ", ") .. ")")
		end

		local function reqf(o)
			tickOp()
			local url = type(o) == "table" and (rawget(o, "Url") or rawget(o, "url")) or nil
			logf("request(" .. fmtv(url) .. ")")
			if isUrl(url) then st.urls[#st.urls + 1] = url end
			return { StatusCode = 200, Body = "return nil", Success = true, Headers = {} }
		end

		local sstring = {}
		for k, v in pairs(string) do sstring[k] = v end
		local realRep = string.rep
		sstring.rep = function(s, n, sep)
			if type(s) == "string" and type(n) == "number" and #s * n > 2000000 then error("aluz-sandbox-limit", 0) end
			return realRep(s, n, sep)
		end
		sstring.dump = nil

		local base = {
			assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs, pcall = sp,
			xpcall = function(f, h, ...)
				local r = pack(xpcall(f, h, ...))
				if st.dead then error("aluz-sandbox-limit", 0) end
				return unpack(r, 1, r.n)
			end,
			getmetatable = function(x)
				if type(x) == "table" and MOCKP[x] then return "locked" end
				return getmetatable(x)
			end,
			rawequal = rawequal, rawget = rawget, rawset = rawset, select = select, setmetatable = setmetatable,
			tonumber = tonumber, tostring = tostring, type = type, unpack = unpack,
			typeof = function(x)
				if type(x) == "table" and MOCKP[x] then return "Instance" end
				return typeof(x)
			end,
			string = sstring, table = table, math = math, bit32 = bit32, utf8 = utf8, coroutine = coroutine,
			os = { time = os.time, clock = os.clock, date = os.date },
			debug = {
				traceback = function() return "" end,
				info = function() return nil end,
				getinfo = function() return nil end,
			},
			tick = function() return os.time() end,
			time = function() return 1 end,
			elapsedTime = function() return 1 end,
			wait = waitf, Wait = waitf, spawn = defer, Spawn = defer, delay = delayf, Delay = delayf,
			task = { wait = waitf, spawn = defer, defer = defer, delay = delayf, cancel = function() end },
			print = prn, warn = prn,
			getgenv = function() return env end,
			getfenv = function() return env end,
			setfenv = function() end,
			shared = env, _G = env,
			require = function()
				tickOp()
				return mkmock("require()")
			end,
			request = reqf, http_request = reqf,
			loadstring = function(s)
				tickOp()
				if type(s) ~= "string" then return nil, "sandbox: chunk must be a string" end
				st.layers[#st.layers + 1] = s
				logf("loadstring(<" .. #s .. " bytes>)")
				local f, e = loadstring(s)
				if not f then return nil, e end
				if not sandboxed(f) then return nil, "sandbox: setfenv unsupported" end
				return f
			end,
		}

		setmetatable(env, {
			__index = function(_, k)
				tickOp()
				local v = base[k]
				if v ~= nil then return v end
				if k ~= nil then st.globals[tostring(k)] = true end
				return mkmock(tostring(k))
			end,
		})

		local fn, cerr = loadstring(src)
		if not fn then return nil, "compile: " .. tostring(cerr) end
		if not sandboxed(fn) then return nil, "setfenv unsupported, refusing to run" end
		local okm, errm = pcall(fn)
		if not okm and tostring(errm) ~= "aluz-sandbox-limit" then
			st.errors[#st.errors + 1] = tostring(errm):sub(1, 160)
		end
		local ran = 0
		while #st.pending > 0 and ran < 80 and st.total < TOTCAP do
			local item = table.remove(st.pending, 1)
			ran = ran + 1
			st.ops, st.waits, st.dead = 0, 0, false
			local args = item[3]
			local okc, errc
			if args then
				okc, errc = pcall(item[1], unpack(args, 1, args.n))
			else
				okc, errc = pcall(item[1], mkmock("arg1"), mkmock("arg2"))
			end
			if not okc and tostring(errc) ~= "aluz-sandbox-limit" and #st.errors < 20 then
				st.errors[#st.errors + 1] = tostring(errc):sub(1, 160)
			end
		end
		local out = {
			"AluzSpy sandbox report",
			"ops " .. st.total .. "  callbacks run " .. ran .. "  remote calls " .. st.remotes .. "  layers " .. #st.layers,
		}
		local seen, urls = {}, {}
		for i = 1, #st.urls do
			if not seen[st.urls[i]] then
				seen[st.urls[i]] = true
				urls[#urls + 1] = st.urls[i]
			end
		end
		if #urls > 0 then
			out[#out + 1] = "urls:"
			for i = 1, math.min(#urls, 30) do out[#out + 1] = "  " .. urls[i] end
		end
		local names = {}
		for k in pairs(st.globals) do names[#names + 1] = k end
		table.sort(names)
		if #names > 0 then
			out[#out + 1] = "globals used: " .. table.concat(names, ", ", 1, math.min(#names, 80))
		end
		if #st.errors > 0 then
			out[#out + 1] = "errors:"
			for i = 1, #st.errors do out[#out + 1] = "  " .. st.errors[i] end
		end
		out[#out + 1] = "calls:"
		for i = 1, st.nlog do out[#out + 1] = string.format("%4d %s", i, st.log[i]) end
		return table.concat(out, "\n"), st.layers
	end
	F.sandbox = runSandbox

	local function baseName(ent)
		local b = ent.f:gsub("%.lua$", "")
		return b
	end

	local function emitFile(name, text)
		D.pending = D.pending + #text
		D.t = D.t + 1
		D.q[D.t] = { f = name, s = text }
	end

	local function addLayers(ent, list, tag)
		local depth = DEC.depth[ent] or 0
		if depth >= 5 then return 0 end
		local c = 0
		for i = 1, math.min(#list, 6) do
			local item = list[i]
			local src = type(item) == "table" and item.src or item
			if type(src) == "string" and #src >= 24 then
				DEC.nextDepth = depth + 1
				local e2 = D.add(src, tag, ent.url or ent.f, ent.id, nil)
				DEC.nextDepth = 0
				if e2 then c = c + 1 end
			end
		end
		return c
	end

	local function sbAuto(ent, src)
		if not alive then return end
		local prev = busy
		busy = true
		local ok, rtext, layers = pcall(runSandbox, src, { net = CFG.net })
		busy = prev
		if ok and rtext then
			emitFile(baseName(ent) .. ".sandbox.txt", rtext)
			addLayers(ent, layers or {}, "layer_sbox")
		end
	end

	local function listLines(lines, title, list, cap)
		if #list == 0 then return end
		lines[#lines + 1] = title .. ":"
		for i = 1, math.min(#list, cap) do lines[#lines + 1] = "  " .. list[i] end
		if #list > cap then lines[#lines + 1] = "  ... +" .. (#list - cap) end
	end

	local function finish(j, text, rep, stats)
		local ent, src = j.ent, j.src
		local lines = {
			"AluzSpy decode report",
			"source: " .. ent.f .. " (" .. #src .. " bytes)" .. (ent.obf and ("  obf: " .. ent.obf) or ""),
			"changes: strings " .. stats.unesc .. ", folded " .. stats.fold .. ", renamed " .. stats.rename,
		}
		listLines(lines, "flags", rep.flags, 20)
		listLines(lines, "urls", rep.urls, 20)
		listLines(lines, "services", rep.services, 20)
		listLines(lines, "names", rep.names, 30)
		if #rep.layers > 0 then
			lines[#lines + 1] = "layers:"
			for i = 1, #rep.layers do
				lines[#lines + 1] = "  " .. rep.layers[i].via .. " (" .. #rep.layers[i].src .. " bytes)"
			end
		end
		local changed = stats.unesc + stats.fold + stats.rename + #rep.layers + #rep.flags
		local _, nlc = src:gsub("\n", "\n")
		if changed > 0 or ent.obf or (#src / (nlc + 1)) > 160 then
			local hdr = "--[==[\n" .. table.concat(lines, "\n"):gsub("%]==%]", "] ==]") .. "\n]==]\n"
			emitFile(baseName(ent) .. ".dec.lua", hdr .. text)
		end
		addLayers(ent, rep.layers, "layer")
		if CFG.sandbox and #src <= 400000 and (ent.obf or #rep.flags > 0 or changed > 0) then
			task.defer(sbAuto, ent, src)
		end
		j.src = nil
	end

	local function step()
		if not alive then return end
		if not DEC.cur then
			local j = table.remove(DEC.jobs, 1)
			while j and j.ent.dup do j = table.remove(DEC.jobs, 1) end
			if not j then return end
			DEC.cur = j
			j.co = coroutine.create(function() return F.decodeCore(j.src) end)
		end
		local j = DEC.cur
		local prev = busy
		busy = true
		DEC.inJob = true
		DEC.ss = clock()
		local ok, a, b, c = coroutine.resume(j.co)
		DEC.inJob = false
		busy = prev
		if not ok then
			DEC.cur = nil
			DEC.fail = DEC.fail + 1
			noteErr(a)
			return
		end
		if coroutine.status(j.co) == "dead" then
			DEC.cur = nil
			DEC.done = DEC.done + 1
			local okf, errf = pcall(finish, j, a, b, c)
			if not okf then noteErr(errf) end
		end
	end

	local baseAdd = D.add
	D.add = function(src, tag, url, parent, id)
		local depth = DEC.nextDepth
		DEC.nextDepth = 0
		local ent = baseAdd(src, tag, url, parent, id)
		if ent and CFG.decode then
			if depth > 0 then DEC.depth[ent] = depth end
			if tag:sub(1, 7) ~= "bytecod" and #src >= 64 and #src <= 800000
				and (DEC.depth[ent] or 0) < 6 and #DEC.jobs < 24 then
				DEC.jobs[#DEC.jobs + 1] = { src = src, ent = ent }
			end
		end
		return ent
	end

	conns[#conns + 1] = SV.RunService.Heartbeat:Connect(step)

	local function resolveSrc(x)
		if type(x) ~= "string" then return nil end
		if #x < 260 and not x:find("\n", 1, true) then
			local body = FS.read(PATH.d(x))
			if body then return body, x end
			body = FS.read(x)
			if body then return body, x end
		end
		return x, "inline"
	end

	local function outName(nm, suffix)
		if nm == "inline" then return "inline_" .. os.time() .. suffix end
		local b = nm:match("([^/]+)$") or nm
		b = b:gsub("%.lua$", "")
		return b .. suffix
	end

	local SETTABLE = { decode = true, sandbox = true, net = true, code = true, tree = true, callerDump = true, autoDeobf = true, autoReverse = true, redact = true, redactIds = true }

	local DAPI = {
		decode = function(x)
			local src, nm = resolveSrc(x)
			if not src then return nil, "no source" end
			local ok, text, rep, stats = pcall(F.decodeCore, src)
			if not ok then return nil, tostring(text) end
			local name = outName(nm, ".dec.lua")
			FS.write(PATH.d(name), text)
			return text, name, rep, stats
		end,
		analyze = function(x, net)
			local src, nm = resolveSrc(x)
			if not src then return nil, "no source" end
			local prev = busy
			busy = true
			local ok, rtext, layers = pcall(runSandbox, src, { net = net == true or (net == nil and CFG.net) })
			busy = prev
			if not ok then return nil, tostring(rtext) end
			if not rtext then return nil, layers end
			local name = outName(nm, ".sandbox.txt")
			FS.write(PATH.d(name), rtext)
			return rtext, name, layers
		end,
		decodeAll = function()
			pcall(D.flush)
			local c = 0
			for _, ent in ipairs(D.list) do
				if not ent.dup and ent.f and #DEC.jobs < 24 then
					local body = FS.read(PATH.d(ent.f))
					if body and #body >= 64 and #body <= 800000 then
						DEC.jobs[#DEC.jobs + 1] = { src = body, ent = ent }
						c = c + 1
					end
				end
			end
			return c
		end,
		set = function(key, val)
			if not SETTABLE[key] then return false end
			CFG[key] = val and true or false
			F.cfgSave()
			return CFG[key]
		end,
	}
	F.apiMerge(DAPI)
	F.resolveSrc = resolveSrc
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okDC then
	warn("[AluzSpy] decode module failed: " .. tostring(errDC))
end
