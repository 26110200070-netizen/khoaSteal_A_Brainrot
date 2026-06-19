--[[
    Fear Duels GUI - PC & Mobile Support with Hotkeys
    Quick button layout (4 rows):
        (0,0)=CARRY SPEED, (1,0)=AUTO LEFT, 
        (0,1)=BAT COUNTER, (1,1)=AUTO RIGHT,
        (0,2)=LAGGER MODE, (1,2)=BAT AIMBOT,
        (0,3)=TP DOWN,     (1,3)=DROP BR
    
    HOTKEYS:
    - Z: Toggle TP DOWN (Auto Teleport)
    - X: Toggle DROP BR (Auto Drop)
    - V: Toggle Auto Left
    - B: Toggle Auto Right
    - N: Toggle Bat Counter
    - M: Toggle Bat Aimbot
    - G: Manual Drop (same as DROP BR button)
    - H: Manual TP Down
    - K: Toggle Carry Speed
    - L: Toggle Lagger Mode

--]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local LP = Players.LocalPlayer

local cloneref = (cloneref or clonereference or function(instance)
	return instance
end)

local WindUI
do
	local ok, result = pcall(function()
		return require("./src/Init")
	end)

	if ok then
		WindUI = result
	else
		if cloneref(game:GetService("RunService")):IsStudio() then
			WindUI = require(cloneref(game:GetService("ReplicatedStorage"):WaitForChild("WindUI"):WaitForChild("Init")))
		else
			WindUI =
				loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
		end
	end
end
-- Safe file functions (fixed: pcall always returns true, must check type directly)
local function hasFileFuncs()
    return type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function"
end
local function safeWriteFile(name, data)
    if not hasFileFuncs() then return end
    local ok, err = pcall(writefile, name, data)
    if not ok then
        warn("[FearDuel] Save failed: " .. tostring(err))
    end
end
local function safeReadFile(name)
    if not hasFileFuncs() then return nil end
    local existsOk, exists = pcall(isfile, name)
    if not existsOk or not exists then return nil end
    local ok, res = pcall(readfile, name)
    if ok then return res end
    return nil
end
pcall(function()
    local pg = LP:FindFirstChild("PlayerGui")
    if pg then
        local old = pg:FindFirstChild("FearDuelGUI")
        if old then old:Destroy() end
    end
end)
-- State
local State = {
    normalSpeed = 60, carrySpeed = 30, laggerSpeed = 60, oxgSpeed = 60, jumpVelocity = 57,
    infJumpEnabled = false, antiRagdollEnabled = false,
    fpsBoostEnabled = false, guiVisible = true,
    isStealing = false, stealStartTime = nil, lastStealTick = 0,
    brainrotReturnEnabled = false, brainrotReturnCooldown = false,
    brainrotReturnSide = nil, lastKnownHealth = 100,
    autoLeftEnabled = false, autoRightEnabled = false,
    _tplnProgress = false, detectedBaseSide = nil,
    lastMoveDir = Vector3.new(0,0,0),
    animEnabled = false,
    mobilesStealing = false,
    _sideDetecting = false,
    carrySpeedActive = false,
    laggerModeEnabled = false,
    oxgModeEnabled = false,

    uiLocked = false,
    quickLocked = false,
    accentTheme = "White", -- default theme name
    batCounterEnabled = true,
    desyncEnabled = false,
    medusaCounterEnabled = false,
    batAimbotEnabled = false,
    batAimbotAutoDrop = true,
    batAimbotMeleeOffset = 2,
    tpDownEnabled = false,
    dropBREnabled = false,
    unwalkEnabled = false,
    infJumpMode = "manual",
    fovValue = 110,
    -- Auto TP State
    autoTPEnabled = false,
    autoTPHeight = 20,
    -- GUI Scale
    guiScale = 0.7,
    quickScale = 1.0,
    quickBtnSize = 60,
    moveableMode = false,
    duelLaggerActive = false,
    duelLaggerThread = nil,
    _laggerTableIncrease = 25,
}
local syncInfJumpChips = nil
-- ========== BINDS ==========
local Binds = {
    tpDown        = { key = "Z",  pad = nil },
    dropBR        = { key = "X",  pad = nil },
    autoLeft      = { key = "V",  pad = nil },
    autoRight     = { key = "B",  pad = nil },
    batCounter    = { key = "N",  pad = nil },
    batAimbot     = { key = "M",  pad = nil },
    manualDrop    = { key = "G",  pad = nil },
    manualTpDown  = { key = "H",  pad = nil },
    carrySpeed    = { key = "K",  pad = nil },
    laggerMode    = { key = "L",  pad = "ButtonL3" },
    oxgMode       = { key = "K2", pad = nil },

    duelLagger    = { key = nil,  pad = nil },

    instaGrab     = { key = nil,  pad = nil },
    infJump       = { key = nil,  pad = nil },
    instaReset    = { key = nil,  pad = nil },
}
local BIND_LABELS = {
    tpDown       = "TP Down",       dropBR       = "Drop BR",
    autoLeft     = "Auto Left",     autoRight    = "Auto Right",
    batCounter   = "Bat Counter",   batAimbot    = "Bat Aimbot",
    manualDrop   = "Manual Drop",   manualTpDown = "Manual TP Down",
    carrySpeed   = "Carry Speed",   laggerMode   = "Lagger Mode",
    oxgMode      = "OXG Mode",
    instaGrab    = "Auto Steal",    infJump      = "Inf Jump",
    instaReset   = "Insta Reset",   duelLagger   = "Duel Lagger",
}
local BIND_ORDER = {
    "tpDown","dropBR","autoLeft","autoRight",
    "batCounter","batAimbot","manualDrop","manualTpDown",
    "carrySpeed","laggerMode","oxgMode","instaGrab","infJump","instaReset","duelLagger",
}
local function getBindDisplay(action)
    local b = Binds[action]
    local k = b.key or "—"
    local p = b.pad or "—"
    return k .. " / " .. p
end
local Steal = {
    AutoStealEnabled = false, StealRadius = 60, StealDuration = 1.3,
    Data = {}, plotCache = {}, plotCacheTime = {}, cachedPrompts = {}, promptCacheTime = 0,
}
local CARRY_DETECTION_RADIUS = 17
local PLOT_CACHE_DURATION = 0.5
local PROMPT_CACHE_REFRESH = 0.15
local STEAL_COOLDOWN = 0.1
local medusaDebounce = false
local medusaLastUsed = 0
local medusaConns = {}
local POS = {
    L1 = Vector3.new(-476.48,-6.28,92.73), L2 = Vector3.new(-483.12,-4.95,94.80),
    R1 = Vector3.new(-476.16,-6.52,25.62), R2 = Vector3.new(-483.04,-5.09,23.14),
    RETURN_L = Vector3.new(-475.27,-6.99,94.54),
    RETURN_R = Vector3.new(-475.22,-6.99,23.63),
}
local Conns = { autoSteal = nil, antiRag = nil, autoLeft = nil, autoRight = nil, float = nil,
    progress = nil, heartbeat = nil, batCounter = nil, batAimbot = nil, drop = nil, autoTP = nil }
local h, hrp, speedLbl
local setAutoLeft, setAutoRight
local setInstaGrab, setInfJump, setAntiRag, setFps
local setAnimToggle, setLockUI
local setNormalSpeed, setCarrySpeed, setLaggerSpeed, setGrabRadius, setStealDuration
local startAntiRagdoll, stopAntiRagdoll
local applyFPSBoost, startAutoSteal, stopAutoSteal
local startAutoLeft, stopAutoLeft, startAutoRight, stopAutoRight
local progressFill, progressPct
local setTpDown, setDropBR
local doInstaReset  -- forward ref for keybind
local setOxgMode
local setBatCounter, setDesync, setBrainrotReturn, setAimbotOffset, setBatAimbotAutoDrop

local setFovSlider  -- forward ref for FOV slider visual update
local setAutoTP, setAutoTPHeight  -- forward refs for Auto TP
local setBatAimbot, setCarrySpeedActive, setLaggerModeActive
local autoLeftToggle, autoRightToggle, batAimbotToggle, carrySpeedToggle, laggerModeToggle, tpDownToggle, dropBRToggle, autoStealToggle, infJumpToggle, antiRagToggle, fpsBoostToggle, animToggle, medusaCounterToggle, unwalkToggle, darkModeToggle, cameraFOVSlider, lockUIToggle
-- ========== AUTO TP FUNCTION ==========
local autoTPConn = nil
local function startAutoTP()
    if autoTPConn then return end
    autoTPConn = RunService.Heartbeat:Connect(function()
        if not State.autoTPEnabled then return end
        if State.batAimbotEnabled then return end
        pcall(function()
            local char = LP.Character
            if not char then return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum then return end
            -- Only TP if falling and above height threshold
            if hum.FloorMaterial == Enum.Material.Air and hrp.Position.Y > State.autoTPHeight then
                local rp = RaycastParams.new()
                rp.FilterDescendantsInstances = { char }
                rp.FilterType = Enum.RaycastFilterType.Exclude
                local result = workspace:Raycast(hrp.Position, Vector3.new(0, -2000, 0), rp)
                if result then
                    local groundY = result.Position.Y
                    local offset = hum.HipHeight + (hrp.Size.Y / 2) + 0.5
                    hrp.CFrame = CFrame.new(hrp.Position.X, groundY + offset, hrp.Position.Z)
                    hrp.AssemblyLinearVelocity = Vector3.zero
                end
            end
        end)
    end)
end
local function stopAutoTP()
    if autoTPConn then
        autoTPConn:Disconnect()
        autoTPConn = nil
    end
end
-- ========== INSTA RESET (top-level, callable from keybind) ==========
local _antiDieConns = {}  -- declared here so doInstaReset can reference it
local _irDebounce = false
local _irTpPos = CFrame.new(1000003.56, 999999.69, 8.17)
local function _irRestoreCamera()
    pcall(function()
        local ch = LP.Character
        local hm = ch and ch:FindFirstChildOfClass("Humanoid")
        workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
        if hm then workspace.CurrentCamera.CameraSubject = hm end
    end)
end
doInstaReset = function()
    if _irDebounce then return end
    local c = LP.Character
    if not c then return end
    local hrp2 = c:FindFirstChild("HumanoidRootPart")
    local hum2 = c:FindFirstChildOfClass("Humanoid")
    if not hrp2 or not hum2 then return end
    _irDebounce = true
    pcall(function() hum2.WalkSpeed = 16 end)
    pcall(function() hrp2.AssemblyLinearVelocity = Vector3.new(0,0,0) end)
    local carpet = c:FindFirstChild("Flying Carpet")
    if carpet then pcall(function() carpet:Destroy() end) end
    pcall(function()
        local cam = workspace.CurrentCamera
        cam.CameraType = Enum.CameraType.Scriptable
        cam.CFrame = cam.CFrame
    end)
    pcall(function()
        for _, part in ipairs(c:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end)
    -- Temporarily stop anti-die from blocking the kill
    local savedConns = _antiDieConns
    _antiDieConns = {}
    for _, conn in ipairs(savedConns) do pcall(function() conn:Disconnect() end) end
    pcall(function() hum2:SetStateEnabled(Enum.HumanoidStateType.Dead, true) end)
    pcall(function() hum2.Health = 0 end)
    pcall(function() hrp2.CFrame = _irTpPos end)
    pcall(function() c:BreakJoints() end)
    LP.CharacterAdded:Once(function()
        task.wait(0.1); _irRestoreCamera(); _irDebounce = false
    end)
    task.delay(5, function() if _irDebounce then _irDebounce = false; _irRestoreCamera() end end)
end

-- ========== FOV ==========
local fovConnection = nil
local function applyFOV()
    local cam = workspace.CurrentCamera
    if cam then cam.FieldOfView = State.fovValue end
end
local function hookFOV()
    if fovConnection then pcall(function() fovConnection:Disconnect() end) end
    local cam = workspace.CurrentCamera
    if not cam then return end
    applyFOV()
    fovConnection = cam:GetPropertyChangedSignal("FieldOfView"):Connect(function()
        if cam.FieldOfView ~= State.fovValue then
            cam.FieldOfView = State.fovValue
        end
    end)
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookFOV)
LP.CharacterAdded:Connect(function()
    task.wait(0.1)
    hookFOV()
end)
hookFOV()
-- ========== TP DOWN FUNCTION (ONE-SHOT) ==========
local _tpDownLastUsed = 0
local _tpDownCooldown = 0.1
local function tpDownNow()
    local now = tick()
    if now - _tpDownLastUsed < _tpDownCooldown then return end

    local char = LP.Character
    if not char then return end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    local floorMat = hum.FloorMaterial
    if floorMat ~= Enum.Material.Air then return end

    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = { char }
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude

    local result = workspace:Raycast(root.Position, Vector3.new(0, -2000, 0), raycastParams)
    if not result then return end

    local currentY = root.Position.Y
    local groundY = result.Position.Y
    local offset = hum.HipHeight + (root.Size.Y / 2) + 0.1
    local safeGroundY = groundY + offset

    local distToGround = currentY - safeGroundY
    if distToGround < 1 then return end

    _tpDownLastUsed = now
    root.CFrame = CFrame.new(root.Position.X, safeGroundY, root.Position.Z)
    root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
end
-- Auto TP DOWN loop
local tpDownConn = nil
local function startTpDown()
    if tpDownConn then return end
    tpDownConn = RunService.Heartbeat:Connect(function()
        if State.tpDownEnabled then
            tpDownNow()
        end
    end)
end
local function stopTpDown()
    if tpDownConn then
        tpDownConn:Disconnect()
        tpDownConn = nil
    end
end
-- ========== DROP BRAINROT FUNCTION ==========
-- ========== DROP BRAINROT FUNCTION ==========
local dropBrainrotActive = false
local function dropBrainrotNow()
    if dropBrainrotActive then return end

    local char = LP.Character
    if not char then return end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    dropBrainrotActive = true
    local t0 = tick()
    local DROP_ASCEND_DURATION = 0.2
    local DROP_ASCEND_SPEED = 150
    local dc

    dc = RunService.Heartbeat:Connect(function()
        local r = char and char:FindFirstChild("HumanoidRootPart")
        if not r then
            dc:Disconnect()
            dropBrainrotActive = false
            return
        end

        if tick() - t0 >= DROP_ASCEND_DURATION then
            dc:Disconnect()

            local rp = RaycastParams.new()
            rp.FilterDescendantsInstances = { char }
            rp.FilterType = Enum.RaycastFilterType.Exclude
            local rr = workspace:Raycast(r.Position, Vector3.new(0, -2000, 0), rp)

            if rr then
                local hum = char:FindFirstChildOfClass("Humanoid")
                local off = (hum and hum.HipHeight or 2) + (r.Size.Y / 2)
                r.CFrame = CFrame.new(r.Position.X, rr.Position.Y + off, r.Position.Z)
                r.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            end

            dropBrainrotActive = false
            return
        end

        r.AssemblyLinearVelocity = Vector3.new(r.AssemblyLinearVelocity.X, DROP_ASCEND_SPEED, r.AssemblyLinearVelocity.Z)
    end)
end
-- Auto DROP BR loop
local dropBRConn = nil
local function startDropBR()
    if dropBRConn then return end
    dropBRConn = RunService.Heartbeat:Connect(function()
        if State.dropBREnabled then
            dropBrainrotNow()
        end
    end)
end
local function stopDropBR()
    if dropBRConn then
        dropBRConn:Disconnect()
        dropBRConn = nil
    end
    dropBrainrotActive = false
end
-- ========== DARK MODE ==========
local nightModeEnabled = false
local defBrightness = Lighting.Brightness
local defClockTime = Lighting.ClockTime
local defOutdoorAmbient = Lighting.OutdoorAmbient
local defExposureComp = Lighting.ExposureCompensation

local function enableDarkMode()
    nightModeEnabled = true
    local sky = Lighting:FindFirstChild("fearDarkSky") or Instance.new("Sky")
    sky.Name = "fearDarkSky"
    sky.SkyboxBk = "rbxassetid://159454299"; sky.SkyboxDn = "rbxassetid://159454296"
    sky.SkyboxFt = "rbxassetid://159454293"; sky.SkyboxLf = "rbxassetid://159454286"
    sky.SkyboxRt = "rbxassetid://159454289"; sky.SkyboxUp = "rbxassetid://159454291"
    sky.Parent = Lighting
    Lighting.Brightness = 0; Lighting.ClockTime = 0
    Lighting.ExposureCompensation = -2
    Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
end

local function disableDarkMode()
    nightModeEnabled = false
    local s = Lighting:FindFirstChild("fearDarkSky"); if s then s:Destroy() end
    Lighting.Brightness = defBrightness; Lighting.ClockTime = defClockTime
    Lighting.ExposureCompensation = defExposureComp; Lighting.OutdoorAmbient = defOutdoorAmbient
end

-- ========== UNWALK (NO ANIMATIONS) ==========
local _unwalkAnimations = {}
local unwalkConn = nil

local function _disableAnimations()
    local char = LP.Character; if not char then return end
    local hum2 = char:FindFirstChildOfClass("Humanoid"); if not hum2 then return end
    for _, track in pairs(_unwalkAnimations) do pcall(function() track:Stop() end) end
    _unwalkAnimations = {}
    local animator = hum2:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in pairs(animator:GetPlayingAnimationTracks()) do
            track:Stop()
            table.insert(_unwalkAnimations, track)
        end
    end
end

local function startUnwalk()
    _disableAnimations()
    if unwalkConn then unwalkConn:Disconnect() end
    unwalkConn = RunService.Heartbeat:Connect(function()
        if not State.unwalkEnabled then return end
        _disableAnimations()
    end)
end

local function stopUnwalk()
    if unwalkConn then unwalkConn:Disconnect(); unwalkConn = nil end
    _unwalkAnimations = {}
    local c = LP.Character
    if c then
        local anim = c:FindFirstChild("Animate")
        if anim and anim:IsA("LocalScript") and anim.Disabled then
            anim.Disabled = false
        end
    end
end

-- ========== DESYNC ==========
local function applyDesync(state)
    if state then
        if raknet and typeof(raknet.desync) == "function" then
            raknet.desync(true)
        elseif _G.raknet and typeof(_G.raknet.desync) == "function" then
            _G.raknet.desync(true)
        end
    else
        if raknet and typeof(raknet.desync) == "function" then
            raknet.desync(false)
        elseif _G.raknet and typeof(_G.raknet.desync) == "function" then
            _G.raknet.desync(false)
        end
    end
end
local function onCharacterAddedDesync(char)
    if State.desyncEnabled then
        task.wait(0.5)
        applyDesync(true)
    end
end
LP.CharacterAdded:Connect(onCharacterAddedDesync)
if LP.Character then task.spawn(function() onCharacterAddedDesync(LP.Character) end) end
-- ========== MEDUSA ==========
local function findMedusa()
    local char = LP.Character
    if not char then return nil end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") and t.Name:lower():find("medusa") then return t end
    end
    local bp = LP:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and t.Name:lower():find("medusa") then return t end
        end
    end
    return nil
end
local function useMedusa()
    if medusaDebounce or tick() - medusaLastUsed < 25 then return end
    local char = LP.Character
    if not char then return end
    medusaDebounce = true
    local med = findMedusa()
    if med then
        if med.Parent ~= char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum:EquipTool(med) end
        end
        pcall(function() med:Activate() end)
        medusaLastUsed = tick()
    end
    medusaDebounce = false
end
local function setupMedusa(char)
    for _, c in pairs(medusaConns) do pcall(function() c:Disconnect() end) end
    medusaConns = {}
    if not char then return end
    local function onAnchor(part)
        return part:GetPropertyChangedSignal("Anchored"):Connect(function()
            if State.medusaCounterEnabled and part.Anchored and part.Transparency == 1 then
                useMedusa()
            end
        end)
    end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then table.insert(medusaConns, onAnchor(part)) end
    end
    table.insert(medusaConns, char.DescendantAdded:Connect(function(part)
        if part:IsA("BasePart") then table.insert(medusaConns, onAnchor(part)) end
    end))
end
local function stopMedusaCounter()
    for _, c in pairs(medusaConns) do pcall(function() c:Disconnect() end) end
    medusaConns = {}
end
local function getHRP()
    local char = LP.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local char = LP.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end
-- ========== BAT AIMBOT ==========
local AIMBOT_SPEED = 56.5
local function findBat()
    local c = LP.Character
    if not c then return nil end
    local bp = LP:FindFirstChildOfClass("Backpack")
    
    for _, ch in ipairs(c:GetChildren()) do
        if ch:IsA("Tool") and (ch.Name:lower():find("bat") or ch.Name:lower():find("slap")) then
            return ch
        end
    end
    if bp then
        for _, ch in ipairs(bp:GetChildren()) do
            if ch:IsA("Tool") and (ch.Name:lower():find("bat") or ch.Name:lower():find("slap")) then
                return ch
            end
        end
    end
    
    local SlapList = {
        "Bat", "Slap", "Iron Slap", "Gold Slap", "Diamond Slap",
        "Emerald Slap", "Ruby Slap", "Dark Matter Slap", "Flame Slap",
        "Nuclear Slap", "Galaxy Slap", "Glitched Slap"
    }
    for _, name in ipairs(SlapList) do
        local t = c:FindFirstChild(name) or (bp and bp:FindFirstChild(name))
        if t then return t end
    end
    return nil
end
local _closestPlayerCache, _closestPlayerCacheTime = nil, 0
local CLOSEST_PLAYER_REFRESH = 0.12
local function getClosestPlayer()
    local now = tick()
    if now - _closestPlayerCacheTime < CLOSEST_PLAYER_REFRESH then return _closestPlayerCache end
    local c = LP.Character
    if not c then _closestPlayerCache = nil; _closestPlayerCacheTime = now; return nil end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then _closestPlayerCache = nil; _closestPlayerCacheTime = now; return nil end
    local closest, bestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local tr = p.Character:FindFirstChild("HumanoidRootPart")
            if tr then
                local d = (hrp.Position - tr.Position).Magnitude
                if d < bestDist then
                    bestDist = d
                    closest = p
                end
            end
        end
    end
    _closestPlayerCache = closest
    _closestPlayerCacheTime = now
    return closest
end
-- Detect if player is currently holding a brainrot (any tool that isn't a bat/slap/medusa)
local function isHoldingBrainrot()
    local char = LP.Character
    if not char then return false end
    for _, obj in ipairs(char:GetChildren()) do
        if obj:IsA("Tool") then
            local n = obj.Name:lower()
            if not n:find("bat") and not n:find("slap") and not n:find("medusa") then
                return true
            end
        end
    end
    return false
end
local function dropIfHoldingBrainrot()
    if isHoldingBrainrot() then
        State.dropBREnabled = true
        dropBrainrotNow()
        task.delay(0.3, function()
            State.dropBREnabled = false
            stopDropBR()
        end)
    end
end
-- ========== BAT AIMBOT ==========
local aimbotLockedTarget   = nil
local aimbotNoTargetSince  = nil

local aimbotHighlight = Instance.new("Highlight")
aimbotHighlight.Name             = "AimbotESP"
aimbotHighlight.FillColor        = Color3.fromRGB(255, 0, 0)
aimbotHighlight.OutlineColor     = Color3.fromRGB(255, 255, 255)
aimbotHighlight.FillTransparency = 0.5
aimbotHighlight.OutlineTransparency = 0
pcall(function() aimbotHighlight.Parent = game:GetService("CoreGui") end)
if not aimbotHighlight.Parent then aimbotHighlight.Parent = LP:WaitForChild("PlayerGui") end

local function _aimbotTargetValid(tc)
    if not tc or not tc.Parent then return false end
    local hum = tc:FindFirstChildOfClass("Humanoid")
    local hrp2 = tc:FindFirstChild("HumanoidRootPart")
    return hum and hrp2
end

local function _aimbotGetTarget(myHRP)
    -- Clear locked target if their character was removed (reset)
    if aimbotLockedTarget and not _aimbotTargetValid(aimbotLockedTarget) then
        aimbotLockedTarget = nil
    end
    if aimbotLockedTarget then
        return aimbotLockedTarget:FindFirstChild("HumanoidRootPart"), aimbotLockedTarget
    end
    local best, bestHRP, bestDist = nil, nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and _aimbotTargetValid(p.Character) then
            local tHRP = p.Character:FindFirstChild("HumanoidRootPart")
            local d = (tHRP.Position - myHRP.Position).Magnitude
            if d < bestDist then bestDist = d; bestHRP = tHRP; best = p.Character end
        end
    end
    aimbotLockedTarget = best
    return bestHRP, best
end

-- Anti-die: prevents death during aimbot
local function _activateAntiDie()
    for _, c in ipairs(_antiDieConns) do pcall(function() c:Disconnect() end) end
    _antiDieConns = {}
    local char = LP.Character; if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
    hum.BreakJointsOnDeath = false
    hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
    table.insert(_antiDieConns, hum:GetPropertyChangedSignal("Health"):Connect(function()
        if hum.Health <= 0 then hum.Health = hum.MaxHealth end
    end))
end

local function startBatAimbot()
    if Conns.batAimbot then
        Conns.batAimbot:Disconnect()
        Conns.batAimbot = nil
    end
    _activateAntiDie()

    Conns.batAimbot = RunService.Heartbeat:Connect(function()
        local char = LP.Character; if not char or not char.Parent then return end
        local myHRP = char:FindFirstChild("HumanoidRootPart"); if not myHRP then return end
        local myH = char:FindFirstChildOfClass("Humanoid"); if not myH or myH.Health <= 0 then return end

        if not State.batAimbotEnabled then
            aimbotHighlight.Adornee = nil
            return
        end

        myH.AutoRotate = false

        -- Auto equip bat
        local bat = findBat()
        if bat and bat.Parent ~= char then pcall(function() myH:EquipTool(bat) end) end

        -- Absolute movement override: forces character into an active unwalked state
        myH:Move(Vector3.new(0, 0, 0), false)

        local tHRP, tChar = _aimbotGetTarget(myHRP)
        if tHRP and tChar and tHRP.Parent and tChar.Parent then
            aimbotNoTargetSince = nil
            aimbotHighlight.Adornee = tChar

            -- Velocity prediction
            local tVel        = tHRP.AssemblyLinearVelocity
            local predictTime = math.clamp(tVel.Magnitude / 150, 0.05, 0.2)
            local predicted   = tHRP.Position + tVel * predictTime

            -- Offsets: behind target + above head (matching OG)
            local behindOffset  = -tHRP.CFrame.LookVector * State.batAimbotMeleeOffset
            local headTopOffset = Vector3.new(0, 2.6, 0)
            local standPos      = predicted + behindOffset + headTopOffset

            local moveDir = standPos - myHRP.Position

            -- CFrame lookAt with -15° pitch (OG style)
            local lookTarget = Vector3.new(predicted.X, myHRP.Position.Y, predicted.Z)
            if (lookTarget - myHRP.Position).Magnitude > 0.1 then
                myHRP.CFrame = CFrame.lookAt(myHRP.Position, lookTarget) * CFrame.Angles(math.rad(-15), 0, 0)
            end

            if moveDir.Magnitude > 1 then
                myHRP.AssemblyLinearVelocity = moveDir.Unit * AIMBOT_SPEED
            else
                myHRP.AssemblyLinearVelocity = tVel
            end
        else
            if not aimbotNoTargetSince then aimbotNoTargetSince = tick() end
            if tick() - aimbotNoTargetSince > 1.5 then
                aimbotLockedTarget = nil
                if myHRP and myHRP.Parent then
                    myHRP.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                end
                aimbotHighlight.Adornee = nil
            end
        end
    end)
end

local function stopBatAimbot()
    if Conns.batAimbot then
        Conns.batAimbot:Disconnect()
        Conns.batAimbot = nil
    end
    local c2 = LP.Character
    local r = c2 and c2:FindFirstChild("HumanoidRootPart")
    local hum2 = c2 and c2:FindFirstChildOfClass("Humanoid")
    if r then
        r.AssemblyLinearVelocity = Vector3.zero
    end
    if hum2 then hum2.AutoRotate = true end
    aimbotLockedTarget  = nil
    aimbotNoTargetSince = nil
    aimbotHighlight.Adornee = nil
end
-- ========== BAT COUNTER ==========
local function findBatCounter()
    local char = LP.Character
    if not char then return nil end
    local bp = LP:FindFirstChildOfClass("Backpack")
    local list = {"Bat","Slap","Iron Slap","Gold Slap","Diamond Slap","Emerald Slap","Ruby Slap","Dark Matter Slap","Flame Slap","Nuclear Slap","Galaxy Slap","Glitched Slap"}
    for _, n in ipairs(list) do
        local t = char:FindFirstChild(n) or (bp and bp:FindFirstChild(n))
        if t then return t end
    end
    for _, ch in ipairs(char:GetChildren()) do
        if ch:IsA("Tool") and ch.Name:lower():find("bat") then return ch end
    end
    if bp then
        for _, ch in ipairs(bp:GetChildren()) do
            if ch:IsA("Tool") and ch.Name:lower():find("bat") then return ch end
        end
    end
    return nil
end
local _nearestAttackerCache, _nearestAttackerCacheTime = nil, 0
local function getNearestAttacker()
    local now = tick()
    if now - _nearestAttackerCacheTime < CLOSEST_PLAYER_REFRESH then return _nearestAttackerCache end
    local char = LP.Character
    local myHRP = char and char:FindFirstChild("HumanoidRootPart")
    if not myHRP then _nearestAttackerCache = nil; _nearestAttackerCacheTime = now; return nil end
    local closest, closestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local dist = (hrp.Position - myHRP.Position).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closest = p
                end
            end
        end
    end
    _nearestAttackerCache = closest
    _nearestAttackerCacheTime = now
    return closest
end
-- ========== BAT COUNTER (always on) ==========
Conns.batCounter = RunService.Heartbeat:Connect(function()
    if not State.batCounterEnabled then return end
    local char = LP.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local st = hum:GetState()
    local isRagdolled = st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.FallingDown
    if isRagdolled then
        task.spawn(function()
            local root = char:FindFirstChild("HumanoidRootPart")
            local bat = findBatCounter()
            if not bat then return end
            if bat.Parent ~= char then
                local hum2 = char:FindFirstChildOfClass("Humanoid")
                if hum2 then pcall(function() hum2:EquipTool(bat) end) end
            end
            if root then
                local target = getNearestAttacker()
                local tHRP = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
                if tHRP then
                    local dir = (tHRP.Position - root.Position).Unit
                    local flatDir = Vector3.new(dir.X, 0, dir.Z)
                    local isShiftLocked = UIS.MouseBehavior == Enum.MouseBehavior.LockCenter
                    if isShiftLocked then
                        local cam = workspace.CurrentCamera
                        local camFlat = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
                        if camFlat.Magnitude > 0 then flatDir = camFlat.Unit end
                    end
                    root.CFrame = CFrame.lookAt(root.Position, root.Position + flatDir)
                    root.AssemblyLinearVelocity = dir * 75
                end
            end
            pcall(function() bat:Activate() end)
            task.wait(0.15)
            pcall(function() bat:Activate() end)
        end)
        task.wait(0.5)
    end
end)
local L1 = Vector3.new(-476.48, -6.28, 92.73)
local L2 = Vector3.new(-483.12, -4.95, 94.80)
local R1 = Vector3.new(-476.16, -6.52, 25.62)
local R2 = Vector3.new(-483.04, -5.09, 23.14)
-- Quick-button frame refs so the auto loops can flash them on waypoint hits
local _autoLeftBtnFrame = nil
local _autoRightBtnFrame = nil
-- Gray color scheme for buttons
local C_BTN_WAYPOINT = Color3.fromRGB(45, 45, 45)
local C_BTN_ON_COLOR  = Color3.fromRGB(100, 100, 100)
local C_BTN_OFF = Color3.fromRGB(40, 40, 40)
local function flashWaypointBtn(frame)
    if not frame or not frame.Parent then return end
    TweenService:Create(frame, TweenInfo.new(0.08), {BackgroundColor3 = C_BTN_WAYPOINT}):Play()
    task.delay(0.18, function()
        if frame and frame.Parent then
            TweenService:Create(frame, TweenInfo.new(0.12), {BackgroundColor3 = C_BTN_ON_COLOR}):Play()
        end
    end)
end
local function turnOffBtn(frame)
    if not frame or not frame.Parent then return end
    TweenService:Create(frame, TweenInfo.new(0.15), {BackgroundColor3 = C_BTN_OFF}):Play()
end
local autoLeftConn = nil
local autoLeftPhase = 1
local function stopAutoLeft()
    if autoLeftConn then
        autoLeftConn:Disconnect()
        autoLeftConn = nil
    end
    autoLeftPhase = 1
    State.autoLeftEnabled = false
    turnOffBtn(_autoLeftBtnFrame)
    local hum = getHum()
    if hum then hum:Move(Vector3.zero, false) end
    local root = getHRP()
    if root then
        root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
    end
end
local function startAutoLeft()
    dropIfHoldingBrainrot()
    if autoLeftConn then stopAutoLeft() end
    if State.autoRightEnabled then
        State.autoRightEnabled = false
        if setAutoRight then setAutoRight(false) end
        stopAutoRight()
    end
    State.autoLeftEnabled = true
    autoLeftPhase = 1
    autoLeftConn = RunService.Heartbeat:Connect(function()
        if not State.autoLeftEnabled then return end
        local root = getHRP()
        local hum = getHum()
        if not root or not hum then return end
        local spd = State.normalSpeed
        if autoLeftPhase == 1 then
            local d = Vector3.new(L1.X - root.Position.X, 0, L1.Z - root.Position.Z)
            if d.Magnitude < 1 then
                autoLeftPhase = 2
                return
            end
            local md = d.Unit
            hum:Move(md, false)
            root.AssemblyLinearVelocity = Vector3.new(md.X * spd, root.AssemblyLinearVelocity.Y, md.Z * spd)
        elseif autoLeftPhase == 2 then
            local d = Vector3.new(L2.X - root.Position.X, 0, L2.Z - root.Position.Z)
            if d.Magnitude < 1 then
                hum:Move(Vector3.zero, false)
                root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                stopAutoLeft()
                return
            end
            local md = d.Unit
            hum:Move(md, false)
            root.AssemblyLinearVelocity = Vector3.new(md.X * spd, root.AssemblyLinearVelocity.Y, md.Z * spd)
        end
    end)
end
local autoRightConn = nil
local autoRightPhase = 1
local function stopAutoRight()
    if autoRightConn then
        autoRightConn:Disconnect()
        autoRightConn = nil
    end
    autoRightPhase = 1
    State.autoRightEnabled = false
    turnOffBtn(_autoRightBtnFrame)
    local hum = getHum()
    if hum then hum:Move(Vector3.zero, false) end
    local root = getHRP()
    if root then
        root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
    end
end
local function startAutoRight()
    dropIfHoldingBrainrot()
    if autoRightConn then stopAutoRight() end
    if State.autoLeftEnabled then
        State.autoLeftEnabled = false
        if setAutoLeft then setAutoLeft(false) end
        stopAutoLeft()
    end
    State.autoRightEnabled = true
    autoRightPhase = 1
    autoRightConn = RunService.Heartbeat:Connect(function()
        if not State.autoRightEnabled then return end
        local root = getHRP()
        local hum = getHum()
        if not root or not hum then return end
        local spd = State.normalSpeed
        if autoRightPhase == 1 then
            local d = Vector3.new(R1.X - root.Position.X, 0, R1.Z - root.Position.Z)
            if d.Magnitude < 1 then
                autoRightPhase = 2
                return
            end
            local md = d.Unit
            hum:Move(md, false)
            root.AssemblyLinearVelocity = Vector3.new(md.X * spd, root.AssemblyLinearVelocity.Y, md.Z * spd)
        elseif autoRightPhase == 2 then
            local d = Vector3.new(R2.X - root.Position.X, 0, R2.Z - root.Position.Z)
            if d.Magnitude < 1 then
                hum:Move(Vector3.zero, false)
                root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                stopAutoRight()
                return
            end
            local md = d.Unit
            hum:Move(md, false)
            root.AssemblyLinearVelocity = Vector3.new(md.X * spd, root.AssemblyLinearVelocity.Y, md.Z * spd)
        end
    end)
end
-- Black & White clean theme
local C_BG       = Color3.fromRGB(6, 6, 6)
local C_PANEL    = Color3.fromRGB(12, 12, 12)
local C_ROW      = Color3.fromRGB(18, 18, 18)
local C_BORDER   = Color3.fromRGB(60, 60, 60)
local C_BORDER2  = Color3.fromRGB(40, 40, 40)
local C_HEADER   = Color3.fromRGB(10, 10, 10)
local C_ACCENT   = Color3.fromRGB(255, 255, 255)
local C_ACCENT2  = Color3.fromRGB(210, 210, 210)
local C_DIM      = Color3.fromRGB(90, 90, 90)
local C_WHITE    = Color3.fromRGB(255, 255, 255)
local C_ON_BG    = Color3.fromRGB(255, 255, 255)
local C_OFF_BG   = Color3.fromRGB(18, 18, 18)
local C_KEY_BG   = Color3.fromRGB(16, 16, 16)
local C_TAB_ACT  = Color3.fromRGB(20, 20, 20)
local C_PROGRESS = Color3.fromRGB(200, 200, 200)

-- ========== COLOUR THEMES ==========
local THEMES = {
    { name = "White",   accent = Color3.fromRGB(255,255,255), accent2 = Color3.fromRGB(210,210,210), glow = Color3.fromRGB(180,180,180), btnOn = Color3.fromRGB(255,255,255), btnText = Color3.fromRGB(255,255,255) },
    { name = "Gray",    accent = Color3.fromRGB(180,180,200), accent2 = Color3.fromRGB(210,210,230), glow = Color3.fromRGB(100,100,120), btnOn = Color3.fromRGB(90,90,100),  btnText = Color3.fromRGB(200,200,210) },
    { name = "Purple",  accent = Color3.fromRGB(170,130,255), accent2 = Color3.fromRGB(200,170,255), glow = Color3.fromRGB(130,80,220),  btnOn = Color3.fromRGB(100,60,180), btnText = Color3.fromRGB(200,170,255) },
    { name = "Blue",    accent = Color3.fromRGB(100,160,255), accent2 = Color3.fromRGB(140,195,255), glow = Color3.fromRGB(50,120,220),  btnOn = Color3.fromRGB(40,90,180),  btnText = Color3.fromRGB(140,195,255) },
    { name = "Green",   accent = Color3.fromRGB(100,210,150), accent2 = Color3.fromRGB(140,240,180), glow = Color3.fromRGB(50,170,100),  btnOn = Color3.fromRGB(35,130,75),  btnText = Color3.fromRGB(140,240,180) },
    { name = "Red",     accent = Color3.fromRGB(255,110,110), accent2 = Color3.fromRGB(255,150,150), glow = Color3.fromRGB(200,60,60),   btnOn = Color3.fromRGB(160,45,45),  btnText = Color3.fromRGB(255,150,150) },
    { name = "Pink",    accent = Color3.fromRGB(255,140,200), accent2 = Color3.fromRGB(255,180,220), glow = Color3.fromRGB(210,80,150),  btnOn = Color3.fromRGB(170,55,115), btnText = Color3.fromRGB(255,180,220) },
    { name = "Cyan",    accent = Color3.fromRGB(80,215,230),  accent2 = Color3.fromRGB(120,235,245), glow = Color3.fromRGB(30,170,185),  btnOn = Color3.fromRGB(20,130,145), btnText = Color3.fromRGB(120,235,245) },
}
local function getThemeByName(name)
    for _, t in ipairs(THEMES) do if t.name == name then return t end end
    return THEMES[1]
end
-- Applied at GUI build time; also stored so live-update functions can read it
local _activeTheme = getThemeByName("White")
local function applyTheme(theme)
    _activeTheme = theme
    C_ACCENT    = theme.accent
    C_ACCENT2   = theme.accent2
    C_PROGRESS  = theme.accent
    State.accentTheme = theme.name
end

-- Animations
local Anims = {
    idle1 = "rbxassetid://133806214992291", idle2 = "rbxassetid://94970088341563",
    walk = "rbxassetid://707897309", run = "rbxassetid://707861613",
    jump = "rbxassetid://116936326516985", fall = "rbxassetid://116936326516985",
    climb = "rbxassetid://116936326516985", swim = "rbxassetid://116936326516985",
    swimidle = "rbxassetid://116936326516985",
}
local animHeartbeatConn, originalAnims
local function isPackAnim(id)
    if not id then return false end
    for _, v in pairs(Anims) do if v == id then return true end end
    return false
end
local function saveOriginalAnims(char)
    local anim = char:FindFirstChild("Animate")
    if not anim then return end
    local function g(o) return o and o.AnimationId or nil end
    local ids = {
        idle1 = g(anim.idle and anim.idle.Animation1), idle2 = g(anim.idle and anim.idle.Animation2),
        walk = g(anim.walk and anim.walk.WalkAnim), run = g(anim.run and anim.run.RunAnim),
        jump = g(anim.jump and anim.jump.JumpAnim), fall = g(anim.fall and anim.fall.FallAnim),
        climb = g(anim.climb and anim.climb.ClimbAnim), swim = g(anim.swim and anim.swim.Swim),
        swimidle = g(anim.swimidle and anim.swimidle.SwimIdle),
    }
    if not isPackAnim(ids.walk) then originalAnims = ids end
end
local function applyAnimPack(char)
    local anim = char:FindFirstChild("Animate")
    if not anim then return end
    local function s(o, id) if o then o.AnimationId = id end end
    s(anim.idle and anim.idle.Animation1, Anims.idle1)
    s(anim.idle and anim.idle.Animation2, Anims.idle2)
    s(anim.walk and anim.walk.WalkAnim, Anims.walk)
    s(anim.run and anim.run.RunAnim, Anims.run)
    s(anim.jump and anim.jump.JumpAnim, Anims.jump)
    s(anim.fall and anim.fall.FallAnim, Anims.fall)
    s(anim.climb and anim.climb.ClimbAnim, Anims.climb)
    s(anim.swim and anim.swim.Swim, Anims.swim)
    s(anim.swimidle and anim.swimidle.SwimIdle, Anims.swimidle)
end
local function restoreOriginalAnims(char)
    if not originalAnims then return end
    local anim = char:FindFirstChild("Animate")
    if not anim then return end
    local function s(o, id) if o and id then o.AnimationId = id end end
    s(anim.idle and anim.idle.Animation1, originalAnims.idle1)
    s(anim.idle and anim.idle.Animation2, originalAnims.idle2)
    s(anim.walk and anim.walk.WalkAnim, originalAnims.walk)
    s(anim.run and anim.run.RunAnim, originalAnims.run)
    s(anim.jump and anim.jump.JumpAnim, originalAnims.jump)
    s(anim.fall and anim.fall.FallAnim, originalAnims.fall)
    s(anim.climb and anim.climb.ClimbAnim, originalAnims.climb)
    s(anim.swim and anim.swim.Swim, originalAnims.swim)
    s(anim.swimidle and anim.swimidle.SwimIdle, originalAnims.swimidle)
    local hum2 = char:FindFirstChildOfClass("Humanoid")
    if hum2 then
        for _, t in ipairs(hum2:GetPlayingAnimationTracks()) do t:Stop(0) end
        hum2:ChangeState(Enum.HumanoidStateType.Running)
    end
end
local function startAnimToggle()
    if animHeartbeatConn then animHeartbeatConn:Disconnect(); animHeartbeatConn = nil end
    local char = LP.Character
    if char then
        saveOriginalAnims(char)
        applyAnimPack(char)
        local hum2 = char:FindFirstChildOfClass("Humanoid")
        if hum2 then
            for _, t in ipairs(hum2:GetPlayingAnimationTracks()) do t:Stop(0) end
            hum2:ChangeState(Enum.HumanoidStateType.Running)
        end
    end
    -- Re-apply on character added instead of every frame
end
local function stopAnimToggle()
    if animHeartbeatConn then animHeartbeatConn:Disconnect() end
    State.animEnabled = false
    local char = LP.Character
    if char then restoreOriginalAnims(char) end
end
-- Mobile carry detection
LP:GetAttributeChangedSignal("Stealing"):Connect(function()
    State.mobilesStealing = LP:GetAttribute("Stealing") == true
end)
local function isNearPodiumWithPrompt()
    local char = LP.Character
    local hrpL = char and char:FindFirstChild("HumanoidRootPart")
    if not hrpL then return false end
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return false end
    for _, plot in ipairs(plots:GetChildren()) do
        local podiums = plot:FindFirstChild("AnimalPodiums")
        if not podiums then continue end
        for _, podium in ipairs(podiums:GetChildren()) do
            if not podium:IsA("Model") then continue end
            local base = podium:FindFirstChild("Base")
            if not base then continue end
            local sp = base:FindFirstChild("Spawn")
            if not sp then continue end
            if (hrpL.Position - podium:GetPivot().Position).Magnitude > CARRY_DETECTION_RADIUS then continue end
            local att = sp:FindFirstChild("PromptAttachment")
            if not att then continue end
            for _, obj in ipairs(att:GetChildren()) do
                if obj:IsA("ProximityPrompt") and obj.Enabled then return true end
            end
        end
    end
    return false
end
local function getMobileCarryState()
    return State.mobilesStealing or isNearPodiumWithPrompt()
end
-- Plot detection
local function getPlotPosition(plot)
    if not plot then return nil end
    if plot.PrimaryPart then return plot.PrimaryPart.Position end
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local p = sign:IsA("BasePart") and sign or sign:FindFirstChildWhichIsA("BasePart")
        if p then return p.Position end
    end
    local sum, count = Vector3.new(0,0,0), 0
    for _, obj in plot:GetDescendants() do
        if obj:IsA("BasePart") then
            sum += obj.Position
            count += 1
        end
    end
    return count > 0 and (sum / count) or nil
end
local function findMyPlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local nameLower = (LP.DisplayName or LP.Name):lower()
    for _, plot in plots:GetChildren() do
        local sign = plot:FindFirstChild("PlotSign")
        if not sign then continue end
        local yb = sign:FindFirstChild("YourBase")
        if yb and yb:IsA("BillboardGui") and yb.Enabled then return plot end
        local sg = sign:FindFirstChild("SurfaceGui")
        if not sg then continue end
        local fr = sg:FindFirstChild("Frame")
        if not fr then continue end
        local lbl = fr:FindFirstChild("TextLabel")
        if lbl and typeof(lbl.Text) == "string" and lbl.Text ~= "" then
            local t = lbl.Text:lower()
            if t:find(nameLower, 1, true) and t:find("'s base", 1, true) then return plot end
        end
    end
    return nil
end
local function getSideByPlayerPos()
    local char = LP.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local pos = root.Position
    local dR = (pos - POS.RETURN_R).Magnitude
    local dL = (pos - POS.RETURN_L).Magnitude
    if math.abs(dR - dL) > 10 then return dR < dL and "right" or "left" end
    return nil
end
local function detectBaseSideAsync(callback)
    task.spawn(function()
        local myPlot = nil
        for _ = 1, 30 do
            myPlot = findMyPlot()
            if myPlot then break end
            task.wait(1)
        end
        local side = nil
        if myPlot then
            local bp = getPlotPosition(myPlot)
            if bp then
                side = (bp - POS.RETURN_R).Magnitude < (bp - POS.RETURN_L).Magnitude and "right" or "left"
            end
        end
        if not side then side = getSideByPlayerPos() end
        side = side or "left"
        State.detectedBaseSide = side
        if callback then callback(side) end
    end)
end
local function resetBaseSide() State.detectedBaseSide = nil end
local function doReturnTeleport(targetPos)
    if State.brainrotReturnCooldown then return end
    State.brainrotReturnCooldown = true
    State._tplnProgress = true
    if Conns.autoLeft then Conns.autoLeft:Disconnect(); Conns.autoLeft = nil end
    if Conns.autoRight then Conns.autoRight:Disconnect(); Conns.autoRight = nil end
    State.autoLeftEnabled = false
    State.autoRightEnabled = false
    if setAutoLeft then setAutoLeft(false) end
    if setAutoRight then setAutoRight(false) end
    task.spawn(function()
        local char = LP.Character
        if char then
            local root = char:FindFirstChild("HumanoidRootPart")
            if root then
                root.CFrame = CFrame.new(targetPos)
                root.AssemblyLinearVelocity = Vector3.zero
                local hum2 = char:FindFirstChildOfClass("Humanoid")
                if hum2 then hum2:Move(Vector3.zero, false) end
            end
        end
        State._tplnProgress = false
        task.wait(0.2)
        State.brainrotReturnCooldown = false
    end)
end
startAntiRagdoll = function()
    if Conns.antiRag then Conns.antiRag:Disconnect(); Conns.antiRag = nil end
    Conns.antiRag = RunService.Heartbeat:Connect(function()
        if not State.antiRagdollEnabled then return end
        local char = LP.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum2 = char:FindFirstChildOfClass("Humanoid")
        if hum2 then
            local st = hum2:GetState()
            if st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.FallingDown then
                hum2:ChangeState(Enum.HumanoidStateType.Running)
                workspace.CurrentCamera.CameraSubject = hum2
                pcall(function()
                    local PlayerModule = LP.PlayerScripts:FindFirstChild("PlayerModule")
                    if PlayerModule then
                        local Controls = require(PlayerModule:FindFirstChild("ControlModule"))
                        Controls:Enable()
                    end
                end)
                if root then root.Velocity = Vector3.new(0,0,0); root.RotVelocity = Vector3.new(0,0,0) end
            end
        end
        for _, obj in ipairs(char:GetDescendants()) do
            if obj:IsA("Motor6D") and obj.Enabled == false then obj.Enabled = true end
        end
    end)
end
stopAntiRagdoll = function()
    if Conns.antiRag then Conns.antiRag:Disconnect(); Conns.antiRag = nil end
    State.antiRagdollEnabled = false
end
applyFPSBoost = function()
    local function proc(v)
        pcall(function()
            if v:IsA("Decal") or v:IsA("Texture") then v.Transparency = 1
            elseif v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles") or v:IsA("ParticleEmitter") then v.Enabled = false
            elseif v:IsA("Attachment") then v.Visible = false
            elseif v:IsA("MeshPart") then v.CastShadow = false; v.DoubleSided = false; v.RenderFidelity = Enum.RenderFidelity.Performance
            elseif v:IsA("BasePart") then v.CastShadow = false; v.Material = Enum.Material.Plastic; v.Reflectance = 0
            end
        end)
    end
    for _, v in pairs(workspace:GetDescendants()) do proc(v) end
    workspace.DescendantAdded:Connect(function(v)
        if State.fpsBoostEnabled then task.spawn(proc, v) end
    end)
end
-- ========== AUTO STEAL ==========
local function isMyPlotByName(plotName)
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return false end
    local plot = plots:FindFirstChild(plotName)
    if not plot then return false end
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local yb = sign:FindFirstChild("YourBase")
        if yb and yb:IsA("BillboardGui") then return yb.Enabled == true end
    end
    return false
end
local function findNearestPrompt()
    local char = LP.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local nearest, dist = nil, math.huge
    for _, plot in ipairs(plots:GetChildren()) do
        if isMyPlotByName(plot.Name) then continue end
        local pods = plot:FindFirstChild("AnimalPodiums")
        if not pods then continue end
        for _, pod in ipairs(pods:GetChildren()) do
            local base = pod:FindFirstChild("Base")
            if not base then continue end
            local spawn = base:FindFirstChild("Spawn")
            if not spawn then continue end
            local d = (spawn.Position - root.Position).Magnitude
            if d <= Steal.StealRadius and d < dist then
                local att = spawn:FindFirstChild("PromptAttachment")
                if att then
                    for _, p in ipairs(att:GetChildren()) do
                        if p:IsA("ProximityPrompt") and p.ActionText and p.ActionText:find("Steal") then
                            nearest, dist = p, d
                        end
                    end
                end
            end
        end
    end
    return nearest
end
local function executeSteal(prompt, name)
    if State.isStealing then return end
    if not Steal.Data[prompt] then
        Steal.Data[prompt] = {hold = {}, trigger = {}, ready = true}
        if getconnections then
            for _, c in ipairs(getconnections(prompt.PromptButtonHoldBegan)) do
                if c.Function then table.insert(Steal.Data[prompt].hold, c.Function) end
            end
            for _, c in ipairs(getconnections(prompt.Triggered)) do
                if c.Function then table.insert(Steal.Data[prompt].trigger, c.Function) end
            end
        end
    end
    local data = Steal.Data[prompt]; if not data.ready then return end
    data.ready = false; State.isStealing = true; State.stealStartTime = tick()
    if Conns.progress then Conns.progress:Disconnect() end
    Conns.progress = RunService.Heartbeat:Connect(function()
        if not State.isStealing then Conns.progress:Disconnect(); Conns.progress = nil; return end
        local prog = math.clamp((tick() - State.stealStartTime) / Steal.StealDuration, 0, 1)
        if progressFill then progressFill.Size = UDim2.new(prog, 0, 1, 0) end
        if progressPct then progressPct.Text = math.floor(prog * 100) .. "%" end
    end)
    task.spawn(function()
        for _, fn in ipairs(data.hold) do task.spawn(fn) end
        task.wait(Steal.StealDuration)
        for _, fn in ipairs(data.trigger) do task.spawn(fn) end
        if Conns.progress then Conns.progress:Disconnect(); Conns.progress = nil end
        if progressFill then progressFill.Size = UDim2.new(0, 0, 1, 0) end
        if progressPct then progressPct.Text = "0%" end
        data.ready = true; State.isStealing = false
    end)
end
startAutoSteal = function()
    if Conns.autoSteal then return end
    Conns.autoSteal = RunService.Heartbeat:Connect(function()
        if not Steal.AutoStealEnabled or State.isStealing then return end
        local p = findNearestPrompt(); if p then executeSteal(p) end
    end)
end
stopAutoSteal = function()
    if Conns.autoSteal then Conns.autoSteal:Disconnect(); Conns.autoSteal = nil end
    if Conns.progress then Conns.progress:Disconnect(); Conns.progress = nil end
    Steal.AutoStealEnabled = false; State.isStealing = false
    Steal.plotCache = {}; Steal.plotCacheTime = {}; Steal.cachedPrompts = {}
    if progressFill then progressFill.Size = UDim2.new(0, 0, 1, 0) end
    if progressPct then progressPct.Text = "0%" end
end
-- Saved positions for moveable mode (persists across rebuilds)
-- _btnSavedPos[idx] = UDim2 absolute position for each button (when individually draggable)
-- _btnSavedPos.containerPos = UDim2 for the whole container (normal mode)
local _btnSavedPos = {}
-- Auto Save
local _autoSaveCooldown = false
local function autoSave()
    if not hasFileFuncs() then return end
    if _autoSaveCooldown then return end
    _autoSaveCooldown = true
    task.delay(0.3, function()
        _autoSaveCooldown = false
        pcall(function()
            local bindsSafe = {}
            for action, b in pairs(Binds) do
                bindsSafe[action] = {
                    key = (type(b.key) == "string") and b.key or "",
                    pad = (type(b.pad) == "string") and b.pad or "",
                }
            end
            local cfg = {
                normalSpeed = State.normalSpeed, carrySpeed = State.carrySpeed, laggerSpeed = State.laggerSpeed, oxgSpeed = State.oxgSpeed,
                autoStealEnabled = Steal.AutoStealEnabled, grabRadius = Steal.StealRadius, stealDuration = Steal.StealDuration,
                infJump = State.infJumpEnabled, infJumpMode = State.infJumpMode, antiRagdoll = State.antiRagdollEnabled,
                fpsBoost = State.fpsBoostEnabled, brainrotReturnEnabled = State.brainrotReturnEnabled,
                animEnabled = State.animEnabled,
                carrySpeedActive = State.carrySpeedActive,
                laggerModeEnabled = State.laggerModeEnabled, oxgModeEnabled = State.oxgModeEnabled, jumpVelocity = State.jumpVelocity, uiLocked = State.uiLocked,
                batCounterEnabled = State.batCounterEnabled,
                desyncEnabled = State.desyncEnabled,
                medusaCounterEnabled = State.medusaCounterEnabled,
                batAimbotEnabled = State.batAimbotEnabled,
                batAimbotAutoDrop = State.batAimbotAutoDrop,
                batAimbotMeleeOffset = State.batAimbotMeleeOffset,
                tpDownEnabled = State.tpDownEnabled,
                dropBREnabled = State.dropBREnabled,
                autoLeftEnabled = State.autoLeftEnabled,
                autoRightEnabled = State.autoRightEnabled,
                fovValue = State.fovValue,
                autoTPEnabled = State.autoTPEnabled,
                autoTPHeight = State.autoTPHeight,
                accentTheme = State.accentTheme,
                quickBtnSize = State.quickBtnSize,
                moveableMode = State.moveableMode,
                quickLocked = State.quickLocked,
                binds = bindsSafe,
                btnSavedPos = (function()
                    local posData = {}
                    -- Save container position
                    if _btnSavedPos.containerPos then
                        posData.containerPos = {
                            xs = _btnSavedPos.containerPos.X.Scale,
                            xo = _btnSavedPos.containerPos.X.Offset,
                            ys = _btnSavedPos.containerPos.Y.Scale,
                            yo = _btnSavedPos.containerPos.Y.Offset,
                        }
                    end
                    -- Save individual button positions (moveable mode)
                    for i = 1, 8 do
                        if _btnSavedPos[i] then
                            posData["btn"..i] = {
                                xs = _btnSavedPos[i].X.Scale,
                                xo = _btnSavedPos[i].X.Offset,
                                ys = _btnSavedPos[i].Y.Scale,
                                yo = _btnSavedPos[i].Y.Offset,
                            }
                        end
                    end
                    return posData
                end)(),
            }
            safeWriteFile("FearDuelConfig.json", HttpService:JSONEncode(cfg))
        end)
    end)
end
local _loadedCfg = nil
local function loadConfigData()
    if not hasFileFuncs() then return end
    local data = safeReadFile("FearDuelConfig.json")
    if not data then return end
    local ok, cfg = pcall(function() return HttpService:JSONDecode(data) end)
    if not ok or not cfg then return end
    _loadedCfg = cfg
    if cfg.normalSpeed and type(cfg.normalSpeed) == "number" then State.normalSpeed = cfg.normalSpeed end
    if cfg.carrySpeed and type(cfg.carrySpeed) == "number" then State.carrySpeed = cfg.carrySpeed end
    if cfg.laggerSpeed and type(cfg.laggerSpeed) == "number" then State.laggerSpeed = cfg.laggerSpeed end
    if cfg.oxgSpeed and type(cfg.oxgSpeed) == "number" then State.oxgSpeed = cfg.oxgSpeed end
    if cfg.jumpVelocity and type(cfg.jumpVelocity) == "number" then State.jumpVelocity = math.clamp(cfg.jumpVelocity, 1, 500) end
    if cfg.infJumpMode == "manual" or cfg.infJumpMode == "hold" then State.infJumpMode = cfg.infJumpMode end
    if syncInfJumpChips then syncInfJumpChips() end

    if cfg.grabRadius and type(cfg.grabRadius) == "number" then Steal.StealRadius = cfg.grabRadius end
    if cfg.stealDuration and type(cfg.stealDuration) == "number" then Steal.StealDuration = math.clamp(cfg.stealDuration, 0.05, 5) end
    if cfg.infJump then State.infJumpEnabled = true end
    if cfg.antiRagdoll then State.antiRagdollEnabled = true end
    if cfg.fpsBoost then State.fpsBoostEnabled = true end
    if cfg.brainrotReturnEnabled then State.brainrotReturnEnabled = true end
    if cfg.animEnabled then State.animEnabled = true end
    if cfg.carrySpeedActive then State.carrySpeedActive = true end
    if cfg.laggerModeEnabled then State.laggerModeEnabled = true end
    if cfg.oxgModeEnabled then State.oxgModeEnabled = true end

    if cfg.uiLocked ~= nil then State.uiLocked = cfg.uiLocked end
    if cfg.batCounterEnabled then State.batCounterEnabled = true end
    if cfg.desyncEnabled then State.desyncEnabled = true end
    if cfg.medusaCounterEnabled then State.medusaCounterEnabled = true end
    if cfg.batAimbotAutoDrop ~= nil then State.batAimbotAutoDrop = cfg.batAimbotAutoDrop end
    if cfg.batAimbotMeleeOffset and type(cfg.batAimbotMeleeOffset) == "number" then State.batAimbotMeleeOffset = cfg.batAimbotMeleeOffset end
    if cfg.batAimbotEnabled then
        State.batAimbotEnabled = true
        startBatAimbot()
    end
    if cfg.tpDownEnabled then
        State.tpDownEnabled = true
        startTpDown()
    end
    if cfg.fovValue and type(cfg.fovValue) == "number" then
        State.fovValue = math.clamp(cfg.fovValue, 10, 180)
        applyFOV()
    end
    if cfg.dropBREnabled then
        State.dropBREnabled = true
        startDropBR()
    end
    -- Load Auto TP settings
    if cfg.autoTPEnabled ~= nil then
        State.autoTPEnabled = cfg.autoTPEnabled
        if State.autoTPEnabled then startAutoTP() else stopAutoTP() end
    end
    if cfg.autoTPHeight and type(cfg.autoTPHeight) == "number" then
        State.autoTPHeight = cfg.autoTPHeight
    end
    if cfg.accentTheme and type(cfg.accentTheme) == "string" then
        applyTheme(getThemeByName(cfg.accentTheme))
    end
    if cfg.quickBtnSize and type(cfg.quickBtnSize) == "number" then
        State.quickBtnSize = math.clamp(math.floor(cfg.quickBtnSize), 30, 150)
    end
    if cfg.moveableMode ~= nil then State.moveableMode = cfg.moveableMode end
    if cfg.quickLocked ~= nil then State.quickLocked = cfg.quickLocked end
    -- Load saved button positions (moveable mode)
    if cfg.btnSavedPos and type(cfg.btnSavedPos) == "table" then
        local pd = cfg.btnSavedPos
        if pd.containerPos and type(pd.containerPos) == "table" then
            local xo = pd.containerPos.xo or 0
            local yo = pd.containerPos.yo or 0
            -- Discard if saved position is clearly off-screen (e.g. from old tab layout)
            local screenW = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X or 1920
            local screenH = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y or 1080
            if xo > -screenW and xo < screenW and yo > -screenH and yo < screenH then
                _btnSavedPos.containerPos = UDim2.new(
                    pd.containerPos.xs or 1, xo,
                    pd.containerPos.ys or 0.5, yo
                )
            end
            -- else leave nil so rebuildQuickButtons uses the default position
        end
        for i = 1, 8 do
            local key = "btn"..i
            if pd[key] and type(pd[key]) == "table" then
                _btnSavedPos[i] = UDim2.new(
                    pd[key].xs or 1, pd[key].xo or 0,
                    pd[key].ys or 0.5, pd[key].yo or 0
                )
            end
        end
    end
    -- Load binds (fixed: validate types, guard nulls, and strip reserved gamepad buttons)
    if cfg.binds and type(cfg.binds) == "table" then
        for action, v in pairs(cfg.binds) do
            if Binds[action] and type(v) == "table" then
                local k = v.key
                local p = v.pad
                local savedKey = (type(k) == "string" and k ~= "" and k ~= "null") and k or nil
                local padVal = (type(p) == "string" and p ~= "" and p ~= "null") and p or nil
                -- Only overwrite default if a real saved value exists
                if savedKey ~= nil then Binds[action].key = savedKey end
                if padVal ~= nil then
                    local reservedPadButtons = { ButtonA=true, ButtonSelect=true, ButtonStart=true, ButtonR3=true }
                    Binds[action].pad = (not reservedPadButtons[padVal]) and padVal or nil
                end
            end
        end
    end
end
-- ========== QUICK ACTION BUTTONS ==========
-- ========== QUICK ACTION BUTTONS HELPERS & THEME SYNC ==========
local function getQuickButtonColors()
    local theme = State.accentTheme or "Midnight"
    theme = theme:lower()
    
    local color = Color3.fromRGB(255, 255, 255) -- default white
    if theme:find("red") or theme:find("crimson") then
        color = Color3.fromRGB(255, 100, 100)
    elseif theme:find("rose") or theme:find("pink") or theme:find("candy") then
        color = Color3.fromRGB(255, 140, 200)
    elseif theme:find("green") or theme:find("plant") or theme:find("emerald") then
        color = Color3.fromRGB(100, 210, 150)
    elseif theme:find("blue") or theme:find("sky") or theme:find("indigo") then
        color = Color3.fromRGB(100, 160, 255)
    elseif theme:find("purple") or theme:find("violet") then
        color = Color3.fromRGB(170, 130, 255)
    elseif theme:find("amber") or theme:find("yellow") then
        color = Color3.fromRGB(255, 200, 50)
    end
    return color
end

local function syncVisualAccentTheme(windUIThemeName)
    local mapped = "Gray"
    local name = windUIThemeName:lower()
    if name:find("rose") or name:find("pink") or name:find("candy") then
        mapped = "Pink"
    elseif name:find("red") or name:find("crimson") then
        mapped = "Red"
    elseif name:find("green") or name:find("plant") or name:find("emerald") then
        mapped = "Green"
    elseif name:find("blue") or name:find("sky") or name:find("indigo") then
        mapped = "Blue"
    elseif name:find("purple") or name:find("violet") then
        mapped = "Purple"
    elseif name:find("cyan") then
        mapped = "Cyan"
    elseif name:find("white") or name:find("light") then
        mapped = "White"
    end
    applyTheme(getThemeByName(mapped))
end

-- ========== QUICK ACTION BUTTONS ==========
local quickPanel
local quickBtnFrames_global = {} -- track individual button panels for cleanup
local btnFrames, btnButtons, btnWasDragged = {}, {}, {}

local function rebuildQuickButtons()
    local QW, QH, QG = State.quickBtnSize, State.quickBtnSize, 8
    local _btnCorner = math.max(8, math.floor(QW * 0.21))
    local _btnTextSize = math.max(9, math.floor(QW * 0.168))
    local C_BTN = Color3.fromRGB(0, 0, 0)
    local C_BTN_ON = getQuickButtonColors()
    local C_BTN_TEXT = Color3.fromRGB(255, 255, 255)

    -- Separate ScreenGui for Quick Action buttons so they remain visible when main UI toggles
    local gui = LP.PlayerGui:FindFirstChild("FearDuelQuickButtonsGui")
    if not gui then
        gui = Instance.new("ScreenGui")
        gui.Name = "FearDuelQuickButtonsGui"
        gui.ResetOnSpawn = false
        gui.DisplayOrder = 101
        gui.IgnoreGuiInset = true
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.Parent = LP.PlayerGui
    end

    -- Fade out and destroy old container
    local oldContainer = gui:FindFirstChild("QuickBtnContainer")
    if oldContainer then
        TweenService:Create(oldContainer, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {BackgroundTransparency = 1}):Play()
        for _, child in ipairs(oldContainer:GetDescendants()) do
            if child:IsA("Frame") or child:IsA("TextButton") or child:IsA("TextLabel") then
                pcall(function()
                    TweenService:Create(child, TweenInfo.new(0.18), {BackgroundTransparency = 1}):Play()
                    if child:IsA("TextButton") or child:IsA("TextLabel") then
                        TweenService:Create(child, TweenInfo.new(0.18), {TextTransparency = 1}):Play()
                    end
                end)
            end
        end
        task.delay(0.2, function() pcall(function() oldContainer:Destroy() end) end)
    end

    -- Clean up old tracked frames
    for _, f in ipairs(quickBtnFrames_global) do
        pcall(function() f:Destroy() end)
    end
    quickBtnFrames_global = {}
    if quickPanel then quickPanel:Destroy(); quickPanel = nil end
    local oldBg = gui:FindFirstChild("QuickActionsBg")
    if oldBg then oldBg:Destroy() end

    local CONT_PAD = 10
    local CONT_W = QW * 2 + QG + CONT_PAD * 2
    local CONT_H = QH * 4 + QG * 3 + CONT_PAD * 2

    -- Saved container position persists across rebuilds
    if not _btnSavedPos.containerPos then
        _btnSavedPos.containerPos = UDim2.new(1, -(CONT_W + 60), 0.5, -CONT_H / 2)
    end

    local btnContainer = Instance.new("Frame", gui)
    btnContainer.Name = "QuickBtnContainer"
    btnContainer.Size = UDim2.new(0, CONT_W, 0, CONT_H)
    btnContainer.Position = _btnSavedPos.containerPos
    btnContainer.BorderSizePixel = 0
    btnContainer.ZIndex = 25
    btnContainer.Active = true  -- Enabled for dragging
    btnContainer.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
    btnContainer.BackgroundTransparency = 0.6
    Instance.new("UICorner", btnContainer).CornerRadius = UDim.new(0, 10)
    local btnContStroke = Instance.new("UIStroke", btnContainer)
    btnContStroke.Color = Color3.fromRGB(55, 55, 65)
    btnContStroke.Thickness = 1.2

    if State.moveableMode then
        btnContainer.BackgroundTransparency = 1
        btnContStroke.Transparency = 1
    else
        btnContainer.BackgroundTransparency = 0.6
        btnContStroke.Transparency = 0
    end

    -- Background image on quick buttons panel (subtle)
    local qbBgImg = Instance.new("ImageLabel", btnContainer)
    qbBgImg.Name = "QBBackgroundImage"
    qbBgImg.Size = UDim2.new(1, 0, 1, 0)
    qbBgImg.Position = UDim2.new(0, 0, 0, 0)
    qbBgImg.BackgroundTransparency = 1
    qbBgImg.Image = "rbxassetid://112977078041259"
    qbBgImg.ScaleType = Enum.ScaleType.Crop
    qbBgImg.ImageTransparency = State.moveableMode and 1 or 0.35
    qbBgImg.ZIndex = 24
    Instance.new("UICorner", qbBgImg).CornerRadius = UDim.new(0, 10)

    local qbLocked = State.quickLocked

    local _qbDragging, _qbDragStart, _qbStartPos = false, nil, nil
    btnContainer.InputBegan:Connect(function(inp)
        if qbLocked then return end
        if inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseButton1 then
            _qbDragging = true
            _qbDragStart = inp.Position
            _qbStartPos = btnContainer.Position
            inp.Changed:Connect(function()
                if inp.UserInputState == Enum.UserInputState.End then _qbDragging = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(inp)
        if not _qbDragging then return end
        if inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseMovement then
            local dx = inp.Position.X - _qbDragStart.X
            local dy = inp.Position.Y - _qbDragStart.Y
            local newPos = UDim2.new(
                _qbStartPos.X.Scale, _qbStartPos.X.Offset + dx,
                _qbStartPos.Y.Scale, _qbStartPos.Y.Offset + dy
            )
            btnContainer.Position = newPos
            _btnSavedPos.containerPos = newPos
            autoSave()
        end
    end)

    local function makeDraggableButton(label, idx)
        local col = (idx - 1) % 2
        local row = math.floor((idx - 1) / 2)
        local defaultOffX = CONT_PAD + col * (QW + QG)
        local defaultOffY = CONT_PAD + row * (QH + QG)

        local parent = State.moveableMode and gui or btnContainer
        local f = Instance.new("Frame", parent)
        f.Name = "QuickBtn_" .. idx
        f.Size = UDim2.new(0, QW, 0, QH)
        f.BorderSizePixel = 0
        f.Active = false
        f.ZIndex = 30
        Instance.new("UICorner", f).CornerRadius = UDim.new(0, _btnCorner)

        if State.moveableMode then
            if _btnSavedPos[idx] then
                f.Position = _btnSavedPos[idx]
            else
                local containerAbsX = _btnSavedPos.containerPos.X.Offset
                local containerAbsY = _btnSavedPos.containerPos.Y.Offset
                f.Position = UDim2.new(
                    _btnSavedPos.containerPos.X.Scale,
                    containerAbsX + defaultOffX,
                    _btnSavedPos.containerPos.Y.Scale,
                    containerAbsY + defaultOffY
                )
            end
            f.BackgroundColor3 = C_BTN
            f.BackgroundTransparency = 0

            local btn = Instance.new("TextButton", f)
            btn.Size = UDim2.new(1, 0, 1, 0)
            btn.BackgroundTransparency = 1
            btn.Text = label
            btn.TextColor3 = C_BTN_TEXT
            btn.Font = Enum.Font.GothamBlack
            btn.TextSize = _btnTextSize
            btn.TextWrapped = true
            btn.AutoButtonColor = false
            btn.Selectable = false
            btn.ZIndex = 34
            btn.TextXAlignment = Enum.TextXAlignment.Center

            local dragging, dragStart, startPos = false, nil, nil
            local wasDragged = false
            btn.InputBegan:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseButton1 then
                    dragging = true
                    wasDragged = false
                    dragStart = inp.Position
                    startPos = f.Position
                    inp.Changed:Connect(function()
                        if inp.UserInputState == Enum.UserInputState.End then
                            dragging = false
                        end
                    end)
                end
            end)
            UIS.InputChanged:Connect(function(inp)
                if not dragging then return end
                if State.quickLocked then return end
                if inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseMovement then
                    local dx = inp.Position.X - dragStart.X
                    local dy = inp.Position.Y - dragStart.Y
                    if math.abs(dx) > 6 or math.abs(dy) > 6 then
                        wasDragged = true
                    end
                    local newPos = UDim2.new(startPos.X.Scale, startPos.X.Offset + dx, startPos.Y.Scale, startPos.Y.Offset + dy)
                    f.Position = newPos
                    _btnSavedPos[idx] = newPos
                    autoSave()
                end
            end)
            table.insert(quickBtnFrames_global, f)

            return f, btn, function() return wasDragged end
        else
            f.Position = UDim2.new(0, defaultOffX, 0, defaultOffY)
            f.BackgroundColor3 = C_BTN
            f.BackgroundTransparency = 0

            local btn = Instance.new("TextButton", f)
            btn.Size = UDim2.new(1, 0, 1, 0)
            btn.BackgroundTransparency = 1
            btn.Text = label
            btn.TextColor3 = C_BTN_TEXT
            btn.Font = Enum.Font.GothamBlack
            btn.TextSize = _btnTextSize
            btn.TextWrapped = true
            btn.AutoButtonColor = false
            btn.Selectable = false
            btn.ZIndex = 34
            btn.TextXAlignment = Enum.TextXAlignment.Center

            table.insert(quickBtnFrames_global, f)
            return f, btn, function() return false end
        end
    end

    local function makeButton(label, idx)
        return makeDraggableButton(label, idx)
    end

    local function setButtonState(frame, button, isOn)
        if isOn then
            TweenService:Create(frame, TweenInfo.new(0.1), {BackgroundColor3 = C_BTN_ON, BackgroundTransparency = 0}):Play()
            TweenService:Create(button, TweenInfo.new(0.1), {TextColor3 = Color3.fromRGB(0, 0, 0)}):Play()
        else
            TweenService:Create(frame, TweenInfo.new(0.15), {BackgroundColor3 = C_BTN, BackgroundTransparency = 0}):Play()
            TweenService:Create(button, TweenInfo.new(0.15), {TextColor3 = Color3.fromRGB(255, 255, 255)}):Play()
        end
    end

    -- btn1 = DROP BR (one-shot)
    -- btn2 = AUTO LEFT
    -- btn3 = BAT AIMBOT
    -- btn4 = AUTO RIGHT
    -- btn5 = CARRY SPEED
    -- btn6 = LAGGER MODE
    -- btn7 = TP DOWN
    -- btn8 = INSTA RESET
    btnFrames[1], btnButtons[1], btnWasDragged[1] = makeButton("DROP\nBR", 1)
    btnFrames[2], btnButtons[2], btnWasDragged[2] = makeButton("AUTO\nLEFT", 2)
    btnFrames[3], btnButtons[3], btnWasDragged[3] = makeButton("BAT\nAIMBOT", 3)
    btnFrames[4], btnButtons[4], btnWasDragged[4] = makeButton("AUTO\nRIGHT", 4)
    _autoLeftBtnFrame  = btnFrames[2]
    _autoRightBtnFrame = btnFrames[4]
    btnFrames[5], btnButtons[5], btnWasDragged[5] = makeButton("CARRY\nSPEED", 5)
    btnFrames[6], btnButtons[6], btnWasDragged[6] = makeButton("LAGGER\nMODE", 6)
    btnFrames[7], btnButtons[7], btnWasDragged[7] = makeButton("TP\nDOWN", 7)
    btnFrames[8], btnButtons[8], btnWasDragged[8] = makeButton("INSTA\nRESET", 8)

    btnButtons[1].Activated:Connect(function()
        if btnWasDragged[1]() then return end
        _G._fearGuiClickActive = true; task.delay(0.1, function() _G._fearGuiClickActive = false end)
        if dropBRToggle then
            dropBRToggle:Set(true)
        else
            State.dropBREnabled = true
            dropBrainrotNow()
            State.dropBREnabled = false
            stopDropBR()
        end
    end)

    btnButtons[2].Activated:Connect(function()
        if btnWasDragged[2]() then return end
        _G._fearGuiClickActive = true; task.delay(0.1, function() _G._fearGuiClickActive = false end)
        if autoLeftToggle then
            autoLeftToggle:Set(not State.autoLeftEnabled)
        else
            State.autoLeftEnabled = not State.autoLeftEnabled
            if State.autoLeftEnabled then startAutoLeft() else stopAutoLeft() end
            setButtonState(btnFrames[2], btnButtons[2], State.autoLeftEnabled)
        end
        autoSave()
    end)

    btnButtons[3].Activated:Connect(function()
        if btnWasDragged[3]() then return end
        _G._fearGuiClickActive = true; task.delay(0.1, function() _G._fearGuiClickActive = false end)
        if batAimbotToggle then
            batAimbotToggle:Set(not State.batAimbotEnabled)
        else
            State.batAimbotEnabled = not State.batAimbotEnabled
            if State.batAimbotEnabled then startBatAimbot() else stopBatAimbot() end
            setButtonState(btnFrames[3], btnButtons[3], State.batAimbotEnabled)
        end
        autoSave()
    end)

    btnButtons[4].Activated:Connect(function()
        if btnWasDragged[4]() then return end
        _G._fearGuiClickActive = true; task.delay(0.1, function() _G._fearGuiClickActive = false end)
        if autoRightToggle then
            autoRightToggle:Set(not State.autoRightEnabled)
        else
            State.autoRightEnabled = not State.autoRightEnabled
            if State.autoRightEnabled then startAutoRight() else stopAutoRight() end
            setButtonState(btnFrames[4], btnButtons[4], State.autoRightEnabled)
        end
        autoSave()
    end)

    btnButtons[5].Activated:Connect(function()
        if btnWasDragged[5]() then return end
        _G._fearGuiClickActive = true; task.delay(0.1, function() _G._fearGuiClickActive = false end)
        if carrySpeedToggle then
            carrySpeedToggle:Set(not State.carrySpeedActive)
        else
            State.carrySpeedActive = not State.carrySpeedActive
            setButtonState(btnFrames[5], btnButtons[5], State.carrySpeedActive)
        end
        autoSave()
    end)

    btnButtons[6].Activated:Connect(function()
        if btnWasDragged[6]() then return end
        _G._fearGuiClickActive = true; task.delay(0.1, function() _G._fearGuiClickActive = false end)
        if laggerModeToggle then
            laggerModeToggle:Set(not State.laggerModeEnabled)
        else
            State.laggerModeEnabled = not State.laggerModeEnabled
            setButtonState(btnFrames[6], btnButtons[6], State.laggerModeEnabled)
        end
        autoSave()
    end)

    btnButtons[7].Activated:Connect(function()
        if btnWasDragged[7]() then return end
        _G._fearGuiClickActive = true; task.delay(0.1, function() _G._fearGuiClickActive = false end)
        if tpDownToggle then
            tpDownToggle:Set(true)
        else
            tpDownNow()
        end
    end)

    btnButtons[8].Activated:Connect(function()
        if btnWasDragged[8]() then return end
        _G._fearGuiClickActive = true; task.delay(0.1, function() _G._fearGuiClickActive = false end)
        doInstaReset()
        TweenService:Create(btnFrames[8], TweenInfo.new(0.1), {BackgroundColor3 = C_BTN_ON, BackgroundTransparency = 0}):Play()
        task.delay(0.4, function()
            TweenService:Create(btnFrames[8], TweenInfo.new(0.15), {BackgroundColor3 = C_BTN, BackgroundTransparency = 0}):Play()
        end)
    end)

    -- Export setters for TP Down / Drop BR button visuals
    setTpDown = function(on) setButtonState(btnFrames[7], btnButtons[7], on) end
    setDropBR = function(on) setButtonState(btnFrames[1], btnButtons[1], on) end

    -- Sync initial visuals
    setButtonState(btnFrames[1], btnButtons[1], State.dropBREnabled)
    setButtonState(btnFrames[2], btnButtons[2], State.autoLeftEnabled)
    setButtonState(btnFrames[3], btnButtons[3], State.batAimbotEnabled)
    setButtonState(btnFrames[4], btnButtons[4], State.autoRightEnabled)
    setButtonState(btnFrames[5], btnButtons[5], State.carrySpeedActive)
    setButtonState(btnFrames[6], btnButtons[6], State.laggerModeEnabled)
end

-- ========== HOTKEY HANDLER ==========
local function setupHotkeys()
    local function doAction(action)
        if action == "tpDown" then
            if tpDownToggle then
                tpDownToggle:Set(true)
            else
                tpDownNow()
            end
        elseif action == "dropBR" then
            if dropBRToggle then
                dropBRToggle:Set(true)
            else
                State.dropBREnabled = true
                dropBrainrotNow()
                State.dropBREnabled = false
                stopDropBR()
            end
        elseif action == "autoLeft" then
            if autoLeftToggle then
                autoLeftToggle:Set(not State.autoLeftEnabled)
            else
                State.autoLeftEnabled = not State.autoLeftEnabled
                if State.autoLeftEnabled then startAutoLeft() else stopAutoLeft() end
            end
        elseif action == "autoRight" then
            if autoRightToggle then
                autoRightToggle:Set(not State.autoRightEnabled)
            else
                State.autoRightEnabled = not State.autoRightEnabled
                if State.autoRightEnabled then startAutoRight() else stopAutoRight() end
            end
        elseif action == "batAimbot" then
            if batAimbotToggle then
                batAimbotToggle:Set(not State.batAimbotEnabled)
            else
                State.batAimbotEnabled = not State.batAimbotEnabled
                if State.batAimbotEnabled then startBatAimbot() else stopBatAimbot() end
            end
        elseif action == "manualDrop" then
            dropBrainrotNow()
        elseif action == "manualTpDown" then
            tpDownNow()
        elseif action == "carrySpeed" then
            if carrySpeedToggle then
                carrySpeedToggle:Set(not State.carrySpeedActive)
            else
                State.carrySpeedActive = not State.carrySpeedActive
            end
        elseif action == "laggerMode" then
            if laggerModeToggle then
                laggerModeToggle:Set(not State.laggerModeEnabled)
            else
                State.laggerModeEnabled = not State.laggerModeEnabled
            end
        elseif action == "oxgMode" then
            if oxgModeToggle then
                oxgModeToggle:Set(not State.oxgModeEnabled)
            else
                State.oxgModeEnabled = not State.oxgModeEnabled
            end
        elseif action == "instaGrab" then
            if autoStealToggle then
                autoStealToggle:Set(not Steal.AutoStealEnabled)
            else
                Steal.AutoStealEnabled = not Steal.AutoStealEnabled
                if Steal.AutoStealEnabled then pcall(startAutoSteal) else stopAutoSteal() end
            end
        elseif action == "infJump" then
            if infJumpToggle then
                infJumpToggle:Set(not State.infJumpEnabled)
            else
                State.infJumpEnabled = not State.infJumpEnabled
            end
        elseif action == "instaReset" then
            doInstaReset()
        elseif action == "duelLagger" then
            if State._toggleDuelLaggerFn then State._toggleDuelLaggerFn() end
        elseif action == "batCounter" then
            if batCounterToggle then
                batCounterToggle:Set(not State.batCounterEnabled)
            else
                State.batCounterEnabled = not State.batCounterEnabled
            end
        end
        autoSave()
    end

    -- Keyboard input (skip when bind overlay is active)
    UIS.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if _G._fearBindOverlayActive then return end
        if _G._fearGuiClickActive then return end
        local keyName = input.KeyCode.Name
        for action, b in pairs(Binds) do
            if b.key and b.key == keyName then
                doAction(action)
            end
        end
    end)

    -- Controller / gamepad input (skip when bind overlay is active)
    UIS.InputBegan:Connect(function(input, gameProcessed)
        if _G._fearBindOverlayActive then return end
        if _G._fearGuiClickActive then return end
        if input.UserInputType ~= Enum.UserInputType.Gamepad1 then return end
        -- NOTE: do NOT check gameProcessed here — Roblox always marks gamepad buttons
        -- as gameProcessed=true, which would silently block every controller bind
        local padName = input.KeyCode.Name
        for action, b in pairs(Binds) do
            if b.pad and b.pad == padName then
                doAction(action)
            end
        end
    end)
end
-- ========== MAIN UI ==========
local function rebuildUI()
    -- Apply saved theme color mappings
    syncVisualAccentTheme(State.accentTheme or "Gray")

    -- Destroy old WindUI if it exists
    pcall(function()
        if Window then
            Window:Destroy()
        end
    end)

    -- Create Window
    Window = WindUI:CreateWindow({
        Title = "Fear Duels",
        Author = "by fearduels.cc",
        Folder = "FearDuels",
        Icon = "solar:folder-2-bold-duotone",
        NewElements = true,
        HideSearchBar = false,
        OpenButton = {
            Title = "Open Fear Duels UI",
            CornerRadius = UDim.new(1, 0),
            StrokeThickness = 3,
            Enabled = true,
            Draggable = true,
            OnlyMobile = false,
            Scale = 0.5,
            Color = ColorSequence.new(
                Color3.fromHex("#ffffff"),
                Color3.fromHex("#888888")
            ),
        },
        Topbar = {
            Height = 44,
            ButtonsType = "Mac",
        },
    })

    -- Set UI Scale initially
    Window:SetUIScale(State.guiScale or 1.0)
    Window:SetToggleKey(Enum.KeyCode.RightShift) -- Default toggle key

    -- Sidebar Sections
    local MainSection = Window:Section({ Title = "Combat & Movement" })
    local SettingsSection = Window:Section({ Title = "Settings & Binds" })

    -- ==================== STEAL TAB ====================
    local StealTab = MainSection:Tab({ Title = "Steal", Icon = "solar:cursor-square-bold", Border = true })

    autoStealToggle = StealTab:Toggle({
        Title = "Auto Steal",
        Desc = "Automatically steal brainrots from podiums",
        Value = Steal.AutoStealEnabled,
        Callback = function(on)
            Steal.AutoStealEnabled = on
            if on then
                pcall(startAutoSteal)
            else
                stopAutoSteal()
            end
            autoSave()
        end
    })

    StealTab:Space()

    local radiusSlider = StealTab:Slider({
        Title = "Steal Radius",
        Desc = "Range for auto-stealing prompts",
        Step = 1,
        Value = { Min = 5, Max = 300, Default = Steal.StealRadius },
        Callback = function(v)
            Steal.StealRadius = math.floor(v)
            Steal.cachedPrompts = {}
            Steal.promptCacheTime = 0
            autoSave()
        end
    })

    StealTab:Space()

    local durationSlider = StealTab:Slider({
        Title = "Steal Duration (s)",
        Desc = "Time required to steal a prompt",
        Step = 0.05,
        Value = { Min = 0.05, Max = 2.0, Default = Steal.StealDuration },
        Callback = function(v)
            Steal.StealDuration = v
            autoSave()
        end
    })

    setInstaGrab = function(on) autoStealToggle:Set(on) end
    setGrabRadius = function(v) radiusSlider:Set(v) end
    setStealDuration = function(v) durationSlider:Set(v) end

    -- ==================== BYPASS TAB ====================
    local BypassTab = MainSection:Tab({ Title = "Bypass", Icon = "solar:shield-bold", Border = true })
    local BypassGroup = BypassTab:Group({})

    -- 1. Fear Speed Bypass Section
    local BypassSection = BypassGroup:Section({
        Title = "Fear Speed Bypass",
        Desc = "Speed bypass settings",
        Box = true,
        BoxBorder = true,
        Opened = false
    })

    local bypassPower = 10000
    local bypassLagAmount = 0.12
    local bypassLagConn = nil
    local bypassActivated = false
    local bypassKeybind = Enum.KeyCode.E

    local function bypassApplyPower(val)
        bypassPower = math.clamp(val, 10000, 500000)
        local t2 = (bypassPower - 10000) / 490000
        bypassLagAmount = t2 * 0.2
    end

    local function bypassStartLag()
        if bypassLagConn then bypassLagConn:Disconnect() end
        bypassLagConn = RunService.Heartbeat:Connect(function()
            if not bypassActivated then return end
            if bypassLagAmount > 0 then
                local t2 = tick()
                while tick() - t2 < bypassLagAmount do end
            end
        end)
    end

    local function bypassStopLag()
        bypassActivated = false
        if bypassLagConn then bypassLagConn:Disconnect(); bypassLagConn = nil end
    end

    local function bypassToggle(on)
        if on then
            bypassActivated = true
            bypassStartLag()
        else
            bypassStopLag()
        end
    end

    local bypassPowerSlider = BypassSection:Slider({
        Title = "Power",
        Step = 1000,
        Value = { Min = 10000, Max = 500000, Default = bypassPower },
        Callback = function(v)
            bypassApplyPower(v)
        end
    })

    BypassSection:Space()

    local bypassKeybindElement = BypassSection:Keybind({
        Title = "Toggle Key",
        Value = "E",
        Callback = function(v)
            bypassKeybind = Enum.KeyCode[v]
        end
    })

    BypassSection:Space()

    local bypassToggleElement = BypassSection:Toggle({
        Title = "Activate Bypass",
        Value = false,
        Callback = function(on)
            bypassToggle(on)
        end
    })

    UIS.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == bypassKeybind then
            local targetState = not bypassActivated
            bypassToggleElement:Set(targetState)
        end
    end)

    LP.CharacterAdded:Connect(function()
        task.wait(1)
        if bypassActivated then
            bypassStopLag()
            bypassActivated = true
            bypassStartLag()
        end
    end)

    -- 2. Insta Reset Section
    local ResetSection = BypassGroup:Section({
        Title = "Insta Reset",
        Desc = "Instant character reset utilities",
        Box = true,
        BoxBorder = true,
        Opened = false
    })

    ResetSection:Button({
        Title = "Reset Character",
        Color = Color3.fromHex("#ff4830"),
        Justify = "Center",
        Callback = function()
            doInstaReset()
        end
    })

    -- 3. Open Anti Section
    local AntiSection = BypassGroup:Section({
        Title = "FearAphex Anti Panel",
        Desc = "Anti bypass systems",
        Box = true,
        BoxBorder = true,
        Opened = false
    })

    local infJumpActive = false
    local infJumpSession2 = 0
    local lastBurstTime2 = 0
    local HOLD_INTERVAL2 = 0.055
    local infJumpRenderConn2 = nil
    local touchJumpHeld2 = false

    local infJumpRay2 = RaycastParams.new()
    infJumpRay2.FilterType = Enum.RaycastFilterType.Exclude

    local function infJumpFloorStandY2(r, hum, char)
        infJumpRay2.FilterDescendantsInstances = { char }
        local hit = workspace:Raycast(r.Position + Vector3.new(0, 2.25, 0), Vector3.new(0, -200, 0), infJumpRay2)
        if not hit then return nil, nil end
        local floorY = hit.Position.Y
        local standY = floorY + hum.HipHeight + r.Size.Y * 0.5 + 0.12
        return standY, floorY
    end

    local function infJumpCorrectSink2(r, hum, char, floorY, standY)
        if not floorY or not standY then return end
        if r.Position.Y >= floorY + 0.35 then return end
        r.CFrame = CFrame.new(r.Position.X, standY, r.Position.Z) * (r.CFrame - r.CFrame.Position)
        local v = r.AssemblyLinearVelocity
        r.AssemblyLinearVelocity = Vector3.new(v.X, math.max(0, v.Y), v.Z)
    end

    local function isJumpHeld2()
        if UIS:IsKeyDown(Enum.KeyCode.Space) then return true end
        local ok, down = pcall(function() return UIS:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA) end)
        if ok and down then return true end
        return touchJumpHeld2
    end

    local function doInfJumpBurst2()
        if not infJumpActive then return end
        local char = LP.Character
        if not char then return end
        local hrp2 = char:FindFirstChild("HumanoidRootPart")
        local hum2 = char:FindFirstChildOfClass("Humanoid")
        if not hrp2 or not hum2 or hum2.Health <= 0 then return end
        infJumpSession2 = infJumpSession2 + 1
        local session = infJumpSession2
        local jy = 50
        if hum2.UseJumpPower and hum2.JumpPower > 0 then
            jy = hum2.JumpPower
        else
            local jh = hum2.JumpHeight
            if type(jh) == "number" and jh > 0 then
                jy = math.sqrt(math.max(0, 2 * workspace.Gravity * jh))
            end
        end
        jy = math.clamp(jy, 35, 95)
        local standY, floorY = infJumpFloorStandY2(hrp2, hum2, char)
        infJumpCorrectSink2(hrp2, hum2, char, floorY, standY)
        local v0 = hrp2.AssemblyLinearVelocity
        hrp2.AssemblyLinearVelocity = Vector3.new(v0.X, math.max(v0.Y * 0.15, jy), v0.Z)
        local postSim = RunService.PostSimulation
        local waitPhys = (postSim and function() postSim:Wait() end) or function() RunService.Heartbeat:Wait() end
        task.spawn(function()
            local c = char; local boost = jy
            for i = 1, 10 do
                waitPhys()
                if session ~= infJumpSession2 or LP.Character ~= c or not infJumpActive then break end
                local r2 = c:FindFirstChild("HumanoidRootPart")
                local h2 = c:FindFirstChildOfClass("Humanoid")
                if not r2 or not h2 or h2.Health <= 0 then break end
                local sy, fy = infJumpFloorStandY2(r2, h2, c)
                infJumpCorrectSink2(r2, h2, c, fy, sy)
                if i > 2 and h2.FloorMaterial ~= Enum.Material.Air then break end
                local vel = r2.AssemblyLinearVelocity
                if vel.Y < boost * 0.72 then
                    r2.AssemblyLinearVelocity = Vector3.new(vel.X, math.min(boost, math.max(vel.Y + boost * 0.42, boost * 0.72)), vel.Z)
                end
            end
        end)
    end

    local function startInfJumpHandler2()
        if infJumpRenderConn2 then return end
        infJumpRenderConn2 = RunService.RenderStepped:Connect(function()
            if not infJumpActive then return end
            if not isJumpHeld2() then return end
            local now = tick()
            if now - lastBurstTime2 < HOLD_INTERVAL2 then return end
            lastBurstTime2 = now
            doInfJumpBurst2()
        end)
    end

    local function stopInfJumpHandler2()
        if infJumpRenderConn2 then infJumpRenderConn2:Disconnect(); infJumpRenderConn2 = nil end
        infJumpSession2 = infJumpSession2 + 1
        lastBurstTime2 = 0; touchJumpHeld2 = false
    end

    task.defer(function()
        local pg = LP:FindFirstChild("PlayerGui")
        if not pg then return end
        local function hookJumpBtn(btn)
            if not btn:IsA("GuiButton") or btn.Name ~= "JumpButton" or btn:GetAttribute("AntiPanelJumpHook") then return end
            btn:SetAttribute("AntiPanelJumpHook", true)
            btn.MouseButton1Down:Connect(function() touchJumpHeld2 = true end)
            btn.MouseButton1Up:Connect(function() touchJumpHeld2 = false end)
            btn.MouseLeave:Connect(function() touchJumpHeld2 = false end)
        end
        for _, d in ipairs(pg:GetDescendants()) do hookJumpBtn(d) end
        pg.DescendantAdded:Connect(hookJumpBtn)
    end)

    UIS.JumpRequest:Connect(function()
        if infJumpActive then lastBurstTime2 = tick(); doInfJumpBurst2() end
    end)

    AntiSection:Toggle({
        Title = "Inf Jump",
        Desc = "Bypassed Infinite Jump",
        Value = false,
        Callback = function(on)
            infJumpActive = on
            if on then
                startInfJumpHandler2()
            else
                stopInfJumpHandler2()
            end
        end
    })

    AntiSection:Space()

    local desyncToggle = AntiSection:Toggle({
        Title = "Raknet Desync",
        Desc = "Bypasses certain server authority checks",
        Value = State.desyncEnabled,
        Callback = function(on)
            State.desyncEnabled = on
            applyDesync(on)
            autoSave()
        end
    })

    -- 4. Cursed Lagger Section
    local LaggerSection = BypassGroup:Section({
        Title = "Cursed Lagger",
        Desc = "Spams remote events to lag server client-side",
        Box = true,
        BoxBorder = true,
        Opened = false
    })

    local LAGGER_CONFIG = { TableIncrease = 25, Tries = 1, LoopWaitTime = 1.2 }
    local CUSTOM_REMOTE_PATH = "RobloxReplicatedStorage.SetPlayerBlockList"

    local function resolveRemote(path)
        if not path or path == "" then return nil end
        local obj = game
        local cleaned = path:gsub("^game%.", "")
        for segment in cleaned:gmatch("[^%.]+") do
            if obj then obj = obj[segment] else return nil end
        end
        return obj
    end

    local function getmaxvalue(val)
        local mainvalueifonetable = 499999
        if type(val) ~= "number" then return nil end
        return mainvalueifonetable / (val + 2)
    end

    local function buildBombTable(tableincrease)
        local maintable = {}
        local spammedtable = {}
        table.insert(spammedtable, {})
        local z = spammedtable[1]
        for i = 1, tableincrease do
            local tableins = {}
            table.insert(z, tableins)
            z = tableins
        end
        local maximum = getmaxvalue(tableincrease) or 9999999
        for i = 1, maximum do
            table.insert(maintable, spammedtable)
            if i % 5000 == 0 then task.wait() end
        end
        return maintable
    end

    local preBuiltTable = nil
    local remoteInstance = nil
    local wlaggerEnabled = false
    local wlaggerThread = nil

    local function startLaggerLoop()
        if not preBuiltTable then
            preBuiltTable = buildBombTable(LAGGER_CONFIG.TableIncrease)
            remoteInstance = resolveRemote(CUSTOM_REMOTE_PATH)
        end
        while wlaggerEnabled do
            game:GetService("NetworkClient"):SetOutgoingKBPSLimit(math.huge)
            task.spawn(function()
                if remoteInstance then
                    pcall(function()
                        if remoteInstance:IsA("RemoteEvent") or remoteInstance:IsA("UnreliableRemoteEvent") then
                            remoteInstance:FireServer(preBuiltTable)
                        elseif remoteInstance:IsA("RemoteFunction") then
                            remoteInstance:InvokeServer(preBuiltTable)
                        end
                    end)
                end
            end)
            task.wait(math.max(LAGGER_CONFIG.LoopWaitTime, 0.15))
        end
    end

    local function stopLaggerLoop()
        wlaggerEnabled = false
        if wlaggerThread then coroutine.close(wlaggerThread); wlaggerThread = nil end
    end

    local function startLagger()
        if wlaggerThread then return end
        wlaggerEnabled = true
        wlaggerThread = coroutine.create(startLaggerLoop)
        coroutine.resume(wlaggerThread)
    end

    local laggerToggle = LaggerSection:Toggle({
        Title = "Release Lagger",
        Value = false,
        Callback = function(on)
            if on then
                startLagger()
            else
                stopLaggerLoop()
            end
        end
    })
    State._toggleDuelLaggerFn = function() laggerToggle:Set(not wlaggerEnabled) end

    -- 5. Brainrot Return Section
    local ReturnSection = BypassGroup:Section({
        Title = "Brainrot Return",
        Desc = "Teleports back to base side when hit or ragdolled",
        Box = true,
        BoxBorder = true,
        Opened = false
    })

    local returnToggle = ReturnSection:Toggle({
        Title = "Enable Return",
        Value = State.brainrotReturnEnabled,
        Callback = function(on)
            State.brainrotReturnEnabled = on
            if on then
                resetBaseSide()
                detectBaseSideAsync(function(side)
                    State.brainrotReturnSide = (side == "right") and "left" or "right"
                end)
            end
            autoSave()
        end
    })

    -- ==================== MOVEMENT TAB ====================
    local MovementTab = MainSection:Tab({ Title = "Movement", Icon = "solar:square-transfer-horizontal-bold", Border = true })

    local normalSpeedSlider = MovementTab:Slider({
        Title = "Normal Speed",
        Step = 1,
        Value = { Min = 16, Max = 250, Default = State.normalSpeed },
        Callback = function(v)
            State.normalSpeed = v
            autoSave()
        end
    })

    MovementTab:Space()

    local carrySpeedSlider = MovementTab:Slider({
        Title = "Carry Speed",
        Step = 1,
        Value = { Min = 16, Max = 250, Default = State.carrySpeed },
        Callback = function(v)
            State.carrySpeed = v
            autoSave()
        end
    })

    MovementTab:Space()

    local laggerSpeedSlider = MovementTab:Slider({
        Title = "Lagger Speed",
        Step = 1,
        Value = { Min = 16, Max = 250, Default = State.laggerSpeed },
        Callback = function(v)
            State.laggerSpeed = v
            autoSave()
        end
    })

    MovementTab:Space()

    local jumpVelocitySlider = MovementTab:Slider({
        Title = "Jump Velocity",
        Step = 1,
        Value = { Min = 16, Max = 250, Default = State.jumpVelocity },
        Callback = function(v)
            State.jumpVelocity = v
            autoSave()
        end
    })

    MovementTab:Space()

    local oxgSpeedSlider = MovementTab:Slider({
        Title = "OXG Speed",
        Step = 1,
        Value = { Min = 16, Max = 250, Default = State.oxgSpeed },
        Callback = function(v)
            State.oxgSpeed = v
            autoSave()
        end
    })

    MovementTab:Space()

    oxgModeToggle = MovementTab:Toggle({
        Title = "OXG Mode",
        Value = State.oxgModeEnabled,
        Callback = function(on)
            State.oxgModeEnabled = on
            autoSave()
        end
    })

    MovementTab:Space()

    autoLeftToggle = MovementTab:Toggle({
        Title = "Auto Left",
        Value = State.autoLeftEnabled,
        Callback = function(on)
            if on then
                if State.batAimbotEnabled and batAimbotToggle then batAimbotToggle:Set(false) end
                if State.autoRightEnabled and autoRightToggle then autoRightToggle:Set(false) end
                startAutoLeft()
            else
                stopAutoLeft()
            end
            if btnFrames[2] and btnButtons[2] then
                setButtonState(btnFrames[2], btnButtons[2], on)
            end
            autoSave()
        end
    })

    MovementTab:Space()

    autoRightToggle = MovementTab:Toggle({
        Title = "Auto Right",
        Value = State.autoRightEnabled,
        Callback = function(on)
            if on then
                if State.batAimbotEnabled and batAimbotToggle then batAimbotToggle:Set(false) end
                if State.autoLeftEnabled and autoLeftToggle then autoLeftToggle:Set(false) end
                startAutoRight()
            else
                stopAutoRight()
            end
            if btnFrames[4] and btnButtons[4] then
                setButtonState(btnFrames[4], btnButtons[4], on)
            end
            autoSave()
        end
    })

    MovementTab:Space()

    batAimbotToggle = MovementTab:Toggle({
        Title = "Bat Aimbot",
        Value = State.batAimbotEnabled,
        Callback = function(on)
            State.batAimbotEnabled = on
            if on then
                if State.autoLeftEnabled and autoLeftToggle then autoLeftToggle:Set(false) end
                if State.autoRightEnabled and autoRightToggle then autoRightToggle:Set(false) end
                if State.batAimbotAutoDrop then
                    dropBrainrotActive = false
                    State.dropBREnabled = true
                    dropBrainrotNow()
                    task.delay(0.3, function() State.dropBREnabled = false; stopDropBR() end)
                end
                startBatAimbot()
            else
                stopBatAimbot()
            end
            if btnFrames[3] and btnButtons[3] then
                setButtonState(btnFrames[3], btnButtons[3], on)
            end
            autoSave()
        end
    })

    MovementTab:Space()

    local batAimbotAutoDropToggle = MovementTab:Toggle({
        Title = "Aimbot Auto Drop",
        Desc = "Automatically drops brainrot when Bat Aimbot is enabled",
        Value = State.batAimbotAutoDrop or false,
        Callback = function(on)
            State.batAimbotAutoDrop = on
            autoSave()
        end
    })

    MovementTab:Space()

    local aimbotOffsetSlider = MovementTab:Slider({
        Title = "Aimbot Melee Offset",
        Desc = "Distance to stay behind target",
        Step = 0.5,
        Value = { Min = 0, Max = 10, Default = State.batAimbotMeleeOffset },
        Callback = function(v)
            State.batAimbotMeleeOffset = v
            autoSave()
        end
    })

    MovementTab:Space()

    carrySpeedToggle = MovementTab:Toggle({
        Title = "Carry Speed Active",
        Value = State.carrySpeedActive,
        Callback = function(on)
            State.carrySpeedActive = on
            if on and State.laggerModeEnabled and laggerModeToggle then
                laggerModeToggle:Set(false)
            end
            if btnFrames[5] and btnButtons[5] then
                setButtonState(btnFrames[5], btnButtons[5], on)
            end
            autoSave()
        end
    })

    MovementTab:Space()

    laggerModeToggle = MovementTab:Toggle({
        Title = "Lagger Speed Active",
        Value = State.laggerModeEnabled,
        Callback = function(on)
            State.laggerModeEnabled = on
            if on and State.carrySpeedActive and carrySpeedToggle then
                carrySpeedToggle:Set(false)
            end
            if btnFrames[6] and btnButtons[6] then
                setButtonState(btnFrames[6], btnButtons[6], on)
            end
            autoSave()
        end
    })

    MovementTab:Space()

    tpDownToggle = MovementTab:Toggle({
        Title = "TP Down",
        Value = State.tpDownEnabled,
        Callback = function(on)
            if on then
                tpDownNow()
                State.tpDownEnabled = false
                task.defer(function()
                    tpDownToggle:Set(false)
                end)
            else
                State.tpDownEnabled = false
                stopTpDown()
            end
            autoSave()
        end
    })

    MovementTab:Space()

    dropBRToggle = MovementTab:Toggle({
        Title = "Drop BR",
        Value = State.dropBREnabled,
        Callback = function(on)
            if on then
                State.dropBREnabled = true
                startDropBR()
                dropBrainrotNow()
                State.dropBREnabled = false
                stopDropBR()
                task.defer(function()
                    dropBRToggle:Set(false)
                end)
            else
                State.dropBREnabled = false
                stopDropBR()
            end
            autoSave()
        end
    })

    MovementTab:Space()

    local autoTPToggle = MovementTab:Toggle({
        Title = "Auto TP (fall TP)",
        Value = State.autoTPEnabled,
        Callback = function(on)
            State.autoTPEnabled = on
            if on then
                startAutoTP()
            else
                stopAutoTP()
            end
            autoSave()
        end
    })

    MovementTab:Space()

    local autoTPHeightSlider = MovementTab:Slider({
        Title = "Auto TP Height",
        Step = 1,
        Value = { Min = 1, Max = 200, Default = State.autoTPHeight },
        Callback = function(v)
            State.autoTPHeight = math.floor(v)
            autoSave()
        end
    })

    setNormalSpeed = function(v) normalSpeedSlider:Set(v) end
    setCarrySpeed = function(v) carrySpeedSlider:Set(v) end
    setLaggerSpeed = function(v) laggerSpeedSlider:Set(v) end
    setOxgMode = function(on) oxgModeToggle:Set(on) end
    setAutoLeft = function(on) autoLeftToggle:Set(on) end
    setAutoRight = function(on) autoRightToggle:Set(on) end
    setBatAimbot = function(on) batAimbotToggle:Set(on) end
    setCarrySpeedActive = function(on) carrySpeedToggle:Set(on) end
    setLaggerModeActive = function(on) laggerModeToggle:Set(on) end
    setTpDown = function(on) tpDownToggle:Set(on) end
    setDropBR = function(on) dropBRToggle:Set(on) end
    setAutoTP = function(on) autoTPToggle:Set(on) end
    setAutoTPHeight = function(v) autoTPHeightSlider:Set(v) end
    setAimbotOffset = function(v) aimbotOffsetSlider:Set(v) end
    setBatAimbotAutoDrop = function(on) batAimbotAutoDropToggle:Set(on) end

    -- ==================== EXTRAS TAB ====================
    local ExtrasTab = MainSection:Tab({ Title = "Extras", Icon = "solar:info-square-bold", Border = true })

    infJumpToggle = ExtrasTab:Toggle({
        Title = "Inf Jump",
        Value = State.infJumpEnabled,
        Callback = function(on)
            State.infJumpEnabled = on
            autoSave()
        end
    })

    ExtrasTab:Space()

    antiRagToggle = ExtrasTab:Toggle({
        Title = "Anti Ragdoll",
        Value = State.antiRagdollEnabled,
        Callback = function(on)
            State.antiRagdollEnabled = on
            if on then
                startAntiRagdoll()
            else
                stopAntiRagdoll()
            end
            autoSave()
        end
    })

    ExtrasTab:Space()

    local infJumpModeDropdown = ExtrasTab:Dropdown({
        Title = "Inf Jump Mode",
        Values = { "manual", "hold" },
        Value = State.infJumpMode,
        Callback = function(v)
            State.infJumpMode = v
            autoSave()
        end
    })

    ExtrasTab:Space()

    fpsBoostToggle = ExtrasTab:Toggle({
        Title = "FPS Boost",
        Value = State.fpsBoostEnabled,
        Callback = function(on)
            State.fpsBoostEnabled = on
            if on then
                pcall(applyFPSBoost)
            end
            autoSave()
        end
    })

    ExtrasTab:Space()

    animToggle = ExtrasTab:Toggle({
        Title = "Tryhard Anim",
        Value = State.animEnabled,
        Callback = function(on)
            State.animEnabled = on
            if on then
                startAnimToggle()
            else
                stopAnimToggle()
            end
            autoSave()
        end
    })

    ExtrasTab:Space()

    local medusaCounterToggle = ExtrasTab:Toggle({
        Title = "Medusa Counter",
        Value = State.medusaCounterEnabled,
        Callback = function(on)
            State.medusaCounterEnabled = on
            if on then
                if LP.Character then setupMedusa(LP.Character) end
            else
                stopMedusaCounter()
            end
            autoSave()
        end
    })

    ExtrasTab:Space()

    local unwalkToggle = ExtrasTab:Toggle({
        Title = "Unwalk",
        Value = State.unwalkEnabled,
        Callback = function(on)
            State.unwalkEnabled = on
            if on then
                startUnwalk()
            else
                stopUnwalk()
            end
            autoSave()
        end
    })

    ExtrasTab:Space()

    local batCounterToggle = ExtrasTab:Toggle({
        Title = "Bat Counter",
        Desc = "Automatically targets attackers with a bat/slap tool on ragdoll",
        Value = State.batCounterEnabled,
        Callback = function(on)
            State.batCounterEnabled = on
            autoSave()
        end
    })

    ExtrasTab:Space()

    local rmAccsToggle = ExtrasTab:Toggle({
        Title = "Remove Accessories",
        Value = false,
        Callback = function(on)
            if on then
                for _, p in pairs(Players:GetPlayers()) do
                    if p.Character then
                        for _, obj in ipairs(p.Character:GetDescendants()) do
                            if obj:IsA("Accessory") or obj:IsA("Hat") then
                                pcall(function() obj:Destroy() end)
                            end
                        end
                    end
                end
                task.defer(function()
                    rmAccsToggle:Set(false)
                end)
            end
        end
    })

    ExtrasTab:Space()

    local darkModeToggle = ExtrasTab:Toggle({
        Title = "Dark Mode",
        Value = false,
        Callback = function(on)
            if on then
                enableDarkMode()
            else
                disableDarkMode()
            end
        end
    })

    setInfJump = function(on) infJumpToggle:Set(on) end
    setAntiRag = function(on) antiRagToggle:Set(on) end
    setFps = function(on) fpsBoostToggle:Set(on) end
    setAnimToggle = function(on) animToggle:Set(on) end
    setMedusaCounter = function(on) medusaCounterToggle:Set(on) end
    setBatCounter = function(on) batCounterToggle:Set(on) end
    setDesync = function(on) desyncToggle:Set(on) end
    setBrainrotReturn = function(on) returnToggle:Set(on) end
    syncInfJumpChips = function() infJumpModeDropdown:Select({ State.infJumpMode }) end

    -- ==================== DISPLAY TAB ====================
    local DisplayTab = SettingsSection:Tab({ Title = "Display", Icon = "solar:home-2-bold", Border = true })

    local mainGUISizeDropdown = DisplayTab:Dropdown({
        Title = "Main GUI Size",
        Values = { "Small", "Medium", "Large" },
        Value = (State.guiScale == 0.75 and "Small" or (State.guiScale == 1.2 and "Large" or "Medium")),
        Callback = function(val)
            if val == "Small" then
                State.guiScale = 0.75
            elseif val == "Large" then
                State.guiScale = 1.2
            else
                State.guiScale = 1.0
            end
            Window:SetUIScale(State.guiScale)
            autoSave()
        end
    })

    DisplayTab:Space()

    local moveableModeToggle = DisplayTab:Toggle({
        Title = "Right Buttons Moveable",
        Value = State.moveableMode,
        Callback = function(on)
            State.moveableMode = on
            autoSave()
            rebuildQuickButtons()
        end
    })

    DisplayTab:Space()

    local quickBtnSizeSlider = DisplayTab:Slider({
        Title = "Button Size",
        Step = 5,
        Value = { Min = 30, Max = 150, Default = State.quickBtnSize },
        Callback = function(v)
            State.quickBtnSize = math.clamp(math.floor(v), 30, 150)
            rebuildQuickButtons()
            autoSave()
        end
    })

    DisplayTab:Space()

    local lockBtnPositionsToggle = DisplayTab:Toggle({
        Title = "Lock Button Positions",
        Value = State.quickLocked,
        Callback = function(on)
            State.quickLocked = on
            autoSave()
        end
    })

    DisplayTab:Space()

    DisplayTab:Button({
        Title = "Reset Button Positions",
        Color = Color3.fromHex("#EF4F1D"), -- Red
        Justify = "Center",
        Callback = function()
            for i = 1, 8 do
                _btnSavedPos[i] = nil
            end
            _btnSavedPos.containerPos = nil
            autoSave()
            rebuildQuickButtons()
            WindUI:Notify({ Title = "Quick Buttons", Content = "Positions reset!" })
        end
    })

    -- ==================== CONFIG TAB ====================
    local ConfigTab = SettingsSection:Tab({ Title = "Configuration", Icon = "solar:folder-with-files-bold", Border = true })

    local cameraFOVSlider = ConfigTab:Slider({
        Title = "Camera FOV",
        Step = 1,
        Value = { Min = 10, Max = 180, Default = State.fovValue },
        Callback = function(v)
            State.fovValue = v
            applyFOV()
            autoSave()
        end
    })

    ConfigTab:Space()

    local lockUIToggle = ConfigTab:Toggle({
        Title = "Lock UI",
        Value = State.uiLocked,
        Callback = function(on)
            State.uiLocked = on
            autoSave()
        end
    })

    ConfigTab:Space()

    local themeDropdown = ConfigTab:Dropdown({
        Title = "Select UI Theme",
        Values = (function()
            local names = {}
            for name in pairs(WindUI:GetThemes()) do
                table.insert(names, name)
            end
            table.sort(names)
            return names
        end)(),
        Value = WindUI:GetCurrentTheme(),
        Callback = function(selected)
            WindUI:SetTheme(selected)
            State.accentTheme = selected
            syncVisualAccentTheme(selected)
            rebuildQuickButtons()
            autoSave()
        end
    })

    setFovSlider = function(v) cameraFOVSlider:Set(v) end
    setLockUI = function(on) lockUIToggle:Set(on) end

    -- ==================== BINDS TAB ====================
    local BindsTab = SettingsSection:Tab({ Title = "Keybinds", Icon = "solar:password-minimalistic-input-bold", Border = true })
    local kbGroup = BindsTab:Group({ Title = "Keyboard Keybinds" })
    local padGroup = BindsTab:Group({ Title = "Gamepad / Controller Keybinds" })

    bindRowRefs = {}

    for _, action in ipairs(BIND_ORDER) do
        local label = BIND_LABELS[action]
        local currentBind = Binds[action]
        
        local kbElement = kbGroup:Keybind({
            Title = label,
            Value = currentBind.key or "None",
            Callback = function(v)
                if v == "Backspace" or v == "None" then
                    Binds[action].key = nil
                else
                    Binds[action].key = v
                end
                autoSave()
            end
        })
        
        local padElement = padGroup:Keybind({
            Title = label,
            Value = currentBind.pad or "None",
            Callback = function(v)
                if v == "DPadUp" or v == "None" then
                    Binds[action].pad = nil
                else
                    Binds[action].pad = v
                end
                autoSave()
            end
        })
        
        bindRowRefs[action] = {
            kb = kbElement,
            pad = padElement
        }
    end
