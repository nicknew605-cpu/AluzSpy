do local _ = "aluzspy@1.2.1-max" if F and F.trace then F.trace("load ui") end end
local okUI, errUI = xpcall(function()
	local TS, UIS = SV.TweenService, SV.UserInputService
	local W_OPEN, W_CLOSED, H = 126, 26, 26
	local C_BG = Color3.fromRGB(14, 15, 20)
	local C_ACC = Color3.fromRGB(0, 210, 150)
	local C_NEU = Color3.fromRGB(32, 34, 44)
	local C_TXT = Color3.fromRGB(225, 228, 238)
	local C_OK_BG, C_OK_TX = Color3.fromRGB(22, 78, 52), Color3.fromRGB(110, 255, 170)
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
		if not parented then gui.Parent = LP:WaitForChild("PlayerGui") end
	end

	local root = mk("Frame", {
		Size = UDim2.fromOffset(W_OPEN, H), Position = UDim2.fromOffset(12, 64),
		BackgroundColor3 = C_BG, BackgroundTransparency = 0.05, BorderSizePixel = 0,
		ClipsDescendants = true, Active = true, ZIndex = 1,
	}, gui)
	mk("UICorner", { CornerRadius = UDim.new(0, 13) }, root)
	mk("UIStroke", { Thickness = 1.2, Color = C_ACC, Transparency = 0.25 }, root)

	local function isPress(i)
		return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
	end

	local function mkBtn(text, x, y, w, h, radius)
		local b = mk("TextButton", {
			Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(x, y), BackgroundColor3 = C_NEU,
			TextColor3 = C_TXT, Text = text, Font = Enum.Font.GothamBold, TextSize = 10, BorderSizePixel = 0,
			AutoButtonColor = false, ZIndex = 2,
		}, root)
		mk("UICorner", { CornerRadius = UDim.new(0, radius) }, b)
		local sc = mk("UIScale", { Scale = 1 }, b)
		b.InputBegan:Connect(function(i)
			if isPress(i) then TS:Create(sc, TI_DOWN, { Scale = 0.86 }):Play() end
		end)
		b.InputEnded:Connect(function(i)
			if isPress(i) then TS:Create(sc, TI_UP, { Scale = 1 }):Play() end
		end)
		return b
	end

	local function paint(btn, bg, fg)
		TS:Create(btn, TI_COL, { BackgroundColor3 = bg, TextColor3 = fg }):Play()
	end

	local foldBtn = mkBtn("-", 2, 2, 22, 22, 11)
	foldBtn.TextSize = 14
	foldBtn.TextColor3 = C_ACC
	local cnt = mkBtn("0", 28, 0, 48, H, 0)
	cnt.BackgroundTransparency = 1
	cnt.TextColor3 = Color3.fromRGB(150, 155, 175)
	cnt.TextXAlignment = Enum.TextXAlignment.Left
	cnt.TextTruncate = Enum.TextTruncate.AtEnd
	local saveBtn = mkBtn("SAVE", 80, 3, 42, 20, 10)

	local pop = mk("Frame", {
		Size = UDim2.fromOffset(190, 0), BackgroundColor3 = C_BG, BackgroundTransparency = 0.05,
		BorderSizePixel = 0, ClipsDescendants = true, Visible = false, ZIndex = 3,
	}, gui)
	mk("UICorner", { CornerRadius = UDim.new(0, 12) }, pop)
	mk("UIStroke", { Thickness = 1, Color = C_ACC, Transparency = 0.4 }, pop)
	local popLabel = mk("TextLabel", {
		Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4), BackgroundTransparency = 1,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.Code, TextSize = 10, TextColor3 = C_TXT, Text = "", ZIndex = 4,
	}, pop)

	local popMode, popH = nil, 0

	local function popText(mode)
		if mode == "stats" then
			local s = F.stats()
			local cs, parts = F.catSummary and F.catSummary() or {}, {}
			for k, v in pairs(cs) do parts[#parts + 1] = k .. " " .. v end
			table.sort(parts)
			return string.format("calls %d  logged %d\nremotes %d  muted %d  errors %d\ndumps %d  %s\nfps %d  mem %dMB\nhooks %s\nwarnings %d\n%s",
				s.total, s.logged, s.remotes, s.muted, s.errors, s.dumps, table.concat(parts, " "), s.fps, s.mem,
				F.hookLine and F.hookLine() or "n/a", F.warnN or 0, F.vipLine and F.vipLine() or "max std")
		end
		return "session file:\n" .. PATH.session .. "\n\ncache/spool:\n" .. PATH.dir
	end

	local function showPop(mode)
		if popMode == mode then
			popMode = nil
			popH = 0
			TS:Create(pop, TI_FOLD, { Size = UDim2.fromOffset(190, 0) }):Play()
			task.delay(0.33, function()
				if popMode == nil then pop.Visible = false end
			end)
			return
		end
		popMode = mode
		popLabel.Text = popText(mode)
		popH = mode == "stats" and 104 or 80
		pop.Visible = true
		TS:Create(pop, TI_FOLD, { Size = UDim2.fromOffset(190, popH) }):Play()
	end

	uiCount = function()
		local s = F.fmt(N.total)
		local mn = #muteList
		if mn > 0 then s = s .. " m" .. mn end
		if (F.warnN or 0) > 0 then s = s .. " !" end
		if X.recovered then s = "R " .. s elseif BAN.safe then s = "S " .. s end
		if F.vipOn and F.vipOn() then s = "+" .. s end
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

	cnt.Activated:Connect(function() showPop("stats") end)

	local pid, down, held = 0, false, false
	saveBtn.InputBegan:Connect(function(i)
		if isPress(i) then
			pid = pid + 1
			local my = pid
			down, held = true, false
			task.delay(0.5, function()
				if down and pid == my then
					held = true
					showPop("path")
				end
			end)
		end
	end)
	saveBtn.InputEnded:Connect(function(i)
		if isPress(i) then down = false end
	end)

	saveBtn.Activated:Connect(function()
		if held then
			held = false
			return
		end
		local ok, res = saveNow("manual")
		saveBtn.Text = ok and "OK" or "ERR"
		if ok then
			paint(saveBtn, C_OK_BG, C_OK_TX)
			notify(tostring(res):match("[^/]+$") or res)
		else
			paint(saveBtn, C_BAD_BG, C_BAD_TX)
			notify("Save failed: " .. tostring(res))
		end
		task.delay(1.4, function()
			if saveBtn.Parent then
				saveBtn.Text = "SAVE"
				paint(saveBtn, C_NEU, C_TXT)
			end
		end)
	end)

	function F.setNC(on)
		if on then
			if not INST.nc and not IN.nc() then
				S.nc = false
				return false
			end
			if not INST.fn then pcall(IN.fn) end
			S.nc = true
		else
			S.nc = false
		end
		CFG.nc = S.nc
		return S.nc
	end

	F.paintNC = function() end
	F.gui = gui
	F.notify = notify
	uiCount()
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not okUI then
	warn("[AluzSpy] fatal ui: " .. tostring(errUI))
end
