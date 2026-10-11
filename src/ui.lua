local okUI, errUI = xpcall(function()
	local TS, UIS = SV.TweenService, SV.UserInputService
	local W_OPEN, W_CLOSED, H = 170, 28, 28
	local C_BG = Color3.fromRGB(14, 15, 20)
	local C_ACC = Color3.fromRGB(0, 210, 150)
	local C_NEU_BG = Color3.fromRGB(32, 34, 44)
	local C_TXT = Color3.fromRGB(225, 228, 238)
	local C_ON_BG, C_ON_TX = Color3.fromRGB(22, 78, 52), Color3.fromRGB(110, 255, 170)
	local C_BAD_BG, C_BAD_TX = Color3.fromRGB(86, 32, 32), Color3.fromRGB(255, 130, 130)
	local TI_DOWN = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local TI_UP = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local TI_FOLD = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local TI_COL = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function notify(text)
		pcall(function()
			SV.StarterGui:SetCore("SendNotification", { Title = "Aluz Spy", Text = tostring(text), Duration = 3 })
		end)
	end

	local function mk(cls, props, parent)
		local o = Instance.new(cls)
		for k, v in pairs(props) do o[k] = v end
		if parent then o.Parent = parent end
		return o
	end

	local gui = mk("ScreenGui", {
		Name = "AluzSpy", ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = 999999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	do
		local parented = false
		if gethui then
			parented = pcall(function() gui.Parent = gethui() end) and gui.Parent ~= nil
		end
		if not parented then
			parented = pcall(function() gui.Parent = SV.CoreGui end) and gui.Parent ~= nil
		end
		if not parented then
			gui.Parent = LP:WaitForChild("PlayerGui")
		end
	end

	local root = mk("Frame", {
		Size = UDim2.fromOffset(W_OPEN, H), Position = UDim2.fromOffset(12, 64),
		BackgroundColor3 = C_BG, BackgroundTransparency = 0.05, BorderSizePixel = 0,
		ClipsDescendants = true, Active = true, ZIndex = 1,
	}, gui)
	mk("UICorner", { CornerRadius = UDim.new(0, 14) }, root)
	mk("UIStroke", { Thickness = 1.2, Color = C_ACC, Transparency = 0.25 }, root)

	local function isPress(i)
		return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
	end

	local function pressFx(btn)
		local sc = mk("UIScale", { Scale = 1 }, btn)
		btn.InputBegan:Connect(function(i)
			if isPress(i) then TS:Create(sc, TI_DOWN, { Scale = 0.86 }):Play() end
		end)
		btn.InputEnded:Connect(function(i)
			if isPress(i) then TS:Create(sc, TI_UP, { Scale = 1 }):Play() end
		end)
	end

	local function mkBtn(cls, text, x, y, w, h, radius, parent)
		local b = mk(cls, {
			Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(x, y),
			BackgroundColor3 = C_NEU_BG, TextColor3 = C_TXT, Text = text,
			Font = Enum.Font.GothamBold, TextSize = 10, BorderSizePixel = 0,
			AutoButtonColor = false, ZIndex = 2,
		}, parent or root)
		mk("UICorner", { CornerRadius = UDim.new(0, radius) }, b)
		pressFx(b)
		return b
	end

	local function paint(btn, bg, fg)
		TS:Create(btn, TI_COL, { BackgroundColor3 = bg, TextColor3 = fg }):Play()
	end

	local held = {}
	local function longPress(btn, fn)
		local pid, down = 0, false
		btn.InputBegan:Connect(function(i)
			if isPress(i) then
				pid = pid + 1
				local my = pid
				down = true
				held[btn] = false
				task.delay(0.5, function()
					if down and pid == my then
						held[btn] = true
						fn()
					end
				end)
			end
		end)
		btn.InputEnded:Connect(function(i)
			if isPress(i) then down = false end
		end)
	end

	local foldBtn = mkBtn("TextButton", "-", 3, 3, 22, 22, 11)
	foldBtn.TextSize = 14
	foldBtn.TextColor3 = C_ACC
	local cnt = mkBtn("TextButton", "0", 30, 0, 50, H, 0)
	cnt.BackgroundTransparency = 1
	cnt.TextColor3 = Color3.fromRGB(150, 155, 175)
	cnt.TextXAlignment = Enum.TextXAlignment.Left
	cnt.TextTruncate = Enum.TextTruncate.AtEnd
	local ncBtn = mkBtn("TextButton", "NC", 82, 4, 38, 20, 10)
	local saveBtn = mkBtn("TextButton", "SAVE", 124, 4, 42, 20, 10)

	local function paintNC()
		if S.nc then paint(ncBtn, C_ON_BG, C_ON_TX) else paint(ncBtn, C_BAD_BG, C_BAD_TX) end
	end

	local pop = mk("Frame", {
		Size = UDim2.fromOffset(W_OPEN, 0), BackgroundColor3 = C_BG, BackgroundTransparency = 0.05,
		BorderSizePixel = 0, ClipsDescendants = true, Visible = false, ZIndex = 3,
	}, gui)
	mk("UICorner", { CornerRadius = UDim.new(0, 12) }, pop)
	mk("UIStroke", { Thickness = 1, Color = C_ACC, Transparency = 0.4 }, pop)
	local popLabel = mk("TextLabel", {
		Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4), BackgroundTransparency = 1,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.Code, TextSize = 10, TextColor3 = C_TXT, Text = "", ZIndex = 4,
	}, pop)
	local chipHolder = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4, Visible = false }, pop)

	local function setCfg(key)
		return function(v)
			CFG[key] = v
			if key == "dump" then S.dump = v end
			F.cfgSave()
			return v
		end
	end

	local items = {
		{ "FN", function() return MOD.fn end, function(v) return F.setMod("fn", v) end },
		{ "S2C", function() return MOD.s2c end, function(v) return F.setMod("s2c", v) end },
		{ "CB", function() return MOD.cb end, function(v) return F.setMod("cb", v) end },
		{ "NI", function() return MOD.ni end, function(v) return F.setMod("ni", v) end },
		{ "SYS", function() return MOD.sys end, function(v) return F.setMod("sys", v) end },
		{ "NET", function() return MOD.net end, function(v) return F.setMod("net", v) end },
		{ "HTTP", function() return MOD.http end, function(v) return F.setMod("http", v) end },
		{ "LS", function() return MOD.ls end, function(v) return F.setMod("ls", v) end },
		{ "RW", function() return MOD.rw end, function(v) return F.setMod("rw", v) end },
		{ "WS", function() return MOD.ws end, function(v) return F.setMod("ws", v) end },
		{ "REQ", function() return MOD.req end, function(v) return F.setMod("req", v) end },
		{ "HX", function() return MOD.hx end, function(v) return F.setMod("hx", v) end },
		{ "DUMP", function() return S.dump end, setCfg("dump") },
		{ "TREE", function() return CFG.tree end, setCfg("tree") },
		{ "CODE", function() return CFG.code end, setCfg("code") },
		{ "CALR", function() return CFG.callerDump end, setCfg("callerDump") },
		{ "DEC", function() return CFG.decode end, setCfg("decode") },
		{ "SBOX", function() return CFG.sandbox end, setCfg("sandbox") },
		{ "RST", function() return false end, function() F.reset() notify("Reset") return false end },
	}
	local chips = {}
	local function paintChip(b, on)
		paint(b, on and C_ON_BG or C_NEU_BG, on and C_ON_TX or C_TXT)
	end
	for i, it in ipairs(items) do
		local col, row = (i - 1) % 4, floor((i - 1) / 4)
		local b = mkBtn("TextButton", it[1], 4 + col * 41, 4 + row * 24, 38, 20, 6, chipHolder)
		b.TextSize = 9
		b.ZIndex = 5
		chips[i] = b
		b.Activated:Connect(function()
			local cur = it[2]()
			local res = it[3](not cur)
			paintChip(b, it[2]() == true or res == true)
		end)
	end
	local function refreshChips()
		for i, it in ipairs(items) do paintChip(chips[i], it[2]() == true) end
	end

	local popMode, popH = nil, 0

	local function popText(mode)
		if mode == "stats" then
			local s = F.stats()
			return string.format(
				"calls %d  logged %d\nmerged %d  muted %d\nsuppressed %d  remotes %d\ndumps %d  errors %d\nfps %d  mem %dMB  load %d",
				s.total, s.logged, s.merged, s.muted, s.suppressed, s.remotes, s.dumps, s.errors, s.fps, s.mem, s.load)
		end
		return "save:\n" .. PATH.session .. "\n\ndump:\n" .. (PATH.ok and PATH.dumpDir or "workspace root")
	end

	local function showPop(mode)
		if popMode == mode then
			popMode = nil
			popH = 0
			TS:Create(pop, TI_FOLD, { Size = UDim2.fromOffset(W_OPEN, 0) }):Play()
			task.delay(0.33, function()
				if popMode == nil then pop.Visible = false end
			end)
			return
		end
		popMode = mode
		chipHolder.Visible = mode == "mods"
		popLabel.Visible = mode ~= "mods"
		if mode == "mods" then refreshChips() else popLabel.Text = popText(mode) end
		popH = mode == "mods" and 130 or 82
		pop.Visible = true
		TS:Create(pop, TI_FOLD, { Size = UDim2.fromOffset(W_OPEN, popH) }):Play()
	end

	uiCount = function()
		local s = F.fmt(N.total)
		local mn = #muteList
		if mn > 0 then s = s .. " m" .. mn end
		if X.recovered then s = "R " .. s elseif BAN.safe then s = "S " .. s end
		cnt.Text = s
		if popMode == "stats" then popLabel.Text = popText("stats") end
	end

	local function screenSize()
		local s = gui.AbsoluteSize
		if s.X < 10 then
			local cam = workspace.CurrentCamera
			s = cam and cam.ViewportSize or Vector2.new(800, 600)
		end
		return s
	end

	local curW = W_OPEN
	local tgt = Vector2.new(12, 64)
	local cur = tgt

	local function clampPos(v)
		local s = screenSize()
		return Vector2.new(math.clamp(v.X, 0, math.max(0, s.X - curW)), math.clamp(v.Y, 0, math.max(0, s.Y - H)))
	end

	local dragging, dragInput, startPtr, startTgt = false, nil, Vector2.new(), tgt

	root.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging = true
			dragInput = input
			startPtr = Vector2.new(input.Position.X, input.Position.Y)
			startTgt = tgt
		end
	end)

	conns[#conns + 1] = UIS.InputChanged:Connect(function(input)
		if not dragging then return end
		if input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement then
			tgt = clampPos(startTgt + (Vector2.new(input.Position.X, input.Position.Y) - startPtr))
		end
	end)

	conns[#conns + 1] = UIS.InputEnded:Connect(function(input)
		if dragging and (input == dragInput or isPress(input)) then
			dragging = false
			dragInput = nil
		end
	end)

	conns[#conns + 1] = SV.RunService.RenderStepped:Connect(function(dt)
		local d = tgt - cur
		if d.Magnitude >= 0.05 then
			cur = cur + d * (1 - math.exp(-dt * 22))
		elseif cur ~= tgt then
			cur = tgt
		end
		local rx, ry = floor(cur.X + 0.5), floor(cur.Y + 0.5)
		root.Position = UDim2.fromOffset(rx, ry)
		if pop.Visible then
			local py = ry + H + 4
			if py + popH > screenSize().Y then py = ry - popH - 4 end
			pop.Position = UDim2.fromOffset(rx, py)
		end
	end)

	local isOpen = true
	foldBtn.Activated:Connect(function()
		isOpen = not isOpen
		curW = isOpen and W_OPEN or W_CLOSED
		foldBtn.Text = isOpen and "-" or "+"
		tgt = clampPos(tgt)
		TS:Create(root, TI_FOLD, { Size = UDim2.fromOffset(curW, H) }):Play()
	end)

	function F.setNC(on)
		if on then
			if not INST.nc and not IN.nc() then
				notify("NC: hook failed")
				S.nc = false
				paintNC()
				return false
			end
			if not INST.fn then pcall(IN.fn) end
			S.nc = true
		else
			S.nc = false
		end
		CFG.nc = S.nc
		paintNC()
		return S.nc
	end

	cnt.Activated:Connect(function() showPop("stats") end)
	longPress(ncBtn, function() showPop("mods") end)
	longPress(saveBtn, function() showPop("path") end)

	ncBtn.Activated:Connect(function()
		if held[ncBtn] then held[ncBtn] = false return end
		F.setNC(not S.nc)
	end)

	saveBtn.Activated:Connect(function()
		if held[saveBtn] then held[saveBtn] = false return end
		local ok, res = saveNow("manual")
		saveBtn.Text = ok and "OK" or "ERR"
		if ok then
			paint(saveBtn, C_ON_BG, C_ON_TX)
			notify(tostring(res):match("[^/]+$") or res)
		else
			paint(saveBtn, C_BAD_BG, C_BAD_TX)
			notify("Save failed: " .. tostring(res))
		end
		task.delay(1.4, function()
			if saveBtn.Parent then
				saveBtn.Text = "SAVE"
				paint(saveBtn, C_NEU_BG, C_TXT)
			end
		end)
	end)

	F.gui = gui
	F.notify = notify
	F.paintNC = paintNC
	paintNC()
	uiCount()
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okUI then
	warn("[AluzSpy] fatal ui: " .. tostring(errUI))
end