end

local function applyGuiFromConfig()
    local cfg = _loadedCfg
    if not cfg then return end
    if setNormalSpeed and cfg.normalSpeed then setNormalSpeed(cfg.normalSpeed) end
    if setCarrySpeed and cfg.carrySpeed then setCarrySpeed(cfg.carrySpeed) end
    if setLaggerSpeed and cfg.laggerSpeed then setLaggerSpeed(cfg.laggerSpeed) end
    if setGrabRadius and cfg.grabRadius then setGrabRadius(cfg.grabRadius) end
    if setStealDuration and cfg.stealDuration then setStealDuration(math.clamp(cfg.stealDuration, 0.05, 5)) end
    if cfg.autoStealEnabled then Steal.AutoStealEnabled = true; pcall(startAutoSteal); if setInstaGrab then setInstaGrab(true) end end
    if cfg.infJump and setInfJump then setInfJump(true) end
    if cfg.antiRagdoll and setAntiRag then setAntiRag(true); startAntiRagdoll() end
    if cfg.fpsBoost and setFps then setFps(true); pcall(applyFPSBoost) end
    if cfg.brainrotReturnEnabled then
        State.brainrotReturnEnabled = true
        if setBrainrotReturn then setBrainrotReturn(true) end
    end
    if cfg.animEnabled and setAnimToggle then setAnimToggle(true); task.spawn(function() task.wait(0.5); startAnimToggle() end) end
    if cfg.carrySpeedActive then State.carrySpeedActive = true end
    if cfg.laggerModeEnabled then State.laggerModeEnabled = true end
    if cfg.oxgModeEnabled then State.oxgModeEnabled = true end
    if cfg.uiLocked ~= nil then State.uiLocked = cfg.uiLocked; if setLockUI then setLockUI(State.uiLocked) end end
    if cfg.desyncEnabled then
        State.desyncEnabled = true
        applyDesync(true)
        if setDesync then setDesync(true) end
    end
    if cfg.medusaCounterEnabled and setMedusaCounter then setMedusaCounter(true); if LP.Character then setupMedusa(LP.Character) end end
    if cfg.batCounterEnabled ~= nil and setBatCounter then setBatCounter(cfg.batCounterEnabled) end
    if cfg.batAimbotAutoDrop ~= nil and setBatAimbotAutoDrop then setBatAimbotAutoDrop(cfg.batAimbotAutoDrop) end
    if cfg.batAimbotMeleeOffset and setAimbotOffset then setAimbotOffset(cfg.batAimbotMeleeOffset) end
    if cfg.batAimbotEnabled and not State.batAimbotEnabled then
        State.batAimbotEnabled = true
        startBatAimbot()
    end
    if cfg.tpDownEnabled and setTpDown then setTpDown(true) end
    if cfg.dropBREnabled and setDropBR then setDropBR(true) end
    if cfg.autoLeftEnabled and setAutoLeft then setAutoLeft(true); startAutoLeft() end
    if cfg.autoRightEnabled and setAutoRight then setAutoRight(true); startAutoRight() end
    if cfg.fovValue and setFovSlider then setFovSlider(math.clamp(cfg.fovValue, 10, 180)) end
    -- Apply Auto TP settings
    if cfg.autoTPEnabled ~= nil and setAutoTP then
        State.autoTPEnabled = cfg.autoTPEnabled
        setAutoTP(State.autoTPEnabled)
        if State.autoTPEnabled then startAutoTP() else stopAutoTP() end
    end
    if cfg.autoTPHeight and setAutoTPHeight then
        State.autoTPHeight = cfg.autoTPHeight
        setAutoTPHeight(State.autoTPHeight)
    end
    -- Refresh bind elements in the Settings UI so loaded binds are visible
    for action, refs in pairs(bindRowRefs) do
        local b = Binds[action]
        if refs.kb then refs.kb:Set(b.key or "None") end
        if refs.pad then refs.pad:Set(b.pad or "None") end
    end
