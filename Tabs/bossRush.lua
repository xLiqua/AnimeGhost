return function(Window, State)
    local PlayerGui = State.services.PlayerGui
    local BridgeNet = State.services.BridgeNet

    local function fireButton(btn)
        if not btn then
            return false
        end

        local fired = false

        local ok1, mouseConnections = pcall(getconnections, btn.MouseButton1Click)
        if ok1 and mouseConnections then
            for _, v in ipairs(mouseConnections) do
                pcall(function()
                    v:Fire()
                end)
                fired = true
            end
        end

        if not fired then
            local ok2, activatedConnections = pcall(getconnections, btn.Activated)
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

    local BossRushTab = Window:CreateTab("Boss Rush", 4483362458)

    local statusLabel = BossRushTab:CreateLabel("Status: IDLE")
    local timerLabel = BossRushTab:CreateLabel("Next Boss Rush: Ready")

    local modeOptions = {
        "Scientist",
        "Demon Fox",
    }

    local difficultyOptions = {
        "Easy",
        "Medium",
        "Hard",
    }

    local currentMode = State.bossRush.selectedMode or "Scientist"
    local modeOk = false
    for _, m in ipairs(modeOptions) do
        if m == currentMode then
            modeOk = true
            break
        end
    end
    if not modeOk then
        currentMode = modeOptions[1]
    end
    State.bossRush.selectedMode = currentMode

    local currentDifficulty = State.bossRush.selectedDifficulty or "Easy"
    local diffOk = false
    for _, d in ipairs(difficultyOptions) do
        if d == currentDifficulty then
            diffOk = true
            break
        end
    end
    if not diffOk then
        currentDifficulty = difficultyOptions[1]
    end
    State.bossRush.selectedDifficulty = currentDifficulty

    local modeDropdown = BossRushTab:CreateDropdown({
        Name = "Mode",
        Options = modeOptions,
        CurrentOption = State.bossRush.selectedMode,
        MultipleOptions = false,
        Callback = function(Option)
            local selected = Option
            if typeof(Option) == "table" then
                selected = Option[1]
            end
            if type(selected) == "string" and selected ~= "" then
                State.bossRush.selectedMode = selected
                State.helpers.queueWebhookUpdate(true)
            end
        end,
    })

    local difficultyDropdown = BossRushTab:CreateDropdown({
        Name = "Difficulty",
        Options = difficultyOptions,
        CurrentOption = State.bossRush.selectedDifficulty,
        MultipleOptions = false,
        Callback = function(Option)
            local selected = Option
            if typeof(Option) == "table" then
                selected = Option[1]
            end
            if type(selected) == "string" and selected ~= "" then
                State.bossRush.selectedDifficulty = selected
                State.helpers.queueWebhookUpdate(true)
            end
        end,
    })

    local function probeBossRushCooldownFromGame()
        local before = State.helpers.snapshotGamemodeFolderNames()
        local mode = State.bossRush.selectedMode or "Scientist"
        local difficulty = State.bossRush.selectedDifficulty or "Easy"
        BridgeNet:FireServer(unpack({ { { "GamemodeSystem", "Create", "Boss Rush", mode, difficulty, n = 6 }, "\002" } }))
        if State.helpers.waitForGamemodeProbeOutcome(before, function()
            return (State.bossRush.serverCooldownEnd or 0) > tick()
        end) then
            State.helpers.bumpBossRushGeneration()
            State.helpers.fireGamemodeStart("Boss Rush")
            return true
        end
        return false
    end

    -- Only called when serverCooldownEnd > tick(). Probing would FireServer(Create) every few seconds — spam.
    local function cooldownProbeAndWait()
        local endTime = State.bossRush.serverCooldownEnd or 0
        if endTime > tick() then
            local remaining = endTime - tick()
            task.wait(math.min(remaining + 0.05, 5))
            return
        end
        if not probeBossRushCooldownFromGame() then
            State.helpers.waitAfterFailedCooldownProbe()
        end
    end

    local function setBrStatus(text)
        if statusLabel then
            statusLabel:Set(text)
        end
    end

    local function setBrTimer(text)
        if timerLabel then
            timerLabel:Set(text)
        end
    end

    local function hookResultsUI(resultsGui)
        if State.bossRush.hookedResults[resultsGui] then
            return
        end
        State.bossRush.hookedResults[resultsGui] = true

        resultsGui:GetPropertyChangedSignal("Enabled"):Connect(function()
            if State.bossRush.autoBossRushActive and resultsGui.Enabled and not State.bossRush.handlingResults and State.helpers.isInBossRushGamemode() then
                task.spawn(function()
                    State.helpers.bumpBossRushGeneration()
                    State.bossRush.handlingResults = true
                    State.bossRush.checking = false
                    State.bossRush.launching = false

                    setBrStatus("Status: BOSS RUSH FINISHED!")
                    setBrTimer("Next Boss Rush: Returning...")
                    State.helpers.queueWebhookUpdate()

                    task.wait(2)

                    local content = resultsGui:FindFirstChild("Content")
                    local returnBtn = content and content:FindFirstChild("Return")

                    if returnBtn then
                        setBrStatus("Status: RETURNING TO LOBBY...")
                        setBrTimer("Next Boss Rush: Waiting...")
                        State.helpers.queueWebhookUpdate()
                        fireButton(returnBtn)
                    end

                    repeat
                        task.wait(0.25)
                    until not resultsGui.Parent
                        or not resultsGui.Enabled
                        or not State.bossRush.autoBossRushActive
                        or not State.helpers.isInBossRushGamemode()

                    State.bossRush.handlingResults = false

                    if State.automation.savedFarmCFrame and State.automation.tpEnabled then
                        State.automation.pendingFarmReturn = true
                    end

                    if State.bossRush.autoBossRushActive then
                        setBrStatus("Status: CHECKING BOSS RUSH...")
                        setBrTimer("Next Boss Rush: Ready")
                        State.bossRush.checking = true
                    else
                        setBrStatus("Status: IDLE")
                        setBrTimer("Next Boss Rush: Ready")
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

    local brToggle = BossRushTab:CreateToggle({
        Name = "Auto Boss Rush",
        CurrentValue = State.bossRush.autoBossRushActive == true,
        Callback = function(Value)
            State.bossRush.autoBossRushActive = Value
            State.helpers.bumpBossRushGeneration()

            if not Value then
                State.helpers.resetBossRushState(false)
                setBrStatus("Status: IDLE")
                setBrTimer("Next Boss Rush: Ready")
            else
                local onCooldown = State.bossRush.serverCooldownEnd > tick()
                -- "Checking" only when we can actually attempt a launch soon; on server cooldown, stay idle for priority/webhook.
                State.helpers.resetBossRushState(not onCooldown)
                if onCooldown then
                    local remaining = math.max(0, math.ceil(State.bossRush.serverCooldownEnd - tick()))
                    setBrStatus("Status: SYNCED COOLDOWN")
                    setBrTimer(string.format("Next Boss Rush: %02dm %02ds", math.floor(remaining / 60), remaining % 60))
                else
                    setBrStatus("Status: CHECKING BOSS RUSH...")
                    setBrTimer("Next Boss Rush: Ready")
                end
            end

            State.helpers.queueWebhookUpdate(true)
        end,
    })

    task.spawn(function()
        while true do
            if State.bossRush.autoBossRushActive
                and not State.bossRush.handlingResults
                and not State.helpers.isInBossRushGamemode()
                and not State.helpers.isInRaidGamemode()
                and not State.helpers.isInInfCastleGamemode()
                and not State.helpers.isInDefenseGamemode()
                and not State.helpers.isInMapDungeonGamemode()
                and not State.bossRush.launching
                and State.bossRush.serverCooldownEnd <= tick() then

                State.bossRush.checking = true
                setBrStatus("Status: CHECKING BOSS RUSH...")
                setBrTimer("Next Boss Rush: Ready")
                State.helpers.queueWebhookUpdate()

                local myGen = State.helpers.bumpBossRushGeneration()

                State.bossRush.checking = false
                State.bossRush.launching = true

                setBrStatus("Status: CREATING BOSS RUSH...")
                setBrTimer("Next Boss Rush: Launching...")
                State.helpers.queueWebhookUpdate()

                local mode = State.bossRush.selectedMode or "Scientist"
                local difficulty = State.bossRush.selectedDifficulty or "Easy"
                local createArgs = {
                    {
                        {
                            "GamemodeSystem",
                            "Create",
                            "Boss Rush",
                            mode,
                            difficulty,
                            n = 6
                        },
                        "\002"
                    }
                }

                local tCreate = tick()
                local roomSnap = State.helpers.snapshotGamemodeFolderNames()
                BridgeNet:FireServer(unpack(createArgs))

                local roomReady = State.helpers.waitForGamemodeRoomCreated(roomSnap, 6, function()
                    return (State.bossRush.serverCooldownEnd or 0) > tick()
                end)

                if not State.bossRush.autoBossRushActive
                    or not State.helpers.isCurrentBossRushGeneration(myGen)
                    or State.helpers.isInRaidGamemode()
                    or State.helpers.isInInfCastleGamemode()
                    or State.helpers.isInDefenseGamemode()
                    or State.helpers.isInMapDungeonGamemode() then
                    State.bossRush.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                if (State.bossRush.serverCooldownEnd or 0) > tick() or not roomReady then
                    State.bossRush.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                State.helpers.sendGamemodeCreateChat("Rush")

                local remaining = State.helpers.getGamemodeStartDelay() - (tick() - tCreate)
                if remaining > 0 then
                    task.wait(remaining)
                end

                if (State.bossRush.serverCooldownEnd or 0) > tick() then
                    State.bossRush.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                if not State.bossRush.autoBossRushActive
                    or not State.helpers.isCurrentBossRushGeneration(myGen)
                    or State.helpers.isInRaidGamemode()
                    or State.helpers.isInInfCastleGamemode()
                    or State.helpers.isInDefenseGamemode()
                    or State.helpers.isInMapDungeonGamemode() then
                    State.bossRush.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                setBrStatus("Status: STARTING BOSS RUSH...")
                setBrTimer("Next Boss Rush: Starting...")
                State.helpers.queueWebhookUpdate()

                local startArgs = {
                    {
                        {
                            "GamemodeSystem",
                            "Start",
                            "Boss Rush",
                            10686337651,
                            n = 4
                        },
                        "\002"
                    }
                }

                BridgeNet:FireServer(unpack(startArgs))

                task.wait(3)

                if not State.bossRush.autoBossRushActive
                    or not State.helpers.isCurrentBossRushGeneration(myGen)
                    or State.helpers.isInRaidGamemode()
                    or State.helpers.isInInfCastleGamemode()
                    or State.helpers.isInDefenseGamemode()
                    or State.helpers.isInMapDungeonGamemode() then
                    State.bossRush.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                State.bossRush.launching = false

                task.wait(2)

                if State.helpers.isBossRushStarted() then
                    setBrStatus("Status: BOSS RUSH RUNNING")
                    setBrTimer("Next Boss Rush: In Progress")
                    State.bossRush.checking = false
                else
                    setBrStatus("Status: CHECKING BOSS RUSH...")
                    setBrTimer("Next Boss Rush: Waiting Join...")
                    State.bossRush.checking = true
                end

                State.helpers.queueWebhookUpdate()
            else
                if not State.bossRush.autoBossRushActive then
                    State.bossRush.checking = false
                    setBrStatus("Status: IDLE")
                    setBrTimer("Next Boss Rush: Ready")
                elseif State.bossRush.serverCooldownEnd > tick()
                    and not State.helpers.isInBossRushGamemode()
                    and not State.bossRush.handlingResults then
                    State.bossRush.checking = false
                    local remaining = math.max(0, math.ceil(State.bossRush.serverCooldownEnd - tick()))
                    setBrStatus("Status: SYNCED COOLDOWN")
                    setBrTimer(string.format("Next Boss Rush: %02dm %02ds", math.floor(remaining / 60), remaining % 60))
                elseif State.helpers.isInRaidGamemode() and not State.bossRush.handlingResults then
                    State.bossRush.checking = false
                    setBrStatus("Status: WAITING FOR RAID TO FINISH...")
                    setBrTimer("Next Boss Rush: Ready")
                elseif State.helpers.isInInfCastleGamemode() and not State.bossRush.handlingResults then
                    State.bossRush.checking = false
                    setBrStatus("Status: WAITING FOR INF CASTLE TO FINISH...")
                    setBrTimer("Next Boss Rush: Ready")
                elseif State.helpers.isInDefenseGamemode() and not State.bossRush.handlingResults then
                    State.bossRush.checking = false
                    setBrStatus("Status: WAITING FOR DEFENSE TO FINISH...")
                    setBrTimer("Next Boss Rush: Ready")
                elseif State.helpers.isInMapDungeonGamemode() and not State.bossRush.handlingResults then
                    State.bossRush.checking = false
                    setBrStatus("Status: WAITING FOR DUNGEON TO FINISH...")
                    setBrTimer("Next Boss Rush: Ready")
                elseif State.helpers.isBossRushStarted() and not State.bossRush.handlingResults then
                    setBrStatus("Status: BOSS RUSH RUNNING")
                    setBrTimer("Next Boss Rush: In Progress")
                end
            end

            if State.bossRush.autoBossRushActive
                and State.bossRush.serverCooldownEnd > tick()
                and not State.helpers.isInBossRushGamemode()
                and not State.bossRush.handlingResults then
                cooldownProbeAndWait()
            else
                task.wait(0.2)
            end
        end
    end)

    table.insert(State.configUiSync, function()
        if modeDropdown then
            modeDropdown:Set(State.bossRush.selectedMode or "Scientist", true)
        end
        if difficultyDropdown then
            difficultyDropdown:Set(State.bossRush.selectedDifficulty or "Easy", true)
        end
        if brToggle then
            brToggle:Set(State.bossRush.autoBossRushActive == true, true)
        end
    end)
end
