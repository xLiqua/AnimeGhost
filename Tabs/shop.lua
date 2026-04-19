return function(Window, State)
    local BridgeNet = State.services.BridgeNet
    local ShopTab = Window:CreateTab("Shop", 4483362458)

    local categoryInput = ShopTab:CreateInput({
        Name = "Shop Category",
        CurrentValue = State.shop.category,
        PlaceholderText = "Example: Dungeon",
        RemoveTextAfterFocusLost = false,
        Callback = function(Text)
            local value = tostring(Text or ""):gsub("^%s*(.-)%s*$", "%1")
            if value ~= "" then
                State.shop.category = value
            end
        end,
    })

    local itemInput = ShopTab:CreateInput({
        Name = "Shop Item",
        CurrentValue = State.shop.item,
        PlaceholderText = "Example: DungeonTickets",
        RemoveTextAfterFocusLost = false,
        Callback = function(Text)
            local value = tostring(Text or ""):gsub("^%s*(.-)%s*$", "%1")
            if value ~= "" then
                State.shop.item = value
            end
        end,
    })

    local quantitySlider = ShopTab:CreateSlider({
        Name = "Quantity",
        Range = { 1, 5 },
        Increment = 1,
        CurrentValue = State.shop.quantity,
        Suffix = "x",
        Callback = function(Value)
            State.shop.quantity = math.max(1, tonumber(Value) or 1)
        end,
    })

    ShopTab:CreateButton({
        Name = "Buy Item",
        Callback = function()
            local category = State.shop.category
            local item = State.shop.item
            local quantity = math.max(1, tonumber(State.shop.quantity) or 1)

            if category == "" or item == "" then
                warn("Shop buy blocked: category/item cannot be empty")
                return
            end

            local args = {
                {
                    {
                        "StockShopSystem",
                        "Buy",
                        category,
                        item,
                        quantity,
                        n = 5
                    },
                    "\2"
                }
            }

            BridgeNet:FireServer(unpack(args))
        end,
    })

    table.insert(State.configUiSync, function()
        if categoryInput then
            categoryInput:Set(State.shop.category or "", true)
        end
        if itemInput then
            itemInput:Set(State.shop.item or "", true)
        end
        if quantitySlider then
            quantitySlider:Set(State.shop.quantity or 1, true)
        end
    end)
end