end
-- ========== INTRO SEQUENCE (Blue Bands) ==========
local INTRO_MUSIC_ID = "rbxassetid://119414415681261"
local INTRO_DURATION = 11

local introGui = Instance.new("ScreenGui")
introGui.Name = "FearDuelIntro"
introGui.ResetOnSpawn = false
introGui.DisplayOrder = 99999
introGui.IgnoreGuiInset = true
introGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
introGui.Parent = LP:WaitForChild("PlayerGui")

local introOverlay = Instance.new("Frame", introGui)
introOverlay.Size = UDim2.new(1, 0, 1, 0)
introOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
introOverlay.BackgroundTransparency = 1
introOverlay.BorderSizePixel = 0
introOverlay.ZIndex = 1

-- Music
local introSound = Instance.new("Sound", introOverlay)
introSound.SoundId = INTRO_MUSIC_ID
introSound.Volume = 0.85
introSound.Looped = false
task.spawn(function()
    task.wait(0.15)
    pcall(function()
        introSound.TimePosition = 45
        introSound:Play()
    end)
end)

-- Title split into two halves for slide-in effect
local introFear = Instance.new("TextLabel", introOverlay)
introFear.Size = UDim2.new(0.5, -10, 0, 60)
introFear.Position = UDim2.new(-1, 0, 0.5, -50)
introFear.BackgroundTransparency = 1
introFear.Text = "FEAR"
introFear.TextColor3 = Color3.fromRGB(255, 255, 255)
introFear.Font = Enum.Font.GothamBlack
introFear.TextSize = 32
introFear.TextXAlignment = Enum.TextXAlignment.Right
introFear.TextTransparency = 0
introFear.ZIndex = 2
introFear.TextStrokeTransparency = 0.6
introFear.TextStrokeColor3 = Color3.fromRGB(180, 180, 180)

