Tentu, nama script-nya sudah saya ubah dari Dark Hub menjadi NYB Hub v1.0. Semua referensi nama, judul menu, notifikasi, hingga folder visualizer-nya juga sudah disesuaikan.
Berikut adalah script lengkap yang siap Anda salin dan jalankan di executor Delta:
-- NYB Hub v1.0 - Blade Ball AutoParry
-- In v1.1 we will add Sword Changer

print("[NYB Hub v1.0]  Loaded! PlaceId: " .. game.PlaceId)

-- === LOAD RAYFIELD ===
local Rayfield
local success, err = pcall(function()
    Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield", true))()
end)
if not success or not Rayfield then
    local success2, err2 = pcall(function()
        Rayfield = loadstring(game:HttpGet("https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua", true))()
    end)
    if not success2 or not Rayfield then
        Rayfield = {
            CreateWindow = function() return {
                CreateTab = function() return {
                    CreateSection = function() end,
                    CreateToggle = function() end,
                    CreateSlider = function() end,
                    CreateLabel = function() return {Set = function() end} end,
                    CreateButton = function() end,
                    CreateKeybind = function() end,
                } end
            } end,
            Notify = function(_, t) warn("[Notify] " .. tostring(t.Title) .. ": " .. tostring(t.Content)) end,
        }
        warn("[NYB Hub] Running without GUI!")
    end
end
print("[NYB Hub v1.0]  Rayfield loaded!")

-- === SERVICES ===
local RunService          = game:GetService("RunService")
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Player              = Players.LocalPlayer

-- === REMOTE ===
local ParryRemote = nil
pcall(function()
    ParryRemote = ReplicatedStorage:WaitForChild("Remotes", 5):WaitForChild("ParryButtonPress", 5)
end)

-- === CONFIG ===
local AUTO_PARRY_ENABLED    = false
local AUTO_SPAM_ENABLED     = false
local VISUALIZER_ENABLED    = true
local TIME_TO_IMPACT        = 0.55
local SPAM_INTERVAL         = 0.1
local PARRY_COOLDOWN        = 0.4
local CLASH_SPEED_THRESHOLD = 150
local CLASH_TTI_THRESHOLD   = 0.8
local MIN_CIRCLE_RADIUS     = 5
local MAX_CIRCLE_RADIUS     = 25
local MIN_BALL_SPEED        = 0
local MAX_BALL_SPEED        = 400
local parryCount            = 0
local spamCount             = 0
local Parried               = false
local Connection            = nil
local lastParryTime         = 0
local currentCircleRadius   = 8

-- === SPAM STATE ===
local spamTimer             = 0
local spamLabel_ref         = nil
local spamStatusLabel_ref   = nil
local spamHeartbeat         = nil

-- ================================
-- === SPAM FUNCTIONS
-- ================================

local function startSpam()
    if spamHeartbeat then return end
    spamTimer = 0
    spamHeartbeat = RunService.Heartbeat:Connect(function(dt)
        if not AUTO_SPAM_ENABLED then
            spamHeartbeat:Disconnect()
            spamHeartbeat = nil
            return
        end
        spamTimer = spamTimer + dt
        if spamTimer >= SPAM_INTERVAL then
            spamTimer = 0
            if ParryRemote then
                ParryRemote:FireServer()
            else
                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
            end
            spamCount = spamCount + 1
            if spamLabel_ref then
                spamLabel_ref:Set("Spam Count: " .. spamCount)
            end
        end
    end)
end

local function stopSpam()
    AUTO_SPAM_ENABLED = false
    if spamHeartbeat then
        spamHeartbeat:Disconnect()
        spamHeartbeat = nil
    end
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    end)
    if spamStatusLabel_ref then
        spamStatusLabel_ref:Set("Spam:  Stopped")
    end
end

-- ================================
-- === DYNAMIC CIRCLE VISUALIZER
-- ================================

local visualizerParts = {}

