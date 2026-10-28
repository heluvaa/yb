--[[ ==========================================================================
     N O V A   V D   |   Violence District Toolkit            v1.0
     --------------------------------------------------------------------------
     File    : nova_vd_v1.lua      (file baru, engine sendiri)
     Engine  : vanilla UI buatan sendiri -- TANPA Rayfield, TANPA loadstring
     Target  : [BUTCHER] Violence District      (PlaceId 93978595733734)
     Platform: Mobile (Delta / Hydrogen) + PC (Xeno / Wave / Swift)

     Remote map hasil reverse-engineer client game:
       ReplicatedStorage.Remotes
         Generator.SkillCheckEvent        (OnClientEvent -> QTE muncul)
         Generator.SkillCheckResultEvent  (FireServer("success", 1))
         Generator.RepairEvent            (FireServer(GeneratorPoint, true|false))
         Items["Parrying Dagger"].parry        (FireServer())
         Items["Parrying Dagger"].parryResult  (OnClientEvent(result, cd))
         Items.Flashlight.GotBlinded
         Items["Twist of Fate"].Fire
         KillerPerks.kingscourge.KingScourgeStart / KingScourgeHit
         Killers.Veil.Spearthrow
         Killers.Abysswalker.corrupt
         Mechanics.Slow / Mechanics.Fall
         Pallet.PalletDropEvent / PalletSlideEvent / PalletSlideCompleteEvent
         Window.VaultEvent / VaultCompleteEvent
         Healing.HealEvent                (FireServer(hrp, true))
         Game.UpdateCharacterLook

     Atribut karakter/objek yang dipakai:
       char      : speedboost, Knocked, IsHooked, Flowstate, IsCarried,
                   HookCount, IsStunned, Immobile, SelectedKiller, EquippedItem
       interaksi : Character.CheckInterractable.{isRepairing,isVaulting,
                   isUnhooking,isHealing,isSliding}
       generator : Model "Generator" + anak "GeneratorPoint", atribut
                   RepairProgress / ProgressRepair / kickcount / Completed
   ========================================================================== ]]

--===================== [ 0. LOAD GUARD ] ==================================
local NOV_ENV = (getgenv and getgenv()) or _G
if NOV_ENV.NOVA_VD_RUNNING then
	warn("[NOVA] Script sudah jalan. Tekan Unload dulu sebelum reload.")
	return
end
NOV_ENV.NOVA_VD_RUNNING = true