local introDuels = Instance.new("TextLabel", introOverlay)
introDuels.Size = UDim2.new(0.5, -10, 0, 60)
introDuels.Position = UDim2.new(2, 0, 0.5, -50)
introDuels.BackgroundTransparency = 1
introDuels.Text = "DUELS"
introDuels.TextColor3 = Color3.fromRGB(255, 255, 255)
introDuels.Font = Enum.Font.GothamBlack
introDuels.TextSize = 32
introDuels.TextXAlignment = Enum.TextXAlignment.Left
introDuels.TextTransparency = 0
introDuels.ZIndex = 2
introDuels.TextStrokeTransparency = 0.6
introDuels.TextStrokeColor3 = Color3.fromRGB(180, 180, 180)

-- Subtitle label
local introSub = Instance.new("TextLabel", introOverlay)
introSub.Size = UDim2.new(1, 0, 0, 24)
introSub.Position = UDim2.new(0, 0, 0.5, 32)
introSub.BackgroundTransparency = 1
introSub.Text = "/fearduels"
introSub.TextColor3 = Color3.fromRGB(200, 200, 200)
introSub.Font = Enum.Font.GothamBold
introSub.TextSize = 15
introSub.TextXAlignment = Enum.TextXAlignment.Center
introSub.TextTransparency = 1
introSub.ZIndex = 2