local function createCircleVisualizer()
    -- Clean up old parts
    for _, p in ipairs(visualizerParts) do
        pcall(function() p:Destroy() end)
    end
    visualizerParts = {}

    local SEGMENTS  = 64
    local THICKNESS = 0.3
    local HEIGHT    = 0.5

    local folder = workspace:FindFirstChild("NYBHubVisualizer")
    if folder then folder:Destroy() end
    folder = Instance.new("Folder")
    folder.Name   = "NYBHubVisualizer"
    folder.Parent = workspace

    for i = 1, SEGMENTS do
        local p = Instance.new("Part")
        p.Name         = "VisualizerSegment"
        p.Anchored     = true
        p.CanCollide   = false
        p.CanTouch     = false
        p.CastShadow   = false
        p.Material     = Enum.Material.Neon
        p.Color        = Color3.fromRGB(255, 30, 30)
        p.Transparency = 1
        p.Size         = Vector3.new(1, HEIGHT, THICKNESS)
        p.Parent       = folder
        visualizerParts[i] = p
    end
end

createCircleVisualizer()

local function updateVisualizer(rootPos, radius)
    if not VISUALIZER_ENABLED then
        for _, p in ipairs(visualizerParts) do
            pcall(function() p.Transparency = 1 end)
        end
        return
    end

    local Y_OFFSET = -2.5
    local SEGMENTS = #visualizerParts

    if SEGMENTS == 0 then
        createCircleVisualizer()
        SEGMENTS = #visualizerParts
        if SEGMENTS == 0 then return end
    end

    if not visualizerParts[1] or not visualizerParts[1].Parent then
        createCircleVisualizer()
        SEGMENTS = #visualizerParts
        if SEGMENTS == 0 then return end
    end

    local segmentWidth = 2 * radius * math.sin(math.pi / SEGMENTS)

    local speedRatio = math.clamp(
        (radius - MIN_CIRCLE_RADIUS) / (MAX_CIRCLE_RADIUS - MIN_CIRCLE_RADIUS),
        0, 1
    )
    local circleColor
    if speedRatio < 0.5 then
        circleColor = Color3.fromRGB(
            math.floor(255 * (speedRatio * 2)),
            255,
            0
        )
    else
        circleColor = Color3.fromRGB(
            255,
            math.floor(255 * (1 - (speedRatio - 0.5) * 2)),
            0
        )
    end

    for i, p in ipairs(visualizerParts) do
        pcall(function()
            local angle = ((i - 0.5) / SEGMENTS) * (2 * math.pi)
            p.Size  = Vector3.new(segmentWidth, 0.5, 0.3)
            p.Color = circleColor
            p.CFrame = CFrame.new(
                rootPos.X + radius * math.cos(angle),
                rootPos.Y + Y_OFFSET,
                rootPos.Z + radius * math.sin(angle)
            ) * CFrame.Angles(0, -angle + math.pi / 2, 0)
            p.Transparency = 0.3
        end)
    end
end

local function hideVisualizer()
    for _, p in ipairs(visualizerParts) do
        pcall(function() p.Transparency = 1 end)
    end
end

local function getDynamicRadius(speed)
    local ratio = math.clamp(
        (speed - MIN_BALL_SPEED) / (MAX_BALL_SPEED - MIN_BALL_SPEED),
        0, 1
    )
    return MIN_CIRCLE_RADIUS + (MAX_CIRCLE_RADIUS - MIN_CIRCLE_RADIUS) * ratio
end

-- ===========================
-- === BALL FUNCTIONS ===
-- ===========================

local function GetBall()
    local folder = workspace:FindFirstChild("Balls")
    if not folder then return nil end
    for _, Ball in ipairs(folder:GetChildren()) do
        if Ball:IsA("BasePart") and Ball:GetAttribute("realBall") then
            return Ball
        end
    end
end

local function ResetConnection()
    if Connection then Connection:Disconnect() Connection = nil end
end

