-- wait for game to load --
task.wait(5)

-- services --
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

-- place info --
local JOB_ID = game.JobId
local PLACE_ID = game.PlaceId -- Added missing PLACE_ID

-- config --
local PROXY_URL = getgenv().PROXY_URL
local HOOK = getgenv().HOOK
local CONFIG = getgenv().CONFIG

-- private globals --
M.currentServer = M.currentServer or 1

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
        M.serverList = data.data
    else
        warn("Failed to get server list: "..tostring(response and response.StatusMessage or "Unknown error"))
        M.serverList = {}
    end
end

for i, v in pairs(M.serverList) do
    print(i, v.id)
end

-- auxiliary --
local function Contains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

-- server hop --
local function ServerHop()
    -- manage server index --
    if M.currentServer >= #M.serverList then
        M.currentServer = 1
    else
        M.currentServer = M.currentServer + 1
    end

    -- queue the script to run after teleport
    if queue_on_teleport then
        queue_on_teleport(string.format([[
            getgenv().PROXY_URL = %q
            getgenv().HOOK = %q
            getgenv().CONFIG = %q
            getgenv().M = %s
            loadstring(game:HttpGet('https://raw.githubusercontent.com/redscorpions/fuzzy-octo-fishstick/refs/heads/main/RiftFinder.lua'))()
        ]], 
        PROXY_URL,
        HOOK,
        HttpService:JSONEncode(CONFIG),
        HttpService:JSONEncode(M)))
    end

    -- perform the teleport
    local success, err = pcall(function()
        TeleportService:Teleport(M.serverList[M.currentServer].id)
    end)

    if not success then
        warn("Experienced a problem while server hopping: " .. tostring(err))
    end
end

-- send webhook --
local function SendToDiscord(payload)
    if not payload then warn("No payload provided") return end
    
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

    if success then
        if response.Success then
            print("Webhook sent successfully")
        else
            warn("Webhook request failed: "..response.StatusMessage)
        end
    else
        warn("Failed to send webhook: " .. tostring(response))
    end
end

-- rifts --
local riftsFolder = game.Workspace:FindFirstChild("Rendered"):FindFirstChild("Rifts")

-- find config rifts --
local function CheckRifts()
    if not riftsFolder then warn("No folder found for rifts") return end

    -- check for x25 servers --
    for _, rift in pairs(riftsFolder:GetChildren()) do
        if not rift:IsA("Model") then continue end
        if not Contains(CONFIG, rift.Name) then warn("Filtering " .. rift.Name) continue end

        local sign = rift:FindFirstChild("Display") and rift.Display:FindFirstChild("SurfaceGui")
        if not sign then warn("No sign found for " .. rift.Name) continue end

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
        if luckText then
            if string.gsub(luckText, "[%a%s]", "") == "25" then
                print("Found x25 rift")
                embed.title = embed.title .. " " .. luckText
            end
        end
      
        payload = {
            username = "Text.exe",
            embeds = { embed }
        }

        SendToDiscord(payload)
    end

    -- server hop if no rifts found --
    ServerHop()
end

-- wait for game to load --
print("Checking...")
CheckRifts()
