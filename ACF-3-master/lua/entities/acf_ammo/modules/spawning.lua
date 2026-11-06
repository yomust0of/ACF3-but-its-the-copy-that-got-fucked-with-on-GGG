local ACF          = ACF
local Classes      = ACF.Classes
local Utilities    = ACF.Utilities
local WireIO       = Utilities.WireIO
local Notify       = Utilities.Notify
local WireLib      = WireLib
local Entities     = Classes.Entities
local AmmoTypes    = Classes.AmmoTypes
local Weapons      = Classes.Weapons
local ActiveCrates = ACF.AmmoCrates
local HookRun      = hook.Run
local Clamp        = math.Clamp
local Floor        = math.floor


local Inputs = {
	"Load (If set to a non-zero value, it'll allow weapons to use rounds from this ammo crate.)",
}

local Outputs = {
	"Loading (Whether or not weapons can use rounds from this crate.)",
	"Ammo (Rounds left in this ammo crate.)",
	"Entity (The ammo crate itself.) [ENTITY]",
}

do -- IO
	WireLib.AddInputAlias("Active", "Load")
	WireLib.AddOutputAlias("Munitions", "Ammo")

	ACF.AddInputAction("acf_ammo", "Load", function(Entity, Value)
		Entity.Load = tobool(Value)

		WireLib.TriggerOutput(Entity, "Loading", Entity:CanConsume() and 1 or 0)
	end)
end