local ballsFolder = workspace:WaitForChild("Balls", 10)
if ballsFolder then
    ballsFolder.ChildAdded:Connect(function()
        task.wait(0.1)

        if #visualizerParts == 0 or not visualizerParts[1] or not visualizerParts[1].Parent then
            createCircleVisualizer()
        end

        local Ball = GetBall()
        if not Ball then return end
        ResetConnection()
        Connection = Ball:GetAttributeChangedSignal("target"):Connect(function()
            local now = tick()
            if now - lastParryTime >= PARRY_COOLDOWN then
                Parried = false
            end
        end)
    end)
end

workspace.DescendantRemoving:Connect(function(obj)
    if obj.Name == "NYBHubVisualizer" then
        task.wait(0.1)
        createCircleVisualizer()
    end
end)

local existingBall = GetBall()
if existingBall then
    Connection = existingBall:GetAttributeChangedSignal("target"):Connect(function()
        local now = tick()
        if now - lastParryTime >= PARRY_COOLDOWN then
            Parried = false
        end
    end)
end

-- === PARRY FUNCTION ===
local function doParry()
    local now = tick()

    local ball = GetBall()
    local isClashing = false

    if ball then
        local zoomies = ball:FindFirstChild("zoomies")
        if zoomies then
            local speed = zoomies.VectorVelocity.Magnitude
            isClashing = speed > CLASH_SPEED_THRESHOLD
        end
    end

    local effectiveCooldown = isClashing and 0.15 or PARRY_COOLDOWN
    if now - lastParryTime < effectiveCooldown then return end

    lastParryTime = now

    if ParryRemote then
        ParryRemote:FireServer()
    else
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
    end
    Parried = true
    parryCount = parryCount + 1
end

Player.CharacterAdded:Connect(function()
    hideVisualizer()
    task.wait(0.5)
    createCircleVisualizer()
    stopSpam()
    Parried = false
    lastParryTime = 0
end)

-- ========================
-- === RAYFIELD GUI ===
-- ========================

local Window = Rayfield:CreateWindow({
    Name = "NYB Hub v1.0",
    Icon = 0,
    LoadingTitle = "NYB Hub v1.0",
    LoadingSubtitle = "Blade Ball | v1.0 | PlaceId: " .. game.PlaceId,
    Theme = "Default",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings = false,
    ConfigurationSaving = {
        Enabled = false,
        FolderName = "NYBHub",
        FileName = "Config"
    },
    KeySystem = false,
})

-- ===========================
-- === TAB 1: AUTO PARRY ===
-- ===========================

local MainTab = Window:CreateTab(" Auto Parry", nil)

MainTab:CreateSection("Settings")

MainTab:CreateToggle({
    Name = "Auto Parry",
    CurrentValue = false,
    Flag = "AutoParryToggle",
    Callback = function(v)
        AUTO_PARRY_ENABLED = v
        Rayfield:Notify({
            Title = "NYB Hub",
            Content = v and " Auto Parry ENABLED" or " Auto Parry DISABLED",
            Duration = 2,
        })
    end,
})

MainTab:CreateToggle({
    Name = "Circle Visualizer",
    CurrentValue = true,
    Flag = "VisualizerToggle",
    Callback = function(v)
        VISUALIZER_ENABLED = v
        if not v then hideVisualizer() end
        Rayfield:Notify({
            Title = "NYB Hub",
            Content = v and " Visualizer ON" or " Visualizer OFF",
            Duration = 2,
        })
    end,
})

MainTab:CreateSlider({
    Name = "Time To Impact Threshold",
    Range = {0.1, 2.0},
    Increment = 0.05,
    Suffix = "s",
    CurrentValue = TIME_TO_IMPACT,
    Flag = "TimeToImpact",
    Callback = function(v) TIME_TO_IMPACT = v end,
})

MainTab:CreateSlider({
    Name = "Parry Cooldown",
    Range = {0.1, 2.0},
    Increment = 0.1,
    Suffix = "s",
    CurrentValue = PARRY_COOLDOWN,
    Flag = "ParryCooldown",
    Callback = function(v) PARRY_COOLDOWN = v end,
})

