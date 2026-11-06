-- The fixed-size ammo crates and fuel tanks of the oldest ACF versions, for dupes that still hold them.
--
-- Nothing here is used by the game itself. The ammo crate and fuel tank code (acf_ammo and acf_fueltank, in their spawning.lua)
-- reads these two tables when a dupe has one of these old IDs, and turns it into a scalable crate or tank of the same size.

local Compatibility = ACF.Compatibility

---------------------------------------------------------------------------------------------------------------------
--  Fixed-size ammo crates (2019 - October 2020)
--      Dupes saved the crate's ID ("Ammo2x4x4") with the weapon in RoundId, the ammo type in RoundType and so on.
--      Size is the size of the crate model in inches. Offset is where the model's origin was compared to the middle of
--      that size, the scalable crate is put there so it ends up where the old one was.
--      The values are the ones ACF itself used when it moved to scalable crates (lua/acf/shared/ammo_crates/crates.lua).
---------------------------------------------------------------------------------------------------------------------
Compatibility.AmmoCrates = {
	["AmmoSmall"]   = { Size = Vector(20.44, 7.93, 13.77), Offset = Vector(-0.36, -0.01, 7.01) },
	["AmmoMedCube"] = { Size = Vector(26.27, 25.9, 26.3), Offset = Vector(-0.03, 0.42, 13.1) },
	["AmmoMedium"]  = { Size = Vector(51.9, 26.27, 25.9), Offset = Vector(-0.12, 0.42, 13.1) },
	["AmmoLarge"]   = { Size = Vector(52.17, 52.06, 51.92), Offset = Vector(-0.05, -0.38, 26.06) },
	["Ammo1x1x8"]   = { Size = Vector(11.09, 89.15, 11.13), Offset = Vector(0, -0.02, -0.12) },
	["Ammo1x1x6"]   = { Size = Vector(11.2, 66.51, 11.14), Offset = Vector(0, 0.02, -0.14) },
	["Ammo1x1x4"]   = { Size = Vector(11.16, 45.06, 11.11), Offset = Vector(0, 0.16, -0.17) },
	["Ammo1x1x2"]   = { Size = Vector(11.16, 22.43, 11.11), Offset = Vector(0, 0.05, -0.17) },
	["Ammo2x2x1"]   = { Size = Vector(20.06, 8.06, 20.06), Offset = Vector(-0.52, 0, 10.19) },
	["Ammo2x2x2"]   = { Size = Vector(20.06, 20.06, 20.06), Offset = Vector(-0.09, 0.51, 10.51) },
	["Ammo2x2x4"]   = { Size = Vector(20.06, 45.06, 20.06), Offset = Vector(-0.71, 0, 10.18) },
	["Ammo2x2x6"]   = { Size = Vector(22.45, 66.59, 22.33), Offset = Vector(0, 0, -0.1) },
	["Ammo2x2x8"]   = { Size = Vector(22.46, 90.1, 22.82), Offset = Vector(0, 0, -0.14) },
	["Ammo2x3x1"]   = { Size = Vector(32.06, 8.06, 20.06), Offset = Vector(-0.64, 0, 10.19) },
	["Ammo2x3x2"]   = { Size = Vector(32.06, 20.06, 20.06), Offset = Vector(-0.64, 0, 10.19) },
	["Ammo2x3x4"]   = { Size = Vector(32.06, 45.06, 20.06), Offset = Vector(-0.79, 0, 10) },
	["Ammo2x3x6"]   = { Size = Vector(31.94, 68.04, 20.1), Offset = Vector(-0.79, -0.04, 10.02) },
	["Ammo2x3x8"]   = { Size = Vector(31.94, 90.1, 20.1), Offset = Vector(-0.79, 0, 10.02) },
	["Ammo2x4x1"]   = { Size = Vector(45.06, 8.06, 20.06), Offset = Vector(-0.64, 0, 10.19) },
	["Ammo2x4x2"]   = { Size = Vector(45.06, 20.06, 20.06), Offset = Vector(-0.2, 0.71, 10.18) },
	["Ammo2x4x4"]   = { Size = Vector(45.06, 45.06, 20.06), Offset = Vector(-0.79, 0, 10) },
	["Ammo2x4x6"]   = { Size = Vector(45.06, 68.06, 20.06), Offset = Vector(-0.79, 0, 10) },
	["Ammo2x4x8"]   = { Size = Vector(45.06, 90.06, 20.06), Offset = Vector(-0.79, 0, 10) },
	["Ammo3x4x1"]   = { Size = Vector(45.06, 8.06, 32.06), Offset = Vector(-0.64, 0, 16.25) },
	["Ammo3x4x2"]   = { Size = Vector(45.06, 20.06, 32.06), Offset = Vector(-0.2, 0.71, 16.26) },
	["Ammo3x4x4"]   = { Size = Vector(45.06, 45.06, 32.06), Offset = Vector(-0.79, 0, 16) },
	["Ammo3x4x6"]   = { Size = Vector(45.06, 68.06, 32.06), Offset = Vector(-0.79, 0, 16) },
	["Ammo3x4x8"]   = { Size = Vector(45.06, 90.06, 32.06), Offset = Vector(0.15, 0, 16) },
	["Ammo4x4x1"]   = { Size = Vector(45.06, 45.06, 11.51), Offset = Vector(0, 0, -0.06) },
	["Ammo4x4x2"]   = { Size = Vector(45.06, 20.06, 45.06), Offset = Vector(-0.14, 0.71, 22.5) },
	["Ammo4x4x4"]   = { Size = Vector(45.06, 45.06, 45.06), Offset = Vector(0.15, 0, 22.5) },
	["Ammo4x4x6"]   = { Size = Vector(45.06, 68.06, 45.06), Offset = Vector(0.15, 0.06, 22.5) },
	["Ammo4x4x8"]   = { Size = Vector(45.06, 90.06, 45.06), Offset = Vector(0.15, -0.01, 22.5) },
	["Ammo4x6x6"]   = { Size = Vector(67.56, 89.98, 44.99), Offset = Vector(0, 0, -0.07) },
	["Ammo4x6x8"]   = { Size = Vector(67.56, 67.35, 45), Offset = Vector(0, 0, -0.02) },
	["Ammo4x8x8"]   = { Size = Vector(90.21, 90.13, 45.19), Offset = Vector(0, 0, -0.15) },
}

---------------------------------------------------------------------------------------------------------------------
--  Old fuel tanks that are not boxes of "Tank_AxBxC" (those are worked out from their name in the fuel tank code)
--      Size is in inches. Shape is the ContainerShapeModels shape the tank becomes.
---------------------------------------------------------------------------------------------------------------------
Compatibility.FuelTanks = {
	["Fuel_Drum"]      = { Shape = "Cylinder", Size = Vector(28, 28, 45) }, -- Size of the oil drum model
	["Jerry_Can"]      = { Shape = "Box",      Size = Vector(20, 8, 30) },  -- Size of the gas can model
	-- These two were huge refuel-only tanks. Containers can be 96 inches at most, so they become the biggest tank there is.
	["Transport_Tank"] = { Shape = "Cylinder", Size = Vector(96, 96, 96) },
	["Storage_Tank"]   = { Shape = "Cylinder", Size = Vector(96, 96, 96) },
}