-- Underline bar
local introLine = Instance.new("Frame", introOverlay)
introLine.Size = UDim2.new(0, 0, 0, 2)
introLine.Position = UDim2.new(0.5, 0, 0.5, 26)
introLine.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
introLine.BorderSizePixel = 0
introLine.ZIndex = 2

-- Animate intro in a separate thread; Initialize runs immediately after
task.spawn(function()
    -- Slide FEAR in from left + zoom out from small
    introFear.TextSize = 8
    TweenService:Create(introFear, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0, 0, 0.5, -50),
        TextSize = 32
    }):Play()
    -- Slide DUELS in from right + zoom out from small
    introDuels.TextSize = 8
    TweenService:Create(introDuels, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 10, 0.5, -50),
        TextSize = 32
    }):Play()
    task.wait(0.5)

    -- Expand underline
    local lineW = 300
    TweenService:Create(introLine, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, lineW, 0, 2),
        Position = UDim2.new(0.5, -lineW / 2, 0.5, 26),
    }):Play()

    -- Fade in subtitle
    TweenService:Create(introSub, TweenInfo.new(0.45), {TextTransparency = 0}):Play()

    -- Hold for the rest of the duration
    local elapsed = 0.5 + 0.45
    local remaining = INTRO_DURATION - elapsed
    if remaining > 0 then task.wait(remaining) end

    -- Slide back out opposite sides
    TweenService:Create(introFear, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Position = UDim2.new(-1, 0, 0.5, -50),
        TextSize = 8
    }):Play()
    TweenService:Create(introDuels, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Position = UDim2.new(2, 0, 0.5, -50),
        TextSize = 8
    }):Play()
    TweenService:Create(introSub, TweenInfo.new(0.4), {TextTransparency = 1}):Play()
    TweenService:Create(introLine, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Size = UDim2.new(0, 0, 0, 2),
        Position = UDim2.new(0.5, 0, 0.5, 26),
    }):Play()
    task.wait(0.45)
    pcall(function() introSound:Stop() end)
    introGui:Destroy()