MainTab:CreateSlider({
    Name = "Clash Speed Threshold",
    Range = {50, 500},
    Increment = 10,
    Suffix = " speed",
    CurrentValue = CLASH_SPEED_THRESHOLD,
    Flag = "ClashThreshold",
    Callback = function(v) CLASH_SPEED_THRESHOLD = v end,
})

MainTab:CreateSection("Dynamic Circle Settings")

MainTab:CreateSlider({
    Name = "Min Circle Radius",
    Range = {3, 20},
    Increment = 1,
    Suffix = " studs",
    CurrentValue = MIN_CIRCLE_RADIUS,
    Flag = "MinRadius",
    Callback = function(v) MIN_CIRCLE_RADIUS = v end,
})

MainTab:CreateSlider({
    Name = "Max Circle Radius",
    Range = {10, 60},
    Increment = 1,
    Suffix = " studs",
    CurrentValue = MAX_CIRCLE_RADIUS,
    Flag = "MaxRadius",
    Callback = function(v) MAX_CIRCLE_RADIUS = v end,
})

MainTab:CreateSlider({
    Name = "Max Ball Speed Reference",
    Range = {100, 1000},
    Increment = 50,
    Suffix = " speed",
    CurrentValue = MAX_BALL_SPEED,
    Flag = "MaxBallSpeed",
    Callback = function(v) MAX_BALL_SPEED = v end,
})

MainTab:CreateSection("Live Stats")

local parryLabel  = MainTab:CreateLabel("Total Parries: 0")
local statusLabel = MainTab:CreateLabel("Status:  Disabled")
local ballLabel   = MainTab:CreateLabel("Ball: Waiting...")
local targetLabel = MainTab:CreateLabel("Target: None")
local ttiLabel    = MainTab:CreateLabel("TTI: --")
local speedLabel  = MainTab:CreateLabel("Ball Speed: --")
local radiusLabel = MainTab:CreateLabel("Circle Radius: --")
local jumpLabel   = MainTab:CreateLabel("Jump State: --")
local remoteLabel = MainTab:CreateLabel("Remote: " .. (ParryRemote and " Found" or " Fallback"))

MainTab:CreateButton({
    Name = "Reset Parry Count",
    Callback = function()
        parryCount = 0
        parryLabel:Set("Total Parries: 0")
    end,
})

-- ===========================
-- === TAB 2: AUTO SPAM ===
-- ===========================

local SpamTab = Window:CreateTab(" Auto Spam", nil)

SpamTab:CreateSection("Settings")

local spamLabel = SpamTab:CreateLabel("Spam Count: 0")
spamLabel_ref   = spamLabel

local spamStatusLabel = SpamTab:CreateLabel("Spam:  Stopped")
spamStatusLabel_ref   = spamStatusLabel

SpamTab:CreateToggle({
    Name = "Auto Spam",
    CurrentValue = false,
    Flag = "AutoSpamToggle",
    Callback = function(v)
        AUTO_SPAM_ENABLED = v
        if v then
            startSpam()
            spamStatusLabel:Set("Spam:  Running")
        else
            stopSpam()
        end
        Rayfield:Notify({
            Title = "NYB Hub",
            Content = v and " Spam ENABLED" or " Spam DISABLED",
            Duration = 2,
        })
    end,
})

SpamTab:CreateSlider({
    Name = "Spam Interval",
    Range = {0.05, 1.0},
    Increment = 0.05,
    Suffix = "s",
    CurrentValue = SPAM_INTERVAL,
    Flag = "SpamInterval",
    Callback = function(v)
        SPAM_INTERVAL = v
        if AUTO_SPAM_ENABLED then
            stopSpam()
            AUTO_SPAM_ENABLED = true
            startSpam()
            spamStatusLabel:Set("Spam:  Running")
        end
    end,
})