--===================== [ 1. SERVICES ] ====================================
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local UIS                 = game:GetService("UserInputService")
local Lighting            = game:GetService("Lighting")
local TweenService        = game:GetService("TweenService")
local HttpService         = game:GetService("HttpService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local CollectionService   = game:GetService("CollectionService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local lp  = Players.LocalPlayer
local cam = workspace.CurrentCamera

local unpack = table.unpack or unpack

--===================== [ 2. ROOT TABLE + CONFIG ] =========================
-- Satu local di main chunk. Semua modul nempel di sini supaya tidak kena
-- limit 200 local per function.
local NOV = {
	remotes = {},
	conns   = {},
	cleanups = {},
	esp      = {},
	state    = {},
	cache    = { gens = {}, hooks = {}, pallets = {}, windows = {}, gates = {} },
	ui       = {},
	alive    = true,
}

local CFG = {
	-- UI
	Keybind        = Enum.KeyCode.RightShift,
	Accent         = Color3.fromRGB(0, 210, 190),
	-- ESP
	EspPlayers     = false,
	EspChams       = true,
	EspBox         = false,
	EspName        = true,
	EspRole        = true,
	EspDist        = true,
	EspTool        = true,
	EspHealth      = true,
	EspGens        = true,
	EspHooks       = false,
	EspPallets     = false,
	EspWindows     = false,
	EspGates       = true,
	EspMaxDist     = 900,
	EspAliveOnly   = true,
	ColorKiller    = Color3.fromRGB(255, 70, 70),
	ColorSurvivor  = Color3.fromRGB(90, 190, 255),
	ColorOther     = Color3.fromRGB(200, 200, 200),
	ColorGen       = Color3.fromRGB(255, 205, 60),
	ColorGenDone   = Color3.fromRGB(60, 255, 120),
	ColorGate      = Color3.fromRGB(170, 90, 255),
	ColorHook      = Color3.fromRGB(255, 90, 90),
	ColorPallet    = Color3.fromRGB(255, 150, 60),
	ColorWindow    = Color3.fromRGB(120, 255, 240),
	KillerAlert    = false,
	AlertDist      = 90,
	-- Generator
	GenPerfect     = false,
	GenFailSafe    = true,
	GenDelayMin    = 0.10,
	GenDelayMax    = 0.28,
	AutoRepair     = false,
	AutoRepairTp   = true,
	RepairRange    = 16,
	RepairRate     = 0.35,
	-- Combat
	AutoParry      = false,
	AutoEquipDagger= true,
	ParryRange     = 22,
	ParryCooldown  = 0.8,
	AutoHeal       = false,
	HealThreshold  = 0.85,
	AutoWiggle     = false,
	AutoVault      = false,
	AntiFall       = false,
	-- Movement
	SpeedEnabled   = false,
	SpeedValue     = 26,
	Fly            = false,
	FlySpeed       = 70,
	Noclip         = false,
	InfJump        = false,
	AntiAfk        = false,
	Gravity        = 196.2,
	-- Visual
	Fullbright     = false,
	NoFog          = false,
	AntiFlash      = false,
	SelfHighlight  = false,
	CameraFov      = 70,
	InfZoom        = false,
	TimeOfDay      = -1,
	-- Teleport
	SmoothTp       = true,
	SmoothTpTime   = 0.25,
	-- Misc
	RemoteLog      = false,
	ShowStats      = true,
}

--===================== [ 3. UTIL ] ========================================
do
	local function safe(fn, ...)
		local ok, res = pcall(fn, ...)
		if not ok then
			return nil, res
		end
		return res
	end
	NOV.safe = safe

	NOV.bind = function(signal, fn)
		local c = signal:Connect(fn)
		table.insert(NOV.conns, c)
		return c
	end

	NOV.delay = function()
		return CFG.GenDelayMin + math.random() * math.max(0, CFG.GenDelayMax - CFG.GenDelayMin)
	end

	NOV.msg = function(text)
		if NOV.ui.notify then
			NOV.ui.notify(text)
		else
			print("[NOVA] " .. tostring(text))
		end
	end

	NOV.hrp = function()
		local char = lp.Character
		return char and char:FindFirstChild("HumanoidRootPart")
	end

	NOV.hum = function()
		local char = lp.Character
		return char and char:FindFirstChildOfClass("Humanoid")
	end

	-- deteksi role: Team-based (utama) + fallback atribut/heuristik
	NOV.role = function(plr)
		plr = plr or lp
		local team = plr.Team
		if team then
			local n = string.lower(team.Name)
			if string.find(n, "killer", 1, true) then return "Killer" end
			if string.find(n, "surv", 1, true) then return "Survivor" end
		end
		if plr:GetAttribute("SelectedKiller") ~= nil then return "Killer" end
		local char = plr.Character
		if char then
			if char:GetAttribute("Knocked") ~= nil or char:GetAttribute("IsHooked") ~= nil then
				return "Survivor"
			end
		end
		return "Unknown"
	end

	NOV.isKiller = function(plr)
		return NOV.role(plr) == "Killer"
	end

	NOV.dist = function(a, b)
		if not a or not b then return math.huge end
		return (a - b).Magnitude
	end

	NOV.rayClear = function(from, to)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { lp.Character }
		local hit = workspace:Raycast(from, to - from, params)
		return hit == nil
	end
end

--===================== [ 4. REMOTE RESOLVER ] =============================
do
	local RS = ReplicatedStorage

	local function child(parent, name)
		if not parent then return nil end
		return parent:FindFirstChild(name)
	end

	local function path(...)
		local node = RS
		local parts = { ... }
		for _, n in ipairs(parts) do
			node = child(node, n)
			if not node then return nil end
		end
		return node
	end

	NOV.remotes.resolve = function()
		local R = NOV.remotes
		local root = RS:FindFirstChild("Remotes") or RS:WaitForChild("Remotes", 10)
		R.root = root
		if not root then return false end

		R.gen         = child(root, "Generator")
		R.genSkill    = child(R.gen, "SkillCheckEvent")
		R.genResult   = child(R.gen, "SkillCheckResultEvent")
		R.genRepair   = child(R.gen, "RepairEvent")

		local items   = child(root, "Items")
		R.items       = items
		local dagger  = items and (child(items, "Parrying Dagger") or child(items, "ParryingDagger"))
		R.dagger      = dagger
		R.parry       = child(dagger, "parry")
		R.parryResult = child(dagger, "parryResult")

		local perks   = child(root, "KillerPerks")
		local ks      = perks and child(perks, "kingscourge")
		R.kingStart   = child(ks, "KingScourgeStart")
		R.kingHit     = child(ks, "KingScourgeHit")

		R.mechanics   = child(root, "Mechanics")
		R.slow        = child(R.mechanics, "Slow")
		R.fall        = child(R.mechanics, "Fall")

		R.pallet      = child(root, "Pallet")
		R.palletDrop  = child(R.pallet, "PalletDropEvent")
		R.palletSlide = child(R.pallet, "PalletSlideEvent")
		R.palletDone  = child(R.pallet, "PalletSlideCompleteEvent")

		R.window      = child(root, "Window")
		R.vault       = child(R.window, "VaultEvent")
		R.vaultDone   = child(R.window, "VaultCompleteEvent")

		R.healing     = child(root, "Healing")
		R.heal        = child(R.healing, "HealEvent")

		local gamef   = child(root, "Game")
		R.look        = child(gamef, "UpdateCharacterLook")

		local fl      = items and child(items, "Flashlight")
		R.blind       = child(fl, "GotBlinded")

		return true
	end

	NOV.remotes.count = function()
		local n = 0
		for _, v in pairs(NOV.remotes) do
			if typeof(v) == "Instance" then n = n + 1 end
		end
		return n
	end

	-- tooltip daftar remote yang kedeteksi (buat self-test / clipboard)
	NOV.remotes.list = function()
		local out = {}
		local names = {
			"gen", "genSkill", "genResult", "genRepair", "dagger", "parry",
			"parryResult", "kingStart", "kingHit", "slow", "fall", "palletDrop",
			"palletSlide", "palletDone", "vault", "vaultDone", "heal", "look", "blind",
		}
		for _, k in ipairs(names) do
			local v = NOV.remotes[k]
			table.insert(out, string.format("%s=%s", k, tostring(v ~= nil)))
		end
		return table.concat(out, " ")
	end
end

--===================== [ 5. VANILLA UI ] ==================================
do
	local guiParent
	do
		local ok, p = pcall(function()
			if gethui then return gethui() end
			return game:GetService("CoreGui")
		end)
		guiParent = (ok and p) or lp:WaitForChild("PlayerGui")
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "NOVA_VD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 100
	local okParent = pcall(function() gui.Parent = guiParent end)
	if not okParent then gui.Parent = lp:WaitForChild("PlayerGui") end

	local C = {
		bg      = Color3.fromRGB(16, 17, 20),
		panel   = Color3.fromRGB(22, 24, 28),
		panel2  = Color3.fromRGB(28, 31, 36),
		stroke  = Color3.fromRGB(44, 48, 55),
		text    = Color3.fromRGB(236, 238, 242),
		dim     = Color3.fromRGB(140, 146, 158),
		accent  = CFG.Accent,
	}

	local function corner(inst, r)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r or 8)
		c.Parent = inst
	end
	local function stroke(inst, col, th)
		local s = Instance.new("UIStroke")
		s.Color = col or C.stroke
		s.Thickness = th or 1
		s.Parent = inst
		return s
	end

	--======== WINDOW ========
	local win = Instance.new("Frame")
	win.Size = UDim2.new(0, 620, 0, 420)
	win.Position = UDim2.new(0.5, -310, 0.5, -210)
	win.BackgroundColor3 = C.bg
	win.BorderSizePixel = 0
	win.Active = true
	win.Draggable = true
	win.ClipsDescendants = true
	win.Parent = gui
	corner(win, 12)
	stroke(win, C.stroke)

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 42)
	bar.BackgroundColor3 = C.panel
	bar.BorderSizePixel = 0
	bar.Parent = win

	local accentBar = Instance.new("Frame")
	accentBar.Size = UDim2.new(0, 3, 0, 20)
	accentBar.Position = UDim2.new(0, 14, 0.5, -10)
	accentBar.BackgroundColor3 = C.accent
	accentBar.BorderSizePixel = 0
	accentBar.Parent = bar
	corner(accentBar, 99)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0, 300, 1, 0)
	title.Position = UDim2.new(0, 26, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "NOVA VD"
	title.TextColor3 = C.text
	title.TextSize = 15
	title.Font = Enum.Font.GothamBlack
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = bar

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(0, 300, 1, 0)
	sub.Position = UDim2.new(0, 100, 0, 0)
	sub.BackgroundTransparency = 1
	sub.Text = "Violence District  ·  v1.0"
	sub.TextColor3 = C.dim
	sub.TextSize = 12
	sub.Font = Enum.Font.GothamMedium
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Parent = bar

	local statusLbl = Instance.new("TextLabel")
	statusLbl.Size = UDim2.new(0, 200, 1, 0)
	statusLbl.Position = UDim2.new(1, -270, 0, 0)
	statusLbl.BackgroundTransparency = 1
	statusLbl.Text = ""
	statusLbl.TextColor3 = C.accent
	statusLbl.TextSize = 11
	statusLbl.Font = Enum.Font.GothamBold
	statusLbl.TextXAlignment = Enum.TextXAlignment.Right
	statusLbl.Parent = bar

	local close = Instance.new("TextButton")
	close.Size = UDim2.new(0, 34, 0, 34)
	close.Position = UDim2.new(1, -38, 0.5, -17)
	close.BackgroundTransparency = 1
	close.Text = "×"
	close.TextColor3 = C.dim
	close.TextSize = 22
	close.Font = Enum.Font.GothamBold
	close.AutoButtonColor = false
	close.Parent = bar
	close.MouseEnter:Connect(function() close.TextColor3 = Color3.fromRGB(255, 90, 90) end)
	close.MouseLeave:Connect(function() close.TextColor3 = C.dim end)

	local sidebar = Instance.new("Frame")
	sidebar.Size = UDim2.new(0, 152, 1, -42)
	sidebar.Position = UDim2.new(0, 0, 0, 42)
	sidebar.BackgroundColor3 = C.panel
	sidebar.BorderSizePixel = 0
	sidebar.Parent = win

	local tabList = Instance.new("Frame")
	tabList.Size = UDim2.new(1, -14, 1, -14)
	tabList.Position = UDim2.new(0, 7, 0, 7)
	tabList.BackgroundTransparency = 1
	tabList.Parent = sidebar
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.Padding = UDim.new(0, 5)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabList

	-- versi compact: di layar kecil sidebar jadi baris atas
	local function applyResponsive()
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		if vp.X < 700 then
			local n = #NOV.ui.tabs
			local w = math.floor((vp.X - 40) / math.max(1, n))
			sidebar.Size = UDim2.new(1, -20, 0, 40)
			sidebar.Position = UDim2.new(0, 10, 0, 46)
			tabLayout.FillDirection = Enum.FillDirection.Horizontal
			for _, t in ipairs(NOV.ui.tabs) do
				t.button.Size = UDim2.new(0, w - 6, 1, 0)
			end
			for _, p in ipairs(NOV.ui.pages) do
				p.Size = UDim2.new(1, -20, 1, -100)
				p.Position = UDim2.new(0, 10, 0, 94)
			end
			win.Size = UDim2.new(0, math.min(vp.X - 16, 620), 0, math.min(vp.Y - 16, 420))
			win.Position = UDim2.new(0.5, -win.Size.X.Offset / 2, 0.5, -win.Size.Y.Offset / 2)
		end
	end

	NOV.ui.tabs  = {}
	NOV.ui.pages = {}

	--======== CONTAINER ========
	local pagesHolder = Instance.new("Frame")
	pagesHolder.Size = UDim2.new(1, -152, 1, -42)
	pagesHolder.Position = UDim2.new(0, 152, 0, 42)
	pagesHolder.BackgroundTransparency = 1
	pagesHolder.Parent = win

	NOV.ui.createTab = function(name)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 34)
		btn.BackgroundColor3 = C.panel2
		btn.BackgroundTransparency = 0
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.Parent = tabList
		corner(btn, 7)

		local dot = Instance.new("Frame")
		dot.Size = UDim2.new(0, 3, 0, 16)
		dot.Position = UDim2.new(0, 0, 0.5, -8)
		dot.BackgroundColor3 = C.accent
		dot.BorderSizePixel = 0
		dot.Visible = false
		dot.Parent = btn
		corner(dot, 99)

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -16, 1, 0)
		lbl.Position = UDim2.new(0, 12, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = name
		lbl.TextColor3 = C.dim
		lbl.TextSize = 13
		lbl.Font = Enum.Font.GothamMedium
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = btn

		local page = Instance.new("ScrollingFrame")
		page.Size = UDim2.new(1, -20, 1, -20)
		page.Position = UDim2.new(0, 10, 0, 10)
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.ScrollBarThickness = 3
		page.ScrollBarImageColor3 = C.accent
		page.CanvasSize = UDim2.new(0, 0, 0, 0)
		page.Visible = false
		page.Parent = pagesHolder
		local lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, 6)
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Parent = page

		local tab = { button = btn, page = page, label = lbl, dot = dot, layout = lay }
		table.insert(NOV.ui.tabs, tab)
		table.insert(NOV.ui.pages, page)

		btn.MouseButton1Click:Connect(function()
			for _, t in ipairs(NOV.ui.tabs) do
				t.page.Visible = false
				t.dot.Visible = false
				t.button.BackgroundColor3 = C.panel2
				t.label.TextColor3 = C.dim
			end
			page.Visible = true
			dot.Visible = true
			btn.BackgroundColor3 = C.panel2
			lbl.TextColor3 = C.text
		end)

		return tab
	end

	--======== COMPONENTS ========
	NOV.ui.section = function(page, text)
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, 0, 0, 22)
		f.BackgroundTransparency = 1
		f.Parent = page
		local line = Instance.new("Frame")
		line.Size = UDim2.new(1, 0, 0, 1)
		line.Position = UDim2.new(0, 0, 1, -2)
		line.BackgroundColor3 = C.stroke
		line.BorderSizePixel = 0
		line.Parent = f
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = string.upper(text)
		lbl.TextColor3 = C.accent
		lbl.TextSize = 11
		lbl.Font = Enum.Font.GothamBold
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = f
		return f
	end

	NOV.ui.label = function(page, text, color)
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, 0, 0, 18)
		l.BackgroundTransparency = 1
		l.Text = text
		l.TextColor3 = color or C.dim
		l.TextSize = 11
		l.Font = Enum.Font.GothamMedium
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Parent = page
		return l
	end

	NOV.ui.toggle = function(page, text, default, callback)
		local state = default and true or false
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 32)
		btn.BackgroundColor3 = C.panel2
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.Parent = page
		corner(btn, 7)
		local st = stroke(btn)

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -110, 1, 0)
		lbl.Position = UDim2.new(0, 12, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = text
		lbl.TextColor3 = C.text
		lbl.TextSize = 13
		lbl.Font = Enum.Font.GothamMedium
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = btn

		local tag = Instance.new("TextLabel")
		tag.Size = UDim2.new(0, 34, 1, 0)
		tag.Position = UDim2.new(1, -100, 0, 0)
		tag.BackgroundTransparency = 1
		tag.Text = state and "ON" or "OFF"
		tag.TextColor3 = state and C.accent or C.dim
		tag.TextSize = 10
		tag.Font = Enum.Font.GothamBold
		tag.Parent = btn

		local sw = Instance.new("Frame")
		sw.Size = UDim2.new(0, 38, 0, 18)
		sw.Position = UDim2.new(1, -56, 0.5, -9)
		sw.BackgroundColor3 = state and C.accent or C.stroke
		sw.BorderSizePixel = 0
		sw.Parent = btn
		corner(sw, 99)

		local knob = Instance.new("Frame")
		knob.Size = UDim2.new(0, 14, 0, 14)
		knob.Position = state and UDim2.new(0, 22, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
		knob.BackgroundColor3 = state and Color3.new(1, 1, 1) or C.dim
		knob.BorderSizePixel = 0
		knob.Parent = sw
		corner(knob, 99)

		local api = {}
		api.set = function(v)
			state = v and true or false
			tag.Text = state and "ON" or "OFF"
			tag.TextColor3 = state and C.accent or C.dim
			TweenService:Create(sw, TweenInfo.new(0.15), {
				BackgroundColor3 = state and C.accent or C.stroke,
			}):Play()
			TweenService:Create(knob, TweenInfo.new(0.15), {
				Position = state and UDim2.new(0, 22, 0.5, -7) or UDim2.new(0, 2, 0.5, -7),
				BackgroundColor3 = state and Color3.new(1, 1, 1) or C.dim,
			}):Play()
		end

		btn.MouseEnter:Connect(function()
			TweenService:Create(st, TweenInfo.new(0.12), { Color = C.accent }):Play()
		end)
		btn.MouseLeave:Connect(function()
			TweenService:Create(st, TweenInfo.new(0.12), { Color = C.stroke }):Play()
		end)

		btn.MouseButton1Click:Connect(function()
			state = not state
			api.set(state)
			if callback then
				local ok, err = pcall(callback, state)
				if not ok then warn("[NOVA] toggle error: " .. tostring(err)) end
			end
		end)

		api.set(state)
		return api
	end

	NOV.ui.slider = function(page, text, min, max, default, decimals, callback)
		local val = default
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, 0, 0, 42)
		f.BackgroundColor3 = C.panel2
		f.BorderSizePixel = 0
		f.Parent = page
		corner(f, 7)
		stroke(f)

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -70, 0, 18)
		lbl.Position = UDim2.new(0, 12, 0, 4)
		lbl.BackgroundTransparency = 1
		lbl.Text = text
		lbl.TextColor3 = C.text
		lbl.TextSize = 12
		lbl.Font = Enum.Font.GothamMedium
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = f

		local valLbl = Instance.new("TextLabel")
		valLbl.Size = UDim2.new(0, 60, 0, 18)
		valLbl.Position = UDim2.new(1, -66, 0, 4)
		valLbl.BackgroundTransparency = 1
		valLbl.TextColor3 = C.accent
		valLbl.TextSize = 12
		valLbl.Font = Enum.Font.GothamBold
		valLbl.TextXAlignment = Enum.TextXAlignment.Right
		valLbl.Parent = f

		local track = Instance.new("Frame")
		track.Size = UDim2.new(1, -24, 0, 6)
		track.Position = UDim2.new(0, 12, 1, -14)
		track.BackgroundColor3 = C.stroke
		track.BorderSizePixel = 0
		track.Parent = f
		corner(track, 99)

		local fill = Instance.new("Frame")
		fill.Size = UDim2.new(0, 0, 1, 0)
		fill.BackgroundColor3 = C.accent
		fill.BorderSizePixel = 0
		fill.Parent = track
		corner(fill, 99)

		local knob = Instance.new("Frame")
		knob.Size = UDim2.new(0, 12, 0, 12)
		knob.Position = UDim2.new(0, 0, 0.5, -6)
		knob.BackgroundColor3 = Color3.new(1, 1, 1)
		knob.BorderSizePixel = 0
		knob.Parent = track
		corner(knob, 99)

		local dragging = false
		local function fmt(v)
			if decimals and decimals > 0 then
				return string.format("%." .. decimals .. "f", v)
			end
			return tostring(math.floor(v + 0.5))
		end
		local function paint()
			local a = (val - min) / math.max(0.0001, (max - min))
			fill.Size = UDim2.new(a, 0, 1, 0)
			knob.Position = UDim2.new(a, -6, 0.5, -6)
			valLbl.Text = fmt(val)
		end
		local function applyFromX(x)
			local abs = track.AbsolutePosition.X
			local w = track.AbsoluteSize.X
			local a = math.clamp((x - abs) / math.max(1, w), 0, 1)
			val = min + a * (max - min)
			paint()
			if callback then pcall(callback, val) end
		end

		NOV.bind(UIS.InputChanged, function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				applyFromX(input.Position.X)
			elseif dragging and input.UserInputType == Enum.UserInputType.Touch then
				applyFromX(input.Position.X)
			end
		end)
		NOV.bind(UIS.InputEnded, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
		track.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				applyFromX(input.Position.X)
			end
		end)

		paint()
		return {
			get = function() return val end,
			set = function(v) val = math.clamp(v, min, max); paint(); if callback then pcall(callback, val) end end,
		}
	end

	NOV.ui.button = function(page, text, callback)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 30)
		btn.BackgroundColor3 = C.panel2
		btn.Text = text
		btn.TextColor3 = C.text
		btn.TextSize = 12
		btn.Font = Enum.Font.GothamMedium
		btn.AutoButtonColor = false
		btn.Parent = page
		corner(btn, 7)
		local st = stroke(btn)
		btn.MouseEnter:Connect(function()
			TweenService:Create(st, TweenInfo.new(0.12), { Color = C.accent }):Play()
		end)
		btn.MouseLeave:Connect(function()
			TweenService:Create(st, TweenInfo.new(0.12), { Color = C.stroke }):Play()
		end)
		btn.MouseButton1Click:Connect(function()
			local ok, err = pcall(callback)
			if not ok then NOV.msg("Error: " .. tostring(err)) end
		end)
		return btn
	end

	--======== NOTIFY ========
	local notifyHolder = Instance.new("Frame")
	notifyHolder.Size = UDim2.new(0, 260, 1, -160)
	notifyHolder.Position = UDim2.new(1, -272, 0, 80)
	notifyHolder.BackgroundTransparency = 1
	notifyHolder.Parent = gui
	local nlay = Instance.new("UIListLayout")
	nlay.Padding = UDim.new(0, 6)
	nlay.VerticalAlignment = Enum.VerticalAlignment.Top
	nlay.Parent = notifyHolder

	NOV.ui.notify = function(text, duration)
		duration = duration or 3
		local nf = Instance.new("Frame")
		nf.Size = UDim2.new(1, 0, 0, 34)
		nf.BackgroundColor3 = C.panel
		nf.BorderSizePixel = 0
		nf.Parent = notifyHolder
		corner(nf, 8)
		stroke(nf, C.accent)

		local acc = Instance.new("Frame")
		acc.Size = UDim2.new(0, 3, 1, -10)
		acc.Position = UDim2.new(0, 6, 0.5, 0)
		acc.AnchorPoint = Vector2.new(0, 0.5)
		acc.BackgroundColor3 = C.accent
		acc.BorderSizePixel = 0
		acc.Parent = nf
		corner(acc, 99)

		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, -24, 1, 0)
		l.Position = UDim2.new(0, 18, 0, 0)
		l.BackgroundTransparency = 1
		l.Text = text
		l.TextColor3 = C.text
		l.TextSize = 11
		l.Font = Enum.Font.GothamMedium
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Parent = nf

		task.delay(duration, function()
			if nf and nf.Parent then
				TweenService:Create(nf, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
				TweenService:Create(l, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
				task.wait(0.25)
				nf:Destroy()
			end
		end)
	end

	NOV.ui.setStatus = function(text)
		statusLbl.Text = text
	end

	NOV.ui.window = win
	NOV.ui.gui = gui
	NOV.ui.colors = C

	close.MouseButton1Click:Connect(function()
		win.Visible = false
		NOV.msg("Window disembunyikan. Tekan " .. tostring(CFG.Keybind):gsub("Enum.KeyCode.", "") .. " untuk buka.")
	end)

	NOV.bind(UIS.InputBegan, function(input, gp)
		if gp then return end
		if input.KeyCode == CFG.Keybind then
			win.Visible = not win.Visible
		end
	end)

	task.spawn(function()
		task.wait(0.2)
		applyResponsive()
		NOV.bind(cam:GetPropertyChangedSignal("ViewportSize"), applyResponsive)
		if NOV.ui.tabs[1] then
			NOV.ui.tabs[1].button.MouseButton1Click:Fire()
		end
	end)
end

--===================== [ 6. ESP ENGINE ] ==================================
do
	local ESP = NOV.esp
	ESP.pool = {}
	ESP.tracked = {}

	local function make(entry)
		local model = entry.model
		local o = {}

		if entry.chams then
			local hl = Instance.new("Highlight")
			hl.Name = "NOVA_Chams"
			hl.Adornee = model
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.FillTransparency = 0.72
			hl.OutlineTransparency = 0
			hl.Parent = cam
			o.hl = hl
		end

		local bb = Instance.new("BillboardGui")
		bb.Name = "NOVA_ESP"
		bb.Adornee = entry.adornee or model
		bb.AlwaysOnTop = true
		bb.Size = UDim2.new(0, 240, 0, 46)
		bb.StudsOffset = Vector3.new(0, 3.1, 0)
		bb.MaxDistance = 1000
		bb.Parent = cam
		o.bb = bb

		local bg = Instance.new("Frame")
		bg.Size = UDim2.new(1, 0, 1, 0)
		bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		bg.BackgroundTransparency = 0.5
		bg.BorderSizePixel = 0
		bg.Parent = bb
		local uc = Instance.new("UICorner")
		uc.CornerRadius = UDim.new(0, 4)
		uc.Parent = bg

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 12
		lbl.TextStrokeTransparency = 0.35
		lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
		lbl.TextYAlignment = Enum.TextYAlignment.Center
		lbl.Text = ""
		lbl.Parent = bg
		o.lbl = lbl

		if entry.box then
			local box = Instance.new("BoxHandleAdornment")
			box.Size = Vector3.new(3, 6, 3)
			box.Adornee = entry.adornee or model
			box.AlwaysOnTop = true
			box.Transparency = 0.6
			box.ZIndex = 5
			box.Parent = cam
			o.box = box
		end

		ESP.pool[model] = o
		return o
	end

	-- sinkronisasi: entry = {model, adornee, text, color, chams, box}
	ESP.sync = function(list)
		local present = {}
		for _, e in ipairs(list) do
			local model = e.model
			if model then
				present[model] = true
				local o = ESP.pool[model]
				if not o then o = make(e) end
				-- chams bisa di-toggle saat runtime
				if e.chams and not o.hl then
					local hl = Instance.new("Highlight")
					hl.Name = "NOVA_Chams"
					hl.Adornee = model
					hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					hl.FillTransparency = 0.72
					hl.OutlineTransparency = 0
					hl.Parent = cam
					o.hl = hl
				elseif (not e.chams) and o.hl then
					o.hl:Destroy()
					o.hl = nil
				end
				-- box juga
				if e.box and not o.box then
					local box = Instance.new("BoxHandleAdornment")
					box.Size = Vector3.new(3, 6, 3)
					box.Adornee = e.adornee or model
					box.AlwaysOnTop = true
					box.Transparency = 0.6
					box.ZIndex = 5
					box.Parent = cam
					o.box = box
				elseif (not e.box) and o.box then
					o.box:Destroy()
					o.box = nil
				end
				if o.bb and o.bb.Adornee ~= (e.adornee or model) then
					o.bb.Adornee = e.adornee or model
				end
				if o.hl then
					o.hl.FillColor = e.color
					o.hl.OutlineColor = e.color
				end
				if o.box then
					o.box.Color3 = e.color
				end
				if o.lbl then
					o.lbl.Text = e.text
					o.lbl.TextColor3 = e.color
				end
			end
		end
		for model, o in pairs(ESP.pool) do
			if not present[model] then
				if o.hl then o.hl:Destroy() end
				if o.bb then o.bb:Destroy() end
				if o.box then o.box:Destroy() end
				ESP.pool[model] = nil
			end
		end
		ESP.count = 0
		for _ in pairs(ESP.pool) do ESP.count = ESP.count + 1 end
	end

	ESP.clear = function()
		for model, o in pairs(ESP.pool) do
			if o.hl then o.hl:Destroy() end
			if o.bb then o.bb:Destroy() end
			if o.box then o.box:Destroy() end
			ESP.pool[model] = nil
		end
	end
end

--===================== [ 7. MAP SCANNER ] =================================
do
	local C = NOV.cache

	local function scanChildren(root, out, attrCheck)
		if not root then return out end
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Model") and attrCheck(d) then
				out[d] = true
			end
		end
		return out
	end

	NOV.scan = function()
		local map = workspace:FindFirstChild("Map")
		if not map then return end

		C.gens, C.hooks, C.pallets, C.windows, C.gates = {}, {}, {}, {}, {}
		C.vaultList = {}

		for _, d in ipairs(map:GetDescendants()) do
			local n = d.Name
			if d:IsA("BasePart") and n == "VaultTrigger" then
				table.insert(C.vaultList, d)
			end
			if d:IsA("Model") then
				if n == "Generator" and (d:GetAttribute("RepairProgress") ~= nil
					or d:GetAttribute("ProgressRepair") ~= nil
					or d:GetAttribute("kickcount") ~= nil) then
					C.gens[d] = true
				end
				local ln = string.lower(n)
				if ln == "hook" or string.find(ln, "hook", 1, true) and d:FindFirstChild("HookPoint", true) then
					C.hooks[d] = true
				end
				if string.find(ln, "pallet", 1, true) and d:FindFirstChildWhichIsA("BasePart", true) then
					C.pallets[d] = true
				end
				if string.find(ln, "window", 1, true) and d:FindFirstChild("VaultTrigger", true) then
					C.windows[d] = true
				end
				if string.find(ln, "exitlever", 1, true) or (string.find(ln, "gate", 1, true) and ln ~= "gatehouse") then
					C.gates[d] = true
				end
			end
		end

		C.genList   = {}
		C.hookList  = {}
		C.palletList= {}
		C.windowList= {}
		C.gateList  = {}
		for k in pairs(C.gens) do table.insert(C.genList, k) end
		for k in pairs(C.hooks) do table.insert(C.hookList, k) end
		for k in pairs(C.pallets) do table.insert(C.palletList, k) end
		for k in pairs(C.windows) do table.insert(C.windowList, k) end
		for k in pairs(C.gates) do table.insert(C.gateList, k) end
	end

	NOV.part = function(model)
		if not model then return nil end
		local p = model.PrimaryPart
		if p and p:IsA("BasePart") then return p end
		local named = model:FindFirstChild("Main", true) or model:FindFirstChild("HookPoint", true)
			or model:FindFirstChild("GeneratorPoint1", true) or model:FindFirstChild("defaultMaterial", true)
			or model:FindFirstChild("HitBox", true)
		if named and named:IsA("BasePart") then return named end
		return model:FindFirstChildWhichIsA("BasePart", true)
	end

	NOV.genProgress = function(gen)
		local p = gen:GetAttribute("RepairProgress")
		if p == nil then p = gen:GetAttribute("ProgressRepair") end
		return tonumber(p) or 0
	end

	NOV.genDone = function(gen)
		local c = gen:GetAttribute("Completed")
		if c ~= nil then return c == true end
		return NOV.genProgress(gen) >= 100
	end

	NOV.nearest = function(list, from)
		local best, bd = nil, math.huge
		from = from or (NOV.hrp() and NOV.hrp().Position)
		if not from then return nil end
		for _, m in ipairs(list or {}) do
			if m and m.Parent then
				local pt = NOV.part(m)
				if pt then
					local d = (pt.Position - from).Magnitude
					if d < bd then bd = d; best = m end
				end
			end
		end
		return best, bd
	end
end

--===================== [ 8. AUTO: SKILLCHECK + REPAIR ] ===================
do
	local R = NOV.remotes

	-- ambil node SkillCheck dari PlayerGui
	local function skillNodes()
		local pg = lp:FindFirstChild("PlayerGui")
		if not pg then return nil end
		local gui = pg:FindFirstChild("SkillCheckPromptGui")
		if not gui then return nil end
		local check = gui:FindFirstChild("Check")
		if not check then return nil end
		local line = check:FindFirstChild("Line")
		local goal = check:FindFirstChild("Goal")
		return check, line, goal
	end

	local lastVisible = false

	local function pressSpace()
		pcall(function()
			VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
			task.wait(0.04)
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
		end)
	end

	-- Layer 1: snap needle + kirim space
	NOV.autoSkill = function()
		if not CFG.GenPerfect then
			lastVisible = false
			return
		end
		local check, line, goal = skillNodes()
		if not check then return end

		local vis = check.Visible
		if vis and not lastVisible then
			task.delay(NOV.delay(), function()
				if not CFG.GenPerfect then return end
				local ck, ln, gl = skillNodes()
				if not ck or not ln or not gl then return end
				pcall(function()
					ln.Rotation = 109 + (gl.Rotation or 0)
				end)
				pressSpace()
			end)
		end
		lastVisible = vis
	end

	-- Layer 2: hook outgoing remote, paksa hasil success
	NOV.installHook = function()
		if not CFG.GenFailSafe then return end
		if NOV.state.hooked then return end
		local ok = pcall(function()
			local mt = getrawmetatable(game)
			local old = mt.__namecall
			setreadonly(mt, false)
			mt.__namecall = newcclosure(function(self, ...)
				local m = getnamecallmethod()
				if m == "FireServer" and not checkcaller() then
					if CFG.GenPerfect and R.genResult and self == R.genResult then
						local a = { ... }
						a[1] = "success"
						a[2] = 1
						return old(self, unpack(a))
					elseif CFG.GenPerfect and R.kingHit and self == R.kingHit then
						local a = { ... }
						a[2] = "success"
						return old(self, unpack(a))
					elseif CFG.AntiFall and R.fall and self == R.fall then
						local a = { ... }
						a[1] = 0
						return old(self, unpack(a))
					elseif CFG.AntiFlash and R.blind and self == R.blind then
						if lp.Team and lp.Team.Name == "Killer" then
							return nil
						end
					end
				end
				return old(self, ...)
			end)
			setreadonly(mt, true)
			NOV.state.hooked = true
		end)
		if not ok then
			NOV.msg("Hook tidak didukung executor ini (Layer 2 off).")
		end
	end

	-- koneksi event QTE dipasang setelah remote di-resolve (dipanggil dari BOOT)
	NOV.autoSkillInit = function()
		if NOV.state.skillInit then return end
		NOV.state.skillInit = true
		if R.genSkill then
			NOV.bind(R.genSkill.OnClientEvent, function() NOV.state.qtePending = true end)
		end
		if R.kingStart then
			NOV.bind(R.kingStart.OnClientEvent, function() NOV.state.qtePending = true end)
		end
	end
end

--===================== [ 9. AUTO: REPAIR / HEAL / PARRY / WIGGLE ] ========
do
	local R = NOV.remotes
	local C = NOV.cache

	NOV.autoRepair = function()
		local hrp = NOV.hrp()
		if not hrp then return end

		local gen, dist = NOV.nearest(C.genList, hrp.Position)
		if not gen then return end

		-- cari GeneratorPoint terdekat
		local point, pd = nil, math.huge
		for _, ch in ipairs(gen:GetChildren()) do
			if ch:IsA("BasePart") and string.find(ch.Name, "GeneratorPoint", 1, true) then
				local d = (ch.Position - hrp.Position).Magnitude
				if d < pd then pd = d; point = ch end
			end
		end
		if not point then return end

		if pd > CFG.RepairRange and CFG.AutoRepairTp then
			NOV.tpTo(point.Position + Vector3.new(0, 3, 0))
			return
		end
		if pd > CFG.RepairRange then return end

		local now = tick()
		if not NOV.state.lastRepair or now - NOV.state.lastRepair >= CFG.RepairRate then
			NOV.state.lastRepair = now
			NOV.state.repairPoint = point
			NOV.playRepairAnim()
			pcall(function()
				if R.genRepair then R.genRepair:FireServer(point, true) end
			end)
		end
	end

	NOV.stopRepair = function()
		NOV.stopRepairAnim()
		local p = NOV.state.repairPoint
		NOV.state.repairPoint = nil
		if p then
			pcall(function()
				if R.genRepair then R.genRepair:FireServer(p, false) end
			end)
		end
	end

	NOV.playRepairAnim = function()
		if NOV.state.repairTrack and NOV.state.repairTrack.IsPlaying then return end
		pcall(function()
			local hum = NOV.hum()
			local anim = hum and hum:FindFirstChildOfClass("Animator")
			if not anim then return end
			local a = Instance.new("Animation")
			a.AnimationId = "rbxassetid://92960319113695"
			local t = anim:LoadAnimation(a)
			t.Priority = Enum.AnimationPriority.Action
			t:Play()
			NOV.state.repairTrack = t
		end)
	end

	NOV.stopRepairAnim = function()
		pcall(function()
			if NOV.state.repairTrack and NOV.state.repairTrack.IsPlaying then
				NOV.state.repairTrack:Stop()
			end
		end)
		NOV.state.repairTrack = nil
	end

	--======== HEAL ========
	NOV.autoHeal = function()
		local hum = NOV.hum()
		local hrp = NOV.hrp()
		if not hum or not hrp then return end
		if hum.Health >= hum.MaxHealth * CFG.HealThreshold then return end
		local char = lp.Character
		local ci = char and char:FindFirstChild("CheckInterractable")
		if ci and (ci:GetAttribute("isRepairing") or ci:GetAttribute("isHealing")) then return end
		local now = tick()
		if NOV.state.lastHeal and now - NOV.state.lastHeal < 0.5 then return end
		NOV.state.lastHeal = now
		pcall(function()
			if R.heal then R.heal:FireServer(hrp, true) end
		end)
	end

	--======== PARRY ========
	NOV.parry = function()
		if not CFG.AutoParry then return end
		if NOV.state.parryCD then return end
		local char = lp.Character
		if not char then return end

		local dagger = char:FindFirstChild("Parrying Dagger")
		local pack = lp:FindFirstChild("Backpack")
		if not dagger and pack then dagger = pack:FindFirstChild("Parrying Dagger") end
		if not dagger then return end

		if CFG.AutoEquipDagger and dagger.Parent == pack then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				pcall(function() hum:EquipTool(dagger) end)
				task.wait(0.08)
			end
		end
		if not char:FindFirstChild("Parrying Dagger") then return end

		NOV.state.parryCD = true
		pcall(function()
			if R.parry then
				for _ = 1, 3 do R.parry:FireServer() end
			end
		end)
		task.delay(CFG.ParryCooldown, function() NOV.state.parryCD = false end)
	end

	NOV.watchKiller = function(char)
		local hum = char:WaitForChild("Humanoid", 5)
		local anim = hum and hum:WaitForChild("Animator", 5)
		if not anim then return end
		NOV.bind(anim.AnimationPlayed, function()
			if not CFG.AutoParry then return end
			local hrp, khrp = NOV.hrp(), char:FindFirstChild("HumanoidRootPart")
			if not hrp or not khrp then return end
			if (hrp.Position - khrp.Position).Magnitude > CFG.ParryRange then return end
			NOV.parry()
		end)
	end

	--======== WIGGLE / ANTI-STUN ========
	NOV.autoWiggle = function()
		if not CFG.AutoWiggle then return end
		local char = lp.Character
		if not char then return end
		if not (char:GetAttribute("IsHooked") or char:GetAttribute("Knocked")) then return end
		pcall(function()
			VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.A, false, game)
			task.wait(0.05)
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.A, false, game)
			VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.D, false, game)
			task.wait(0.05)
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.D, false, game)
		end)
	end

	--======== AUTO VAULT (slide over window/pallet saat lari) ========
	NOV.autoVault = function()
		if not CFG.AutoVault then return end
		local hrp = NOV.hrp()
		if not hrp then return end
		for _, d in ipairs(NOV.cache.vaultList or {}) do
			if d.Parent and (d.Position - hrp.Position).Magnitude < 6 then
				pcall(function()
					if R.vault then R.vault:FireServer(d, true) end
				end)
				return
			end
		end
	end
