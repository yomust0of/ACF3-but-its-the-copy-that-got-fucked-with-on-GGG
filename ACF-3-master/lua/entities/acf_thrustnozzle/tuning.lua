-- VTOL JET THRUSTER (acf_thrustnozzle): TUNING
--
-- Every number that decides how the thruster behaves is in this one file. Change a number here, restart the game (or the server)
-- and that is all. Nothing else needs touching. The entity, the menu and the overlay all read from this table.
--
-- Thrust "numbers" are in the same scheme as the GMod thruster tool's Force box (see ForceFactor): the number you wire into the
-- Thrust input is that kind of number, and the overlay (the popup you get when you look at the thruster) shows the most the
-- thruster can ever give, in the same scheme.
--
-- Nothing in here has been run in Garry's Mod. The numbers marked PLACEHOLDER are my starting guesses, for you to change.

local Tune = ACF.ThrustNozzle or {}
ACF.ThrustNozzle = Tune

---------------------------------------------------------------------------------------------------------------
-- SIZE: the diameter slider in the menu, in inches (source units)
---------------------------------------------------------------------------------------------------------------
Tune.DiameterMin     = 6     -- Smallest nozzle you can make. Gets EfficiencySmall and MassSmall
Tune.DiameterMax     = 40    -- Largest nozzle you can make. Gets EfficiencyLarge and MassLarge
Tune.DiameterDefault = 30    -- What the slider starts on
Tune.ModelDiameter   = 17.66 -- How wide hover_propeller.mdl really is at scale 1 (measured in game), so a nozzle set to 10 is 10 wide. Only used to scale the model

-- The nozzle's weight, in kg: MassSmall for the smallest nozzle and MassLarge for the biggest, and in between it grows the way
-- the thrust does (about with the square of the diameter): a straight line on a log-log graph between the two.
Tune.MassSmall = 30
Tune.MassLarge = 1000

Tune.EntityLimit     = 50    -- How many a player can have (sbox_max_acf_thrustnozzle; a server can still change that console variable)

---------------------------------------------------------------------------------------------------------------
-- THRUST
---------------------------------------------------------------------------------------------------------------
-- How hard the push is for a thrust number N, in kg * inch / s^2 per unit of N. A sandbox thruster's push depends on its model (a
-- bigger model pushes harder for the same Force; measured with the calibration scripts: 1198.75 for a 48 inch cube, 308 for
-- thruster.mdl, 57 for jaanus/thruster_flat.mdl). This one number decides how hard every nozzle pushes, whatever its size.
-- 1198.75 (the 48 inch cube's push) is the owner's choice, set by feel in game; it is not tested against and is not changed by anything else.
Tune.ForceFactor = 1198.75

-- The yardstick for how thrust and power scale: a nozzle ReferenceDiameter wide, running at 100 percent efficiency, gives
-- ThrustCeiling from CeilingPowerKW of engine power. No nozzle that wide can be built any more (the biggest is DiameterMax); these
-- three numbers only fix the scale, so changing DiameterMax or the efficiency does not move them. A nozzle of any diameter gets
-- ThrustCeiling x (diameter / ReferenceDiameter)^2, its share of the area: twice as wide = four times the thrust.
Tune.ReferenceDiameter = 60
Tune.ThrustCeiling     = 75000

-- 1082 kW is the strongest engine in ACF (the Large Gas Turbine; the next ones are 1021, 625, 522 and 261 kW, all counted the way
-- ACF counts power for the engine menu's graph, without the server's torque multiplier). Thrust per kW at 100 percent efficiency
-- is ThrustCeiling / CeilingPowerKW = 69.3.
Tune.CeilingPowerKW = 1082

-- Overall thrust per engine power, as a plain multiplier: 2 gives every nozzle twice the thrust for the same engine power
-- (and, because the nozzle never gives more than its own maximum, it also means the engine has to work less hard to reach it).
-- 0.29 is the owner's choice: it felt right for a 10 inch nozzle on a small gas turbine under a 2500 kg baseplate. At this value the
-- 40 inch nozzle (33333 thrust) needs about 2210 kW, two Large Gas Turbines.
Tune.ThrustPerPowerScale = 0.29

-- Small nozzles waste more of the engine's power than big ones: the thrust you get per kW is multiplied by this, 0.5 for the
-- smallest nozzle (DiameterMin) up to 0.75 for the largest (DiameterMax), straight line in between. At 0.75 the biggest nozzle
-- needs two thirds of the power of the smallest for the same thrust. PLACEHOLDER.
Tune.EfficiencySmall = 0.5
Tune.EfficiencyLarge = 0.75

-- Under water the same power gives this much of the thrust: 0.7 = 30 percent less. It still works.
Tune.WaterMultiplier = 0.7

---------------------------------------------------------------------------------------------------------------
-- HOW HARD IT LOADS THE ENGINE
---------------------------------------------------------------------------------------------------------------
-- The thruster holds back the engine like a propeller: the harder it is asked to push, the more it drags, and the drag grows
-- with the square of the RPM. That kind of load makes the engine slow down until it balances and settle there. (A load that
-- always asks for the same power would stall the engine to idle instead; I tried that on a model of the turbine.)
--
-- BogRefFraction is where on the RPM scale a healthy engine of the right size settles at full thrust, as a fraction of its
-- redline: 0.55 on the Large Gas Turbine means 55 percent of 13000 RPM. A weaker engine than the nozzle needs settles lower
-- (and thrusts less, since it delivers less power); a stronger one settles higher. PLACEHOLDER, to be checked in game.
-- On my stand-in model the turbines and electric motors reach their full power at this setting. Piston engines (petrol and diesel)
-- do not: their power peaks high in their RPM range, so under a load that rises with the RPM they settle at about 40 percent of
-- redline and give anywhere from about a third to four fifths of the thrust a turbine of the same peak power gives.
Tune.BogRefFraction = 0.55

-- Overall scale of that drag. 1 = as described above. 1.5 makes every thruster drag the engine 50 percent harder at the same
-- thrust, so the engine settles lower (about 48 percent of redline instead of 55 on the Large Gas Turbine).
Tune.BogScale = 1

-- RPM at the thruster's shaft to size the drag by when no engine can be found behind it (for example a gearbox that is fed by
-- another gearbox). Normally the engine's redline and the gearbox's current ratio are used and this is ignored.
Tune.FallbackRefRPM = 7000

