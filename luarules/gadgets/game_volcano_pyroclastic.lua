--------------------------------------------------------------------------------
-- VOLCANO PYROCLASTIC ERUPTIONS — FINAL BASELINE #3 WITH RIM + BUILDUP FIRE + BUILDUP RUMBLE
--------------------------------------------------------------------------------

function gadget:GetInfo()
    return {
        name    = "Volcano Pyroclastic Eruptions",
        desc    = "Cinematic volcano eruption event for BAR",
        author  = "Steel",
        date    = "Dec 2025",
        layer   = 0,
        enabled = true,
    }
end

--------------------------------------------------------------------------------
-- SYNCED
--------------------------------------------------------------------------------
if gadgetHandler:IsSyncedCode() then

--------------------------------------------------------------------------------
-- Shortcuts
--------------------------------------------------------------------------------
local spCreateUnit         = Spring.CreateUnit
local spDestroyUnit        = Spring.DestroyUnit
local spGiveOrderToUnit    = Spring.GiveOrderToUnit
local spSpawnCEG           = Spring.SpawnCEG
local spGetGroundHeight    = Spring.GetGroundHeight
local spSetProjectileModel = Spring.SetProjectileModel
local spSetProjectileSpin  = Spring.SetProjectileSpin

local GameFrame            = Spring.GetGameFrame
local SendToUnsynced       = SendToUnsynced

local CMD_ATTACK           = CMD.ATTACK
local CMD_FIRE_STATE       = CMD.FIRE_STATE

--------------------------------------------------------------------------------
-- Volcano center
--------------------------------------------------------------------------------
local mapX = Game.mapSizeX
local mapZ = Game.mapSizeZ

local VX   = mapX * 0.5
local VZ   = mapZ * 0.5

-- Rim height offset
local VRIM = 600

--------------------------------------------------------------------------------
-- [RIM FIRE SYSTEM] Editable Rim Fire Parameters
--------------------------------------------------------------------------------
local VRIM_FIRE_HEIGHT = VRIM       -- << EDIT HEIGHT HERE

local FIRE_RIM_BASE  = 160          -- << EDIT RING BASE HERE
local FIRE_RIM_SCALE = 1.20         -- << EDIT RING SCALE %

local FIRE_RIM_RADIUS = FIRE_RIM_BASE * FIRE_RIM_SCALE

--------------------------------------------------------------------------------
-- [BUILDUP FIRE SYSTEM] Editable Parameters
--------------------------------------------------------------------------------
local BUILDUP_FIRE_MIN_PCT = 0.03   -- << EDIT MIN DISTANCE %
local BUILDUP_FIRE_MAX_PCT = 0.10   -- << EDIT MAX DISTANCE %

-- Option C: rare flickers (~1 every 1–2 seconds)
local BUILDUP_FIRE_CHANCE = 0.02    -- << EDIT CHANCE

local BUILDUP_FIRE_HEIGHT = 0       -- << Height offset for ground fire

--------------------------------------------------------------------------------
-- Timing
--------------------------------------------------------------------------------
local FIRST_MIN    = 20 * 30
local FIRST_MAX    = 35 * 30
local COOLDOWN_MIN = 50 * 30
local COOLDOWN_MAX = 80 * 30
local BUILDUP      = 20 * 30

local nextErupt = nil
local pendingDestroy = {}

-- [BUILDUP RUMBLE] Track if buildup rumble has played this cycle
local buildupSoundPlayed = false

local function R(a,b) return a + math.random()*(b-a) end

--------------------------------------------------------------------------------
-- Delayed call queue
--------------------------------------------------------------------------------

local delayed = {}

