return function(Window, State)
    local targetFolder = State.services.targetFolder
    local LocalPlayer = State.services.LocalPlayer

    local function copyMobList(t)
        local o = {}
        for _, v in ipairs(t or {}) do
            table.insert(o, v)
        end
        return o
    end

    local AutomationTab = Window:CreateTab("Automation", 4483362458)

    local MobDropdown = AutomationTab:CreateDropdown({
        Name = "Select Target Mob(s)",
        Options = State.helpers.getUniqueMobNames(),
        CurrentOption = copyMobList(State.automation.selectedMobs),
        MultipleOptions = true,
        Callback = function(Options)
            State.automation.selectedMobs = Options or {}
            State.helpers.queueWebhookUpdate(true)
        end,
    })

    AutomationTab:CreateButton({
        Name = "Refresh List",
        Callback = function()
            MobDropdown:Refresh(State.helpers.getUniqueMobNames(), true)
        end,
    })

    local tpToggle = AutomationTab:CreateToggle({
        Name = "Auto-TP ME to Targets",
        CurrentValue = State.automation.tpEnabled == true,
        Callback = function(Value)
            State.automation.tpEnabled = Value
            State.helpers.queueWebhookUpdate(true)
        end,
    })

    local farmStatusLabel = AutomationTab:CreateLabel("Farm spawn: not saved")

    local function refreshFarmLabel()
        if State.automation.savedFarmCFrame then
            farmStatusLabel:Set("Farm spawn: saved (return after raid)")
        else
            farmStatusLabel:Set("Farm spawn: not saved")
        end
    end

    AutomationTab:CreateButton({
        Name = "Save farm position (CFrame)",
        Callback = function()
            local char = LocalPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                State.automation.savedFarmCFrame = root.CFrame
                refreshFarmLabel()
            else
                farmStatusLabel:Set("Farm spawn: no character / HRP")
            end
        end,
    })

    AutomationTab:CreateButton({
        Name = "Clear saved farm position",
        Callback = function()
            State.automation.savedFarmCFrame = nil
            State.automation.pendingFarmReturn = false
            refreshFarmLabel()
        end,
    })

    refreshFarmLabel()

    task.spawn(function()
        while true do
            if State.automation.pendingFarmReturn and State.automation.savedFarmCFrame then
                if not State.helpers.isInRaidGamemode()
                    and not State.helpers.isInInfCastleGamemode()
                    and not State.helpers.isInBossRushGamemode()
                    and not State.helpers.isInDefenseGamemode()
                    and not State.helpers.isInMapDungeonGamemode() then
                    local mode = State.helpers.getGamemodeType()
                    if mode == "Lobby" or mode == "Unknown" then
                        local char = LocalPlayer.Character
                        local root = char and char:FindFirstChild("HumanoidRootPart")
                        if root then
                            root.CFrame = State.automation.savedFarmCFrame
                            State.automation.pendingFarmReturn = false
                        end
                    end
                end
            end
            task.wait(0.15)
        end
    end)

    task.spawn(function()
        while true do
            if State.automation.tpEnabled
                and #State.automation.selectedMobs > 0
                and not State.helpers.isHigherPriorityActivityRunning() then

                local modeType = State.helpers.getCurrentGamemodeType()

                if modeType == "Lobby" or modeType == "Unknown" then
                    local char = LocalPlayer.Character
                    local myRoot = char and char:FindFirstChild("HumanoidRootPart")

                    if myRoot then
                        for _, targetName in ipairs(State.automation.selectedMobs) do
                            if not State.automation.tpEnabled
                                or State.helpers.isHigherPriorityActivityRunning() then
                                break
                            end

                            local liveModeType = State.helpers.getCurrentGamemodeType()
                            if liveModeType ~= "Lobby" and liveModeType ~= "Unknown" then
                                break
                            end

                            for _, hashModel in ipairs(targetFolder:GetChildren()) do
                                if not State.automation.tpEnabled
                                    or State.helpers.isHigherPriorityActivityRunning() then
                                    break
                                end

                                local latestModeType = State.helpers.getCurrentGamemodeType()
                                if latestModeType ~= "Lobby" and latestModeType ~= "Unknown" then
                                    break
                                end

                                local isMatch = false
                                local billboard = hashModel:FindFirstChild("EnemyBillboard", true)
                                local title = billboard and billboard:FindFirstChild("Title")

                                if title and title.Text == targetName then
                                    isMatch = true
                                elseif targetName == "Secret" and hashModel:FindFirstChild("Appearance") then
                                    isMatch = true
                                end

                                if isMatch then
                                    local targetPart = hashModel:FindFirstChild("EnemyHitbox")
                                        or hashModel:FindFirstChild("HumanoidRootPart")
                                        or hashModel.PrimaryPart

                                    if targetPart then
                                        myRoot.CFrame = targetPart.CFrame * CFrame.new(0, 3, 0)
                                        task.wait(0.1)
                                    end
                                end
                            end
                        end
                    end
                end
            end

            task.wait()
        end
    end)

    table.insert(State.configUiSync, function()
        if MobDropdown then
            MobDropdown:Refresh(State.helpers.getUniqueMobNames(), true)
            MobDropdown:Set(copyMobList(State.automation.selectedMobs), true)
        end
        if tpToggle then
            tpToggle:Set(State.automation.tpEnabled == true, true)
        end
    end)
end