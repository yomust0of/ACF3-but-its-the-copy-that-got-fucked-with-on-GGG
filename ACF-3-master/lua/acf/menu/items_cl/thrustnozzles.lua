local ACF        = ACF
local Components = ACF.Classes.Components

-- Shows up in the Components list right next to the Water Jet.
-- The numbers (diameter range, efficiency and so on) are in lua\entities\acf_thrustnozzle\tuning.lua.
Components.Register("TNZ", {
	Name   = "VTOL Jet Thruster",
	Entity = "acf_thrustnozzle",
})

Components.RegisterItem("TNZ-VTOL", "TNZ", {
	Name        = "VTOL Jet Thruster",
	Description = "A thruster for aircraft, driven by an engine through a gearbox like a waterjet. It works in air and in water. You wire in how much thrust you want, and it gives that, up to what it can do and what the linked engines can deliver.",
	Model       = "models/maxofs2d/hover_propeller.mdl",
	CreateMenu = function(_, Menu)
		local Tune = ACF.ThrustNozzle

		local Stats = Menu:AddLabel("")

		local function ShowStats(Diameter)
			local MaxThrust, _, RatedPower, Efficiency = Tune.GetStats(Diameter)

			Stats:SetText(("Max thrust: %d\nEngine power for max thrust: %d kW\nEfficiency: %d%%"):format(math.Round(MaxThrust), math.ceil(RatedPower), math.Round(Efficiency * 100)))
		end

		-- Our own slider: the nozzle's diameter, in inches. The thrust it can give grows with the area of that circle.
		local Size = Menu:AddSlider("Diameter (inches)", Tune.DiameterMin, Tune.DiameterMax, 1)
		Size:SetValue(Tune.DiameterDefault)
		Size:SetClientData("NozzleDiameter", "OnValueChanged")
		Size:DefineSetter(function(Panel, _, _, Value)
			local Diameter = math.Round(Value, 1)

			Panel:SetValue(Diameter)
			ShowStats(Diameter)

			if Menu.ComponentPreview then
				Menu.ComponentPreview:SetModelScale(Diameter / Tune.ModelDiameter, true)
			end
		end)

		-- The sound file. ACF.PersistClientData("NozzleSoundPath") (lua\acf\persisted_vars\vars_cl.lua) is what keeps what you type
		-- between games; the box is filled from it here.
		local _, _, SoundEntry = Menu:AddTextEntry("Sound")
		SoundEntry:SetValue(ACF.GetClientString("NozzleSoundPath", Tune.SoundDefault))
		SoundEntry:SetClientData("NozzleSoundPath", "OnValueChange")

		SoundEntry.OnLoseFocus = function(self)
			DTextEntry.OnLoseFocus(self)
			self:OnValueChange(self:GetText())
		end

		SoundEntry.OnEnter = function(self)
			self:OnValueChange(self:GetText())
		end

		Menu:AddHelp("The sound file the thruster plays, relative to the game's sound folder. Leave it empty for no sound. What you type here is remembered between games. Volume and pitch are set with the ACF sound tool; the thrust changes them as it goes.")
		Menu:AddHelp("Link it to a gearbox like a waterjet. Wire a number into Thrust to say how much you want; Slew, Pitch and Yaw are optional.")
	end
})
