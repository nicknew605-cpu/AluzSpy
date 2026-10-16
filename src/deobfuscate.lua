do local _ = "aluzspy@1.2.1-max" end
local okDO, errDO = xpcall(function()
	if not (F.tok and F.job and F.decodeCore) then return end
	CAP.deobfuscate = true
	F.register("deobfuscate", { ver = "1.2.1-max" })

	local TK = F.tok
	local tokenize, quote, unescape, format = TK.tokenize, TK.quote, TK.unescape, TK.format
	local floor, fmt, byte, char, sub = math.floor, string.format, string.byte, string.char, string.sub

	local LIM = { src = 800000, rounds = 4, strlen = 20000, timeout = 12, layers = 8 }
	local DB = { runs = 0, changed = 0, rolled = 0, passes = {}, flags = {}, items = {}, errors = 0 }
	local PASSES = { "numfold", "strfold", "strtab", "dead", "rename" }

	local lastY = 0
	local function Y()
		if coroutine.isyieldable() and ((F.J and F.J.inJob) or (F.decInJob and F.decInJob())) and clock() - lastY > 0.0025 then
			coroutine.yield()
			lastY = clock()
		end
	end

	local function isop(t, s) return t ~= nil and t.t == "op" and t.s == s end
	local function iskw(t, s) return t ~= nil and t.t == "kw" and t.s == s end

	local function sval(t)
		if not t or t.t ~= "string" then return nil end
		if t.v then return t.v end
		if t.q == 34 or t.q == 39 then
			local s = t.s
			if #s >= 2 and byte(s, #s) == t.q then return unescape(sub(s, 2, -2)) end
			return nil
		end
		if t.q == 0 then
			local body = t.s:match("^%[=*%[(.*)%]=*%]$")
			if body then
				if byte(body, 1) == 10 then body = sub(body, 2) end
				return body
			end
		end
		return nil
	end

	local function mkstr(raw) return { t = "string", s = quote(raw), v = raw, q = 34 } end
	local function mkop(s) return { t = "op", s = s } end
	local function mkkw(s) return { t = "kw", s = s } end

	local function numstr(v)
		if v ~= v or v == math.huge or v == -math.huge then return nil end
		if v % 1 == 0 and math.abs(v) < 9007199254740992 then return fmt("%d", v) end
		local s = fmt("%.14g", v)
		if tonumber(s) ~= v then s = fmt("%.17g", v) end
		return s
	end

	local function numtoks(v, wrapNeg)
		local s = numstr(math.abs(v))
		if not s then return nil end
		if v < 0 or (v == 0 and 1 / v < 0) then
			if v == 0 then return { { t = "num", s = "0" } } end
			if wrapNeg then return { mkop("("), mkop("-"), { t = "num", s = s }, mkop(")") } end
			return { mkop("-"), { t = "num", s = s } }
		end
		return { { t = "num", s = s } }
	end

	local function valueEnd(t)
		if not t then return false end
		local k = t.t
		if k == "name" or k == "num" or k == "string" then return true end
		if k == "kw" then return t.s == "end" or t.s == "nil" or t.s == "true" or t.s == "false" end
		if k == "op" then return t.s == ")" or t.s == "]" or t.s == "}" or t.s == "..." end
		return false
	end

	local function wrapNeeded(nt)
		return nt ~= nil and nt.t == "op" and (nt.s == ":" or nt.s == "." or nt.s == "[" or nt.s == "(" or nt.s == "..")
	end

	local function balanced(toks)
		local depth, br = 0, 0
		for i = 1, #toks do
			local t = toks[i]
			if t.t == "kw" then
				local s = t.s
				if s == "function" or s == "if" or s == "do" or s == "repeat" then
					depth = depth + 1
				elseif s == "end" or s == "until" then
					depth = depth - 1
					if depth < 0 then return false end
				end
			elseif t.t == "op" then
				local s = t.s
				if s == "(" or s == "[" or s == "{" then
					br = br + 1
				elseif s == ")" or s == "]" or s == "}" then
					br = br - 1
					if br < 0 then return false end
				end
			end
		end
		return depth == 0 and br == 0
	end

	local PREC = { ["+"] = 1, ["-"] = 1, ["*"] = 2, ["/"] = 2, ["%"] = 2, ["^"] = 4 }

	local function evalRun(toks, a, b)
		local pos = a
		local top = 99
		local parseExpr
		local function primary(depth)
			local t = toks[pos]
			if pos > b or not t then return nil end
			if t.t == "num" then
				local v = tonumber(t.s)
				if not v then return nil end
				pos = pos + 1
				return v + 0.0
			end
			if isop(t, "(") then
				pos = pos + 1
				local v = parseExpr(1, depth + 1)
				if v == nil or pos > b or not isop(toks[pos], ")") then return nil end
				pos = pos + 1
				return v
			end
			return nil
		end
		local function unary(depth)
			local t = toks[pos]
			if pos <= b and isop(t, "-") then
				pos = pos + 1
				if depth == 0 and top > 3 then top = 3 end
				local v = parseExpr(4, depth)
				if v == nil then return nil end
				return -v
			end
			return primary(depth)
		end
		parseExpr = function(minPrec, depth)
			local lhs = unary(depth)
			if lhs == nil then return nil end
			while pos <= b do
				local t = toks[pos]
				local p = t and t.t == "op" and PREC[t.s]
				if not p or p < minPrec then break end
				pos = pos + 1
				local rhs = parseExpr(t.s == "^" and p or p + 1, depth)
				if rhs == nil then return nil end
				if depth == 0 and p < top then top = p end
				local op = t.s
				if op == "+" then lhs = lhs + rhs
				elseif op == "-" then lhs = lhs - rhs
				elseif op == "*" then lhs = lhs * rhs
				elseif op == "/" then lhs = lhs / rhs
				elseif op == "%" then
					if rhs == 0 or lhs % 1 ~= 0 or rhs % 1 ~= 0 or math.abs(lhs) > 9007199254740992 or math.abs(rhs) > 9007199254740992 then return nil end
					lhs = lhs - floor(lhs / rhs) * rhs
				else lhs = lhs ^ rhs end
			end
			return lhs
		end
		local v = parseExpr(1, 0)
		if v == nil or pos ~= b + 1 then return nil end
		return v, top
	end

	local function numfold(toks, st)
		local out, n, i, m = {}, 0, 1, #toks
		local changed = 0
		while i <= m do
			if i % 256 == 0 then Y() end
			local t = toks[i]
			local prev = out[n]
			local start = false
			if t.t == "num" then
				start = true
			elseif isop(t, "(") and not valueEnd(prev) then
				start = true
			elseif isop(t, "-") and not valueEnd(prev) and toks[i + 1] and (toks[i + 1].t == "num" or isop(toks[i + 1], "(")) then
				start = true
			end
			local done = false
			if start then
				local j = i
				while j <= m do
					local x = toks[j]
					if x.t == "num" or (x.t == "op" and (PREC[x.s] or x.s == "(" or x.s == ")")) then
						if isop(x, "(") and j > i and valueEnd(toks[j - 1]) then break end
						j = j + 1
					else
						break
					end
				end
				j = j - 1
				local k = j
				while k > i do
					local v, top = evalRun(toks, i, k)
					if v ~= nil then
						local size = k - i + 1
						local bnb
						if prev then
							if prev.t == "op" and PREC[prev.s] then
								bnb = PREC[prev.s]
								if prev.s == "-" and not valueEnd(out[n - 1]) then bnb = 3 end
							elseif (prev.t == "kw" and prev.s == "not") or isop(prev, "#") then
								bnb = 3
							end
						end
						local after = toks[k + 1]
						local ana = after and after.t == "op" and PREC[after.s]
						local single = (v >= 0 and size == 1) or (v < 0 and size == 2 and isop(toks[i], "-") and toks[i + 1].t == "num")
						local safe = (not bnb or bnb < top) and (not ana or ana < top)
						if top == 99 then safe = true end
						if after and after.t == "op" and (after.s == "." or after.s == ":" or after.s == "[") then safe = false end
						if not single and safe then
							local rep = numtoks(v, (bnb or ana) and v < 0)
							if rep then
								for q = 1, #rep do
									n = n + 1
									out[n] = rep[q]
								end
								i = k + 1
								changed = changed + 1
								done = true
							end
						end
						break
					end
					k = k - 1
				end
			end
			if not done then
				n = n + 1
				out[n] = t
				i = i + 1
			end
		end
		st.numfold = (st.numfold or 0) + changed
		return out, changed
	end

	local function parseArgs(toks, p)
		local args, j = {}, p + 1
		if isop(toks[j], ")") then return args, j end
		while true do
			local a = toks[j]
			local v
			if a and a.t == "string" then
				v = sval(a)
				if v == nil then return nil end
				j = j + 1
			elseif a and a.t == "num" then
				v = tonumber(a.s)
				if not v then return nil end
				j = j + 1
			elseif isop(a, "-") and toks[j + 1] and toks[j + 1].t == "num" and tonumber(toks[j + 1].s) then
				v = -tonumber(toks[j + 1].s)
				j = j + 2
			else
				return nil
			end
			args[#args + 1] = v
			local d = toks[j]
			if isop(d, ",") then
				j = j + 1
			elseif isop(d, ")") then
				return args, j
			else
				return nil
			end
			if #args > 64 then return nil end
		end
	end

	local function u32(x) return x % 4294967296 end
	local function bitop(f, a, b)
		a, b = u32(floor(a)), u32(floor(b))
		local r, p = 0, 1
		for _ = 1, 32 do
			local x, y = a % 2, b % 2
			if f(x, y) then r = r + p end
			a, b, p = (a - x) / 2, (b - y) / 2, p * 2
		end
		return r
	end

	local function isint(x) return type(x) == "number" and x % 1 == 0 end

	local SF = {
		rep = function(a)
			local s, n, sep = a[1], a[2], a[3]
			if type(s) ~= "string" or not isint(n) or n < 0 or n > 4096 then return nil end
			if sep ~= nil and type(sep) ~= "string" then return nil end
			if (#s + (sep and #sep or 0)) * n > LIM.strlen then return nil end
			return s:rep(n, sep)
		end,
		reverse = function(a) if type(a[1]) == "string" and #a == 1 then return a[1]:reverse() end end,
		lower = function(a) if type(a[1]) == "string" and #a == 1 then return a[1]:lower() end end,
		upper = function(a) if type(a[1]) == "string" and #a == 1 then return a[1]:upper() end end,
		len = function(a) if type(a[1]) == "string" and #a == 1 then return #a[1] end end,
		sub = function(a)
			if type(a[1]) ~= "string" or not isint(a[2]) or (a[3] ~= nil and not isint(a[3])) or #a > 3 then return nil end
			return a[1]:sub(a[2], a[3] or -1)
		end,
		byte = function(a)
			if type(a[1]) ~= "string" or (a[2] ~= nil and not isint(a[2])) or #a > 2 then return nil end
			return a[1]:byte(a[2] or 1)
		end,
		char = function(a)
			if #a == 0 then return nil end
			local parts = {}
			for q = 1, #a do
				if not isint(a[q]) or a[q] < 0 or a[q] > 255 then return nil end
				parts[q] = char(a[q])
			end
			return table.concat(parts)
		end,
	}

	local BF = {
		bxor = function(a, b) return bitop(function(x, y) return x ~= y end, a, b) end,
		band = function(a, b) return bitop(function(x, y) return x == 1 and y == 1 end, a, b) end,
		bor = function(a, b) return bitop(function(x, y) return x == 1 or y == 1 end, a, b) end,
		lshift = function(a, b)
			if not isint(b) or b < 0 then return nil end
			if b >= 32 then return 0 end
			return u32(floor(a) * 2 ^ b)
		end,
		rshift = function(a, b)
			if not isint(b) or b < 0 then return nil end
			if b >= 32 then return 0 end
			return floor(u32(floor(a)) / 2 ^ b)
		end,
	}

	local function foldCall(toks, i, prev)
		local t = toks[i]
		if t.t == "name" and (t.s == "string") and isop(toks[i + 1], ".") and toks[i + 2] and toks[i + 2].t == "name"
			and isop(toks[i + 3], "(") and not (prev and prev.t == "op" and (prev.s == "." or prev.s == ":")) then
			local fn = SF[toks[i + 2].s]
			if not fn then return nil end
			local args, e = parseArgs(toks, i + 3)
			if not args then return nil end
			local ok, v = pcall(fn, args)
			if ok and v ~= nil then return v, e end
			return nil
		end
		if isop(t, "(") and not valueEnd(prev) and toks[i + 1] and toks[i + 1].t == "string" and isop(toks[i + 2], ")")
			and isop(toks[i + 3], ":") and toks[i + 4] and toks[i + 4].t == "name" and isop(toks[i + 5], "(") then
			local s = sval(toks[i + 1])
			local fn = SF[toks[i + 4].s]
			if not s or not fn then return nil end
			local args, e = parseArgs(toks, i + 5)
			if not args then return nil end
			table.insert(args, 1, s)
			local ok, v = pcall(fn, args)
			if ok and v ~= nil then return v, e end
			return nil
		end
		if isop(t, "#") and toks[i + 1] and toks[i + 1].t == "string" and not valueEnd(prev) then
			local s = sval(toks[i + 1])
			local nx = toks[i + 2]
			if s and not (nx and nx.t == "op" and (nx.s == ":" or nx.s == "." or nx.s == "[" or nx.s == "(")) then return #s, i + 1 end
			return nil
		end
		if t.t == "name" and t.s == "table" and isop(toks[i + 1], ".") and toks[i + 2] and toks[i + 2].t == "name" and toks[i + 2].s == "concat"
			and isop(toks[i + 3], "(") and isop(toks[i + 4], "{") and not (prev and prev.t == "op" and (prev.s == "." or prev.s == ":")) then
			local j, parts = i + 5, {}
			while true do
				local a = toks[j]
				if a and a.t == "string" then
					local v = sval(a)
					if not v then return nil end
					parts[#parts + 1] = v
					j = j + 1
				elseif a and a.t == "num" and tonumber(a.s) then
					parts[#parts + 1] = numstr(tonumber(a.s))
					j = j + 1
				else
					return nil
				end
				local d = toks[j]
				if isop(d, ",") or isop(d, ";") then
					j = j + 1
					if isop(toks[j], "}") then
						j = j + 1
						break
					end
				elseif isop(d, "}") then
					j = j + 1
					break
				else
					return nil
				end
			end
			local sep = ""
			if isop(toks[j], ",") then
				local s = sval(toks[j + 1])
				if not s then return nil end
				sep = s
				j = j + 2
			end
			if not isop(toks[j], ")") then return nil end
			local r = table.concat(parts, sep)
			if #r > LIM.strlen then return nil end
			return r, j
		end
		if t.t == "name" and (t.s == "bit32" or t.s == "bit") and isop(toks[i + 1], ".") and toks[i + 2] and toks[i + 2].t == "name"
			and isop(toks[i + 3], "(") and not (prev and prev.t == "op" and (prev.s == "." or prev.s == ":")) then
			local nm = toks[i + 2].s
			local args, e = parseArgs(toks, i + 3)
			if not args then return nil end
			for q = 1, #args do if type(args[q]) ~= "number" then return nil end end
			local ok, v
			if nm == "bnot" and #args == 1 then
				ok, v = true, 4294967295 - u32(floor(args[1]))
			elseif BF[nm] and #args == 2 then
				ok, v = pcall(BF[nm], args[1], args[2])
			else
				return nil
			end
			if ok and v ~= nil then return v, e end
		end
		return nil
	end

	local function strfold(toks, st)
		local out, n, i, m = {}, 0, 1, #toks
		local changed = 0
		while i <= m do
			if i % 256 == 0 then Y() end
			local t = toks[i]
			local prev = out[n]
			local v, e = foldCall(toks, i, prev)
			if v ~= nil then
				local nt = toks[e + 1]
				local rep
				if type(v) == "string" then
					rep = { mkstr(v) }
				else
					rep = numtoks(v, false)
				end
				if rep then
					local wrap = wrapNeeded(nt) and (type(v) == "string" or true)
					if type(v) == "number" and nt and nt.t == "op" and nt.s ~= ".." and nt.s ~= ":" and nt.s ~= "." and nt.s ~= "[" and nt.s ~= "(" then
						wrap = false
					end
					if wrap then
						n = n + 1
						out[n] = mkop("(")
					end
					for q = 1, #rep do
						n = n + 1
						out[n] = rep[q]
					end
					if wrap then
						n = n + 1
						out[n] = mkop(")")
					end
					i = e + 1
					changed = changed + 1
				else
					n = n + 1
					out[n] = t
					i = i + 1
				end
			elseif isop(t, "[") and toks[i + 1] and toks[i + 1].t == "string" and isop(toks[i + 2], "]") and valueEnd(prev) then
				local s = sval(toks[i + 1])
				if s and s:match("^[%a_][%w_]*$") and not TK.kw[s] and #s <= 64 then
					n = n + 1
					out[n] = mkop(".")
					n = n + 1
					out[n] = { t = "name", s = s }
					i = i + 3
					changed = changed + 1
				else
					n = n + 1
					out[n] = t
					i = i + 1
				end
			else
				n = n + 1
				out[n] = t
				i = i + 1
			end
		end
		st.strfold = (st.strfold or 0) + changed
		return out, changed
	end

	local function stmtStart(toks, k)
		local p = toks[k - 1]
		if p == nil then return true end
		if valueEnd(p) then return true end
		if p.t == "kw" and (p.s == "do" or p.s == "then" or p.s == "else" or p.s == "repeat" or p.s == "end") then return true end
		return isop(p, ";")
	end

	local function strtab(toks, st)
		local cands, byName = {}, {}
		local m = #toks
		for i = 1, m - 4 do
			if iskw(toks[i], "local") and toks[i + 1].t == "name" and isop(toks[i + 2], "=") and isop(toks[i + 3], "{") then
				local j, vals, ok = i + 4, {}, true
				if isop(toks[j], "}") then ok = false end
				while ok do
					local a = toks[j]
					local v
					if a and a.t == "string" then
						v = sval(a)
						if v == nil then ok = false break end
						j = j + 1
					elseif a and a.t == "num" and tonumber(a.s) then
						v = tonumber(a.s)
						j = j + 1
					elseif isop(a, "-") and toks[j + 1] and toks[j + 1].t == "num" and tonumber(toks[j + 1].s) then
						v = -tonumber(toks[j + 1].s)
						j = j + 2
					else
						ok = false
						break
					end
					vals[#vals + 1] = v
					local d = toks[j]
					if isop(d, ",") or isop(d, ";") then
						j = j + 1
						if isop(toks[j], "}") then
							j = j + 1
							break
						end
					elseif isop(d, "}") then
						j = j + 1
						break
					else
						ok = false
					end
					if #vals > 5000 then ok = false end
				end
				if ok and #vals > 0 then
					local nm = toks[i + 1].s
					if not byName[nm] then
						local c = { name = nm, decl = i, last = j - 1, vals = vals, uses = {}, bad = false }
						cands[#cands + 1] = c
						byName[nm] = c
					else
						byName[nm].bad = true
					end
				end
			end
		end
		if #cands == 0 then return toks, 0 end
		for i = 1, m do
			if i % 1024 == 0 then Y() end
			local t = toks[i]
			if t.t == "name" then
				local c = byName[t.s]
				local p = toks[i - 1]
				if c and not c.bad and not (p and p.t == "op" and (p.s == "." or p.s == ":")) then
					if i == c.decl + 1 then
					elseif i <= c.last then
						c.bad = true
					else
						local a, b, d, nx = toks[i + 1], toks[i + 2], toks[i + 3], toks[i + 4]
						if isop(a, "[") and b and b.t == "num" and isop(d, "]") and not isop(nx, "=") and not stmtStart(toks, i) then
							local idx = tonumber(b.s)
							if idx and idx % 1 == 0 and idx >= 1 and idx <= #c.vals then
								c.uses[#c.uses + 1] = { at = i, idx = idx }
							else
								c.bad = true
							end
						else
							c.bad = true
						end
					end
				end
			end
		end
		local rep, drop = {}, {}
		local changed = 0
		for _, c in ipairs(cands) do
			if not c.bad and #c.uses > 0 then
				for _, u in ipairs(c.uses) do rep[u.at] = { c = c, idx = u.idx } end
				drop[c.decl] = c.last
				changed = changed + #c.uses
			end
		end
		if changed == 0 then return toks, 0 end
		local out, n, i = {}, 0, 1
		while i <= m do
			if drop[i] then
				i = drop[i] + 1
			elseif rep[i] then
				local r = rep[i]
				local v = r.c.vals[r.idx]
				local nt = toks[i + 4]
				local pt = out[n]
				local toksR
				if type(v) == "string" then
					toksR = { mkstr(v) }
					if wrapNeeded(nt) then toksR = { mkop("("), toksR[1], mkop(")") } end
				else
					toksR = numtoks(v, true) or { { t = "num", s = "0" } }
					if v >= 0 and wrapNeeded(nt) then toksR = { mkop("("), toksR[1], mkop(")") } end
				end
				for q = 1, #toksR do
					n = n + 1
					out[n] = toksR[q]
				end
				i = i + 4
			else
				n = n + 1
				out[n] = toks[i]
				i = i + 1
			end
		end
		st.strtab = (st.strtab or 0) + changed
		return out, changed
	end

	local function cmpLit(a, op, b)
		local ta, tb = type(a), type(b)
		if op == "==" then return a == b end
		if op == "~=" then return a ~= b end
		if ta ~= tb or (ta ~= "number" and ta ~= "string") then return nil end
		if op == "<" then return a < b end
		if op == "<=" then return a <= b end
		if op == ">" then return a > b end
		if op == ">=" then return a >= b end
		return nil
	end

	local CMP = { ["=="] = true, ["~="] = true, ["<"] = true, ["<="] = true, [">"] = true, [">="] = true }
	local CTX_PREV = { ["if"] = true, ["elseif"] = true, ["while"] = true, ["until"] = true, ["and"] = true, ["or"] = true }
	local CTX_NEXT = { ["then"] = true, ["do"] = true, ["and"] = true, ["or"] = true }

	local function litVal(t)
		if not t then return false end
		if t.t == "num" then
			local v = tonumber(t.s)
			if v then return true, v end
			return false
		end
		if t.t == "string" then
			local v = sval(t)
			if v ~= nil then return true, v end
			return false
		end
		if t.t == "kw" then
			if t.s == "true" then return true, true end
			if t.s == "false" then return true, false end
			if t.s == "nil" then return true, nil end
		end
		return false
	end

	local function cmpfold(toks)
		local out, n, i, m = {}, 0, 1, #toks
		local changed = 0
		while i <= m do
			local t = toks[i]
			local done = false
			local op = toks[i + 1]
			if op and op.t == "op" and CMP[op.s] and toks[i + 2] then
				local okA, a = litVal(t)
				local okB, b = litVal(toks[i + 2])
				if okA and okB then
					local prev, after = out[n], toks[i + 3]
					local pOk = prev and ((prev.t == "kw" and CTX_PREV[prev.s]) or isop(prev, "("))
					local aOk = after and ((after.t == "kw" and CTX_NEXT[after.s]) or isop(after, ")"))
					if pOk and aOk then
						local r = cmpLit(a, op.s, b)
						if r ~= nil then
							n = n + 1
							out[n] = mkkw(r and "true" or "false")
							i = i + 3
							changed = changed + 1
							done = true
						end
					end
				end
			end
			if not done then
				n = n + 1
				out[n] = t
				i = i + 1
			end
		end
		return out, changed
	end

	local function blockEnd(toks, from)
		local depth, elseAt = 1, nil
		local m = #toks
		for k = from, m do
			local t = toks[k]
			if t.t == "kw" then
				local s = t.s
				if s == "function" or s == "if" or s == "do" or s == "repeat" then
					depth = depth + 1
				elseif s == "end" or s == "until" then
					depth = depth - 1
					if depth == 0 then return k, elseAt, false end
				elseif depth == 1 and s == "elseif" then
					return nil, nil, true
				elseif depth == 1 and s == "else" and not elseAt then
					elseAt = k
				end
			end
		end
		return nil
	end

	local function dead(toks, st)
		local c0
		toks, c0 = cmpfold(toks)
		local out, n, i, m = {}, 0, 1, #toks
		local changed = c0
		while i <= m do
			if i % 256 == 0 then Y() end
			local t = toks[i]
			local done = false
			if iskw(t, "if") or iskw(t, "while") then
				local isIf = t.s == "if"
				local k = i + 1
				local neg = false
				if iskw(toks[k], "not") then
					neg = true
					k = k + 1
				end
				local okL, v = litVal(toks[k])
				local closer = toks[k + 1]
				if okL and closer and closer.t == "kw" and closer.s == (isIf and "then" or "do") and (toks[k].t == "kw") then
					local truth = v ~= nil and v ~= false
					if neg then truth = not truth end
					local e, elseAt, hasElif = blockEnd(toks, k + 2)
					if e and not hasElif then
						if isIf then
							if truth then
								out[n + 1] = mkkw("do")
								n = n + 1
								for q = k + 2, (elseAt or e) - 1 do
									n = n + 1
									out[n] = toks[q]
								end
								n = n + 1
								out[n] = mkkw("end")
							elseif elseAt then
								n = n + 1
								out[n] = mkkw("do")
								for q = elseAt + 1, e - 1 do
									n = n + 1
									out[n] = toks[q]
								end
								n = n + 1
								out[n] = mkkw("end")
							end
							i = e + 1
							changed = changed + 1
							done = true
						elseif not truth then
							i = e + 1
							changed = changed + 1
							done = true
						end
					end
				end
			end
			if not done then
				n = n + 1
				out[n] = t
				i = i + 1
			end
		end
		st.dead = (st.dead or 0) + changed
		return out, changed
	end

	local function junk(nm)
		if #nm >= 4 and nm:match("^[Il1]+$") then return true end
		if #nm >= 6 and nm:match("^[IlO0o1_]+$") then return true end
		if nm:match("^l_%d+_%d+$") or nm:match("^%a_%d+_%d+$") or nm:match("^_0x%x+$") or nm:match("^_x%x+$") then return true end
		if #nm >= 5 and nm:match("^[A-Za-z]%d%d%d%d+$") then return true end
		return false
	end

	local STMT_KW = { ["local"] = true, ["if"] = true, ["for"] = true, ["while"] = true, ["do"] = true, ["repeat"] = true, ["return"] = true,
		["break"] = true, ["end"] = true, ["else"] = true, ["elseif"] = true, ["until"] = true, ["function"] = true }

	local function scoperename(toks, st)
		local m = #toks
		local frames = {}
		local pends = {}
		local decls = {}
		local bd, br = 0, 0
		local tmap = {}
		local luau = false
		local brk = {}
		local used = {}
		for i = 1, m do
			if toks[i].t == "name" then used[toks[i].s] = true end
			local t = toks[i]
			if t.t == "op" and (t.s == "->" or t.s == "::" or t.s == "+=" or t.s == "-=" or t.s == "*=" or t.s == "/=" or t.s == "..=") then return toks, 0 end
		end

		local function push(kind) frames[#frames + 1] = { kind = kind, vars = {} } end
		local function pop() frames[#frames] = nil end
		local function declare(tokIdx, kind, frame)
			local tk = toks[tokIdx]
			local d = { name = tk.s, kind = kind, toks = { tokIdx }, uses = 0 }
			decls[#decls + 1] = d
			tmap[tokIdx] = d
			frame = frame or frames[#frames]
			frame.vars[tk.s] = d
			return d
		end
		local function lookup(nm)
			for f = #frames, 1, -1 do
				local d = frames[f].vars[nm]
				if d then return d end
			end
			return nil
		end

		push("root")
		local i = 1
		local function startsStmt(k)
			local t = toks[k]
			if t.t == "kw" and STMT_KW[t.s] then
				if t.s == "function" then return valueEnd(toks[k - 1]) end
				return true
			end
			if t.t == "name" then return valueEnd(toks[k - 1]) end
			return false
		end

		while i <= m do
			if i % 256 == 0 then Y() end
			local t = toks[i]
			while #pends > 0 do
				local p = pends[#pends]
				if p.bd == bd and p.br == br and i > p.from and startsStmt(i) then
					if p.kind == "local" then
						for _, ix in ipairs(p.names) do declare(ix, p.dk, p.frame) end
					else
						pop()
					end
					pends[#pends] = nil
				else
					break
				end
			end
			if t.t == "kw" then
				local s = t.s
				if s == "local" then
					local nx = toks[i + 1]
					if iskw(nx, "function") then
						if toks[i + 2] and toks[i + 2].t == "name" then declare(i + 2, "func") end
					else
						local names, k = {}, i + 1
						while toks[k] and toks[k].t == "name" do
							names[#names + 1] = k
							k = k + 1
							if isop(toks[k], ":") then luau = true end
							if isop(toks[k], ",") then k = k + 1 else break end
						end
						if luau or #names == 0 then return toks, 0 end
						pends[#pends + 1] = { kind = "local", names = names, bd = bd, br = br, from = k - 1, dk = "var", frame = frames[#frames] }
						for _, ix in ipairs(names) do tmap[ix] = false end
						i = k - 1
						if not (isop(toks[k], "=")) then
							local p = pends[#pends]
							pends[#pends] = nil
							for _, ix in ipairs(p.names) do declare(ix, p.dk, p.frame) end
						end
					end
				elseif s == "function" then
					push("func")
					bd = bd + 1
					local k = i + 1
					while toks[k] and not isop(toks[k], "(") do k = k + 1 end
					if not toks[k] then return toks, 0 end
					for q = i + 1, k - 1 do
						local x = toks[q]
						if x.t == "name" and tmap[q] == nil then
							local p2 = toks[q - 1]
							if not (p2 and p2.t == "op" and (p2.s == "." or p2.s == ":")) then
								local d = lookup(x.s)
								if d then
									tmap[q] = d
									d.toks[#d.toks + 1] = q
								end
							end
						end
					end
					local pframe = frames[#frames]
					k = k + 1
					while toks[k] and not isop(toks[k], ")") do
						if toks[k].t == "name" then
							declare(k, "param", pframe)
							if isop(toks[k + 1], ":") then return toks, 0 end
						end
						k = k + 1
					end
					i = k
				elseif s == "for" then
					push("for")
					local names, k = {}, i + 1
					while toks[k] and toks[k].t == "name" do
						names[#names + 1] = k
						k = k + 1
						if isop(toks[k], ":") then return toks, 0 end
						if isop(toks[k], ",") then k = k + 1 else break end
					end
					frames[#frames].names = names
					for _, ix in ipairs(names) do tmap[ix] = false end
					i = k - 1
				elseif s == "do" then
					local top = frames[#frames]
					bd = bd + 1
					if top.kind == "for" and not top.started then
						top.started = true
						for _, ix in ipairs(top.names or {}) do declare(ix, "loop", top) end
					else
						push("do")
					end
				elseif s == "while" then
				elseif s == "if" then
					bd = bd + 1
				elseif s == "then" then
					push("then")
				elseif s == "elseif" then
					if frames[#frames].kind == "then" then pop() end
				elseif s == "else" then
					if frames[#frames].kind == "then" then pop() end
					push("else")
				elseif s == "repeat" then
					bd = bd + 1
					push("repeat")
				elseif s == "until" then
					bd = bd - 1
					pends[#pends + 1] = { kind = "pop", bd = bd, br = br, from = i }
				elseif s == "end" then
					bd = bd - 1
					pop()
					if bd < 0 or #frames < 1 then return toks, 0 end
				end
			elseif t.t == "op" then
				local s = t.s
				if s == "(" or s == "[" or s == "{" then
					br = br + 1
					brk[#brk + 1] = s
				elseif s == ")" or s == "]" or s == "}" then
					br = br - 1
					brk[#brk] = nil
				end
			elseif t.t == "name" and tmap[i] == nil then
				local p = toks[i - 1]
				local nx = toks[i + 1]
				local member = p and p.t == "op" and (p.s == "." or p.s == ":")
				if not member and p and p.t == "op" and (p.s == "{" or p.s == "," or p.s == ";") and brk[#brk] == "{" and isop(nx, "=") then member = true end
				if not member then
					local d = lookup(t.s)
					if d then
						tmap[i] = d
						d.toks[#d.toks + 1] = i
					end
				end
			end
			i = i + 1
		end
		if bd ~= 0 or #frames ~= 1 then return toks, 0 end

		local map, count = {}, 0
		local counters = { var = 0, func = 0, param = 0, loop = 0 }
		local prefix = { var = "v", func = "f", param = "p", loop = "i" }
		for _, d in ipairs(decls) do
			if junk(d.name) and #d.toks >= 1 then
				local kd = d.kind
				local nn
				repeat
					counters[kd] = counters[kd] + 1
					nn = prefix[kd] .. counters[kd]
				until not used[nn]
				used[nn] = true
				for _, ix in ipairs(d.toks) do map[ix] = nn end
				count = count + 1
			end
		end
		if count == 0 then return toks, 0 end
		local out = {}
		for q = 1, m do
			local t = toks[q]
			if map[q] then
				out[q] = { t = "name", s = map[q] }
			else
				out[q] = t
			end
		end
		st.rename = (st.rename or 0) + count
		return out, count
	end

	local function markers(toks, src)
		local flags = {}
		local whileTrue, chain, bin, strs, bigstr, iife = 0, 0, 0, 0, 0, false
		local m = #toks
		if m >= 4 and ((iskw(toks[1], "return") and isop(toks[2], "(") and iskw(toks[3], "function")) or (isop(toks[1], "(") and iskw(toks[2], "function"))) then
			iife = true
		end
		for i = 1, m do
			local t = toks[i]
			if t.t == "kw" and t.s == "while" and iskw(toks[i + 1], "true") then
				whileTrue = whileTrue + 1
			elseif t.t == "kw" and t.s == "elseif" and toks[i + 1] and toks[i + 1].t == "name" and isop(toks[i + 2], "==") and toks[i + 3] and toks[i + 3].t == "num" then
				chain = chain + 1
			elseif t.t == "kw" and t.s == "if" and toks[i + 1] and toks[i + 1].t == "name" and toks[i + 2] and toks[i + 2].t == "op"
				and (toks[i + 2].s == "<" or toks[i + 2].s == "<=") and toks[i + 3] and toks[i + 3].t == "num" then
				bin = bin + 1
			elseif t.t == "string" then
				local v = t.v
				if v and #v >= 2000 then
					local nonprint = select(2, v:sub(1, 400):gsub("[^%w%s%p]", ""))
					if nonprint > 40 or (#v >= 4000 and v:match("^[%w%+/=]+$")) then bigstr = bigstr + 1 end
				end
				strs = strs + 1
			end
		end
		if iife then flags[#flags + 1] = "deobf: wrapped in a single anonymous function" end
		if chain >= 12 then flags[#flags + 1] = "deobf: dispatch chain with " .. chain .. " numeric branches (VM or control-flow flattening likely; structure not restored)" end
		if bin >= 12 then flags[#flags + 1] = "deobf: binary-search dispatch with " .. bin .. " branches (VM style)" end
		if whileTrue > 0 and (chain >= 12 or bin >= 12) then flags[#flags + 1] = "deobf: dispatch loop present" end
		if bigstr > 0 then flags[#flags + 1] = "deobf: " .. bigstr .. " encoded blob string(s) not decoded statically" end
		return flags
	end

	local function layerScan(toks, rep)
		if type(rep) ~= "table" then return 0 end
		rep.layers = rep.layers or {}
		local have, added = {}, 0
		for _, l in ipairs(rep.layers) do have[#l.src .. ":" .. l.src:sub(1, 32)] = true end
		for i = 1, #toks - 3 do
			local t = toks[i]
			if t.t == "name" and (t.s == "loadstring" or t.s == "load") and isop(toks[i + 1], "(") and toks[i + 2] and toks[i + 2].t == "string"
				and isop(toks[i + 3], ")") and #rep.layers < LIM.layers then
				local p = toks[i - 1]
				if not (p and p.t == "op" and (p.s == "." or p.s == ":")) then
					local v = sval(toks[i + 2])
					if v and #v >= 24 then
						local key = #v .. ":" .. v:sub(1, 32)
						if not have[key] then
							have[key] = true
							rep.layers[#rep.layers + 1] = { src = v, via = "loadstring literal (deobf)" }
							added = added + 1
						end
					end
				end
			end
		end
		return added
	end

	local function compiles(text)
		local fn = loadstring or load
		if type(fn) ~= "function" then return true end
		local ok, f = pcall(fn, text)
		return ok and f ~= nil
	end

	local function runPass(name, toks, st)
		if name == "numfold" then return numfold(toks, st) end
		if name == "strfold" then return strfold(toks, st) end
		if name == "strtab" then return strtab(toks, st) end
		if name == "dead" then return dead(toks, st) end
		return scoperename(toks, st)
	end

	local function strip(toks)
		local out, n = {}, 0
		for i = 1, #toks do
			local t = toks[i]
			if t.t ~= "comment" and t.t ~= "lcomment" then
				n = n + 1
				out[n] = t
			end
		end
		return out
	end

	function F.deobf(text, rep, opts)
		opts = opts or {}
		lastY = clock()
		local t0 = clock()
		local info = { passes = {}, rolled = {}, changed = 0, flags = {} }
		if type(text) ~= "string" or #text == 0 or #text > LIM.src then return text, info end
		local wanted = {}
		for _, p in ipairs(opts.passes or PASSES) do wanted[p] = true end
		local origOk = compiles(text)
		local toks = strip(tokenize(text))
		local st = {}
		local function snapshot() return format(toks) end
		local base = snapshot()
		local function try(name)
			local before = toks
			local ok, nt, c = pcall(runPass, name, toks, st)
			if not ok then
				info.rolled[#info.rolled + 1] = name .. ":error"
				toks = before
				return 0
			end
			if c and c > 0 then
				if not balanced(nt) then
					info.rolled[#info.rolled + 1] = name .. ":unbalanced"
					return 0
				end
				toks = nt
				return c
			end
			return 0
		end
		for round = 1, LIM.rounds do
			local c = 0
			for _, name in ipairs({ "numfold", "strfold", "strtab", "dead" }) do
				if wanted[name] and clock() - t0 < LIM.timeout then c = c + try(name) end
			end
			if c == 0 then break end
		end
		if wanted.rename and clock() - t0 < LIM.timeout then try("rename") end
		local okf, out = pcall(format, toks)
		if not okf or type(out) ~= "string" then
			info.rolled[#info.rolled + 1] = "format"
			return text, info
		end
		if origOk and not compiles(out) then
			local good = base
			local cur = strip(tokenize(base))
			toks = cur
			st = {}
			for _, name in ipairs(PASSES) do
				if wanted[name] then
					local snap = toks
					local c = try(name)
					if c > 0 then
						local okp, txt = pcall(format, toks)
						if okp and type(txt) == "string" and compiles(txt) then
							good = txt
						else
							toks = snap
							info.rolled[#info.rolled + 1] = name .. ":compile"
						end
					end
				end
			end
			out = good
		end
		for _, name in ipairs(PASSES) do
			if st[name] and st[name] > 0 then
				info.passes[name] = st[name]
				info.changed = info.changed + st[name]
			end
		end
		info.layers = layerScan(toks, rep)
		info.flags = markers(toks, out)
		info.ms = floor((clock() - t0) * 1000)
		if info.changed == 0 and #info.rolled == 0 and #info.flags == 0 and info.layers == 0 then return text, info end
		return out, info
	end

	local function record(name, info)
		DB.runs = DB.runs + 1
		DB.changed = DB.changed + info.changed
		DB.rolled = DB.rolled + #info.rolled
		for p, c in pairs(info.passes) do DB.passes[p] = (DB.passes[p] or 0) + c end
		for _, fl in ipairs(info.flags) do DB.flags[fl] = (DB.flags[fl] or 0) + 1 end
		DB.items[#DB.items + 1] = { f = name, changed = info.changed, rolled = #info.rolled > 0 and info.rolled or nil, flags = #info.flags > 0 and info.flags or nil, ms = info.ms }
		for i = #DB.items, 61, -1 do table.remove(DB.items, 1) end
	end

	local baseDC = F.decodeCore
	F.decodeCore = function(src)
		local text, rep, stats = baseDC(src)
		if CFG.autoDeobf and type(text) == "string" and #text <= LIM.src then
			local ok, t2, info = pcall(F.deobf, text, rep)
			if ok and type(t2) == "string" then
				text = t2
				stats.deob = info.changed
				if type(rep) == "table" and type(rep.flags) == "table" then
					if info.changed > 0 then
						local parts = {}
						for p, c in pairs(info.passes) do parts[#parts + 1] = p .. " " .. c end
						table.sort(parts)
						table.insert(rep.flags, 1, "deobf: " .. table.concat(parts, ", "))
					end
					for _, fl in ipairs(info.flags) do rep.flags[#rep.flags + 1] = fl end
					if #info.rolled > 0 then rep.flags[#rep.flags + 1] = "deobf: rolled back " .. table.concat(info.rolled, ", ") end
				end
				record("auto", info)
			elseif not ok then
				DB.errors = DB.errors + 1
				noteErr("deobf:" .. tostring(t2))
			end
		end
		return text, rep, stats
	end

	local function outFile(nm)
		local b = (nm or "inline"):match("([^/\\]+)$") or "inline"
		b = b:gsub("%.lua$", ""):gsub("%.dec$", "")
		if nm == "inline" or not nm then b = "inline_" .. os.time() end
		return b .. ".deobf.lua"
	end

	local function emit(name, text, info)
		local lines = { "AluzSpy deobfuscation report" }
		local parts = {}
		for p, c in pairs(info.passes) do parts[#parts + 1] = p .. " " .. c end
		table.sort(parts)
		lines[#lines + 1] = "changes: " .. (#parts > 0 and table.concat(parts, ", ") or "none")
		for _, fl in ipairs(info.flags) do lines[#lines + 1] = fl end
		if #info.rolled > 0 then lines[#lines + 1] = "rolled back: " .. table.concat(info.rolled, ", ") end
		local hdr = "--[==[\n" .. table.concat(lines, "\n"):gsub("%]==%]", "] ==]") .. "\n]==]\n"
		local f = outFile(name)
		D.pending = D.pending + #text
		D.t = D.t + 1
		D.q[D.t] = { f = f, s = hdr .. text }
		return f
	end

	local function runNow(body, name, opts)
		local prev = busy
		busy = true
		local rep = { flags = {}, layers = {}, urls = {}, services = {}, names = {} }
		local ok, text, info = pcall(F.deobf, body, rep, opts)
		busy = prev
		if not ok then
			DB.errors = DB.errors + 1
			noteErr("deobf:" .. tostring(text))
			return nil, tostring(text)
		end
		record(name or "inline", info)
		local f = emit(name, text, info)
		return text, f, info
	end

	local function api(x, opts)
		local body, name = F.resolveSrc and F.resolveSrc(x)
		if not body then
			warn("[AluzSpy] deobf: nothing to process")
			return nil
		end
		if #body > 60000 and F.job then
			local queued = F.job("deobf", function()
				local text, f, info = runNow(body, name, opts)
				if text then warn("[AluzSpy] deobf " .. tostring(f) .. " changes " .. tostring(info and info.changed)) end
			end, nil, { prio = 3, timeout = 60 })
			return queued and "queued" or nil
		end
		local text, f, info = runNow(body, name, opts)
		if text then warn("[AluzSpy] deobf " .. tostring(f) .. " changes " .. tostring(info and info.changed)) end
		return text, f, info
	end

	local function deobfAll()
		local c = 0
		for _, ent in ipairs(D.list) do
			if c >= 24 then break end
			if not ent.dup and ent.f and ent.cat ~= "bytecode" and not ent.f:find("%.dec%.lua$") and not ent.f:find("%.deobf%.lua$") then
				local ok = F.job("deobf", function()
					local body = FS.read(PATH.d(ent.f))
					if body then runNow(body, ent.f) end
				end, nil, { prio = 3, timeout = 60 })
				if ok then c = c + 1 end
			end
		end
		return c
	end

	function F.deobfReport()
		return {
			runs = DB.runs, changed = DB.changed, rolled_back = DB.rolled, errors = DB.errors, auto = CFG.autoDeobf == true,
			passes = DB.passes, flags = DB.flags, recent = DB.items,
		}
	end
	F.extra.deobf = function()
		return { runs = DB.runs, changed = DB.changed, rolled_back = DB.rolled, auto = CFG.autoDeobf == true }
	end

	F.apiMerge({ deobf = api, deobfAll = deobfAll, deobfReport = F.deobfReport })
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okDO then
	warn("[AluzSpy] deobfuscate failed: " .. tostring(errDO))
end
