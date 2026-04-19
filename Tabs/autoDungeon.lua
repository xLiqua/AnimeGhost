return function(Window, State)
    local PlayerGui = State.services.PlayerGui
    local BridgeNet = State.services.BridgeNet
    local enemyRoot = State.services.enemyRoot
    local LocalPlayer = State.services.LocalPlayer

    local mapOptions = {
        "CursedZone",
        "BizarreDesert",
    }

    local function probeDungeonCooldownFromGame()
        local before = State.helpers.snapshotGamemodeFolderNames()
        local mapName = State.dungeon.selectedMode or "CursedZone"
        BridgeNet:FireServer(unpack({
            { { "GamemodeSystem", "Create", "Defense Mode", mapName, "Easy", n = 6 }, "\002" },
        }))
        if State.helpers.waitForGamemodeProbeOutcome(before, function()
            return (State.dungeon.serverCooldownEnd or 0) > tick()
        end) then
            State.helpers.bumpDungeonGeneration()
            State.helpers.fireGamemodeStart("Defense Mode")
            return true
        end
        return false
    end

    local function cooldownProbeAndWait()
        local endTime = State.dungeon.serverCooldownEnd or 0
        if endTime > tick() then
            local remaining = endTime - tick()
            task.wait(math.min(remaining + 0.05, 5))
            return
        end
        if not probeDungeonCooldownFromGame() then
            State.helpers.waitAfterFailedCooldownProbe()
        end
    end

    local DefenseTab = Window:CreateTab("Auto Defense", 4483362458)

    local statusLabel = DefenseTab:CreateLabel("Status: IDLE")
    local timerLabel = DefenseTab:CreateLabel("Next Defense: Ready")

    local function setDgStatus(text)
        if statusLabel then
            statusLabel:Set(text)
        end
    end

    local function setDgTimer(text)
        if timerLabel then
            timerLabel:Set(text)
        end
    end

    local function hookResultsUI(resultsGui)
        if State.dungeon.hookedResults[resultsGui] then
            return
        end
        State.dungeon.hookedResults[resultsGui] = true

        resultsGui:GetPropertyChangedSignal("Enabled"):Connect(function()
            if State.dungeon.autoDungeonActive
                and resultsGui.Enabled
                and not State.dungeon.handlingResults
                and State.helpers.isInDefenseGamemode() then
                task.spawn(function()
                    State.helpers.bumpDungeonGeneration()
                    State.dungeon.handlingResults = true
                    State.dungeon.checking = false
                    State.dungeon.launching = false

                    setDgStatus("Status: DEFENSE FINISHED!")
                    setDgTimer("Next Defense: Returning...")
                    State.helpers.queueWebhookUpdate()

                    task.wait(2)

                    local content = resultsGui:FindFirstChild("Content")
                    local returnBtn = content and content:FindFirstChild("Return")

                    if returnBtn then
                        setDgStatus("Status: RETURNING TO LOBBY...")
                        setDgTimer("Next Defense: Waiting...")
                        State.helpers.queueWebhookUpdate()
                        State.helpers.fireButtonConnections(returnBtn)
                    end

                    repeat
                        task.wait(0.25)
                    until not resultsGui.Parent
                        or not resultsGui.Enabled
                        or not State.dungeon.autoDungeonActive
                        or not State.helpers.isInDefenseGamemode()

                    State.dungeon.handlingResults = false

                    if State.automation.savedFarmCFrame and State.automation.tpEnabled then
                        State.automation.pendingFarmReturn = true
                    end

                    if State.dungeon.autoDungeonActive then
                        setDgStatus("Status: CHECKING DEFENSE...")
                        setDgTimer("Next Defense: Ready")
                        State.dungeon.checking = true
                    else
                        setDgStatus("Status: IDLE")
                        setDgTimer("Next Defense: Ready")
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

    local currentMap = State.dungeon.selectedMode or "CursedZone"
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
    State.dungeon.selectedMode = currentMap

    local mapDropdown = DefenseTab:CreateDropdown({
        Name = "Map",
        Options = mapOptions,
        CurrentOption = State.dungeon.selectedMode,
        MultipleOptions = false,
        Callback = function(Option)
            local selected = Option
            if typeof(Option) == "table" then
                selected = Option[1]
            end
            if type(selected) == "string" and selected ~= "" then
                State.dungeon.selectedMode = selected
                State.helpers.queueWebhookUpdate(true)
            end
        end,
    })

    local dgToggle = DefenseTab:CreateToggle({
        Name = "Auto Defense Mode",
        CurrentValue = State.dungeon.autoDungeonActive == true,
        Callback = function(Value)
            State.dungeon.autoDungeonActive = Value
            State.helpers.bumpDungeonGeneration()

            if not Value then
                State.helpers.resetDungeonState(false)
                setDgStatus("Status: IDLE")
                setDgTimer("Next Defense: Ready")
            else
                if State.helpers.isBossRushBlockingRaidAndInfQueues() then
                    setDgStatus("Status: WAITING FOR BOSS RUSH...")
                    setDgTimer("Next Defense: Blocked")
                else
                    local onCooldown = State.dungeon.serverCooldownEnd > tick()
                    State.helpers.resetDungeonState(not onCooldown)
                    if onCooldown then
                        local remaining = math.max(0, math.ceil(State.dungeon.serverCooldownEnd - tick()))
                        setDgStatus("Status: SYNCED COOLDOWN")
                        setDgTimer(string.format("Next Defense: %02dm %02ds", math.floor(remaining / 60), remaining % 60))
                    else
                        setDgStatus("Status: CHECKING DEFENSE...")
                        setDgTimer("Next Defense: Ready")
                    end
                end
            end

            State.helpers.queueWebhookUpdate(true)
        end,
    })

    task.spawn(function()
        while true do
            if State.dungeon.autoDungeonActive
                and State.helpers.isDefenseStarted()
                and not State.dungeon.handlingResults
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
                                setDgStatus("Status: FIGHTING")
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
            if State.dungeon.autoDungeonActive
                and not State.dungeon.handlingResults
                and not State.helpers.isInDefenseGamemode()
                and not State.helpers.isInMapDungeonGamemode()
                and not State.helpers.isInRaidGamemode()
                and not State.helpers.isInInfCastleGamemode()
                and not State.dungeon.launching
                and not State.helpers.isBossRushBlockingRaidAndInfQueues()
                and State.dungeon.serverCooldownEnd <= tick() then

                State.dungeon.checking = true
                setDgStatus("Status: CHECKING DEFENSE...")
                setDgTimer("Next Defense: Ready")
                State.helpers.queueWebhookUpdate()

                local myGen = State.helpers.bumpDungeonGeneration()

                State.dungeon.checking = false
                State.dungeon.launching = true

                setDgStatus("Status: CREATING DEFENSE...")
                setDgTimer("Next Defense: Launching...")
                State.helpers.queueWebhookUpdate()

                local mapName = State.dungeon.selectedMode or "CursedZone"
                local createArgs = {
                    {
                        {
                            "GamemodeSystem",
                            "Create",
                            "Defense Mode",
                            mapName,
                            "Easy",
                            n = 6,
                        },
                        "\002",
                    },
                }

                local tCreate = tick()
                local roomSnap = State.helpers.snapshotGamemodeFolderNames()
                BridgeNet:FireServer(unpack(createArgs))

                local roomReady = State.helpers.waitForGamemodeRoomCreated(roomSnap, 6, function()
                    return (State.dungeon.serverCooldownEnd or 0) > tick()
                end)

                if not State.dungeon.autoDungeonActive
                    or not State.helpers.isCurrentDungeonGeneration(myGen)
                    or State.helpers.isBossRushBlockingRaidAndInfQueues()
                    or State.helpers.isInRaidGamemode()
                    or State.helpers.isInInfCastleGamemode()
                    or State.helpers.isInMapDungeonGamemode() then
                    State.dungeon.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                if (State.dungeon.serverCooldownEnd or 0) > tick() or not roomReady then
                    State.dungeon.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                State.helpers.sendGamemodeCreateChat("Def")

                local remaining = State.helpers.getGamemodeStartDelay() - (tick() - tCreate)
                if remaining > 0 then
                    task.wait(remaining)
                end

                if (State.dungeon.serverCooldownEnd or 0) > tick() then
                    State.dungeon.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                if not State.dungeon.autoDungeonActive
                    or not State.helpers.isCurrentDungeonGeneration(myGen)
                    or State.helpers.isBossRushBlockingRaidAndInfQueues()
                    or State.helpers.isInRaidGamemode()
                    or State.helpers.isInInfCastleGamemode()
                    or State.helpers.isInMapDungeonGamemode() then
                    State.dungeon.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                setDgStatus("Status: STARTING DEFENSE...")
                setDgTimer("Next Defense: Starting...")
                State.helpers.queueWebhookUpdate()

                local startArgs = {
                    {
                        {
                            "GamemodeSystem",
                            "Start",
                            "Defense Mode",
                            10686337651,
                            n = 4,
                        },
                        "\002",
                    },
                }

                BridgeNet:FireServer(unpack(startArgs))

                task.wait(3)

                if not State.dungeon.autoDungeonActive
                    or not State.helpers.isCurrentDungeonGeneration(myGen)
                    or State.helpers.isBossRushBlockingRaidAndInfQueues()
                    or State.helpers.isInRaidGamemode()
                    or State.helpers.isInInfCastleGamemode()
                    or State.helpers.isInMapDungeonGamemode() then
                    State.dungeon.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                State.dungeon.launching = false

                task.wait(2)

                if State.helpers.isDefenseStarted() then
                    setDgStatus("Status: DEFENSE RUNNING")
                    setDgTimer("Next Defense: In Progress")
                    State.dungeon.checking = false
                else
                    setDgStatus("Status: CHECKING DEFENSE...")
                    setDgTimer("Next Defense: Waiting Join...")
                    State.dungeon.checking = true
                end

                State.helpers.queueWebhookUpdate()
            else
                if not State.dungeon.autoDungeonActive then
                    State.dungeon.checking = false
                    setDgStatus("Status: IDLE")
                    setDgTimer("Next Defense: Ready")
                elseif State.dungeon.serverCooldownEnd > tick()
                    and not State.helpers.isInDefenseGamemode()
                    and not State.dungeon.handlingResults then
                    State.dungeon.checking = false
                    local remaining = math.max(0, math.ceil(State.dungeon.serverCooldownEnd - tick()))
                    setDgStatus("Status: SYNCED COOLDOWN")
                    setDgTimer(string.format("Next Defense: %02dm %02ds", math.floor(remaining / 60), remaining % 60))
                elseif State.helpers.isBossRushBlockingRaidAndInfQueues()
                    and not State.helpers.isInDefenseGamemode()
                    and not State.dungeon.handlingResults then
                    State.dungeon.checking = false
                    setDgStatus("Status: WAITING FOR BOSS RUSH...")
                    setDgTimer("Next Defense: Blocked")
                elseif State.helpers.isInRaidGamemode() and not State.dungeon.handlingResults then
                    State.dungeon.checking = false
                    setDgStatus("Status: WAITING FOR RAID TO FINISH...")
                    setDgTimer("Next Defense: Ready")
                elseif State.helpers.isInInfCastleGamemode() and not State.dungeon.handlingResults then
                    State.dungeon.checking = false
                    setDgStatus("Status: WAITING FOR INF CASTLE TO FINISH...")
                    setDgTimer("Next Defense: Ready")
                elseif State.helpers.isInMapDungeonGamemode() and not State.dungeon.handlingResults then
                    State.dungeon.checking = false
                    setDgStatus("Status: WAITING FOR DUNGEON TO FINISH...")
                    setDgTimer("Next Defense: Ready")
                elseif State.helpers.isDefenseStarted() and not State.dungeon.handlingResults then
                    setDgStatus("Status: DEFENSE RUNNING")
                    setDgTimer("Next Defense: In Progress")
                end
            end

            if State.dungeon.autoDungeonActive
                and State.dungeon.serverCooldownEnd > tick()
                and not State.helpers.isInDefenseGamemode()
                and not State.dungeon.handlingResults then
                cooldownProbeAndWait()
            else
                task.wait(0.2)
            end
        end
    end)

    table.insert(State.configUiSync, function()
        if mapDropdown then
            mapDropdown:Set(State.dungeon.selectedMode or "CursedZone", true)
        end
        if dgToggle then
            dgToggle:Set(State.dungeon.autoDungeonActive == true, true)
        end
    end)
end