---------------------------------------------------------------------------------------------------------------
-- VECTORING AND THRUST SLEW
---------------------------------------------------------------------------------------------------------------
Tune.MaxVectorAngle = 30     -- Most the Pitch and Yaw angles can add up to, in degrees (if they would pass it, both are scaled down together)

-- Which way the push goes along the model's up axis. -1 = the same as ACF's waterjet (pushes along the model's down). If your
-- thruster pushes the wrong way when you place it, change this to 1.
Tune.ThrustDirection = -1

-- The most time one tick of push can cover. Normally one tick; this only matters after a freeze of the server or just after the
-- engine starts, so the first push cannot be a huge one. In seconds.
Tune.MaxStep = 0.1

---------------------------------------------------------------------------------------------------------------
-- SOUND (the pitch and volume you set with ACF's sound tool are the base; these change them as the thrust changes)
---------------------------------------------------------------------------------------------------------------
Tune.SoundDefault = "ambient/machines/spin_loop.wav"  -- What a new thruster plays (the same file ACF's waterjet uses)

-- Pitch multiplier from thrust: higher pitch at low thrust, lower at heavy thrust. PLACEHOLDER.
Tune.SoundPitchLowThrust  = 1.2
Tune.SoundPitchHighThrust = 0.85

-- Pitch multiplier from diameter: a small nozzle whines high, a big one rumbles low. Wider spread than the thrust one, because
-- you asked for the diameter to matter more. PLACEHOLDER.
Tune.SoundPitchSmallNozzle = 1.5
Tune.SoundPitchLargeNozzle = 0.6

-- Volume from thrust: this fraction of the sound tool's volume at zero thrust, rising to the full volume at full thrust.
Tune.SoundVolumeLowThrust = 0.25

---------------------------------------------------------------------------------------------------------------
-- The same numbers worked out for one diameter, so the entity, the menu and the overlay never disagree.
-- Returns: max thrust, thrust per kW (efficiency included), engine kW needed for max thrust, efficiency, size fraction (0 smallest, 1 biggest)
---------------------------------------------------------------------------------------------------------------
function Tune.GetStats(Diameter)
	local Span       = Tune.DiameterMax - Tune.DiameterMin
	local Size       = Span > 0 and math.Clamp((Diameter - Tune.DiameterMin) / Span, 0, 1) or 1
	local Efficiency = Tune.EfficiencySmall + (Tune.EfficiencyLarge - Tune.EfficiencySmall) * Size
	local MaxThrust  = Tune.ThrustCeiling * (Diameter / Tune.ReferenceDiameter) ^ 2
	local PerKW      = Tune.ThrustCeiling / Tune.CeilingPowerKW * Tune.ThrustPerPowerScale * Efficiency

	return MaxThrust, PerKW, MaxThrust / PerKW, Efficiency, Size
end

---------------------------------------------------------------------------------------------------------------
-- The nozzle's weight in kg for one diameter (see MassSmall / MassLarge above)
---------------------------------------------------------------------------------------------------------------
function Tune.GetMass(Diameter)
	local Min, Max = Tune.DiameterMin, Tune.DiameterMax

	if Max <= Min or Min <= 0 then return Tune.MassLarge end

	local Along = math.log(math.Clamp(Diameter, Min, Max) / Min) / math.log(Max / Min) -- 0 at the smallest, 1 at the biggest

	return math.Round(Tune.MassSmall * (Tune.MassLarge / Tune.MassSmall) ^ Along, 1)
end
