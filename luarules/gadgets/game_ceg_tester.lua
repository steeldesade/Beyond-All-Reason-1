function gadget:GetInfo()
    return {
        name    = "CEG Tester",
        desc    = "Spawns CEGs on demand for testing",
        author  = "Lonie + ChatGPT",
        enabled = true,
        layer   = 0,
    }
end

-- Synced only
if not gadgetHandler:IsSyncedCode() then
    return
end

local spSpawnCEG        = Spring.SpawnCEG
local spGetGroundHeight = Spring.GetGroundHeight
local spEcho            = Spring.Echo

local math   = math
local cos    = math.cos
local sin    = math.sin
local sqrt   = math.sqrt
local pi     = math.pi
local random = math.random

local PREFIX_SINGLE = "cegtest:"        -- original, single CEG
local PREFIX_MULTI  = "cegtest_multi:"  -- new, multi-CEG combo

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function SpawnCEG(name, x, z)
    if not name or name == "" then return end
    x = tonumber(x)
    z = tonumber(z)
    if not x or not z then
        spEcho("[CEG Tester] ERROR: bad coordinates")
        return
    end

    local y = spGetGroundHeight(x, z) or 0
    spSpawnCEG(name, x, y, z, 0, 1, 0, 0, 0)
end

-- Spawn a *set* of CEGs simultaneously at one point
local function SpawnCEGSet(names, x, z)
    if type(names) ~= "table" then
        return
    end
    for i = 1, #names do
        SpawnCEG(names[i], x, z)
    end
end

-- Pattern dispatcher: applies line / ring / scatter,
-- and at each point spawns ALL selected CEGs simultaneously.
local function SpawnPattern(names, x, z, count, spacing, pat)
    if count < 1 then count = 1 end
    if count > 100 then count = 100 end
    if spacing < 0 then spacing = 0 end

    if pat ~= "line" and pat ~= "ring" and pat ~= "scatter" then
        pat = "line"
    end

    if pat == "line" then
        ------------------------------------------------
        -- LINE: along +X from (x,z)
        ------------------------------------------------
        for i = 0, count - 1 do
            local ox = x + i * spacing
            local oz = z
            SpawnCEGSet(names, ox, oz)
        end

    elseif pat == "ring" then
        ------------------------------------------------
        -- RING: count points around a circle
        ------------------------------------------------
        local radius = spacing * 5  -- keeps your previous “bigger ring” behavior
        for i = 0, count - 1 do
            local angle = (2 * pi * i) / count
            local ox = x + radius * cos(angle)
            local oz = z + radius * sin(angle)
            SpawnCEGSet(names, ox, oz)
        end

    elseif pat == "scatter" then
        ------------------------------------------------
        -- SCATTER: random points within radius
        ------------------------------------------------
        local radius = spacing * 3  -- keeps your previous scatter scaling
        for i = 1, count do
            local r     = radius * sqrt(random())
            local angle = 2 * pi * random()
            local ox    = x + r * cos(angle)
            local oz    = z + r * sin(angle)
            SpawnCEGSet(names, ox, oz)
        end
    end
end

-- /luarules ceg NAME X Z (optional helper)
function gadget:TextCommand(cmd)
    if cmd:sub(1, 4) ~= "ceg " then return end

    local name, xs, zs = cmd:match("^ceg%s+(%S+)%s*(%S*)%s*(%S*)$")
    if not name or name == "" then return end
    SpawnCEG(name, xs, zs)
end

------------------------------------------------------------
-- Widget messages:
--   SINGLE (legacy): cegtest:name:x:z:count:spacing:pattern
--   MULTI (new):    cegtest_multi:name1,name2,...:x:z:count:spacing:pattern
------------------------------------------------------------

function gadget:RecvLuaMsg(msg, playerID)
    local isMulti = false
    local body

    if msg:sub(1, #PREFIX_MULTI) == PREFIX_MULTI then
        isMulti = true
        body    = msg:sub(#PREFIX_MULTI + 1)
    elseif msg:sub(1, #PREFIX_SINGLE) == PREFIX_SINGLE then
        isMulti = false
        body    = msg:sub(#PREFIX_SINGLE + 1)
    else
        return -- not for us
    end

    -- Common parse: <name-or-list>:x:z:count:spacing:pattern
    local nameField, xs, zs, cs, ss, pat =
        body:match("^([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)$")

    if not nameField then
        spEcho("[CEG Tester] ERROR: bad message: " .. tostring(msg))
        return
    end

    -- Build the list of names
    local names = {}
    if isMulti then
        -- nameField = "ceg1,ceg2,ceg3"
        for n in nameField:gmatch("([^,]+)") do
            n = n:match("^%s*(.-)%s*$") -- trim
            if n ~= "" then
                names[#names + 1] = n
            end
        end
        if #names == 0 then
            spEcho("[CEG Tester] ERROR: multi message had no CEG names")
            return
        end
    else
        -- single name
        local n = nameField:match("^%s*(.-)%s*$")
        if n == "" then
            spEcho("[CEG Tester] ERROR: empty CEG name")
            return
        end
        names[1] = n
    end

    local x       = tonumber(xs)
    local z       = tonumber(zs)
    local count   = tonumber(cs) or 1
    local spacing = tonumber(ss) or 0
    pat           = tostring(pat or "line")

    if not x or not z then
        spEcho("[CEG Tester] ERROR: bad coordinates in message")
        return
    end

    -- Single unified pattern handler: at each point, spawn ALL names simultaneously
    SpawnPattern(names, x, z, count, spacing, pat)
end