do -- Spawn/Update/Remove
	local function VerifyData(Data)
		-- Crates from the very first ACF versions (before October 2020) were fixed models, and kept their weapon, ammo type and
		-- size under other names. This is what ACF itself did with them when it went to scalable crates, and what this copy
		-- lost on the way: without it these crates came out as 24x24x24 boxes of 50mm cannon AP.
		if isstring(Data.RoundId) and not isstring(Data.Weapon) then
			local OldCrate = ACF.Compatibility.AmmoCrates and ACF.Compatibility.AmmoCrates[Data.Id]

			Data.Weapon   = Data.RoundId
			Data.AmmoType = Data.RoundType or "AP"

			if OldCrate then -- The old crate model's size, and where its origin was compared to the middle of the box
				Data.Size   = Vector(OldCrate.Size)
				Data.Offset = Vector(OldCrate.Offset)
			else
				local X = ACF.CheckNumber(tonumber(Data.RoundData11), 24)
				local Y = ACF.CheckNumber(tonumber(Data.RoundData12), 24)
				local Z = ACF.CheckNumber(tonumber(Data.RoundData13), 24)

				Data.Size = Vector(X, Y, Z)
			end
		end

		if not isvector(Data.Size) then
			local X = ACF.CheckNumber(Data.AmmoSizeX or Data.CrateSizeX, 24)
			local Y = ACF.CheckNumber(Data.AmmoSizeY or Data.CrateSizeY, 24)
			local Z = ACF.CheckNumber(Data.AmmoSizeZ or Data.CrateSizeZ, 24)

			Data.Size = Vector(X, Y, Z)
		end

		do
			local Min  = ACF.AmmoMinSize
			local Size = Data.Size

			Size.x = Clamp(Size.x, Min, ACF.AmmoMaxLength)
			Size.y = Clamp(Size.y, Min, ACF.AmmoMaxWidth)
			Size.z = Clamp(Size.z, Min, ACF.AmmoMaxWidth)

			if not isstring(Data.Destiny) then
				Data.Destiny = ACF.FindWeaponrySource(Data.Weapon) or "Weapons"
			end

			local Source = Classes[Data.Destiny]
			local Class = Classes.GetGroup(Source, Data.Weapon)

			-- Compatibility layer for pre-scalable guns
			if not Class then
				local Compat = ACF.Compatibility[Data.Destiny]
				local AliasData = Compat and Compat.CheckGroupItem and Compat.CheckGroupItem(Data.Weapon)

				if AliasData then
					Data.Weapon = AliasData.ID
					Data.Caliber = AliasData.Caliber or Data.Caliber

					Class = Classes.GetGroup(Source, Data.Weapon)
				end
			end

			-- Scalable guns whose whole class is gone (smoothbore, autoloaded cannon): the class that replaced it, same caliber
			if not Class then
				local Compat   = ACF.Compatibility[Data.Destiny]
				local NewGroup = Compat and Compat.CheckGroup and Compat.CheckGroup(Data.Weapon)

				if NewGroup then
					Data.Weapon = NewGroup

					Class = Classes.GetGroup(Source, Data.Weapon)
				end
			end

			-- No class exists! A cannon, with the caliber the old gun had when that can be found (it used to always become 50mm)
			if not Class then
				local OldCaliber = tonumber(string.match(tostring(Data.Weapon), "^([%d%.]+)mm")) or tonumber(Data.Caliber)

				Class = Weapons.Get("C")
				Data.Destiny = "Weapons"
				Data.Weapon  = "C"
				Data.Caliber = OldCaliber or 50
			end

			do
				local Weapon = Source.GetItem(Class.ID, Data.Weapon)
				if Weapon then
					if Class.IsScalable then
						local Bounds  = Class.Caliber
						local Caliber = ACF.CheckNumber(Weapon.Caliber, Bounds.Base)
						Data.Weapon  = Class.ID
						Data.Caliber = Clamp(Caliber, Bounds.Min, Bounds.Max)
					else
						Data.Caliber = ACF.CheckNumber(Weapon.Caliber, 50)
					end
				end
			end

			-- A scalable class only has the calibers between its limits. Old guns that came from a bigger class (240mm howitzer) or
			-- have no caliber saved get the nearest one, the same as the gun itself does. Before this the crate kept the old caliber
			-- and could not be linked to the gun.
			if Class.IsScalable and Class.Caliber then
				local Bounds = Class.Caliber

				Data.Caliber = Clamp(ACF.CheckNumber(Data.Caliber, Bounds.Base), Bounds.Min, Bounds.Max)
			end

			local Ammo = AmmoTypes.Get(Data.AmmoType)

			if not Ammo or Ammo.Blacklist[Class.ID] then
				Data.AmmoType = Class.DefaultAmmo or "AP"

				Ammo = AmmoTypes.Get(Data.AmmoType)
			end

			if not isnumber(Data.AmmoStage) then
				Data.AmmoStage = 1
			end
			Data.AmmoStage = Clamp(Data.AmmoStage, ACF.AmmoStageMin, ACF.AmmoStageMax)

			do
				Ammo:VerifyData(Data, Class)

				if Class.VerifyData then
					Class.VerifyData(Data, Class, Ammo)
				end

				hook.Run("ACF_OnVerifyData", "acf_ammo", Data, Class, Ammo)
			end
		end
	end

	-- Crates that have no projectile counts yet (every dupe from before cartridge-scale crates, which only had a box size) get
	-- their counts worked out from that size. ACF's own way takes the biggest counts that still fit inside the old box, so the box
	-- always shrinks, by up to one round on every axis. This tries the counts around that one and takes the combination that gives
	-- a box closest to the old one, so old boxes keep about the size they had.
	-- Rounds packed in a honeycomb fit up to 1 / 0.866 times as many along the width as square ones, so on that axis the counts
	-- tried go from the square fit to a bit past the honeycomb fit. On every axis, a count lower than what fits is never closer.
	local function GetNearestCounts(Size, Class, Data, Bullet)
		local FitX      = ACF.GetProjectileCountsFromCrateSize(Size, Class, Data, Bullet)
		local RoundSize = ACF.GetRoundProperties(Class, Data, Bullet)
		local SquareY   = math.max(1, Floor(Size.y / RoundSize.y))
		local SquareZ   = math.max(1, Floor(Size.z / RoundSize.z))
		local BestX, BestY, BestZ, BestScore

		for X = FitX, FitX + 1 do
			for Y = SquareY, math.ceil(SquareY * 1.16) + 1 do
				for Z = SquareZ, SquareZ + 1 do
					local Box   = ACF.GetCrateSizeFromProjectileCounts(X, Y, Z, Class, Data, Bullet)
					local Score = math.abs(Box.x - Size.x) / Size.x + math.abs(Box.y - Size.y) / Size.y + math.abs(Box.z - Size.z) / Size.z

					if not BestScore or Score < BestScore then -- On a tie the smaller count stays
						BestX, BestY, BestZ, BestScore = X, Y, Z, Score
					end
				end
			end
		end

		return BestX, BestY, BestZ
	end

	local function UpdateCrateSize(Entity, Data, Class, _, Ammo)
		-- Convert current tool data once to get projectile geometry
		local Bullet = Ammo:ServerConvert(Data)

		-- Check if this is an ammo drum (cylinder shape)
		local IsDrum = Data.AmmoShape == "Cylinder"

		if IsDrum then
			local roundSize = ACF.GetRoundProperties(Class, Data, Bullet)
			local minRounds = ACF.GetMinRoundsPerRing()
			local maxRounds = ACF.GetMaxRoundsPerRing(roundSize, ACF.AmmoMaxWidth)
			local maxLayers = ACF.GetMaxDrumLayers(roundSize, ACF.AmmoMaxLength)

			local roundsPerRing = Clamp(Floor(tonumber(Data.CrateProjectilesX) or minRounds), minRounds, maxRounds)
			local numLayers     = Clamp(Floor(tonumber(Data.CrateProjectilesZ) or 2), 1, maxLayers)

			Data.CrateProjectilesX = roundsPerRing
			Data.CrateProjectilesZ = numLayers
			Data.CrateProjectilesY = 1
			Data.Size              = ACF.GetDrumDimensions(roundsPerRing, numLayers, roundSize)

			Entity:SetSize(Data.Size)

			return roundsPerRing * numLayers
		else
			-- Standard box crate logic
			local cx = tonumber(Data.CrateProjectilesX)
			local cy = tonumber(Data.CrateProjectilesY)
			local cz = tonumber(Data.CrateProjectilesZ)

			if not (cx and cy and cz) then
				cx, cy, cz = GetNearestCounts(Data.Size, Class, Data, Bullet)
			end

			cx = math.max(1, Floor(cx or 3))
			cy = math.max(1, Floor(cy or 3))
			cz = math.max(1, Floor(cz or 3))

			-- Clamp counts to maximum allowed dimensions
			local roundSize = ACF.GetRoundProperties(Class, Data, Bullet)
			local maxX, maxY, maxZ = ACF.GetMaxCounts(roundSize, ACF.AmmoMaxLength, ACF.AmmoMaxWidth, cy, cz)

			cx = math.min(cx, maxX)
			cy = math.min(cy, maxY)
			cz = math.min(cz, maxZ)

			-- Persist counts on both Data and Entity
			Data.CrateProjectilesX = cx
			Data.CrateProjectilesY = cy
			Data.CrateProjectilesZ = cz

			-- Recompute and apply consistent crate size from final counts
			Data.Size = ACF.GetCrateSizeFromProjectileCounts(cx, cy, cz, Class, Data, Bullet)

			Entity:SetSize(Data.Size)

			return cx * cy * cz
		end
	end

	local function CalculateExtraData(Entity, Data, Class, Weapon)
		local Rounds = Entity.Capacity
		local ExtraData = {}

		if Rounds > 0 then
			local BulletData = Entity.BulletData
			local Caliber = Entity.Caliber
			local BeltFed = ACF.GetWeaponValue("IsBelted", Caliber, Class, Weapon) or false
			local AmmoType = Entity.RoundData

			-- Get model info from ammo type's unified resolver
			local ModelInfo   = AmmoType:ResolveModel("Crate", Class, Weapon)
			local RoundModel  = ModelInfo.Model
			local RoundOffset = ModelInfo.Offset
			local Bodygroup   = ModelInfo.Bodygroup
			local NeedsRotation = ModelInfo.NeedsRotation

			-- Get dimensions from weapon's round definition
			local Round = Weapon and Weapon.Round or Class.Round
			local RoundLength, RoundDiameter = ACF.GetModelDimensions(Round)

			if not RoundLength then
				RoundDiameter = Caliber * ACF.AmmoCaseScale * 0.1
				RoundLength = BulletData.PropLength + BulletData.ProjLength
				RoundLength = RoundLength / ACF.InchToCm
				RoundDiameter = RoundDiameter / ACF.InchToCm
			end

			Entity.IsBelted = BeltFed
			ExtraData.AmmoStage = Data.AmmoStage
			ExtraData.IsRound = true
			ExtraData.Capacity = Entity.Capacity
			ExtraData.Enabled = true
			ExtraData.RoundSize = Vector(RoundLength, RoundDiameter, RoundDiameter)
			ExtraData.LocalAng = Angle(0, 0, 0)
			ExtraData.Spacing = 0
			ExtraData.MagSize = Entity.MagSize
			ExtraData.IsBelted = BeltFed
			ExtraData.RoundModel = RoundModel
			ExtraData.RoundOffset = RoundOffset
			ExtraData.Bodygroup = Bodygroup
			ExtraData.NeedsRotation = NeedsRotation

			-- Drum-specific data
			ExtraData.IsDrum = Entity.Shape == "Cylinder"
			if ExtraData.IsDrum then
				ExtraData.RoundsPerRing = Entity.CrateProjectilesX
				ExtraData.DrumLayers = Entity.CrateProjectilesZ
			end
		else
			ExtraData = { Enabled = false }
		end

		return ExtraData
	end

	local function NetworkAmmoData(Entity, Player)
		if IsValid(Entity) and Entity.ExtraData then
			net.Start("ACF_RequestAmmoData")
				net.WriteEntity(Entity)

				local ExtraData = Entity.ExtraData
				local Enabled = ExtraData.Enabled
				net.WriteBool(Enabled)

				if Enabled then
					-- Send stored projectile counts for client rendering
					-- These are validated at spawn time, no fallbacks needed
					local CountX = Entity.CrateProjectilesX
					local CountY = Entity.CrateProjectilesY
					local CountZ = Entity.CrateProjectilesZ

					net.WriteUInt(ExtraData.Capacity, 25)
					net.WriteBool(ExtraData.IsRound)
					net.WriteVector(ExtraData.RoundSize)
					net.WriteAngle(ExtraData.LocalAng)
					net.WriteVector(Vector(CountX, CountY, CountZ))
					net.WriteFloat(ExtraData.Spacing)
					net.WriteUInt(ExtraData.MagSize, 10)
					net.WriteUInt(ExtraData.AmmoStage, 5)
					net.WriteBool(ExtraData.IsBelted)
					net.WriteUInt(ExtraData.Bodygroup, 4) -- Bodygroup index (0-15)

					-- Send drum-specific data
					local IsDrum = ExtraData.IsDrum
					net.WriteBool(IsDrum)

					if IsDrum then
						net.WriteUInt(ExtraData.RoundsPerRing, 8)
						net.WriteUInt(ExtraData.DrumLayers, 8)
					end

					local HasModel = ExtraData.RoundModel ~= nil

					net.WriteBool(HasModel)

					if HasModel then
						net.WriteString(ExtraData.RoundModel)
						net.WriteVector(ExtraData.RoundOffset)
					end

					-- Send rotation flag (true = needs -90 degree rotation for cartridge models)
					net.WriteBool(ExtraData.NeedsRotation)
				end

			if Player then
				net.Send(Player)
			else
				net.Broadcast()
			end
		end
	end

	util.AddNetworkString("ACF_RequestAmmoData")

	net.Receive("ACF_RequestAmmoData", function(_, Player)
		local Entity = net.ReadEntity()

		NetworkAmmoData(Entity, Player)
	end)

	local function UpdateCrate(Entity, Data, Class, Weapon, Ammo)
		local Name, ShortName, WireName = Ammo:GetCrateName()
		local Scalable    = Class.IsScalable
		local Caliber     = Scalable and Data.Caliber or Weapon.Caliber
		local WeaponName  = Scalable and Caliber .. "mm " .. Class.Name or Weapon.Name
		local WeaponShort = Scalable and Caliber .. "mm" .. Class.ID or Weapon.ID
		local Rounds      = UpdateCrateSize(Entity, Data, Class, Weapon, Ammo)
		local OldAmmo     = Entity.RoundData

		if OldAmmo then
			if OldAmmo.OnLast then
				OldAmmo:OnLast(Entity)
			end

			HookRun("ACF_OnAmmoLast", OldAmmo, Entity)
		end

		Entity.RoundData  = Ammo
		Entity.BulletData = Ammo:ServerConvert(Data)
		Entity.BulletData.Crate = Entity:EntIndex()

		if Ammo.OnFirst then
			Ammo:OnFirst(Entity)
		end

		HookRun("ACF_OnAmmoFirst", Ammo, Entity, Data, Class, Weapon)

		Ammo:Network(Entity, Entity.BulletData)

		for _, V in ipairs(Entity.DataStore) do
			Entity[V] = Data[V]
		end

		Entity.Name       = Name or WeaponName .. " " .. Ammo.Name
		Entity.ShortName  = ShortName or WeaponShort .. " " .. Ammo.ID
		Entity.EntType    = "Ammo Crate"
		Entity.ClassData  = Class
		Entity.Shape      = Data.AmmoShape or "Box"
		Entity.Class      = Class.ID
		Entity.WeaponData = Weapon
		Entity.Caliber    = Caliber
		Entity.AmmoStage  = Data.AmmoStage
		Entity.UnitMass   = Entity.BulletData.CartMass

		WireIO.SetupInputs(Entity, Inputs, Data, Class, Weapon, Ammo)
		WireIO.SetupOutputs(Entity, Outputs, Data, Class, Weapon, Ammo)

			Entity.WireAmountName = "Ammo"

		Entity:SetNWString("WireName", "ACF " .. (WireName or WeaponName .. " Ammo Crate"))

		local Percentage = Entity.Capacity and Entity.Amount / Entity.Capacity or 1
		local MagSize    = ACF.GetWeaponValue("MagSize", Caliber, Class, Weapon) or 0

		Entity.Capacity = Rounds
		Entity.MagSize  = MagSize
		Entity:SetAmount(math.floor(Entity.Capacity * Percentage))
		Entity:SetNWInt("Ammo", Entity.Amount)

		Entity.ExtraData = CalculateExtraData(Entity, Data, Class, Weapon)

		NetworkAmmoData(Entity)

		if next(Entity.Weapons) then
			local Unloaded

			for K in pairs(Entity.Weapons) do
				if K.CurrentCrate == Entity then
					Unloaded = true

					K:Unload()
				end
			end

			if Unloaded then
				Notify.EntityWarning(Entity, "Weapons unloaded.", "Crate updated while weapons were loaded with its ammo")
			end
		end

		ACF.Activate(Entity, true)

		Entity.ACF.Model = Entity:GetModel()

		Entity:UpdateMass(true)
	end

	function ACF.MakeAmmo(Player, Pos, Ang, Data)
		if not Player:CheckLimit("_acf_ammo") then return end

		VerifyData(Data)

		local Source = Classes[Data.Destiny]
		local Class  = Classes.GetGroup(Source, Data.Weapon)
		local Weapon = Source.GetItem(Class.ID, Data.Weapon)
		local Ammo   = AmmoTypes.Get(Data.AmmoType)

		-- Select model based on ammo shape
		local Model
		if Data.AmmoShape == "Cylinder" then
			Model = ACF.ContainerShapeModels.Cylinder or "models/acf/core/s_fuel_cyl.mdl"
		else
			Model = "models/holograms/hq_rcube_thin.mdl"
		end

		local CanSpawn = HookRun("ACF_PreSpawnEntity", "acf_ammo", Player, Data, Class, Weapon, Ammo)

		if CanSpawn == false then return false end

		local Crate = ents.Create("acf_ammo")

		if not IsValid(Crate) then return end

		Player:AddCleanup("acf_ammo", Crate)
		Player:AddCount("_acf_ammo", Crate)

		Crate.ACF       = Crate.ACF or {}
		Crate.ACF.Model = Model

		Crate:SetMaterial("phoenix_storms/Future_vents")
		Crate:SetScaledModel(Model)
		Crate:SetAngles(Ang)
		Crate:SetPos(Pos)
		Crate:Spawn()

		Crate.IsExplosive = true
		Crate.Weapons     = {}
		Crate.DataStore	  = Entities.GetArguments("acf_ammo")

		UpdateCrate(Crate, Data, Class, Weapon, Ammo)

		if Class.OnSpawn then
			Class.OnSpawn(Crate, Data, Class, Weapon, Ammo)
		end

		HookRun("ACF_OnSpawnEntity", "acf_ammo", Crate, Data, Class, Weapon, Ammo)

		if Data.Offset then
			local Position = Crate:LocalToWorld(Data.Offset)

			ACF.SaveEntity(Crate)

			Crate:SetPos(Position)

			ACF.RestoreEntity(Crate)

			if Data.BuildDupeInfo then
				Data.BuildDupeInfo.PosReset = Position
			end
		end

		Crate:TriggerInput("Load", 1)

		ActiveCrates[Crate] = true

		return Crate
	end

	function ENT:Update(Data)
		VerifyData(Data)

		local Source     = Classes[Data.Destiny]
		local Class      = Classes.GetGroup(Source, Data.Weapon)
		local Weapon     = Source.GetItem(Class.ID, Data.Weapon)
		local Caliber    = Weapon and Weapon.Caliber or Data.Caliber
		local OldClass   = self.ClassData
		local OldWeapon  = self.Weapon
		local OldCaliber = self.Caliber
		local OldShape   = self.Shape
		local Ammo       = AmmoTypes.Get(Data.AmmoType)
		local Blacklist  = Ammo.Blacklist
		local Extra      = ""

		local CanUpdate, Reason = HookRun("ACF_PreUpdateEntity", "acf_ammo", self, Data, Class, Weapon, Ammo)
		if CanUpdate == false then return CanUpdate, Reason end

		if OldClass.OnLast then
			OldClass.OnLast(self, OldClass)
		end

		HookRun("ACF_OnEntityLast", "acf_ammo", self, OldClass)

		ACF.SaveEntity(self)

		-- Update model if shape changed
		local NewShape = Data.AmmoShape or "Box"
		if NewShape ~= OldShape then
			local Model
			if NewShape == "Cylinder" then
				Model = ACF.ContainerShapeModels.Cylinder or "models/acf/core/s_fuel_cyl.mdl"
			else
				Model = "models/holograms/hq_rcube_thin.mdl"
			end
			self.ACF.Model = Model
			self:SetScaledModel(Model)
		end

		UpdateCrate(self, Data, Class, Weapon, Ammo)

		ACF.RestoreEntity(self)

		if Class.OnUpdate then
			Class.OnUpdate(self, Data, Class, Weapon, Ammo)
		end

		HookRun("ACF_OnUpdateEntity", "acf_ammo", self, Data, Class, Weapon, Ammo)

		if Data.Weapon ~= OldWeapon or Caliber ~= OldCaliber or self.Unlinkable then
			for Entity in pairs(self.Weapons) do
				self:Unlink(Entity)
			end

			Extra = " All weapons have been unlinked."
		else
			local Count = 0
			for Entity in pairs(self.Weapons) do
				if Blacklist[Entity.Class] then
					self:Unlink(Entity)

					Entity:Unload()

					Count = Count + 1
				end
			end

			if Count > 0 then
				Extra = " Unlinked " .. Count .. " weapons from this crate."
			end
		end

		return true, "Crate updated successfully." .. Extra
	end

	function ENT:OnRemove()
		local Class = self.ClassData

		if Class.OnLast then
			Class.OnLast(self, Class)
		end

		HookRun("ACF_OnEntityLast", "acf_ammo", self, Class)

		ActiveCrates[self] = nil

		if self.RoundData and self.RoundData.OnLast then
			self.RoundData:OnLast(self)
		end

		if self.Damaged then
			timer.Remove("ACF Crate Cookoff " .. self:EntIndex())

			self:Detonate()
		end

		for K in pairs(self.Weapons) do
			self:Unlink(K)
		end

		if self.BaseClass.OnRemove then
			self.BaseClass.OnRemove(self)
		end
	end

	function ENT:OnResized(Size)
		local A = ACF.ContainerArmor * ACF.MmToInch
		local ExteriorVolume = Size.x * Size.y * Size.z
		local InteriorVolume = math.max(0, (Size.x - 2 * A) * (Size.y - 2 * A) * (Size.z - 2 * A))

		local Volume = ExteriorVolume - InteriorVolume
		local Mass   = Volume * 0.13

		self.EmptyMass = Mass
	end

	Entities.Register("acf_ammo", ACF.MakeAmmo, "Weapon", "Caliber", "AmmoType", "AmmoShape", "Size", "AmmoStage", "CrateProjectilesX", "CrateProjectilesY", "CrateProjectilesZ")

	ACF.RegisterLinkSource("acf_ammo", "Weapons")