end)

-- Initialize (runs right away, behind the intro overlay)
rebuildUI()
loadConfigData()
rebuildQuickButtons()
applyGuiFromConfig()
setupHotkeys()

-- Auto-enable grab on start
task.defer(function()
    Steal.AutoStealEnabled = true
    pcall(startAutoSteal)
    if setInstaGrab then setInstaGrab(true) end
end)

-- ========== AUTO STEAL PROGRESS WINDOW (fearduels_4 style) ==========
local stealProgressGui = (function()
    local SPG = {}
    local _oldSPG = LP.PlayerGui:FindFirstChild("StealProgressScreenGui")
    if _oldSPG then _oldSPG:Destroy() end
    local spScreenGui = Instance.new("ScreenGui")
    spScreenGui.Name = "StealProgressScreenGui"
    spScreenGui.ResetOnSpawn = false
    spScreenGui.DisplayOrder = 200
    spScreenGui.IgnoreGuiInset = true
    spScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    spScreenGui.Parent = LP.PlayerGui

    -- Main container — taller to fit FPS/ping row
    local spFrame = Instance.new("Frame", spScreenGui)
    spFrame.Name = "StealProgressGui"
    spFrame.Size = UDim2.new(0, 200, 0, 46)
    spFrame.Position = UDim2.new(0.5, -100, 1, -60)
    spFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
    spFrame.BackgroundTransparency = 0.05
    spFrame.BorderSizePixel = 0
    spFrame.Active = true
    spFrame.Visible = true
    spFrame.ZIndex = 300
    spFrame.ClipsDescendants = true

    local function mkC(p,r) local c=Instance.new("UICorner",p); c.CornerRadius=UDim.new(0,r or 8); return c end
    local function mkS(p,col,th) local s=Instance.new("UIStroke",p); s.Color=col; s.Thickness=th or 1; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; return s end
    mkC(spFrame, 0); mkS(spFrame, Color3.fromRGB(60, 60, 70), 1.5)

    -- Background image
    local spBgImg = Instance.new("ImageLabel", spFrame)
    spBgImg.Size = UDim2.new(1, 0, 1, 0)
    spBgImg.Position = UDim2.new(0, 0, 0, 0)
    spBgImg.BackgroundTransparency = 1
    spBgImg.Image = "rbxassetid://112977078041259"
    spBgImg.ScaleType = Enum.ScaleType.Crop
    spBgImg.ImageTransparency = 0.45
    spBgImg.ZIndex = 299
    mkC(spBgImg, 0)

    -- Draggable
    local spDragging, spDragStart, spStartPos = false, nil, nil
    spFrame.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            spDragging = true; spDragStart = inp.Position; spStartPos = spFrame.Position
            inp.Changed:Connect(function() if inp.UserInputState == Enum.UserInputState.End then spDragging = false end end)
        end
    end)
    UIS.InputChanged:Connect(function(inp)
        if not spDragging then return end
        if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
            local d = inp.Position - spDragStart
            spFrame.Position = UDim2.new(spStartPos.X.Scale, spStartPos.X.Offset + d.X, spStartPos.Y.Scale, spStartPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then spDragging = false end
    end)

    local spPct = Instance.new("TextLabel", spFrame)
    spPct.Size = UDim2.new(0.4, 0, 0, 22)
    spPct.Position = UDim2.new(0, 12, 0, 5)
    spPct.BackgroundTransparency = 1
    spPct.Text = "0%"
    spPct.TextColor3 = Color3.fromRGB(255, 255, 255)
    spPct.Font = Enum.Font.GothamBlack
    spPct.TextSize = 14
    spPct.TextXAlignment = Enum.TextXAlignment.Left
    spPct.ZIndex = 302

    local spRadiusLbl = Instance.new("TextLabel", spFrame)
    spRadiusLbl.Size = UDim2.new(0.58, 0, 0, 22)
    spRadiusLbl.Position = UDim2.new(0.42, 0, 0, 5)
    spRadiusLbl.BackgroundTransparency = 1
    spRadiusLbl.Text = "Radius: " .. tostring(Steal.StealRadius)
    spRadiusLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    spRadiusLbl.Font = Enum.Font.GothamBold
    spRadiusLbl.TextSize = 12
    spRadiusLbl.TextXAlignment = Enum.TextXAlignment.Right
    spRadiusLbl.ZIndex = 302

    -- FPS / Ping row
    local spFpsLbl = Instance.new("TextLabel", spFrame)
    spFpsLbl.Size = UDim2.new(0.5, 0, 0, 14)
    spFpsLbl.Position = UDim2.new(0, 12, 0, 24)
    spFpsLbl.BackgroundTransparency = 1
    spFpsLbl.Text = "FPS: --"
    spFpsLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    spFpsLbl.Font = Enum.Font.GothamBold
    spFpsLbl.TextSize = 11
    spFpsLbl.TextXAlignment = Enum.TextXAlignment.Left
    spFpsLbl.ZIndex = 302

    local spPingLbl = Instance.new("TextLabel", spFrame)
    spPingLbl.Size = UDim2.new(0.5, -14, 0, 14)
    spPingLbl.Position = UDim2.new(0.5, 0, 0, 24)
    spPingLbl.BackgroundTransparency = 1
    spPingLbl.Text = "PING: --"
    spPingLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    spPingLbl.Font = Enum.Font.GothamBold
    spPingLbl.TextSize = 11
    spPingLbl.TextXAlignment = Enum.TextXAlignment.Right
    spPingLbl.ZIndex = 302

    -- High ping warning overlay
    local pingWarnGui = Instance.new("ScreenGui", LP.PlayerGui)
    pingWarnGui.Name = "PingWarnOverlay"
    pingWarnGui.ResetOnSpawn = false
    pingWarnGui.DisplayOrder = 9999
    pingWarnGui.IgnoreGuiInset = true

    local pingWarnFrame = Instance.new("Frame", pingWarnGui)
    pingWarnFrame.Size = UDim2.new(1, 0, 1, 0)
    pingWarnFrame.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    pingWarnFrame.BackgroundTransparency = 1
    pingWarnFrame.BorderSizePixel = 0
    pingWarnFrame.ZIndex = 9999
    pingWarnFrame.Visible = false

    local pingWarnLbl = Instance.new("TextLabel", pingWarnFrame)
    pingWarnLbl.Size = UDim2.new(1, 0, 0, 60)
    pingWarnLbl.Position = UDim2.new(0, 0, 0.5, -30)
    pingWarnLbl.BackgroundTransparency = 1
    pingWarnLbl.Text = "⚠ WARNING HIGH PING ⚠"
    pingWarnLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    pingWarnLbl.Font = Enum.Font.GothamBlack
    pingWarnLbl.TextSize = 36
    pingWarnLbl.TextStrokeTransparency = 0
    pingWarnLbl.TextStrokeColor3 = Color3.fromRGB(180, 0, 0)
    pingWarnLbl.ZIndex = 10000

    local _pingWarnDone = false
    local function triggerPingWarning()
        if _pingWarnDone then return end
        _pingWarnDone = true
        pingWarnFrame.Visible = true
        task.spawn(function()
            local endTime = tick() + 3
            while tick() < endTime do
                TweenService:Create(pingWarnFrame, TweenInfo.new(0.25), {BackgroundTransparency = 0.6}):Play()
                task.wait(0.25)
                TweenService:Create(pingWarnFrame, TweenInfo.new(0.25), {BackgroundTransparency = 0.85}):Play()
                task.wait(0.25)
            end
            pingWarnFrame.Visible = false
            pingWarnFrame.BackgroundTransparency = 1
        end)
    end

    -- FPS/Ping update loop
    do
        local _spFpsTick = tick(); local _spFc = 0
        RunService.RenderStepped:Connect(function()
            _spFc = _spFc + 1
            local now = tick()
            if now - _spFpsTick >= 0.5 then
                local fps = math.round(_spFc / (now - _spFpsTick))
                _spFc = 0; _spFpsTick = now
                local ping = math.round(LP:GetNetworkPing() * 1000)
                spFpsLbl.Text = "FPS: " .. fps
                spPingLbl.Text = "PING: " .. ping .. "ms"
                if ping >= 100 then
                    triggerPingWarning()
                end
            end
        end)
    end

    -- Progress bar track (very thin: 3px)
    local spTrackBg = Instance.new("Frame", spFrame)
    spTrackBg.Size = UDim2.new(1, -20, 0, 2)
    spTrackBg.Position = UDim2.new(0, 10, 1, -8)
    spTrackBg.BackgroundColor3 = Color3.fromRGB(50, 50, 58)
    spTrackBg.BorderSizePixel = 0
    spTrackBg.ZIndex = 301
    mkC(spTrackBg, 2)

    -- Fill bar
    local spFill = Instance.new("Frame", spTrackBg)
    spFill.Size = UDim2.new(0, 0, 1, 0)
    spFill.BackgroundColor3 = Color3.fromRGB(210, 210, 225)
    spFill.BorderSizePixel = 0
    spFill.ZIndex = 302
    mkC(spFill, 2)

    local _lastPct = 0
    function SPG.update()
        if not spFrame.Visible then return end
        local pct = 0
        if State.isStealing and State.stealStartTime then
            local elapsed = tick() - State.stealStartTime
            pct = math.clamp(elapsed / math.max(Steal.StealDuration, 0.01), 0, 1)
        elseif Steal.AutoStealEnabled then
            local char = LP.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root and findNearestPrompt() then pct = 1 else pct = 0 end
        end
        _lastPct = _lastPct + (pct - _lastPct) * 0.2
        local display = math.floor(_lastPct * 100)
        spFill.Size = UDim2.new(math.clamp(_lastPct, 0, 1), 0, 1, 0)
        spPct.Text = display .. "%"
        -- Keep radius label live so it reflects any slider changes
        spRadiusLbl.Text = "Radius: " .. tostring(Steal.StealRadius)
    end
    function SPG.setVisible(v) spFrame.Visible = v end
    function SPG.isVisible() return spFrame.Visible end
    return SPG
end)()
-- Character setup
local function setupChar(char)
    task.wait(0.1); resetBaseSide(); originalAnims = nil
    detectBaseSideAsync(function(side)
        if State.brainrotReturnEnabled then State.brainrotReturnSide = (side == "right") and "left" or "right" end
    end)
    h = char:WaitForChild("Humanoid",5)
    hrp = char:WaitForChild("HumanoidRootPart",5)
    if not h or not hrp then return end
    State.lastKnownHealth = h.Health
    local head = char:FindFirstChild("Head")
    if head then
        local old = head:FindFirstChild("SpeedBillboard")
        if old then old:Destroy() end
        local bb = Instance.new("BillboardGui", head)
        bb.Name = "SpeedBillboard"; bb.Size = UDim2.new(0,140,0,25)
        bb.StudsOffset = Vector3.new(0,3,0); bb.AlwaysOnTop = true
        bb.ResetOnSpawn = false
        speedLbl = Instance.new("TextLabel", bb)
        speedLbl.Size = UDim2.new(1,0,0,25); speedLbl.BackgroundTransparency = 1
        speedLbl.TextColor3 = C_ACCENT2; speedLbl.Font = Enum.Font.GothamBold
        speedLbl.TextScaled = true; speedLbl.TextStrokeTransparency = 0
    end
    if State.antiRagdollEnabled and not Conns.antiRag then task.wait(0.5); startAntiRagdoll() end
    if State.animEnabled then task.wait(0.3); saveOriginalAnims(char); applyAnimPack(char) end
    if State.medusaCounterEnabled then setupMedusa(char) end
    if State.desyncEnabled then task.wait(0.2); applyDesync(true) end
    if State.autoLeftEnabled then task.wait(0.5); startAutoLeft() end
    if State.autoRightEnabled then task.wait(0.5); startAutoRight() end
    if State.batAimbotEnabled then
        task.wait(0.5)
        startBatAimbot()
    end
    if State.tpDownEnabled then
        task.wait(0.5)
        startTpDown()
        if setTpDown then setTpDown(true) end
    end
    if State.dropBREnabled then
        task.wait(0.5)
        startDropBR()
        if setDropBR then setDropBR(true) end
    end
    if State.unwalkEnabled then
        if unwalkConn then unwalkConn:Disconnect(); unwalkConn = nil end
        _unwalkAnimations = {}
        task.wait(0.3)
        startUnwalk()
    end
    -- Auto TP will be handled by the heartbeat connection, just ensure it's running
    if State.autoTPEnabled then
        if autoTPConn then stopAutoTP() end
        startAutoTP()
    end
