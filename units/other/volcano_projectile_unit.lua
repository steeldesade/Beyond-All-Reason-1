--------------------------------------------------------------------------------
-- Volcano Projectile Launcher (dummy unit with embedded weaponDef)
--------------------------------------------------------------------------------

return {
  volcano_projectile_unit = {
    activatewhenbuilt      = true,
    autoheal               = 0,
    energycost             = 1,
    metalcost              = 1,
    builder                = false,
    buildpic               = "empty.png",
    buildtime              = 1,
    canrepeat              = false,

    -- Baseline dummy model + script
    objectname             = "empty.s3o",
    script                 = "volcano_launcher_script.lua",

    category               = "NOTARGET",
    footprintx             = 1,
    footprintz             = 1,
    maxdamage              = 100,
    idleautoheal           = 0,
    idletime               = 0,

    canattack              = true,
    canmove                = false,
    canpatrol              = false,
    canstop                = true,

    sightdistance          = 0,
    radardistance          = 0,
    seismicsignature       = 0,

    mass                   = 1,
    explodeas              = "",
    selfdestructas         = "",

    customparams = {
      is_dummy_unit = 1,
    },

    --------------------------------------------------------------------------------
    -- Embedded WeaponDef (BALLISTIC CANNON VERSION)
    --------------------------------------------------------------------------------
    weapondefs = {
      weapon = {
        name               = "Volcano Fireball",

        -- SWITCH: missile-style → cannon-style ballistics
        weapontype         = "Cannon",

        -- Projectile model (unchanged)
        model              = "rocks30/rocks30_def_19.s3o",
        -- CEG FX (unchanged)
        cegtag             = "volcano_rock_trail",
        explosiongenerator = "custom:volcano_rock_impact",

        -- True ballistic behavior
        gravityaffected    = "true",
        hightrajectory     = 1,          -- engine uses a high arc solution
        trajectoryheight   = 1.1,
	mygravity          = 0.16,
	range              = 32000,
        reloadtime         = 5,

        -- Pure cannon velocity (no missile accel)
        weaponvelocity     = 780,        -- tuned for a strong upward arc
        -- removed: startvelocity
        -- removed: weaponacceleration
        -- removed: flighttime

        wobble             = 0,
        smoketrail         = false,

        -- Impact + collision behavior (unchanged)
        areaofeffect       = 150,
        turret             = true,

        avoidfeature       = false,
        avoidfriendly      = false,
        collidefriendly    = false,
        collidefeature     = false,
        collideground      = true,

        firestarter        = 80,

        damage = {
          default = 500,
        },

        soundhit           = "xplolrg1",
        soundhitwet        = "sizzle",
        soundhitwetvolume  = 0.5,
      },
    },

    --------------------------------------------------------------------------------
    -- Link weapon slot to weapondefs.weapon
    --------------------------------------------------------------------------------
    weapons = {
      [1] = {
        def = "WEAPON",
        onlyTargetCategory = "NOTHING",
      },
    },
  },
}
