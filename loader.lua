local base = "https://raw.githubusercontent.com/nicknew605-cpu/AluzSpy/refs/heads/main/src/"
local order = {
	"core.lua",
	"ai.lua",
	"hooks.lua",
	"dump.lua",
	"save.lua",
	"ui.lua",
	"runtime.lua",
}

local function notify(title, text)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", {
			Title = title,
			Text = text,
			Duration = 5,
		})
	end)
end

local parts = {}
local failed = {}

for i = 1, #order do
	local name = order[i]
	local ok, src = pcall(function()
		return game:HttpGet(base .. name)
	end)
	if not ok or type(src) ~= "string" or #src < 20 then
		failed[#failed + 1] = name
		notify("AluzSpy", "Download fail: " .. name)
	else
		parts[#parts + 1] = src .. "\n"
	end
end

if #failed > 0 then
	notify("AluzSpy FAIL", "Missing: " .. table.concat(failed, ", "))
	return
end

local src = table.concat(parts, "\n")
local fn, err = loadstring(src, "AluzSpyBundle")
if not fn then
	notify("AluzSpy FAIL", "Compile: " .. tostring(err):sub(1, 80))
	return
end

local ok, runErr = pcall(fn)
if not ok then
	notify("AluzSpy FAIL", "Run: " .. tostring(runErr):sub(1, 90))
	return
end

notify("AluzSpy", "Loaded OK")
