-- Fault Line Earthquakes - Option D (Flames-only crack + circular area + volcano exclusion)
-- Random sinusoidal faultlines in a circular band, crack phase (visual + sound) then gradual band collapse.
-- Visuals are drawn from the UNSYNCED part of this gadget (no widget needed).

function gadget:GetInfo()
    return {
        name      = "Fault Line Earthquakes",
        desc      = "Dynamic regenerating random curvy faultlines, crack pre-visual, then terrain collapse + sounds",
        author    = "ChatGPT + Lonie",
        date      = "2025",
        license   = "GPL",
        layer     = 0,
        enabled   = true,
    }
end

------------------------------------------------------------
-- SHARED CONFIG
------------------------------------------------------------

local WARNING_FRAMES         = 90    -- ~3 seconds at 30 fps
local CRACK_DURATION_FRAMES  = 120   -- ~4 seconds for the crack to travel
local COLLAPSE_STEPS         = 30    -- frames for the ground to fully sink
local FLAME_EXTRA_FRAMES     = 90    -- flames stay ~3s AFTER collapse finishes (reserved for future use)

------------------------------------------------------------
-- SYNCED
------------------------------------------------------------
if gadgetHandler:IsSyncedCode() then

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

local NUM_LINES         = 3          -- how many possible faultlines exist at once
local RUPTURE_WIDTH     = 60         -- radius of damage / deformation band
local RUPTURE_DEPTH     = 2          -- vertical change
local QUAKE_MIN_FRAMES  = 30 * 30    -- 30 seconds (testing)
local QUAKE_MAX_FRAMES  = 30 * 30    -- same = fixed 30s

local mapX = Game.mapSizeX
local mapZ = Game.mapSizeZ

-- For compatibility with older versions (not used for geometry anymore)
local midMinX = mapX * 0.20
local midMaxX = mapX * 0.80
local midMinZ = mapZ * 0.20
local midMaxZ = mapZ * 0.80

-- New circular quake band + volcano exclusion
local centerX = mapX * 0.5
local centerZ = mapZ * 0.5

-- Treat "18% of map width" as *diameter* of the exclusion zone -> radius = 9%
local volcanoRadius     = (mapX * 0.22) * 0.5
local volcanoRadiusSq   = volcanoRadius * volcanoRadius

-- Outer radius for where faultlines may exist (circular instead of the old square mid-band)
local outerRadius       = math.min(mapX, mapZ) * 0.28
local outerRadiusSq     = outerRadius * outerRadius

-- Helpers for ring checks
local function InVolcanoExclusion(x, z)
    local dx, dz = x - centerX, z - centerZ
    return (dx * dx + dz * dz) < volcanoRadiusSq
end

local function InQuakeRing(x, z)
    local dx, dz = x - centerX, z - centerZ
    local d2 = dx * dx + dz * dz
    return (d2 >= volcanoRadiusSq) and (d2 <= outerRadiusSq)
end

-- Borrow lava CEGs from the map's lava gadget if present
local lava = Spring.Lava or {}
local lavaEffectBurst  = lava and lava.effectBurst
local lavaEffectDamage = lava and lava.effectDamage

local spSpawnCEG = Spring.SpawnCEG

-- For collapse we now sink the *whole* band gradually, not a finger.
local POINTS_PER_FRAME  = 1   -- kept for possible future use

local faultLines     = {}
_G.faultLines        = faultLines   -- exposed so UNSYNCED can read them
local activeRuptures = {}
local pendingQuakes  = {}
local nextQuake      = 0

------------------------------------------------------------
-- RANDOM SINUSOIDAL / JAGGED FAULTLINES (CIRCULAR AREA + VOLCANO HOLE)
------------------------------------------------------------

