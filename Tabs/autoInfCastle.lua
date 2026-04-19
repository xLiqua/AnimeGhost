return function(Window, State)
    local PlayerGui = State.services.PlayerGui
    local BridgeNet = State.services.BridgeNet

    local function probeInfCastleCooldownFromGame()
        local before = State.helpers.snapshotGamemodeFolderNames()
        local act = State.infCastle.selectedAct or "Act1"
        BridgeNet:FireServer(unpack({ { { "GamemodeSystem", "Create", "Infinity Castle", act, "Easy", n = 6 }, "\002" } }))
        if State.helpers.waitForGamemodeProbeOutcome(before, function()
            return (State.infCastle.serverCooldownEnd or 0) > tick()
        end) then
            State.helpers.bumpInfCastleGeneration()
            State.helpers.fireGamemodeStart("Infinity Castle")
            return true
        end
        return false
    end

    local function cooldownProbeAndWait()
        local endTime = State.infCastle.serverCooldownEnd or 0
        if endTime > tick() then
            local remaining = endTime - tick()
            task.wait(math.min(remaining + 0.05, 5))
            return
        end
        if not probeInfCastleCooldownFromGame() then
            State.helpers.waitAfterFailedCooldownProbe()
        end
    end

    local function isRaidBlockingInfCastle()
        if State.helpers.isRaidPriority() then
            return true
        end
        if State.helpers.isRaidEligibleToStartRun then
            return State.helpers.isRaidEligibleToStartRun()
        end
        return false
    end

    local function isBlockingHigherPriorityForInf()
        return State.helpers.isBossRushBlockingRaidAndInfQueues()
            or State.helpers.isDungeonBlockingRaidAndInfQueues()
    end

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

    local InfCastleTab = Window:CreateTab("Auto-InfCastle", 4483362458)

    local actOptions = {
        "Act1",
        "Act2",
    }

    local currentAct = State.infCastle.selectedAct or "Act1"
    local actOk = false
    for _, a in ipairs(actOptions) do
        if a == currentAct then
            actOk = true
            break
        end
    end
    if not actOk then
        currentAct = actOptions[1]
    end
    State.infCastle.selectedAct = currentAct

    local actDropdown = InfCastleTab:CreateDropdown({
        Name = "Act",
        Options = actOptions,
        CurrentOption = State.infCastle.selectedAct,
        MultipleOptions = false,
        Callback = function(Option)
            local selected = Option
            if typeof(Option) == "table" then
                selected = Option[1]
            end
            if selected == "Act1" or selected == "Act2" then
                State.infCastle.selectedAct = selected
                State.helpers.queueWebhookUpdate(true)
            end
        end,
    })

    local statusLabel = InfCastleTab:CreateLabel("Status: IDLE")
    local timerLabel = InfCastleTab:CreateLabel("Next Inf Castle: Ready")

    local function setInfStatus(text)
        if statusLabel then
            statusLabel:Set(text)
        end
    end

    local function setInfTimer(text)
        if timerLabel then
            timerLabel:Set(text)
        end
    end

    local function hookResultsUI(resultsGui)
        if State.infCastle.hookedResults[resultsGui] then
            return
        end
        State.infCastle.hookedResults[resultsGui] = true

        resultsGui:GetPropertyChangedSignal("Enabled"):Connect(function()
            if State.infCastle.autoInfCastleActive and resultsGui.Enabled and not State.infCastle.handlingResults and State.helpers.isInInfCastleGamemode() then
                task.spawn(function()
                    State.helpers.bumpInfCastleGeneration()
                    State.infCastle.handlingResults = true
                    State.infCastle.checking = false
                    State.infCastle.launching = false

                    setInfStatus("Status: INF CASTLE FINISHED!")
                    setInfTimer("Next Inf Castle: Returning...")
                    State.helpers.queueWebhookUpdate()

                    task.wait(2)

                    local content = resultsGui:FindFirstChild("Content")
                    local returnBtn = content and content:FindFirstChild("Return")

                    if returnBtn then
                        setInfStatus("Status: RETURNING TO LOBBY...")
                        setInfTimer("Next Inf Castle: Waiting...")
                        State.helpers.queueWebhookUpdate()
                        fireButton(returnBtn)
                    end

                    repeat
                        task.wait(0.25)
                    until not resultsGui.Parent
                        or not resultsGui.Enabled
                        or not State.infCastle.autoInfCastleActive
                        or not State.helpers.isInInfCastleGamemode()

                    State.infCastle.handlingResults = false

                    if State.infCastle.autoInfCastleActive then
                        setInfStatus("Status: CHECKING INF CASTLE...")
                        setInfTimer("Next Inf Castle: Ready")
                        State.infCastle.checking = true
                    else
                        setInfStatus("Status: IDLE")
                        setInfTimer("Next Inf Castle: Ready")
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

    local infToggle = InfCastleTab:CreateToggle({
        Name = "Auto Infinite Castle",
        CurrentValue = State.infCastle.autoInfCastleActive == true,
        Callback = function(Value)
            State.infCastle.autoInfCastleActive = Value
            State.helpers.bumpInfCastleGeneration()

            if not Value then
                State.helpers.resetInfCastleState(false)
                setInfStatus("Status: IDLE")
                setInfTimer("Next Inf Castle: Ready")
            else
                if State.helpers.isBossRushBlockingRaidAndInfQueues() then
                    setInfStatus("Status: WAITING FOR BOSS RUSH...")
                    setInfTimer("Next Inf Castle: Blocked")
                elseif State.helpers.isDungeonBlockingRaidAndInfQueues() then
                    setInfStatus("Status: WAITING FOR DEFENSE...")
                    setInfTimer("Next Inf Castle: Blocked")
                elseif isRaidBlockingInfCastle() then
                    setInfStatus("Status: WAITING FOR RAID...")
                    setInfTimer("Next Inf Castle: Blocked")
                else
                    State.helpers.resetInfCastleState(true)
                    setInfStatus("Status: CHECKING INF CASTLE...")
                    setInfTimer("Next Inf Castle: Ready")
                end
            end

            State.helpers.queueWebhookUpdate(true)
        end,
    })

    task.spawn(function()
        while true do
            if State.infCastle.autoInfCastleActive
                and not isBlockingHigherPriorityForInf()
                and not isRaidBlockingInfCastle()
                and not State.infCastle.handlingResults
                and not State.helpers.isInInfCastleGamemode()
                and not State.infCastle.launching
                and State.infCastle.serverCooldownEnd <= tick() then

                State.infCastle.checking = true
                setInfStatus("Status: CHECKING INF CASTLE...")
                setInfTimer("Next Inf Castle: Ready")
                State.helpers.queueWebhookUpdate()

                local myGen = State.helpers.bumpInfCastleGeneration()

                State.infCastle.checking = false
                State.infCastle.launching = true

                setInfStatus("Status: CREATING INF CASTLE...")
                setInfTimer("Next Inf Castle: Launching...")
                State.helpers.queueWebhookUpdate()

                local act = State.infCastle.selectedAct or "Act1"
                local createArgs = {
                    {
                        {
                            "GamemodeSystem",
                            "Create",
                            "Infinity Castle",
                            act,
                            "Easy",
                            n = 6
                        },
                        "\002"
                    }
                }

                local tCreate = tick()
                local roomSnap = State.helpers.snapshotGamemodeFolderNames()
                BridgeNet:FireServer(unpack(createArgs))

                local roomReady = State.helpers.waitForGamemodeRoomCreated(roomSnap, 6, function()
                    return (State.infCastle.serverCooldownEnd or 0) > tick()
                end)

                if not State.infCastle.autoInfCastleActive
                    or isBlockingHigherPriorityForInf()
                    or isRaidBlockingInfCastle()
                    or not State.helpers.isCurrentInfCastleGeneration(myGen) then
                    State.infCastle.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                if (State.infCastle.serverCooldownEnd or 0) > tick() or not roomReady then
                    State.infCastle.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                State.helpers.sendGamemodeCreateChat("Castle")

                local remaining = State.helpers.getGamemodeStartDelay() - (tick() - tCreate)
                if remaining > 0 then
                    task.wait(remaining)
                end

                if (State.infCastle.serverCooldownEnd or 0) > tick() then
                    State.infCastle.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                if not State.infCastle.autoInfCastleActive
                    or isBlockingHigherPriorityForInf()
                    or isRaidBlockingInfCastle()
                    or not State.helpers.isCurrentInfCastleGeneration(myGen) then
                    State.infCastle.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                setInfStatus("Status: STARTING INF CASTLE...")
                setInfTimer("Next Inf Castle: Starting...")
                State.helpers.queueWebhookUpdate()

                local startArgs = {
                    {
                        {
                            "GamemodeSystem",
                            "Start",
                            "Infinity Castle",
                            10686337651,
                            n = 4
                        },
                        "\002"
                    }
                }

                BridgeNet:FireServer(unpack(startArgs))

                task.wait(3)

                if not State.infCastle.autoInfCastleActive
                    or isBlockingHigherPriorityForInf()
                    or isRaidBlockingInfCastle()
                    or not State.helpers.isCurrentInfCastleGeneration(myGen) then
                    State.infCastle.launching = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                State.infCastle.launching = false

                task.wait(2)

                if State.helpers.isInfCastleStarted() then
                    setInfStatus("Status: INF CASTLE RUNNING")
                    setInfTimer("Next Inf Castle: In Progress")
                    State.infCastle.checking = false
                else
                    setInfStatus("Status: CHECKING INF CASTLE...")
                    setInfTimer("Next Inf Castle: Waiting Join...")
                    State.infCastle.checking = true
                end

                State.helpers.queueWebhookUpdate()
            else
                if not State.infCastle.autoInfCastleActive then
                    State.infCastle.checking = false
                    setInfStatus("Status: IDLE")
                    setInfTimer("Next Inf Castle: Ready")
                elseif State.infCastle.serverCooldownEnd > tick()
                    and not State.helpers.isInInfCastleGamemode()
                    and not State.infCastle.handlingResults then
                    local remaining = math.max(0, math.ceil(State.infCastle.serverCooldownEnd - tick()))
                    setInfStatus("Status: SYNCED COOLDOWN")
                    setInfTimer(string.format("Next Inf Castle: %02dm %02ds", math.floor(remaining / 60), remaining % 60))
                elseif State.helpers.isBossRushBlockingRaidAndInfQueues() and not State.helpers.isInInfCastleGamemode() and not State.infCastle.handlingResults then
                    setInfStatus("Status: WAITING FOR BOSS RUSH...")
                    setInfTimer("Next Inf Castle: Blocked")
                elseif State.helpers.isDungeonBlockingRaidAndInfQueues() and not State.helpers.isInInfCastleGamemode() and not State.infCastle.handlingResults then
                    setInfStatus("Status: WAITING FOR DEFENSE...")
                    setInfTimer("Next Inf Castle: Blocked")
                elseif isRaidBlockingInfCastle() and not State.helpers.isInInfCastleGamemode() and not State.infCastle.handlingResults then
                    setInfStatus("Status: WAITING FOR RAID...")
                    setInfTimer("Next Inf Castle: Blocked")
                elseif State.helpers.isInfCastleStarted() and not State.infCastle.handlingResults then
                    setInfStatus("Status: INF CASTLE RUNNING")
                    setInfTimer("Next Inf Castle: In Progress")
                end
            end

            if State.infCastle.autoInfCastleActive
                and State.infCastle.serverCooldownEnd > tick()
                and not State.helpers.isInInfCastleGamemode()
                and not State.infCastle.handlingResults then
                cooldownProbeAndWait()
            else
                task.wait(0.2)
            end
        end
    end)

    table.insert(State.configUiSync, function()
        if actDropdown then
            actDropdown:Set(State.infCastle.selectedAct or "Act1", true)
        end
        if infToggle then
            infToggle:Set(State.infCastle.autoInfCastleActive == true, true)
        end
    end)
end