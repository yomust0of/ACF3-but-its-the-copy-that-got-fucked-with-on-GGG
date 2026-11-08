AddCSLuaFile("tuning.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

-- VTOL jet thruster. Built the way ACF's waterjet is (a gearbox "effector": the gearbox asks it for torque, then hands it the
-- torque the engine could really give), with these differences:
--   * it works in air and in water (30 percent weaker in water, see tuning.lua), where the waterjet only works in water
--   * its thrust comes from the power the engine really delivered to it, so a damaged engine, a heavy contraption (mass ratio),
--     a damaged gearbox and a weak engine all lower the thrust by themselves
--   * you tell it how much thrust you want (a number like the GMod thruster tool's Force), it never goes over its own maximum
--   * it loads the engine like a propeller (see tuning.lua), harder the more thrust it is asked for
-- Every number is in tuning.lua.

local ACF         = ACF
local Mobility    = ACF.Mobility
local MobilityObj = Mobility.Objects
local Sounds      = ACF.Utilities.Sounds
local Clock       = ACF.Utilities.Clock
local Tune        = ACF.ThrustNozzle

local ActiveTime = 0.15 -- Seconds without being driven before the sound stops and the thrust reads zero
local NWRPM      = "ACF_ThrustNozzleRPM"

local function GenerateLinkTable(Entity, Target)
	local InPos = Target.In and Target.In.Pos or Vector()
	local InPosWorld = Target:LocalToWorld(InPos)
	local OutPos, Side

	local Plane
	if Entity:WorldToLocal(InPosWorld).y < 0 then
		Plane = Entity.OutL
		OutPos = Entity.OutL.Pos
		Side = 0
	else
		Plane = Entity.OutR
		OutPos = Entity.OutR.Pos
		Side = 1
	end

	local OutPosWorld = Entity:LocalToWorld(OutPos)
	local Excessive, Angle = ACF.IsDriveshaftAngleExcessive(Target, Target.In, Entity, Plane)
	if Excessive then return nil, Angle end

	local Link	= MobilityObj.Link(Entity, Target)

	Link:SetOrigin(OutPos)
	Link:SetTargetPos(InPos)
	Link:SetAxis(Target.In and Plane.Dir or Target:GetPhysicsObject():WorldToLocalVector(Entity:GetRight()))
	Link.OutDirection = Plane.Dir
	Link.Side = Side
	Link.RopeLen = (OutPosWorld - InPosWorld):Length()

	return Link, Angle
end

function ENT.ACF_OnVerifyClientData(ClientData)
	-- The diameter is already limited by the user variable (tuning.lua). The model is ModelDiameter wide at scale 1.
	local Diameter = math.Clamp(tonumber(ClientData.NozzleDiameter) or Tune.DiameterDefault, Tune.DiameterMin, Tune.DiameterMax)
	local Scale    = Diameter / Tune.ModelDiameter

	ClientData.NozzleDiameter = Diameter
	ClientData.Size           = Vector(Scale, Scale, Scale)

	-- What was typed in the menu: no capitals, no spaces round it, not absurdly long. Empty means silent.
	ClientData.NozzleSoundPath = string.sub(string.Trim(tostring(ClientData.NozzleSoundPath or Tune.SoundDefault)):lower(), 1, 128)
end

function ENT:ACF_PreSpawn()
	self:SetScaledModel("models/maxofs2d/hover_propeller.mdl")
end

function ENT:ACF_PostUpdateEntityData(ClientData)
	self:SetScale(ClientData.Size)

	local Diameter = ClientData.NozzleDiameter

	self.Diameter = Diameter
	self.MaxThrust, self.ThrustPerKW, self.RatedPower, self.Efficiency, self.SizeFraction = Tune.GetStats(Diameter)

	-- Torque the thruster asks for at full thrust, per RPM squared (worked out in RefreshLoad, which knows the engine)
	self.LoadCoef = self.RatedPower * 9548.8 / (Tune.FallbackRefRPM ^ 3)

	-- Things that must survive the thruster being updated from the menu (and not start from zero then)
	self.Gearboxes     = self.Gearboxes or {}
	self.GearboxCount  = self.GearboxCount or 0
	self.WantedThrust  = self.WantedThrust or math.huge -- Until something is wired to Thrust it asks for its maximum
	self.GoalThrust    = math.min(self.GoalThrust or 0, self.MaxThrust)
	self.SlewRate      = self.SlewRate or 0
	self.VecPitch      = self.VecPitch or 0
	self.VecYaw        = self.VecYaw or 0
	self.Thrust        = self.Thrust or 0
	self.TickThrust    = 0
	self.ShaftRPM      = self.ShaftRPM or 0
	self.NetRPM        = 0

	self:UpdateVector()
end

ACF.RegisterClassLink("acf_thrustnozzle", "acf_gearbox", function(This, Gearbox)
	if Gearbox.Effectors[This] then return false, "This thruster is already connected to this gearbox!" end

	local Link, DriveshaftAngle = GenerateLinkTable(Gearbox, This)

	if not Link then return false, "Cannot link due to excessive driveshaft angle! (" .. math.Round(DriveshaftAngle) .. " deg)" end

	Gearbox.Effectors[This] = Link
	This.Gearboxes[Gearbox] = Link
	This.GearboxCount = This.GearboxCount + 1

	Gearbox:InvalidateClientInfo()

	return true, "Thruster linked successfully."
end)

ACF.RegisterClassUnlink("acf_thrustnozzle", "acf_gearbox", function(This, Gearbox)
	if not Gearbox.Effectors[This] then return false, "This thruster is not connected to this gearbox!" end

	Gearbox.Effectors[This] = nil
	This.Gearboxes[Gearbox] = nil
	This.GearboxCount = math.max(This.GearboxCount - 1, 0)

	return true, "Thruster unlinked successfully."
end)

ACF.RegisterLinkSource("acf_thrustnozzle", "Gearboxes")

-- Unlink from the gearboxes when removed, so a gearbox is not left holding a removed thruster
function ENT:OnRemove()
	for Gearbox in pairs(self.Gearboxes or {}) do
		self:Unlink(Gearbox)
	end
end

---------------------------------------------------------------------------------------------------------------
-- Wire inputs
---------------------------------------------------------------------------------------------------------------
ACF.AddInputAction("acf_thrustnozzle", "Thrust", function(Entity, Value)
	Entity.WantedThrust = math.max(tonumber(Value) or 0, 0)
end)

ACF.AddInputAction("acf_thrustnozzle", "Slew", function(Entity, Value)
	Entity.SlewRate = math.max(tonumber(Value) or 0, 0)
end)

ACF.AddInputAction("acf_thrustnozzle", "Pitch", function(Entity, Value)
	Entity.VecPitch = tonumber(Value) or 0
	Entity:UpdateVector()
end)

ACF.AddInputAction("acf_thrustnozzle", "Yaw", function(Entity, Value)
	Entity.VecYaw = tonumber(Value) or 0
	Entity:UpdateVector()
end)

-- Works out the two angles that tilt the push away from the nozzle's axis, the same two angles the waterjet uses (Pitch as the pitch
-- angle, Yaw as the roll angle). Together they are limited to MaxVectorAngle (pitch and yaw each scaled down the same amount).
-- UNCONFIRMED in game: which way is "forward" for the plus sign depends on how the model is built.
function ENT:UpdateVector()
	local Max   = Tune.MaxVectorAngle
	local Pitch = self.VecPitch
	local Yaw   = self.VecYaw
	local Total = math.sqrt(Pitch * Pitch + Yaw * Yaw)

	if Total > Max then
		Pitch = Pitch * Max / Total
		Yaw   = Yaw * Max / Total
	end

	self.TiltAng = Angle(Pitch, 0, Yaw)