local function GenerateRandomCurvyLine()
    local pts = {}

    ----------------------------------------------------------------
    -- 1) Pick a starting point in the circular quake band (ring)
    ----------------------------------------------------------------
    local x, z
    local tries = 0

    repeat
        -- random radius + angle around map center
        local r     = math.random() * outerRadius
        local theta = math.random() * math.pi * 2
        x = centerX + math.cos(theta) * r
        z = centerZ + math.sin(theta) * r
        tries = tries + 1
        if tries > 50 then
            break
        end
    until InQuakeRing(x, z)

    -- Fallback: if for some reason we failed to get a ring point, pick something sane
    if not InQuakeRing(x, z) then
        x = math.random(mapX * 0.25, mapX * 0.75)
        z = math.random(mapZ * 0.25, mapZ * 0.75)
        -- If this lands inside the volcano, nudge it sideways out of the hole
        if InVolcanoExclusion(x, z) then
            if x < centerX then
                x = centerX - volcanoRadius - 40
            else
                x = centerX + volcanoRadius + 40
            end
        end
    end

    pts[#pts + 1] = { x, z }

    ----------------------------------------------------------------
    -- 2) Sinusoidal wandering instead of purely random turning
    ----------------------------------------------------------------
    local numSeg     = math.random(10, 20)
    local baseAngle  = math.random() * math.pi * 2
    local waveAmp    = math.rad(45)   -- how hard we sway left/right
    local waveFreq   = 0.40           -- how tightly we wiggle

    local base       = outerRadius
    local minStep    = base * 0.08
    local maxStep    = base * 0.14

    for i = 2, numSeg do
        -- angle is a base direction plus a sinusoidal offset
        local wave  = math.sin(i * waveFreq) * waveAmp
        local angle = baseAngle + wave

        local len = math.random(minStep, maxStep)
        local nx  = x + math.cos(angle) * len
        local nz  = z + math.sin(angle) * len

        -- Try a few times to steer the segment back into the allowed ring
        local steerTries = 0
        while (not InQuakeRing(nx, nz)) and steerTries < 3 do
            -- turn mostly around and try again
            angle = angle + math.pi * 0.6
            nx    = x + math.cos(angle) * len
            nz    = z + math.sin(angle) * len
            steerTries = steerTries + 1
        end

        -- Clamp into map bounds (safety)
        if nx < 0 then nx = 0 end
        if nx > mapX then nx = mapX end
        if nz < 0 then nz = 0 end
        if nz > mapZ then nz = mapZ end

        -- If it's still invalid after steering, just stop the line here.
        if not InQuakeRing(nx, nz) then
            break
        end

        x, z = nx, nz
        pts[#pts + 1] = { x, z }
    end

    return pts
end

local function InterpolateCurvy(raw)
    local pts = {}
    for i = 1, #raw - 1 do
        local x1, z1 = raw[i][1],   raw[i][2]
        local x2, z2 = raw[i+1][1], raw[i+1][2]
        local dx, dz = x2 - x1, z2 - z1
        local dist   = math.sqrt(dx*dx + dz*dz)
        -- more steps for longer segments; keeps the path smooth and continuous
        local steps  = math.max(5, math.floor(dist / 10))

        for s = 0, steps - 1 do
            local t = s / steps
            pts[#pts + 1] = { x1 + dx * t, z1 + dz * t }
        end
    end
    -- ensure we include the last raw point
    pts[#pts + 1] = raw[#raw]
    return pts
end

local function RegenerateFaultLines()
    faultLines = {}
    _G.faultLines = faultLines

    for i = 1, NUM_LINES do
        local raw = GenerateRandomCurvyLine()
        faultLines[i] = {
            raw    = raw,
            points = InterpolateCurvy(raw),

            -- crack / collapse + VFX meta (populated per-quake)
            crackStartIdx   = nil,
            crackFrontIdx   = nil,
            crackLastIdx    = nil,
            crackStep       = nil,

            collapseStartIdx = nil,
            collapseLastIdx  = nil,

            -- last index we spawned CEGs for along this crack
            lastCEGIdx       = nil,
        }
    end

    Spring.Echo("[FaultQuake] Regenerated faultlines (circular band + volcano exclusion)")
end

------------------------------------------------------------
-- DAMAGE + TERRAIN (band collapse)
------------------------------------------------------------

local function DamageUnitsAt(x, z, stepScale)
    local scale = stepScale or 1.0
    local units = Spring.GetAllUnits()
    local r2    = RUPTURE_WIDTH * RUPTURE_WIDTH

    for _, u in ipairs(units) do
        local ux, uy, uz = Spring.GetUnitPosition(u)
        if ux then
            local dx, dz = ux - x, uz - z
            local dist2  = dx*dx + dz*dz
            if dist2 <= r2 then
                local dist   = math.sqrt(dist2)
                local factor = 1 - (dist / RUPTURE_WIDTH)
                if factor > 0 then
                    Spring.AddUnitDamage(u, 120 * factor * scale)
                end
            end
        end
    end
end

-- Apply one "step" of collapse: sink the whole band along [startIdx, lastIdx]
local function ApplyCollapseStep(rupture)
    local pts     = rupture.pts
    local sIdx    = rupture.startIdx
    local eIdx    = rupture.lastIdx
    local dStep   = rupture.stepDepth

    if sIdx > eIdx then
        return
    end

    Spring.SetHeightMapFunc(function()
        for i = sIdx, eIdx do
            local p  = pts[i]
            local cx = p[1]
            local cz = p[2]

            for x = cx - RUPTURE_WIDTH, cx + RUPTURE_WIDTH, Game.squareSize do
                for z = cz - RUPTURE_WIDTH, cz + RUPTURE_WIDTH, Game.squareSize do
                    local dx, dz = x - cx, z - cz
                    if dx*dx + dz*dz <= (RUPTURE_WIDTH * RUPTURE_WIDTH) then
                        Spring.AddHeightMap(x, z, dStep)
                    end
                end
            end
        end
    end)

    -- Per-step damage so over all steps it roughly matches the old total
    local stepScale = 1.0 / COLLAPSE_STEPS
    for i = sIdx, eIdx do
        local p = pts[i]
        DamageUnitsAt(p[1], p[2], stepScale)
    end
end

------------------------------------------------------------
-- CRACK VFX: flames / smoke along the fissure (CEGs)
------------------------------------------------------------

local CEG_SPACING_POINTS = 25 -- how many interpolated points between CEGs

------------------------------------------------------------
-- COLLAPSE VFX: chaotic pulsing fire + smoke along entire segment
------------------------------------------------------------
local function SpawnCollapseEffects(rupture)
    if not spSpawnCEG then return end

    local pts     = rupture.pts
    local sIdx    = rupture.startIdx
    local eIdx    = rupture.lastIdx
    local count   = math.random(4, 7) -- P2 intensity

    for i = 1, count do
        -- ambient glow along full segment
        for j = sIdx, eIdx, CEG_SPACING_POINTS do
            local p2 = pts[j]
            if p2 then
                local xg,zg = p2[1], p2[2]
                local yg = Spring.GetGroundHeight(xg,zg)
                spSpawnCEG("lava_glow", xg, yg+3, zg, 0,1,0)
            end
        end
        local idx = math.random(sIdx, eIdx)
        local p   = pts[idx]
        if p then
            local x, z = p[1], p[2]
            local y    = Spring.GetGroundHeight(x, z)

            -- primary flame bursts
            if lavaEffectBurst then
                spSpawnCEG(lavaEffectBurst, x, y + 12, z, 0, 1, 0)
            end
            if lavaEffectDamage then
                spSpawnCEG(lavaEffectDamage, x, y + 6, z, 0, 1, 0)
            end

            -- extra smoke + pop bursts
            spSpawnCEG("unitsmokegen-beh", x, y + 10, z, 0, 1, 0)
            spSpawnCEG("smokegen-part2", x, y + 6, z, 0, 1, 0)
        end
    end
end


local function SpawnCrackEffects(line)
    if not spSpawnCEG then
        return
    end
    local pts        = line.points
    local startIdx   = line.lastCEGIdx or line.crackStartIdx
    local frontIdx   = line.crackFrontIdx
    if not pts or not startIdx or not frontIdx or frontIdx <= startIdx then
        return
    end

    -- clamp to valid range
    local n = #pts
    if startIdx < 1 then startIdx = 1 end
    if frontIdx > n then frontIdx = n end

    for i = startIdx, frontIdx, CEG_SPACING_POINTS do
        local p = pts[i]
        if p then
            local x, z = p[1], p[2]
            local y    = Spring.GetGroundHeight(x, z)

            -- use the map's lava CEGs if available, they already look like
            -- molten bursts + smoke. fall back to some generic ids otherwise.
            if lavaEffectBurst then
                spSpawnCEG(lavaEffectBurst, x, y + 10, z, 0, 1, 0)
            end
            if lavaEffectDamage then
                spSpawnCEG(lavaEffectDamage, x, y + 5, z, 0, 1, 0)
            end
            if (not lavaEffectBurst and not lavaEffectDamage) then
                -- generic fallback; harmless if missing, engine just logs once
                spSpawnCEG("lavasplash", x, y + 8, z, 0, 1, 0)
            end
        end
    end

    line.lastCEGIdx = frontIdx
end

------------------------------------------------------------
-- CRACK + COLLAPSE CONTROL
------------------------------------------------------------

-- Phase 1: fast crack visual (flames travel along this)
local function StartCrack(lineIndex)
    local line = faultLines[lineIndex]
    if not line or not line.points then
        Spring.Echo("[FaultQuake] StartCrack: missing line " .. tostring(lineIndex))
        return
    end

    local pts = line.points
    local n   = #pts
    if n < 10 then
        Spring.Echo("[FaultQuake] StartCrack: line too short, n=" .. n)
        return
    end

    -- Choose a partial segment
    local maxStart = math.max(1, n - 500)
    local start    = math.random(1, maxStart)
    local length   = math.random(250, 700)
    local last     = math.min(n, start + length)

    local totalPoints = last - start + 1
    local crackStep   = math.max(1, math.floor(totalPoints / CRACK_DURATION_FRAMES))

    line.crackStartIdx   = start
    line.crackFrontIdx   = start
    line.crackLastIdx    = last
    line.crackStep       = crackStep

    -- collapse will use the same segment
    line.collapseStartIdx = start
    line.collapseLastIdx  = last

    -- reset VFX progress along this line
    line.lastCEGIdx       = start

    -- Tell unsynced to play crack SFX
    SendToUnsynced("quake_crack", lineIndex, RUPTURE_WIDTH, CRACK_DURATION_FRAMES)

    -- collapse starts right after crack finishes
    local collapseFrame = Spring.GetGameFrame() + CRACK_DURATION_FRAMES
    pendingQuakes[#pendingQuakes + 1] = {
        frame = collapseFrame,
        line  = lineIndex,
        mode  = "collapse",
    }

    Spring.Echo(string.format(
        "[FaultQuake] Crack phase on line %d (%d -> %d) for %d frames, step=%d",
        lineIndex, start, last, CRACK_DURATION_FRAMES, crackStep
    ))
end

-- Phase 2: gradual band collapse (entire path sinks together)
local function StartCollapse(lineIndex)
    local line = faultLines[lineIndex]
    if not line or not line.points then
        Spring.Echo("[FaultQuake] StartCollapse: missing line " .. tostring(lineIndex))
        return
    end

    local pts = line.points
    local n   = #pts
    if n < 10 then
        Spring.Echo("[FaultQuake] StartCollapse: line too short, n=" .. n)
        return
    end

    local start = line.collapseStartIdx or line.crackStartIdx or 1
    local last  = line.collapseLastIdx  or line.crackLastIdx  or n

    local rupture = {
        pts       = pts,
        startIdx  = start,
        lastIdx   = last,
        curStep   = 0,
        maxSteps  = COLLAPSE_STEPS,
        stepDepth = -RUPTURE_DEPTH / COLLAPSE_STEPS,
    }
    activeRuptures[#activeRuptures + 1] = rupture

    -- Clear crack info so UNSYNCED stops drawing the crack line (if it did)
    line.crackStartIdx   = nil
    line.crackFrontIdx   = nil
    line.crackLastIdx    = nil
    line.crackStep       = nil

    Spring.Echo(string.format(
        "[FaultQuake] Collapse phase on line %d (%d -> %d) over %d frames",
        lineIndex, start, last, COLLAPSE_STEPS
    ))

    -- Now trigger the heavy rumble sound
    SendToUnsynced("quake_event", lineIndex, RUPTURE_WIDTH)
end

-- Initial scheduling: warning -> crack -> collapse
local function QueueCrack(line)
    local executeAt = Spring.GetGameFrame() + WARNING_FRAMES
    pendingQuakes[#pendingQuakes + 1] = {
        frame = executeAt,
        line  = line,
        mode  = "crack",
    }
    Spring.Echo("[FaultQuake] Crack for line " .. line .. " will start at frame " .. executeAt)
end

local function TriggerQuake(line)
    -- New random geometry each quake so paths are never reused
    RegenerateFaultLines()

    Spring.Echo("[FaultQuake] TriggerQuake on line " .. tostring(line))
    SendToUnsynced("quake_warning", "⚠ SEISMIC ACTIVITY DETECTED")
    QueueCrack(line)
end

------------------------------------------------------------
-- ENGINE CALLBACKS (SYNCED)
------------------------------------------------------------

function gadget:Initialize()
    RegenerateFaultLines()
end

function gadget:GameStart()
    local f = Spring.GetGameFrame()
    nextQuake = f + QUAKE_MIN_FRAMES
    Spring.Echo("[FaultQuake] First quake scheduled at frame " .. nextQuake)
end

function gadget:GameFrame(f)
    -- 1) Time to schedule a new quake?
    if f == nextQuake then
        local line = math.random(1, NUM_LINES)
        TriggerQuake(line)
        nextQuake = f + math.random(QUAKE_MIN_FRAMES, QUAKE_MAX_FRAMES)
        Spring.Echo("[FaultQuake] Next quake scheduled at frame " .. nextQuake)
    end

    -- 2) Process pending phases (crack / collapse)
    for i = #pendingQuakes, 1, -1 do
        local q = pendingQuakes[i]
        if f >= q.frame then
            if q.mode == "crack" then
                StartCrack(q.line)
            elseif q.mode == "collapse" then
                StartCollapse(q.line)
            end
            table.remove(pendingQuakes, i)
        end
    end

    -- 3) Advance crack front along each active crack (for drawing + VFX)
    for _, line in pairs(faultLines) do
        if line.crackStartIdx and line.crackFrontIdx and line.crackLastIdx then
            if line.crackFrontIdx < line.crackLastIdx then
                local inc = line.crackStep or 1
                line.crackFrontIdx = math.min(line.crackLastIdx, line.crackFrontIdx + inc)
            end

            -- spawn smoke / flame CEGs along the newly revealed segment
            SpawnCrackEffects(line)
        end
    end

    -- 4) Apply collapse steps (whole band sinking + pulsing fire)
    for i = #activeRuptures, 1, -1 do
        local r = activeRuptures[i]
        if r.curStep < r.maxSteps then
            ApplyCollapseStep(r)
            SpawnCollapseEffects(r)
            r.curStep = r.curStep + 1
        else
            table.remove(activeRuptures, i)
        end
    end
