return function(Window, State)
    local PlayerGui = State.services.PlayerGui
    local BridgeNet = State.services.BridgeNet
    local ReplicatedStorage = State.services.ReplicatedStorage
    local enemyRoot = State.services.enemyRoot
    local LocalPlayer = State.services.LocalPlayer
    local Framework = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Library"))
    local ticketCache = {}
    local ticketCacheTtl = 0.75

    local function isAnyRaidEnabled()
        return State.raid.autoRaidActive or State.raid.autoEasterRaidActive
    end

    local function isBlockingHigherPriorityQueues()
        return State.helpers.isBossRushBlockingRaidAndInfQueues()
            or State.helpers.isDungeonBlockingRaidAndInfQueues()
    end

    local function getTicketAmount(ticketName)
        local playerData = Framework and Framework.PlayerData
        local inv = playerData and playerData.Inventory
        if type(inv) ~= "table" then
            return 0
        end

        local now = tick()
        local cached = ticketCache[ticketName]
        if cached and now - cached.t < ticketCacheTtl then
            return cached.v
        end

        local targetName = string.lower(tostring(ticketName))
        local total = 0

        local function readAmount(value)
            if type(value) == "number" then
                return math.max(0, value)
            end
            if type(value) == "table" then
                local n = tonumber(value._am or value.Amount or value.Count)
                if n then
                    return math.max(0, n)
                end
                return 1
            end
            local n = tonumber(value)
            if n then
                return math.max(0, n)
            end
            return 0
        end

        -- Fast path: direct inventory key lookup.
        local direct = rawget(inv, ticketName)
        if direct ~= nil then
            local directAmount = readAmount(direct)
            ticketCache[ticketName] = { v = directAmount, t = now }
            return directAmount
        end

        local seen = {}
        local maxDepth = 6
        local function scan(value, key, depth)
            if depth > maxDepth then
                return
            end
            if type(value) == "table" then
                if seen[value] then
                    return
                end
                seen[value] = true

                local name = value._n or value.Name or value.Id or key

                if name and string.lower(tostring(name)) == targetName then
                    local n = readAmount(value)
                    if n > 0 then
                        total = total + n
                    end
                end

                for childKey, childValue in pairs(value) do
                    scan(childValue, childKey, depth + 1)
                end
            elseif key and string.lower(tostring(key)) == targetName then
                local n = readAmount(value)
                if n > 0 then
                    total = total + n
                end
            end
        end

        for key, value in pairs(inv) do
            scan(value, key, 1)
        end

        ticketCache[ticketName] = { v = total, t = now }
        return total
    end

    local function getActiveRaidSelection()
        local now = tick()
        -- Priority: Normal Raid first, Easter Raid second.
        -- If both are enabled and normal ticket use is enabled, Easter can only run
        -- when normal tickets are fully depleted.
        if State.raid.autoRaidActive then
            local hasNormalTickets = getTicketAmount("RaidTickets") > 0
            local normalNeedsTickets = State.raid.useRaidTicket == true
            local normalReady = (State.raid.normalCooldownEnd or 0) <= now

            if normalReady and (not normalNeedsTickets or hasNormalTickets or not State.raid.autoEasterRaidActive) then
                return "Normal", (State.raid.selectedMode or "TitanTown")
            end
        end

        if State.raid.autoEasterRaidActive and (State.raid.easterCooldownEnd or 0) <= now then
            return "Easter", (State.raid.selectedEasterMode or "ChocolateKingdom")
        end

        return nil, nil
    end

    -- Fire Create: cooldown text updates via scanForCooldown; if a new Gamemode folder appears (room created), Start.
    local function probeRaidCooldownFromGame()
        local before = State.helpers.snapshotGamemodeFolderNames()
        if State.raid.autoRaidActive then
            local mode = State.raid.selectedMode or "TitanTown"
            BridgeNet:FireServer(unpack({ { { "GamemodeSystem", "Create", "Raid", mode, "Easy", n = 6 }, "\002" } }))
            if State.helpers.waitForGamemodeProbeOutcome(before, function()
                return (State.raid.normalCooldownEnd or 0) > tick()
            end) then
                State.helpers.bumpRaidGeneration()
                State.raid.currentRunType = "Normal"
                State.helpers.fireGamemodeStart("Raid")
                return true
            end
        end
        before = State.helpers.snapshotGamemodeFolderNames()
        if State.raid.autoEasterRaidActive then
            local mode = State.raid.selectedEasterMode or "ChocolateKingdom"
            BridgeNet:FireServer(unpack({ { { "GamemodeSystem", "Create", "Easter Raid", mode, "Easy", n = 6 }, "\002" } }))
            if State.helpers.waitForGamemodeProbeOutcome(before, function()
                return (State.raid.easterCooldownEnd or 0) > tick()
            end) then
                State.helpers.bumpRaidGeneration()
                State.raid.currentRunType = "Easter"
                State.helpers.fireGamemodeStart("Easter Raid")
                return true
            end
        end
        return false
    end

    local function cooldownProbeAndWait()
        local now = tick()
        local nextEnd = nil
        if State.raid.autoRaidActive then
            local n = State.raid.normalCooldownEnd or 0
            if n > now then
                nextEnd = n
            end
        end
        if State.raid.autoEasterRaidActive then
            local e = State.raid.easterCooldownEnd or 0
            if e > now then
                nextEnd = nextEnd and math.min(nextEnd, e) or e
            end
        end
        if nextEnd then
            task.wait(math.min(nextEnd - now + 0.05, 5))
            return
        end
        if not probeRaidCooldownFromGame() then
            State.helpers.waitAfterFailedCooldownProbe()
        end
    end

    local function shouldTpToRaidMobs()
        -- Only Normal Raid should auto-TP to mobs.
        if State.raid.currentRunType == "Normal" then
            return true
        end
        if State.raid.currentRunType == "Easter" then
            return false
        end

        -- Fallback when run type is not set yet.
        return State.raid.autoRaidActive and not State.raid.autoEasterRaidActive
    end

    local function tryUseTicket(raidType)
        local useTicket = false
        local ticketName = nil

        if raidType == "Normal" then
            useTicket = State.raid.useRaidTicket == true
            ticketName = "RaidTickets"
        elseif raidType == "Easter" then
            useTicket = State.raid.useEasterTicket == true
            ticketName = "EasterTickets"
        end

        if not useTicket or not ticketName then
            return
        end

        if getTicketAmount(ticketName) <= 0 then
            return
        end

        local useArgs = {
            {
                {
                    "ItemSystem",
                    "Use",
                    ticketName,
                    n = 3
                },
                "\002"
            }
        }

        BridgeNet:FireServer(unpack(useArgs))
        task.wait(0.2)
    end

    local function hookResultsUI(resultsGui)
        if State.raid.hookedResults[resultsGui] then
            return
        end
        State.raid.hookedResults[resultsGui] = true

        resultsGui:GetPropertyChangedSignal("Enabled"):Connect(function()
            if isAnyRaidEnabled() and resultsGui.Enabled and not State.raid.handlingResults and State.helpers.isInRaidGamemode() then
                task.spawn(function()
                    State.helpers.bumpRaidGeneration()
                    State.raid.handlingResults = true
                    State.raid.checkingRaid = false
                    State.raid.launchingRaid = false
                    State.raid.currentRunType = nil
                    State.helpers.setStatus("Status: RAID FINISHED!")
                    State.helpers.queueWebhookUpdate()

                    task.wait(2)

                    local content = resultsGui:FindFirstChild("Content")
                    local returnBtn = content and content:FindFirstChild("Return")

                    if returnBtn then
                        State.helpers.setStatus("Status: RETURNING TO LOBBY...")
                        State.helpers.queueWebhookUpdate()
                        State.helpers.fireButtonConnections(returnBtn)
                    end

                    repeat
                        task.wait(0.25)
                    until not resultsGui.Parent
                        or not resultsGui.Enabled
                        or not isAnyRaidEnabled()
                        or not State.helpers.isInRaidGamemode()

                    State.raid.handlingResults = false

                    if State.automation.savedFarmCFrame and State.automation.tpEnabled then
                        State.automation.pendingFarmReturn = true
                    end

                    if isAnyRaidEnabled() then
                        State.raid.checkingRaid = true
                        State.raid.launchingRaid = false
                        State.helpers.setStatus("Status: CHECKING RAID...")
                        State.helpers.setTimer("Next Raid: Ready")
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

    local RaidTab = Window:CreateTab("Auto-Raid", 4483362458)
    local raidModeOptions = {
        "TitanTown",
        "HollowDimension"
    }
    local easterModeOptions = {
        "ChocolateKingdom",
        "CarrotIsland"
    }

    local currentMode = State.raid.selectedMode or "TitanTown"
    local modeIsValid = false
    for _, mode in ipairs(raidModeOptions) do
        if mode == currentMode then
            modeIsValid = true
            break
        end
    end
    if not modeIsValid then
        currentMode = raidModeOptions[1]
    end
    State.raid.selectedMode = currentMode

    RaidTab:CreateLabel("----- Normal Raid -----")

    local normalModeDropdown = RaidTab:CreateDropdown({
        Name = "Normal Mode",
        Options = raidModeOptions,
        CurrentOption = State.raid.selectedMode,
        MultipleOptions = false,
        Callback = function(Option)
            local selected = Option
            if typeof(Option) == "table" then
                selected = Option[1]
            end

            if type(selected) == "string" and selected ~= "" then
                State.raid.selectedMode = selected
                State.helpers.queueWebhookUpdate(true)
            end
        end,
    })

    local raidLoopToggle = RaidTab:CreateToggle({
        Name = "Infinite Raid Loop",
        CurrentValue = State.raid.autoRaidActive == true,
        Callback = function(Value)
            State.raid.autoRaidActive = Value
            State.helpers.bumpRaidGeneration()

            if not isAnyRaidEnabled() then
                State.helpers.resetRaidState(false)
                State.helpers.setStatus("Status: IDLE")
                State.helpers.setTimer("Next Raid: Ready")
                State.raid.currentRunType = nil
            else
                State.helpers.resetRaidState(true)
                State.helpers.setStatus("Status: CHECKING RAID...")
                State.helpers.setTimer("Next Raid: Ready")
            end

            State.helpers.queueWebhookUpdate(true)
        end,
    })

    local useRaidTicketToggle = RaidTab:CreateToggle({
        Name = "Use Raid Ticket",
        CurrentValue = State.raid.useRaidTicket == true,
        Callback = function(Value)
            State.raid.useRaidTicket = Value == true
        end,
    })

    RaidTab:CreateLabel("----- Easter Raid -----")

    local currentEasterMode = State.raid.selectedEasterMode or "ChocolateKingdom"
    local easterModeIsValid = false
    for _, mode in ipairs(easterModeOptions) do
        if mode == currentEasterMode then
            easterModeIsValid = true
            break
        end
    end
    if not easterModeIsValid then
        currentEasterMode = easterModeOptions[1]
    end
    State.raid.selectedEasterMode = currentEasterMode

    local easterModeDropdown = RaidTab:CreateDropdown({
        Name = "Easter Mode",
        Options = easterModeOptions,
        CurrentOption = State.raid.selectedEasterMode,
        MultipleOptions = false,
        Callback = function(Option)
            local selected = Option
            if typeof(Option) == "table" then
                selected = Option[1]
            end

            if type(selected) == "string" and selected ~= "" then
                State.raid.selectedEasterMode = selected
                State.helpers.queueWebhookUpdate(true)
            end
        end,
    })

    local easterLoopToggle = RaidTab:CreateToggle({
        Name = "Infinite Easter Raid Loop",
        CurrentValue = State.raid.autoEasterRaidActive == true,
        Callback = function(Value)
            State.raid.autoEasterRaidActive = Value
            State.helpers.bumpRaidGeneration()

            if not isAnyRaidEnabled() then
                State.helpers.resetRaidState(false)
                State.helpers.setStatus("Status: IDLE")
                State.helpers.setTimer("Next Raid: Ready")
                State.raid.currentRunType = nil
            else
                State.helpers.resetRaidState(true)
                State.helpers.setStatus("Status: CHECKING RAID...")
                State.helpers.setTimer("Next Raid: Ready")
            end

            State.helpers.queueWebhookUpdate(true)
        end,
    })

    local useEasterTicketToggle = RaidTab:CreateToggle({
        Name = "Use Easter Ticket",
        CurrentValue = State.raid.useEasterTicket == true,
        Callback = function(Value)
            State.raid.useEasterTicket = Value == true
        end,
    })

    State.ui.StatusLabel = RaidTab:CreateLabel("Status: IDLE")
    State.ui.TimerLabel = RaidTab:CreateLabel("Next Raid: Ready")

    task.spawn(function()
        while true do
            if isAnyRaidEnabled()
                and State.helpers.isRaidStarted()
                and not State.raid.handlingResults
                and shouldTpToRaidMobs()
                and not isBlockingHigherPriorityQueues() then

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
                                State.helpers.setStatus("Status: FIGHTING")
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
            if isAnyRaidEnabled()
                and not State.raid.handlingResults
                and not State.helpers.isInRaidGamemode()
                and not State.raid.launchingRaid
                and not isBlockingHigherPriorityQueues() then
                State.raid.checkingRaid = true
                State.helpers.setStatus("Status: CHECKING RAID...")
                State.helpers.queueWebhookUpdate()

                local currentTime = tick()

                local myGen = State.helpers.bumpRaidGeneration()
                local raidType, selectedMode = getActiveRaidSelection()

                if not raidType or not selectedMode then
                    local normalRemaining = math.max(0, math.ceil((State.raid.normalCooldownEnd or 0) - currentTime))
                    local easterRemaining = math.max(0, math.ceil((State.raid.easterCooldownEnd or 0) - currentTime))

                    State.helpers.setStatus("Status: SYNCED COOLDOWN")
                    State.helpers.setTimer(string.format("N:%02dm%02ds | E:%02dm%02ds",
                        math.floor(normalRemaining / 60), normalRemaining % 60,
                        math.floor(easterRemaining / 60), easterRemaining % 60))
                    State.raid.checkingRaid = false
                    State.raid.launchingRaid = false
                    State.helpers.queueWebhookUpdate()
                    cooldownProbeAndWait()
                    continue
                end

                State.raid.checkingRaid = false
                State.raid.launchingRaid = true
                State.raid.currentRunType = raidType

                State.helpers.setStatus("Status: ATTEMPTING " .. string.upper(raidType) .. " LAUNCH...")
                State.helpers.setTimer("Next Raid: Ready")
                State.helpers.queueWebhookUpdate()

                tryUseTicket(raidType)

                local gamemodeName = (raidType == "Easter") and "Easter Raid" or "Raid"
                local createArgs = {{{"GamemodeSystem", "Create", gamemodeName, selectedMode, "Easy", n = 6}, "\002"}}
                local tCreate = tick()
                local roomSnap = State.helpers.snapshotGamemodeFolderNames()
                BridgeNet:FireServer(unpack(createArgs))

                local roomReady = State.helpers.waitForGamemodeRoomCreated(roomSnap, 6, function()
                    if raidType == "Easter" then
                        return (State.raid.easterCooldownEnd or 0) > tick()
                    end
                    return (State.raid.normalCooldownEnd or 0) > tick()
                end)

                local activeCooldownEnd = (raidType == "Easter") and (State.raid.easterCooldownEnd or 0) or (State.raid.normalCooldownEnd or 0)
                if not isAnyRaidEnabled()
                    or State.raid.handlingResults
                    or not State.helpers.isCurrentGeneration(myGen)
                    or activeCooldownEnd > tick()
                    or isBlockingHigherPriorityQueues() then
                    State.raid.launchingRaid = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                if not roomReady then
                    State.raid.launchingRaid = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                State.helpers.sendGamemodeCreateChat(raidType == "Easter" and "E Raid" or "Raid")

                local remaining = State.helpers.getGamemodeStartDelay() - (tick() - tCreate)
                if remaining > 0 then
                    task.wait(remaining)
                end

                activeCooldownEnd = (raidType == "Easter") and (State.raid.easterCooldownEnd or 0) or (State.raid.normalCooldownEnd or 0)
                if not isAnyRaidEnabled()
                    or State.raid.handlingResults
                    or not State.helpers.isCurrentGeneration(myGen)
                    or activeCooldownEnd > tick()
                    or isBlockingHigherPriorityQueues() then
                    State.raid.launchingRaid = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                local startArgs = {{{"GamemodeSystem", "Start", gamemodeName, 10686337651, n = 4}, "\002"}}
                BridgeNet:FireServer(unpack(startArgs))

                task.wait(3)

                activeCooldownEnd = (raidType == "Easter") and (State.raid.easterCooldownEnd or 0) or (State.raid.normalCooldownEnd or 0)
                if not isAnyRaidEnabled()
                    or State.raid.handlingResults
                    or not State.helpers.isCurrentGeneration(myGen)
                    or activeCooldownEnd > tick()
                    or isBlockingHigherPriorityQueues() then
                    State.raid.launchingRaid = false
                    State.helpers.queueWebhookUpdate()
                    task.wait(0.2)
                    continue
                end

                task.wait(5)

                if isAnyRaidEnabled() and not State.raid.handlingResults and State.helpers.isCurrentGeneration(myGen) then
                    if State.helpers.isRaidStarted() then
                        State.raid.checkingRaid = false
                        State.helpers.setStatus("Status: FIGHTING")
                        State.helpers.setTimer("Next Raid: In Progress")
                    else
                        State.helpers.setStatus("Status: CHECKING RAID...")
                        State.helpers.setTimer("Next Raid: Waiting Join...")
                        State.raid.checkingRaid = true
                    end
                    State.helpers.queueWebhookUpdate()
                end

                State.raid.launchingRaid = false
                State.helpers.queueWebhookUpdate()
            else
                if not isAnyRaidEnabled() then
                    State.raid.checkingRaid = false
                elseif State.helpers.isRaidStarted() and not State.raid.handlingResults then
                    State.helpers.setStatus("Status: FIGHTING")
                    State.helpers.setTimer("Next Raid: In Progress")
                end
            end

            if isAnyRaidEnabled()
                and not State.raid.handlingResults
                and not State.helpers.isInRaidGamemode()
                and not State.raid.launchingRaid
                and not isBlockingHigherPriorityQueues()
                and not getActiveRaidSelection() then
                cooldownProbeAndWait()
            else
                task.wait(0.2)
            end
        end
    end)

    State.helpers.isRaidEligibleToStartRun = function()
        if State.helpers.isBossRushBlockingRaidAndInfQueues() then
            return false
        end
        if State.helpers.isDungeonBlockingRaidAndInfQueues() then
            return false
        end
        if not (State.raid.autoRaidActive or State.raid.autoEasterRaidActive) then
            return false
        end
        if State.raid.handlingResults then
            return false
        end
        if State.helpers.isInRaidGamemode() then
            return false
        end
        if State.raid.launchingRaid then
            return false
        end
        local raidType, selectedMode = getActiveRaidSelection()
        return raidType ~= nil and selectedMode ~= nil
    end

    table.insert(State.configUiSync, function()
        if normalModeDropdown then
            normalModeDropdown:Set(State.raid.selectedMode or "TitanTown", true)
        end
        if easterModeDropdown then
            easterModeDropdown:Set(State.raid.selectedEasterMode or "ChocolateKingdom", true)
        end
        if raidLoopToggle then
            raidLoopToggle:Set(State.raid.autoRaidActive == true, true)
        end
        if easterLoopToggle then
            easterLoopToggle:Set(State.raid.autoEasterRaidActive == true, true)
        end
        if useRaidTicketToggle then
            useRaidTicketToggle:Set(State.raid.useRaidTicket == true, true)
        end
        if useEasterTicketToggle then
            useEasterTicketToggle:Set(State.raid.useEasterTicket == true, true)
        end
    end)
end