end

---------------------------------------------------------------------------------------------------------------
-- Thrust the thruster is trying to reach: the wired Thrust, held at the maximum, reached at the Slew rate
---------------------------------------------------------------------------------------------------------------
local function UpdateGoal(SelfTbl)
	local Now  = Clock.CurTime
	local Last = SelfTbl.LastSlew

	if Last == Now then return end -- Asked twice in the same tick

	SelfTbl.LastSlew = Now

	local Max    = SelfTbl.MaxThrust
	local Target = math.min(SelfTbl.WantedThrust, Max)
	local Rate   = SelfTbl.SlewRate

	if Rate <= 0 then -- 0 means instantly
		SelfTbl.GoalThrust = Target
		return
	end

	-- Real elapsed time, so it is the same at any tick rate and nothing is lost between two calls. (The very first call has no
	-- "last time" yet, so it moves nothing: a new thruster starts from zero and climbs at the Slew rate.)
	local Step = Rate * (Now - (Last or Now))
	local Goal = math.min(SelfTbl.GoalThrust, Max)

	if Goal < Target then
		Goal = math.min(Goal + Step, Target)
	else
		Goal = math.max(Goal - Step, Target)
	end

	SelfTbl.GoalThrust = Goal
end

-- The engine RPM scale the load is sized by. A healthy engine of the right size settles at BogRefFraction of its redline when the
-- thruster is asked for its maximum. The shaft RPM is the engine RPM divided by the gearbox ratio, so that is divided here too,
-- which makes the load on the engine the same whatever the gearbox is set to.
local function RefreshLoad(SelfTbl)
	local Ref = 0

	for Gearbox in pairs(SelfTbl.Gearboxes) do
		if IsValid(Gearbox) and Gearbox.Engines then
			local Ratio = math.abs(Gearbox.GearRatio or 0)

			if Ratio > 0 then
				for Engine in pairs(Gearbox.Engines) do
					if IsValid(Engine) and Engine.LimitRPM then
						Ref = math.max(Ref, Engine.LimitRPM * Tune.BogRefFraction / Ratio)
					end
				end
			end
		end
	end

	if Ref <= 0 then Ref = Tune.FallbackRefRPM end

	SelfTbl.LoadCoef = SelfTbl.RatedPower * 9548.8 / (Ref * Ref * Ref)