end
LP.CharacterAdded:Connect(setupChar)
if LP.Character then task.spawn(function() setupChar(LP.Character) end) end

-- ========== ENEMY SPEED TRACKER ==========
local enemySpeedBBs = {} -- [player] = {bb, lbl, lastHRP, smooth}

local function getOrCreateEnemyBB(player)
    local char = player.Character
    if not char then return nil end
    local head = char:FindFirstChild("Head")
    local hrp2 = char:FindFirstChild("HumanoidRootPart")
    if not head or not hrp2 then return nil end

    local existing = enemySpeedBBs[player]
    if existing and existing.lastHRP ~= hrp2 then
        pcall(function() existing.bb:Destroy() end)
        enemySpeedBBs[player] = nil
        existing = nil
    end

    if not existing then
        local old = head:FindFirstChild("EnemySpeedBillboard")
        if old then old:Destroy() end
        local bb = Instance.new("BillboardGui", head)
        bb.Name = "EnemySpeedBillboard"
        bb.Size = UDim2.new(0, 140, 0, 25)
        bb.StudsOffset = Vector3.new(0, 3.6, 0)
        bb.AlwaysOnTop = true
        bb.ResetOnSpawn = false
        local lbl = Instance.new("TextLabel", bb)
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = Color3.fromRGB(0, 0, 0)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextScaled = true
        lbl.TextStrokeTransparency = 0
        enemySpeedBBs[player] = {bb = bb, lbl = lbl, lastHRP = hrp2, smooth = 0}
        existing = enemySpeedBBs[player]
    end
    return existing
