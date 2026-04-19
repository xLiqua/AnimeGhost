return function(Window, State)
    local WebhookTab = Window:CreateTab("Webhook", 4483362458)

    local urlInput = WebhookTab:CreateInput({
        Name = "Webhook URL",
        CurrentValue = State.webhook.url or "",
        PlaceholderText = "Paste Discord webhook URL",
        RemoveTextAfterFocusLost = false,
        Callback = function(Text)
            State.webhook.url = Text or ""
        end,
    })

    local webhookToggle = WebhookTab:CreateToggle({
        Name = "Enable Webhook Updates",
        CurrentValue = State.webhook.enabled == true,
        Callback = function(Value)
            State.webhook.enabled = Value

            if not Value then
                State.webhook.messageId = nil
                State.webhook.lastState = nil
                State.webhook.updateQueued = false
            else
                State.webhook.messageId = nil
                State.webhook.lastState = nil
                State.webhook.updateQueued = false
                State.helpers.queueWebhookUpdate(true)
            end
        end,
    })

    table.insert(State.configUiSync, function()
        if urlInput then
            urlInput:Set(State.webhook.url or "", true)
        end
        if webhookToggle then
            webhookToggle:Set(State.webhook.enabled == true, true)
        end
    end)
end