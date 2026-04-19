return function(Window, State)
    local PlayerGui = State.services.PlayerGui
    local BridgeNet = State.services.BridgeNet
    local enemyRoot = State.services.enemyRoot
    local LocalPlayer = State.services.LocalPlayer

    local mapOptions = {
        "PunkCity",
        "CrystalCave",
    }

    local difficultyOptions = {
        "Easy",
        "Medium",
        "Hard",
    }

    local function probeMapDungeonCooldownFromGame()
        local before = State.helpers.snapshotGamemodeFolderNames()
        local mapName = State.mapDungeon.selectedMap or "PunkCity"
        local diff = State.mapDungeon.selectedDifficulty or "Easy"
        BridgeNet:FireServer(unpack({
            { { "GamemodeSystem", "Create", "Dungeon", mapName, diff, n = 6 }, "\002" },
        }))
        if State.helpers.waitForGamemodeProbeOutcome(before, function()
            return (State.mapDungeon.serverCooldownEnd or 0) > tick()
        end) then
            State.helpers.bumpMapDungeonGeneration()
            State.helpers.fireGamemodeStart("Dungeon")
            return true
        end
        return false
    end

    local function cooldownProbeAndWait()
        local endTime = State.mapDungeon.serverCooldownEnd or 0
        if endTime > tick() then
            local remaining = endTime - tick()
            task.wait(math.min(remaining + 0.05, 5))
            return
        end
        if not probeMapDungeonCooldownFromGame() then
            State.helpers.waitAfterFailedCooldownProbe()
        end
    end

    local function isDefenseTierBlocking()
        return State.helpers.isDefenseBlockingRaidAndInfQueues()
    end

    local DungeonTab = Window:CreateTab("Auto Dungeon", 4483362458)

    local statusLabel = DungeonTab:CreateLabel("Status: IDLE")
    local timerLabel = DungeonTab:CreateLabel("Next Dungeon: Ready")

    local function setMdStatus(text)
        if statusLabel then
            statusLabel:Set(text)
        end
    end

    local function setMdTimer(text)
        if timerLabel then
            timerLabel:Set(text)
        end
    end

    local function hookResultsUI(resultsGui)
        if State.mapDungeon.hookedResults[resultsGui] then
            return
        end
        State.mapDungeon.hookedResults[resultsGui] = true

        resultsGui:GetPropertyChangedSignal("Enabled"):Connect(function()
            if State.mapDungeon.autoActive
                and resultsGui.Enabled
                and not State.mapDungeon.handlingResults
                and State.helpers.isInMapDungeonGamemode() then
                task.spawn(function()
                    State.helpers.bumpMapDungeonGeneration()
                    State.mapDungeon.handlingResults = true
                    State.mapDungeon.checking = false
                    State.mapDungeon.launching = false

                    setMdStatus("Status: DUNGEON FINISHED!")
                    setMdTimer("Next Dungeon: Returning...")
                    State.helpers.queueWebhookUpdate()

                    task.wait(2)

                    local content = resultsGui:FindFirstChild("Content")
                    local returnBtn = content and content:FindFirstChild("Return")

                    if returnBtn then
                        setMdStatus("Status: RETURNING TO LOBBY...")
                        setMdTimer("Next Dungeon: Waiting...")
                        State.helpers.queueWebhookUpdate()
                        State.helpers.fireButtonConnections(returnBtn)
                    end

                    repeat
                        task.wait(0.25)
                    until not resultsGui.Parent
                        or not resultsGui.Enabled
                        or not State.mapDungeon.autoActive
                        or not State.helpers.isInMapDungeonGamemode()

                    State.mapDungeon.handlingResults = false

                    if State.automation.savedFarmCFrame and State.automation.tpEnabled then
                        State.automation.pendingFarmReturn = true
                    end

                    if State.mapDungeon.autoActive then
                        setMdStatus("Status: CHECKING DUNGEON...")
                        setMdTimer("Next Dungeon: Ready")
                        State.mapDungeon.checking = true
                    else
                        setMdStatus("Status: IDLE")
                        setMdTimer("Next Dungeon: Ready")
                    end

                    State.helpers.queueWebhookUpdate()
                end)
            end
        end)
    end

    local existingResults = PlayerGui:FindFirstChild("Results")
    if existingResults then
        hookResultsUI(existingResults)
    end

    PlayerGui.ChildAdded:Connect(function(child)
        if child.Name == "Results" then
            hookResultsUI(child)
        end
    end)

    local currentMap = State.mapDungeon.selectedMap or "PunkCity"
    local mapOk = false
    for _, m in ipairs(mapOptions) do
        if m == currentMap then
            mapOk = true
            break
        end
    end
    if not mapOk then
        currentMap = mapOptions[1]
    end
    State.mapDungeon.selectedMap = currentMap

    local currentDiff = State.mapDungeon.selectedDifficulty or "Easy"
    local diffOk = false
    for _, d in ipairs(difficultyOptions) do
        if d == currentDiff then
            diffOk = true
            break
        end
    end
    if not diffOk then
        currentDiff = difficultyOptions[1]
    end
    State.mapDungeon.selectedDifficulty = currentDiff

    local mapDropdown = DungeonTab:CreateDropdown({
        Name = "Map",
        Options = mapOptions,
        CurrentOption = State.mapDungeon.selectedMap,
        MultipleOptions = false,
        Callback = function(Option)
            local selected = Option
            if typeof(Option) == "table" then
                selected = Option[1]
            end
            if type(selected) == "string" and selected ~= "" then
                State.mapDungeon.selectedMap = selected
                State.helpers.queueWebhookUpdate(true)
            end
        end,
    })

    local difficultyDropdown = DungeonTab:CreateDropdown({
        Name = "Difficulty",
        Options = difficultyOptions,
        CurrentOption = State.mapDungeon.selectedDifficulty,
        MultipleOptions = false,
        Callback = function(Option)
            local selected = Option
            if typeof(Option) == "table" then
                selected = Option[1]
            end
            if type(selected) == "string" and selected ~= "" then
                State.mapDungeon.selectedDifficulty = selected
                State.helpers.queueWebhookUpdate(true)
            end
        end,
    })

    local mdToggle = DungeonTab:CreateToggle({
        Name = "Auto Dungeon Loop",
        CurrentValue = State.mapDungeon.autoActive == true,
        Callback = function(Value)
            State.mapDungeon.autoActive = Value
            State.helpers.bumpMapDungeonGeneration()

            if not Value then
                State.helpers.resetMapDungeonState(false)
                setMdStatus("Status: IDLE")
                setMdTimer("Next Dungeon: Ready")
            else
                if State.helpers.isBossRushBlockingRaidAndInfQueues() then
                    setMdStatus("Status: WAITING FOR BOSS RUSH...")
                    setMdTimer("Next Dungeon: Blocked")
                elseif isDefenseTierBlocking() then
                    setMdStatus("Status: WAITING FOR DEFENSE...")
                    setMdTimer("Next Dungeon: Blocked")
                else
                    local onCooldown = State.mapDungeon.serverCooldownEnd > tick()
                    State.helpers.resetMapDungeonState(not onCooldown)
                    if onCooldown then
                        local remaining = math.max(0, math.ceil(State.mapDungeon.serverCooldownEnd - tick()))
                        setMdStatus("Status: SYNCED COOLDOWN")
                        setMdTimer(string.format("Next Dungeon: %02dm %02ds", math.floor(remaining / 60), remaining % 60))
                    else
                        setMdStatus("Status: CHECKING DUNGEON...")
                        setMdTimer("Next Dungeon: Ready")
                    end
                end
            end

            State.helpers.queueWebhookUpdate(true)
        end,
    })

    task.spawn(function()
        while true do
            if State.mapDungeon.autoActive
                and State.helpers.isMapDungeonStarted()
                and not State.mapDungeon.handlingResults
                and not State.helpers.isBossRushBlockingRaidAndInfQueues() then

                local mobFolder = enemyRoot:FindFirstChild("Client")

                if mobFolder then
                    local mobs = mobFolder:GetChildren()
                    local mobCount = #mobs

                    if mobCount > 0 and mobCount <= 15 then
                        local char = LocalPlayer.Character
                        local myRoot = char and char:FindFirstChild("HumanoidRootPart")

                        if myRoot then
                            local closest = nil
                            local dist = math.huge

                            for _, mob in ipairs(mobs) do
                                local hrp = mob:FindFirstChild("EnemyHitbox") or mob:FindFirstChild("HumanoidRootPart")
                                if hrp then
                                    local magnitude = (myRoot.Position - hrp.Position).Magnitude
                                    if magnitude < dist then
                                        dist = magnitude
                                        closest = hrp
                                    end
                                end
                            end

                            if closest then
                                setMdStatus("Status: FIGHTING")
                                myRoot.CFrame = closest.CFrame * CFrame.new(0, 3, 0)
                            end
                        end
                    end
                end
            end

            task.wait(0.1)
        end
    end)

    task.spawn(function()
        while true do
            if State.mapDungeon.autoActive
                and not State.mapDungeon.handlingResults
                and not State.helpers.isInMapDungeonGamemode()
                and not State.helpers.isInDefenseGamemode()
                and not State.helpers.isInRaidGamemode()
                and not State.helpers.isInInfCastleGamemode()
                and not State.mapDungeon.launching
                and not State.helpers.isBossRushBlockingRaidAndInfQueues()
                and not isDefenseTierBlocking()
                and State.mapDungeon.serverCooldownEnd <= tick() then

                State.mapDungeon.checking = true
                setMdStatus("Status: CHECKING DUNGEON...")
                setMdTimer("Next Dungeon: Ready")
                State.helpers.queueWebhookUpdate()

                local myGen = State.helpers.bumpMapDungeonGeneration()

                State.mapDungeon.checking = false
                State.mapDungeon.launching = true

                setMdStatus("Status: CREATING DUNGEON...")
                setMdTimer("Next Dungeon: Launching...")
                State.helpers.queueWebhookUpdate()

                local mapName = State.mapDungeon.selectedMap or "PunkCity"
                local diff = State.mapDungeon.selectedDifficulty or "Easy"
                local createArgs = {
                    {
                        {
                            "GamemodeSystem",
                            "Create",
                            "Dungeon",
                            mapName,
                            diff,
                            n = 6,
                        },
                        "\002",
                    },
                }

                local tCreate = tick()
                local roomSnap = State.helpers.snapshotGamemodeFolderNames()
                BridgeNet:FireServer(unpack(createArgs))

                local roomReady = State.helpers.waitForGamemodeRoomCreated(roomSnap, 6, function()
                    return (State.mapDungeon.serverCooldownEnd or 0) > tick()
                end)

                if not State.mapDungeon.autoActive
                    or not State.helpers.isCurrentMapDungeonGeneration(myGen)
                    or State.helpers.isBossRushBlockingRaidAndInfQueues()
                    or isDefenseTierBlocking()
                    or State.helpers.isInRaidGamemode()
                    or State.helpers.isInInfCastleGamemode()
                    or State.helpers.isInDefenseGamemode() then
                    State.mapDungeon.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                if (State.mapDungeon.serverCooldownEnd or 0) > tick() or not roomReady then
                    State.mapDungeon.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                State.helpers.sendGamemodeCreateChat("Dung")

                local remaining = State.helpers.getGamemodeStartDelay() - (tick() - tCreate)
                if remaining > 0 then
                    task.wait(remaining)
                end

                if (State.mapDungeon.serverCooldownEnd or 0) > tick() then
                    State.mapDungeon.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                if not State.mapDungeon.autoActive
                    or not State.helpers.isCurrentMapDungeonGeneration(myGen)
                    or State.helpers.isBossRushBlockingRaidAndInfQueues()
                    or isDefenseTierBlocking()
                    or State.helpers.isInRaidGamemode()
                    or State.helpers.isInInfCastleGamemode()
                    or State.helpers.isInDefenseGamemode() then
                    State.mapDungeon.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                setMdStatus("Status: STARTING DUNGEON...")
                setMdTimer("Next Dungeon: Starting...")
                State.helpers.queueWebhookUpdate()

                local startArgs = {
                    {
                        {
                            "GamemodeSystem",
                            "Start",
                            "Dungeon",
                            10686337651,
                            n = 4,
                        },
                        "\002",
                    },
                }

                BridgeNet:FireServer(unpack(startArgs))

                task.wait(3)

                if not State.mapDungeon.autoActive
                    or not State.helpers.isCurrentMapDungeonGeneration(myGen)
                    or State.helpers.isBossRushBlockingRaidAndInfQueues()
                    or isDefenseTierBlocking()
                    or State.helpers.isInRaidGamemode()
                    or State.helpers.isInInfCastleGamemode()
                    or State.helpers.isInDefenseGamemode() then
                    State.mapDungeon.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                State.mapDungeon.launching = false

                task.wait(2)

                if State.helpers.isMapDungeonStarted() then
                    setMdStatus("Status: DUNGEON RUNNING")
                    setMdTimer("Next Dungeon: In Progress")
                    State.mapDungeon.checking = false
                else
                    setMdStatus("Status: CHECKING DUNGEON...")
                    setMdTimer("Next Dungeon: Waiting Join...")
                    State.mapDungeon.checking = true
                end

                State.helpers.queueWebhookUpdate()
            else
                if not State.mapDungeon.autoActive then
                    State.mapDungeon.checking = false
                    setMdStatus("Status: IDLE")
                    setMdTimer("Next Dungeon: Ready")
                elseif State.mapDungeon.serverCooldownEnd > tick()
                    and not State.helpers.isInMapDungeonGamemode()
                    and not State.mapDungeon.handlingResults then
                    State.mapDungeon.checking = false
                    local remaining = math.max(0, math.ceil(State.mapDungeon.serverCooldownEnd - tick()))
                    setMdStatus("Status: SYNCED COOLDOWN")
                    setMdTimer(string.format("Next Dungeon: %02dm %02ds", math.floor(remaining / 60), remaining % 60))
                elseif State.helpers.isBossRushBlockingRaidAndInfQueues()
                    and not State.helpers.isInMapDungeonGamemode()
                    and not State.mapDungeon.handlingResults then
                    State.mapDungeon.checking = false
                    setMdStatus("Status: WAITING FOR BOSS RUSH...")
                    setMdTimer("Next Dungeon: Blocked")
                elseif isDefenseTierBlocking()
                    and not State.helpers.isInMapDungeonGamemode()
                    and not State.mapDungeon.handlingResults then
                    State.mapDungeon.checking = false
                    setMdStatus("Status: WAITING FOR DEFENSE...")
                    setMdTimer("Next Dungeon: Blocked")
                elseif State.helpers.isInRaidGamemode() and not State.mapDungeon.handlingResults then
                    State.mapDungeon.checking = false
                    setMdStatus("Status: WAITING FOR RAID TO FINISH...")
                    setMdTimer("Next Dungeon: Ready")
                elseif State.helpers.isInInfCastleGamemode() and not State.mapDungeon.handlingResults then
                    State.mapDungeon.checking = false
                    setMdStatus("Status: WAITING FOR INF CASTLE TO FINISH...")
                    setMdTimer("Next Dungeon: Ready")
                elseif State.helpers.isMapDungeonStarted() and not State.mapDungeon.handlingResults then
                    setMdStatus("Status: DUNGEON RUNNING")
                    setMdTimer("Next Dungeon: In Progress")
                end
            end

            if State.mapDungeon.autoActive
                and State.mapDungeon.serverCooldownEnd > tick()
                and not State.helpers.isInMapDungeonGamemode()
                and not State.mapDungeon.handlingResults then
                cooldownProbeAndWait()
            else
                task.wait(0.2)
            end
        end
    end)

    table.insert(State.configUiSync, function()
        if mapDropdown then
            mapDropdown:Set(State.mapDungeon.selectedMap or "PunkCity", true)
        end
        if difficultyDropdown then
            difficultyDropdown:Set(State.mapDungeon.selectedDifficulty or "Easy", true)
        end
        if mdToggle then
            mdToggle:Set(State.mapDungeon.autoActive == true, true)
        end
    end)
end
