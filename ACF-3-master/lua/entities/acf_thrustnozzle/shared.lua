DEFINE_BASECLASS("acf_base_scalable")

-- All the numbers that decide how the thruster behaves are in tuning.lua, next to this file.
include("tuning.lua")

local Tune = ACF.ThrustNozzle

ENT.PrintName      = "ACF VTOL Jet Thruster"
ENT.WireDebugName  = "ACF VTOL Jet Thruster"
ENT.PluralName     = "ACF VTOL Jet Thrusters"
ENT.ACF_Limit      = Tune.EntityLimit
ENT.ACF_PreventArmoring = true

-- Maps user var name to its type, whether it is client data and type specific arguments (all support defaults?)
-- The sound variables have their own names (not SoundPath and so on, which ACF's waterjet uses) so that what you type in this
-- thruster's menu can never end up on a waterjet.
ENT.ACF_UserVars = {
    ["NozzleDiameter"] = {Type = "Number", Min = Tune.DiameterMin, Max = Tune.DiameterMax, Default = Tune.DiameterDefault, Decimals = 1},
    ["NozzleSoundPath"] = {Type = "String", Default = Tune.SoundDefault},
    ["NozzleSoundPitch"] = {Type = "Number", Min = 0.1, Max = 2, Default = 1, Decimals = 2},
    ["NozzleSoundVolume"] = {Type = "Number", Min = 0.1, Max = 1, Default = 0.5, Decimals = 2},
}

ENT.ACF_WireInputs = {
    "Thrust (The thrust to hold, in the same numbers as the thruster tool's Force. It never goes above the Max Thrust shown on the overlay. If nothing is wired here the thruster asks for its maximum and the engine throttle alone sets the thrust.)",
    "Slew (How fast the thrust may change, in thrust per second, up or down. 0 = instantly.)",
    "Pitch (Swings the exhaust toward the thruster's front for plus, back for minus, in degrees. Limited to the maximum vector angle.)",
    "Yaw (Swings the exhaust sideways, in degrees. Limited to the maximum vector angle.)",
}

ENT.ACF_WireOutputs = {
    "Max Thrust (The most this nozzle can ever give, in the same numbers as the Thrust input.)",
    "Available Thrust (The most the engines linked to it can keep up, never above Max Thrust. Keep the Thrust input at or below this so the engine does not stall. You can ask for more, the engine just bogs down.)",
    "Thrust Delivered (The thrust it is really giving right now.)",
    "Diameter (The nozzle's diameter, in inches.)",
    "Required Power (The engine power it needs for Max Thrust, in kW.)",
    "Received Power (The engine power it is getting right now, in kW.)",
    "Efficiency (How much of the engine power becomes thrust, in percent.)",
}
-- NOTE: do not put brackets inside these descriptions, Wire cuts the name at the LAST " (" of the text.

cleanup.Register("acf_thrustnozzle")
