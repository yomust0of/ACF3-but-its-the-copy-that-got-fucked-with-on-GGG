-- Pre-scalable gearbox conversion, part 2 of 2.
--
-- Part 1 is in lua/entities/acf_gearbox/init.lua (VerifyData and ACF.MakeGearbox). When a dupe holds an old gearbox ID such as
-- "4Gear-T-M", it is spawned as the scalable gearbox it became ("Manual-T") at the fixed size the old S/M/L had, with the old gear
-- count and the gear ratios flipped, and Entity.PreScalableID is set on it.
--
-- That fixed size is only a first guess, because while a dupe is still spawning nothing is linked yet. This file runs when Advanced
-- Duplicator says the paste is finished (every entity exists and every link is back). It then resizes each flagged gearbox to the
-- smallest scale whose torque rating still carries the torque of whatever feeds it, and tells the player in chat what it did.

local ACF  = ACF
local hook = hook
local abs  = math.abs
local max  = math.max
local min  = math.min

local ScaleStep = 0.01 -- The gearbox scale slider works in hundredths
local CVTRatio  = 20   -- The biggest ratio a CVT picks by itself is 1 / 0.05, see the CVT part of ENT:Calc
local MaxListed = 8    -- How many gearboxes get their own chat line, the rest are only counted

local Input, Resolve -- They call each other

-- The most a gearbox can multiply torque by: its biggest gear times its final drive
local function GetMultiplier(Box)
	local Best = 0

	if Box.CVT then
		Best = CVTRatio
	else
		for I = 1, Box.MaxGear do
			Best = max(Best, abs(Box.Gears[I] or 0))
		end
	end

	return Best * abs(Box.FinalDrive or 1)
end

-- The torque a gearbox hands to whatever it drives: what it receives, held back by its own rating, times its biggest gear
local function Output(Box, Plans, Busy)
	local Rating = Box.MaxTorque
	local Need

	if Box.PreScalableID then
		local Plan = Resolve(Box, Plans, Busy)

		if Plan then Rating, Need = Plan.Rating, Plan.Need end
	end

	return min(Need or Input(Box, Plans, Busy), Rating) * GetMultiplier(Box)
end

-- The torque arriving at a gearbox: the peak of every engine linked to it plus the output of every gearbox feeding it.
-- Busy stops a loop of gearboxes linked in a circle from running forever.
function Input(Box, Plans, Busy)
	if Busy[Box] then return 0 end

	Busy[Box] = true

	local Sum = 0

	for Engine in pairs(Box.Engines) do
		if IsValid(Engine) then Sum = Sum + (Engine.PeakTorqueHeld or 0) end
	end

	for Source in pairs(Box.GearboxIn) do
		if IsValid(Source) then Sum = Sum + Output(Source, Plans, Busy) end
	end

	Busy[Box] = nil

	return Sum
end

-- Works out the new scale of one flagged gearbox. Gearboxes feeding it are worked out first, because their new rating decides
-- how much torque reaches this one.
function Resolve(Box, Plans, Busy)
	if Plans[Box] then return Plans[Box] end
	if Busy[Box] then return end

	local Need  = Input(Box, Plans, Busy)
	local Item  = ACF.Classes.Gearboxes.GetItem(Box.ClassData.ID, Box.ShortName)
	local Plan  = { Need = Need, Scale = Box.ScaleMult, Rating = Box.MaxTorque }

	Plans[Box] = Plan

	-- Nothing feeds it, so there is nothing to size it for and it keeps the size the old S/M/L had
	if Need <= 0 or not Item then return Plan end

	-- Rating = floor(MaxTorque * GearEfficiency ^ gears * Scale ^ GearboxTorqueScale / 10) * 10 (ACF.GetGearboxStats).
	-- Solve that for the scale to get a starting point just under the answer, then step up until the rating covers the torque.
	local PerScale = Item.MaxTorque * ACF.GearEfficiency ^ Box.MaxGear
	local Scale    = math.Round(math.floor((Need / PerScale) ^ (1 / ACF.GearboxTorqueScale) / ScaleStep) * ScaleStep, 2)

	Scale = math.Clamp(Scale, ACF.GearboxMinSize, ACF.GearboxMaxSize)

	local _, _, Rating = ACF.GetGearboxStats(Item.Mass, Scale, Item.MaxTorque, Box.MaxGear)

	while Rating < Need and Scale < ACF.GearboxMaxSize do
		Scale = min(math.Round(Scale + ScaleStep, 2), ACF.GearboxMaxSize)

		_, _, Rating = ACF.GetGearboxStats(Item.Mass, Scale, Item.MaxTorque, Box.MaxGear)
	end

	Plan.Scale  = Scale
	Plan.Rating = Rating
	Plan.Sized  = true -- Sized for the engines, not just left at the old size

	return Plan
