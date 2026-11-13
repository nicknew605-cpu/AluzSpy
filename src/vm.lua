do local _ = "aluzspy@1.2.3-stable" if F and F.trace then F.trace("load vm") end end
local okVM, errVM = xpcall(function()
	if type(D) ~= "table" then return end
	if CFG.vmdump == nil then CFG.vmdump = true end
	if CFG.bytecode == nil then CFG.bytecode = true end
	if CFG.strings == nil then CFG.strings = true end

	local VM = { runs = 0, ok = 0, fail = 0, strings = 0, captures = 0, protos = 0, ins = 0 }
	F.vm = VM

	local OPS = {
		"MOVE", "LOADK", "LOADBOOL", "LOADNIL", "GETUPVAL", "GETGLOBAL", "GETTABLE", "SETGLOBAL",
		"SETUPVAL", "SETTABLE", "NEWTABLE", "SELF", "ADD", "SUB", "MUL", "DIV", "MOD", "POW",
		"UNM", "NOT", "LEN", "CONCAT", "JMP", "EQ", "LT", "LE", "TEST", "TESTSET",
		"CALL", "TAILCALL", "RETURN", "FORLOOP", "FORPREP", "TFORCALL", "TFORLOOP", "SETLIST",
		"CLOSE", "CLOSURE", "VARARG",
	}
	local OPM = {}
	for i, v in ipairs(OPS) do OPM[v] = i - 1 end
	local ARITH = { ADD = "+", SUB = "-", MUL = "*", DIV = "/", MOD = "%", POW = "^" }

	local function mkReader(s)
		local pos = 1
		local r = {}
		function r.byte()
			local v = s:byte(pos)
			pos = pos + 1
			return v or 0
		end
		function r.bytes(n)
			local v = s:sub(pos, pos + n - 1)
			pos = pos + n
			return v
		end
		function r.skip(n) pos = pos + n end
		function r.at() return pos end
		function r.seek(p) pos = p end
		return r
	end

	local function parseHeader(s)
		if type(s) ~= "string" or #s < 12 then return nil end
		if s:sub(1, 4) ~= "\27Lua" then return nil end
		local ver = s:byte(5)
		local fmt = s:byte(6)
		local endian = s:byte(7)
		local sizeInt = s:byte(8)
		local sizeSizeT = s:byte(9)
		local sizeInstr = s:byte(10)
		local sizeNum = s:byte(11)
		local integral = s:byte(12)
		return {
			ver = ver, fmt = fmt, endian = endian, sizeInt = sizeInt, sizeSizeT = sizeSizeT,
			sizeInstr = sizeInstr, sizeNum = sizeNum, integral = integral == 1,
			little = endian == 1,
		}
	end

	local function readNumber(r, h)
		local bytes = {}
		for i = 0, h.sizeNum - 1 do bytes[i] = r.byte() end
		if h.integral then
			local v = 0
			if h.little then
				for i = h.sizeNum - 1, 0, -1 do v = v * 256 + bytes[i] end
			else
				for i = 0, h.sizeNum - 1 do v = v * 256 + bytes[i] end
			end
			return v
		end
		local bits = {}
		if h.little then
			for i = h.sizeNum - 1, 0, -1 do bits[#bits + 1] = bytes[i] end
		else
			for i = 0, h.sizeNum - 1 do bits[#bits + 1] = bytes[i] end
		end
		local sign = 1
		local exp = 0
		for i = 1, 11 do exp = exp + bits[i] * 2 ^ (11 - i) end
		local mant = 0
		for i = 12, #bits do mant = mant + bits[i] * 2 ^ (#bits - i) end
		if exp == 0 then exp = 1 else exp = exp - 1023 end
		local v = mant * 2 ^ (exp - 52)
		if sign < 0 then v = -v end
		return v
	end

	local function readInt(r, h)
		local bytes = {}
		for i = 0, h.sizeInt - 1 do bytes[i] = r.byte() end
		local v = 0
		if h.little then
			for i = h.sizeInt - 1, 0, -1 do v = v * 256 + bytes[i] end
		else
			for i = 0, h.sizeInt - 1 do v = v * 256 + bytes[i] end
		end
		return v
	end

	local function readString(r, h)
		local len = 0
		local bytes = {}
		for i = 0, h.sizeSizeT - 1 do bytes[i] = r.byte() end
		if h.little then
			for i = h.sizeSizeT - 1, 0, -1 do len = len * 256 + bytes[i] end
		else
			for i = 0, h.sizeSizeT - 1 do len = len * 256 + bytes[i] end
		end
		if len == 0 then return nil end
		if len > 4000000 then return nil end
		return r.bytes(len)
	end

	local function readConst(r, h)
		local t = r.byte()
		if t == 0 then return { t = "nil" } end
		if t == 1 then
			local v = r.byte()
			return { t = "boolean", v = v ~= 0 }
		end
		if t == 3 then
			local s = readString(r, h)
			return { t = "string", v = s or "" }
		end
		if t == 2 then
			return { t = "number", v = readNumber(r, h) }
		end
		if t == 4 then
			return { t = "upvalue", v = r.byte() }
		end
		return { t = "unknown" }
	end

	local function readProto(r, h, depth, out, parent)
		local p = { source = readString(r, h) }
		p.line = readInt(r, h)
		p.lastline = readInt(r, h)
		p.nups = r.byte()
		p.numparams = r.byte()
		p.is_vararg = r.byte()
		p.maxstack = r.byte()
		local ncode = readInt(r, h)
		p.code = {}
		p.ncode = ncode
		for i = 1, math.min(ncode, 20000) do
			local op, a, b, c, bx
			if h.sizeInstr == 4 then
				local i1, i2, i3, i4 = r.byte(), r.byte(), r.byte(), r.byte()
				local w = i1 + i2 * 256 + i3 * 65536 + i4 * 16777216
				op = w % 256
				a = floor(w / 256) % 256
				c = floor(w / 65536) % 256
				b = floor(w / 16777216) % 256
				bx = floor(w / 65536)
			else
				op = r.byte()
				a = r.byte()
				b = r.byte()
				c = r.byte()
				bx = a * 256 + b
			end
			p.code[i] = { op = op, a = a, b = b, c = c, bx = bx }
		end
		local nk = readInt(r, h)
		p.k = {}
		for i = 1, math.min(nk, 4000) do p.k[i] = readConst(r, h) end
		local np = readInt(r, h)
		p.protos = {}
		if depth < 6 then
			for i = 1, math.min(np, 200) do
				local child = readProto(r, h, depth + 1, out, p)
				p.protos[i] = child
			end
		end
		local nl = readInt(r, h)
		r.skip(math.min(nl, 20000) * h.sizeInt)
		local nv = readInt(r, h)
		r.skip(math.min(nv, 4000) * (h.sizeSizeT * 2))
		local nu = readInt(r, h)
		p.upnames = {}
		for i = 1, math.min(nu, 400) do p.upnames[i] = readString(r, h) end
		return p
	end

	local function constText(k)
		if not k then return "nil" end
		if k.t == "string" then
			local s = tostring(k.v or "")
			if #s > 160 then s = s:sub(1, 160) .. "..." end
			return string.format("%q", s)
		end
		if k.t == "number" then return tostring(k.v) end
		if k.t == "boolean" then return tostring(k.v) end
		if k.t == "upvalue" then return "upval(" .. tostring(k.v) .. ")" end
		return k.t
	end

	local function collectStrings(p, out, depth)
		depth = depth or 0
		if depth > 6 then return end
		for i = 1, #(p.k or {}) do
			local k = p.k[i]
			if k.t == "string" and type(k.v) == "string" and #k.v > 0 then
				out[#out + 1] = k.v
			end
		end
		for i = 1, #(p.protos or {}) do collectStrings(p.protos[i], out, depth + 1) end
	end

	local function countInstr(p, acc)
		acc = acc or { n = 0, protos = 0, jumps = 0, calls = 0, tables = 0, closures = 0 }
		acc.n = acc.n + (p.ncode or 0)
		acc.protos = acc.protos + 1
		for i = 1, #(p.code or {}) do
			local op = p.code[i].op
			local nm = OPS[op + 1]
			if nm == "JMP" or nm == "FORLOOP" or nm == "FORPREP" or nm == "TFORLOOP" then acc.jumps = acc.jumps + 1 end
			if nm == "CALL" or nm == "TAILCALL" then acc.calls = acc.calls + 1 end
			if nm == "GETTABLE" or nm == "SETTABLE" then acc.tables = acc.tables + 1 end
			if nm == "CLOSURE" then acc.closures = acc.closures + 1 end
		end
		for i = 1, #(p.protos or {}) do countInstr(p.protos[i], acc) end
		return acc
	end

	local function vmScore(p, acc)
		acc = acc or { n = 0, protos = 0, jumps = 0, calls = 0, tables = 0, closures = 0 }
		countInstr(p, acc)
		local s = 0
		if acc.protos >= 3 then s = s + 15 end
		if acc.n >= 400 then s = s + 20 end
		if acc.jumps >= 40 then s = s + 20 end
		if acc.tables >= 60 then s = s + 20 end
		if acc.calls >= 80 then s = s + 10 end
		local k = #(p.k or {})
		if k >= 30 then s = s + 15 end
		return math.min(100, s)
	end

	local function emitProto(p, lines, indent, stats)
		local pad = string.rep("  ", indent)
		lines[#lines + 1] = pad .. string.format("function <%s> line=%d params=%d vararg=%d stack=%d upvals=%d code=%d consts=%d",
			tostring(p.source or "?"), p.line or 0, p.numparams or 0, p.is_vararg or 0, p.maxstack or 0, p.nups or 0, p.ncode or 0, #(p.k or {}))
		for i = 1, math.min(#(p.k or {}), 400) do
			lines[#lines + 1] = pad .. "  K[" .. i .. "] = " .. constText(p.k[i])
		end
		for i = 1, math.min(#(p.upnames or {}), 100) do
			lines[#lines + 1] = pad .. "  upval[" .. i .. "] = " .. string.format("%q", tostring(p.upnames[i] or ""))
		end
		for i = 1, math.min(#(p.code or {}), 1200) do
			local c = p.code[i]
			local nm = OPS[c.op + 1] or ("OP" .. tostring(c.op))
			local txt
			if nm == "LOADK" then
				txt = string.format("%-10s R%d K%d (%s)", nm, c.a, c.bx, constText(p.k and p.k[c.bx + 1]))
			elseif nm == "GETGLOBAL" or nm == "SETGLOBAL" then
				txt = string.format("%-10s R%d K%d (%s)", nm, c.a, c.bx, constText(p.k and p.k[c.bx + 1]))
			elseif nm == "GETTABLE" or nm == "SETTABLE" or nm == "SELF" or nm == "ADD" or nm == "SUB"
				or nm == "MUL" or nm == "DIV" or nm == "MOD" or nm == "POW" or nm == "CONCAT" then
				txt = string.format("%-10s R%d R%d R%d", nm, c.a, c.b, c.c)
			elseif nm == "JMP" or nm == "FORLOOP" or nm == "FORPREP" or nm == "TFORLOOP" then
				txt = string.format("%-10s %d -> %d", nm, i, i + (c.bx or 0) - 65535)
			elseif nm == "CALL" or nm == "TAILCALL" or nm == "RETURN" or nm == "SETLIST" then
				txt = string.format("%-10s R%d %d %d", nm, c.a, c.b, c.c)
			elseif nm == "CLOSURE" then
				txt = string.format("%-10s R%d P%d", nm, c.a, c.bx)
			else
				txt = string.format("%-10s R%d %d %d", nm, c.a, c.b, c.c)
			end
			lines[#lines + 1] = pad .. string.format("%4d  %s", i, txt)
			stats.ins = stats.ins + 1
		end
		for i = 1, #(p.protos or {}) do emitProto(p.protos[i], lines, indent + 1, stats) end
	end

	local function disassemble(bc)
		local h = parseHeader(bc)
		if not h then return nil, "no lua header" end
		local r = mkReader(bc)
		r.skip(12)
		local upcount = r.byte()
		local lines = {
			string.format("ALUZSPY BYTECODE DISASSEMBLY  luav=%d format=%d endian=%s int=%d size_t=%d instr=%d num=%d integral=%s upvalues=%d",
				h.ver, h.fmt, h.little and "little" or "big", h.sizeInt, h.sizeSizeT, h.sizeInstr, h.sizeNum,
				tostring(h.integral), upcount),
			"",
		}
		local okp, errp = pcall(function()
			local p = readProto(r, h, 0, {}, nil)
			local stats = { ins = 0 }
			emitProto(p, lines, 0, stats)
			VM.protos = (VM.protos or 0) + countInstr(p).protos
			VM.ins = (VM.ins or 0) + stats.ins
			return p
		end)
		if not okp then return nil, tostring(errp) end
		return lines, nil, h
	end

	local function stringsOf(bc)
		local h = parseHeader(bc)
		if not h then return {} end
		local r = mkReader(bc)
		r.skip(12)
		local upcount = r.byte()
		local out = {}
		pcall(function()
			local p = readProto(r, h, 0, {}, nil)
			collectStrings(p, out, 0)
		end)
		return out
	end

	local function kindFromBytes(bc)
		local h = parseHeader(bc)
		if not h then return nil end
		return h
	end

	function F.vmAnalyze(name, bc)
		VM.runs = VM.runs + 1
		if type(bc) ~= "string" or #bc < 13 then
			VM.fail = VM.fail + 1
			return nil, "empty bytecode"
		end
		local lines, err, h = disassemble(bc)
		if not lines then
			VM.fail = VM.fail + 1
			return nil, err
		end
		local strs = stringsOf(bc)
		local seen, uniq = {}, {}
		for i = 1, #strs do
			local s = strs[i]
			if not seen[s] then
				seen[s] = true
				uniq[#uniq + 1] = s
			end
		end
		local urls = {}
		for i = 1, #uniq do
			local s = uniq[i]
			for u in s:gmatch("https?://[%w%-%._~:/%?#@!%$&%*%+,;=%%]+") do urls[#urls + 1] = u end
		end
		local rep = {
			tool = "AluzSpy", version = VERSION, name = tostring(name or "?"),
			bytes = #bc, header = h and {
				luav = h.ver, format = h.fmt, endian = h.little and "little" or "big",
				int = h.sizeInt, size_t = h.sizeSizeT, instr = h.sizeInstr, num = h.sizeNum,
				integral = h.integral,
			} or nil,
			strings = #uniq, urls = urls, captured = #uniq,
			protos = VM.protos, instructions = VM.ins,
		}
		lines[#lines + 1] = ""
		lines[#lines + 1] = "STRINGS (" .. #uniq .. "):"
		for i = 1, math.min(#uniq, 500) do
			local s = tostring(uniq[i])
			if #s > 200 then s = s:sub(1, 200) .. "..." end
			lines[#lines + 1] = string.format("  [%d] %q", i, s)
		end
		if #urls > 0 then
			lines[#lines + 1] = ""
			lines[#lines + 1] = "URLS:"
			for i = 1, math.min(#urls, 200) do lines[#lines + 1] = "  " .. urls[i] end
		end
		VM.ok = VM.ok + 1
		VM.strings = VM.strings + #uniq
		return table.concat(lines, "\n"), rep, uniq
	end

	function F.vmDump(ent, bc)
		if not CFG.vmdump then return nil end
		local text, rep = F.vmAnalyze(ent and ent.f or "bytecode", bc)
		if not text then return nil end
		local base = (ent and ent.f or "bytecode"):gsub("%.lua$", "")
		local p1 = PATH.d(base .. ".bytecode.txt")
		local p2 = PATH.d(base .. ".bytecode.json")
		FS.write(p1, text)
		if rep then FS.write(p2, F.enc(rep) or "{}") end
		D.extraFiles[base .. ".bytecode.txt"] = #text
		D.extraBytes = (D.extraBytes or 0) + #text
		D.kind.bytecode = (D.kind.bytecode or 0) + #text
		return p1, p2, rep
	end

	local strCap = {}
	local strCapN = 0

	function F.captureString(s, via)
		if type(s) ~= "string" then return end
		if #s < 4 or #s > 4000 then return end
		if strCapN > 4000 then return end
		if strCap[s] then return end
		strCap[s] = true
		strCapN = strCapN + 1
		VM.captures = VM.captures + 1
		F.on(10, "str", function()
			enqueue({ k = 10, s = s, m = via, t = clock() })
		end)
	end

	local stringHooked = false

	local function hookStrings()
		if stringHooked or not CFG.strings then return false end
		local ok = false
		local s = genv.string or _G.string
		if type(s) ~= "table" then return false end
		if type(s.char) == "function" then
			local oc = s.char
			if F.hookWith(s.char, function(holder)
				return function(...)
					local r = holder.old(...)
					if type(r) == "string" then F.captureString(r, "string.char") end
					return r
				end
			end, false, "str_char") then ok = true end
		end
		if type(s.sub) == "function" then
			local os_ = s.sub
			if F.hookWith(s.sub, function(holder)
				return function(str, i, j)
					local r = holder.old(str, i, j)
					if type(r) == "string" and #r >= 4 then F.captureString(r, "string.sub") end
					return r
				end
			end, false, "str_sub") then ok = true end
		end
		if type(table.concat) == "function" then
			if F.hookWith(table.concat, function(holder)
				return function(t, sep)
					local r = holder.old(t, sep)
					if type(r) == "string" and #r >= 4 then F.captureString(r, "table.concat") end
					return r
				end
			end, false, "str_concat") then ok = true end
		end
		stringHooked = ok
		return ok
	end

	IN.st = function()
		MOD.st = false
		INST.st = false
		F.defMods.st = true
		if CFG.mods.st == nil then CFG.mods.st = true end
		local ok = hookStrings()
		MOD.st = ok
		INST.st = ok
		local st = F.reg("strings")
		st.installed = ok
		st.kind = "function"
		st.target = "string.char/string.sub/table.concat"
		return ok
	end
	F.stage("st", 17, IN.st)

	F.h[10] = function(e, now)
		if not takeToken(now) then
			N.bucket = N.bucket + 1
			return
		end
		local s = e.s
		if type(s) ~= "string" then return end
		if #s > 300 then s = s:sub(1, 300) .. "..." end
		newRec("STR", s, e.m or "capture", { #s .. "b" }, now)
	end

	F.api.vm = function(cmd)
		cmd = tostring(cmd or "status"):lower()
		if cmd == "status" then
			return {
				runs = VM.runs, ok = VM.ok, fail = VM.fail, strings = VM.strings,
				captures = VM.captures, protos = VM.protos, instructions = VM.ins,
			}
		end
		if cmd == "captured" then
			local out = {}
			for s in pairs(strCap) do out[#out + 1] = s end
			table.sort(out)
			return out
		end
		return F.api.vm("status")
	end

	F.extra.vm = function()
		return {
			runs = VM.runs, ok = VM.ok, fail = VM.fail, strings = VM.strings,
			captures = VM.captures, hooked = stringHooked,
		}
	end
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okVM then
	warn("[AluzSpy] vm failed: " .. tostring(errVM))
end
