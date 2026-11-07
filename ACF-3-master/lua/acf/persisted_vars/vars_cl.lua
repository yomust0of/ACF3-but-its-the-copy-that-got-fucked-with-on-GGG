-- Variables that should be persisted between servers

-- Settings
ACF.PersistClientData("Volume", 0.5)
ACF.PersistClientData("AmmoSupplyColor", Color(255, 255, 0, 10))
ACF.PersistClientData("FuelSupplyColor", Color(76, 201, 250, 10))
ACF.PersistClientData("DualClutch", false)

-- Crate projectile counts
ACF.PersistClientData("CrateProjectilesX", 3)
ACF.PersistClientData("CrateProjectilesY", 3)
ACF.PersistClientData("CrateProjectilesZ", 3)

-- Fuel tank size and shape
ACF.PersistClientData("FuelSizeX", 24)
ACF.PersistClientData("FuelSizeY", 24)
ACF.PersistClientData("FuelSizeZ", 24)
ACF.PersistClientData("FuelShape", "Box")

-- Supply crate size and shape
ACF.PersistClientData("SupplySizeX", 24)
ACF.PersistClientData("SupplySizeY", 24)
ACF.PersistClientData("SupplySizeZ", 24)
ACF.PersistClientData("SupplyShape", "Box")

-- Gearbox. Legacy ratios (driven / driver, 0 to 1) are the default here, stock ACF starts with the realistic ones (false)
ACF.PersistClientData("GearboxLegacyRatio", true)

-- VTOL jet thruster: the sound file typed in its menu (same default as SoundDefault in lua\entities\acf_thrustnozzle\tuning.lua)
ACF.PersistClientData("NozzleSoundPath", "ambient/machines/spin_loop.wav")