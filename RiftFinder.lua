
-- === Prevent double execution ===
if getgenv().RIFT_LOADED then
    warn("[RiftFinder] Already loaded. Skipping.")
    return
end
getgenv().RIFT_LOADED = true

-- === Wait for game to fully load ===
if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(1)

-- === Services ===
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

-- === Place Info ===
local JOB_ID = game.JobId
local PLACE_ID = game.PlaceId

-- === Globals ===
local PROXY_URL = getgenv().PROXY_URL
local HOOKS = getgenv().HOOKS
getgenv().CONFIG = getgenv().CONFIG or { "Nothing" }

-- Fix CONFIG if it's JSON string
if typeof(getgenv().CONFIG) == "string" then
    local success, result = pcall(function()
        return HttpService:JSONDecode(getgenv().CONFIG)
    end)
    if success then
        getgenv().CONFIG = result
    else
        warn("Invalid CONFIG JSON. Using fallback.")
        getgenv().CONFIG = { "Nothing" }
    end
end
local CONFIG = getgenv().CONFIG

-- === Shared state ===
getgenv().M = getgenv().M or {}
local M = getgenv().M
M.currentServer = M.currentServer or 0

-- === Fetch server list if needed ===
local function FetchServerList()
    if not M.serverList then
        local success, response = pcall(function()
            return HttpService:RequestAsync({
                Url = PROXY_URL,
                Method = "GET",
                Headers = {
                    ["Content-Type"] = "application/json"
                }
            })
        end)

        if success and response.Success then
            local data = HttpService:JSONDecode(response.Body)
            M.serverList = data.data or {}
        else
            warn("Failed to get server list: " .. tostring(response and response.StatusMessage or "Unknown error"))
            M.serverList = {}
        end
    end
end

FetchServerList()

-- === Debug: Print server list ===
for i, v in pairs(M.serverList) do
    print(i, v.id, v.maxPlayers, v.ping, v.fps, v.playing)
end

-- === Helpers ===
local function Contains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

-- === Teleport and re-inject ===
local function TeleportAndReinject(placeId, jobId)
    -- Prevent teleporting to the same server
    if jobId == JOB_ID then
        warn("[Teleport] Skipping current server:", jobId)
        return
    end

    local queueCode = string.format([[
        getgenv().PROXY_URL = %q
        getgenv().HOOKS = game:GetService("HttpService"):JSONDecode(%q)
        getgenv().CONFIG = game:GetService("HttpService"):JSONDecode(%q)
        getgenv().M = game:GetService("HttpService"):JSONDecode(%q)
        getgenv().RIFT_LOADED = nil
        loadstring(game:HttpGet("https://raw.githubusercontent.com/redscorpions/fuzzy-octo-fishstick/main/RiftFinder.lua"))()
    ]],
    PROXY_URL,
    HttpService:JSONEncode(HOOKS),
    HttpService:JSONEncode(CONFIG),
    HttpService:JSONEncode(M))

    -- Use spawn to avoid recursive stack overflow
    spawn(function()
        -- Only queue right before teleport
        if queue_on_teleport then
            queue_on_teleport(queueCode)
        else
            warn("queue_on_teleport not available.")
        end

        -- Delay before attempting teleport to avoid 771 spam
        task.wait(1)

        local success, err = pcall(function()
            print("[Teleport] Attempting ->", jobId)
            TeleportService:TeleportToPlaceInstance(placeId, jobId, Players.LocalPlayer)
        end)

        if not success then
            warn("[Teleport Failed] (" .. tostring(err) .. ")")

            -- Retry with next server after delay
            task.wait(3)

            M.currentServer = M.currentServer + 1
            if M.currentServer >= #M.serverList then
                M.currentServer = 0
                FetchServerList()
            end

            local nextServer = M.serverList[M.currentServer]
            if nextServer and nextServer.id then
                print("[Teleport Retry] Next server ->", nextServer.id)
                TeleportAndReinject(placeId, nextServer.id)
            else
                warn("No valid servers left to retry.")
            end
        end
    end)
end