end

-- Makes the gearbox the new size, the same way the menu's update does it (which also relinks it to everything)
local function Apply(Box, Scale)
	if abs(Scale - Box.ScaleMult) < 0.001 then return true, "" end

	local Data = {}

	for _, Key in ipairs(Box.DataStore) do
		Data[Key] = Box[Key]
	end

	Data.Gears        = table.Copy(Box.Gears)
	Data.ShiftPoints  = Box.ShiftPoints and table.Copy(Box.ShiftPoints)
	Data.Gearbox      = Box.ShortName
	Data.GearboxScale = Scale

	local Done, Result = Box:Update(Data)

	-- On success the text is "Gearbox updated successfully!" and then one line per thing that had to be unlinked
	if Done then Result = string.match(Result, "\n(.*)$") or "" end

	return Done, Result
end

local function Convert(Info)
	local Boxes = {}

	for _, Ent in pairs(Info.CreatedEntities or {}) do
		if IsValid(Ent) and Ent.PreScalableID then Boxes[#Boxes + 1] = Ent end
	end

	if not Boxes[1] then return end

	table.sort(Boxes, function(A, B) return A:EntIndex() < B:EntIndex() end)

	local Plans, Busy = {}, {}
	local Lines       = {}
	local Mult        = ACF.TorqueMult or 1 -- The overlay shows torque times this, so the chat does too

	-- Plan everything first, then resize. Resizing relinks the gearbox, and the plans need the links as they were.
	for _, Box in ipairs(Boxes) do Resolve(Box, Plans, Busy) end

	for _, Box in ipairs(Boxes) do
		local Plan        = Plans[Box]
		local OldID       = Box.PreScalableID
		local Done, Extra = Apply(Box, Plan.Scale)
		local Text        = ("[%s] %s -> %s, scale %s"):format(Box:EntIndex(), OldID, Box.ShortName, Plan.Scale)
		local Warn        = not Done

		if not Done then
			Text = Text .. " - could not be resized: " .. tostring(Extra)
		elseif not Plan.Sized then
			Text = Text .. " (no engine is linked to it, so it kept the size of the old one)"
		else
			Text = Text .. (" (rating %s Nm for %s Nm of engine torque)"):format(math.Round(Plan.Rating * Mult), math.Round(Plan.Need * Mult))

			if Plan.Rating < Plan.Need then
				Text = Text .. " - the biggest scale is still too small for it"
				Warn = true
			end
		end

		if Done and Extra ~= "" then
			Text = Text .. " - " .. string.Trim(string.Replace(Extra, "\n", " "))
			Warn = true
		end

		Box.PreScalableID = nil

		Lines[#Lines + 1] = { Text = Text, Warn = Warn }
	end

	local Player = Info.Player

	if not IsValid(Player) then return end

	local Messages = ACF.Utilities.Messages
	local Count    = #Lines

	Messages.SendChat(Player, "Info", ("This dupe had %s old gearbox%s. %s now scalable and sized for the engines linked to %s:"):format(
		Count, Count == 1 and "" or "es", Count == 1 and "It is" or "They are", Count == 1 and "it" or "them"))

	for I = 1, min(Count, MaxListed) do
		Messages.SendChat(Player, Lines[I].Warn and "Warning" or "Info", Lines[I].Text)
	end

	if Count > MaxListed then
		Messages.SendChat(Player, "Info", ("...and %s more."):format(Count - MaxListed))
	end
end

-- Advanced Duplicator 1 and 2 call this after the last entity and the last link of a paste are done
hook.Add("AdvDupe_FinishPasting", "ACF_ConvertPreScalableGearboxes", function(Tab)
	local Info = istable(Tab) and Tab[1]

	if not Info then return end

	-- An error here must not stop the duplicator from finishing the paste
	local Success, Err = pcall(Convert, Info)

	if not Success then ErrorNoHalt("[ACF] Converting old gearboxes failed: " .. tostring(Err) .. "\n") end
end)