local function DelayCall(func, args, delay)
    local f = GameFrame() + delay
    if not delayed[f] then delayed[f] = {} end
    delayed[f][#delayed[f]+1] = {func,args}
end

--------------------------------------------------------------------------------
-- Rock models & spin utilities
--------------------------------------------------------------------------------

local rockModels = {
    "rocks30/rocks30_def_10.s3o",
    "rocks30/rocks30_def_12.s3o",
    "rocks30/rocks30_def_18.s3o",
    "rocks30/rocks30_def_19.s3o",
}

local function randomUnitVector()
    local x,y,z
    repeat
        x = math.random()*2 - 1
        y = math.random()*2 - 1
        z = math.random()*2 - 1
    until (x*x + y*y + z*z) > 0.05
    local d = math.sqrt(x*x + y*y + z*z)
    return x/d, y/d, z/d
end

--------------------------------------------------------------------------------
-- Smoke / Ash CEGs
--------------------------------------------------------------------------------

local function spawnAshBuild()
    local x = VX + math.random(-160,160)
    local z = VZ + math.random(-160,160)
    local y = spGetGroundHeight(x,z) + VRIM
    spSpawnCEG("volcano_ash_build", x,y,z)
end

local function spawnAshBig()
    local x = VX + math.random(-260,260)
    local z = VZ + math.random(-260,260)
    local y = spGetGroundHeight(x,z) + VRIM + 50
    spSpawnCEG("volcano_ash_big", x,y,z)
end

local function spawnAshSmall()
    local x = VX + math.random(-320,320)
    local z = VZ + math.random(-320,320)
    local y = spGetGroundHeight(x,z) + VRIM
    spSpawnCEG("volcano_ash_small", x,y,z)
end

local function pyro()
    for i=1,math.random(12,20) do
        local a = math.random()*math.pi*2
        local d = math.random(260,550)
        local x = VX + math.cos(a)*d
        local z = VZ + math.sin(a)*d
        local y = spGetGroundHeight(x,z) + 10
        spSpawnCEG("pyro_flow", x,y,z)
    end
end

--------------------------------------------------------------------------------
-- [RIM FIRE SYSTEM] Rim Fire Spawner
--------------------------------------------------------------------------------
local function spawnFireRimCEG()
    local a = math.random() * math.pi * 2
    local x = VX + math.cos(a) * FIRE_RIM_RADIUS
    local z = VZ + math.sin(a) * FIRE_RIM_RADIUS
    local y = spGetGroundHeight(x, z) + VRIM_FIRE_HEIGHT
    spSpawnCEG("fire-area-150", x, y, z)
end

--------------------------------------------------------------------------------
-- [BUILDUP FIRE SYSTEM] Ground Fire Spawner (5–15% map width)
--------------------------------------------------------------------------------
local function spawnBuildUpGroundFire()
    local pct = math.random() * (BUILDUP_FIRE_MAX_PCT - BUILDUP_FIRE_MIN_PCT) + BUILDUP_FIRE_MIN_PCT
    local radius = mapX * pct
    local a = math.random() * math.pi * 2

    local x = VX + math.cos(a) * radius
    local z = VZ + math.sin(a) * radius
    local y = spGetGroundHeight(x, z) + BUILDUP_FIRE_HEIGHT

    spSpawnCEG("fire-area-150", x, y, z)
end

--------------------------------------------------------------------------------
-- Fireball launcher
--------------------------------------------------------------------------------

local function launchFireball()
    local gy = spGetGroundHeight(VX,VZ)

    local uid = spCreateUnit(
        "volcano_projectile_unit",
        VX, gy + VRIM - 40, VZ, 0,
        Spring.GetGaiaTeamID()
    )
    if not uid then return end

    spGiveOrderToUnit(uid, CMD_FIRE_STATE, {2}, {})

    local a = math.random()*math.pi*2
    local d = 900 + math.random(900)
    local tx = VX + math.cos(a)*d
    local tz = VZ + math.sin(a)*d
    local ty = spGetGroundHeight(tx,tz) + 20

    spGiveOrderToUnit(uid, CMD_ATTACK, {tx,ty,tz}, {})

    pendingDestroy[uid] = GameFrame() + 10
end

--------------------------------------------------------------------------------
-- Main frame loop
--------------------------------------------------------------------------------

function gadget:GameFrame(f)

    -- delayed calls
    local list = delayed[f]
    if list then
        for i=1,#list do
            local func = list[i][1]
            local args = list[i][2]
            if args then func(args[1],args[2],args[3])
            else func() end
        end
        delayed[f] = nil
    end

    -- cleanup launchers
    for uid,kill in pairs(pendingDestroy) do
        if f >= kill then
            spDestroyUnit(uid,false,true)
            pendingDestroy[uid] = nil
        end
    end

    ------------------------------------------------------------
    -- START FIRST ERUPTION
    ------------------------------------------------------------
    if not nextErupt then
        nextErupt = f + R(FIRST_MIN,FIRST_MAX)
        return
    end

    local remain = nextErupt - f

    ------------------------------------------------------------
    -- SMOKE BUILDUP PHASE
    ------------------------------------------------------------
    if remain > 0 and remain <= BUILDUP then
        if f % 4 == 0 then spawnAshBuild() end

        ------------------------------------------------------------------------
        -- [BUILDUP FIRE SYSTEM] Rare ground fire flickers
        ------------------------------------------------------------------------
        if math.random() < BUILDUP_FIRE_CHANCE then
            spawnBuildUpGroundFire()
        end

        ------------------------------------------------------------------------
        -- [BUILDUP RUMBLE] Play buildup rumble once at start of smoke buildup
        ------------------------------------------------------------------------
        if not buildupSoundPlayed then
            SendToUnsynced("volcano_buildup_rumble", VX, spGetGroundHeight(VX,VZ), VZ)
            buildupSoundPlayed = true
        end

        return
    end

    ------------------------------------------------------------
    -- ERUPTION MOMENT
    ------------------------------------------------------------
    if f >= nextErupt then

        -- Reset buildup sound for next cycle
        buildupSoundPlayed = false  -- [BUILDUP RUMBLE]

        SendToUnsynced("volcano_sound", VX, spGetGroundHeight(VX,VZ), VZ)

        ------------------------------------------------------------------------
        -- [RIM FIRE SYSTEM] 3 bursts, 3 seconds apart, 3–5 fires each
        ------------------------------------------------------------------------
        local f_now = GameFrame()
        for burst = 1, 3 do
            local delay = burst * (3 * 30)
            DelayCall(function()
                local count = math.random(3,5)
                for i = 1, count do
                    spawnFireRimCEG()
                end
            end, nil, delay)
        end

        ------------------------------------------------------------------------
        -- ORIGINAL ASH + FIREBALL LOGIC (unchanged)
        ------------------------------------------------------------------------
        for i=1,28 do spawnAshBig() end

        local n = math.random(10,15)
        local total = 60
        local step = math.max(1, math.floor(total/n))

        for i=1,n do
            DelayCall(launchFireball, nil, i*step)
        end

        pyro()
        for i=1,18 do spawnAshSmall() end

        ------------------------------------------------------------------------
        -- CINEMATIC CHAOTIC EJECT BURSTS (Option D/E)
        -- Fires ~0.5s after eruption, then 3–5 chaotic bursts
        -- Spawns at crater using VRIM as height baseline
        ------------------------------------------------------------------------
        DelayCall(function()
            local x0 = VX
            local z0 = VZ
            local baseY = spGetGroundHeight(x0, z0) + VRIM

            local bursts = math.random(3,5)

            for i = 1, bursts do
                DelayCall(function()
                    -- random vertical range above rim so it’s clearly visible
                    local y = baseY + math.random(180, 420)

                    -- small horizontal offsets for chaos
                    local ox = math.random(-40, 40)
                    local oz = math.random(-40, 40)

                    spSpawnCEG("volcano_eject", x0 + ox, y, z0 + oz)

                end, nil, math.random(0, 25))  -- 0–0.8s staggering after first eject
            end

        end, nil, 15) -- first eject cluster ~0.5s after eruption start

        ------------------------------------------------------------------------
        -- Schedule next eruption
        ------------------------------------------------------------------------
        nextErupt = f + R(COOLDOWN_MIN,COOLDOWN_MAX)
    end
end

--------------------------------------------------------------------------------
-- Projectile override + fire trail
--------------------------------------------------------------------------------

local FIRE_CEG = "fire-area-150"
local activeRocks = {}

local function ApplyModelAndSpin(proID)
    spSetProjectileModel(proID, rockModels[math.random(#rockModels)])
    local ax,ay,az = randomUnitVector()
    spSetProjectileSpin(proID, 0.12 + math.random()*0.10, ax,ay,az)
end

function gadget:ProjectileCreated(proID, ownerID, weaponDefID)
    local wd = WeaponDefs[weaponDefID]
    if wd and wd.name == "Volcano Fireball" then
        DelayCall(ApplyModelAndSpin, {proID}, 1)
        activeRocks[proID] = true
    end
end

function gadget:ProjectileDestroyed(id)
    activeRocks[id] = nil
end

function gadget:ProjectileMoved(id, x, y, z)
    if activeRocks[id] then
        spSpawnCEG(FIRE_CEG, x, y, z)
    end
end

--------------------------------------------------------------------------------
-- UNSYNCED (sound)
--------------------------------------------------------------------------------
else

local spPlaySoundFile = Spring.PlaySoundFile

function gadget:Initialize()

    --------------------------------------------------------------------
    -- Eruption blast + rumble + explosion
    --------------------------------------------------------------------
    gadgetHandler:AddSyncAction("volcano_sound",
        function(_, x, y, z)
            Spring.Echo("[VOLCANO] volcano_sound at", x, y, z)

            spPlaySoundFile("sounds/atmos-local/lavaburst2.wav", 1.5, "ui")
            spPlaySoundFile("sounds/atmos/lavarumble3.wav", 0.9, "ui")
            spPlaySoundFile("sounds/weapons/xplolrg1.wav", 0.55, "ui")
        end
    )

    --------------------------------------------------------------------
    -- [BUILDUP RUMBLE] Low rumble during smoke formation
    --------------------------------------------------------------------
    gadgetHandler:AddSyncAction("volcano_buildup_rumble",
        function(_, x, y, z)
            Spring.Echo("[VOLCANO] buildup rumble at", x, y, z)
            spPlaySoundFile("sounds/atmos/lavarumble2.wav", 1.0, "ui")
        end
    )
end

end
--------------------------------------------------------------------------------
