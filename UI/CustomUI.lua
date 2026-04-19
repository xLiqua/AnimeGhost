return function()
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local TweenService = game:GetService("TweenService")

    local LocalPlayer = Players.LocalPlayer

    -- Nebula: cool blue shell (light → dark), controls slightly darker so they read as panels.
    local themes = {
        Nebula = {
            WindowTop = Color3.fromRGB(58, 88, 145),
            WindowBottom = Color3.fromRGB(18, 28, 52),
            SidebarTop = Color3.fromRGB(52, 78, 128),
            SidebarBottom = Color3.fromRGB(26, 40, 72),
            Border = Color3.fromRGB(85, 125, 185),
            CardTop = Color3.fromRGB(34, 50, 88),
            CardBottom = Color3.fromRGB(22, 34, 62),
            InputTop = Color3.fromRGB(28, 42, 74),
            InputBottom = Color3.fromRGB(18, 28, 52),
            ControlBorder = Color3.fromRGB(68, 98, 152),
            Accent = Color3.fromRGB(130, 185, 255),
            AccentAlt = Color3.fromRGB(72, 110, 175),
            Text = Color3.fromRGB(240, 245, 255),
            TextMuted = Color3.fromRGB(168, 195, 235),
            InputPlaceholder = Color3.fromRGB(160, 185, 220),
        },
        Ember = {
            WindowTop = Color3.fromRGB(38, 24, 22),
            WindowBottom = Color3.fromRGB(30, 18, 16),
            SidebarTop = Color3.fromRGB(42, 26, 22),
            SidebarBottom = Color3.fromRGB(34, 20, 17),
            Border = Color3.fromRGB(120, 72, 58),
            CardTop = Color3.fromRGB(52, 32, 26),
            CardBottom = Color3.fromRGB(44, 28, 22),
            InputTop = Color3.fromRGB(36, 22, 18),
            InputBottom = Color3.fromRGB(30, 18, 14),
            Accent = Color3.fromRGB(230, 150, 110),
            AccentAlt = Color3.fromRGB(118, 64, 52),
            Text = Color3.fromRGB(255, 238, 228),
            TextMuted = Color3.fromRGB(216, 178, 158),
            InputPlaceholder = Color3.fromRGB(200, 165, 150),
        },
        Emerald = {
            WindowTop = Color3.fromRGB(18, 34, 30),
            WindowBottom = Color3.fromRGB(14, 28, 24),
            SidebarTop = Color3.fromRGB(20, 36, 32),
            SidebarBottom = Color3.fromRGB(16, 30, 26),
            Border = Color3.fromRGB(58, 110, 96),
            CardTop = Color3.fromRGB(28, 52, 44),
            CardBottom = Color3.fromRGB(22, 44, 38),
            InputTop = Color3.fromRGB(18, 34, 30),
            InputBottom = Color3.fromRGB(14, 28, 24),
            Accent = Color3.fromRGB(100, 200, 168),
            AccentAlt = Color3.fromRGB(48, 88, 78),
            Text = Color3.fromRGB(230, 255, 245),
            TextMuted = Color3.fromRGB(162, 214, 194),
            InputPlaceholder = Color3.fromRGB(140, 195, 175),
        },
        -- Black + blood crimson: wine shadow → true black, hot red accents.
        Crimson = {
            WindowTop = Color3.fromRGB(52, 14, 20),
            WindowBottom = Color3.fromRGB(6, 4, 6),
            SidebarTop = Color3.fromRGB(44, 12, 16),
            SidebarBottom = Color3.fromRGB(12, 6, 8),
            Border = Color3.fromRGB(175, 42, 58),
            CardTop = Color3.fromRGB(26, 8, 12),
            CardBottom = Color3.fromRGB(14, 5, 8),
            InputTop = Color3.fromRGB(20, 6, 9),
            InputBottom = Color3.fromRGB(10, 4, 6),
            ControlBorder = Color3.fromRGB(120, 32, 48),
            Accent = Color3.fromRGB(255, 48, 72),
            AccentAlt = Color3.fromRGB(168, 28, 52),
            Text = Color3.fromRGB(255, 246, 246),
            TextMuted = Color3.fromRGB(198, 155, 162),
            InputPlaceholder = Color3.fromRGB(235, 200, 208),
        },
    }

    local currentThemeName = "Nebula"
    local themed = {}

    local function bindTheme(cb)
        table.insert(themed, cb)
        cb(themes[currentThemeName], currentThemeName)
    end

    local function applyTheme(name)
        if not themes[name] then
            return false
        end
        currentThemeName = name
        for _, cb in ipairs(themed) do
            cb(themes[currentThemeName], currentThemeName)
        end
        return true
    end

    local function getGuiParent()
        if gethui then
            local ok, ui = pcall(gethui)
            if ok and ui then
                return ui
            end
        end
        return LocalPlayer:WaitForChild("PlayerGui")
    end

    local function make(className, props)
        local obj = Instance.new(className)
        for k, v in pairs(props or {}) do
            obj[k] = v
        end
        return obj
    end

    local function destroyExisting()
        local parent = getGuiParent()
        local old = parent:FindFirstChild("PeanutCustomUI")
        if old then
            old:Destroy()
        end
    end

    local function lerpColor(a, b, t)
        return Color3.new(
            a.R + (b.R - a.R) * t,
            a.G + (b.G - a.G) * t,
            a.B + (b.B - a.B) * t
        )
    end

    -- UIGradient on TextBox/TextButton tints the text itself — keep typed text solid + readable.
    local function styleReadableText(inst)
        inst.TextStrokeColor3 = Color3.new(0, 0, 0)
        inst.TextStrokeTransparency = 0.62
    end

    -- Light → dark: top color is brighter, bottom is deeper (vertical fade).
    local function gradient(frame, topKey, bottomKey)
        local g = make("UIGradient", { Parent = frame, Rotation = 90 })
        bindTheme(function(th)
            local top = th[topKey]
            local bot = th[bottomKey]
            local mid = lerpColor(top, bot, 0.5)
            g.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, top),
                ColorSequenceKeypoint.new(0.5, mid),
                ColorSequenceKeypoint.new(1, bot),
            })
        end)
    end

    local function styleCard(frame)
        make("UICorner", { Parent = frame, CornerRadius = UDim.new(0, 10) })
        local stroke = make("UIStroke", { Parent = frame, Thickness = 1, Transparency = 0.4 })
        gradient(frame, "CardTop", "CardBottom")
        bindTheme(function(th)
            stroke.Color = th.ControlBorder or th.Border
        end)
    end

    local function setCanvasAuto(scroller, list)
        local function update()
            scroller.CanvasSize = UDim2.new(0, 0, 0, list.AbsoluteContentSize.Y + 14)
        end
        list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(update)
        update()
    end

    local function createWindow(opts)
        destroyExisting()

        local gui = make("ScreenGui", {
            Name = "PeanutCustomUI",
            Parent = getGuiParent(),
            ResetOnSpawn = false,
            ZIndexBehavior = Enum.ZIndexBehavior.Global,
        })

        local root = make("Frame", {
            Parent = gui,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(0, 900, 0, 590),
            BorderSizePixel = 0,
        })
        make("UICorner", { Parent = root, CornerRadius = UDim.new(0, 14) })
        local rootStroke = make("UIStroke", { Parent = root, Thickness = 1, Transparency = 0.45 })
        gradient(root, "WindowTop", "WindowBottom")
        bindTheme(function(th)
            rootStroke.Color = th.Border
        end)

        local topBar = make("Frame", {
            Parent = root,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 54),
        })

        local title = make("TextLabel", {
            Parent = topBar,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 16, 0, 6),
            Size = UDim2.new(1, -32, 1, -12),
            Font = Enum.Font.GothamBold,
            TextSize = 18,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = opts.Name or "Custom Window",
        })
        bindTheme(function(th)
            title.TextColor3 = th.Text
        end)

        local split = make("Frame", {
            Parent = root,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, 54),
            Size = UDim2.new(1, 0, 0, 1),
        })
        bindTheme(function(th)
            split.BackgroundColor3 = th.Border
        end)

        local sidebar = make("Frame", {
            Parent = root,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, 55),
            Size = UDim2.new(0, 224, 1, -55),
        })
        gradient(sidebar, "SidebarTop", "SidebarBottom")

        local sidePadding = make("UIPadding", {
            Parent = sidebar,
            PaddingTop = UDim.new(0, 12),
            PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 10),
        })
        sidePadding = sidePadding
        local sideList = make("UIListLayout", {
            Parent = sidebar,
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        sideList = sideList

        local content = make("Frame", {
            Parent = root,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 224, 0, 55),
            Size = UDim2.new(1, -224, 1, -55),
        })

        -- Main panel visibility (floating toggle always stays visible)
        local mainVisible = true
        local dockBtn

        local function syncDockLabel()
            if dockBtn then
                dockBtn.Text = mainVisible and "Hide UI" or "Show UI"
            end
        end

        local function setMainVisible(visible)
            mainVisible = visible == true
            root.Visible = mainVisible
            syncDockLabel()
        end

        dockBtn = make("TextButton", {
            Parent = gui,
            Name = "PeanutUIToggle",
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -14, 1, -14),
            Size = UDim2.new(0, 108, 0, 34),
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            Text = "Hide UI",
            AutoButtonColor = false,
            ZIndex = 50,
        })
        make("UICorner", { Parent = dockBtn, CornerRadius = UDim.new(0, 10) })
        gradient(dockBtn, "CardTop", "CardBottom")
        bindTheme(function(th)
            dockBtn.TextColor3 = th.Text
        end)
        dockBtn.MouseButton1Click:Connect(function()
            setMainVisible(not mainVisible)
        end)

        local toggleKey = Enum.KeyCode.RightShift
        local keyConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then
                return
            end
            if input.KeyCode == toggleKey then
                setMainVisible(not mainVisible)
            end
        end)
        gui.AncestryChanged:Connect(function()
            if not gui.Parent then
                keyConn:Disconnect()
            end
        end)

        do
            local dragging, dragStart, startPos = false, nil, nil
            topBar.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    dragging = true
                    dragStart = input.Position
                    startPos = root.Position
                    input.Changed:Connect(function()
                        if input.UserInputState == Enum.UserInputState.End then
                            dragging = false
                        end
                    end)
                end
            end)
            UserInputService.InputChanged:Connect(function(input)
                if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                    local d = input.Position - dragStart
                    root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
                end
            end)
        end

        local tabs = {}
        local selected

        local window = {}

        function window:GetThemes()
            local out = {}
            for name in pairs(themes) do
                table.insert(out, name)
            end
            table.sort(out)
            return out
        end

        function window:SetTheme(name)
            return applyTheme(name)
        end

        function window:GetTheme()
            return currentThemeName
        end

        function window:SetMainVisible(visible)
            setMainVisible(visible)
        end

        function window:ToggleMain()
            setMainVisible(not mainVisible)
        end

        function window:IsMainVisible()
            return mainVisible
        end

        function window:GetToggleKey()
            return toggleKey
        end

        local function setSelected(tabObj)
            selected = tabObj
            for _, t in ipairs(tabs) do
                local on = (t == tabObj)
                t.Page.Visible = on
                TweenService:Create(t.Button, TweenInfo.new(0.14), {
                    BackgroundTransparency = on and 0 or 0.25
                }):Play()
                local th = themes[currentThemeName]
                t.ButtonLabel.TextColor3 = on and th.Text or th.TextMuted
                t.Button.BackgroundColor3 = on and th.AccentAlt or th.CardTop
            end
        end

        function window:CreateTab(name)
            local btn = make("Frame", { Parent = sidebar, Size = UDim2.new(1, 0, 0, 40), BorderSizePixel = 0 })
            styleCard(btn)
            btn.BackgroundTransparency = 0.25
            local lbl = make("TextLabel", {
                Parent = btn,
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 12, 0, 0),
                Size = UDim2.new(1, -16, 1, 0),
                Font = Enum.Font.GothamSemibold,
                TextSize = 14,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = name,
            })
            bindTheme(function(th)
                lbl.TextColor3 = th.TextMuted
            end)
            local click = make("TextButton", { Parent = btn, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = "" })

            local page = make("ScrollingFrame", {
                Parent = content,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 1, 0),
                ScrollBarThickness = 4,
                Visible = false,
                CanvasSize = UDim2.new(0, 0, 0, 0),
            })
            bindTheme(function(th)
                page.ScrollBarImageColor3 = th.Accent
            end)
            local list = make("UIListLayout", { Parent = page, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) })
            make("UIPadding", { Parent = page, PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) })
            setCanvasAuto(page, list)

            local tabObj = { Page = page, Button = btn, ButtonLabel = lbl }
            table.insert(tabs, tabObj)
            bindTheme(function(th)
                local on = (selected == tabObj)
                lbl.TextColor3 = on and th.Text or th.TextMuted
                btn.BackgroundColor3 = on and th.AccentAlt or th.CardTop
            end)
            click.MouseButton1Click:Connect(function()
                setSelected(tabObj)
            end)
            if #tabs == 1 then
                setSelected(tabObj)
            end

            local tab = {}

            function tab:CreateLabel(text)
                local card = make("Frame", { Parent = page, Size = UDim2.new(1, -12, 0, 38), BorderSizePixel = 0 })
                styleCard(card)
                local l = make("TextLabel", {
                    Parent = card, BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -24, 1, 0),
                    Font = Enum.Font.GothamSemibold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Text = text or "",
                })
                bindTheme(function(th) l.TextColor3 = th.Text end)
                return { Set = function(_, t) l.Text = tostring(t or "") end }
            end

            function tab:CreateButton(cfg)
                local card = make("Frame", { Parent = page, Size = UDim2.new(1, -12, 0, 42), BorderSizePixel = 0 })
                styleCard(card)
                local b = make("TextButton", { Parent = card, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = cfg.Name or "Button", Font = Enum.Font.GothamBold, TextSize = 14 })
                bindTheme(function(th) b.TextColor3 = th.Text end)
                b.MouseButton1Click:Connect(function() if cfg.Callback then task.spawn(cfg.Callback) end end)
            end

            function tab:CreateToggle(cfg)
                local value = cfg.CurrentValue == true
                local card = make("Frame", { Parent = page, Size = UDim2.new(1, -12, 0, 42), BorderSizePixel = 0 })
                styleCard(card)
                local l = make("TextLabel", { Parent = card, BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -70, 1, 0), Font = Enum.Font.GothamSemibold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Text = cfg.Name or "Toggle" })
                bindTheme(function(th) l.TextColor3 = th.Text end)
                local bg = make("Frame", { Parent = card, Size = UDim2.new(0, 44, 0, 22), Position = UDim2.new(1, -56, 0.5, -11), BorderSizePixel = 0 })
                make("UICorner", { Parent = bg, CornerRadius = UDim.new(1, 0) })
                local knob = make("Frame", { Parent = bg, Size = UDim2.new(0, 18, 0, 18), BorderSizePixel = 0 })
                make("UICorner", { Parent = knob, CornerRadius = UDim.new(1, 0) })
                bindTheme(function(th) knob.BackgroundColor3 = th.Text end)
                local hit = make("TextButton", { Parent = card, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = "" })
                local function set(v, fire)
                    value = v == true
                    bindTheme(function(th)
                        bg.BackgroundColor3 = value and th.Accent or th.InputBottom
                    end)
                    knob.Position = value and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
                    if fire and cfg.Callback then task.spawn(cfg.Callback, value) end
                end
                hit.MouseButton1Click:Connect(function() set(not value, true) end)
                set(value, false)
                return { Set = function(_, v, silent) set(v, not silent) end, Get = function() return value end }
            end

            function tab:CreateInput(cfg)
                local card = make("Frame", { Parent = page, Size = UDim2.new(1, -12, 0, 68), BorderSizePixel = 0 })
                styleCard(card)
                local l = make("TextLabel", { Parent = card, BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 7), Size = UDim2.new(1, -24, 0, 16), Font = Enum.Font.GothamSemibold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Text = cfg.Name or "Input" })
                bindTheme(function(th) l.TextColor3 = th.Text end)
                local box = make("TextBox", { Parent = card, Position = UDim2.new(0, 12, 0, 30), Size = UDim2.new(1, -24, 0, 30), BorderSizePixel = 0, ClearTextOnFocus = cfg.RemoveTextAfterFocusLost == true, Font = Enum.Font.Code, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Text = tostring(cfg.CurrentValue or ""), PlaceholderText = cfg.PlaceholderText or "" })
                make("UICorner", { Parent = box, CornerRadius = UDim.new(0, 8) })
                styleReadableText(box)
                bindTheme(function(th)
                    box.BackgroundColor3 = lerpColor(th.InputTop, th.InputBottom, 0.5)
                    box.TextColor3 = th.Text
                    box.PlaceholderColor3 = th.InputPlaceholder or th.TextMuted
                end)
                box.FocusLost:Connect(function() if cfg.Callback then task.spawn(cfg.Callback, box.Text) end end)
                return { Set = function(_, t, silent) box.Text = tostring(t or ""); if not silent and cfg.Callback then task.spawn(cfg.Callback, box.Text) end end }
            end

            function tab:CreateSlider(cfg)
                local min, max = cfg.Range[1], cfg.Range[2]
                local inc = cfg.Increment or 1
                local value = math.clamp(tonumber(cfg.CurrentValue) or min, min, max)
                local card = make("Frame", { Parent = page, Size = UDim2.new(1, -12, 0, 70), BorderSizePixel = 0 })
                styleCard(card)
                local l = make("TextLabel", { Parent = card, BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(1, -24, 0, 16), Font = Enum.Font.GothamSemibold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left })
                bindTheme(function(th) l.TextColor3 = th.Text end)
                local bar = make("Frame", { Parent = card, Position = UDim2.new(0, 12, 0, 40), Size = UDim2.new(1, -24, 0, 10), BorderSizePixel = 0 })
                make("UICorner", { Parent = bar, CornerRadius = UDim.new(1, 0) })
                bindTheme(function(th) bar.BackgroundColor3 = th.InputBottom end)
                local fill = make("Frame", { Parent = bar, Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0 })
                make("UICorner", { Parent = fill, CornerRadius = UDim.new(1, 0) })
                bindTheme(function(th) fill.BackgroundColor3 = th.Accent end)
                local dragging = false
                local function snap(v) return math.floor((v / inc) + 0.5) * inc end
                local function draw()
                    local alpha = (value - min) / (max - min)
                    fill.Size = UDim2.new(alpha, 0, 1, 0)
                    l.Text = string.format("%s: %s%s", cfg.Name or "Slider", tostring(value), cfg.Suffix or "")
                end
                local function set(v, fire)
                    value = math.clamp(snap(v), min, max)
                    draw()
                    if fire and cfg.Callback then task.spawn(cfg.Callback, value) end
                end
                local function fromX(x)
                    local alpha = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
                    set(min + ((max - min) * alpha), true)
                end
                bar.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true fromX(i.Position.X) end end)
                bar.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
                UserInputService.InputChanged:Connect(function(i) if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then fromX(i.Position.X) end end)
                draw()
                return { Set = function(_, v, silent) set(v, not silent) end, Get = function() return value end }
            end

            function tab:CreateDropdown(cfg)
                local opts = cfg.Options or {}
                local multiple = cfg.MultipleOptions == true
                local selectedMap, selectedOne = {}, nil
                if multiple then
                    for _, v in ipairs(cfg.CurrentOption or {}) do selectedMap[tostring(v)] = true end
                else
                    if type(cfg.CurrentOption) == "table" then selectedOne = tostring(cfg.CurrentOption[1] or opts[1] or "") else selectedOne = tostring(cfg.CurrentOption or opts[1] or "") end
                end

                local card = make("Frame", { Parent = page, Size = UDim2.new(1, -12, 0, 42), BorderSizePixel = 0 })
                styleCard(card)
                local head = make("TextButton", { Parent = card, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Font = Enum.Font.GothamSemibold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Text = "" })
                styleReadableText(head)
                bindTheme(function(th) head.TextColor3 = th.Text end)
                local dd = make("Frame", { Parent = page, Size = UDim2.new(1, -12, 0, 0), BorderSizePixel = 0, Visible = false })
                styleCard(dd)
                local ddList = make("UIListLayout", { Parent = dd, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder })
                make("UIPadding", { Parent = dd, PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) })

                local expanded = false
                local rows = {}
                local function selectedText()
                    if multiple then
                        local t = {}
                        for _, o in ipairs(opts) do if selectedMap[tostring(o)] then table.insert(t, tostring(o)) end end
                        return #t > 0 and table.concat(t, ", ") or "None"
                    end
                    return selectedOne ~= "" and selectedOne or "None"
                end
                local function emit()
                    if not cfg.Callback then return end
                    if multiple then
                        local t = {}
                        for _, o in ipairs(opts) do if selectedMap[tostring(o)] then table.insert(t, tostring(o)) end end
                        task.spawn(cfg.Callback, t)
                    else
                        task.spawn(cfg.Callback, selectedOne)
                    end
                end
                local function redrawHeader()
                    head.Text = string.format("  %s: %s", cfg.Name or "Dropdown", selectedText())
                end
                local function redrawRows()
                    for _, r in ipairs(rows) do r:Destroy() end
                    rows = {}
                    for _, o in ipairs(opts) do
                        local s = tostring(o)
                        local row = make("TextButton", { Parent = dd, Size = UDim2.new(1, 0, 0, 30), BorderSizePixel = 0, Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Text = "" })
                        make("UICorner", { Parent = row, CornerRadius = UDim.new(0, 7) })
                        styleReadableText(row)
                        local on = multiple and selectedMap[s] or (selectedOne == s)
                        row.Text = string.format("  %s %s", on and "●" or "○", s)
                        bindTheme(function(th)
                            local base = lerpColor(th.InputTop, th.InputBottom, 0.5)
                            row.BackgroundColor3 = on and lerpColor(base, th.AccentAlt, 0.38) or base
                            row.TextColor3 = th.Text
                        end)
                        table.insert(rows, row)
                        row.MouseButton1Click:Connect(function()
                            if multiple then selectedMap[s] = not selectedMap[s] else selectedOne = s expanded = false dd.Visible = false end
                            redrawHeader()
                            emit()
                            redrawRows()
                            dd.Size = UDim2.new(1, -12, 0, expanded and (ddList.AbsoluteContentSize.Y + 12) or 0)
                        end)
                    end
                end
                head.MouseButton1Click:Connect(function()
                    expanded = not expanded
                    dd.Visible = expanded
                    dd.Size = UDim2.new(1, -12, 0, expanded and (ddList.AbsoluteContentSize.Y + 12) or 0)
                end)
                redrawHeader()
                redrawRows()

                local api = {}
                function api:Refresh(newOpts, keepSelection)
                    opts = newOpts or {}
                    if not keepSelection then
                        selectedMap, selectedOne = {}, tostring(opts[1] or "")
                    end
                    redrawHeader()
                    redrawRows()
                    dd.Size = UDim2.new(1, -12, 0, expanded and (ddList.AbsoluteContentSize.Y + 12) or 0)
                end
                function api:Set(val, silent)
                    if multiple then
                        selectedMap = {}
                        if type(val) == "table" then for _, v in ipairs(val) do selectedMap[tostring(v)] = true end end
                    else
                        selectedOne = tostring(val or "")
                    end
                    redrawHeader()
                    redrawRows()
                    if not silent then emit() end
                end
                return api
            end

            return tab
        end

        return window
    end

    return { CreateWindow = createWindow }
end
