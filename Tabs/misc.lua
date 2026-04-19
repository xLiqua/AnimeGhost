return function(Window, State)
    local MiscTab = Window:CreateTab("Misc", 4483362458)

    MiscTab:CreateLabel("Memory dump: Lua heap (GC) stats → console; clipboard / file if available.")

    MiscTab:CreateButton({
        Name = "Dump memory (GC)",
        Callback = function()
            local text = State.helpers.getMemoryDumpText()
            print(text)

            local notes = { "Peanut: memory dump printed (F9 / executor console)." }

            pcall(function()
                local sc = setclipboard or (syn and syn.setclipboard)
                if type(sc) == "function" then
                    sc(text)
                    table.insert(notes, "Clipboard OK.")
                end
            end)

            pcall(function()
                local wf = writefile or (syn and syn.writefile)
                if type(wf) == "function" then
                    local name = "Peanut_memory_" .. math.floor(tick() * 1000) .. ".txt"
                    wf(name, text)
                    table.insert(notes, "File: " .. name)
                end
            end)

            warn(table.concat(notes, " "))
        end,
    })

    local rewardsToggle = MiscTab:CreateToggle({
        Name = "Auto Claim Time Rewards",
        CurrentValue = State.rewards.autoClaimRewards == true,
        Callback = function(Value)
            State.rewards.autoClaimRewards = Value
            if Value and (not State.rewards.lib or not State.rewards.data) then
                State.helpers.setupTimeRewardsAccess()
            end
            State.helpers.queueWebhookUpdate(true)
        end,
    })

    task.spawn(function()
        while true do
            if State.rewards.autoClaimRewards then
                if not State.rewards.lib or not State.rewards.data then
                    State.helpers.setupTimeRewardsAccess()
                end

                if State.rewards.lib and State.rewards.data and State.rewards.lib.PlayerData and State.rewards.lib.PlayerData.TimeRewards then
                    for rewardType, rewardInfo in pairs(State.rewards.data) do
                        local save = State.rewards.lib.PlayerData.TimeRewards[rewardType]

                        if save and save.Claimed then
                            local allClaimed = true

                            for rewardIndex, reward in pairs(rewardInfo.Rewards) do
                                local claimed = save.Claimed[rewardIndex]

                                if not claimed then
                                    allClaimed = false

                                    if reward.Time <= save.Time then
                                        pcall(function()
                                            State.rewards.lib.Remote:Fire("TimeRewardSystem", "Claim", rewardType, rewardIndex)
                                        end)

                                        State.helpers.queueWebhookUpdate()
                                        task.wait(0.5)
                                    end
                                end
                            end

                            if rewardType == "General" and allClaimed then
                                task.wait(1)
                                State.helpers.resetGeneralTimeRewards()
                                State.helpers.queueWebhookUpdate()
                                task.wait(1)
                            end
                        end
                    end
                end
            end

            task.wait(2)
        end
    end)

    table.insert(State.configUiSync, function()
        if rewardsToggle then
            rewardsToggle:Set(State.rewards.autoClaimRewards == true, true)
        end
    end)
end