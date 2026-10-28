--[[ ==========================================================================
     N O V A   V D   |   Violence District Toolkit            v2.2
     --------------------------------------------------------------------------
     File    : nova_vd_v1.lua      (file baru, engine sendiri)
     Engine  : vanilla UI buatan sendiri -- TANPA Rayfield, TANPA loadstring
     Target  : [BUTCHER] Violence District      (PlaceId 93978595733734)
     Platform: Mobile (Delta / Hydrogen) + PC (Xeno / Wave / Swift)

     v2.2 = DASH LOCK beneran (port PANDU Hub): camera aim-lock ke survivor
            terdekat -- trigger klik kanan (PC) / keybind V / tombol move2 (mobile),
            plus tombol DASH LOCK ngambang di HP. Slider range/durasi/smooth + mode Hold.

     v2.1 = port fitur dari source Aeris Hub (kode + arg remote kebaca polos):
       AIM    Aimbot survivor/killer (+FOV circle, wallcheck, predict, smooth)
              Silent aim Flashlight / Twist of Fate / Flask
       SURV   Unlimited Vault (lepas tag CollectionService "Blocked")
              Auto Pallet Slide, Drop All Pallets, Quick Recovery,
              Flowstate No CD, Anti Hook (spam Game.UpdateCharacterLook),
              Fast Bandage, God Mode, Invisible (offset look +5000 Y)
       KILLER No Slowdown, Infinite Lunge (lungeboost), Auto Stalk
       QoL    Stretch Res, Moonwalk, Auto Run, Crosshair,
              Next Killer (AllowKiller/KillerChance), Next Map (8 map),
              Bypass Exit Gate, Instant TP Gate, Save/Load Config

     Remote map dari dump live in-game:
       Generator / Healing / Carry / Attacks / Collision / Pallet / Window /
       Exit / Mechanics / Items / KillerPerks / Killers.Stalker / Events / Game
     Catatan: Remotes.Mechanics.Chat.* (TempBan/PermaBan/Unban) SENGAJA tidak
     dipakai -- itu tool moderasi yang menyasar pemain asli.
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
	EspChams       = false,
	EspBox         = false,
	EspName        = false,
	EspRole        = false,
	EspDist        = false,
	EspTool        = false,
	EspHealth      = false,
	EspGens        = false,
	EspHooks       = false,
	EspPallets     = false,
	EspWindows     = false,
	EspGates       = false,
	EspMaxDist     = 900,
	EspAliveOnly   = false,
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
	GenFailSafe    = false,
	GenDelayMin    = 0.10,
	GenDelayMax    = 0.28,
	AutoRepair     = false,
	AutoRepairTp   = false,
	RepairRange    = 16,
	RepairRate     = 0.35,
	-- Combat
	AutoParry      = false,
	AutoEquipDagger= false,
	ParryRange     = 22,
	ParryCooldown  = 0.8,
	AutoHeal       = false,
	HealThreshold  = 0.85,
	AutoWiggle     = false,
	AutoVault      = false,
	AntiFall       = false,
	AutoSelfUnhook = false,
	UnhookRate     = 0.5,
	AutoExit       = false,
	KillAura       = false,
	AttackRange    = 14,
	AttackRate     = 0.6,
	AttackFace     = false,
	AttackLunge    = false,
	BreakGen       = false,
	BreakRange     = 10,
	BreakRate      = 0.5,
	RealNoclip     = false,
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
	SmoothTp       = false,
	SmoothTpTime   = 0.25,
	-- Misc
	RemoteLog      = false,
	ShowStats      = false,
	-- ==== AIM (port dari source Aeris) ====
	AimSurvivor    = false,
	AimKiller      = false,
	AimPart        = "Torso",
	AimRadius      = 150,
	AimMaxDist     = 300,
	AimSmooth      = 0.40,
	AimPredict     = 0.01,
	AimShowFov     = false,
	AimWallCheck   = false,
	AimKillerDist  = 14,
	SilentFlash    = false,
	SilentToF      = false,
	SilentFlask    = false,
	FlashYOffset   = 1.5,
	-- ==== SURVIVOR UTIL ====
	UnlimitedVault = false,
	PalletSlide    = false,
	QuickRecovery  = false,
	FlowstateNoCD  = false,
	GodMode        = false,
	Invisible      = false,
	AntiHook       = false,
	AntiHookY      = -250,
	AntiHookHz     = 44,
	FastBandage    = false,
	-- ==== KILLER UTIL ====
	NoSlowdown     = false,
	InfiniteLunge  = false,
	LungeValue     = 999,
	AutoStalk      = false,
	StalkRange     = 150,
	-- ==== QoL ====
	StretchRes     = false,
	StretchAmount  = 0.67,
	Moonwalk       = false,
	AutoRun        = false,
	Crosshair      = false,
	CrossSize      = 8,
	NextKiller     = false,
	NextMap        = false,
	BypassGate     = false,
	InstantTPGate  = false,
	-- ==== PORT LANJUTAN (v2.1) ====
	SpearSilent    = false,
	SpearSpeed     = 165,
	SpearGravity   = 103,
	SpearMaxDist   = 500,
	SpearLead      = 1.4,
	PerfectLanding = false,
	AdrenalineRush = false,
	StreamerMode   = false,
	CounterParry   = false,
	CounterParryDist = 15,
	CounterParryRate = 0.3,
	InfCorrupt     = false,
	DashLock       = false,
	DashLockDist   = 250,
	DashLockTime   = 2,
	DashLockSmooth = 0.55,
	DashLockHold   = false,
	DashLockBtn    = true,
	DashLockKey    = Enum.KeyCode.V,
	KorlessMorph   = false,
	SkipEndscreen  = false,
	FakeName       = "NOVA",
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
		R.slow        = child(R.mechanics, "Slow") or child(R.mechanics, "Slowserver")
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
		R.healSkill   = child(R.healing, "SkillCheckEvent")
		R.healResult  = child(R.healing, "SkillCheckResultEvent")
		R.healFail    = child(R.healing, "SkillCheckFailEvent")
		R.healStop    = child(R.healing, "Stophealing")
		R.healReset   = child(R.healing, "Reset")

		local gamef   = child(root, "Game")
		R.look        = child(gamef, "UpdateCharacterLook")

		local fl      = items and child(items, "Flashlight")
		R.blind       = child(fl, "GotBlinded")

		-- ==== baru: hasil dump remote live ====
		R.attacks     = child(root, "Attacks")
		R.basicAttack = child(R.attacks, "BasicAttack")
		R.afterAttack = child(R.attacks, "AfterAttack")
		R.attackHit   = child(R.attacks, "hit")
		R.lunge       = child(R.attacks, "Lunge")
		R.lungeDetect = child(R.attacks, "LungeDetect")
		R.attackLock  = child(R.attacks, "AttackLock")
		R.attackEvt   = child(root, "AttackEvent")

		local killers = child(root, "Killers")
		R.killers      = killers
		R.stalker      = child(killers, "Stalker")
		R.stalkerStart = child(R.stalker, "StartStalking")
		R.stalkerStop  = child(R.stalker, "StopStalking")
		R.stalkerGrab  = child(R.stalker, "grab")
		R.veil         = child(killers, "Veil")
		R.veilSpear    = child(R.veil, "Spearthrow")
		R.abyss        = child(killers, "Abysswalker")
		R.abyssCorrupt = child(R.abyss, "corrupt")
		R.hidden       = child(killers, "Hidden")
		R.hiddenLeap   = child(R.hidden, "Leap")
		R.hiddenM2     = child(R.hidden, "M2")

		R.collision    = child(root, "Collision")
		R.colOff       = child(R.collision, "DisableCollision")
		R.colOn        = child(R.collision, "EnableCollision")

		R.genFail      = child(R.gen, "SkillCheckFailEvent")
		R.genBreak     = child(R.gen, "BreakGenEvent")
		R.genBreakCommit = child(R.gen, "BreakGenCommit")
		R.escapeTime   = child(R.gen, "Escapetime")

		R.vaultCommit  = child(R.window, "VaultCommit")
		R.vaultReject  = child(R.window, "VaultReject")
		R.fastVault    = child(R.window, "fastvault")
		R.vaultAnim    = child(R.window, "VaultAnim")

		R.palletCommit = child(R.pallet, "PalletDropCommit")
		R.palletAnim   = child(R.pallet, "PalletDropAnim")

		R.progress     = child(root, "Progress")
		R.progressEvt  = child(R.progress, "ProgressUpdateEvent")
		R.fovEvent     = child(root, "FovEvent")

		-- ==== dari dump remote lengkap ====
		R.carry        = child(root, "Carry")
		R.hookEvent    = child(R.carry, "HookEvent")
		R.unhookEvent  = child(R.carry, "UnHookEvent")
		R.selfUnhook   = child(R.carry, "SelfUnHookEvent")
		R.hookCommit   = child(R.carry, "HookCommit")
		R.hookReject   = child(R.carry, "HookReject")
		R.carryDrop    = child(R.carry, "DropSurvivorEvent")

		R.exit         = child(root, "Exit")
		R.leverEvent   = child(R.exit, "LeverEvent")

		R.mechTeleport = child(R.mechanics, "Teleportcharacter")
		R.mechAttr     = child(R.mechanics, "ChangeAttribute")
		R.mechInterrupt= child(R.mechanics, "InterruptActions")
		R.mechCancel   = child(R.mechanics, "cancelaction")
		R.mechSync     = child(R.mechanics, "syncPosition")
		R.mechParried  = child(R.mechanics, "parriedclient")
		R.crouch       = child(R.mechanics, "Crouch")

		R.tracker      = child(child(items, "Tracker"), "active")
		R.gateItem     = child(child(items, "Gate"), "gate")
		R.bandage      = child(child(items, "Bandage"), "Fire")
		R.twistFire    = child(child(items, "Twist of Fate"), "Fire")
		R.twistAim     = child(child(items, "Twist of Fate"), "Aim")
		R.shieldRush   = child(child(items, "Riot Shield"), "Rush")
		R.monkeyPaw    = child(child(items, "Monkey Paw"), "Use")
		R.candle       = child(child(items, "WaxBound Candle"), "Fire")
		R.holyWater    = child(child(items, "Holy Water"), "Throw")
		R.adrenShot    = child(child(items, "Adrenaline Shot"), "Healthy")

		local ev       = child(root, "Events")
		local hallo    = ev and child(ev, "Halloween")
		R.evPassClaim  = child(child(hallo, "Pass"), "Claim")
		R.evPassReroll = child(child(hallo, "Pass"), "Reroll")
		R.evCrush      = child(hallo, "Crush")
		R.evMedal      = child(child(ev, "Medal"), "MedalQuestClaim")
		R.evGift       = child(child(ev, "Christmas"), "gift")

		R.playerAction = child(gamef, "PlayerActionEvent")
		R.roundEvt     = child(root, "Round")
		R.teleport     = child(root, "Teleport")

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
			"gen", "genSkill", "genResult", "genFail", "genRepair", "genBreak",
			"dagger", "parry", "parryResult", "kingStart", "kingHit",
			"slow", "fall", "palletDrop", "palletSlide", "palletDone",
			"vault", "vaultDone", "fastVault", "vaultCommit", "vaultReject",
			"heal", "healSkill", "healResult", "look", "blind",
			"basicAttack", "lunge", "attackHit", "attackLock",
			"colOff", "colOn", "progressEvt",
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

	-- HP / tablet: hit target dibesarkan + window bisa di-drag pakai sentuhan
	local TOUCH = UIS.TouchEnabled

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
	win.Size = UDim2.new(0, 560, 0, 370)
	win.Position = UDim2.new(0.5, -280, 0.5, -185)
	win.BackgroundColor3 = C.bg
	win.BorderSizePixel = 0
	win.Active = true
	win.Draggable = false   -- dipakai drag manual: Draggable nggak jalan di HP
	win.ClipsDescendants = true
	win.Parent = gui
	corner(win, 12)
	stroke(win, C.stroke)

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 42)
	bar.BackgroundColor3 = C.panel
	bar.BorderSizePixel = 0
	bar.Parent = win

	-- drag bar (mouse + sentuhan)
	do
		local dragging, dragStart, startPos = false, nil, nil
		bar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging, dragStart, startPos = true, input.Position, win.Position
			end
		end)
		UIS.InputChanged:Connect(function(input)
			if not dragging then return end
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				local d = input.Position - dragStart
				win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
					startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end)
		UIS.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
	end

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
	sub.Text = "Violence District  ·  v2.2"
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

	NOV.ui.tabs  = {}
	NOV.ui.pages = {}

	local pagesHolder  -- forward declaration: dipakai applyResponsive()
	local fab          -- tombol mengambang buka ulang

	-- Layout adaptif. Sempit (= HP) -> tab jadi baris horizontal + window pas layar.
	local function applyResponsive()
		local vp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
		local narrow = (vp.X < 780) or (vp.Y < 440)

		if narrow then
			local w = math.max(260, math.min(vp.X - 16, 620))
			local h = math.max(240, math.min(vp.Y - 16, 420))
			win.Size = UDim2.new(0, w, 0, h)
			win.Position = UDim2.new(0.5, -w / 2, 0.5, -h / 2)

			sidebar.Size = UDim2.new(1, 0, 0, 34)
			sidebar.Position = UDim2.new(0, 0, 0, 42)
			tabList.Size = UDim2.new(1, -8, 1, -6)
			tabList.Position = UDim2.new(0, 4, 0, 3)
			tabLayout.FillDirection = Enum.FillDirection.Horizontal
			tabLayout.Padding = UDim.new(0, 3)

			local n = math.max(1, #NOV.ui.tabs)
			local bw = math.floor((w - 10) / n)
			for _, t in ipairs(NOV.ui.tabs) do
				t.button.Size = UDim2.new(0, bw - 3, 1, 0)
				t.label.TextSize = 10
				t.label.Position = UDim2.new(0, 4, 0, 0)
				t.label.TextXAlignment = Enum.TextXAlignment.Center
				t.label.Text = t.short
				t.dot.Size = UDim2.new(0, 2, 0, 10)
				t.dot.Position = UDim2.new(0, 0, 0.5, -5)
			end

			pagesHolder.Size = UDim2.new(1, 0, 1, 84)
			pagesHolder.Position = UDim2.new(0, 0, 0, 82)
			for _, p in ipairs(NOV.ui.pages) do
				p.Size = UDim2.new(1, -14, 1, -6)
				p.Position = UDim2.new(0, 7, 0, 3)
			end

			sub.Visible = false
			title.Size = UDim2.new(0, 160, 1, 0)
			statusLbl.Size = UDim2.new(0, 90, 1, 0)
			statusLbl.Position = UDim2.new(1, -160, 0, 0)
		else
			local w = math.max(520, math.min(vp.X * 0.52, 620))
			local h = math.max(330, math.min(vp.Y * 0.62, 420))
			win.Size = UDim2.new(0, w, 0, h)
			win.Position = UDim2.new(0.5, -w / 2, 0.5, -h / 2)

			sidebar.Size = UDim2.new(0, 152, 1, -42)
			sidebar.Position = UDim2.new(0, 0, 0, 42)
			tabList.Size = UDim2.new(1, -14, 1, -14)
			tabList.Position = UDim2.new(0, 7, 0, 7)
			tabLayout.FillDirection = Enum.FillDirection.Vertical
			tabLayout.Padding = UDim.new(0, 5)
			for _, t in ipairs(NOV.ui.tabs) do
				t.button.Size = UDim2.new(1, 0, 0, 34)
				t.label.TextSize = 13
				t.label.Position = UDim2.new(0, 12, 0, 0)
				t.label.TextXAlignment = Enum.TextXAlignment.Left
				t.label.Text = t.name
				t.dot.Size = UDim2.new(0, 3, 0, 16)
				t.dot.Position = UDim2.new(0, 0, 0.5, -8)
			end

			pagesHolder.Size = UDim2.new(1, -152, 1, -42)
			pagesHolder.Position = UDim2.new(0, 152, 0, 42)
			for _, p in ipairs(NOV.ui.pages) do
				p.Size = UDim2.new(1, -20, 1, -20)
				p.Position = UDim2.new(0, 10, 0, 10)
			end

			sub.Visible = true
			title.Size = UDim2.new(0, 300, 1, 0)
			statusLbl.Size = UDim2.new(0, 200, 1, 0)
			statusLbl.Position = UDim2.new(1, -270, 0, 0)
		end

		if fab then
			local s = math.clamp(vp.X * 0.085, 46, 62)
			fab.Size = UDim2.new(0, s, 0, s)
		end
	end
	NOV.ui.applyResponsive = applyResponsive

	--======== CONTAINER ========
	pagesHolder = Instance.new("Frame")
	pagesHolder.Size = UDim2.new(1, -152, 1, -42)
	pagesHolder.Position = UDim2.new(0, 152, 0, 42)
	pagesHolder.BackgroundTransparency = 1
	pagesHolder.Parent = win

	NOV.ui.createTab = function(name, short)
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
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.ScrollingDirection = Enum.ScrollingDirection.Y
		page.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
		page.Visible = false

		-- ruang bawah biar item terakhir nggak nempel scrollbar
		local pad = Instance.new("UIPadding")
		pad.PaddingBottom = UDim.new(0, 14)
		pad.Parent = page
		page.Parent = pagesHolder
		local lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, 6)
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Parent = page

		local tab = { button = btn, page = page, label = lbl, dot = dot, layout = lay, name = name, short = short or name }
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
		f.Size = UDim2.new(1, 0, 0, TOUCH and 26 or 22)
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

	NOV.ui.reg = {}

	-- key = nama field di CFG (string) supaya toggle bisa disinkronkan dari preset
	NOV.ui.toggle = function(page, text, key, callback)
		local default
		if type(key) == "string" then
			default = CFG[key] and true or false
		else
			default = key and true or false
		end
		local state = default
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, TOUCH and 40 or 32)
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
			if type(key) == "string" then CFG[key] = state end
			if callback then
				local ok, err = pcall(callback, state)
				if not ok then warn("[NOVA] toggle error: " .. tostring(err)) end
			end
		end)

		api.set(state)
		api.key = type(key) == "string" and key or nil
		if type(key) == "string" then
			NOV.ui.reg[key] = api
		end
		return api
	end

	-- ubah CFG + sinkronkan tampilan toggle-nya (dipakai preset/macro)
	NOV.setCfg = function(key, v)
		CFG[key] = v
		local t = NOV.ui.reg[key]
		if t then t.set(v) end
	end

	NOV.ui.slider = function(page, text, min, max, default, decimals, callback)
		local val = default
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, 0, 0, TOUCH and 50 or 42)
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
		track.Size = UDim2.new(1, -24, 0, TOUCH and 8 or 6)
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
		local ksz = TOUCH and 18 or 12
		knob.Size = UDim2.new(0, ksz, 0, ksz)
		knob.Position = UDim2.new(0, 0, 0.5, -ksz / 2)
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
			knob.Position = UDim2.new(a, -ksz / 2, 0.5, -ksz / 2)
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
				page.ScrollingEnabled = true
			end
		end)
		track.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				page.ScrollingEnabled = false   -- biar geser slider nggak ikut scroll
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
		btn.Size = UDim2.new(1, 0, 0, TOUCH and 38 or 30)
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

	--======== TOMBOL MENGAMBANG (buka ulang di HP, tanpa keyboard) ========
	fab = Instance.new("TextButton")
	fab.Name = "NOVA_Fab"
	fab.Size = UDim2.new(0, 52, 0, 52)
	fab.Position = UDim2.new(0, 12, 0, 96)
	fab.BackgroundColor3 = C.panel
	fab.BackgroundTransparency = 0.1
	fab.Text = "NOVA"
	fab.TextColor3 = C.accent
	fab.TextSize = 12
	fab.Font = Enum.Font.GothamBlack
	fab.AutoButtonColor = false
	fab.Visible = false
	fab.Active = true
	fab.Selectable = false
	fab.Parent = gui
	corner(fab, 99)
	stroke(fab, C.accent, 2)

	local function setWin(v)
		win.Visible = v and true or false
		fab.Visible = not win.Visible
	end
	NOV.ui.setWin = setWin

	fab.MouseButton1Click:Connect(function()
		setWin(true)
	end)

	--======== TOMBOL "—" (minimize) DI TOP BAR ========
	local minBtn = Instance.new("TextButton")
	minBtn.Size = UDim2.new(0, 30, 0, 34)
	minBtn.Position = UDim2.new(1, -68, 0.5, -17)
	minBtn.BackgroundTransparency = 1
	minBtn.Text = "—"
	minBtn.TextColor3 = C.dim
	minBtn.TextSize = 18
	minBtn.Font = Enum.Font.GothamBold
	minBtn.AutoButtonColor = false
	minBtn.Parent = bar
	minBtn.MouseButton1Click:Connect(function()
		setWin(false)
		NOV.msg("Window disembunyikan. Tekan tombol NOVA kiri atas untuk buka.")
	end)

	NOV.ui.window = win
	NOV.ui.gui = gui
	NOV.ui.colors = C

	close.MouseButton1Click:Connect(function()
		setWin(false)
		NOV.msg("Window disembunyikan. Tekan tombol NOVA kiri atas untuk buka.")
	end)

	NOV.bind(UIS.InputBegan, function(input, gp)
		if input.KeyCode == CFG.Keybind then
			-- keybind diproses walau game menganggapnya "processed"
			setWin(not win.Visible)
			return
		end
		if gp then return end
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

	NOV.scan = function()
		local map = workspace:FindFirstChild("Map")
		local root = map or workspace

		C.gens, C.hooks, C.pallets, C.windows, C.gates = {}, {}, {}, {}, {}
		C.vaultList = {}
		C.scanRoot = map and "Map" or "workspace"

		local function consider(d)
			local n = d.Name
			if d:IsA("BasePart") and n == "VaultTrigger" then
				table.insert(C.vaultList, d)
			end
			if not d:IsA("Model") then return end
			local ln = string.lower(n)

			-- Generator: nama ada "generator" (+ bukan part "GeneratorPoint"),
			-- dan punya atribut progress ATAU anak GeneratorPoint
			if string.find(ln, "generator", 1, true) and not string.find(ln, "point", 1, true) then
				if d:GetAttribute("RepairProgress") ~= nil
					or d:GetAttribute("ProgressRepair") ~= nil
					or d:GetAttribute("kickcount") ~= nil
					or d:FindFirstChild("GeneratorPoint1", true)
					or d:FindFirstChild("GeneratorPoint", true) then
					C.gens[d] = true
				end
			end

			if string.find(ln, "hook", 1, true) and d:FindFirstChild("HookPoint", true) then
				C.hooks[d] = true
			end

			if string.find(ln, "pallet", 1, true) and not string.find(ln, "point", 1, true)
				and (d:FindFirstChild("PrimaryPartPallet", true) or d:FindFirstChild("PalletPoint", true)) then
				C.pallets[d] = true
			end

			if string.find(ln, "window", 1, true)
				and (d:FindFirstChild("VaultTrigger", true) or d:FindFirstChild("VaultPoint", true)) then
				C.windows[d] = true
			end

			if string.find(ln, "exitlever", 1, true) or string.find(ln, "exit", 1, true)
				or (string.find(ln, "gate", 1, true) and not string.find(ln, "gatehouse", 1, true)) then
				C.gates[d] = true
			end
		end

		for _, d in ipairs(root:GetDescendants()) do
			consider(d)
		end

		-- fallback: Map ada tapi generator nol -> sisir sisa workspace
		if map and next(C.gens) == nil then
			for _, d in ipairs(workspace:GetDescendants()) do
				if not d:IsDescendantOf(map) then
					consider(d)
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
			or model:FindFirstChild("HitBox", true) or model:FindFirstChild("PrimaryPartPallet", true)
		if named and named:IsA("BasePart") then return named end
		-- GeneratorPoint bisa bernama "GeneratorPoint", "GeneratorPoint1", "GeneratorPointA", dst.
		for _, ch in ipairs(model:GetChildren()) do
			if ch:IsA("BasePart") and string.find(ch.Name, "GeneratorPoint", 1, true) then
				return ch
			end
		end
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
					if CFG.GenPerfect and typeof(self) == "Instance" then
						local nm = string.lower(self.Name)
						if string.find(nm, "skillcheckresult", 1, true) then
							local a = { ... }
							a[1] = "success"
							if a[2] == nil then a[2] = 1 end
							return old(self, unpack(a))
						elseif nm == "kingscourgehit" then
							local a = { ... }
							a[2] = "success"
							return old(self, unpack(a))
						end
					end
					if CFG.AntiFall and R.fall and self == R.fall then
						local a = { ... }
						a[1] = 0
						return old(self, unpack(a))
					elseif CFG.AntiFlash and R.blind and self == R.blind then
						if lp.Team and lp.Team.Name == "Killer" then
							return nil
						end
					end

					-- INVISIBLE: geser CFrame UpdateCharacterLook keluar peta
					if CFG.Invisible and self == R.look then
						local a = {}
						for i, v in ipairs({ ... }) do
							if typeof(v) == "CFrame" then
								a[i] = v * CFrame.new(0, 5000, 0)
							else
								a[i] = v
							end
						end
						return old(self, unpack(a))
					end

					-- SILENT AIM Twist of Fate: arg Vector3 pertama = arah ke target
					if CFG.SilentToF and self == R.twistFire then
						local a = { ... }
						local tgt = NOV.silentTarget and NOV.silentTarget()
						if tgt then
							local hrp = NOV.hrp()
							local from = hrp and hrp.Position or cam.CFrame.Position
							local dir = (tgt.Position - from)
							if dir.Magnitude > 0.001 then
								for i = 1, math.min(#a, 4) do
									if typeof(a[i]) == "Vector3" then
										a[i] = dir.Unit
										break
									end
								end
							end
						end
						return old(self, unpack(a))
					end

					-- SILENT AIM Flask (Cure): arah throw diganti ke survivor terdekat
					if CFG.SilentFlask and typeof(self) == "Instance" and self.Name == "ThrowFlask" then
						local a = { ... }
						local tgt = NOV.silentTarget and NOV.silentTarget()
						if tgt and a[2] ~= nil and typeof(a[2]) == "Vector3" then
							a[1] = (tgt.Position - a[2]).Unit
							setnamecallmethod(m)
							return old(self, unpack(a))
						end
					end

					-- SILENT VEIL (spear): arah balistik + lead target
					if CFG.SpearSilent and typeof(self) == "Instance" and self.Name == "Spearthrow" then
						local hrp = NOV.hrp()
						local origin = hrp and hrp.Position
						local target = NOV.silentTarget and NOV.silentTarget()
						if target and origin and target.Parent then
							local speed = CFG.SpearSpeed
							local gravity = CFG.SpearGravity
							local hum = target.Parent:FindFirstChildOfClass("Humanoid")
							local mv = Vector3.zero
							if hum and hum.MoveDirection.Magnitude > 0 then
								mv = hum.MoveDirection * hum.WalkSpeed
							elseif target:IsA("BasePart") then
								mv = target.AssemblyLinearVelocity
							end
							local planar = Vector3.new(mv.X, 0, mv.Z)
							local delta = target.Position - origin
							local dist = delta.Magnitude
							if dist > 0.1 and dist <= CFG.SpearMaxDist then
								local horiz = Vector3.new(delta.X, 0, delta.Z).Magnitude
								local travel = select(2, NOV.ballistic(speed, gravity, horiz, delta.Y))
								local leadPos = target.Position + planar * (travel or 0) * CFG.SpearLead
								local d2 = leadPos - origin
								local h2 = Vector3.new(d2.X, 0, d2.Z).Magnitude
								local ang2 = select(1, NOV.ballistic(speed, gravity, math.max(h2, 0.1), d2.Y))
								local dir
								if h2 > 0.001 then
									dir = Vector3.new(d2.X, 0, d2.Z).Unit * math.cos(ang2)
										+ Vector3.new(0, math.sin(ang2), 0)
								else
									dir = d2.Unit
								end
								setnamecallmethod(m)
								return old(self, dir, speed, origin)
							end
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
		if R.healSkill then
			NOV.bind(R.healSkill.OnClientEvent, function() NOV.state.qtePending = true end)
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

--===================== [ 9b. AUTO: VD EXTRA (attack/carry/exit) ] ==========
do
	local R = NOV.remotes
	local C = NOV.cache

	--======== AUTO SELF-UNHOOK (remote resmi, bukan simulasi tombol) ========
	NOV.autoSelfUnhook = function()
		if not CFG.AutoSelfUnhook then return end
		local char = lp.Character
		if not char then return end
		local hooked = char:GetAttribute("IsHooked") or char:GetAttribute("IsCarried")
		if not hooked then return end
		local now = tick()
		if NOV.state.lastUnhook and now - NOV.state.lastUnhook < (CFG.UnhookRate or 0.5) then return end
		NOV.state.lastUnhook = now
		pcall(function()
			if R.selfUnhook then R.selfUnhook:FireServer() end
		end)
		-- fallback: kalau remote kosong, tetap wiggle
		if not R.selfUnhook then NOV.autoWiggle() end
	end

	--======== AUTO EXIT LEVER (buka gate keluar) ========
	NOV.autoExitLever = function()
		if not CFG.AutoExit then return end
		local hrp = NOV.hrp()
		if not hrp then return end
		local lever = workspace:FindFirstChild("Map")
		if lever then
			for _, d in ipairs(lever:GetDescendants()) do
				if d:IsA("BasePart") and (d.Name == "Main" or d.Name == "ExitLever" or d.Name == "Lever")
					and d:IsDescendantOf(lever) then
					local parent = d.Parent
					local isExit = parent and (string.find(string.lower(parent.Name), "exit", 1, true)
						or string.find(string.lower(parent.Name), "lever", 1, true))
					if isExit and (d.Position - hrp.Position).Magnitude < 8 then
						local now = tick()
						if NOV.state.lastLever and now - NOV.state.lastLever < 0.6 then return end
						NOV.state.lastLever = now
						pcall(function()
							if R.leverEvent then R.leverEvent:FireServer(d) end
						end)
						return
					end
				end
			end
		end
	end

	--======== KILL AURA / AUTO ATTACK (killer) ========
	NOV.killAura = function()
		if not CFG.KillAura then return end
		if NOV.role(lp) ~= "Killer" then return end
		local hrp = NOV.hrp()
		if not hrp then return end

		local best, bd = nil, math.huge
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lp and NOV.role(plr) ~= "Killer" then
				local char = plr.Character
				local thrp = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if thrp and hum and hum.Health > 0 then
					local d = (thrp.Position - hrp.Position).Magnitude
					if d <= CFG.AttackRange and d < bd and not char:GetAttribute("IsHooked") then
						bd = d
						best = thrp
					end
				end
			end
		end
		if not best then return end

		local now = tick()
		if NOV.state.lastAtk and now - NOV.state.lastAtk < CFG.AttackRate then return end
		NOV.state.lastAtk = now

		if CFG.AttackFace then
			pcall(function()
				hrp.CFrame = CFrame.new(hrp.Position, Vector3.new(best.Position.X, hrp.Position.Y, best.Position.Z))
			end)
		end
		pcall(function()
			if R.basicAttack then R.basicAttack:FireServer() end
		end)
		if CFG.AttackLunge then
			pcall(function()
				if R.lunge then R.lunge:FireServer() end
			end)
		end
	end

	--======== BREAK GENERATOR (killer) ========
	NOV.breakGen = function()
		if not CFG.BreakGen then return end
		local hrp = NOV.hrp()
		if not hrp then return end
		local gen, d = NOV.nearest(C.genList, hrp.Position)
		if not gen or (d or 999) > CFG.BreakRange then return end
		local now = tick()
		if NOV.state.lastBreak and now - NOV.state.lastBreak < CFG.BreakRate then return end
		NOV.state.lastBreak = now
		local pt = NOV.part(gen)
		pcall(function()
			if R.genBreak then R.genBreak:FireServer(pt or gen) end
		end)
	end

	--======== REAL NOCLIP (collision server-side) ========
	NOV.realNoclip = function(on)
		pcall(function()
			if on and R.colOff then
				R.colOff:FireServer(lp.Character)
			elseif (not on) and R.colOn then
				R.colOn:FireServer(lp.Character)
			end
		end)
	end

	--======== CLAIM REWARD EVENT (sekali tekan) ========
	NOV.claimEvents = function()
		local done = {}
		pcall(function()
			if R.evMedal then
				local ok, res = pcall(function() return R.evMedal:InvokeServer() end)
				table.insert(done, "MedalQuestClaim=" .. tostring(ok) .. " " .. tostring(res))
			end
			if R.evPassClaim then
				R.evPassClaim:FireServer()
				table.insert(done, "HalloweenPassClaim=ok")
			end
			if R.evGift then
				R.evGift:FireServer()
				table.insert(done, "ChristmasGift=ok")
			end
		end)
		NOV.msg(#done > 0 and table.concat(done, " | ") or "Tidak ada remote event yang ketemu.")
	end

	--======== INTERRUPT ACTION (batalkan aksi berjalan) ========
	NOV.interruptActions = function()
		pcall(function()
			if R.mechInterrupt then R.mechInterrupt:FireServer() end
			if R.mechCancel then R.mechCancel:FireServer() end
		end)
		NOV.msg("Interrupt/cancel action dikirim.")
	end

	--======== PROBE ChangeAttribute (eksperimen) ========
	NOV.probeAttr = function(name, value)
		local char = lp.Character
		if not char then return end
		if not R.mechAttr then NOV.msg("Mechanics.ChangeAttribute tidak ada.") return end
		pcall(function() R.mechAttr:FireServer(char, name, value) end)
		pcall(function() R.mechAttr:FireServer(char, { name, value }) end)
		NOV.msg("Probe ChangeAttribute: " .. tostring(name) .. " = " .. tostring(value) .. " (cek Remote Log)")
	end
end

--===================== [ 9c. AIM (port dari source Aeris) ] ===============
do
	local R = NOV.remotes
	local aimGui, aimCircle, crossGui
	local lastTarget, lastTargetTime = nil, 0

	local function tPart(char)
		if not char then return nil end
		local p = char:FindFirstChild(CFG.AimPart)
		if not (p and p:IsA("BasePart")) then p = char:FindFirstChild("Torso") end
		if not (p and p:IsA("BasePart")) then p = char:FindFirstChild("UpperTorso") end
		if not (p and p:IsA("BasePart")) then p = char:FindFirstChild("HumanoidRootPart") end
		return p
	end

	local function downed(char)
		return char:GetAttribute("Knocked") == true or char:GetAttribute("IsHooked") == true
	end

	NOV.aimMode = function()
		local role = NOV.role(lp)
		if role == "Killer" and CFG.AimKiller then return "killer" end
		if role ~= "Killer" and CFG.AimSurvivor then return "survivor" end
		return nil
	end

	NOV.aimTarget = function()
		local mode = NOV.aimMode()
		if not mode then return nil end
		local hrp = NOV.hrp()
		if not hrp then return nil end
		local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
		local best, score = nil, math.huge

		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lp then
				local isK = NOV.isKiller(plr)
				local wanted = (mode == "survivor") and isK or ((mode == "killer") and (not isK))
				if wanted then
					local char = plr.Character
					local chrp = char and char:FindFirstChild("HumanoidRootPart")
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					if chrp and hum and hum.Health > 0 then
						if (mode == "killer") and downed(char) then
							-- survivor yang sudah knocked/hooked dilewati (sama seperti Aeris)
						else
							local part = tPart(char) or chrp
							local d = (chrp.Position - hrp.Position).Magnitude
							local maxD = (mode == "survivor") and CFG.AimMaxDist or CFG.AimKillerDist
							if d <= maxD then
								if mode == "survivor" then
									local sp = cam:WorldToViewportPoint(part.Position)
									local m = (Vector2.new(sp.X, sp.Y) - center).Magnitude
									if m <= CFG.AimRadius and m < score then
										score = m
										best = part
									end
								else
									if d < score then
										score = d
										best = part
									end
								end
							end
						end
					end
				end
			end
		end

		if best and CFG.AimWallCheck then
			if not NOV.rayClear(cam.CFrame.Position, best.Position) then
				return nil
			end
		end
		return best
	end

	--======== FOV CIRCLE + CROSSHAIR ========
	NOV.updateAimDraw = function()
		local mode = NOV.aimMode()
		local wantCircle = CFG.AimShowFov and mode ~= nil
		if wantCircle and not (aimGui and aimGui.Parent) then
			aimGui = Instance.new("ScreenGui")
			aimGui.Name = "NOVA_AimFov"
			aimGui.ResetOnSpawn = false
			aimGui.IgnoreGuiInset = true
			aimGui.Parent = NOV.ui.gui
			aimCircle = Instance.new("Frame")
			aimCircle.AnchorPoint = Vector2.new(0.5, 0.5)
			aimCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
			aimCircle.BackgroundTransparency = 1
			aimCircle.Parent = aimGui
			local uc = Instance.new("UICorner")
			uc.CornerRadius = UDim.new(1, 0)
			uc.Parent = aimCircle
			local st = Instance.new("UIStroke")
			st.Color = CFG.Accent
			st.Thickness = 1.5
			st.Transparency = 0.3
			st.Parent = aimCircle
		end
		if aimCircle then
			aimCircle.Visible = wantCircle
			if wantCircle then
				local r = (mode == "survivor") and CFG.AimRadius or 40
				aimCircle.Size = UDim2.new(0, r * 2, 0, r * 2)
			end
		end
		return mode
	end

	NOV.buildCrosshair = function()
		if crossGui and crossGui.Parent then
			crossGui:Destroy()
		end
		crossGui = nil
		if not CFG.Crosshair then return end
		local s = CFG.CrossSize
		crossGui = Instance.new("ScreenGui")
		crossGui.Name = "NOVA_Crosshair"
		crossGui.ResetOnSpawn = false
		crossGui.IgnoreGuiInset = true
		crossGui.Parent = NOV.ui.gui
		local function bar(w, h, x, y)
			local f = Instance.new("Frame")
			f.Size = UDim2.new(0, w, 0, h)
			f.Position = UDim2.new(0.5, x, 0.5, y)
			f.BackgroundColor3 = CFG.Accent
			f.BorderSizePixel = 0
			f.ZIndex = 20
			f.Parent = crossGui
		end
		bar(s, 2, -s - 3, -1)
		bar(s, 2, 3, -1)
		bar(2, s, -1, -s - 3)
		bar(2, s, -1, 3)
	end

	--======== AIMBOT APPLICATION ========
	NOV.aimStep = function()
		local mode = NOV.updateAimDraw()
		if mode then
			local part = NOV.aimTarget()
			if part then
				local pos = part.Position
				local hrp = NOV.hrp()
				local d = hrp and (pos - hrp.Position).Magnitude or 0
				if d < 100 and CFG.AimPredict > 0 then
					pos = pos + cam.CFrame.RightVector * ((100 - d) * CFG.AimPredict)
				end
				local sm = math.clamp(CFG.AimSmooth, 0.05, 1)
				cam.CFrame = cam.CFrame:Lerp(CFrame.new(cam.CFrame.Position, pos), sm)
				if hrp then
					local face = CFrame.new(hrp.Position, Vector3.new(pos.X, hrp.Position.Y, pos.Z))
					hrp.CFrame = hrp.CFrame:Lerp(face, sm)
				end
			end
		end

		-- Silent aim flashlight: kamera + badan ngarah ke killer
		if CFG.SilentFlash then
			local best, bd = nil, math.huge
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= lp and NOV.isKiller(plr) then
					local char = plr.Character
					local chrp = char and char:FindFirstChild("HumanoidRootPart")
					if chrp then
						local dd = (chrp.Position - cam.CFrame.Position).Magnitude
						if dd < bd then bd = dd; best = chrp end
					end
				end
			end
			if best then
				local aim = best.Position + Vector3.new(0, CFG.FlashYOffset, 0)
				cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, aim), 0.5)
				local hrp = NOV.hrp()
				if hrp then
					local face = CFrame.lookAt(hrp.Position, Vector3.new(aim.X, hrp.Position.Y, aim.Z))
					hrp.CFrame = hrp.CFrame:Lerp(face, 0.5)
				end
			end
		end
	end

	--======== DIRECT TARGET NAMES buat silent aim remote ========
	NOV.silentTarget = function()
		local mode = NOV.aimMode()
		if mode == "survivor" then return NOV.aimTarget() end
		local best, bd = nil, math.huge
		local hrp = NOV.hrp()
		local from = hrp and hrp.Position or cam.CFrame.Position
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lp and not NOV.isKiller(plr) then
				local char = plr.Character
				local chrp = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if chrp and hum and hum.Health > 0 then
					local d = (chrp.Position - from).Magnitude
					if d < bd and d <= 400 then bd = d; best = chrp end
				end
			end
		end
		return best
	end
end

--===================== [ 9d. VD UTIL: survivor / killer / QoL ] ==========
do
	local R = NOV.remotes
	local C = NOV.cache

	--======== UNLIMITED VAULT ========
	-- Game menandai window "Blocked" lewat CollectionService. Hapus tag-nya.
	NOV.unlimitedVault = function(on)
		pcall(function()
			if on then
				for _, v in ipairs(CollectionService:GetTagged("Blocked")) do
					CollectionService:RemoveTag(v, "Blocked")
				end
				if not NOV.state.vaultConn then
					NOV.state.vaultConn = CollectionService:GetInstanceAddedSignal("Blocked"):Connect(function(inst)
						if CFG.UnlimitedVault then
							pcall(function() CollectionService:RemoveTag(inst, "Blocked") end)
						end
					end)
				end
			else
				if NOV.state.vaultConn then
					NOV.state.vaultConn:Disconnect()
					NOV.state.vaultConn = nil
				end
			end
		end)
	end

	--======== AUTO PALLET SLIDE + DROP PALLET ========
	NOV.palletStep = function()
		local hrp = NOV.hrp()
		if not hrp then return end
		local now = tick()

		if CFG.PalletSlide then
			local map = workspace:FindFirstChild("Map")
			if map then
				for _, d in ipairs(map:GetDescendants()) do
					if d:IsA("BasePart") and d.Name == "PalletPointSlide"
						and (d.Position - hrp.Position).Magnitude < 8 then
						if not NOV.state.lastSlide or now - NOV.state.lastSlide > 0.4 then
							NOV.state.lastSlide = now
							pcall(function()
								if R.palletSlide then R.palletSlide:FireServer(d, true) end
							end)
						end
						return
					end
				end
			end
		end

		if CFG.AutoVault and R.palletDrop then
			for _, m in ipairs(C.palletList or {}) do
				if m.Parent then
					local pt = m:FindFirstChild("PalletPoint", true)
					if pt and pt:IsA("BasePart") and (pt.Position - hrp.Position).Magnitude < 8 then
						if not NOV.state.lastDrop or now - NOV.state.lastDrop > 0.5 then
							NOV.state.lastDrop = now
							pcall(function() R.palletDrop:FireServer(pt) end)
						end
						return
					end
				end
			end
		end
	end

	NOV.dropAllPallets = function()
		local map = workspace:FindFirstChild("Map")
		if not map then NOV.msg("Map tidak ketemu.") return end
		local n = 0
		for _, d in ipairs(map:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "PalletPoint" then
				if R.palletDrop then
					pcall(function() R.palletDrop:FireServer(d) end)
					n = n + 1
				end
			end
		end
		NOV.msg(string.format("%d pallet dikirim drop.", n))
	end

	--======== ANTI HOOK / INVISIBLE ========
	NOV.antiHookStep = function(dt)
		if not CFG.AntiHook then
			NOV.state.hookAcc = 0
			return
		end
		local char = lp.Character
		if not char then NOV.state.hookAcc = 0 return end
		if char:GetAttribute("IsCarried") ~= true then
			NOV.state.hookAcc = 0
			return
		end
		if not R.look then return end
		local interval = 1 / math.max(1, CFG.AntiHookHz)
		NOV.state.hookAcc = (NOV.state.hookAcc or 0) + dt
		local guard = 0
		while (NOV.state.hookAcc or 0) >= interval and guard < 4 do
			NOV.state.hookAcc = NOV.state.hookAcc - interval
			guard = guard + 1
			local c1 = CFrame.new(0, 1, 0)
			local c2 = CFrame.new(0, CFG.AntiHookY, 0)
			pcall(function() R.look:FireServer(c1, c2, c2, c2, c2) end)
		end
	end

	--======== GOD MODE / NO SLOWDOWN / INFINITE LUNGE / FLOWSTATE ========
	NOV.killerUtilStep = function()
		local char = lp.Character
		local hum = NOV.hum()
		if not char or not hum then return end

		if CFG.GodMode and hum.Health < hum.MaxHealth then
			pcall(function() hum.Health = hum.MaxHealth end)
		end

		if CFG.NoSlowdown and NOV.role(lp) == "Killer" and hum.WalkSpeed < 16 then
			pcall(function() hum.WalkSpeed = 16 end)
		end

		if CFG.InfiniteLunge then
			if char:GetAttribute("lungeboost") ~= CFG.LungeValue then
				pcall(function() char:SetAttribute("lungeboost", CFG.LungeValue) end)
			end
		end

		if CFG.FlowstateNoCD then
			if char:GetAttribute("Flowstate") ~= true then
				pcall(function() char:SetAttribute("Flowstate", true) end)
			end
		end
	end

	--======== QUICK RECOVERY (vault -> speedboost 1.4, 3 detik) ========
	NOV.quickRecoveryStep = function()
		if not CFG.QuickRecovery then return end
		local char = lp.Character
		if not char then return end
		local ci = char:FindFirstChild("CheckInterractable")
		local vaulting = ci and ci:GetAttribute("isVaulting") == true
		if vaulting and not NOV.state.qrActive then
			NOV.state.qrActive = true
			local until_ = tick() + 3
			task.spawn(function()
				while tick() < until_ and NOV.alive and CFG.QuickRecovery do
					pcall(function() char:SetAttribute("speedboost", 1.4) end)
					task.wait()
				end
				pcall(function() char:SetAttribute("speedboost", 1) end)
				NOV.state.qrActive = false
			end)
		end
	end

	--======== FAST BANDAGE (eksperimen) ========
	NOV.fastBandageStep = function()
		if not CFG.FastBandage then return end
		local hum = NOV.hum()
		if not hum or hum.Health >= hum.MaxHealth then return end
		local now = tick()
		if NOV.state.lastBandage and now - NOV.state.lastBandage < 0.5 then return end
		NOV.state.lastBandage = now
		pcall(function()
			if R.bandage then R.bandage:FireServer() end
		end)
	end

	--======== AUTO STALK (killer) ========
	NOV.autoStalkStep = function()
		if not CFG.AutoStalk then return end
		if NOV.role(lp) ~= "Killer" then return end
		local hrp = NOV.hrp()
		if not hrp then return end
		local stalk = R.stalkerStart
		if not stalk then return end
		local now = tick()
		if NOV.state.lastStalk and now - NOV.state.lastStalk < 0.35 then return end
		local target = nil
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lp and not NOV.isKiller(plr) then
				local char = plr.Character
				local chrp = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if chrp and hum and hum.Health > 30 then
					if (chrp.Position - hrp.Position).Magnitude <= CFG.StalkRange then
						target = plr
						break
					end
				end
			end
		end
		if target then
			NOV.state.lastStalk = now
			pcall(function() stalk:FireServer(target) end)
		end
	end

	--======== STRETCH RES (RenderStepped) ========
	NOV.stretchStep = function()
		if not CFG.StretchRes or not cam then return end
		cam.CFrame = cam.CFrame * CFrame.new(0, 0, 0, 1, 0, 0, 0, CFG.StretchAmount, 0, 0, 0, 1)
	end

	--======== MOONWALK (RenderStepped) ========
	NOV.moonwalkStep = function()
		if not CFG.Moonwalk then return end
		local char = lp.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum then return end
		hum.AutoRotate = false
		local look = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
		local right = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z)
		local lookU = look.Magnitude > 0.001 and look.Unit or look
		local rightU = right.Magnitude > 0.001 and right.Unit or right
		local s = math.sin(tick() * 35)
		local dir = CFrame.Angles(0, math.rad(30 * s), 0) * lookU
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + dir)
		hum:Move(-lookU * 1.2 + rightU * (s * 1.05), false)
	end

	--======== AUTO RUN ========
	NOV.autoRunStep = function()
		if not CFG.AutoRun then return end
		local hum = NOV.hum()
		if not hum then return end
		local look = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
		if look.Magnitude > 0.001 then
			hum:Move(look.Unit, false)
		end
	end

	--======== INFINITY ZOOM ========
	NOV.zoomStep = function()
		if not CFG.InfZoom then return end
		pcall(function()
			lp.CameraMaxZoomDistance = 1e9
			lp.CameraMinZoomDistance = 0
		end)
	end

	--======== BYPASS EXIT GATE ========
	NOV.bypassGate = function(on)
		local map = workspace:FindFirstChild("Map")
		if not map then return end
		local n = 0
		for _, m in ipairs(C.gateList or {}) do
			if m and m.Parent then
				local lg = m:FindFirstChild("LeftGate")
				local rg = m:FindFirstChild("RightGate")
				local gateBox = m:FindFirstChild("Box")
				local lge = m:FindFirstChild("LeftGate-end") or m:FindFirstChild("LeftGate-end2")
				local rge = m:FindFirstChild("RightGate-end") or m:FindFirstChild("RightGate-end2")
				pcall(function()
					if lg then lg.Transparency = on and 1 or 0; lg.CanCollide = not on end
					if rg then rg.Transparency = on and 1 or 0; rg.CanCollide = not on end
					if lge then lge.Transparency = on and 0 or 1 end
					if rge then rge.Transparency = on and 0 or 1 end
					if gateBox then gateBox.CanCollide = not on end
				end)
				n = n + 1
			end
		end
		NOV.msg(string.format("Bypass gate %s (%d model).", on and "ON" or "OFF", n))
	end

	--======== INSTANT TP GATE (getgc + module hook) ========
	NOV.instantGate = function(on)
		NOV.state.instGate = on
		if not on then return end
		local ok = pcall(function()
			if type(getgc) ~= "function" then error("executor tidak punya getgc") end
			for _, v in pairs(getgc(true)) do
				if type(v) == "table" and rawget(v, "gateDuration") and rawget(v, "gateRemote") then
					rawset(v, "gateDuration", 0)
				end
			end
			local mods = ReplicatedStorage:FindFirstChild("Modules")
			local items = mods and mods:FindFirstChild("Items")
			local gateClient = items and items:FindFirstChild("GateClient")
			if gateClient then
				local m = require(gateClient)
				if not NOV.state.gateNew then
					NOV.state.gateNew = m.new
					m.new = function(...)
						local obj = NOV.state.gateNew(...)
						if NOV.state.instGate and type(obj) == "table" then
							pcall(function() obj.gateDuration = 0 end)
						end
						return obj
					end
				end
			end
		end)
		if not ok then
			NOV.msg("Instant TP Gate butuh executor dengan getgc (Xeno/Wave).")
		end
	end

	--======== NEXT KILLER + NEXT MAP ========
	NOV.setupInfoLabels = function()
		if NOV.state.infoGui and NOV.state.infoGui.Parent then return end
		local g = Instance.new("ScreenGui")
		g.Name = "NOVA_Info"
		g.ResetOnSpawn = false
		g.IgnoreGuiInset = true
		g.Parent = NOV.ui.gui
		local function mk(y)
			local l = Instance.new("TextLabel")
			l.Size = UDim2.new(0, 230, 0, 22)
			l.Position = UDim2.new(0.5, 0, 0, y)
			l.AnchorPoint = Vector2.new(0.5, 0)
			l.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
			l.BackgroundTransparency = 0.15
			l.TextColor3 = Color3.fromRGB(220, 220, 230)
			l.Font = Enum.Font.GothamMedium
			l.TextSize = 11
			l.RichText = true
			l.Visible = false
			l.Parent = g
			local uc = Instance.new("UICorner")
			uc.CornerRadius = UDim.new(0, 6)
			uc.Parent = l
			return l
		end
		NOV.state.infoGui = g
		NOV.state.killerLbl = mk(10)
		NOV.state.mapLbl = mk(36)
	end

	NOV.infoStep = function()
		if not (CFG.NextKiller or CFG.NextMap) then
			if NOV.state.killerLbl then NOV.state.killerLbl.Visible = false end
			if NOV.state.mapLbl then NOV.state.mapLbl.Visible = false end
			return
		end
		NOV.setupInfoLabels()
		local kl, ml = NOV.state.killerLbl, NOV.state.mapLbl

		if kl then
			kl.Visible = CFG.NextKiller
			if CFG.NextKiller then
				local list = {}
				for _, p in ipairs(Players:GetPlayers()) do
					table.insert(list, p)
				end
				table.sort(list, function(a, b)
					local aa = a:GetAttribute("AllowKiller") or false
					local bb = b:GetAttribute("AllowKiller") or false
					if aa ~= bb then return aa end
					return (a:GetAttribute("KillerChance") or 0) > (b:GetAttribute("KillerChance") or 0)
				end)
				local p = list[1]
				if p then
					local nm = p == lp and "<font color='#ff5555'>KAMU</font>" or p.Name
					local ch = p:GetAttribute("KillerChance")
					kl.Text = "Next Killer: " .. nm .. (ch and string.format(" <font color='#888888'>(%.0f%%)</font>", ch * 100) or "")
				else
					kl.Text = "Next Killer: <font color='#888888'>-</font>"
				end
			end
		end

		if ml then
			ml.Visible = CFG.NextMap
			if CFG.NextMap then
				local map = workspace:FindFirstChild("Map")
				local name = nil
				if map then
					if map:FindFirstChild("random shakes") or map:FindFirstChild("SCP-173 Room")
						or map:FindFirstChild("SCP-205 Room") then
						name = "Site 68"
					elseif map:FindFirstChild("HooksMeat") then
						name = "BLOODBATH! Club"
					elseif map:FindFirstChild("Gate") and map.Gate:FindFirstChild("vfx") then
						name = "Firelink Shrine"
					elseif map:FindFirstChild("Bldg_Addon_RooftopUnit_A") or map:FindFirstChild("Rooftop") then
						name = "Mercy Hospital Rooftop"
					elseif map:FindFirstChild("White Armored Car") then
						name = "Mount Massive Asylum"
					elseif map:FindFirstChild("Dumbster") then
						name = "The Bay Harbor"
					elseif map:FindFirstChild("water pump") then
						name = "Valdelobos Village"
					elseif map:FindFirstChild("LargeBoulder01") then
						name = "Woodview Cabin"
					end
				end
				ml.Text = "Map: " .. (name and ("<font color='#5fd3ff'>" .. name .. "</font>") or "<font color='#888888'>?</font>")
			end
		end
	end

	--======== CONFIG SAVE / LOAD ========
	local CFG_FOLDER = "NOVA_VD"
	local CFG_FILE = CFG_FOLDER .. "/config.json"

	NOV.saveConfig = function()
		local ok = pcall(function()
			local wf = writefile
			if type(wf) ~= "function" then error("executor tidak punya writefile") end
			if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder(CFG_FOLDER) then
				makefolder(CFG_FOLDER)
			end
			local out = {}
			for k, v in pairs(CFG) do
				if type(v) == "number" or type(v) == "boolean" or type(v) == "string" then
					out[k] = v
				end
			end
			wf(CFG_FILE, HttpService:JSONEncode(out))
		end)
		NOV.msg(ok and ("Config disimpan: " .. CFG_FILE) or "Gagal simpan config (butuh executor dengan writefile).")
	end

	NOV.loadConfig = function()
		local applied = 0
		local ok = pcall(function()
			local rf = readfile
			if type(rf) ~= "function" then error("executor tidak punya readfile") end
			local txt = rf(CFG_FILE)
			if not txt or txt == "" then error("file config kosong") end
			local data = HttpService:JSONDecode(txt)
			for k, v in pairs(data) do
				if CFG[k] ~= nil and type(CFG[k]) == type(v) and k ~= "Keybind" and k ~= "Accent" then
					NOV.setCfg(k, v)
					applied = applied + 1
				end
			end
		end)
		NOV.msg(ok and string.format("Config dimuat: %d field.", applied) or "Gagal load config (belum ada / executor tidak support).")
	end

	NOV.resetConfig = function()
		local defaults = {
			AimSurvivor = false, AimKiller = false, AimShowFov = false, AimWallCheck = false,
			SilentFlash = false, SilentToF = false, SilentFlask = false,
			UnlimitedVault = false, PalletSlide = false, QuickRecovery = false, FlowstateNoCD = false,
			GodMode = false, AntiHook = false, FastBandage = false,
			NoSlowdown = false, InfiniteLunge = false, AutoStalk = false,
			StretchRes = false, Moonwalk = false, AutoRun = false, Crosshair = false,
			NextKiller = false, NextMap = false, BypassGate = false, InstantTPGate = false,
			SpearSilent = false, PerfectLanding = false, AdrenalineRush = false,
			StreamerMode = false, CounterParry = false, InfCorrupt = false, DashLock = false,
			KorlessMorph = false, SkipEndscreen = false,
		}
		for k, v in pairs(defaults) do NOV.setCfg(k, v) end
		NOV.msg("Semua fitur hasil port direset ke OFF.")
	end