end

local function GetHealthRatio(SelfTbl)
	local Data = SelfTbl.ACF

	if not Data or not Data.MaxHealth or Data.MaxHealth <= 0 then return 1 end

	return math.Clamp(Data.Health / Data.MaxHealth, 0, 1)
end

---------------------------------------------------------------------------------------------------------------
-- Sound
---------------------------------------------------------------------------------------------------------------
function ENT:UpdateSound(SelfTbl)
	SelfTbl = SelfTbl or self:GetTable()

	-- Only while it is being driven. The ACF sound tool also calls this when it changes the sound of an idle thruster.
	if not SelfTbl.Sound and Clock.CurTime - (SelfTbl.LastAct or -1) > ActiveTime then return end

	local Path = self:ACF_GetUserVar("NozzleSoundPath")

	if SelfTbl.Sound and SelfTbl.PlayingPath ~= Path then
		self:DestroySound()
	end

	if Path == "" then return end

	-- Higher pitch at low thrust and lower at heavy thrust, lower again for a wider nozzle; quieter at low thrust
	local Fraction = SelfTbl.MaxThrust > 0 and math.Clamp(SelfTbl.Thrust / SelfTbl.MaxThrust, 0, 1) or 0
	local ByThrust = Lerp(Fraction, Tune.SoundPitchLowThrust, Tune.SoundPitchHighThrust)
	local BySize   = Lerp(SelfTbl.SizeFraction, Tune.SoundPitchSmallNozzle, Tune.SoundPitchLargeNozzle)
	local Pitch    = math.Clamp(math.floor(100 * self:ACF_GetUserVar("NozzleSoundPitch") * ByThrust * BySize + 0.5), 1, 255)
	local Volume   = math.floor(self:ACF_GetUserVar("NozzleSoundVolume") * Lerp(Fraction, Tune.SoundVolumeLowThrust, 1) * 100 + 0.5) / 100

	if SelfTbl.Sound then
		-- Only tell the clients when it changed, and not more often than ACF's own limit lets a message through (0.05 s)
		local Now = CurTime()

		if (Pitch ~= SelfTbl.SentPitch or Volume ~= SelfTbl.SentVolume) and Now >= (SelfTbl.NextSoundSend or 0) then
			Sounds.SendAdjustableSound(self, false, Pitch, Volume)

			SelfTbl.SentPitch     = Pitch
			SelfTbl.SentVolume    = Volume
			SelfTbl.NextSoundSend = Now + 0.1
		end
	else
		Sounds.CreateAdjustableSound(self, Path, Pitch, Volume)

		SelfTbl.Sound         = true
		SelfTbl.PlayingPath   = Path
		SelfTbl.SentPitch     = Pitch
		SelfTbl.SentVolume    = Volume
		SelfTbl.NextSoundSend = CurTime() + 0.1
	end
end

function ENT:DestroySound()
	Sounds.SendAdjustableSound(self, true)

	self.PlayingPath = nil
	self.Sound       = nil
end

---------------------------------------------------------------------------------------------------------------
-- The gearbox part
---------------------------------------------------------------------------------------------------------------

-- Calculates the torque the thruster asks for. Like a propeller: grows with the square of the RPM, and with how much thrust is wanted
-- (as a fraction of the maximum). Several gearboxes on one thruster share the request.
function ENT:Calc(InputRPM)
	local SelfTbl = self:GetTable()

	if not IsValid(SelfTbl.Ancestor) then return 0 end

	UpdateGoal(SelfTbl)

	SelfTbl.ShaftRPM = InputRPM

	local Fraction = SelfTbl.GoalThrust / SelfTbl.MaxThrust

	return Tune.BogScale * Fraction * SelfTbl.LoadCoef * InputRPM * InputRPM / math.max(SelfTbl.GearboxCount, 1)
