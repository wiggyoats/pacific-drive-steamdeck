-- PDThrottle: lower the tick rate of Pacific Drive Blueprint systems that don't need to update every frame.
-- Mods/PDThrottle/config.txt: one "/Game/Path/BP_X.BP_X_C seconds" per line ('#' comments).
-- Blueprint classes only exist once a map has loaded, so setup runs a few seconds after the player is (re)spawned:
-- one FindAllOf pass per class for objects already there, then NotifyOnNewObject for later spawns (no periodic
-- scanning: FindAllOf walks every UObject and would hitch the game thread).
local cfg = {}
local f = io.open("Mods/PDThrottle/config.txt", "r")
if f then
    for line in f:lines() do
        local path, secs = line:match("^%s*(/[%w_/%.]+)%s+([%d%.]+)")
        if path then table.insert(cfg, { path = path, short = path:match("%.([%w_]+)$"), secs = tonumber(secs) }) end
    end
    f:close()
end

local applied, notified = {}, {}
local function throttle(o, c)
    if not o:IsValid() or o:GetFullName():find("Default__", 1, true) then return end
    -- Actors have SetActorTickInterval, components SetComponentTickInterval
    local ok = pcall(function() o:SetActorTickInterval(c.secs) end)
    if not ok then ok = pcall(function() o:SetComponentTickInterval(c.secs) end) end
    applied[c.short] = (applied[c.short] or 0) + 1
    if not ok then print(string.format("PDThrottle: FAILED on %s\n", o:GetFullName())) end
end

local function setup()
    for _, c in ipairs(cfg) do
        local before = applied[c.short] or 0
        for _, o in ipairs(FindAllOf(c.short) or {}) do throttle(o, c) end
        if not notified[c.path] then
            notified[c.path] = true
            -- level-placed actors load their saved tick settings after construction, so set the interval a bit later
            NotifyOnNewObject(c.path, function(o)
                ExecuteWithDelay(2000, function() ExecuteInGameThread(function() throttle(o, c) end) end)
            end)
        end
        print(string.format("PDThrottle: %s %.2fs, %d existing\n", c.short, c.secs, (applied[c.short] or 0) - before))
    end
end

print(string.format("PDThrottle loaded, %d classes\n", #cfg))
if #cfg > 0 then
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
        ExecuteWithDelay(5000, function() ExecuteInGameThread(setup) end)
    end)
    -- report how many spawned-later objects were caught
    LoopAsync(30000, function()
        local s = ""
        for k, v in pairs(applied) do s = s .. k .. "=" .. v .. " " end
        print("PDThrottle: totals " .. s .. "\n")
        return false
    end)
end