end

--===================== [ 9e. PORT LANJUTAN (v2.1) ] ========================
do
	local R = NOV.remotes

	--======== SPEAR BALLISTIC SOLVER (Veil) ========
	-- fn29 versi Aeris: hitung sudut + waktu tempuh dari drag/gravitasi.
	NOV.ballistic = function(speed, gravity, horiz, height)
		local t = math.max(horiz, 0.1)
		local v2 = speed * speed
		local disc = v2 * v2 - gravity * (gravity * t * t + 2 * height * v2)
		if disc < 0 then disc = 0 end
		local s = (v2 - math.sqrt(disc)) / (gravity * t)
		local ang = math.atan(s)
		return ang, t / (speed * math.cos(ang))
	end

	--======== PERFECT LANDING ========
	-- Game set speedboost = 0.625 saat mendarat; kita naikkan jadi 1.4 selama 3 detik.
	NOV.setupPerfectLanding = function(on)
		if NOV.state.plConn then
			NOV.state.plConn:Disconnect()
			NOV.state.plConn = nil
		end
		if not on then return end
		local char = lp.Character
		if not char then return end
		NOV.state.plConn = char:GetAttributeChangedSignal("speedboost"):Connect(function()
			if not CFG.PerfectLanding then return end
			if char:GetAttribute("speedboost") == 0.625 and not NOV.state.plBoost then
				NOV.state.plBoost = true
				local until_ = tick() + 3
				task.spawn(function()
					while tick() < until_ and NOV.alive and CFG.PerfectLanding do
						pcall(function() char:SetAttribute("speedboost", 1.4) end)
						task.wait()
					end
					pcall(function() char:SetAttribute("speedboost", 1) end)
					NOV.state.plBoost = false
				end)
			end
		end)
	end

	--======== ADRENALINE RUSH ========
	-- Saat HP turun ke <= 50 dan masih > 0, speedboost 1.4 selama 5 detik.
	NOV.setupAdrenaline = function(on)
		if NOV.state.arConn then
			NOV.state.arConn:Disconnect()
			NOV.state.arConn = nil
		end
		if not on then return end
		local char = lp.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		local last = hum.Health
		NOV.state.arConn = hum.HealthChanged:Connect(function(h)
			if not CFG.AdrenalineRush then return end
			local prev = last
			last = h
			if h < prev and h <= 50 and h > 0 and not NOV.state.arBoost then
				NOV.state.arBoost = true
				local until_ = tick() + 5
				task.spawn(function()
					while tick() < until_ and NOV.alive and CFG.AdrenalineRush do
						pcall(function() char:SetAttribute("speedboost", 1.4) end)
						task.wait()
					end
					pcall(function() char:SetAttribute("speedboost", 1) end)
					NOV.state.arBoost = false
				end)
			end
		end)
	end

	--======== STREAMER MODE ========
	-- Ganti semua nama pemain di teks GUI game jadi "NOVA".
	NOV.streamerMode = function(on)
		if NOV.state.smConns then
			for _, c in ipairs(NOV.state.smConns) do
				pcall(function() c:Disconnect() end)
			end
		end
		NOV.state.smConns = {}

		local pg = lp:FindFirstChild("PlayerGui")
		if not pg then return end

		local function scan(node)
			if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
				if not node:GetAttribute("NOVA_OrigText") then
					node:SetAttribute("NOVA_OrigText", node.Text)
				end
				local txt = node.Text
				local changed = false
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr ~= lp then
						if string.find(txt, plr.Name, 1, true) then
							txt = string.gsub(txt, plr.Name, CFG.FakeName)
							changed = true
						end
						if plr.DisplayName and plr.DisplayName ~= "" and string.find(txt, plr.DisplayName, 1, true) then
							txt = string.gsub(txt, plr.DisplayName, CFG.FakeName)
							changed = true
						end
					end
				end
				if changed and node.Text ~= txt then
					node.Text = txt
				end
			end
		end

		if not on then
			for _, d in ipairs(pg:GetDescendants()) do
				local orig = d:GetAttribute("NOVA_OrigText")
				if orig then
					pcall(function() d.Text = orig end)
					pcall(function() d:SetAttribute("NOVA_OrigText", nil) end)
				end
				local oi = d:GetAttribute("NOVA_OrigImage")
				if oi then
					pcall(function() d.Image = oi end)
					pcall(function() d:SetAttribute("NOVA_OrigImage", nil) end)
				end
			end
			return
		end

		for _, d in ipairs(pg:GetDescendants()) do
			scan(d)
		end
		table.insert(NOV.state.smConns, pg.DescendantAdded:Connect(function(d)
			task.defer(function()
				if CFG.StreamerMode then scan(d) end
			end)
		end))
		NOV.msg("Streamer mode ON — nama pemain diganti jadi '" .. CFG.FakeName .. "'.")
	end

	--======== COPY AVATAR ========
	NOV.applyAvatarOf = function(plr)
		if not plr then return end
		local char = lp.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then NOV.msg("Kamu belum spawn.") return end
		local ok = pcall(function()
			local desc = Players:GetHumanoidDescriptionFromUserId(plr.UserId)
			hum:ApplyDescription(desc)
		end)
		NOV.msg(ok and ("Avatar dicopy dari " .. plr.Name) or "Gagal copy avatar.")
	end

	NOV.randomAvatar = function()
		local list = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= lp then table.insert(list, p) end
		end
		if #list == 0 then NOV.msg("Tidak ada pemain lain.") return end
		NOV.applyAvatarOf(list[math.random(1, #list)])
	end

	--======== KORLESS MORPH ========
	NOV.korless = function(on)
		local char = lp.Character
		if not char then return end
		if not on then
			pcall(function()
				local m = char:FindFirstChild("KorlessHead")
				if m then m:Destroy() end
				if char:FindFirstChild("Head") then char.Head.Transparency = 0 end
				if char:FindFirstChild("Right Leg") then char["Right Leg"].Transparency = 0 end
			end)
			NOV.msg("Korless morph OFF.")
			return
		end
		local ok = pcall(function()
			char.Head.Transparency = 1
			local face = char.Head:FindFirstChild("face")
			if face then face:Destroy() end
			char["Right Leg"].Transparency = 1
			local mp = Instance.new("MeshPart")
			mp.Name = "KorlessHead"
			mp.Size = Vector3.new(0.85, 0.85, 0.85)
			mp.CanCollide = false
			mp.MeshId = "rbxassetid://902942096"
			mp.TextureID = "rbxassetid://902843398"
			mp.CFrame = char["Right Leg"].CFrame * CFrame.new(0, 0.7, 0)
			mp.Parent = char
			local w = Instance.new("WeldConstraint")
			w.Part0 = char["Right Leg"]
			w.Part1 = mp
			w.Parent = mp
		end)
		NOV.msg(ok and "Korless morph ON." or "Korless gagal (bentuk R15?)")
	end

	--======== COUNTER / ANTI PARRY (killer) ========
	NOV.counterParry = function(on)
		NOV.state.cpOn = on
		if not on or NOV.state.cpThread then return end
		NOV.state.cpThread = task.spawn(function()
			local cpTrack
			while NOV.alive and NOV.state.cpOn do
				local char = lp.Character
				if char and NOV.role(lp) == "Killer" and not cpTrack then
					pcall(function()
						local hum = char:FindFirstChildOfClass("Humanoid")
						local anim = hum and hum:FindFirstChildOfClass("Animator")
						if anim then
							local a = Instance.new("Animation")
							a.AnimationId = "rbxassetid://117042998468241"
							cpTrack = anim:LoadAnimation(a)
						end
					end)
				end
				if cpTrack then
					local hrp = char and char:FindFirstChild("HumanoidRootPart")
					local close = false
					if hrp then
						for _, plr in ipairs(Players:GetPlayers()) do
							if plr ~= lp and not NOV.isKiller(plr) then
								local c2 = plr.Character
								local h2 = c2 and c2:FindFirstChild("HumanoidRootPart")
								if h2 and (hrp.Position - h2.Position).Magnitude <= CFG.CounterParryDist then
									close = true
									break
								end
							end
						end
					end
					if close then
						pcall(function()
							cpTrack:Play()
							cpTrack:AdjustWeight(0)
						end)
						task.wait(0.05)
						pcall(function() cpTrack:Stop() end)
					end
				end
				task.wait(CFG.CounterParryRate)
			end
			NOV.state.cpThread = nil
		end)
	end

	--======== INFINITE CORRUPT (Abysswalker) ========
	NOV.infCorrupt = function(on)
		NOV.state.icOn = on
		if not on or NOV.state.icThread then return end
		NOV.state.icThread = task.spawn(function()
			while NOV.alive and NOV.state.icOn do
				if NOV.role(lp) == "Killer" then
					pcall(function()
						if R.abyssCorrupt then R.abyssCorrupt:FireServer() end
					end)
				end
				task.wait(0.5)
			end
			NOV.state.icThread = nil
		end)
	end

	--======== DASH LOCK -- camera aim-lock ke survivor terdekat ============
	-- Trigger: klik kanan (PC) / keybind V / tombol move2 (mobile) / tombol NOVA.
	-- Efek: kamera ngunci + lerp ke HRP survivor terdekat. Bukan lewat remote,
	-- jadi tidak ada arg yang dikirim ke server -- murni kontrol kamera lokal.
	local DS = { locking = false, target = nil, timer = nil, last = 0 }
	NOV.dashState = DS

	local function dsDowned(char)
		if not char then return true end
		if char:GetAttribute("Knocked") == true then return true end
		if char:GetAttribute("IsHooked") == true then return true end
		local h = char:FindFirstChildOfClass("Humanoid")
		if h and h.Health <= 0 then return true end
		return false
	end

	local function dsClosest()
		local hrp = NOV.hrp()
		if not hrp then return nil end
		local best, bd = nil, math.huge
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= lp and NOV.role(p) == "Survivor" then
				local c = p.Character
				local thrp = c and c:FindFirstChild("HumanoidRootPart")
				if thrp and not dsDowned(c) then
					local d = (thrp.Position - hrp.Position).Magnitude
					if d < bd then bd = d; best = c end
				end
			end
		end
		if best and CFG.DashLockDist > 0 and bd > CFG.DashLockDist then return nil end
		return best, bd
	end

	--======== tombol mobile (tap = lock, tahan-geser = pindah posisi) ========
	local function dsUpdateBtn()
		if not DS.btn then return end
		if DS.locking then
			DS.btn.Text = "DASH LOCK [LOCK]"
			DS.btn.TextColor3 = Color3.fromRGB(180, 255, 180)
		elseif CFG.DashLock then
			DS.btn.Text = "DASH LOCK [ON]"
			DS.btn.TextColor3 = Color3.fromRGB(235, 235, 235)
		else
			DS.btn.Text = "DASH LOCK [OFF]"
			DS.btn.TextColor3 = Color3.fromRGB(150, 150, 150)
		end
	end

	local function dsGuiMake()
		if DS.gui then return end
		local parent = (type(gethui) == "function" and gethui()) or lp:FindFirstChild("PlayerGui")
		if not parent then return end
		local g = Instance.new("ScreenGui")
		g.Name = "NOVA_DashLock"
		g.ResetOnSpawn = false
		g.IgnoreGuiInset = true
		g.DisplayOrder = 500
		g.Parent = parent

		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromOffset(124, 34)
		frame.Position = UDim2.fromScale(0.72, 0.68)
		frame.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
		frame.BackgroundTransparency = 0.1
		frame.BorderSizePixel = 0
		frame.Active = true
		frame.Parent = g
		local c1 = Instance.new("UICorner"); c1.CornerRadius = UDim.new(0, 8); c1.Parent = frame
		local st = Instance.new("UIStroke")
		st.Color = CFG.Accent; st.Thickness = 1.5; st.Transparency = 0.3; st.Parent = frame

		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, 0, 1, 0)
		b.BackgroundTransparency = 1
		b.Text = "DASH LOCK [OFF]"
		b.Font = Enum.Font.GothamBold
		b.TextSize = 11
		b.TextColor3 = Color3.fromRGB(150, 150, 150)
		b.AutoButtonColor = false
		b.Parent = frame
		DS.btn, DS.gui = b, g

		local dragging, dragMoved, canDrag = false, false, false
		local dragStart, startPos, hold = nil, nil, nil
		b.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging, dragMoved, canDrag = true, false, false
				dragStart, startPos = input.Position, frame.Position
				if hold then task.cancel(hold) end
				hold = task.delay(0.18, function() if dragging then canDrag = true end end)
			end
		end)
		b.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1 then
				if hold then task.cancel(hold) end
				if dragging and not dragMoved then NOV.dashTrigger() end
				dragging, dragMoved, canDrag = false, false, false
			end
		end)
		UIS.InputChanged:Connect(function(input)
			if dragging and canDrag and (input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseMovement) then
				local d = input.Position - dragStart
				if not dragMoved and (math.abs(d.X) > 16 or math.abs(d.Y) > 16) then dragMoved = true end
				if dragMoved then
					frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
						startPos.Y.Scale, startPos.Y.Offset + d.Y)
				end
			end
		end)
		table.insert(NOV.cleanups, function() pcall(function() g:Destroy() end) end)
	end

	--======== trigger (dipanggil dari input / tombol) ========
	NOV.dashTrigger = function()
		if not CFG.DashLock then return end
		if tick() - DS.last < 0.2 then return end
		DS.last = tick()
		if NOV.role(lp) ~= "Killer" then
			NOV.msg("Dash Lock cuma jalan saat kamu Killer.")
			return
		end
		local t, d = dsClosest()
		if not t then
			NOV.msg("Dash Lock: tidak ada survivor dalam jangkauan.")
			return
		end
		DS.target, DS.locking = t, true
		if DS.timer then task.cancel(DS.timer) end
		if not CFG.DashLockHold then
			DS.timer = task.delay(math.max(0.1, CFG.DashLockTime), function()
				DS.locking, DS.target, DS.timer = false, nil, nil
				dsUpdateBtn()
			end)
		end
		dsUpdateBtn()
	end

	--======== step per-frame (dipanggil dari RenderStepped) ========
	NOV.dashStep = function()
		if not CFG.DashLock then
			if DS.locking then DS.locking, DS.target = false, nil; dsUpdateBtn() end
			return
		end
		if CFG.DashLockHold and NOV.role(lp) == "Killer"
			and (not DS.locking or not DS.target or not DS.target.Parent) then
			local t = dsClosest()
			if t then DS.target, DS.locking = t, true; dsUpdateBtn() end
		end
		if DS.locking and DS.target then
			local thrp = DS.target.Parent and DS.target:FindFirstChild("HumanoidRootPart")
			if thrp then
				cam.CFrame = cam.CFrame:Lerp(
					CFrame.lookAt(cam.CFrame.Position, thrp.Position),
					math.clamp(CFG.DashLockSmooth, 0.05, 1))
			else
				DS.locking, DS.target = false, nil
				dsUpdateBtn()
			end
		end
	end

	NOV.dashLock = function(on)
		CFG.DashLock = on
		if not on then
			DS.locking, DS.target = false, nil
			if DS.timer then task.cancel(DS.timer); DS.timer = nil end
			if DS.gui then DS.gui.Enabled = false end
			dsUpdateBtn()
			return
		end
		if not NOV.state.dashSetup then
			NOV.state.dashSetup = true
			-- PC: klik kanan + keybind
			NOV.bind(UIS.InputBegan, function(input, gp)
				if gp or not CFG.DashLock then return end
				if input.UserInputType == Enum.UserInputType.MouseButton2 then NOV.dashTrigger() end
				if input.KeyCode == CFG.DashLockKey then NOV.dashTrigger() end
			end)
			-- Mobile: pantau tombol move2 milik game (sama seperti PANDU)
			if UIS.TouchEnabled then
				task.spawn(function()
					local conn, last = nil, nil
					while NOV.alive do
						task.wait(1)
						if CFG.DashLock then
							pcall(function()
								local pg = lp:FindFirstChild("PlayerGui")
								local hm = pg and pg:FindFirstChild("Hidden-mob")
								local ctrl = hm and hm:FindFirstChild("Controls")
								local mv = ctrl and ctrl:FindFirstChild("move2")
								if mv and mv ~= last then
									if conn then conn:Disconnect() end
									last = mv
									conn = mv.InputBegan:Connect(function(i)
										if i.UserInputType == Enum.UserInputType.Touch
											or i.UserInputType == Enum.UserInputType.MouseButton1 then
											NOV.dashTrigger()
										end
									end)
								end
							end)
						end
					end
				end)
			end
		end
		if CFG.DashLockBtn and UIS.TouchEnabled then
			dsGuiMake()
			if DS.gui then DS.gui.Enabled = true end
		elseif DS.gui then
			DS.gui.Enabled = false
		end
		dsUpdateBtn()
		NOV.msg("Dash Lock ON -- klik kanan (PC) / tombol V / tap DASH LOCK buat kunci.")
	end

	--======== MASK GUI -- buka GUI milik game sendiri ========
	NOV.maskGui = function(on)
		local pg = lp:FindFirstChild("PlayerGui")
		if not pg then return end
		local found = false
		for _, d in ipairs(pg:GetDescendants()) do
			local n = string.lower(d.Name)
			if (string.find(n, "mask", 1, true) or string.find(n, "select", 1, true))
				and (d:IsA("ScreenGui") or d:IsA("Frame")) then
				if not d:GetAttribute("NOVA_OrigVisible") then
					d:SetAttribute("NOVA_OrigVisible", d.Visible)
				end
				pcall(function() d.Visible = on and true or (d:GetAttribute("NOVA_OrigVisible") or false) end)
				found = true
			end
		end
		NOV.msg(found and ("Mask GUI " .. (on and "dibuka" or "ditutup")) or "GUI mask game tidak ketemu (kamu bukan The Masked?).")
	end

	--======== INSTANT ESCAPE ========
	NOV.instantEscape = function()
		local hrp = NOV.hrp()
		if not hrp then return end
		local found = nil
		for _, d in ipairs(workspace:GetDescendants()) do
			-- nama part di game memang typo: "fininshline"
			if d:IsA("BasePart") and string.lower(d.Name) == "fininshline" then
				found = d
				break
			end
		end
		if not found then
			NOV.msg("Finish line tidak ketemu.")
			return
		end
		hrp.CFrame = found.CFrame + Vector3.new(0, 5, 0)
		NOV.msg("Instant escape: teleport ke finish line.")
	end

	--======== SKIP ENDSCREEN ========
	NOV.skipEndscreen = function(on)
		NOV.state.skipEnd = on
		if not on or NOV.state.skipThread then return end
		NOV.state.skipThread = task.spawn(function()
			while NOV.alive and NOV.state.skipEnd do
				pcall(function()
					local pg = lp:FindFirstChild("PlayerGui")
					local res = pg and pg:FindFirstChild("Results")
					if res then res:Destroy() end
					local map = workspace:FindFirstChild("Map")
					if map then
						local es = map:FindFirstChild("endscreen", true)
						if es then
							for _, d in ipairs(es:GetDescendants()) do
								if d:IsA("LocalScript") then d.Disabled = true end
							end
							es:Destroy()
						end
					end
				end)
				task.wait(0.5)
			end
			NOV.state.skipThread = nil
		end)
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
		Ambient = Lighting.Ambient,
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
				Lighting.Ambient = origLighting.Ambient
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
			if not cam then return end
			if CFG.CameraFov and CFG.CameraFov > 0 then
				cam.FieldOfView = CFG.CameraFov
			end
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
		line("Carry.SelfUnHookEvent", NOV.remotes.selfUnhook ~= nil, tostring(NOV.remotes.selfUnhook))
		line("Exit.LeverEvent", NOV.remotes.leverEvent ~= nil, tostring(NOV.remotes.leverEvent))
		line("Attacks.BasicAttack", NOV.remotes.basicAttack ~= nil, tostring(NOV.remotes.basicAttack))
		line("Attacks.Lunge", NOV.remotes.lunge ~= nil, tostring(NOV.remotes.lunge))
		line("Collision.Disable", NOV.remotes.colOff ~= nil, tostring(NOV.remotes.colOff))
		line("Mechanics.ChangeAttribute", NOV.remotes.mechAttr ~= nil, tostring(NOV.remotes.mechAttr))
		line("Generator.BreakGenEvent", NOV.remotes.genBreak ~= nil, tostring(NOV.remotes.genBreak))
		line("Healing.SkillCheckResult", NOV.remotes.healResult ~= nil, tostring(NOV.remotes.healResult))

		local char = lp.Character
		local hrp = NOV.hrp()
		line("Character/HRP", char ~= nil and hrp ~= nil, char and char:GetFullName() or "-")
		line("Role", true, NOV.role(lp))
		line("Humanoid", NOV.hum() ~= nil, NOV.hum() and tostring(math.floor(NOV.hum().Health)) or "-")
		line("speedboost attr", char and char:GetAttribute("speedboost") ~= nil, tostring(char and char:GetAttribute("speedboost")))

		local C = NOV.cache
		line("Scan root", true, tostring(C.scanRoot or "belum scan"))
		line("Generators scan", true, string.format("%d model (0 = lobby/map belum load)", #(C.genList or {})))
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
		line("Hook terpasang", true, NOV.state.hooked and "aktif" or "belum (butuh toggle Auto Perfect Skillcheck)")
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
	T.main = U.createTab("Main", "Main")
	T.esp  = U.createTab("ESP", "ESP")
	T.aim  = U.createTab("Aim", "Aim")
	T.auto = U.createTab("Auto", "Auto")
	T.combat = U.createTab("Combat", "Fight")
	T.move = U.createTab("Movement", "Move")
	T.vis  = U.createTab("Visual", "Vis")
	T.tp   = U.createTab("Teleport", "TP")
	T.misc = U.createTab("Misc", "Misc")

	--======== MAIN ========
	U.section(T.main.page, "Preset")
	U.button(T.main.page, "Survivor Preset (Auto Gen + ESP)", function()
		NOV.setCfg("EspPlayers", true)
		NOV.setCfg("EspGens", true)
		NOV.setCfg("EspGates", true)
		NOV.setCfg("AutoRepair", true)
		NOV.setCfg("GenPerfect", true)
		NOV.setCfg("GenFailSafe", true)
		NOV.setCfg("AutoHeal", true)
		NOV.setCfg("AutoSelfUnhook", true)
		NOV.setCfg("AutoParry", true)
		NOV.installHook()
		NOV.msg("Preset Survivor aktif.")
	end)
	U.button(T.main.page, "Killer Preset (Kill Aura + ESP + Speed)", function()
		NOV.setCfg("EspPlayers", true)
		NOV.setCfg("EspGates", true)
		NOV.setCfg("SpeedEnabled", true)
		NOV.setCfg("AntiFlash", true)
		NOV.setCfg("KillAura", true)
		NOV.setCfg("BreakGen", true)
		NOV.setCfg("DashLock", true)
		NOV.dashLock(true)
		NOV.msg("Preset Killer aktif (Dash Lock siap: klik kanan / V).")
	end)
	U.button(T.main.page, "Matikan Semua Fitur", function()
		for k, v in pairs(CFG) do
			if type(v) == "boolean" and not string.find(k, "^Esp") and k ~= "GenFailSafe"
				and k ~= "AutoEquipDagger" and k ~= "AttackFace" and k ~= "SmoothTp"
				and k ~= "ShowStats" and k ~= "EspChams" and k ~= "EspName" and k ~= "EspRole"
				and k ~= "EspDist" and k ~= "EspTool" and k ~= "EspHealth" and k ~= "EspAliveOnly" then
				NOV.setCfg(k, false)
			end
		end
		pcall(NOV.stopRepair)
		NOV.dashLock(false)
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
	U.toggle(T.esp.page, "ESP Pemain", "EspPlayers", function(v)
		CFG.EspPlayers = v
		-- kalau semua sub-option mati, nyalakan set dasar biar ESP-nya kelihatan
		if v and not (CFG.EspChams or CFG.EspName or CFG.EspRole or CFG.EspDist or CFG.EspHealth) then
			NOV.setCfg("EspChams", true)
			NOV.setCfg("EspName", true)
			NOV.setCfg("EspRole", true)
			NOV.setCfg("EspDist", true)
			NOV.setCfg("EspHealth", true)
			NOV.msg("Sub-option ESP dinyalakan otomatis (Chams / Nama / Role / Jarak / HP).")
		end
	end)
	U.toggle(T.esp.page, "Chams (Highlight)", "EspChams", function(v) CFG.EspChams = v end)
	U.toggle(T.esp.page, "Box", "EspBox", function(v) CFG.EspBox = v end)
	U.toggle(T.esp.page, "Nama", "EspName", function(v) CFG.EspName = v end)
	U.toggle(T.esp.page, "Role Tag", "EspRole", function(v) CFG.EspRole = v end)
	U.toggle(T.esp.page, "Jarak", "EspDist", function(v) CFG.EspDist = v end)
	U.toggle(T.esp.page, "Item / Killer", "EspTool", function(v) CFG.EspTool = v end)
	U.toggle(T.esp.page, "HP", "EspHealth", function(v) CFG.EspHealth = v end)
	U.toggle(T.esp.page, "Hanya Hidup", "EspAliveOnly", function(v) CFG.EspAliveOnly = v end)

	U.section(T.esp.page, "Objek Map")
	U.toggle(T.esp.page, "Generator (%)", "EspGens", function(v) CFG.EspGens = v end)
	U.toggle(T.esp.page, "Gate / Exit", "EspGates", function(v) CFG.EspGates = v end)
	U.toggle(T.esp.page, "Hook", "EspHooks", function(v) CFG.EspHooks = v end)
	U.toggle(T.esp.page, "Pallet", "EspPallets", function(v) CFG.EspPallets = v end)
	U.toggle(T.esp.page, "Window / Vault", "EspWindows", function(v) CFG.EspWindows = v end)

	U.section(T.esp.page, "Lain")
	U.slider(T.esp.page, "Jarak Maks ESP", 100, 3000, CFG.EspMaxDist, 0, function(v) CFG.EspMaxDist = v end)
	U.toggle(T.esp.page, "Alarm Killer Dekat", "KillerAlert", function(v) CFG.KillerAlert = v end)
	U.slider(T.esp.page, "Radius Alarm", 20, 300, CFG.AlertDist, 0, function(v) CFG.AlertDist = v end)

	--======== AIM ========
	U.section(T.aim.page, "Aimbot")
	U.toggle(T.aim.page, "Aimbot (saat Survivor)", "AimSurvivor", function(v)
		CFG.AimSurvivor = v
		if v then NOV.msg("Aimbot survivor ON — ngunci killer.") end
	end)
	U.toggle(T.aim.page, "Aimbot (saat Killer)", "AimKiller", function(v)
		CFG.AimKiller = v
		if v then NOV.msg("Aimbot killer ON — ngunci survivor terdekat.") end
	end)
	U.slider(T.aim.page, "FOV Radius (survivor)", 20, 500, CFG.AimRadius, 0, function(v) CFG.AimRadius = v end)
	U.slider(T.aim.page, "Max Distance (survivor)", 30, 1000, CFG.AimMaxDist, 0, function(v) CFG.AimMaxDist = v end)
	U.slider(T.aim.page, "Max Distance (killer)", 5, 60, CFG.AimKillerDist, 0, function(v) CFG.AimKillerDist = v end)
	U.slider(T.aim.page, "Smoothness (0.05-1)", 0.05, 1, CFG.AimSmooth, 2, function(v) CFG.AimSmooth = v end)
	U.slider(T.aim.page, "Predict", 0, 0.1, CFG.AimPredict, 3, function(v) CFG.AimPredict = v end)
	U.toggle(T.aim.page, "Tampilkan FOV Circle", "AimShowFov", function(v) CFG.AimShowFov = v end)
	U.toggle(T.aim.page, "Wall Check", "AimWallCheck", function(v) CFG.AimWallCheck = v end)
	U.label(T.aim.page, "Target part: " .. CFG.AimPart .. " (Torso default)", NOV.ui.colors.dim)

	U.section(T.aim.page, "Silent Aim")
	U.toggle(T.aim.page, "Silent Aim Flashlight", "SilentFlash", function(v) CFG.SilentFlash = v end)
	U.toggle(T.aim.page, "Silent Aim Twist of Fate", "SilentToF", function(v)
		CFG.SilentToF = v
		if v then NOV.installHook() end
	end)
	U.toggle(T.aim.page, "Silent Aim Flask (Cure)", "SilentFlask", function(v)
		CFG.SilentFlask = v
		if v then NOV.installHook() end
	end)
	U.slider(T.aim.page, "Flash Y Offset", -5, 5, CFG.FlashYOffset, 2, function(v) CFG.FlashYOffset = v end)
	U.toggle(T.aim.page, "Silent Veil (spear, balistik)", "SpearSilent", function(v)
		CFG.SpearSilent = v
		if v then NOV.installHook() end
	end)
	U.slider(T.aim.page, "Spear Speed", 30, 400, CFG.SpearSpeed, 0, function(v) CFG.SpearSpeed = v end)
	U.slider(T.aim.page, "Spear Gravity", 10, 300, CFG.SpearGravity, 1, function(v) CFG.SpearGravity = v end)
	U.slider(T.aim.page, "Spear Max Dist", 50, 2000, CFG.SpearMaxDist, 0, function(v) CFG.SpearMaxDist = v end)
	U.slider(T.aim.page, "Spear Lead", 0, 3, CFG.SpearLead, 2, function(v) CFG.SpearLead = v end)
	U.button(T.aim.page, "Crosshair ON/OFF", function()
		NOV.setCfg("Crosshair", not CFG.Crosshair)
		NOV.buildCrosshair()
	end)
	U.slider(T.aim.page, "Crosshair Size", 3, 20, CFG.CrossSize, 0, function(v)
		CFG.CrossSize = v
		NOV.buildCrosshair()
	end)

	--======== AUTO ========
	U.section(T.auto.page, "Generator")
	U.toggle(T.auto.page, "Auto Perfect Skillcheck", "GenPerfect", function(v)
		CFG.GenPerfect = v
		if v then
			NOV.installHook()
			if not CFG.GenFailSafe then
				NOV.msg("Layer 2 (Fail-Safe Remote Hook) masih OFF — nyalakan kalau QTE masih sering gagal.")
			end
		end
	end)
	U.toggle(T.auto.page, "Fail-Safe Remote Hook", "GenFailSafe", function(v)
		CFG.GenFailSafe = v
		if v then NOV.installHook() end
	end)
	U.slider(T.auto.page, "QTE Delay Min", 0.02, 1, CFG.GenDelayMin, 2, function(v) CFG.GenDelayMin = v end)
	U.slider(T.auto.page, "QTE Delay Max", 0.05, 1.5, CFG.GenDelayMax, 2, function(v) CFG.GenDelayMax = v end)
	U.toggle(T.auto.page, "Auto Repair Generator", "AutoRepair", function(v)
		CFG.AutoRepair = v
		if not v then pcall(NOV.stopRepair) end
	end)
	U.toggle(T.auto.page, "Auto Teleport ke Gen", "AutoRepairTp", function(v) CFG.AutoRepairTp = v end)
	U.slider(T.auto.page, "Jarak Repair", 5, 40, CFG.RepairRange, 0, function(v) CFG.RepairRange = v end)
	U.slider(T.auto.page, "Repair Rate (detik)", 0.1, 2, CFG.RepairRate, 2, function(v) CFG.RepairRate = v end)

	U.section(T.auto.page, "Survivor QoL")
	U.toggle(T.auto.page, "Auto Heal", "AutoHeal", function(v) CFG.AutoHeal = v end)
	U.slider(T.auto.page, "Heal di bawah % HP", 0.3, 1, CFG.HealThreshold, 2, function(v) CFG.HealThreshold = v end)
	U.toggle(T.auto.page, "Auto Wiggle (simulasi tombol)", "AutoWiggle", function(v) CFG.AutoWiggle = v end)
	U.toggle(T.auto.page, "Auto Self-Unhook (remote asli)", "AutoSelfUnhook", function(v) CFG.AutoSelfUnhook = v end)
	U.slider(T.auto.page, "Self-Unhook Rate", 0.1, 2, CFG.UnhookRate, 2, function(v) CFG.UnhookRate = v end)
	U.toggle(T.auto.page, "Auto Vault", "AutoVault", function(v) CFG.AutoVault = v end)
	U.toggle(T.auto.page, "Auto Exit Lever", "AutoExit", function(v) CFG.AutoExit = v end)
	U.toggle(T.auto.page, "Anti Fall", "AntiFall", function(v)
		CFG.AntiFall = v
		if v then NOV.installHook() end
	end)

	U.section(T.auto.page, "Killer")
	U.toggle(T.auto.page, "Kill Aura / Auto Attack", "KillAura", function(v)
		CFG.KillAura = v
		if v and NOV.role(lp) ~= "Killer" then NOV.msg("Kamu bukan killer sekarang — aura nunggu jadi killer.") end
	end)
	U.slider(T.auto.page, "Attack Range", 5, 40, CFG.AttackRange, 0, function(v) CFG.AttackRange = v end)
	U.slider(T.auto.page, "Attack Rate (detik)", 0.15, 3, CFG.AttackRate, 2, function(v) CFG.AttackRate = v end)
	U.toggle(T.auto.page, "Auto Hadap Target", "AttackFace", function(v) CFG.AttackFace = v end)
	U.toggle(T.auto.page, "Pakai Lunge (eksperimen)", "AttackLunge", function(v) CFG.AttackLunge = v end)
	U.toggle(T.auto.page, "Auto Break Generator", "BreakGen", function(v) CFG.BreakGen = v end)
	U.slider(T.auto.page, "Break Range", 5, 30, CFG.BreakRange, 0, function(v) CFG.BreakRange = v end)
	U.slider(T.auto.page, "Break Rate (detik)", 0.1, 3, CFG.BreakRate, 2, function(v) CFG.BreakRate = v end)
	U.button(T.auto.page, "Interrupt / Cancel Action", NOV.interruptActions)
	U.button(T.auto.page, "Claim Event Reward (Halloween/Medal/Gift)", NOV.claimEvents)

	U.section(T.auto.page, "Survivor Utility")
	U.toggle(T.auto.page, "Unlimited Vault", "UnlimitedVault", function(v) NOV.unlimitedVault(v) end)
	U.toggle(T.auto.page, "Auto Pallet Slide", "PalletSlide", function(v) CFG.PalletSlide = v end)
	U.toggle(T.auto.page, "Quick Recovery (vault boost)", "QuickRecovery", function(v) CFG.QuickRecovery = v end)
	U.toggle(T.auto.page, "Flowstate No CD", "FlowstateNoCD", function(v) CFG.FlowstateNoCD = v end)
	U.toggle(T.auto.page, "Anti Hook (lepas dari gendongan)", "AntiHook", function(v) CFG.AntiHook = v end)
	U.slider(T.auto.page, "Anti Hook Offset Y", -1000, 0, CFG.AntiHookY, 0, function(v) CFG.AntiHookY = v end)
	U.slider(T.auto.page, "Anti Hook Hz", 5, 60, CFG.AntiHookHz, 0, function(v) CFG.AntiHookHz = v end)
	U.toggle(T.auto.page, "Fast Bandage", "FastBandage", function(v) CFG.FastBandage = v end)
	U.button(T.auto.page, "Drop All Pallets (map)", NOV.dropAllPallets)

	U.section(T.auto.page, "Killer Utility")
	U.toggle(T.auto.page, "No Slowdown", "NoSlowdown", function(v) CFG.NoSlowdown = v end)
	U.toggle(T.auto.page, "Infinite Lunge", "InfiniteLunge", function(v) CFG.InfiniteLunge = v end)
	U.slider(T.auto.page, "Lunge Boost Value", 1, 999, CFG.LungeValue, 0, function(v) CFG.LungeValue = v end)
	U.toggle(T.auto.page, "Auto Stalk", "AutoStalk", function(v) CFG.AutoStalk = v end)
	U.slider(T.auto.page, "Stalk Range", 20, 400, CFG.StalkRange, 0, function(v) CFG.StalkRange = v end)
	U.toggle(T.auto.page, "God Mode (isi HP terus)", "GodMode", function(v) CFG.GodMode = v end)
	U.toggle(T.auto.page, "Invisible (offset look)", "Invisible", function(v)
		CFG.Invisible = v
		if v then NOV.installHook() end
	end)

	U.section(T.auto.page, "Fake Perks")
	U.toggle(T.auto.page, "Perfect Landing", "PerfectLanding", function(v) NOV.setupPerfectLanding(v) end)
	U.toggle(T.auto.page, "Adrenaline Rush", "AdrenalineRush", function(v) NOV.setupAdrenaline(v) end)

	U.section(T.auto.page, "Killer Ability")
	U.toggle(T.auto.page, "Anti Parry / Counter Parry", "CounterParry", function(v) NOV.counterParry(v) end)
	U.slider(T.auto.page, "Counter Parry Distance", 3, 60, CFG.CounterParryDist, 0, function(v) CFG.CounterParryDist = v end)
	U.slider(T.auto.page, "Counter Parry Rate", 0.1, 2, CFG.CounterParryRate, 2, function(v) CFG.CounterParryRate = v end)
	U.toggle(T.auto.page, "Infinite Corrupt (Abysswalker)", "InfCorrupt", function(v) NOV.infCorrupt(v) end)
	U.toggle(T.auto.page, "Dash Lock (camera lock)", "DashLock", function(v) NOV.dashLock(v) end)
	U.button(T.auto.page, "Dash Lock Sekarang (manual)", function() NOV.dashTrigger() end)
	U.slider(T.auto.page, "Dash Lock Range (0 = tanpa batas)", 0, 800, CFG.DashLockDist, 0, function(v) CFG.DashLockDist = v end)
	U.slider(T.auto.page, "Dash Lock Durasi (detik)", 0.2, 10, CFG.DashLockTime, 1, function(v) CFG.DashLockTime = v end)
	U.slider(T.auto.page, "Dash Lock Smooth", 0.05, 1, CFG.DashLockSmooth, 2, function(v) CFG.DashLockSmooth = v end)
	U.toggle(T.auto.page, "Dash Lock Hold (ngunci terus)", "DashLockHold", function(v) CFG.DashLockHold = v end)
	U.toggle(T.auto.page, "Dash Lock Tombol Mobile", "DashLockBtn", function(v) CFG.DashLockBtn = v end)
	U.button(T.auto.page, "Mask GUI (buka/tutup)", function() NOV.maskGui(true) end)
	U.button(T.auto.page, "Mask GUI (tutup)", function() NOV.maskGui(false) end)
	U.button(T.auto.page, "Instant Escape", NOV.instantEscape)

	U.section(T.auto.page, "Status Generator")
	local genStatus = U.label(T.auto.page, "tekan Scan Ulang Map")
	NOV.ui.genStatus = genStatus

	--======== COMBAT ========
	U.section(T.combat.page, "Parry")
	U.toggle(T.combat.page, "Auto Parry", "AutoParry", function(v) CFG.AutoParry = v end)
	U.toggle(T.combat.page, "Auto Equip Dagger", "AutoEquipDagger", function(v) CFG.AutoEquipDagger = v end)
	U.slider(T.combat.page, "Parry Range", 5, 60, CFG.ParryRange, 0, function(v) CFG.ParryRange = v end)
	U.slider(T.combat.page, "Parry Cooldown", 0.2, 5, CFG.ParryCooldown, 2, function(v) CFG.ParryCooldown = v end)
	U.button(T.combat.page, "Parry Sekarang", function()
		NOV.state.parryCD = false
		NOV.parry()
		NOV.msg("Parry manual dikirim.")
	end)

	--======== MOVEMENT ========
	U.section(T.move.page, "Kecepatan")
	U.toggle(T.move.page, "Speed Boost", "SpeedEnabled", function(v) CFG.SpeedEnabled = v end)
	U.slider(T.move.page, "WalkSpeed", 16, 120, CFG.SpeedValue, 0, function(v)
		CFG.SpeedValue = v
		if CFG.SpeedEnabled then NOV.setSpeed(v) end
	end)
	U.section(T.move.page, "Terbang & Noclip")
	U.toggle(T.move.page, "Fly", "Fly", function(v)
		CFG.Fly = v
		NOV.flyToggle(v)
		NOV.msg(v and "Fly ON (WASD + Space/Shift)" or "Fly OFF")
	end)
	U.slider(T.move.page, "Fly Speed", 20, 300, CFG.FlySpeed, 0, function(v) CFG.FlySpeed = v end)
	U.toggle(T.move.page, "Noclip (lokal)", "Noclip", function(v) CFG.Noclip = v end)
	U.toggle(T.move.page, "Real Noclip (collision server)", "RealNoclip", function(v)
		CFG.RealNoclip = v
		NOV.realNoclip(v)
	end)
	U.toggle(T.move.page, "Infinite Jump", "InfJump", function(v) CFG.InfJump = v end)
	U.slider(T.move.page, "Gravity", 0, 400, CFG.Gravity, 0, function(v)
		CFG.Gravity = v
		pcall(function() workspace.Gravity = v end)
	end)
	U.section(T.move.page, "Lain")
	U.toggle(T.move.page, "Anti AFK", "AntiAfk", function(v) CFG.AntiAfk = v end)
	U.toggle(T.move.page, "Auto Run (selalu lari)", "AutoRun", function(v) CFG.AutoRun = v end)
	U.toggle(T.move.page, "Moonwalk", "Moonwalk", function(v) CFG.Moonwalk = v end)
	U.toggle(T.move.page, "Stretch Res", "StretchRes", function(v) CFG.StretchRes = v end)
	U.slider(T.move.page, "Stretch Amount", 0.3, 1.5, CFG.StretchAmount, 2, function(v) CFG.StretchAmount = v end)

	--======== VISUAL ========
	U.toggle(T.vis.page, "Fullbright", "Fullbright", function(v) CFG.Fullbright = v; NOV.applyVisual() end)
	U.toggle(T.vis.page, "No Fog", "NoFog", function(v) CFG.NoFog = v; NOV.applyVisual() end)
	U.toggle(T.vis.page, "Anti Flash / Blind", "AntiFlash", function(v)
		CFG.AntiFlash = v
		if v then NOV.installHook() end
	end)
	U.toggle(T.vis.page, "Self Highlight", "SelfHighlight", function(v)
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
	U.toggle(T.vis.page, "Zoom Unlock", "InfZoom", function(v)
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
	U.toggle(T.tp.page, "Smooth Teleport", "SmoothTp", function(v) CFG.SmoothTp = v end)
	U.slider(T.tp.page, "Durasi TP", 0.05, 1, CFG.SmoothTpTime, 2, function(v) CFG.SmoothTpTime = v end)

	--======== MISC ========
	U.section(T.misc.page, "Diagnostik")
	U.toggle(T.misc.page, "Remote Log ke Console", "RemoteLog", function(v)
		CFG.RemoteLog = v
		if v then NOV.remoteLog(true) end
	end)
	U.button(T.misc.page, "Dump Remote Log (clipboard)", function()
		local text = table.concat(NOV.state.logLines or {}, "\n")
		pcall(function() setclipboard(text) end)
		NOV.msg(string.format("%d baris log dicopy.", #(NOV.state.logLines or {})))
	end)
	U.section(T.misc.page, "Probe (eksperimen)")
	U.button(T.misc.page, "Probe ChangeAttribute speedboost=1.6", function()
		NOV.probeAttr("speedboost", 1.6)
	end)
	U.button(T.misc.page, "Probe ChangeAttribute speedboost=6", function()
		NOV.probeAttr("speedboost", 6)
	end)

	U.section(T.misc.page, "Info Overlay (port)")
	U.toggle(T.misc.page, "Next Killer Display", "NextKiller", function(v) CFG.NextKiller = v end)
	U.toggle(T.misc.page, "Next Map Display", "NextMap", function(v) CFG.NextMap = v end)

	U.section(T.misc.page, "Gate")
	U.toggle(T.misc.page, "Bypass Exit Gate", "BypassGate", function(v)
		CFG.BypassGate = v
		NOV.bypassGate(v)
	end)
	U.toggle(T.misc.page, "Instant TP Gate (getgc)", "InstantTPGate", function(v)
		CFG.InstantTPGate = v
		NOV.instantGate(v)
	end)

	U.section(T.misc.page, "Cosmetic / QoL")
	U.toggle(T.misc.page, "Streamer Mode (sensor nama)", "StreamerMode", function(v) NOV.streamerMode(v) end)
	U.toggle(T.misc.page, "Skip Endscreen", "SkipEndscreen", function(v) NOV.skipEndscreen(v) end)
	U.toggle(T.misc.page, "Korless Morph", "KorlessMorph", function(v) NOV.korless(v) end)
	U.button(T.misc.page, "Copy Avatar (pemain terdekat)", function()
		local hrp = NOV.hrp()
		local best, bd
		if hrp then
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= lp and p.Character then
					local h = p.Character:FindFirstChild("HumanoidRootPart")
					if h then
						local d = (h.Position - hrp.Position).Magnitude
						if not bd or d < bd then bd = d; best = p end
					end
				end
			end
		end
		NOV.applyAvatarOf(best)
	end)
	U.button(T.misc.page, "Copy Avatar (random)", NOV.randomAvatar)
	U.button(T.misc.page, "Reset Avatar Sendiri", function()
		NOV.applyAvatarOf(lp)
	end)

	U.section(T.misc.page, "Config")
	U.button(T.misc.page, "Save Config (NOVA_VD/config.json)", NOV.saveConfig)
	U.button(T.misc.page, "Load Config", NOV.loadConfig)
	U.button(T.misc.page, "Reset Semua Fitur Port", NOV.resetConfig)
	U.toggle(T.misc.page, "Status Overlay", "ShowStats", function(v) CFG.ShowStats = v end)
	U.section(T.misc.page, "Remote Terdeteksi")
	local rlbl = U.label(T.misc.page, NOV.remotes.list())
	NOV.ui.remoteLbl = rlbl
	U.button(T.misc.page, "Re-resolve Remote", function()
		NOV.remotes.resolve()
		if NOV.ui.remoteLbl then NOV.ui.remoteLbl.Text = NOV.remotes.list() end
		NOV.msg("Remote di-resolve ulang.")
	end)
	U.section(T.misc.page, "Info")
	U.label(T.misc.page, "NOVA VD v2.2 · engine UI sendiri (tanpa Rayfield)\n"
		.. "Place: " .. tostring(game.PlaceId) .. "\n"
		.. "Hotkey: " .. tostring(CFG.Keybind):gsub("Enum.KeyCode.", "") .. " untuk show/hide\n"
		.. "Kalau window ketutup di HP: tekan tombol NOVA di kiri atas.", NOV.ui.colors.dim)

	-- terapkan layout setelah semua tab jadi (biar tidak ada window kebesaran)
	pcall(NOV.ui.applyResponsive)
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
		-- idle guard: kalau semua kategori ESP OFF, tidak ada kerja sama sekali
		if not (CFG.EspPlayers or CFG.EspGens or CFG.EspGates or CFG.EspHooks
			or CFG.EspPallets or CFG.EspWindows) then
			if next(NOV.esp.pool) ~= nil then NOV.esp.clear() end
			return
		end
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

	NOV.bind(RunService.RenderStepped, function()
		if not NOV.alive then return end
		pcall(NOV.aimStep)
		pcall(NOV.stretchStep)
		pcall(NOV.moonwalkStep)
		pcall(NOV.dashStep)
	end)

	NOV.bind(RunService.Heartbeat, function(dt)
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
			pcall(NOV.autoSelfUnhook)
			pcall(NOV.killAura)
			pcall(NOV.breakGen)
			if CFG.RealNoclip and now - (NOV.state.lastCol or 0) > 2 then
				NOV.state.lastCol = now
				pcall(NOV.realNoclip, true)
			end
			pcall(NOV.killerUtilStep)
			pcall(NOV.quickRecoveryStep)
			pcall(NOV.fastBandageStep)
			pcall(NOV.autoStalkStep)
			pcall(NOV.autoRunStep)
			pcall(NOV.zoomStep)
			pcall(NOV.antiHookStep, dt)
			if now - (NOV.state.lastVault or 0) > 0.2 then
				NOV.state.lastVault = now
				pcall(NOV.autoVault)
				pcall(NOV.autoExitLever)
				pcall(NOV.palletStep)
				pcall(NOV.infoStep)
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
			if CFG.UnlimitedVault then
				task.wait(0.5)
				NOV.unlimitedVault(true)
			end
			if CFG.InfiniteLunge then
				pcall(function() char:SetAttribute("lungeboost", CFG.LungeValue) end)
			end
			if CFG.GodMode then
				local h = char:FindFirstChildOfClass("Humanoid")
				if h then h.Health = h.MaxHealth end
			end
			if CFG.PerfectLanding then NOV.setupPerfectLanding(true) end
			if CFG.AdrenalineRush then
				task.wait(0.3)
				NOV.setupAdrenaline(true)
			end
			if CFG.KorlessMorph then
				task.wait(0.5)
				NOV.korless(true)
			end
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
	-- visual & FOV sengaja TIDAK diterapkan saat load (semua fitur default OFF,
	-- jadi script tidak mengubah apa pun sampai kamu menyalakan togglenya)
	NOV.ui.setStatus(string.format("remote: %d", NOV.remotes.count()))
	NOV.ui.notify("NOVA VD v2.2 loaded", 4)
	task.wait(0.4)
	NOV.ui.notify("Hotkey " .. tostring(CFG.Keybind):gsub("Enum.KeyCode.", "") .. " · Self Test di tab Main", 4)
end)

print("[NOVA VD] v2.2 loaded. Remote terdeteksi: " .. tostring(NOV.remotes.count()))
