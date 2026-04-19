--[[

-- Leave already created raid to fix gui issue --

local enemyRoot = workspace:WaitForChild("_ENEMIES")
local gamemodeFolder = enemyRoot:WaitForChild("Server"):WaitForChild("Gamemode")

local function getGamemodeId()
    for _, v in ipairs(gamemodeFolder:GetChildren()) do
        if v:IsA("Folder") and v.Name ~= "Lobby" then
            local id = tonumber(v.Name:match("(%d+)$"))
            if id then
                return id
            end
        end
    end
end

local id = getGamemodeId()

if id then
    local args = {
        {
            {
                "GamemodeSystem",
                "Leave",
                "Raid",
                id,
                n = 4
            },
            "\002"
        }
    }

    game:GetService("ReplicatedStorage")
        :WaitForChild("ffrostflame_bridgenet2@1.0.0")
        :WaitForChild("dataRemoteEvent")
        :FireServer(unpack(args))

    print("Left gamemode with ID:", id)
else
    warn("No gamemode ID found")
end

------------------------------------------------------

-- Quick spin Hero Stats (World 11) --

local args = {
	{
		{
			"StatsSystem",
			"Spin",
			"Hero",
			"Normal",
			{
				Ghost = 10,
				GachaLuck = 9,
				EggLuck = 10,
				Energy = 10,
				Damage = 9
			},
			n = 5
		},
		"\002"
	}
}

getgenv().autoherostats = false

while getgenv().autoherostats do
game:GetService("ReplicatedStorage"):WaitForChild("ffrostflame_bridgenet2@1.0.0"):WaitForChild("dataRemoteEvent"):FireServer(unpack(args))
task.wait()
end

-----------------------------------------------------------

]]