end

function gadget:RecvLuaMsg(msg, playerID)
    if not msg then
        return false
    end

    -- normalize / trim
    msg = msg:match("^%s*(.-)%s*$")
    msg = msg:lower()

    ------------------------------------------------------------
    -- EXISTING: Manual quake trigger
    ------------------------------------------------------------
    if msg == "quake" or msg:find("quake", 1, true) then
        Spring.Echo("[FaultQuake] Manual quake triggered by player " .. tostring(playerID))
        local line = math.random(1, NUM_LINES)
        TriggerQuake(line)
        return true
    end

    ------------------------------------------------------------
    -- NEW: debugfault toggle (Option A – appended)
    ------------------------------------------------------------
    if msg == "debugfault" then
        if not GG.faultDebug then GG.faultDebug = false end
        GG.faultDebug = not GG.faultDebug

        if GG.faultDebug then
            Spring.Echo("[FaultQuake] Debug overlay ENABLED")
        else
            Spring.Echo("[FaultQuake] Debug overlay DISABLED")
        end

        -- Inform UNSYNCED
        SendToUnsynced("fault_debug_toggle", GG.faultDebug and 1 or 0)
        return true
    end

    return false
end


------------------------------------------------------------
-- UNSYNCED (warning text + sounds)
------------------------------------------------------------
else

