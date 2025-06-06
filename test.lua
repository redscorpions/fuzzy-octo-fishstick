-- Prevent duplicate runs
if getgenv().TEST_LOADED then print("[test.lua] Script already injected") return end
getgenv().TEST_LOADED = true

-- Wait for game to fully load
if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(1)

print("[test.lua] Re-injected successfully")

if typeof(getgenv().CONFIG) == "table" then
    print("CONFIG value:", table.concat(getgenv().CONFIG, ", "))
else
    warn("CONFIG is not a table:", typeof(getgenv().CONFIG))
end

-- Services
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

-- Default test config
getgenv().CONFIG = getgenv().CONFIG or { "Nothing" }

-- Convert stringified config to table if needed
if typeof(getgenv().CONFIG) == "string" then
    local success, result = pcall(function()
        return HttpService:JSONDecode(getgenv().CONFIG)
    end)
    if success then
        getgenv().CONFIG = result
    else
        warn("Invalid JSON CONFIG: ", result)
        getgenv().CONFIG = { "Nothing" }
    end
end

-- queue_on_teleport reinjection
if queue_on_teleport then
    print("[Teleport] queue_on_teleport is available")

    local queueCode = string.format([[
        getgenv().CONFIG = game:GetService("HttpService"):JSONDecode(%q)
        getgenv().TEST_LOADED = nil
        loadstring(game:HttpGet("https://raw.githubusercontent.com/redscorpions/fuzzy-octo-fishstick/main/test.lua"))()
    ]], HttpService:JSONEncode(getgenv().CONFIG))

    queue_on_teleport(queueCode)
else
    warn("queue_on_teleport is not available on this executor!")
end

-- Perform teleport
task.wait(20)

local success, err = pcall(function()
    print("[Teleport] Sending to new server...")
    TeleportService:Teleport(game.PlaceId)
end)

if not success then
    warn("[Teleport] Failed:", err)
end