end

--===================== [ 10. MOVEMENT ] ===================================
do
	local moveBV, moveBG

	NOV.tpTo = function(pos)
		local hrp = NOV.hrp()
		if not hrp or not pos then return end
		if CFG.SmoothTp then
			local dist = (hrp.Position - pos).Magnitude
			local t = math.clamp(dist / 220, 0.05, CFG.SmoothTpTime)
			local tw = TweenService:Create(hrp, TweenInfo.new(t, Enum.EasingStyle.Linear), { CFrame = CFrame.new(pos) })
			tw:Play()
		else
			hrp.CFrame = CFrame.new(pos)
		end
	end

	NOV.setSpeed = function(v)
		local char = lp.Character
		local hum = NOV.hum()
		if hum then
			pcall(function() hum.WalkSpeed = v end)
		end
		if char then
			pcall(function() char:SetAttribute("speedboost", v / 16) end)
		end
	end

	NOV.flyToggle = function(on)
		local hrp = NOV.hrp()
		if not on then
			if moveBV then moveBV:Destroy(); moveBV = nil end
			if moveBG then moveBG:Destroy(); moveBG = nil end
			return
		end
		if not hrp then return end
		moveBV = Instance.new("BodyVelocity")
		moveBV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		moveBV.Velocity = Vector3.zero
		moveBV.Parent = hrp
		moveBG = Instance.new("BodyGyro")
		moveBG.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
		moveBG.P = 9e4
		moveBG.Parent = hrp
	end

	NOV.flyStep = function()
		if not CFG.Fly or not moveBV or not moveBG then return end
		local hrp = NOV.hrp()
		if not hrp then return end
		if moveBV.Parent ~= hrp then
			moveBV.Parent = hrp
			moveBG.Parent = hrp
		end
		local dir = Vector3.zero
		if UIS:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
		if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
		moveBV.Velocity = dir.Magnitude > 0 and dir.Unit * CFG.FlySpeed or Vector3.zero
		moveBG.CFrame = cam.CFrame
	end

	NOV.noclipStep = function()
		if not CFG.Noclip then return end
		local char = lp.Character
		if not char then return end
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") then d.CanCollide = false end
		end
	end