-- === Server Hop ===
local function ServerHop()
    if #M.serverList == 0 then
        warn("[SHop] -> Server list is empty.")
        FetchServerList()
        return
    end

    M.currentServer = M.currentServer + 1

    if M.currentServer >= #M.serverList then
        M.currentServer = 0
        FetchServerList()
    end

    local server = M.serverList[M.currentServer]
    if not server or not server.id then
        warn("[SHop] -> Invalid server data.")
        return
    end

    TeleportAndReinject(PLACE_ID, server.id)
end

-- === Retrieve Webhook ===
local function GetWebhookFor(name)
    if HOOKS[name] then
        return HOOKS[name]
    end

    if string.find(name, "underworld") then
        return HOOKS["underworld"]
    end

    local lower = string.lower(name)
    if string.find(lower, "-egg") then
        return HOOKS[lower]
    elseif string.find(lower, "chest") then
        return HOOKS[lower]
    elseif lower == "rift-vendor" then
        return HOOKS[lower]
    end

    return nil -- fallback
end

-- === Webhook Sender ===
local function SendToDiscord(payload, hookURL)
    if not payload or not hookURL then
        warn("Missing payload or webhook URL.")
        return
    end

    local success, response = pcall(function()
        return HttpService:RequestAsync({
            Url = hookURL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode(payload)
        })
    end)

    if success and response.Success then
        print("Webhook sent to:", hookURL)
    else
        warn("Webhook failed:", response and response.StatusMessage or "Unknown error")
    end
end

-- === Parse Time ===
local function ParseTimeToSeconds(timeStr)
    local num = tonumber(string.match(timeStr, "%d+"))
    if not num then return 0 end
    if string.find(timeStr, "minute") then
        return num * 60
    elseif string.find(timeStr, "second") then
        return num
    else
        return 0
    end
end

-- === Rift Images ===
local IMAGES = {
    ["x5"] = "https://static.wikia.nocookie.net/bgs-infinity/images/5/5b/Common_Egg.png/revision/latest?cb=20250412180346",
    ["x10"] = "https://static.wikia.nocookie.net/bgs-infinity/images/5/5b/Common_Egg.png/revision/latest?cb=20250412180346",
    ["silly-egg"] = "https://static.wikia.nocookie.net/bgs-infinity/images/3/3a/Silly_Egg.png/revision/latest?cb=20250430025645",
    ["void-egg"] = "https://static.wikia.nocookie.net/bgs-infinity/images/5/58/Void_Egg.png/revision/latest?cb=20250412180803",
    ["nightmare-egg"] = "https://static.wikia.nocookie.net/bgs-infinity/images/4/43/Nightmare_Egg.png/revision/latest?cb=20250412170032",
    ["rainbow-egg"] = "https://static.wikia.nocookie.net/bgs-infinity/images/3/3f/Rainbow_Egg.png/revision/latest?cb=20250412180318",
    ["cyber-egg"] = "https://static.wikia.nocookie.net/bgs-infinity/images/7/7b/Cyber_Egg.png/revision/latest?cb=20250505010121",
    ["neon-egg"] = "https://static.wikia.nocookie.net/bgs-infinity/images/b/b1/Neon_Egg.png/revision/latest?cb=20250517192412",
    ["underworld-0"] = "https://static.wikia.nocookie.net/bgs-infinity/images/f/ff/Underworld_Egg.png/revision/latest?cb=20250510201410",
    ["underworld-1"] = "https://static.wikia.nocookie.net/bgs-infinity/images/f/ff/Underworld_Egg.png/revision/latest?cb=20250510201410",
    ["underworld-2"] = "https://static.wikia.nocookie.net/bgs-infinity/images/f/ff/Underworld_Egg.png/revision/latest?cb=20250510201410",
    ["underworld-3"] = "https://static.wikia.nocookie.net/bgs-infinity/images/f/ff/Underworld_Egg.png/revision/latest?cb=20250510201410",
    ["bubble-rift"] = "https://static.wikia.nocookie.net/bgs-infinity/images/0/0c/Bubbles.png/revision/latest/scale-to-width-down/25?cb=20250430031457",
    ["royal-chest"] = "https://static.wikia.nocookie.net/bgs-infinity/images/e/eb/Royal_Key.png/revision/latest?cb=20250412204328",
    ["dice-chest"] = "https://static.wikia.nocookie.net/bgs-infinity/images/e/e4/Dice_Key.png/revision/latest?cb=20250505071325",
    ["rift-vendor"] = "https://static.wikia.nocookie.net/bgs-infinity/images/7/73/Fruit_Egg.png/revision/latest?cb=20250525203558",
}