-- Expose fault lines to LuaUI (left for compatibility, but no longer required)
function GetFaultLinesForUI()
    -- This lets any UI code call: Script.LuaRules.GetFaultLinesForUI()
    return SYNCED and SYNCED.faultLines
end

local spGetGameFrame     = Spring.GetGameFrame
local spPlaySoundFile    = Spring.PlaySoundFile
local spGetViewGeometry  = Spring.GetViewGeometry

local glPushMatrix       = gl.PushMatrix
local glPopMatrix        = gl.PopMatrix
local glTranslate        = gl.Translate
local glText             = gl.Text

local warningText   = nil
local warningEnd    = 0

------------------------------------------------------------
-- SYNCED -> UNSYNCED ACTIONS (sound + UI)
------------------------------------------------------------

function gadget:Initialize()
    -- Warning: on-screen + LavaAlert voice, ~3s before quake
    gadgetHandler:AddSyncAction("quake_warning", function(_, msg)
        warningText = msg or "SEISMIC ACTIVITY DETECTED"
        warningEnd  = spGetGameFrame() + WARNING_FRAMES

        Spring.Echo("[FaultQuake] Warning: " .. warningText)

        -- User-provided path (relative to game VFS); must be forward slashes
        spPlaySoundFile("sounds/voice-soundeffects/LavaAlert.wav", 1.0, "ui")
    end)

    -- Crack phase: sharp cracking sound
    gadgetHandler:AddSyncAction("quake_crack", function(_, lineIdx, width, crackFrames)
        Spring.Echo("[FaultQuake] Crack phase for line " .. tostring(lineIdx) ..
            " over " .. tostring(crackFrames or CRACK_DURATION_FRAMES) .. " frames")

        -- Cracking earth sound
        spPlaySoundFile("sounds/atmos/thunder3.wav", 1.0, "ui")
    end)

    -- Collapse phase: deep rumble
    gadgetHandler:AddSyncAction("quake_event", function(_, lineIdx, width)
        Spring.Echo("[FaultQuake] Collapse event for line " .. tostring(lineIdx))

        -- User-provided path for rumble
        spPlaySoundFile("sounds/atmos/lavarumble3.wav", 1.0, "ui")
    end)

    -- Collapse phase: deep rumble
    gadgetHandler:AddSyncAction("quake_event", function(_, lineIdx, width)
        Spring.Echo("[FaultQuake] Collapse event for line " .. tostring(lineIdx))

        -- User-provided path for rumble
        spPlaySoundFile("sounds/atmos/lavarumble3.wav", 1.0, "ui")
    end)