end

-- Applies the thrust. Torque is what the engine really delivered to the thruster (already lowered by the engine's damage and
-- RPM, the mass ratio and the gearbox's losses), so the power it stands for is all the thrust is made of.
function ENT:Act(Torque, DeltaTime)
	local SelfTbl = self:GetTable()
	local Now     = Clock.CurTime
	local RPM     = math.abs(SelfTbl.ShaftRPM)
	local Rounded = math.floor(RPM / 50 + 0.5) * 50

	SelfTbl.LastAct = Now

	-- Blade speed for the clients; sent only when it changes by a step of 50
	if SelfTbl.NetRPM ~= Rounded then
		SelfTbl.NetRPM = Rounded

		self:SetNW2Float(NWRPM, Rounded)
	end

	if SelfTbl.TickTime ~= Now then
		SelfTbl.TickTime   = Now
		SelfTbl.TickThrust = 0
	end

	local Phys = SelfTbl.AncestorPhys

	if IsValid(SelfTbl.Ancestor) and IsValid(Phys) then
		local Thrust = math.abs(Torque) * RPM / 9548.8 * SelfTbl.ThrustPerKW * GetHealthRatio(SelfTbl) -- kW times thrust per kW

		if SelfTbl.InWater then Thrust = Thrust * Tune.WaterMultiplier end

		-- Never more than was asked for, even when two gearboxes feed it in the same tick
		Thrust = math.min(Thrust, SelfTbl.GoalThrust - SelfTbl.TickThrust)

		if Thrust > 0 then
			SelfTbl.TickThrust = SelfTbl.TickThrust + Thrust

			-- A push is an impulse: the force (ForceFactor times the thrust number) for as long as this tick covers
			local Impulse = Tune.ForceFactor * Thrust * math.min(DeltaTime or 0, Tune.MaxStep)

			-- Which way it pushes: exactly how the waterjet does it. The thruster's own up axis, tilted by the two angles, in world space
			-- (ThrustDirection -1 is the waterjet's minus sign).
			local Dir = self:LocalToWorldAngles(SelfTbl.TiltAng):Up() * Tune.ThrustDirection

			Phys:ApplyForceOffset(Dir * Impulse, self:GetPos())
		end
	end

	SelfTbl.Thrust = SelfTbl.TickThrust

	self:UpdateSound(SelfTbl)
end

function ENT:Think()
	local SelfTbl = self:GetTable()
	local Now     = Clock.CurTime

	-- Nothing has driven it for a moment (engine off, throttle at zero, ...)
	if Now - (SelfTbl.LastAct or -1) > ActiveTime then
		if SelfTbl.Sound then self:DestroySound() end

		SelfTbl.Thrust = 0

		if SelfTbl.NetRPM ~= 0 then
			SelfTbl.NetRPM = 0

			self:SetNW2Float(NWRPM, 0)
		end
	end

	SelfTbl.InWater = bit.band(util.PointContents(self:GetPos()), CONTENTS_WATER) == CONTENTS_WATER

	-- Cache ancestor
	local Ancestor = self:GetAncestor()

	if IsValid(Ancestor) then
		SelfTbl.Ancestor = Ancestor
		SelfTbl.AncestorPhys = Ancestor:GetPhysicsObject()
	end

	UpdateGoal(SelfTbl)
	RefreshLoad(SelfTbl)

	self:UpdateOverlay()
	self:NextThink(CurTime() + 0.1)

	return true
end

function ENT:ACF_UpdateOverlayState(State)
	local SelfTbl = self:GetTable()

	if not SelfTbl.MaxThrust then return end

	local Medium = SelfTbl.InWater and Tune.WaterMultiplier or 1

	State:AddKeyValue("Max Thrust", ("%d"):format(math.Round(SelfTbl.MaxThrust)))
	State:AddKeyValue("Engine Power For Max Thrust", ("%d kW"):format(math.ceil(SelfTbl.RatedPower / Medium)))
	State:AddKeyValue("Wanted Thrust", ("%d"):format(math.Round(math.min(SelfTbl.WantedThrust, SelfTbl.MaxThrust))))
	State:AddKeyValue("Thrust Now", ("%d"):format(math.Round(SelfTbl.Thrust or 0)))
	State:AddKeyValue("Diameter", ("%s in"):format(math.Round(SelfTbl.Diameter, 1)))
	State:AddKeyValue("Efficiency", ("%d%%%s"):format(math.Round(SelfTbl.Efficiency * Medium * 100), SelfTbl.InWater and " (in water)" or ""))
end

ACF.Classes.Entities.Register()