SpamTab:CreateSection("Controls")

SpamTab:CreateButton({
    Name = " Force Stop Spam",
    Callback = function()
        stopSpam()
        Rayfield:Notify({
            Title = "NYB Hub",
            Content = " Spam force stopped!",
            Duration = 2,
        })
    end,
})

SpamTab:CreateButton({
    Name = "Reset Spam Count",
    Callback = function()
        spamCount = 0
        spamLabel:Set("Spam Count: 0")
    end,
})

SpamTab:CreateSection("Info")
SpamTab:CreateLabel("Uses FireServer - no mouse stuck")
SpamTab:CreateLabel("Stops instantly when disabled")
SpamTab:CreateLabel("0.05s = max speed")
SpamTab:CreateLabel("Circle grows when ball is fast")

-- ===========================
-- === TAB 3: KEYBINDS ===
-- ===========================

local KBTab = Window:CreateTab(" Keybinds", nil)
KBTab:CreateSection("Custom Keybinds")

KBTab:CreateKeybind({
    Name = "Toggle Auto Parry",
    CurrentKeybind = "P",
    HoldToInteract = false,
    Flag = "ParryKey",
    Callback = function()
        AUTO_PARRY_ENABLED = not AUTO_PARRY_ENABLED
        Rayfield:Notify({
            Title = "NYB Hub",
            Content = AUTO_PARRY_ENABLED and " Auto Parry ENABLED" or " Auto Parry DISABLED",
            Duration = 2,
        })
    end,
})

KBTab:CreateKeybind({
    Name = "Toggle Auto Spam",
    CurrentKeybind = "B",
    HoldToInteract = false,
    Flag = "SpamKey",
    Callback = function()
        AUTO_SPAM_ENABLED = not AUTO_SPAM_ENABLED
        if AUTO_SPAM_ENABLED then
            startSpam()
            spamStatusLabel:Set("Spam:  Running")
        else
            stopSpam()
        end
        Rayfield:Notify({
            Title = "NYB Hub",
            Content = AUTO_SPAM_ENABLED and " Spam ENABLED" or " Spam DISABLED",
            Duration = 2,
        })
    end,
})

KBTab:CreateKeybind({
    Name = "Toggle Visualizer",
    CurrentKeybind = "V",
    HoldToInteract = false,
    Flag = "VisualizerKey",
    Callback = function()
        VISUALIZER_ENABLED = not VISUALIZER_ENABLED
        if not VISUALIZER_ENABLED then hideVisualizer() end
        Rayfield:Notify({
            Title = "NYB Hub",
            Content = VISUALIZER_ENABLED and " Visualizer ON" or " Visualizer OFF",
            Duration = 2,
        })
    end,
})

KBTab:CreateSection("Note")
KBTab:CreateLabel("Click any keybind then press a key")
KBTab:CreateLabel("to set your own custom bind!")

-- ===========================
-- === TAB 4: INFO ===
-- ===========================

local InfoTab = Window:CreateTab(" Info", nil)
InfoTab:CreateSection("NYB Hub v1.0")
InfoTab:CreateLabel(" Auto Parry: Precision TTI-based")
InfoTab:CreateLabel(" Auto Spam: Direct FireServer spam")
InfoTab:CreateLabel(" Visualizer: Dynamic color + size")
InfoTab:CreateLabel(" Clash Mode: Auto detects fast ball")
InfoTab:CreateLabel(" Jump Fix: Flat XZ distance calc")
InfoTab:CreateSection("Dynamic Circle")
InfoTab:CreateLabel(" Green = slow ball = small circle")
InfoTab:CreateLabel(" Yellow = medium speed")
InfoTab:CreateLabel(" Red = fast ball = big circle")
InfoTab:CreateLabel("Circle radius = parry trigger distance")
InfoTab:CreateSection("Default Keybinds")
InfoTab:CreateLabel("P = Toggle Auto Parry")
InfoTab:CreateLabel("B = Toggle Auto Spam")
InfoTab:CreateLabel("V = Toggle Visualizer")
InfoTab:CreateSection("Coming in v1.1")
InfoTab:CreateLabel(" Sword Changer")