end

local function cleanupEnemyBB(player)
    local d = enemySpeedBBs[player]
    if d then pcall(function() d.bb:Destroy() end) end
    enemySpeedBBs[player] = nil
end

Players.PlayerRemoving:Connect(cleanupEnemyBB)

RunService.Heartbeat:Connect(function()
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        local char = p.Character
        local hrp2 = char and char:FindFirstChild("HumanoidRootPart")
        if hrp2 then
            local d = getOrCreateEnemyBB(p)
            if d and d.lbl then
                local raw = Vector3.new(hrp2.AssemblyLinearVelocity.X, 0, hrp2.AssemblyLinearVelocity.Z).Magnitude
                d.smooth = (d.smooth or raw) * 0.6 + raw * 0.4
                d.lbl.Text = string.format("%.1f", d.smooth)
            end
        else
            cleanupEnemyBB(p)
        end
    end
end)
-- ========== FEAR USER TAG ==========
-- Mark this client so other Fear users can detect it
_G._fearUserTag = true

local FEAR_TAG_NAME = "FearUserTag"
local FEAR_TAG_COLOR = _activeTheme and _activeTheme.accent2 or Color3.fromRGB(180, 180, 200)

local function applyFearTag(char)
    if not char then return end
    local head = char:WaitForChild("Head", 5)
    if not head then return end
    local old = head:FindFirstChild(FEAR_TAG_NAME)
    if old then old:Destroy() end

    local bb = Instance.new("BillboardGui", head)
    bb.Name = FEAR_TAG_NAME
    bb.Size = UDim2.new(0, 240, 0, 44)
    bb.StudsOffset = Vector3.new(0, 2.6, 0)
    bb.AlwaysOnTop = false
    bb.ResetOnSpawn = false

    local lbl = Instance.new("TextLabel", bb)
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = "✦ /fearduels ✦"
    lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    lbl.Font = Enum.Font.GothamBlack
    lbl.TextSize = 20
    lbl.TextStrokeTransparency = 0
    lbl.TextStrokeColor3 = Color3.fromRGB(180, 180, 180)
    lbl.TextScaled = false

    -- Shiny white pulse effect
    task.spawn(function()
        local t = 0
        while lbl and lbl.Parent do
            t = t + 0.08
            local shine = 0.85 + math.sin(t * 3) * 0.15
            local v = math.floor(255 * shine)
            lbl.TextColor3 = Color3.fromRGB(v, v, v)
            lbl.TextStrokeColor3 = Color3.fromRGB(
                math.floor(160 * shine),
                math.floor(160 * shine),
                math.floor(160 * shine)
            )
            task.wait(0.03)
        end
    end)
end

local function removeFearTag(char)
    if not char then return end
    local head = char:FindFirstChild("Head")
    if not head then return end
    local tag = head:FindFirstChild(FEAR_TAG_NAME)
    if tag then tag:Destroy() end
end

local function checkAndTagPlayer(player)
    -- Poll _G._fearUserTag on the player's client via a shared _G check
    -- Since _G is per-VM this only works for players in the same executor context;
    -- we use an Attribute as a cross-client signal instead
    task.spawn(function()
        local char = player.Character or player.CharacterAdded:Wait()
        -- Give their script a moment to set the attribute
        task.wait(1.5)
        if player:GetAttribute("FearUser") then
            applyFearTag(char)
        end
        -- Also watch for it appearing later
        player:GetAttributeChangedSignal("FearUser"):Connect(function()
            if player:GetAttribute("FearUser") then
                applyFearTag(player.Character)
            else
                removeFearTag(player.Character)
            end
        end)
        -- Re-apply on respawn
        player.CharacterAdded:Connect(function(newChar)
            task.wait(1.5)
            if player:GetAttribute("FearUser") then
                applyFearTag(newChar)
            end
        end)
    end)
end

-- Broadcast that this local player is a Fear user via a replicated Attribute
LP:SetAttribute("FearUser", true)
-- Apply tag to own character too
LP.CharacterAdded:Connect(function(char)
    task.spawn(function()
        task.wait(0.5)
        applyFearTag(char)
    end)
end)
-- Self-apply with retry loop in case character isnt ready yet (Luarmor timing)
task.spawn(function()
    for _ = 1, 10 do
        local char = LP.Character
        if char then
            local head = char:FindFirstChild("Head")
            if head and not head:FindFirstChild(FEAR_TAG_NAME) then
                applyFearTag(char)
                break
            end
        end
        task.wait(0.5)
    end
end)

-- Check all current and future players
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LP then checkAndTagPlayer(p) end
end
Players.PlayerAdded:Connect(function(p)
    if p ~= LP then checkAndTagPlayer(p) end
end)
-- ========== FPS & PING GUI (removed) ==========
-- Infinite Jump
UIS.JumpRequest:Connect(function()
    if not State.infJumpEnabled then return end
    if State.infJumpMode ~= "manual" then return end
    local char = LP.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if root then
        local hum = char:FindFirstChildOfClass("Humanoid")
        local heldTool = nil
        for _, v in ipairs(char:GetChildren()) do
            if v:IsA("Tool") then heldTool = v break end
        end
        root.Velocity = Vector3.new(root.Velocity.X, State.jumpVelocity, root.Velocity.Z)
        if heldTool and hum then
            task.defer(function()
                if heldTool and heldTool.Parent ~= char then
                    hum:EquipTool(heldTool)
                end
            end)
        end
    end
end)
-- Movement (RenderStepped for smooth visuals)
local lastSpeed = 0
local _speedLblTick = 0
local _speedSmooth = 0
RunService.RenderStepped:Connect(function()
    if not (h and hrp) then return end
    if State._tplnProgress then return end
    if not State.autoLeftEnabled and not State.autoRightEnabled and not State.batAimbotEnabled then
        local md = h.MoveDirection
        local targetSpd
        if State.laggerModeEnabled then targetSpd = State.laggerSpeed
        elseif State.oxgModeEnabled then targetSpd = State.oxgSpeed
        elseif State.carrySpeedActive then targetSpd = State.carrySpeed
        else local useCarry = getMobileCarryState(); targetSpd = useCarry and State.carrySpeed or State.normalSpeed end
        local smoothFactor = 0.85
        lastSpeed = lastSpeed * smoothFactor + targetSpd * (1 - smoothFactor)
        local spd = lastSpeed
        if md.Magnitude > 0 then
            State.lastMoveDir = md
            hrp.Velocity = Vector3.new(md.X * spd, hrp.Velocity.Y, md.Z * spd)
        end
    end
    -- Speed label: rolling average of last 3 frames for stable but accurate reading
    if speedLbl then
        local vel = hrp.AssemblyLinearVelocity
        local raw = Vector3.new(vel.X, 0, vel.Z).Magnitude
        _speedSmooth = (_speedSmooth or raw) * 0.6 + raw * 0.4
        speedLbl.Text = string.format("%.1f", _speedSmooth)
    end
    -- Steal progress floating window update
    pcall(function() stealProgressGui.update() end)
end)
-- ========== MASTER HEARTBEAT (consolidated, replaces 3 separate always-on connections) ==========
RunService.Heartbeat:Connect(function()
    -- Inf jump
    if State.infJumpEnabled and State.infJumpMode == "hold" then
        local char = LP.Character
        if char then
            local root = char:FindFirstChild("HumanoidRootPart")
            local hum2 = char:FindFirstChildOfClass("Humanoid")
            if root and hum2 then
                local jumpHeld = UIS:IsKeyDown(Enum.KeyCode.Space)
                    or UIS:IsKeyDown(Enum.KeyCode.ButtonA)
                    or (hum2 and hum2.Jump)
                -- only boost when falling or near ground, not while still rising
                if jumpHeld and root.Velocity.Y < 38 then
                    root.Velocity = Vector3.new(root.Velocity.X, 38, root.Velocity.Z)
                end
            end
        end
    end
    -- Brainrot return
    if State.brainrotReturnEnabled and not State.brainrotReturnCooldown then
        local char = LP.Character
        if char then
            local hum2 = char:FindFirstChildOfClass("Humanoid")
            if hum2 then
                local cur = hum2.Health
                local wasHit = cur < State.lastKnownHealth - 5
                local st = hum2:GetState()
                local isRag = (st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.FallingDown)
                State.lastKnownHealth = cur
                if wasHit or isRag then
                    if State.brainrotReturnSide == "left" then doReturnTeleport(POS.RETURN_L)
                    elseif State.brainrotReturnSide == "right" then doReturnTeleport(POS.RETURN_R)
                    elseif not State._sideDetecting then
                        State._sideDetecting = true
                        detectBaseSideAsync(function(s)
                            State.brainrotReturnSide = (s == "right") and "left" or "right"
                            State._sideDetecting = false
                            doReturnTeleport(State.brainrotReturnSide == "left" and POS.RETURN_L or POS.RETURN_R)
                        end)
                    end
                end
            end
        end
    end
end)
detectBaseSideAsync(function(side)
    if State.brainrotReturnEnabled then State.brainrotReturnSide = (side == "right") and "left" or "right" end
end)


-- Print hotkey guide
print("========================================")
print("[Fear Duel] LOADED - CUSTOM BINDS ACTIVE")
print("========================================")
print("Go to Settings tab to assign keyboard")
print("and controller binds for each action.")
print("Binds save automatically.")
print("========================================")
