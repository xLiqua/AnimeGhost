return function(HttpService)
    -- Storage layout (all relative to the executor's writefile root — usually that
    -- executor's workspace folder in AppData, NOT github.com):
    --   <ROOT>/users/<UserId>/configs/<name>.json
    --   <ROOT>/users/<UserId>/autoload.txt
    --
    -- Default ROOT is "PeanutData" (not "Peanut") so we don't create a confusing
    -- extra "Peanut" folder inside a repo folder also named Peanut.
    --
    -- Optional override (run before loading Main, path must work with your executor):
    --   getgenv().PEANUT_CONFIG_ROOT = "MyFolder"           -- relative to executor workspace
    --   getgenv().PEANUT_CONFIG_ROOT = "C:/full/path/data"  -- if your executor allows absolute paths

    local function resolveRoot()
        local g = getgenv and getgenv() or nil
        if g and type(g.PEANUT_CONFIG_ROOT) == "string" then
            local s = g.PEANUT_CONFIG_ROOT:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[/\\]+$", "")
            if s ~= "" then
                return s
            end
        end
        return "PeanutData"
    end

    local ROOT = resolveRoot()
    local USER_ROOT_CACHE = nil

    local function userRoot()
        if USER_ROOT_CACHE then
            return USER_ROOT_CACHE
        end
        local ok, lp = pcall(function()
            return game:GetService("Players").LocalPlayer
        end)
        if ok and lp and type(lp.UserId) == "number" and lp.UserId > 0 then
            USER_ROOT_CACHE = string.format("%s/users/%s", ROOT, tostring(lp.UserId))
        else
            USER_ROOT_CACHE = ROOT .. "/users/default"
        end
        return USER_ROOT_CACHE
    end

    local function cfgDir()
        return userRoot() .. "/configs"
    end

    local function autoloadPath()
        return userRoot() .. "/autoload.txt"
    end

    local function configPath(name)
        return string.format("%s/%s.json", cfgDir(), name)
    end

    local function fsSupported()
        return type(writefile) == "function"
            and type(readfile) == "function"
            and type(isfile) == "function"
            and type(makefolder) == "function"
            and type(isfolder) == "function"
            and type(listfiles) == "function"
    end

    local function ensureFolders()
        if not fsSupported() then
            return false
        end
        if not isfolder(ROOT) then
            makefolder(ROOT)
        end
        local ur = userRoot()
        if not isfolder(ur) then
            makefolder(ur)
        end
        local dir = cfgDir()
        if not isfolder(dir) then
            makefolder(dir)
        end
        return true
    end

    local function cleanName(name)
        local s = tostring(name or ""):gsub("[^%w%-%_]", "")
        return s
    end

    local M = {}

    function M.IsSupported()
        return fsSupported()
    end

    --- Relative path shown in Settings; actual disk = executor writefile root + this path.
    function M.GetStorageRoot()
        return cfgDir()
    end

    function M.List()
        if not ensureFolders() then
            return {}
        end
        local out = {}
        local dir = cfgDir()
        for _, file in ipairs(listfiles(dir)) do
            local full = tostring(file)
            local base = full:match("([^/\\]+)%.json$")
            if base and base ~= "" then
                table.insert(out, base)
            end
        end
        table.sort(out)
        return out
    end

    function M.Save(name, data)
        if not ensureFolders() then
            return false, "Filesystem unsupported"
        end
        local clean = cleanName(name)
        if clean == "" then
            return false, "Config name is empty"
        end
        local ok, encoded = pcall(function()
            return HttpService:JSONEncode(data)
        end)
        if not ok then
            return false, "Config encode failed"
        end
        writefile(configPath(clean), encoded)
        return true
    end

    function M.Load(name)
        if not ensureFolders() then
            return false, "Filesystem unsupported"
        end
        local clean = cleanName(name)
        if clean == "" then
            return false, "Config name is empty"
        end
        local path = configPath(clean)
        if not isfile(path) then
            return false, "Config not found"
        end
        local raw = readfile(path)
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(raw)
        end)
        if not ok or type(decoded) ~= "table" then
            return false, "Config decode failed"
        end
        return true, decoded
    end

    function M.SetAutoload(name)
        if not ensureFolders() then
            return false, "Filesystem unsupported"
        end
        local clean = cleanName(name)
        local path = autoloadPath()
        if clean == "" then
            if isfile(path) then
                writefile(path, "")
            end
            return true
        end
        writefile(path, clean)
        return true
    end

    function M.GetAutoload()
        if not ensureFolders() then
            return nil
        end
        local path = autoloadPath()
        if not isfile(path) then
            return nil
        end
        local raw = tostring(readfile(path) or ""):gsub("%s+", "")
        if raw == "" then
            return nil
        end
        return raw
    end

    function M.LoadAutoload()
        local name = M.GetAutoload()
        if not name then
            return false, "No autoload config", nil
        end
        local ok, cfg = M.Load(name)
        if not ok then
            return false, cfg, name
        end
        return true, cfg, name
    end

    return M
end
