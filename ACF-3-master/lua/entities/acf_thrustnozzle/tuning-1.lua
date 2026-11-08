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
Tune.DiameterMin     = 10    -- PLACEHOLDER. Smallest nozzle you can make
Tune.DiameterMax     = 60    -- PLACEHOLDER. Largest nozzle you can make. This one gets the full ThrustCeiling below
Tune.DiameterDefault = 30    -- What the slider starts on
Tune.ModelDiameter   = 10    -- How wide hover_propeller.mdl is at scale 1 (ACF's waterjet says 10). Only used to scale the model

Tune.EntityLimit     = 50    -- How many a player can have (sbox_max_acf_thrustnozzle; a server can still change that console variable)

---------------------------------------------------------------------------------------------------------------
-- THRUST
---------------------------------------------------------------------------------------------------------------
-- How hard GMod pushes for a thrust number N. GMod's thruster tool pushes with 50 x N, in kg * inch / s^2, and so does this.
-- UNCONFIRMED until the calibration script (thrust_calibration.lua) has been run in game. If it prints a "force factor" other
-- than 50, put that number here.
Tune.ForceFactor = 1198.75

-- The biggest thrust a nozzle can ever give, for the biggest nozzle (DiameterMax). A smaller nozzle gets this times (its
-- diameter / DiameterMax)^2, which is its share of the area: twice as wide = four times the thrust.
Tune.ThrustCeiling = 75000

-- How much engine power makes ThrustCeiling at the biggest nozzle with nothing wasted. 1082 kW is the strongest engine in ACF
-- (the Large Gas Turbine; the next ones are 1021, 625, 522 and 261 kW, all counted the way ACF counts power for the engine
-- menu's graph, without the server's torque multiplier). Thrust per kW is ThrustCeiling / CeilingPowerKW = 69.3.
Tune.CeilingPowerKW = 1082

-- Overall thrust per engine power, as a plain multiplier: 2 gives every nozzle twice the thrust for the same engine power
-- (and, because the nozzle never gives more than its own maximum, it also means the engine has to work less hard to reach it).
Tune.ThrustPerPowerScale = 0.29

-- Small nozzles waste more of the engine's power than big ones: the thrust you get per kW is multiplied by this, 0.5 for the
-- smallest nozzle (DiameterMin) up to 1.0 for the largest (DiameterMax), straight line in between. PLACEHOLDER.
Tune.EfficiencySmall = 0.5
Tune.EfficiencyLarge = 1.0

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
	local MaxThrust  = Tune.ThrustCeiling * (Diameter / Tune.DiameterMax) ^ 2
	local PerKW      = Tune.ThrustCeiling / Tune.CeilingPowerKW * Tune.ThrustPerPowerScale * Efficiency

	return MaxThrust, PerKW, MaxThrust / PerKW, Efficiency, Size
end
