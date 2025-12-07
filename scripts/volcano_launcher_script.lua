local base = piece "empty_root_piece"  -- piece from empty.s3o

function script.Create()
    Spring.Echo("[VOLCANO] Launcher script active")
end

function script.QueryWeapon(num)
    Spring.Echo("[VOLCANO] QueryWeapon:", num)
    return base
end

function script.AimFromWeapon(num)
    Spring.Echo("[VOLCANO] AimFromWeapon:", num)
    return base
end

function script.AimWeapon(num, heading, pitch)
    Spring.Echo("[VOLCANO] AimWeapon:", num, heading, pitch)
    return true
end

function script.FireWeapon(num)
    Spring.Echo("[VOLCANO] FireWeapon CALLED:", num)
end