end

------------------------------------------------------------
-- SCREEN UI (warning text)
------------------------------------------------------------

-- Big warning text at top of screen during WARNING_FRAMES
function gadget:DrawScreen()
    local frame = spGetGameFrame()
    if warningText and frame < warningEnd then
        local vsx, vsy = spGetViewGeometry()
        glPushMatrix()
        glTranslate(vsx * 0.5, vsy * 0.7, 0)
        glText(warningText, 0, 0, 36, "oc")
        glPopMatrix()
    end
end

------------------------------------------------------------
-- WORLD DRAW STUB (no custom GL flames)
------------------------------------------------------------

function gadget:DrawWorld()
    -- Intentionally empty: crack / collapse visuals are purely CEG-based now.
    -- This avoids extra LuaRules DrawWorld GL work that was causing OOM on pause
    -- and also eliminates any sprite lines along the path.
    -- No flame drawing anymore, but allow debug overlay when toggled
    if not debugEnabled then
        return
    end

    -- These values already exist in SYNCED; re-fetch from synced table
    local cx = SYNCED.centerX or Game.mapSizeX * 0.5
    local cz = SYNCED.centerZ or Game.mapSizeZ * 0.5
    local volcanoRadius = SYNCED.volcanoRadius or 300
    local outerRadius   = SYNCED.outerRadius or 1500

    gl.Color(1, 0.1, 0.1, 0.9)   -- red inner ring
    gl.DrawGroundCircle(cx, 0, cz, volcanoRadius, 64)

    gl.Color(0.2, 0.6, 1, 0.5)   -- blue outer ring
    gl.DrawGroundCircle(cx, 0, cz, outerRadius, 64)

    gl.Color(1,1,1,1)
end

end -- if synced / else