-- ========================
-- === MAIN LOOP ===
-- ========================

local frame = 0

RunService.PreSimulation:Connect(function()
    frame = frame + 1

    local Character = Player.Character
    local HRP = Character and Character:FindFirstChild("HumanoidRootPart")

    local Ball = GetBall()
    local currentSpeed = 0

    if Ball then
        local zoomies = Ball:FindFirstChild("zoomies")
        if zoomies then
            currentSpeed = zoomies.VectorVelocity.Magnitude
        end
    end

    local dynamicRadius = getDynamicRadius(currentSpeed)
    currentCircleRadius = dynamicRadius

    if HRP then
        if VISUALIZER_ENABLED then
            updateVisualizer(HRP.Position, dynamicRadius)
        end
    else
        hideVisualizer()
    end

    if frame % 20 == 0 then
        parryLabel:Set("Total Parries: " .. parryCount)
        statusLabel:Set(AUTO_PARRY_ENABLED and "Status:  Active" or "Status:  Disabled")
        radiusLabel:Set("Circle Radius: " .. string.format("%.1f", dynamicRadius) .. " studs")
    end

    if not AUTO_PARRY_ENABLED then return end
    if not HRP then return end

    if not Ball then
        if frame % 20 == 0 then
            ballLabel:Set("Ball:  Not found")
            targetLabel:Set("Target: None")
            ttiLabel:Set("TTI: --")
            speedLabel:Set("Ball Speed: --")
            jumpLabel:Set("Jump State: --")
        end
        return
    end

    local zoomies = Ball:FindFirstChild("zoomies")
    if not zoomies then return end

    local Speed  = zoomies.VectorVelocity.Magnitude
    local target = Ball:GetAttribute("target")

    local hrpPos   = HRP.Position
    local ballPos  = Ball.Position
    local Distance = Vector3.new(hrpPos.X - ballPos.X, 0, hrpPos.Z - ballPos.Z).Magnitude

    local tti = Speed > 0 and (Distance / Speed) or 999

    local isClashing = Speed > CLASH_SPEED_THRESHOLD
    local humanoid   = Character:FindFirstChild("Humanoid")
    local isJumping  = humanoid and humanoid.FloorMaterial == Enum.Material.Air

    local clashJumpBoost = (isClashing and isJumping) and 0.3 or 0
    local effectiveTTI   = isClashing and (CLASH_TTI_THRESHOLD + clashJumpBoost) or TIME_TO_IMPACT

    if frame % 20 == 0 then
        ballLabel:Set("Ball:  " .. math.floor(Distance) .. " studs")
        speedLabel:Set("Ball Speed: " .. math.floor(Speed) .. (isClashing and "  CLASH!" or "  Normal"))
        targetLabel:Set("Target: " .. tostring(target) .. (target == Player.Name and "  YOU!" or ""))
        ttiLabel:Set("TTI: " .. string.format("%.2f", tti) .. "s / " .. string.format("%.2f", effectiveTTI) .. "s")
        jumpLabel:Set("Jump: " .. (isJumping and " Air" .. (isClashing and " +BOOST" or "") or " Ground"))
    end

    local ttiTrigger  = target == Player.Name and not Parried and tti <= effectiveTTI
    local distTrigger = target == Player.Name and not Parried and Distance <= dynamicRadius

    if ttiTrigger or distTrigger then
        doParry()
        parryLabel:Set("Total Parries: " .. parryCount)
    end
end)

-- === FORCE EVERYTHING OFF ON LOAD ===
AUTO_SPAM_ENABLED  = false
AUTO_PARRY_ENABLED = false
stopSpam()

Rayfield:Notify({
    Title = "NYB Hub v1.0",
    Content = "Loaded! P=Parry | B=Spam | V=Visualizer",
    Duration = 5,
})