-- === Rift Finder ===
local function CheckRifts()
    local riftsFolder = game.Workspace:FindFirstChild("Rendered") and game.Workspace.Rendered:FindFirstChild("Rifts")
    if not riftsFolder then
        warn("No folder found for rifts.")
        return
    end

    for _, obj in pairs(riftsFolder:GetChildren()) do
        if not obj:IsA("Model") then continue end
        if not Contains(CONFIG, obj.Name) then continue end

        local objName = obj.Name
        local lowerName = string.lower(objName)
        local webhookKey = objName  -- 🔑 Start with original name

        local sign = obj:FindFirstChild("Display") and obj.Display:FindFirstChild("SurfaceGui")
        if not sign then continue end

        local height = math.round(obj:GetPivot().Position.Y)
        local timer = sign:FindFirstChild("Timer") and sign.Timer.Text or "Unknown"
        local timeInSeconds = ParseTimeToSeconds(timer)
        local expireTimestamp = os.time() + timeInSeconds

        -- Build base embed
        local embed = {
            title = objName,
            description = "**Height:** `" .. tostring(height) .. "`" ..
                        "\n**Time left:** `" .. timer .. "`" ..
                        "\n**Expires:** <t:" .. expireTimestamp .. ":R>" ..
                        "\n**PlaceId:** `" .. PLACE_ID .. "`" ..
                        "\n**JobId:** `" .. JOB_ID .. "`" ..
                        "\n**By:** `" .. Players.LocalPlayer.Name .. "`",
            color = 5814783
        }

        -- === Add Image ===
        local imageURL = IMAGES[objName]
        if imageURL then
            embed.image = { url = imageURL }
        end

        -- === Determine object type by name ===
        local isEgg = string.find(lowerName, "-egg") or string.find(lowerName, "underworld")
        local isChestOrVendor = string.find(lowerName, "chest") or lowerName == "rift-vendor"
        local shouldSend = false

        -- === Process eggs ===
        if isEgg then
            local luckText = sign:FindFirstChild("Icon") and sign.Icon:FindFirstChild("Luck") and sign.Icon.Luck.Text
            local luckValue = luckText and string.gsub(luckText, "[%a%s]", "") or ""

            if luckValue == "25" then
                embed.title = embed.title .. " x25"
                webhookKey = objName -- use the egg-specific webhook
                print("Found x25 egg:", objName)
                shouldSend = true
            elseif luckValue == "10" then
                embed.title = objName .. " x10"
                webhookKey = "x10"
                print("Found x10 egg:", objName)
                shouldSend = true
            elseif luckValue == "5" then
                embed.title = objName .. " x5"
                webhookKey = "x5"
                print("Found x5 egg:", objName)
                shouldSend = true
            end

        -- === Process chests and vendors (no luck needed) ===
        elseif isChestOrVendor then
            print("Found chest/vendor:", objName)
            shouldSend = true

        -- === Process general rifts ===
        else
            print("Found rift:", objName)
            shouldSend = true
        end

        -- 🔁 Single webhook dispatch
        if shouldSend then
            local hookURL = GetWebhookFor(webhookKey)  -- ✅ Use correct hook key
            if hookURL then
                SendToDiscord({ username = "Gelatina.exe", embeds = { embed } }, hookURL)
            else
                warn("No webhook for:", webhookKey)
            end
        end
    end

    -- Server hop if no matching item was processed
    ServerHop()
end

-- === Begin Script ===
print("[RiftFinder] Checking...")
CheckRifts()
