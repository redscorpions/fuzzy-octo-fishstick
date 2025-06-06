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
local HOOK = getgenv().HOOK
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
    if queue_on_teleport then
        local queueCode = string.format([[
            getgenv().PROXY_URL = %q
            getgenv().HOOK = %q
            getgenv().CONFIG = game:GetService("HttpService"):JSONDecode(%q)
            getgenv().M = game:GetService("HttpService"):JSONDecode(%q)
            getgenv().RIFT_LOADED = nil
            loadstring(game:HttpGet("https://raw.githubusercontent.com/redscorpions/fuzzy-octo-fishstick/main/RiftFinder.lua"))()
        ]],
        PROXY_URL,
        HOOK,
        HttpService:JSONEncode(CONFIG),
        HttpService:JSONEncode(M))

        queue_on_teleport(queueCode)
    else
        warn("queue_on_teleport not available!")
        return
    end

    local success, err = pcall(function()
        print("[Teleport] ->", jobId)
        TeleportService:TeleportToPlaceInstance(placeId, jobId, Players.LocalPlayer)
    end)

    if not success then
        warn("Teleport failed: " .. tostring(err))
        task.wait(2)

        -- Try next server
        M.currentServer = M.currentServer + 1
        if M.currentServer >= #M.serverList then
            M.currentServer = 0
            FetchServerList() -- Refresh the list
        end

        local nextServer = M.serverList[M.currentServer]
        if nextServer and nextServer.id then
            TeleportAndReinject(placeId, nextServer.id)
        else
            warn("No valid servers left.")
        end
    end
end

-- === Server Hop ===
local function ServerHop()
    if #M.serverList == 0 then
        warn("Server list is empty.")
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
        warn("Invalid server data.")
        return
    end

    TeleportAndReinject(PLACE_ID, server.id)
end

-- === Webhook Sender ===
local function SendToDiscord(payload)
    if not payload then
        warn("No payload provided.")
        return
    end

    local success, response = pcall(function()
        return HttpService:RequestAsync({
            Url = HOOK,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode(payload)
        })
    end)

    if success and response.Success then
        print("Webhook sent.")
    else
        warn("Webhook failed:", response and response.StatusMessage or "Unknown error")
    end
end

-- === Rift Finder ===
local function CheckRifts()
    local riftsFolder = game.Workspace:FindFirstChild("Rendered") and game.Workspace.Rendered:FindFirstChild("Rifts")
    if not riftsFolder then
        warn("No folder found for rifts.")
        return
    end

    for _, rift in pairs(riftsFolder:GetChildren()) do
        if not rift:IsA("Model") then continue end
        if not Contains(CONFIG, rift.Name) then warn("Filtered out " .. rift.Name) continue end

        local sign = rift:FindFirstChild("Display") and rift.Display:FindFirstChild("SurfaceGui")
        if not sign then warn("No sign for " .. rift.Name) continue end

        local riftName = rift.Name
        local height = math.round(rift:GetPivot().Position.Y)
        local timer = sign:FindFirstChild("Timer") and sign.Timer.Text or "Unknown"
        local timeLeft = string.gsub(timer, "[%a%s]", "")

        local embed = {
            title = riftName,
            description = "**Height:** `" .. tostring(height) ..
                         "`\n**Time left:** `" .. timeLeft ..
                         "`\n**PlaceId:** `" .. PLACE_ID ..
                         "`\n**JobId:** `" .. JOB_ID ..
                         "`\n**By:** `" .. Players.LocalPlayer.Name .. "`",
            color = 5814783
        }

        local luckText = sign:FindFirstChild("Icon") and sign.Icon:FindFirstChild("Luck") and sign.Icon.Luck.Text
        if luckText and string.gsub(luckText, "[%a%s]", "") == "25" then
            print("Found x25 rift")
            embed.title = embed.title .. " " .. luckText
        else
            -- continue
        end

        local payload = {
            username = "Text.exe",
            embeds = { embed }
        }

        SendToDiscord(payload)
    end

    -- No match? Hop to next server
    ServerHop()
end

-- === Begin Script ===
print("[RiftFinder] Checking...")
CheckRifts()