end

do -- Overlay
	function ENT:ACF_UpdateOverlayState(State)
		local Tracer = self.BulletData.Tracer ~= 0 and "-T" or ""
		local AmmoType = self.BulletData.Type .. Tracer

		if next(self.Weapons) then
			if self:CanConsume() then
				State:AddSuccess("Providing Ammo")
			elseif self.Amount ~= 0 then
				State:AddWarning("Idle")
			else
				State:AddError("Empty")
			end
		else
			State:AddError("Not linked to a weapon!")
		end

		local CountX = self.CrateProjectilesX
		local CountY = self.CrateProjectilesY
		local CountZ = self.CrateProjectilesZ

		if AmmoInfo and AmmoInfo ~= "" then
			AmmoInfo = AmmoInfo
		end

		State:AddDivider()
		State:AddSize("Storage (in projectiles)", CountX, CountY, CountZ)
		State:AddKeyValue("Ammo Type", AmmoType)
		State:AddProgressBar("Contents", self.Amount, self.Capacity)

		local BulletData = self.BulletData
		local Projectile = math.Round(BulletData.ProjMass, 2)
		local Cartridge  = math.Round(BulletData.CartMass, 2)
		State:AddHeader("Bullet Info", 2)

		local Caliber = math.Round(BulletData.Caliber * 10, 2)
		local Length  = math.Round(BulletData.ProjLength + BulletData.PropLength, 2)
		if self.IsMissileAmmo then
			local Class    	= Classes.GetGroup(Classes.Missiles, BulletData.Id)
			local Weapon    = Class and Class.Lookup[BulletData.Id]
			local Round 	= Weapon and Weapon.Round
			Length = Round.ActualLength * ACF.InchToCm
		end
		State:AddKeyValue("Shell dimensions", Caliber .. "mm x " .. Length .. "cm")

		local IdealReloadTime = math.Round(ACF.CalcReloadTime(Caliber, self.ClassData, self.Weapon, self.BulletData, self.Override), 2)
		local IdealMagReloadTime = math.Round(ACF.CalcReloadTimeMag(self.Caliber, self.ClassData, self.Weapon, self.BulletData, {MagSize = self.Amount}), 2)
		State:AddKeyValue("Ideal Reload Time", IdealReloadTime .. " s")
		State:AddKeyValue("Ideal Mag Reload Time", IdealMagReloadTime .. " s")

		State:AddNumber("Cartridge Mass", Cartridge, " kg", 2)
		State:AddNumber("Projectile Mass", Projectile, " kg", 2)

		State:AddHeader("Ammo Info", 2)
		self.RoundData:UpdateCrateOverlay(self.BulletData, State)
		ACF.AddAdditionalOverlays(self, State)
	end
end