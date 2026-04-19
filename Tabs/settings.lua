return function(Window, State)
    local SettingsTab = Window:CreateTab("Settings", 4483362458)

    local cfgName = State.config and State.config.selectedName or "default"
    local fsOk = State.helpers.configIsSupported and State.helpers.configIsSupported()
    local statusLabel = SettingsTab:CreateLabel("Settings ready")
    SettingsTab:CreateLabel("UI: bottom-right button or RightShift toggles panel")
    if fsOk and State.helpers.getConfigStorageRoot then
        SettingsTab:CreateLabel(
            "Configs live on disk via your executor (not on GitHub). Path: "
                .. tostring(State.helpers.getConfigStorageRoot())
        )
        SettingsTab:CreateLabel(
            "Override folder: getgenv().PEANUT_CONFIG_ROOT = \"MyFolder\" before loading the script."
        )
    end

    local themeOptions = Window:GetThemes()
    local themeDropdown = SettingsTab:CreateDropdown({
        Name = "Theme",
        Options = themeOptions,
        CurrentOption = State.uiTheme or Window:GetTheme(),
        MultipleOptions = false,
        Callback = function(themeName)
            if Window:SetTheme(themeName) then
                State.uiTheme = themeName
                statusLabel:Set("Theme applied: " .. tostring(themeName))
            end
        end,
    })
    themeDropdown = themeDropdown

    SettingsTab:CreateLabel("Gamemode Start Delay")

    local gamemodeStartDelaySlider = SettingsTab:CreateSlider({
        Name = "Create → Start wait",
        Range = { 2.5, 15 },
        Increment = 0.5,
        CurrentValue = State.gamemodeStartDelay or 2.5,
        Suffix = "s",
        Callback = function(v)
            State.gamemodeStartDelay = math.clamp(v, 2.5, 15)
            if State.helpers.queueWebhookUpdate then
                State.helpers.queueWebhookUpdate(true)
            end
        end,
    })

    local configNameInput = SettingsTab:CreateInput({
        Name = "Config Name",
        CurrentValue = cfgName,
        PlaceholderText = "example: legitfarm",
        RemoveTextAfterFocusLost = false,
        Callback = function(text)
            local clean = tostring(text or ""):gsub("[^%w%-%_]", "")
            if clean ~= "" then
                cfgName = clean
                if State.config then
                    State.config.selectedName = clean
                end
            end
        end,
    })

    local configsDropdown
    local function refreshConfigs()
        if not fsOk then
            return {}
        end
        local list = State.helpers.listConfigs()
        if #list == 0 then
            list = { "default" }
        end
        if configsDropdown then
            configsDropdown:Refresh(list, true)
        end
        return list
    end

    configsDropdown = SettingsTab:CreateDropdown({
        Name = "Saved Configs",
        Options = refreshConfigs(),
        CurrentOption = cfgName,
        MultipleOptions = false,
        Callback = function(name)
            local value = tostring(name or "")
            if value ~= "" then
                cfgName = value
                if State.config then
                    State.config.selectedName = value
                end
                statusLabel:Set("Selected config: " .. value)
            end
        end,
    })

    SettingsTab:CreateButton({
        Name = "Refresh Config List",
        Callback = function()
            refreshConfigs()
            statusLabel:Set("Config list refreshed")
        end,
    })

    SettingsTab:CreateButton({
        Name = "Save Config",
        Callback = function()
            if not fsOk then
                statusLabel:Set("Save failed: filesystem unavailable")
                return
            end
            local ok, err = State.helpers.saveConfig(cfgName)
            if ok then
                refreshConfigs()
                statusLabel:Set("Saved config: " .. cfgName)
            else
                statusLabel:Set("Save failed: " .. tostring(err))
            end
        end,
    })

    SettingsTab:CreateButton({
        Name = "Load Config",
        Callback = function()
            if not fsOk then
                statusLabel:Set("Load failed: filesystem unavailable")
                return
            end
            local ok, err = State.helpers.loadConfig(cfgName)
            if ok then
                statusLabel:Set("Loaded config: " .. cfgName .. " — UI synced")
            else
                statusLabel:Set("Load failed: " .. tostring(err))
            end
        end,
    })

    local autoloadToggle = SettingsTab:CreateToggle({
        Name = "Autoload Selected Config",
        CurrentValue = (State.helpers.getAutoloadConfig() == cfgName),
        Callback = function(v)
            if not fsOk then
                statusLabel:Set("Autoload unavailable: filesystem unsupported")
                return
            end
            if v then
                local ok, err = State.helpers.setAutoloadConfig(cfgName)
                if ok then
                    statusLabel:Set("Autoload set to: " .. cfgName)
                else
                    statusLabel:Set("Autoload set failed: " .. tostring(err))
                end
            else
                local ok, err = State.helpers.setAutoloadConfig("")
                if ok then
                    statusLabel:Set("Autoload disabled")
                else
                    statusLabel:Set("Autoload disable failed: " .. tostring(err))
                end
            end
        end,
    })

    table.insert(State.configUiSync, function()
        if State.config and type(State.config.selectedName) == "string" and State.config.selectedName ~= "" then
            cfgName = State.config.selectedName
        end
        if themeDropdown then
            themeDropdown:Set(State.uiTheme or Window:GetTheme(), true)
        end
        if configNameInput then
            configNameInput:Set(cfgName, true)
        end
        if configsDropdown then
            refreshConfigs()
            configsDropdown:Set(cfgName, true)
        end
        if autoloadToggle then
            autoloadToggle:Set(State.helpers.getAutoloadConfig() == cfgName, true)
        end
        if gamemodeStartDelaySlider then
            gamemodeStartDelaySlider:Set(State.gamemodeStartDelay or 2.5, true)
        end
    end)
end
