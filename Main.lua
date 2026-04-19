local BASE = "https://raw.githubusercontent.com/xLiqua/Anime-Ghosts/main/"

local function import(path)
    return loadstring(game:HttpGet(BASE .. path))()
end

local CustomUI = import("UI/CustomUI.lua")()
local ConfigManagerFactory = import("ConfigManager.lua")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local TextChatService = game:GetService("TextChatService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

-- Runs on every load: Roblox idle kick mitigation + Anime Ghosts AFK rejoin block (executor APIs).
local function setupAutomaticAntiAfk()
    if LocalPlayer then
        LocalPlayer.Idled:Connect(function()
            pcall(function()
                local cam = Workspace.CurrentCamera
                if cam then
                    VirtualUser:CaptureController()
                    VirtualUser:Button2Down(Vector2.new(0, 0), cam.CFrame)
                    task.wait(1)
                    VirtualUser:Button2Up(Vector2.new(0, 0), cam.CFrame)
                end
            end)
        end)
    end

    if type(getrawmetatable) ~= "function" or type(setreadonly) ~= "function" or type(getnamecallmethod) ~= "function" then
        print("Anime Ghosts anti-AFK: idle handler loaded (namecall hook needs executor APIs)")
        return
    end

    local ok, err = pcall(function()
        local mt = getrawmetatable(game)
        if not mt then
            error("getrawmetatable(game) returned nil")
        end
        local oldNamecall = mt.__namecall
        if type(oldNamecall) ~= "function" then
            error("__namecall is not a function")
        end
        local wrap = type(newcclosure) == "function" and newcclosure or function(f)
            return f
        end

        setreadonly(mt, false)
        mt.__namecall = wrap(function(self, ...)
            local args = { ... }
            if getnamecallmethod() == "FireServer" then
                if args[1] == "AFKSystem" and args[2] == "Rejoin" then
                    warn("Blocked Anime Ghosts AFK rejoin")
                    return
                end
            end
            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
    end)

    if ok then
        print("Roblox + Anime Ghosts anti AFK loaded")
    else
        warn("Anime Ghosts anti-AFK namecall hook failed:", err)
    end
end

setupAutomaticAntiAfk()

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local BridgeNet = ReplicatedStorage:WaitForChild("ffrostflame_bridgenet2@1.0.0"):WaitForChild("dataRemoteEvent")

local Window = CustomUI:CreateWindow({
    Name = "Anime Ghosts: Raid Tech V41 Modular",
    LoadingTitle = "Cyber-Electric Hub",
    LoadingSubtitle = "Stable High-Speed",
    ConfigurationSaving = { Enabled = false },
    DisableBuildWarnings = true
})

local enemyRoot = Workspace:WaitForChild("_ENEMIES")
local targetFolder = enemyRoot:WaitForChild("Client")
local serverFolder = enemyRoot:WaitForChild("Server")
local gamemodeFolder = serverFolder:WaitForChild("Gamemode")

local State = {
    window = Window,
    services = {
        Players = Players,
        ReplicatedStorage = ReplicatedStorage,
        Workspace = Workspace,
        HttpService = HttpService,
        LocalPlayer = LocalPlayer,
        PlayerGui = PlayerGui,
        BridgeNet = BridgeNet,
        enemyRoot = enemyRoot,
        targetFolder = targetFolder,
        serverFolder = serverFolder,
        gamemodeFolder = gamemodeFolder
    },

    raid = {
        autoRaidActive = false,
        autoEasterRaidActive = false,
        useRaidTicket = false,
        useEasterTicket = false,
        checkingRaid = false,
        normalCooldownEnd = 0,
        easterCooldownEnd = 0,
        handlingResults = false,
        launchingRaid = false,
        selectedMode = "TitanTown",
        selectedEasterMode = "ChocolateKingdom",
        hookedResults = setmetatable({}, { __mode = "k" }),
        generation = 0
    },

    infCastle = {
        autoInfCastleActive = false,
        checking = false,
        launching = false,
        handlingResults = false,
        hookedResults = setmetatable({}, { __mode = "k" }),
        generation = 0,
        serverCooldownEnd = 0,
        selectedAct = "Act1",
    },

    bossRush = {
        autoBossRushActive = false,
        checking = false,
        launching = false,
        handlingResults = false,
        hookedResults = setmetatable({}, { __mode = "k" }),
        generation = 0,
        serverCooldownEnd = 0,
        selectedMode = "Scientist",
        selectedDifficulty = "Easy",
    },

    dungeon = {
        autoDungeonActive = false,
        checking = false,
        launching = false,
        handlingResults = false,
        hookedResults = setmetatable({}, { __mode = "k" }),
        generation = 0,
        serverCooldownEnd = 0,
        selectedMode = "CursedZone",
    },

    -- Create "Dungeon" (PunkCity / CrystalCave) — distinct from Defense Mode (State.dungeon).
    mapDungeon = {
        autoActive = false,
        checking = false,
        launching = false,
        handlingResults = false,
        hookedResults = setmetatable({}, { __mode = "k" }),
        generation = 0,
        serverCooldownEnd = 0,
        selectedMap = "PunkCity",
        selectedDifficulty = "Easy",
    },

    automation = {
        selectedMobs = {},
        tpEnabled = false,
        savedFarmCFrame = nil,
        pendingFarmReturn = false
    },

    rewards = {
        autoClaimRewards = false,
        lib = nil,
        data = nil
    },

    shop = {
        category = "Dungeon",
        item = "DungeonTickets",
        quantity = 1
    },

    webhook = {
        enabled = false,
        url = "",
        messageId = nil,
        username = "Anime Ghosts Tracker",
        sessionId = HttpService:GenerateGUID(false),
        lastState = nil,
        updateQueued = false,
        webhookPendingRefresh = false,
        lastSentAt = 0,
        -- 0 = send as soon as possible; raise if Discord returns 429 on PATCH.
        minInterval = 0
    },

    uiTheme = "Crimson",
    -- Seconds between GamemodeSystem Create and Start (slider 2.5–10 in Settings).
    gamemodeStartDelay = 2.5,
    config = {
        selectedName = "default"
    },

    ui = {
        StatusLabel = nil,
        TimerLabel = nil
    },

    -- Filled by tabs: each entry is function() that reapplies State to that tab's controls (silent).
    configUiSync = {},

    debug = debug or getrenv().debug
}

local ConfigManager = ConfigManagerFactory(HttpService)

local function getConfigSnapshot()
    return {
        uiTheme = State.uiTheme,
        raid = {
            autoRaidActive = State.raid.autoRaidActive,
            autoEasterRaidActive = State.raid.autoEasterRaidActive,
            useRaidTicket = State.raid.useRaidTicket,
            useEasterTicket = State.raid.useEasterTicket,
            selectedMode = State.raid.selectedMode,
            selectedEasterMode = State.raid.selectedEasterMode,
        },
        infCastle = {
            autoInfCastleActive = State.infCastle.autoInfCastleActive,
            selectedAct = State.infCastle.selectedAct,
        },
        bossRush = {
            autoBossRushActive = State.bossRush.autoBossRushActive,
            selectedMode = State.bossRush.selectedMode,
            selectedDifficulty = State.bossRush.selectedDifficulty,
        },
        dungeon = {
            autoDungeonActive = State.dungeon.autoDungeonActive,
            selectedMode = State.dungeon.selectedMode,
        },
        mapDungeon = {
            autoActive = State.mapDungeon.autoActive,
            selectedMap = State.mapDungeon.selectedMap,
            selectedDifficulty = State.mapDungeon.selectedDifficulty,
        },
        automation = {
            tpEnabled = State.automation.tpEnabled,
            selectedMobs = State.automation.selectedMobs,
        },
        rewards = {
            autoClaimRewards = State.rewards.autoClaimRewards,
        },
        webhook = {
            enabled = State.webhook.enabled,
            url = State.webhook.url,
        },
        shop = {
            category = State.shop.category,
            item = State.shop.item,
            quantity = State.shop.quantity,
        },
        gamemodeStartDelay = State.gamemodeStartDelay,
    }
end

local function applyConfigSnapshot(cfg)
    if type(cfg) ~= "table" then
        return
    end
    if type(cfg.uiTheme) == "string" and cfg.uiTheme ~= "" then
        State.uiTheme = cfg.uiTheme
    end

    local raid = cfg.raid
    if type(raid) == "table" then
        if type(raid.autoRaidActive) == "boolean" then State.raid.autoRaidActive = raid.autoRaidActive end
        if type(raid.autoEasterRaidActive) == "boolean" then State.raid.autoEasterRaidActive = raid.autoEasterRaidActive end
        if type(raid.useRaidTicket) == "boolean" then State.raid.useRaidTicket = raid.useRaidTicket end
        if type(raid.useEasterTicket) == "boolean" then State.raid.useEasterTicket = raid.useEasterTicket end
        if type(raid.selectedMode) == "string" and raid.selectedMode ~= "" then State.raid.selectedMode = raid.selectedMode end
        if type(raid.selectedEasterMode) == "string" and raid.selectedEasterMode ~= "" then State.raid.selectedEasterMode = raid.selectedEasterMode end
    end

    local inf = cfg.infCastle
    if type(inf) == "table" then
        if type(inf.autoInfCastleActive) == "boolean" then
            State.infCastle.autoInfCastleActive = inf.autoInfCastleActive
        end
        if inf.selectedAct == "Act1" or inf.selectedAct == "Act2" then
            State.infCastle.selectedAct = inf.selectedAct
        end
    end

    local br = cfg.bossRush
    if type(br) == "table" then
        if type(br.autoBossRushActive) == "boolean" then State.bossRush.autoBossRushActive = br.autoBossRushActive end
        if type(br.selectedMode) == "string" and br.selectedMode ~= "" then State.bossRush.selectedMode = br.selectedMode end
        if type(br.selectedDifficulty) == "string" and br.selectedDifficulty ~= "" then State.bossRush.selectedDifficulty = br.selectedDifficulty end
    end

    local dg = cfg.dungeon
    if type(dg) == "table" then
        if type(dg.autoDungeonActive) == "boolean" then State.dungeon.autoDungeonActive = dg.autoDungeonActive end
        if type(dg.selectedMode) == "string" and dg.selectedMode ~= "" then State.dungeon.selectedMode = dg.selectedMode end
    end

    local md = cfg.mapDungeon
    if type(md) == "table" then
        if type(md.autoActive) == "boolean" then State.mapDungeon.autoActive = md.autoActive end
        if type(md.selectedMap) == "string" and md.selectedMap ~= "" then State.mapDungeon.selectedMap = md.selectedMap end
        if type(md.selectedDifficulty) == "string" and md.selectedDifficulty ~= "" then State.mapDungeon.selectedDifficulty = md.selectedDifficulty end
    end

    local auto = cfg.automation
    if type(auto) == "table" then
        if type(auto.tpEnabled) == "boolean" then State.automation.tpEnabled = auto.tpEnabled end
        if type(auto.selectedMobs) == "table" then State.automation.selectedMobs = auto.selectedMobs end
    end

    local rewards = cfg.rewards
    if type(rewards) == "table" and type(rewards.autoClaimRewards) == "boolean" then
        State.rewards.autoClaimRewards = rewards.autoClaimRewards
    end

    local webhook = cfg.webhook
    if type(webhook) == "table" then
        if type(webhook.enabled) == "boolean" then State.webhook.enabled = webhook.enabled end
        if type(webhook.url) == "string" then State.webhook.url = webhook.url end
    end

    local shop = cfg.shop
    if type(shop) == "table" then
        if type(shop.category) == "string" and shop.category ~= "" then State.shop.category = shop.category end
        if type(shop.item) == "string" and shop.item ~= "" then State.shop.item = shop.item end
        if type(shop.quantity) == "number" then State.shop.quantity = math.max(1, math.floor(shop.quantity)) end
    end

    if type(cfg.gamemodeStartDelay) == "number" and cfg.gamemodeStartDelay == cfg.gamemodeStartDelay then
        State.gamemodeStartDelay = math.clamp(cfg.gamemodeStartDelay, 2.5, 10)
    end
end

do
    local ok, cfg, name = ConfigManager.LoadAutoload()
    if ok and type(cfg) == "table" then
        applyConfigSnapshot(cfg)
        if type(name) == "string" and name ~= "" then
            State.config.selectedName = name
        end
    end
end

local function setStatus(text)
    if State.ui.StatusLabel then
        State.ui.StatusLabel:Set(text)
    end
end

local function setTimer(text)
    if State.ui.TimerLabel then
        State.ui.TimerLabel:Set(text)
    end
end

local function getUpvalue(func, index)
    local ok, a, b = pcall(function()
        return State.debug.getupvalue(func, index)
    end)
    if not ok then
        return nil
    end
    return b ~= nil and b or a
end

local function bumpRaidGeneration()
    State.raid.generation = State.raid.generation + 1
    return State.raid.generation
end

local function isCurrentGeneration(gen)
    return gen == State.raid.generation
end

local function bumpInfCastleGeneration()
    State.infCastle.generation = State.infCastle.generation + 1
    return State.infCastle.generation
end

local function isCurrentInfCastleGeneration(gen)
    return gen == State.infCastle.generation
end

local function bumpBossRushGeneration()
    State.bossRush.generation = State.bossRush.generation + 1
    return State.bossRush.generation
end

local function isCurrentBossRushGeneration(gen)
    return gen == State.bossRush.generation
end

local function bumpDungeonGeneration()
    State.dungeon.generation = State.dungeon.generation + 1
    return State.dungeon.generation
end

local function isCurrentDungeonGeneration(gen)
    return gen == State.dungeon.generation
end

local function bumpMapDungeonGeneration()
    State.mapDungeon.generation = State.mapDungeon.generation + 1
    return State.mapDungeon.generation
end

local function isCurrentMapDungeonGeneration(gen)
    return gen == State.mapDungeon.generation
end

-- All non-Lobby folders (order is Roblox child order — not always the active run first).
local function getNonLobbyGamemodeChildren()
    local list = {}
    for _, child in ipairs(gamemodeFolder:GetChildren()) do
        if child:IsA("Folder") and child.Name ~= "Lobby" then
            table.insert(list, child)
        end
    end
    return list
end

local function getActiveGamemodeFolder()
    local list = getNonLobbyGamemodeChildren()
    -- Prefer the real run folder Dungeon_<userId> if multiple folders exist.
    for _, child in ipairs(list) do
        local lower = string.lower(child.Name)
        if string.sub(lower, 1, 8) == "dungeon_" then
            return child
        end
    end
    if #list > 0 then
        return list[1]
    end
    for _, child in ipairs(gamemodeFolder:GetChildren()) do
        if child:IsA("Folder") then
            return child
        end
    end
    return nil
end

local function getCurrentGamemodeName()
    local folder = getActiveGamemodeFolder()
    if folder then
        return folder.Name
    end
    return "Unknown"
end

local function getGamemodeType()
    local list = getNonLobbyGamemodeChildren()

    -- Must scan every non-Lobby folder: the first one is not always Dungeon_* (staging / leftover).
    for _, child in ipairs(list) do
        local lower = string.lower(child.Name)
        if string.sub(lower, 1, 8) == "dungeon_"
            or lower:find("punkcity", 1, true)
            or lower:find("crystalcave", 1, true) then
            return "Dungeon"
        end
    end

    if #list == 0 then
        for _, child in ipairs(gamemodeFolder:GetChildren()) do
            if child:IsA("Folder") and child.Name == "Lobby" then
                return "Lobby"
            end
        end
        return "Unknown"
    end

    local name = list[1].Name
    local lower = string.lower(name)

    if lower:find("easterraid", 1, true) then
        return "Raid"
    elseif lower:find("raid_", 1, true) then
        return "Raid"
    end

    if lower:find("infinity castle", 1, true) then
        return "InfCastle"
    elseif lower:find("boss rush", 1, true) or lower:find("bossrush", 1, true) then
        return "BossRush"
    elseif lower:find("punkcity", 1, true)
        or lower:find("crystalcave", 1, true)
        or string.sub(lower, 1, 8) == "dungeon_" then
        return "Dungeon"
    elseif lower:find("defense", 1, true)
        or lower:find("cursedzone", 1, true)
        or lower:find("bizarredesert", 1, true) then
        return "Defense"
    elseif lower:find("raid", 1, true) then
        return "Raid"
    elseif lower:find("lobby", 1, true) then
        return "Lobby"
    elseif lower:find("boss", 1, true) then
        return "Boss"
    end

    -- Some raid maps do not include the word "raid" in the folder name.
    -- Treat selected normal/easter raid map names as Raid so priority stays correct.
    local selectedNormal = State.raid and State.raid.selectedMode
    local selectedEaster = State.raid and State.raid.selectedEasterMode
    local selectedMapDungeon = State.mapDungeon and State.mapDungeon.selectedMap
    if type(selectedMapDungeon) == "string" and selectedMapDungeon ~= "" and name == selectedMapDungeon then
        return "Dungeon"
    end
    local selectedDefense = State.dungeon and State.dungeon.selectedMode
    if type(selectedDefense) == "string" and selectedDefense ~= "" and name == selectedDefense then
        return "Defense"
    end
    if (type(selectedNormal) == "string" and selectedNormal ~= "" and name == selectedNormal)
        or (type(selectedEaster) == "string" and selectedEaster ~= "" and name == selectedEaster) then
        return "Raid"
    end

    return "Unknown"
end

local function isInRaidGamemode()
    return getGamemodeType() == "Raid"
end

local function isInInfCastleGamemode()
    return getGamemodeType() == "InfCastle"
end

local function isInBossRushGamemode()
    return getGamemodeType() == "BossRush"
end

local function isInDefenseGamemode()
    return getGamemodeType() == "Defense"
end

local function isInMapDungeonGamemode()
    return getGamemodeType() == "Dungeon"
end

-- Snapshot Folder names under workspace...Gamemode for detecting new rooms after Create.
local function snapshotGamemodeFolderNames()
    local set = {}
    for _, child in ipairs(gamemodeFolder:GetChildren()) do
        if child:IsA("Folder") then
            set[child.Name] = true
        end
    end
    return set
end

local function getFirstNewNonLobbyFolderName(snapshot)
    if type(snapshot) ~= "table" then
        return nil
    end
    for _, child in ipairs(gamemodeFolder:GetChildren()) do
        if child:IsA("Folder") and child.Name ~= "Lobby" and not snapshot[child.Name] then
            return child.Name
        end
    end
    return nil
end

-- Poll until a new non-Lobby Gamemode folder appears after Create (room ready) or timeout.
-- Optional shouldAbort: when scanForCooldown updates serverCooldownEnd (BridgeNet), exit immediately
-- instead of waiting the full timeout — fixes post-run cases where cooldown syncs mid-wait.
local function waitForGamemodeRoomCreated(snapshot, timeoutSec, shouldAbort)
    if type(snapshot) ~= "table" then
        return false
    end
    local t = type(timeoutSec) == "number" and timeoutSec or 6
    if t < 0 then
        t = 0
    end
    local deadline = tick() + t
    local poll = type(shouldAbort) == "function" and 0.15 or 0.2
    while tick() < deadline do
        if getFirstNewNonLobbyFolderName(snapshot) then
            return true
        end
        if type(shouldAbort) == "function" and shouldAbort() then
            return false
        end
        task.wait(poll)
    end
    return getFirstNewNonLobbyFolderName(snapshot) ~= nil
end

-- After a probe Create: poll for a new Gamemode folder OR until BridgeNet syncs cooldown (scanForCooldown).
-- If no folder appears within a short window, treat as on cooldown — don't sit ~10–15s; scanForCooldown will sync.
local PROBE_POLL_INTERVAL = 0.15
local PROBE_MAX_WAIT = 3.5

local function waitForGamemodeProbeOutcome(snapshot, shouldAbort)
    if type(snapshot) ~= "table" then
        return false
    end
    local deadline = tick() + PROBE_MAX_WAIT
    while tick() < deadline do
        if getFirstNewNonLobbyFolderName(snapshot) then
            return true
        end
        if type(shouldAbort) == "function" and shouldAbort() then
            return false
        end
        task.wait(PROBE_POLL_INTERVAL)
    end
    return getFirstNewNonLobbyFolderName(snapshot) ~= nil
end

local function waitAfterFailedCooldownProbe()
    task.wait(0.35)
end

local function getGamemodeStartDelay()
    local d = State.gamemodeStartDelay
    if type(d) ~= "number" or d ~= d then
        return 2.5
    end
    return math.clamp(d, 2.5, 10)
end

local function fireGamemodeStart(gamemodeName)
    if type(gamemodeName) ~= "string" or gamemodeName == "" then
        return
    end
    local startArgs = {
        {
            {
                "GamemodeSystem",
                "Start",
                gamemodeName,
                10686337651,
                n = 4
            },
            "\002"
        }
    }
    BridgeNet:FireServer(unpack(startArgs))
end

local function gamemodeHasStarted()
    local folder = getActiveGamemodeFolder()
    if not folder or folder.Name == "Lobby" then
        return false
    end

    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Model")
            or child:IsA("Folder")
            or child:IsA("BasePart") then
            return true
        end
    end

    return false
end

local function isRaidStarted()
    return isInRaidGamemode() and gamemodeHasStarted()
end

local function isInfCastleStarted()
    return isInInfCastleGamemode() and gamemodeHasStarted()
end

local function isBossRushStarted()
    return isInBossRushGamemode() and gamemodeHasStarted()
end

local function isDefenseStarted()
    return isInDefenseGamemode() and gamemodeHasStarted()
end

local function isMapDungeonStarted()
    return isInMapDungeonGamemode() and gamemodeHasStarted()
end

local function isRaidPriority()
    if isInRaidGamemode() then
        return true
    end

    return (State.raid.autoRaidActive or State.raid.autoEasterRaidActive) and (
        State.raid.checkingRaid
        or State.raid.launchingRaid
        or State.raid.handlingResults
    )
end

local function isInfCastlePriority()
    if isInInfCastleGamemode() then
        return true
    end

    return State.infCastle.autoInfCastleActive and (
        State.infCastle.checking
        or State.infCastle.launching
        or State.infCastle.handlingResults
    )
end

-- True while Boss Rush is actually active (in map or launching / checking / results).
-- Does NOT include server cooldown in lobby — that is idle time; Auto-TP may run.
local function isBossRushPriority()
    if isInBossRushGamemode() then
        return true
    end

    return State.bossRush.autoBossRushActive and (
        State.bossRush.checking
        or State.bossRush.launching
        or State.bossRush.handlingResults
    )
end

-- Priority: Boss Rush > Defense Mode > Dungeon (map) > Raid / Inf Castle.
local function isDefensePriority()
    if isInDefenseGamemode() then
        return true
    end

    return State.dungeon.autoDungeonActive and (
        State.dungeon.checking
        or State.dungeon.launching
        or State.dungeon.handlingResults
    )
end

local function isMapDungeonPriority()
    if isInMapDungeonGamemode() then
        return true
    end

    return State.mapDungeon.autoActive and (
        State.mapDungeon.checking
        or State.mapDungeon.launching
        or State.mapDungeon.handlingResults
    )
end

-- Boss Rush is running/launching OR auto is on, in lobby, off server cooldown — next to start.
-- Raids / Inf Castle yield so Boss Rush wins when multiple come off cooldown together.
local function isBossRushEligibleToStartRun()
    if not State.bossRush.autoBossRushActive then
        return false
    end
    if State.bossRush.handlingResults then
        return false
    end
    if isInBossRushGamemode() then
        return false
    end
    if State.bossRush.launching then
        return false
    end
    if (State.bossRush.serverCooldownEnd or 0) > tick() then
        return false
    end
    -- Finish Raid / Inf Castle before Boss Rush is allowed to take the queue (cooldown can expire mid-run).
    if isInRaidGamemode() then
        return false
    end
    if isInInfCastleGamemode() then
        return false
    end
    if isInDefenseGamemode() then
        return false
    end
    if isInMapDungeonGamemode() then
        return false
    end
    return true
end

local function isBossRushBlockingRaidAndInfQueues()
    return isBossRushPriority() or isBossRushEligibleToStartRun()
end

local function isDefenseEligibleToStartRun()
    if not State.dungeon.autoDungeonActive then
        return false
    end
    if State.dungeon.handlingResults then
        return false
    end
    if isInDefenseGamemode() then
        return false
    end
    if State.dungeon.launching then
        return false
    end
    if (State.dungeon.serverCooldownEnd or 0) > tick() then
        return false
    end
    if isBossRushBlockingRaidAndInfQueues() then
        return false
    end
    if isInRaidGamemode() or isInInfCastleGamemode() then
        return false
    end
    if isInMapDungeonGamemode() then
        return false
    end
    return true
end

local function isMapDungeonEligibleToStartRun()
    if not State.mapDungeon.autoActive then
        return false
    end
    if State.mapDungeon.handlingResults then
        return false
    end
    if isInMapDungeonGamemode() then
        return false
    end
    if State.mapDungeon.launching then
        return false
    end
    if (State.mapDungeon.serverCooldownEnd or 0) > tick() then
        return false
    end
    if isBossRushBlockingRaidAndInfQueues() then
        return false
    end
    local defenseBlocks = isDefensePriority() or isDefenseEligibleToStartRun()
    if defenseBlocks then
        return false
    end
    if isInRaidGamemode() or isInInfCastleGamemode() then
        return false
    end
    if isInDefenseGamemode() then
        return false
    end
    return true
end

local function isDefenseBlockingRaidAndInfQueues()
    return isDefensePriority() or isDefenseEligibleToStartRun()
end

local function isMapDungeonBlockingRaidAndInfQueues()
    return isMapDungeonPriority() or isMapDungeonEligibleToStartRun()
end

-- Raid / Inf yield to Boss Rush, Defense Mode, and map Dungeon.
local function isDungeonBlockingRaidAndInfQueues()
    return isDefenseBlockingRaidAndInfQueues() or isMapDungeonBlockingRaidAndInfQueues()
end

local function isHigherPriorityActivityRunning()
    return isBossRushPriority()
        or isDefensePriority()
        or isMapDungeonPriority()
        or isRaidPriority()
        or isInfCastlePriority()
end

local function getUniqueMobNames()
    local uniqueNames = {}
    local seen = {}

    for _, hashModel in ipairs(targetFolder:GetChildren()) do
        if hashModel.Name ~= "Highlight" then
            local displayName = nil
            local billboard = hashModel:FindFirstChild("EnemyBillboard", true)
            local title = billboard and billboard:FindFirstChild("Title")

            if title and (title:IsA("TextLabel") or title:IsA("TextBox")) then
                displayName = title.Text
            elseif hashModel:FindFirstChild("Appearance") then
                displayName = "Secret"
            end

            if displayName and not seen[displayName] then
                seen[displayName] = true
                table.insert(uniqueNames, displayName)
            end
        end
    end

    table.sort(uniqueNames)
    return uniqueNames
end

local function getRequestFunction()
    return (syn and syn.request)
        or http_request
        or request
        or (fluxus and fluxus.request)
end

local function doRequest(method, url, bodyTable)
    local req = getRequestFunction()
    if not req then
        warn("No request function found for webhook")
        return nil
    end

    local body = bodyTable and HttpService:JSONEncode(bodyTable) or nil

    local ok, response = pcall(function()
        return req({
            Url = url,
            Method = method,
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = body
        })
    end)

    if not ok then
        warn("Webhook request failed:", response)
        return nil
    end

    return response
end

local function getWebhookStatus()
    local modeType = getGamemodeType()
    local modeName = getCurrentGamemodeName()

    if State.bossRush.autoBossRushActive then
        if State.bossRush.handlingResults then
            return "Boss Rush returning / handling results"
        elseif State.bossRush.launching then
            return "Boss Rush launching"
        elseif modeType == "BossRush" then
            return "Boss Rush running"
        elseif State.bossRush.serverCooldownEnd > tick() and not State.bossRush.handlingResults then
            local remaining = math.max(0, math.ceil(State.bossRush.serverCooldownEnd - tick()))
            return string.format("Boss Rush cooldown (%02dm %02ds)", math.floor(remaining / 60), remaining % 60)
        elseif State.bossRush.checking then
            return "Boss Rush checking"
        else
            return "Boss Rush enabled / ready"
        end
    end

    if State.dungeon.autoDungeonActive then
        if State.dungeon.handlingResults then
            return "Defense returning / handling results"
        elseif State.dungeon.launching then
            return "Defense launching"
        elseif modeType == "Defense" then
            return "Defense running"
        elseif State.dungeon.serverCooldownEnd > tick() and not State.dungeon.handlingResults then
            local remaining = math.max(0, math.ceil(State.dungeon.serverCooldownEnd - tick()))
            return string.format("Defense cooldown (%02dm %02ds)", math.floor(remaining / 60), remaining % 60)
        elseif State.dungeon.checking then
            return "Defense checking"
        else
            return "Defense enabled / ready"
        end
    end

    if State.mapDungeon.autoActive then
        if State.mapDungeon.handlingResults then
            return "Dungeon returning / handling results"
        elseif State.mapDungeon.launching then
            return "Dungeon launching"
        elseif modeType == "Dungeon" then
            return "Dungeon running"
        elseif State.mapDungeon.serverCooldownEnd > tick() and not State.mapDungeon.handlingResults then
            local remaining = math.max(0, math.ceil(State.mapDungeon.serverCooldownEnd - tick()))
            return string.format("Dungeon cooldown (%02dm %02ds)", math.floor(remaining / 60), remaining % 60)
        elseif State.mapDungeon.checking then
            return "Dungeon checking"
        else
            return "Dungeon enabled / ready"
        end
    end

    if State.raid.autoRaidActive then
        if State.raid.handlingResults then
            return "Raid returning / handling results"
        elseif State.raid.launchingRaid then
            return "Raid attempting launch"
        elseif modeType == "Raid" then
            return "Raid fighting"
        elseif State.raid.checkingRaid then
            return "Raid checking"
        elseif State.raid.normalCooldownEnd > tick() then
            local remaining = math.max(0, math.ceil(State.raid.normalCooldownEnd - tick()))
            return string.format("Raid cooldown (%02dm %02ds)", math.floor(remaining / 60), remaining % 60)
        else
            return "Raid enabled / ready"
        end
    end

    if State.raid.autoEasterRaidActive then
        if State.raid.handlingResults then
            return "Easter Raid returning / handling results"
        elseif State.raid.launchingRaid then
            return "Easter Raid attempting launch"
        elseif modeType == "Raid" then
            return "Easter Raid fighting"
        elseif State.raid.checkingRaid then
            return "Easter Raid checking"
        elseif State.raid.easterCooldownEnd > tick() then
            local remaining = math.max(0, math.ceil(State.raid.easterCooldownEnd - tick()))
            return string.format("Easter Raid cooldown (%02dm %02ds)", math.floor(remaining / 60), remaining % 60)
        else
            return "Easter Raid enabled / ready"
        end
    end

    if State.infCastle.autoInfCastleActive then
        if State.infCastle.handlingResults then
            return "Inf Castle returning"
        elseif State.infCastle.launching then
            return "Inf Castle launching"
        elseif modeType == "InfCastle" then
            return "Inf Castle running"
        elseif State.infCastle.checking then
            return "Checking Inf Castle"
        else
            return "Inf Castle enabled / ready"
        end
    end

    if modeType ~= "Lobby" and modeType ~= "Unknown" then
        return "In " .. modeName
    end

    if State.automation.tpEnabled and #State.automation.selectedMobs > 0 then
        return "Auto-TP farming"
    end

    if State.rewards.autoClaimRewards then
        return "Auto claiming rewards"
    end

    return "Online"
end

local function getWebhookColor(status)
    local s = string.lower(status)

    if s:find("fighting", 1, true) then
        return 16711680
    elseif s:find("launch", 1, true) then
        return 16753920
    elseif s:find("cooldown", 1, true) then
        return 16776960
    elseif s:find("checking", 1, true) then
        return 5814783
    elseif s:find("returning", 1, true) or s:find("results", 1, true) then
        return 1146986
    end

    return 65280
end

local function getRaidWebhookSummary()
    local normal = State.raid.autoRaidActive and "ON" or "OFF"
    local easter = State.raid.autoEasterRaidActive and "ON" or "OFF"
    local mode = State.raid.selectedMode or "TitanTown"
    local easterMode = State.raid.selectedEasterMode or "ChocolateKingdom"
    local raidState = "Ready"

    if State.raid.handlingResults then
        raidState = "Results"
    elseif State.raid.launchingRaid then
        raidState = "Launching"
    elseif State.raid.checkingRaid then
        raidState = "Checking"
    elseif State.raid.normalCooldownEnd > tick() or State.raid.easterCooldownEnd > tick() then
        local normalRemaining = math.max(0, math.ceil(State.raid.normalCooldownEnd - tick()))
        local easterRemaining = math.max(0, math.ceil(State.raid.easterCooldownEnd - tick()))
        raidState = string.format("CD N:%02dm%02ds E:%02dm%02ds",
            math.floor(normalRemaining / 60), normalRemaining % 60,
            math.floor(easterRemaining / 60), easterRemaining % 60)
    elseif State.helpers and State.helpers.isInRaidGamemode and State.helpers.isInRaidGamemode() then
        raidState = "Fighting"
    end

    return table.concat({
        "N: " .. normal .. "  |  E: " .. easter,
        "State: " .. raidState,
        "Modes: " .. mode .. " / " .. easterMode
    }, "\n")
end

local function getInfCastleWebhookSummary()
    local enabled = State.infCastle.autoInfCastleActive and "ON" or "OFF"
    local stateText = "Ready"
    local act = State.infCastle.selectedAct or "Act1"

    if State.infCastle.handlingResults then
        stateText = "Handling Results"
    elseif State.infCastle.launching then
        stateText = "Launching"
    elseif State.infCastle.checking then
        stateText = "Checking"
    elseif State.infCastle.serverCooldownEnd > tick() then
        local remaining = math.max(0, math.ceil(State.infCastle.serverCooldownEnd - tick()))
        stateText = string.format("Cooldown (%02dm %02ds)", math.floor(remaining / 60), remaining % 60)
    elseif State.helpers and State.helpers.isInInfCastleGamemode and State.helpers.isInInfCastleGamemode() then
        stateText = "Running"
    end

    return table.concat({
        "Enabled: " .. enabled,
        "State: " .. stateText,
        "Act: " .. act .. " @ Easy"
    }, "\n")
end

local function getBossRushWebhookSummary()
    local enabled = State.bossRush.autoBossRushActive and "ON" or "OFF"
    local stateText = "Ready"
    local mode = State.bossRush.selectedMode or "Scientist"
    local diff = State.bossRush.selectedDifficulty or "Easy"

    if State.bossRush.handlingResults then
        stateText = "Handling Results"
    elseif State.bossRush.launching then
        stateText = "Launching"
    elseif State.bossRush.serverCooldownEnd > tick() and not State.bossRush.handlingResults then
        local remaining = math.max(0, math.ceil(State.bossRush.serverCooldownEnd - tick()))
        stateText = string.format("Cooldown (%02dm %02ds)", math.floor(remaining / 60), remaining % 60)
    elseif State.bossRush.checking then
        stateText = "Checking"
    elseif State.helpers and State.helpers.isInBossRushGamemode and State.helpers.isInBossRushGamemode() then
        stateText = "Running"
    end

    return table.concat({
        "Enabled: " .. enabled,
        "State: " .. stateText,
        "Mode: " .. mode .. " @ " .. diff
    }, "\n")
end

local function getDungeonWebhookSummary()
    local enabled = State.dungeon.autoDungeonActive and "ON" or "OFF"
    local stateText = "Ready"
    local mapName = State.dungeon.selectedMode or "CursedZone"

    if State.dungeon.handlingResults then
        stateText = "Handling Results"
    elseif State.dungeon.launching then
        stateText = "Launching"
    elseif State.dungeon.serverCooldownEnd > tick() and not State.dungeon.handlingResults then
        local remaining = math.max(0, math.ceil(State.dungeon.serverCooldownEnd - tick()))
        stateText = string.format("Cooldown (%02dm %02ds)", math.floor(remaining / 60), remaining % 60)
    elseif State.dungeon.checking then
        stateText = "Checking"
    elseif isInDefenseGamemode() then
        stateText = "Running"
    end

    return table.concat({
        "Enabled: " .. enabled,
        "State: " .. stateText,
        "Map: " .. mapName .. " @ Easy"
    }, "\n")
end

local function getMapDungeonWebhookSummary()
    local enabled = State.mapDungeon.autoActive and "ON" or "OFF"
    local stateText = "Ready"
    local mapName = State.mapDungeon.selectedMap or "PunkCity"
    local diff = State.mapDungeon.selectedDifficulty or "Easy"

    if State.mapDungeon.handlingResults then
        stateText = "Handling Results"
    elseif State.mapDungeon.launching then
        stateText = "Launching"
    elseif State.mapDungeon.serverCooldownEnd > tick() and not State.mapDungeon.handlingResults then
        local remaining = math.max(0, math.ceil(State.mapDungeon.serverCooldownEnd - tick()))
        stateText = string.format("Cooldown (%02dm %02ds)", math.floor(remaining / 60), remaining % 60)
    elseif State.mapDungeon.checking then
        stateText = "Checking"
    elseif isInMapDungeonGamemode() then
        stateText = "Running"
    end

    return table.concat({
        "Enabled: " .. enabled,
        "State: " .. stateText,
        "Map: " .. mapName .. " @ " .. diff
    }, "\n")
end

local function getAutoTpWebhookSummary()
    local enabled = State.automation.tpEnabled and "ON" or "OFF"
    local selected = #State.automation.selectedMobs
    local stateText = "Idle"

    if State.automation.tpEnabled and selected > 0 then
        if isHigherPriorityActivityRunning() then
            stateText = "Blocked by Higher Priority"
        else
            stateText = "Farming"
        end
    elseif State.automation.tpEnabled then
        stateText = "No Targets Selected"
    end

    return table.concat({
        "Enabled: " .. enabled,
        "State: " .. stateText,
        "Targets: " .. tostring(selected)
    }, "\n")
end

local function buildWebhookStateKey()
    return table.concat({
        tostring(State.raid.autoRaidActive),
        tostring(State.raid.autoEasterRaidActive),
        tostring(State.raid.checkingRaid),
        tostring(State.raid.launchingRaid),
        tostring(State.raid.handlingResults),
        tostring(State.bossRush.autoBossRushActive),
        tostring(State.bossRush.checking),
        tostring(State.bossRush.launching),
        tostring(State.bossRush.handlingResults),
        tostring(State.dungeon.autoDungeonActive),
        tostring(State.dungeon.checking),
        tostring(State.dungeon.launching),
        tostring(State.dungeon.handlingResults),
        tostring(State.mapDungeon.autoActive),
        tostring(State.mapDungeon.checking),
        tostring(State.mapDungeon.launching),
        tostring(State.mapDungeon.handlingResults),
        tostring(State.infCastle.autoInfCastleActive),
        tostring(State.infCastle.checking),
        tostring(State.infCastle.launching),
        tostring(State.infCastle.handlingResults),
        tostring(State.infCastle.selectedAct or ""),
        tostring(State.automation.tpEnabled),
        tostring(#State.automation.selectedMobs),
        tostring(State.rewards.autoClaimRewards),
        tostring(math.max(0, math.ceil(State.raid.normalCooldownEnd - tick()))),
        tostring(math.max(0, math.ceil(State.raid.easterCooldownEnd - tick()))),
        tostring(math.max(0, math.ceil(State.bossRush.serverCooldownEnd - tick()))),
        tostring(math.max(0, math.ceil(State.dungeon.serverCooldownEnd - tick()))),
        tostring(math.max(0, math.ceil(State.mapDungeon.serverCooldownEnd - tick()))),
        tostring(State.bossRush.selectedMode or ""),
        tostring(State.bossRush.selectedDifficulty or ""),
        tostring(State.dungeon.selectedMode or ""),
        tostring(State.mapDungeon.selectedMap or ""),
        tostring(State.mapDungeon.selectedDifficulty or ""),
        tostring(getGamemodeType()),
        tostring(getCurrentGamemodeName())
    }, "|")
end

local function createWebhookMessage()
    if State.webhook.url == "" then
        return
    end

    local status = getWebhookStatus()

    local response = doRequest("POST", State.webhook.url .. "?wait=true", {
        username = State.webhook.username,
        embeds = {{
            title = "Anime Ghosts Tracker",
            description = "Session started",
            color = getWebhookColor(status),
            fields = {
                { name = "Raids", value = getRaidWebhookSummary(), inline = true },
                { name = "Boss Rush", value = getBossRushWebhookSummary(), inline = true },
                { name = "Defense", value = getDungeonWebhookSummary(), inline = true },
                { name = "Dungeon", value = getMapDungeonWebhookSummary(), inline = true },
                { name = "Inf Castle", value = getInfCastleWebhookSummary(), inline = true },
                { name = "Auto TP", value = getAutoTpWebhookSummary(), inline = true },
                { name = "Status", value = status, inline = false }
            },
            footer = { text = LocalPlayer.Name .. " • " .. getCurrentGamemodeName() .. " • " .. State.webhook.sessionId },
            timestamp = DateTime.now():ToIsoDate()
        }}
    })

    if response and response.Body then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(response.Body)
        end)

        if ok and data and data.id then
            State.webhook.messageId = data.id
        end
    end
end

local function updateWebhookMessage()
    if State.webhook.url == "" or not State.webhook.messageId then
        return
    end

    local status = getWebhookStatus()

    doRequest("PATCH", State.webhook.url .. "/messages/" .. State.webhook.messageId, {
        username = State.webhook.username,
        embeds = {{
            title = "Anime Ghosts Tracker",
            description = "Live session status",
            color = getWebhookColor(status),
            fields = {
                { name = "Raids", value = getRaidWebhookSummary(), inline = true },
                { name = "Boss Rush", value = getBossRushWebhookSummary(), inline = true },
                { name = "Defense", value = getDungeonWebhookSummary(), inline = true },
                { name = "Dungeon", value = getMapDungeonWebhookSummary(), inline = true },
                { name = "Inf Castle", value = getInfCastleWebhookSummary(), inline = true },
                { name = "Auto TP", value = getAutoTpWebhookSummary(), inline = true },
                { name = "Status", value = status, inline = false }
            },
            footer = { text = LocalPlayer.Name .. " • " .. getCurrentGamemodeName() .. " • " .. State.webhook.sessionId },
            timestamp = DateTime.now():ToIsoDate()
        }}
    })
end

local function queueWebhookUpdate(force)
    if not State.webhook.enabled or State.webhook.url == "" then
        return
    end

    local stateKey = buildWebhookStateKey()

    if not force and stateKey == State.webhook.lastState then
        return
    end

    State.webhook.lastState = stateKey

    if State.webhook.updateQueued then
        State.webhook.webhookPendingRefresh = true
        return
    end

    State.webhook.updateQueued = true

    task.spawn(function()
        local waitTime = 0
        if not force then
            waitTime = State.webhook.minInterval - (tick() - State.webhook.lastSentAt)
        end
        if waitTime > 0 then
            task.wait(waitTime)
        end

        if State.webhook.enabled and State.webhook.url ~= "" then
            if not State.webhook.messageId then
                createWebhookMessage()
            else
                updateWebhookMessage()
            end
            State.webhook.lastSentAt = tick()
        end

        State.webhook.updateQueued = false
        if State.webhook.webhookPendingRefresh then
            State.webhook.webhookPendingRefresh = false
            task.defer(function()
                queueWebhookUpdate(true)
            end)
        end
    end)
end

local function resetRaidState(setChecking)
    State.raid.launchingRaid = false
    State.raid.handlingResults = false
    State.raid.checkingRaid = setChecking == true
    queueWebhookUpdate()
end

local function resetInfCastleState(setChecking)
    State.infCastle.launching = false
    State.infCastle.handlingResults = false
    State.infCastle.checking = setChecking == true
    queueWebhookUpdate()
end

local function resetBossRushState(setChecking)
    State.bossRush.launching = false
    State.bossRush.handlingResults = false
    State.bossRush.checking = setChecking == true
    queueWebhookUpdate()
end

local function resetDungeonState(setChecking)
    State.dungeon.launching = false
    State.dungeon.handlingResults = false
    State.dungeon.checking = setChecking == true
    queueWebhookUpdate()
end

local function resetMapDungeonState(setChecking)
    State.mapDungeon.launching = false
    State.mapDungeon.handlingResults = false
    State.mapDungeon.checking = setChecking == true
    queueWebhookUpdate()
end

local function resetGeneralTimeRewards()
    if not State.rewards.lib or not State.rewards.lib.Remote then
        warn("Reset failed: rewards remote missing")
        return false
    end

    local ok, err = pcall(function()
        State.rewards.lib.Remote:Fire("TimeRewardSystem", "Reset", "General")
    end)

    if not ok then
        warn("Reset failed:", err)
        return false
    end

    warn("General time rewards reset fired")
    return true
end

local function syncRaidCooldown(totalSeconds, raidType)
    if raidType == "Easter" then
        State.raid.easterCooldownEnd = tick() + totalSeconds
    else
        State.raid.normalCooldownEnd = tick() + totalSeconds
    end
    bumpRaidGeneration()
    State.raid.launchingRaid = false
    State.raid.checkingRaid = false

    if (State.raid.autoRaidActive or State.raid.autoEasterRaidActive) and not State.raid.handlingResults then
        setStatus("Status: SYNCED COOLDOWN")
        if raidType == "Easter" then
            setTimer(string.format("Easter Raid: %02dm %02ds", math.floor(totalSeconds / 60), totalSeconds % 60))
        else
            setTimer(string.format("Normal Raid: %02dm %02ds", math.floor(totalSeconds / 60), totalSeconds % 60))
        end
    end

    queueWebhookUpdate()
end

local function syncInfCastleCooldown(totalSeconds)
    State.infCastle.serverCooldownEnd = tick() + totalSeconds
    bumpInfCastleGeneration()
    State.infCastle.launching = false
    State.infCastle.checking = false

    queueWebhookUpdate()
end

local function syncBossRushCooldown(totalSeconds)
    State.bossRush.serverCooldownEnd = tick() + totalSeconds
    bumpBossRushGeneration()
    State.bossRush.launching = false
    State.bossRush.checking = false

    queueWebhookUpdate()
end

local function syncDungeonCooldown(totalSeconds)
    State.dungeon.serverCooldownEnd = tick() + totalSeconds
    bumpDungeonGeneration()
    State.dungeon.launching = false
    State.dungeon.checking = false

    queueWebhookUpdate()
end

local function syncMapDungeonCooldown(totalSeconds)
    State.mapDungeon.serverCooldownEnd = tick() + totalSeconds
    bumpMapDungeonGeneration()
    State.mapDungeon.launching = false
    State.mapDungeon.checking = false

    queueWebhookUpdate()
end

-- BridgeNet can send huge nested tables; unbounded recursion allocates massive memory.
local SCAN_MAX_DEPTH = 6
local SCAN_MAX_NODES = 400

local function scanForCooldown(data, seen, depth, budget)
    seen = seen or {}
    depth = depth or 0
    budget = budget or { remaining = SCAN_MAX_NODES }

    if budget.remaining <= 0 or depth > SCAN_MAX_DEPTH then
        return false
    end

    if typeof(data) == "string" then
        if #data > 2048 then
            data = string.sub(data, 1, 2048)
        end
        local lower = string.lower(data)

        local min = tonumber(data:match("(%d+)%s*m")) or 0
        local sec = tonumber(data:match("(%d+)%s*s")) or 0

        local altMin = tonumber(data:match("(%d+)%s*minute")) or tonumber(data:match("(%d+)%s*minutes")) or 0
        local altSec = tonumber(data:match("(%d+)%s*second")) or tonumber(data:match("(%d+)%s*seconds")) or 0

        if altMin > 0 then
            min = altMin
        end

        if altSec > 0 then
            sec = altSec
        end

        local totalSeconds = (min * 60) + sec

        if totalSeconds > 0 then
            if lower:find("infinity castle", 1, true) then
                syncInfCastleCooldown(totalSeconds)
                return true
            elseif lower:find("boss rush", 1, true) or lower:find("bossrush", 1, true) then
                syncBossRushCooldown(totalSeconds)
                return true
            elseif lower:find("punkcity", 1, true) or lower:find("crystalcave", 1, true) then
                syncMapDungeonCooldown(totalSeconds)
                return true
            elseif lower:find("defense mode", 1, true)
                or lower:find("defense", 1, true)
                or lower:find("cursedzone", 1, true)
                or lower:find("bizarredesert", 1, true) then
                syncDungeonCooldown(totalSeconds)
                return true
            -- "You Will be Able to Create/Join Dungeon in 03m 56s" contains "Able to Create" — must not sync Raid.
            elseif lower:find("dungeon", 1, true)
                and (lower:find("create", 1, true) or lower:find("join", 1, true))
                and not lower:find("defense", 1, true)
                and not lower:find("infinity castle", 1, true) then
                syncMapDungeonCooldown(totalSeconds)
                return true
            elseif data:find("Able to Create") or lower:find("cooldown", 1, true) or data:find("Raid") then
                if lower:find("easter", 1, true) then
                    syncRaidCooldown(totalSeconds, "Easter")
                else
                    syncRaidCooldown(totalSeconds, "Normal")
                end
                return true
            end
        end
    elseif typeof(data) == "table" then
        if seen[data] then
            return false
        end
        seen[data] = true
        budget.remaining = budget.remaining - 1

        for _, v in pairs(data) do
            if budget.remaining <= 0 then
                return false
            end
            if scanForCooldown(v, seen, depth + 1, budget) then
                return true
            end
        end
    end

    return false
end

local function fireButtonConnections(button)
    if not button then
        return false
    end

    local fired = false

    local ok1, mouseConnections = pcall(getconnections, button.MouseButton1Click)
    if ok1 and mouseConnections then
        for _, v in ipairs(mouseConnections) do
            pcall(function()
                v:Fire()
            end)
            fired = true
        end
    end

    if not fired then
        local ok2, activatedConnections = pcall(getconnections, button.Activated)
        if ok2 and activatedConnections then
            for _, v in ipairs(activatedConnections) do
                pcall(function()
                    v:Fire()
                end)
                fired = true
            end
        end
    end

    return fired
end

local function setupTimeRewardsAccess()
    local timeRewardsModule = nil

    for _, v in pairs(getgc(true)) do
        if typeof(v) == "table"
            and rawget(v, "Setup")
            and rawget(v, "UpdateGui")
            and rawget(v, "ResetGui") then
            timeRewardsModule = v
            break
        end
    end

    if not timeRewardsModule then
        return false
    end

    State.rewards.lib = getUpvalue(timeRewardsModule.UpdateGui, 7)
    State.rewards.data = getUpvalue(timeRewardsModule.UpdateGui, 8)

    if not State.rewards.lib or not State.rewards.data then
        return false
    end

    return true
end

setupTimeRewardsAccess()

-- Lua heap / GC snapshot. Full process RAM cannot be read from sandboxed script code.
local function getMemoryDumpText()
    local lines = {}
    local function add(s)
        table.insert(lines, s)
    end

    add("=== Peanut memory dump ===")
    add("This is the Luau/Lua state heap (GC), not a binary RAM image. Total Roblox RAM: Task Manager.")
    pcall(function()
        add("Time: " .. DateTime.now():ToIsoDate())
    end)
    add("tick: " .. tostring(tick()))
    add("")

    pcall(function()
        local kb = collectgarbage("count")
        add("collectgarbage(\"count\") KB: " .. string.format("%.2f", kb))
    end)

    pcall(function()
        collectgarbage("collect")
    end)

    pcall(function()
        local kb = collectgarbage("count")
        add("after collectgarbage(\"collect\"), KB: " .. string.format("%.2f", kb))
    end)

    pcall(function()
        if type(gcinfo) == "function" then
            add("gcinfo(): " .. tostring(gcinfo()))
        end
    end)

    local tryNames = {
        "getmemoryusage",
        "get_memory_usage",
        "getmemusage",
        "memoryusage",
    }
    for _, name in ipairs(tryNames) do
        local f = rawget(_G, name)
        if type(f) == "function" then
            pcall(function()
                add(name .. "(): " .. tostring(f()))
            end)
        end
    end

    pcall(function()
        local s = rawget(_G, "stats")
        if type(s) == "function" then
            add("stats(): " .. tostring(s()))
        end
    end)

    add("=== end ===")
    return table.concat(lines, "\n")
end

BridgeNet.OnClientEvent:Connect(function(content)
    pcall(function()
        scanForCooldown(content)
    end)
end)

local function sendGamemodeCreateChat(message)
    if type(message) ~= "string" or message == "" then
        return
    end
    pcall(function()
        local channels = TextChatService:FindFirstChild("TextChannels")
            or TextChatService:WaitForChild("TextChannels", 5)
        if not channels then
            return
        end
        local rbxGeneral = channels:FindFirstChild("RBXGeneral") or channels:WaitForChild("RBXGeneral", 5)
        if rbxGeneral and rbxGeneral.SendAsync then
            rbxGeneral:SendAsync(message)
        end
    end)
end

State.helpers = {
    setStatus = setStatus,
    setTimer = setTimer,
    getUpvalue = getUpvalue,
    bumpRaidGeneration = bumpRaidGeneration,
    isCurrentGeneration = isCurrentGeneration,
    bumpInfCastleGeneration = bumpInfCastleGeneration,
    isCurrentInfCastleGeneration = isCurrentInfCastleGeneration,
    bumpBossRushGeneration = bumpBossRushGeneration,
    isCurrentBossRushGeneration = isCurrentBossRushGeneration,
    bumpDungeonGeneration = bumpDungeonGeneration,
    isCurrentDungeonGeneration = isCurrentDungeonGeneration,
    bumpMapDungeonGeneration = bumpMapDungeonGeneration,
    isCurrentMapDungeonGeneration = isCurrentMapDungeonGeneration,
    getCurrentGamemodeName = getCurrentGamemodeName,
    getGamemodeType = getGamemodeType,
    getCurrentGamemodeType = getGamemodeType,
    isInRaidGamemode = isInRaidGamemode,
    isInInfCastleGamemode = isInInfCastleGamemode,
    isInBossRushGamemode = isInBossRushGamemode,
    isInDefenseGamemode = isInDefenseGamemode,
    isInMapDungeonGamemode = isInMapDungeonGamemode,
    isRaidPriority = isRaidPriority,
    isInfCastlePriority = isInfCastlePriority,
    isBossRushPriority = isBossRushPriority,
    isBossRushEligibleToStartRun = isBossRushEligibleToStartRun,
    isBossRushBlockingRaidAndInfQueues = isBossRushBlockingRaidAndInfQueues,
    isDefenseBlockingRaidAndInfQueues = isDefenseBlockingRaidAndInfQueues,
    isMapDungeonBlockingRaidAndInfQueues = isMapDungeonBlockingRaidAndInfQueues,
    isDungeonBlockingRaidAndInfQueues = isDungeonBlockingRaidAndInfQueues,
    isDefenseEligibleToStartRun = isDefenseEligibleToStartRun,
    isMapDungeonEligibleToStartRun = isMapDungeonEligibleToStartRun,
    isHigherPriorityActivityRunning = isHigherPriorityActivityRunning,
    getUniqueMobNames = getUniqueMobNames,
    queueWebhookUpdate = queueWebhookUpdate,
    resetRaidState = resetRaidState,
    resetInfCastleState = resetInfCastleState,
    resetBossRushState = resetBossRushState,
    resetDungeonState = resetDungeonState,
    resetMapDungeonState = resetMapDungeonState,
    resetGeneralTimeRewards = resetGeneralTimeRewards,
    fireButtonConnections = fireButtonConnections,
    setupTimeRewardsAccess = setupTimeRewardsAccess,
    getActiveGamemodeFolder = getActiveGamemodeFolder,
    snapshotGamemodeFolderNames = snapshotGamemodeFolderNames,
    getFirstNewNonLobbyFolderName = getFirstNewNonLobbyFolderName,
    waitForGamemodeRoomCreated = waitForGamemodeRoomCreated,
    waitForGamemodeProbeOutcome = waitForGamemodeProbeOutcome,
    waitAfterFailedCooldownProbe = waitAfterFailedCooldownProbe,
    fireGamemodeStart = fireGamemodeStart,
    getGamemodeStartDelay = getGamemodeStartDelay,
    gamemodeHasStarted = gamemodeHasStarted,
    isRaidStarted = isRaidStarted,
    isInfCastleStarted = isInfCastleStarted,
    isBossRushStarted = isBossRushStarted,
    isDefenseStarted = isDefenseStarted,
    isMapDungeonStarted = isMapDungeonStarted,
    configIsSupported = ConfigManager.IsSupported,
    getConfigStorageRoot = ConfigManager.GetStorageRoot,
    listConfigs = ConfigManager.List,
    getAutoloadConfig = ConfigManager.GetAutoload,
    setAutoloadConfig = ConfigManager.SetAutoload,
    saveConfig = function(name)
        return ConfigManager.Save(name, getConfigSnapshot())
    end,
    loadConfig = function(name)
        local ok, cfgOrErr = ConfigManager.Load(name)
        if not ok then
            return false, cfgOrErr
        end
        applyConfigSnapshot(cfgOrErr)
        if State.config and type(name) == "string" and name ~= "" then
            State.config.selectedName = name
        end
        if State.window and State.window.SetTheme then
            pcall(function()
                State.window:SetTheme(State.uiTheme)
            end)
        end
        if State.helpers.syncConfigUiFromState then
            State.helpers.syncConfigUiFromState()
        end
        return true
    end,
    getMemoryDumpText = getMemoryDumpText,
    sendGamemodeCreateChat = sendGamemodeCreateChat,
}

Window:SetTheme(State.uiTheme)

import("Peanut/Tabs/automation.lua")(Window, State)
import("Peanut/Tabs/bossRush.lua")(Window, State)
import("Peanut/Tabs/autoDungeon.lua")(Window, State)
import("Peanut/Tabs/autoMapDungeon.lua")(Window, State)
import("Peanut/Tabs/autoraid.lua")(Window, State)
import("Peanut/Tabs/autoInfCastle.lua")(Window, State)
import("Peanut/Tabs/misc.lua")(Window, State)
import("Peanut/Tabs/webhook.lua")(Window, State)
import("Peanut/Tabs/shop.lua")(Window, State)
import("Peanut/Tabs/settings.lua")(Window, State)

State.helpers.syncConfigUiFromState = function()
    for _, fn in ipairs(State.configUiSync) do
        pcall(fn)
    end
end

task.spawn(function()
    while true do
        if State.webhook.enabled then
            State.helpers.queueWebhookUpdate(true)
        end
        task.wait(30)
    end
end)