end

--===================== [ 11. VISUAL + REMOTE LOG ] ========================
do
	local origLighting = {
		Brightness = Lighting.Brightness,
		FogEnd = Lighting.FogEnd,
		GlobalShadows = Lighting.GlobalShadows,
		ClockTime = Lighting.ClockTime,
	}

	NOV.applyVisual = function()
		pcall(function()
			if CFG.Fullbright then
				Lighting.Brightness = 3
				Lighting.GlobalShadows = false
				Lighting.Ambient = Color3.fromRGB(178, 178, 178)
			else
				Lighting.Brightness = origLighting.Brightness
				Lighting.GlobalShadows = origLighting.GlobalShadows
				Lighting.Ambient = Color3.fromRGB(70, 70, 70)
			end
			if CFG.NoFog then
				Lighting.FogEnd = 100000
			else
				Lighting.FogEnd = origLighting.FogEnd
			end
			if CFG.TimeOfDay >= 0 then
				Lighting.ClockTime = CFG.TimeOfDay
			else
				Lighting.ClockTime = origLighting.ClockTime
			end
		end)
	end

	NOV.applyFov = function()
		pcall(function()
			if cam then cam.FieldOfView = CFG.CameraFov end
		end)
	end

	NOV.antiFlashStep = function()
		if not CFG.AntiFlash then return end
		local pg = lp:FindFirstChild("PlayerGui")
		if not pg then return end
		for _, d in ipairs(pg:GetDescendants()) do
			local n = string.lower(d.Name)
			if (string.find(n, "flash", 1, true) or string.find(n, "blind", 1, true))
				and (d:IsA("Frame") or d:IsA("ImageLabel") or d:IsA("TextLabel")) then
				if d.Visible then d.Visible = false end
			end
		end
	end

	NOV.remoteLog = function(on)
		if not on then return end
		if NOV.state.logging then return end
		NOV.state.logging = true
		local lines = {}
		pcall(function()
			local mt = getrawmetatable(game)
			local old = mt.__namecall
			setreadonly(mt, false)
			mt.__namecall = newcclosure(function(self, ...)
				local m = getnamecallmethod()
				if (m == "FireServer" or m == "InvokeServer") and not checkcaller() then
					local args = { ... }
					local parts = {}
					for i = 1, math.min(#args, 4) do
						parts[i] = tostring(args[i]) .. "(" .. typeof(args[i]) .. ")"
					end
					local line = string.format("[%s] %s %s", m, self:GetFullName(), table.concat(parts, ", "))
					table.insert(lines, line)
					if #lines > 300 then table.remove(lines, 1) end
					if CFG.RemoteLog then print("[NOVA-RE] " .. line) end
				end
				return old(self, ...)
			end)
			setreadonly(mt, true)
		end)
		NOV.state.logLines = lines
		NOV.msg("Remote logger aktif (lihat tab Misc untuk dump).")
	end
end

--===================== [ 12. SELF TEST + UNLOAD ] =========================
do
	NOV.selfTest = function()
		local out = {}
		local function line(k, ok, detail)
			table.insert(out, string.format("%-22s %s  %s", k, ok and "OK " or "FAIL", detail or ""))
		end

		line("PlaceId", true, tostring(game.PlaceId))
		line("Remotes root", NOV.remotes.root ~= nil, NOV.remotes.root and NOV.remotes.root:GetFullName() or "tidak ketemu")
		line("Generator.RepairEvent", NOV.remotes.genRepair ~= nil, tostring(NOV.remotes.genRepair))
		line("Generator.SkillCheckEvent", NOV.remotes.genSkill ~= nil, tostring(NOV.remotes.genSkill))
		line("Generator.ResultEvent", NOV.remotes.genResult ~= nil, tostring(NOV.remotes.genResult))
		line("Parrying Dagger.parry", NOV.remotes.parry ~= nil, tostring(NOV.remotes.parry))
		line("Healing.HealEvent", NOV.remotes.heal ~= nil, tostring(NOV.remotes.heal))
		line("Pallet.DropEvent", NOV.remotes.palletDrop ~= nil, tostring(NOV.remotes.palletDrop))
		line("Window.VaultEvent", NOV.remotes.vault ~= nil, tostring(NOV.remotes.vault))

		local char = lp.Character
		local hrp = NOV.hrp()
		line("Character/HRP", char ~= nil and hrp ~= nil, char and char:GetFullName() or "-")
		line("Role", true, NOV.role(lp))
		line("Humanoid", NOV.hum() ~= nil, NOV.hum() and tostring(math.floor(NOV.hum().Health)) or "-")
		line("speedboost attr", char and char:GetAttribute("speedboost") ~= nil, tostring(char and char:GetAttribute("speedboost")))

		local C = NOV.cache
		line("Generators scan", #(C.genList or {}) > 0, string.format("%d model", #(C.genList or {})))
		local left = 0
		for _, g in ipairs(C.genList or {}) do
			if not NOV.genDone(g) then left = left + 1 end
		end
		line("Generators belum jadi", true, string.format("%d dari %d", left, #(C.genList or {})))
		line("Hooks scan", true, string.format("%d model", #(C.hookList or {})))
		line("Pallets scan", true, string.format("%d model", #(C.palletList or {})))
		line("Windows scan", true, string.format("%d model", #(C.windowList or {})))
		line("Gates scan", true, string.format("%d model", #(C.gateList or {})))
		line("Dagger di backpack", true, tostring((lp:FindFirstChild("Backpack") and lp.Backpack:FindFirstChild("Parrying Dagger")) ~= nil))

		line("ESP objects", true, tostring(NOV.esp.count or 0))
		line("Hook terpasang", NOV.state.hooked == true, tostring(NOV.state.hooked))
		line("Remote log lines", true, tostring(#(NOV.state.logLines or {})))

		local on = {}
		for k, v in pairs(CFG) do
			if type(v) == "boolean" and v and string.find(k, "^Esp") == nil then
				table.insert(on, k)
			end
		end
		table.sort(on)
		line("Fitur ON", true, table.concat(on, ", "))

		local head = string.format("NOVA VD SELF TEST  (PlaceId %d)\n", game.PlaceId)
		local body = table.concat(out, "\n")
		local tail = string.format("\nVERDICT: %d/%d baris OK\n", #out, #out)
		local report = head .. body .. tail

		print(report)
		warn(report)
		pcall(function() setclipboard(report) end)
		NOV.msg("Self test selesai, hasil dicopy ke clipboard.")
		return report
	end

	NOV.unload = function()
		NOV.alive = false
		for _, c in ipairs(NOV.conns) do
			pcall(function() c:Disconnect() end)
		end
		NOV.conns = {}
		for _, fn in ipairs(NOV.cleanups) do
			pcall(fn)
		end
		NOV.esp.clear()
		pcall(NOV.stopRepair)
		pcall(function() NOV.flyToggle(false) end)
		pcall(function() NOV.ui.gui:Destroy() end)
		NOV_ENV.NOVA_VD_RUNNING = nil
		print("[NOVA] Unloaded.")
	end
end

--===================== [ 13. UI BUILD ] ===================================
do
	local U = NOV.ui
	local C = NOV.cache

	local T = {}
	T.main = U.createTab("Main")
	T.esp  = U.createTab("ESP")
	T.auto = U.createTab("Auto")
	T.combat = U.createTab("Combat")
	T.move = U.createTab("Movement")
	T.vis  = U.createTab("Visual")
	T.tp   = U.createTab("Teleport")
	T.misc = U.createTab("Misc")

	--======== MAIN ========
	U.section(T.main.page, "Preset")
	U.button(T.main.page, "Survivor Preset (Auto Gen + ESP)", function()
		CFG.EspPlayers, CFG.EspGens, CFG.EspGates = true, true, true
		CFG.AutoRepair, CFG.GenPerfect, CFG.AutoHeal, CFG.AutoWiggle = true, true, true, true
		CFG.AutoParry = true
		NOV.installHook()
		NOV.msg("Preset Survivor aktif.")
	end)
	U.button(T.main.page, "Killer Preset (ESP + Speed + Anti Flash)", function()
		CFG.EspPlayers, CFG.EspGates = true, true
		CFG.SpeedEnabled, CFG.AntiFlash = true, true
		NOV.msg("Preset Killer aktif.")
	end)
	U.button(T.main.page, "Matikan Semua Fitur", function()
		for k, v in pairs(CFG) do
			if type(v) == "boolean" and (string.find(k, "^Esp") or string.find(k, "^Auto") or string.find(k, "^Gen")
				or string.find(k, "^Anti") or string.find(k, "^Speed") or string.find(k, "^Fly")
				or string.find(k, "^Noclip") or string.find(k, "^Inf")) then
				CFG[k] = false
			end
		end
		CFG.AutoEquipDagger = true
		CFG.GenFailSafe = true
		pcall(NOV.stopRepair)
		NOV.msg("Semua fitur OFF.")
	end)

	U.section(T.main.page, "Session")
	U.button(T.main.page, "Self Test (copy ke clipboard)", NOV.selfTest)
	U.button(T.main.page, "Scan Ulang Map", function()
		NOV.scan()
		NOV.msg(string.format("Scan: %d generator, %d hook, %d pallet, %d window, %d gate",
			#(C.genList or {}), #(C.hookList or {}), #(C.palletList or {}), #(C.windowList or {}), #(C.gateList or {})))
	end)
	U.button(T.main.page, "Dump Remote (clipboard)", function()
		local all = {}
		local root = ReplicatedStorage:FindFirstChild("Remotes")
		if root then
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
					table.insert(all, d:GetFullName() .. "  [" .. d.ClassName .. "]")
				end
			end
		end
		local text = table.concat(all, "\n")
		pcall(function() setclipboard(text) end)
		print(text)
		NOV.msg(string.format("%d remote dicopy ke clipboard.", #all))
	end)
	U.button(T.main.page, "Unload Script", NOV.unload)

	--======== ESP ========
	U.toggle(T.esp.page, "ESP Pemain", CFG.EspPlayers, function(v) CFG.EspPlayers = v end)
	U.toggle(T.esp.page, "Chams (Highlight)", CFG.EspChams, function(v) CFG.EspChams = v end)
	U.toggle(T.esp.page, "Box", CFG.EspBox, function(v) CFG.EspBox = v end)
	U.toggle(T.esp.page, "Nama", CFG.EspName, function(v) CFG.EspName = v end)
	U.toggle(T.esp.page, "Role Tag", CFG.EspRole, function(v) CFG.EspRole = v end)
	U.toggle(T.esp.page, "Jarak", CFG.EspDist, function(v) CFG.EspDist = v end)
	U.toggle(T.esp.page, "Item / Killer", CFG.EspTool, function(v) CFG.EspTool = v end)
	U.toggle(T.esp.page, "HP", CFG.EspHealth, function(v) CFG.EspHealth = v end)
	U.toggle(T.esp.page, "Hanya Hidup", CFG.EspAliveOnly, function(v) CFG.EspAliveOnly = v end)

	U.section(T.esp.page, "Objek Map")
	U.toggle(T.esp.page, "Generator (%)", CFG.EspGens, function(v) CFG.EspGens = v end)
	U.toggle(T.esp.page, "Gate / Exit", CFG.EspGates, function(v) CFG.EspGates = v end)
	U.toggle(T.esp.page, "Hook", CFG.EspHooks, function(v) CFG.EspHooks = v end)
	U.toggle(T.esp.page, "Pallet", CFG.EspPallets, function(v) CFG.EspPallets = v end)
	U.toggle(T.esp.page, "Window / Vault", CFG.EspWindows, function(v) CFG.EspWindows = v end)

	U.section(T.esp.page, "Lain")
	U.slider(T.esp.page, "Jarak Maks ESP", 100, 3000, CFG.EspMaxDist, 0, function(v) CFG.EspMaxDist = v end)
	U.toggle(T.esp.page, "Alarm Killer Dekat", CFG.KillerAlert, function(v) CFG.KillerAlert = v end)
	U.slider(T.esp.page, "Radius Alarm", 20, 300, CFG.AlertDist, 0, function(v) CFG.AlertDist = v end)

	--======== AUTO ========
	U.section(T.auto.page, "Generator")
	U.toggle(T.auto.page, "Auto Perfect Skillcheck", CFG.GenPerfect, function(v)
		CFG.GenPerfect = v
		if v then NOV.installHook() end
	end)
	U.toggle(T.auto.page, "Fail-Safe Remote Hook", CFG.GenFailSafe, function(v)
		CFG.GenFailSafe = v
		if v then NOV.installHook() end
	end)
	U.slider(T.auto.page, "QTE Delay Min", 0.02, 1, CFG.GenDelayMin, 2, function(v) CFG.GenDelayMin = v end)
	U.slider(T.auto.page, "QTE Delay Max", 0.05, 1.5, CFG.GenDelayMax, 2, function(v) CFG.GenDelayMax = v end)
	U.toggle(T.auto.page, "Auto Repair Generator", CFG.AutoRepair, function(v)
		CFG.AutoRepair = v
		if not v then pcall(NOV.stopRepair) end
	end)
	U.toggle(T.auto.page, "Auto Teleport ke Gen", CFG.AutoRepairTp, function(v) CFG.AutoRepairTp = v end)
	U.slider(T.auto.page, "Jarak Repair", 5, 40, CFG.RepairRange, 0, function(v) CFG.RepairRange = v end)
	U.slider(T.auto.page, "Repair Rate (detik)", 0.1, 2, CFG.RepairRate, 2, function(v) CFG.RepairRate = v end)

	U.section(T.auto.page, "Survivor QoL")
	U.toggle(T.auto.page, "Auto Heal", CFG.AutoHeal, function(v) CFG.AutoHeal = v end)
	U.slider(T.auto.page, "Heal di bawah % HP", 0.3, 1, CFG.HealThreshold, 2, function(v) CFG.HealThreshold = v end)
	U.toggle(T.auto.page, "Auto Wiggle (saat di-hook)", CFG.AutoWiggle, function(v) CFG.AutoWiggle = v end)
	U.toggle(T.auto.page, "Auto Vault", CFG.AutoVault, function(v) CFG.AutoVault = v end)
	U.toggle(T.auto.page, "Anti Fall", CFG.AntiFall, function(v)
		CFG.AntiFall = v
		if v then NOV.installHook() end
	end)

	U.section(T.auto.page, "Status Generator")
	local genStatus = U.label(T.auto.page, "tekan Scan Ulang Map")
	NOV.ui.genStatus = genStatus

	--======== COMBAT ========
	U.section(T.combat.page, "Parry")
	U.toggle(T.combat.page, "Auto Parry", CFG.AutoParry, function(v) CFG.AutoParry = v end)
	U.toggle(T.combat.page, "Auto Equip Dagger", CFG.AutoEquipDagger, function(v) CFG.AutoEquipDagger = v end)
	U.slider(T.combat.page, "Parry Range", 5, 60, CFG.ParryRange, 0, function(v) CFG.ParryRange = v end)
	U.slider(T.combat.page, "Parry Cooldown", 0.2, 5, CFG.ParryCooldown, 2, function(v) CFG.ParryCooldown = v end)
	U.button(T.combat.page, "Parry Sekarang", function()
		NOV.state.parryCD = false
		NOV.parry()
		NOV.msg("Parry manual dikirim.")
	end)

	--======== MOVEMENT ========
	U.section(T.move.page, "Kecepatan")
	U.toggle(T.move.page, "Speed Boost", CFG.SpeedEnabled, function(v) CFG.SpeedEnabled = v end)
	U.slider(T.move.page, "WalkSpeed", 16, 120, CFG.SpeedValue, 0, function(v)
		CFG.SpeedValue = v
		if CFG.SpeedEnabled then NOV.setSpeed(v) end
	end)
	U.section(T.move.page, "Terbang & Noclip")
	U.toggle(T.move.page, "Fly", CFG.Fly, function(v)
		CFG.Fly = v
		NOV.flyToggle(v)
		NOV.msg(v and "Fly ON (WASD + Space/Shift)" or "Fly OFF")
	end)
	U.slider(T.move.page, "Fly Speed", 20, 300, CFG.FlySpeed, 0, function(v) CFG.FlySpeed = v end)
	U.toggle(T.move.page, "Noclip", CFG.Noclip, function(v) CFG.Noclip = v end)
	U.toggle(T.move.page, "Infinite Jump", CFG.InfJump, function(v) CFG.InfJump = v end)
	U.slider(T.move.page, "Gravity", 0, 400, CFG.Gravity, 0, function(v)
		CFG.Gravity = v
		pcall(function() workspace.Gravity = v end)
	end)
	U.section(T.move.page, "Lain")
	U.toggle(T.move.page, "Anti AFK", CFG.AntiAfk, function(v) CFG.AntiAfk = v end)

	--======== VISUAL ========
	U.toggle(T.vis.page, "Fullbright", CFG.Fullbright, function(v) CFG.Fullbright = v; NOV.applyVisual() end)
	U.toggle(T.vis.page, "No Fog", CFG.NoFog, function(v) CFG.NoFog = v; NOV.applyVisual() end)
	U.toggle(T.vis.page, "Anti Flash / Blind", CFG.AntiFlash, function(v)
		CFG.AntiFlash = v
		if v then NOV.installHook() end
	end)
	U.toggle(T.vis.page, "Self Highlight", CFG.SelfHighlight, function(v)
		CFG.SelfHighlight = v
		pcall(function()
			local char = lp.Character
			if not char then return end
			local ex = char:FindFirstChild("NOVA_Self")
			if v then
				if not ex then
					local hl = Instance.new("Highlight")
					hl.Name = "NOVA_Self"
					hl.Adornee = char
					hl.FillColor = CFG.Accent
					hl.FillTransparency = 0.6
					hl.Parent = char
				end
			elseif ex then
				ex:Destroy()
			end
		end)
	end)
	U.slider(T.vis.page, "Camera FOV", 50, 120, CFG.CameraFov, 0, function(v) CFG.CameraFov = v; NOV.applyFov() end)
	U.toggle(T.vis.page, "Zoom Unlock", CFG.InfZoom, function(v)
		CFG.InfZoom = v
		pcall(function()
			if v then
				lp.CameraMaxZoomDistance = 500
				lp.CameraMinZoomDistance = 0.5
			else
				lp.CameraMaxZoomDistance = 128
			end
		end)
	end)
	U.slider(T.vis.page, "Time of Day (0 = off)", 0, 24, 0, 0, function(v)
		CFG.TimeOfDay = v > 0 and v or -1
		NOV.applyVisual()
	end)

	--======== TELEPORT ========
	U.section(T.tp.page, "Objek Map")
	U.button(T.tp.page, "Ke Generator Terdekat", function()
		local m, d = NOV.nearest(C.genList, NOV.hrp() and NOV.hrp().Position)
		local p = m and NOV.part(m)
		if p then NOV.tpTo(p.Position + Vector3.new(0, 3, 0)); NOV.msg(string.format("Gen terdekat %.0f stud", d)) end
	end)
	U.button(T.tp.page, "Ke Gate Terdekat", function()
		local m, d = NOV.nearest(C.gateList, NOV.hrp() and NOV.hrp().Position)
		local p = m and NOV.part(m)
		if p then NOV.tpTo(p.Position + Vector3.new(0, 3, 0)); NOV.msg("Ke gate.") end
	end)
	U.button(T.tp.page, "Ke Hook Terdekat", function()
		local m = NOV.nearest(C.hookList, NOV.hrp() and NOV.hrp().Position)
		local p = m and NOV.part(m)
		if p then NOV.tpTo(p.Position + Vector3.new(0, 3, 0)) end
	end)
	U.section(T.tp.page, "Pemain")
	local tpListHolder = Instance.new("Frame")
	tpListHolder.Size = UDim2.new(1, 0, 0, 0)
	tpListHolder.AutomaticSize = Enum.AutomaticSize.Y
	tpListHolder.BackgroundTransparency = 1
	tpListHolder.Parent = T.tp.page
	local tpLay = Instance.new("UIListLayout")
	tpLay.Padding = UDim.new(0, 5)
	tpLay.Parent = tpListHolder

	local function refreshTP()
		for _, ch in ipairs(tpListHolder:GetChildren()) do
			if ch:IsA("TextButton") then ch:Destroy() end
		end
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lp then
				local role = NOV.role(plr)
				local btn = Instance.new("TextButton")
				btn.Size = UDim2.new(1, 0, 0, 28)
				btn.BackgroundColor3 = NOV.ui.colors.panel2
				btn.Text = string.format("[%s] %s", string.sub(role, 1, 1), plr.Name)
				btn.TextColor3 = role == "Killer" and CFG.ColorKiller or CFG.ColorSurvivor
				btn.TextSize = 12
				btn.Font = Enum.Font.GothamMedium
				btn.AutoButtonColor = false
				btn.Parent = tpListHolder
				local uc = Instance.new("UICorner")
				uc.CornerRadius = UDim.new(0, 7)
				uc.Parent = btn
				btn.MouseButton1Click:Connect(function()
					local char = plr.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart")
					if hrp then
						NOV.tpTo(hrp.Position + Vector3.new(0, 2.5, 0))
						NOV.msg("TP ke " .. plr.Name)
					else
						NOV.msg(plr.Name .. " belum spawn.")
					end
				end)
			end
		end
	end
	NOV.ui.refreshTP = refreshTP
	U.button(T.tp.page, "Refresh Daftar Pemain", refreshTP)
	U.toggle(T.tp.page, "Smooth Teleport", CFG.SmoothTp, function(v) CFG.SmoothTp = v end)
	U.slider(T.tp.page, "Durasi TP", 0.05, 1, CFG.SmoothTpTime, 2, function(v) CFG.SmoothTpTime = v end)

	--======== MISC ========
	U.section(T.misc.page, "Diagnostik")
	U.toggle(T.misc.page, "Remote Log ke Console", CFG.RemoteLog, function(v)
		CFG.RemoteLog = v
		if v then NOV.remoteLog(true) end
	end)
	U.button(T.misc.page, "Dump Remote Log (clipboard)", function()
		local text = table.concat(NOV.state.logLines or {}, "\n")
		pcall(function() setclipboard(text) end)
		NOV.msg(string.format("%d baris log dicopy.", #(NOV.state.logLines or {})))
	end)
	U.toggle(T.misc.page, "Status Overlay", CFG.ShowStats, function(v) CFG.ShowStats = v end)
	U.section(T.misc.page, "Remote Terdeteksi")
	local rlbl = U.label(T.misc.page, NOV.remotes.list())
	NOV.ui.remoteLbl = rlbl
	U.button(T.misc.page, "Re-resolve Remote", function()
		NOV.remotes.resolve()
		if NOV.ui.remoteLbl then NOV.ui.remoteLbl.Text = NOV.remotes.list() end
		NOV.msg("Remote di-resolve ulang.")
	end)
	U.section(T.misc.page, "Info")
	U.label(T.misc.page, "NOVA VD v1.0 · engine UI sendiri (tanpa Rayfield)\n"
		.. "Place: " .. tostring(game.PlaceId) .. "\n"
		.. "Hotkey: " .. tostring(CFG.Keybind):gsub("Enum.KeyCode.", "") .. " untuk show/hide\n"
		.. "Semua aksi server dikirim lewat remote resmi game.", NOV.ui.colors.dim)
end

--===================== [ 14. ESP RENDER LOOP ] ============================
do
	local C = NOV.cache
	local U = NOV.ui

	local function playerEntries(list, hrp)
		if not CFG.EspPlayers then return end
		local myPos = hrp and hrp.Position
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lp then
				local char = plr.Character
				local chrp = char and char:FindFirstChild("HumanoidRootPart")
				local head = char and (char:FindFirstChild("Head") or chrp)
				if char and chrp then
					local hum = char:FindFirstChildOfClass("Humanoid")
					local alive = hum and hum.Health > 0
					if (not CFG.EspAliveOnly) or alive then
						local dist = myPos and (chrp.Position - myPos).Magnitude or 0
						if dist <= CFG.EspMaxDist then
							local role = NOV.role(plr)
							local color = CFG.ColorOther
							if role == "Killer" then color = CFG.ColorKiller
							elseif role == "Survivor" then color = CFG.ColorSurvivor end

							local bits = {}
							if CFG.EspName then table.insert(bits, plr.Name) end
							if CFG.EspRole then table.insert(bits, "[" .. string.sub(role, 1, 4):upper() .. "]") end
							if CFG.EspDist then table.insert(bits, string.format("%.0fm", dist)) end
							local line1 = table.concat(bits, " ")

							local line2 = ""
							if CFG.EspTool then
								local item = plr:GetAttribute("EquippedItem")
								if role == "Killer" then
									local k = plr:GetAttribute("SelectedKiller")
									line2 = "Killer: " .. tostring(k or "?")
								elseif item and item ~= "" and item ~= "None" then
									line2 = "Item: " .. tostring(item)
								end
							end
							if CFG.EspHealth and hum then
								local hp = string.format("HP %.0f/%.0f", hum.Health, hum.MaxHealth)
								line2 = line2 ~= "" and (line2 .. "  " .. hp) or hp
							end

							local text = line2 ~= "" and (line1 .. "\n" .. line2) or line1
							table.insert(list, {
								model = char,
								adornee = head,
								text = text,
								color = color,
								chams = CFG.EspChams,
								box = CFG.EspBox,
							})
						end
					end
				end
			end
		end
	end

	local function objEntries(list, hrp)
		local myPos = hrp and hrp.Position
		local function push(model, color, text)
			if not model or not model.Parent then return end
			local part = NOV.part(model)
			if not part then return end
			local dist = myPos and (part.Position - myPos).Magnitude or 0
			if dist > CFG.EspMaxDist then return end
			table.insert(list, {
				model = model,
				adornee = part,
				text = string.format("%s\n%.0fm", text, dist),
				color = color,
				chams = CFG.EspChams,
				box = false,
			})
		end

		if CFG.EspGens then
			for _, g in ipairs(C.genList or {}) do
				if g.Parent then
					local p = NOV.genProgress(g)
					local done = NOV.genDone(g)
					local col = done and CFG.ColorGenDone or CFG.ColorGen
					push(g, col, done and "Generator [DONE]" or string.format("Generator %.0f%%", p))
				end
			end
		end
		if CFG.EspGates then
			for _, g in ipairs(C.gateList or {}) do push(g, CFG.ColorGate, "Gate / Exit") end
		end
		if CFG.EspHooks then
			for _, g in ipairs(C.hookList or {}) do push(g, CFG.ColorHook, "Hook") end
		end
		if CFG.EspPallets then
			for _, g in ipairs(C.palletList or {}) do push(g, CFG.ColorPallet, "Pallet") end
		end
		if CFG.EspWindows then
			for _, g in ipairs(C.windowList or {}) do push(g, CFG.ColorWindow, "Window") end
		end
	end

	NOV.espFrame = function()
		if not NOV.alive then return end
		local hrp = NOV.hrp()
		local list = {}
		playerEntries(list, hrp)
		objEntries(list, hrp)
		NOV.esp.sync(list)
	end

	-- generator status text
	NOV.genStatusTick = function()
		if not U.genStatus then return end
		local total = #(C.genList or {})
		local left = 0
		for _, g in ipairs(C.genList or {}) do
			if not NOV.genDone(g) then left = left + 1 end
		end
		U.genStatus.Text = string.format("%d generator terdeteksi · %d belum selesai", total, left)
	end
end

--===================== [ 15. STATUS OVERLAY ] =============================
do
	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(0, 210, 0, 118)
	holder.Position = UDim2.new(0, 14, 0, 60)
	holder.BackgroundColor3 = NOV.ui.colors.bg
	holder.BackgroundTransparency = 0.25
	holder.BorderSizePixel = 0
	holder.Visible = false
	holder.Parent = NOV.ui.gui
	local uc = Instance.new("UICorner")
	uc.CornerRadius = UDim.new(0, 10)
	uc.Parent = holder
	local s = Instance.new("UIStroke")
	s.Color = NOV.ui.colors.stroke
	s.Parent = holder

	local hdr = Instance.new("TextLabel")
	hdr.Size = UDim2.new(1, -16, 0, 20)
	hdr.Position = UDim2.new(0, 10, 0, 6)
	hdr.BackgroundTransparency = 1
	hdr.Text = "NOVA VD · STATUS"
	hdr.TextColor3 = CFG.Accent
	hdr.TextSize = 11
	hdr.Font = Enum.Font.GothamBold
	hdr.TextXAlignment = Enum.TextXAlignment.Left
	hdr.Parent = holder

	local body = Instance.new("TextLabel")
	body.Size = UDim2.new(1, -20, 1, -32)
	body.Position = UDim2.new(0, 10, 0, 26)
	body.BackgroundTransparency = 1
	body.TextColor3 = NOV.ui.colors.text
	body.TextSize = 11
	body.Font = Enum.Font.GothamMedium
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.Text = ""
	body.Parent = holder

	NOV.overlayTick = function()
		holder.Visible = CFG.ShowStats and NOV.ui.window.Visible
		if not holder.Visible then return end
		local hum = NOV.hum()
		local role = NOV.role(lp)
		local on = {}
		if CFG.GenPerfect then table.insert(on, "GEN") end
		if CFG.AutoRepair then table.insert(on, "REP") end
		if CFG.AutoParry then table.insert(on, "PARRY") end
		if CFG.AutoHeal then table.insert(on, "HEAL") end
		if CFG.EspPlayers then table.insert(on, "ESP") end
		if CFG.SpeedEnabled then table.insert(on, "SPD") end
		body.Text = string.format(
			"Role   : %s\nHP     : %.0f / %.0f\nESP    : %d objek\nRemote : %d terdeteksi\nON     : %s",
			role,
			hum and hum.Health or 0,
			hum and hum.MaxHealth or 0,
			NOV.esp.count or 0,
			NOV.remotes.count(),
			#on > 0 and table.concat(on, " ") or "-"
		)
	end
end

--===================== [ 16. MAIN LOOPS ] =================================
do
	local lastScan, lastEsp, lastAlert = 0, 0, 0

	local function killerAlert(hrp)
		if not CFG.KillerAlert or not hrp then return end
		local now = tick()
		if now - lastAlert < 3 then return end
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lp and NOV.role(plr) == "Killer" then
				local char = plr.Character
				local khrp = char and char:FindFirstChild("HumanoidRootPart")
				if khrp then
					local d = (khrp.Position - hrp.Position).Magnitude
					if d <= CFG.AlertDist then
						lastAlert = now
						NOV.msg(string.format("KILLER DEKAT: %s (%.0f stud)", plr.Name, d))
						return
					end
				end
			end
		end
	end

	NOV.bind(RunService.Heartbeat, function()
		if not NOV.alive then return end
		local now = tick()

		-- map scan tiap 3 detik
		if now - lastScan >= 3 then
			lastScan = now
			pcall(NOV.scan)
		end

		-- ESP tiap frame (dibatasi 20 Hz biar HP aman)
		if now - lastEsp >= 0.05 then
			lastEsp = now
			pcall(NOV.espFrame)
		end

		pcall(NOV.genStatusTick)
		pcall(NOV.overlayTick)
		pcall(NOV.autoSkill)

		local hrp = NOV.hrp()
		if hrp then
			if CFG.SpeedEnabled then NOV.setSpeed(CFG.SpeedValue) end
			pcall(NOV.flyStep)
			pcall(NOV.noclipStep)
			pcall(NOV.autoRepair)
			pcall(NOV.autoHeal)
			pcall(NOV.autoWiggle)
			if now - (NOV.state.lastVault or 0) > 0.2 then
				NOV.state.lastVault = now
				pcall(NOV.autoVault)
			end
			pcall(killerAlert, hrp)
		end

		if now - (NOV.state.lastFlash or 0) > 0.25 then
			NOV.state.lastFlash = now
			pcall(NOV.antiFlashStep)
		end
	end)

	-- respawn
	NOV.bind(lp.CharacterAdded, function(char)
		task.wait(1.2)
		pcall(function()
			NOV.esp.clear()
			if CFG.Fly then NOV.flyToggle(true) end
			if CFG.SelfHighlight then
				local hl = char:FindFirstChild("NOVA_Self")
				if not hl then
					local h = Instance.new("Highlight")
					h.Name = "NOVA_Self"
					h.Adornee = char
					h.FillColor = CFG.Accent
					h.FillTransparency = 0.6
					h.Parent = char
				end
			end
		end)
	end)

	-- killer animation watch
	NOV.bind(Players.PlayerAdded, function(plr)
		NOV.bind(plr.CharacterAdded, function(char)
			task.wait(1)
			if NOV.role(plr) == "Killer" then
				pcall(NOV.watchKiller, char)
			end
		end)
	end)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= lp then
			local char = plr.Character
			if char and NOV.role(plr) == "Killer" then
				pcall(NOV.watchKiller, char)
			end
		end
	end

	-- anti afk
	NOV.bind(UIS.JumpRequest, function()
		if not CFG.InfJump then return end
		local hum = NOV.hum()
		if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
	end)

	task.spawn(function()
		local vu = game:GetService("VirtualUser")
		while NOV.alive do
			task.wait(60)
			if CFG.AntiAfk then
				pcall(function()
					vu:CaptureController()
					vu:ClickButton2(Vector2.new())
				end)
			end
		end
	end)
end

--===================== [ 17. BOOT ] =======================================
task.spawn(function()
	NOV.remotes.resolve()
	NOV.autoSkillInit()
	if CFG.GenPerfect then NOV.installHook() end
	pcall(NOV.scan)
	if NOV.ui.refreshTP then pcall(NOV.ui.refreshTP) end
	if NOV.ui.remoteLbl then NOV.ui.remoteLbl.Text = NOV.remotes.list() end
	NOV.applyVisual()
	NOV.applyFov()
	NOV.ui.setStatus(string.format("remote: %d", NOV.remotes.count()))
	NOV.ui.notify("NOVA VD v1.0 loaded", 4)
	task.wait(0.4)
	NOV.ui.notify("Hotkey " .. tostring(CFG.Keybind):gsub("Enum.KeyCode.", "") .. " · Self Test di tab Main", 4)
end)

print("[NOVA VD] v1.0 loaded. Remote terdeteksi: " .. tostring(NOV.remotes.count()))
