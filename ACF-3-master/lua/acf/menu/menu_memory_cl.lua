-- Menu memory (clientside only).
--
-- Remembers the sliders / number boxes / checkboxes / text boxes of the ACF menu separately for each type of thing
-- you are editing (each gun + ammo type, each gearbox, each turret part, ...), for as long as the game is running.
--
-- It works in two moments only, so it never touches a control while you are editing it:
--   LEAVING a type  -> the values you changed on that type are saved. "Leaving" means: you click another gun / ammo
--                      type / gearbox / component, you switch to another menu page, or you close the spawn menu.
--   ENTERING a type -> once the menu has finished building (0.15s after the last build activity), the values saved
--                      for that type are put back into the controls through the controls' own SetValue, exactly as if
--                      you had moved them by hand. If you are holding the mouse button down at that moment, nothing is
--                      put back, so it can never fight you while you drag a slider.
-- Only the values you actually changed on a type are saved for it. A type you only looked at is never given values
-- it did not have, so clicking through other guns cannot overwrite what they have saved.
--
-- The ammo box settings (Crate/Drum and the projectile counts) belong to the GUN, not to the ammo type: every gun has
-- its own, and a gun you never set one on shows the default box (Crate, 3 x 3 x 3), not the previous gun's.
--
-- Nothing is written to disk and nothing is sent to the server by this file. The values live in ACF.MenuMemory.Data
-- (a normal Lua table) and disappear when the game is closed or the map/server changes.
--
-- Console variables / commands:
--   acf_menu_memory 1/0         turn the memory on/off (default on)
--   acf_menu_memory_debug 1/0   print what is saved/restored to the console (default off)
--   acf_menu_memory_clear       forget everything that was remembered

local ACF = ACF

ACF.MenuMemory = ACF.MenuMemory or {}

local Mem = ACF.MenuMemory

Mem.Data    = Mem.Data or {}    -- [ContextKey] = { [VariableName] = Value }
Mem.Wrapped = Mem.Wrapped or {} -- Wrapper functions created by this file, so reloading the file never wraps twice
Mem.State   = Mem.State or {}   -- Pending, Applying, Epoch, Chain, StableOp, StableCtx, Dirty

local State   = Mem.State
local Enabled = CreateClientConVar("acf_menu_memory", "1", true, false, "Remember the ACF menu slider values per gun/ammo/gearbox/etc. type until the game is closed.")
local Debug   = CreateClientConVar("acf_menu_memory_debug", "0", false, false, "Print what the ACF menu memory saves and restores.")

State.Epoch = State.Epoch or 0
State.Chain = State.Chain or 0
State.Dirty = State.Dirty or {}

local TOOL_KEY      = "ToolMode:acf_menu" -- Client data variable that holds "<Stage>:<Operation>", e.g. "Spawner:Gearbox"
local SETTLE_TIME   = 0.15                -- Seconds without any build activity before the menu counts as built
local MAX_CHAIN     = 8                   -- Restores in a row without the menu calming down before we give up

local function Log(...)
	if not Debug:GetBool() then return end

	MsgN("[ACF Menu Memory] ", ...)
end

---------------------------------------------------------------------------------------------------------------
-- Which type is selected?
--
-- A "scope" says: on these menu pages (Ops), the controls it owns are remembered separately for every
-- combination of the Select client data variables (the "type": weapon id, ammo type, gearbox id, ...).
--   Ops/OpTest : which menu pages (the operation name the menu sets with ACF.SetToolMode) the scope is used on
--   Select     : client data variables that identify the type
--   Vars       : if present, the scope only owns these variables; otherwise it owns every control variable,
--                except the ones in Skip (those are left alone and keep their normal behaviour)
-- Scopes are checked in order; the first one that owns a variable gets it.
---------------------------------------------------------------------------------------------------------------

-- The ammo box (crate/drum) settings belong to the GUN, not to the ammo type: they have their own scope below, so the
-- ammo scope must not take them.
local SkipAmmo = {
	CrateProjectilesX = true,
	CrateProjectilesY = true,
	CrateProjectilesZ = true,
	AmmoShape         = true,
}

-- Ammo box settings of a gun. Order = the order they are put back in (the shape first, because changing it changes
-- what the counts mean and what their limits are). Defaults = what a gun with nothing saved shows when it is entered,
-- so one gun's box does not carry over to the next; these are the same defaults the stock menu starts with.
local Crate = {
	Vars     = { CrateProjectilesX = true, CrateProjectilesY = true, CrateProjectilesZ = true, AmmoShape = true },
	Order    = { "AmmoShape", "CrateProjectilesX", "CrateProjectilesY", "CrateProjectilesZ" },
	Defaults = { CrateProjectilesX = 3, CrateProjectilesY = 3, CrateProjectilesZ = 3, AmmoShape = "Box" },
}

local Scopes = {
	{ Name = "gun",       Ops = { Weapon = true, Missile = true }, Select = { "Weapon" },                 Vars = { Caliber = true } },
	{ Name = "crate",     Ops = { Weapon = true, Missile = true }, Select = { "Weapon" },                 Vars = Crate.Vars, Order = Crate.Order, Defaults = Crate.Defaults },
	{ Name = "ammo",      Ops = { Weapon = true, Missile = true }, Select = { "Weapon", "AmmoType" },     Skip = SkipAmmo },
	{ Name = "gearbox",   Ops = { Gearbox = true },                Select = { "Gearbox" } },
	{ Name = "component", Ops = { Component = true },              Select = { "ComponentClass", "Component" } },
	{ Name = "sensor",    Ops = { Sensor = true },                 Select = { "SensorClass", "Sensor" } },
	{ Name = "turret",    OpTest = function(Op) return string.match(Op, "^%d+%-") ~= nil end, Select = { "Component" } }, -- Turret ring/motor/gyro/computer pages use the class id as operation
}

-- Any other page (crew, engines, ...) is remembered per page.
local Fallback = { Name = "page", Select = {} }

-- Variables that must never be restored, whatever page they show up on.
local Never = {
	PrimaryClass   = true,
	SecondaryClass = true,
	Destiny        = true,
	BreechIndex    = true, -- Drop-down list, ACF re-selects it itself
	[TOOL_KEY]     = true,
}

-- Changing any of these means "the type changed or the page changed", so the menu is about to be rebuilt.
local Triggers = { [TOOL_KEY] = true }

for _, Scope in ipairs(Scopes) do
	for _, Key in ipairs(Scope.Select) do
		Triggers[Key] = true
		Never[Key]    = true
	end
end

local ActiveCache = {}

local function GetOp()
	local Mode = ACF.ClientData[TOOL_KEY]

	if not isstring(Mode) then return end

	local Stage, Op = string.match(Mode, "^([^:]*):(.*)$")

	if Stage ~= "Spawner" then return end -- Settings, scanner, safezones... are not remembered

	return Op
end

local function GetActive(Op)
	local Result = ActiveCache[Op]

	if Result then return Result end

	Result = {}

	for _, Scope in ipairs(Scopes) do
		if (Scope.Ops and Scope.Ops[Op]) or (Scope.OpTest and Scope.OpTest(Op)) then
			Result[#Result + 1] = Scope
		end
	end

	if #Result == 0 then
		Result[1] = Fallback
	end

	ActiveCache[Op] = Result

	return Result
end

local function Owns(Scope, Var)
	if Never[Var] then return false end
	if Scope.Vars then return Scope.Vars[Var] == true end
	if Scope.Skip and Scope.Skip[Var] then return false end

	return true
end

local function FindOwner(Var, Active)
	for _, Scope in ipairs(Active) do
		if Owns(Scope, Var) then return Scope end
	end
end

--- Builds the key the values of a scope are stored under, e.g. "ammo|Weapon|C|HE|AP".
--- Returns nil while the type is not fully chosen yet.
local function GetContext(Scope, Op)
	local Parts = { Scope.Name, Op }
	local Data  = ACF.ClientData

	for _, Key in ipairs(Scope.Select) do
		local Value = Data[Key]

		if Value == nil or Value == false or Value == "" then return end

		Parts[#Parts + 1] = tostring(Value)
	end

	return table.concat(Parts, "|")
end

--- Works out which page and which type are shown right now and remembers it as "the settled state".
local function ReadStable()
	local Op = GetOp()

	State.StableOp  = Op
	State.StableCtx = {}
	State.Dirty     = {}

	if not Op then return end

	for _, Scope in ipairs(GetActive(Op)) do
		State.StableCtx[Scope.Name] = GetContext(Scope, Op)
	end
end

---------------------------------------------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------------------------------------------

--- Returns the valid panels that currently set the given client data variable (nil if there are none).
local function GetPanels(Var)
	local Panels = ACF.DataPanels
	local Data   = Panels and Panels.Client and Panels.Client[Var]
	local Setter = Data and Data.Setter

	if not Setter then return end

	local Result

	for Panel in pairs(Setter) do
		if IsValid(Panel) then
			Result = Result or {}
			Result[#Result + 1] = Panel
		end
	end

	return Result
end

local function IsStorable(Value)
	local Type = type(Value)

	return Type == "number" or Type == "boolean" or Type == "string"
end

-- Controls that are not tied to their variable through Panel:SetClientData, so GetPanels cannot find them.
-- The Crate/Drum drop-down of the ammo box is one: the ammo menu keeps it in Menu.AmmoShapeList and sets AmmoShape
-- itself when you pick an entry (entry 1 = "Box", entry 2 = "Cylinder").
local Special = {
	AmmoShape = {
		Find = function()
			local Menu = ACF.SpawnMenu
			local List = Menu and IsValid(Menu) and Menu.AmmoShapeList

			if List and IsValid(List) and List.ChooseOptionID then return List end
		end,
		Set = function(List, Value)
			if ACF.ClientData.AmmoShape == Value then return false end -- Already showing it

			List:ChooseOptionID(Value == "Cylinder" and 2 or 1) -- Runs the list's own OnSelect, like a click

			return true
		end,
	},
}

--- True if a control of the menu shows this variable right now.
local function HasControl(Var)
	if GetPanels(Var) then return true end

	local Extra = Special[Var]

	return Extra ~= nil and Extra.Find() ~= nil
end

--- Puts a remembered value back into the controls of a variable, the same way the user would.
local function Apply(Var, Value)
	local Extra = Special[Var]

	if Extra then
		local List = Extra.Find()

		return List ~= nil and Extra.Set(List, Value) or false
	end

	local Panels = GetPanels(Var)

	if not Panels then return false end

	local Done = false

	for _, Panel in ipairs(Panels) do
		-- Sliders, number boxes, check boxes and text boxes have SetValue. Combo boxes do not get restored here
		-- (ACF already remembers which entry of each list was selected).
		if Panel.SetValue and not Panel.ChooseOptionID then
			Panel:SetValue(Value)

			Done = true
		end
	end

	return Done
end

--- True while the player is holding the left mouse button (dragging a slider, for example).
local function IsUserBusy()
	return input and input.IsMouseDown and input.IsMouseDown(MOUSE_LEFT) or false
end

---------------------------------------------------------------------------------------------------------------
-- Saving (when leaving a type)
---------------------------------------------------------------------------------------------------------------

--- Notes that the user changed a control variable of the type that is shown. The value itself is only read when
--- the type is left, so a value is never saved while it is being edited.
local function NoteChange(Key, Value)
	if State.Pending or State.Applying then return end
	if not Enabled:GetBool() then return end

	local Op = State.StableOp

	if not Op then return end

	if Value == nil then Value = false end -- ACF.SetClientData stores nil as false
	if ACF.ClientData[Key] == Value then return end -- Not a change

	local Scope = FindOwner(Key, GetActive(Op))

	if not Scope then return end
	if not State.StableCtx or not State.StableCtx[Scope.Name] then return end
	if not HasControl(Key) then return end -- Only values that a control of the menu is showing

	local Dirty = State.Dirty[Scope.Name]

	if not Dirty then
		Dirty = {}
		State.Dirty[Scope.Name] = Dirty
	end

	Dirty[Key] = true
end

--- Saves the values changed on the type that is shown right now. Does nothing while a menu build is in progress,
--- because then the client data is already mixed with the next type's values.
local function Leave()
	if State.Pending or State.Applying then return end
	if not Enabled:GetBool() then return end

	local Op = State.StableOp

	if not Op or not State.StableCtx then return end

	local Active = GetActive(Op)
	local Data   = Mem.Data

	for _, Scope in ipairs(Active) do
		local Dirty = State.Dirty[Scope.Name]
		local Ctx   = State.StableCtx[Scope.Name]

		if Dirty and Ctx then
			for Var in pairs(Dirty) do
				local Value = ACF.ClientData[Var]

				if IsStorable(Value) and FindOwner(Var, Active) == Scope then
					local Store = Data[Ctx]

					if not Store then
						Store = {}
						Data[Ctx] = Store
					end

					if Store[Var] ~= Value then
						Store[Var] = Value

						Log("saved ", Var, " = ", tostring(Value), "  (", Ctx, ")")
					end
				end
			end
		end
	end

	State.Dirty = {}
end

---------------------------------------------------------------------------------------------------------------
-- Restoring (after entering a type)
---------------------------------------------------------------------------------------------------------------

local Settle

--- (Re)starts the countdown until the menu counts as built.
local function Bump()
	State.Epoch = State.Epoch + 1

	timer.Create("ACF Menu Memory Settle", SETTLE_TIME, 1, Settle)
end

--- A type or a page is about to be entered: save the one we are leaving, then wait for the build to finish.
local function Enter()
	Mem.Leave()

	State.Pending = true

	Bump()
end

local function Restore()
	ReadStable() -- Which type is shown now

	local Op = State.StableOp

	if not Op then return end
	if not Enabled:GetBool() then return end

	local Active = GetActive(Op)
	local Data   = Mem.Data

	for _, Scope in ipairs(Active) do
		local Ctx   = State.StableCtx[Scope.Name]
		local Store = Ctx and Data[Ctx]

		if Ctx and (Store or Scope.Defaults) then
			local Names = {}

			if Scope.Order then
				for _, Var in ipairs(Scope.Order) do -- Fixed order, and every one of them (defaults fill the gaps)
					Names[#Names + 1] = Var
				end
			else
				for Var in pairs(Store) do
					if FindOwner(Var, Active) == Scope then
						Names[#Names + 1] = Var
					end
				end

				table.sort(Names)
			end

			for _, Var in ipairs(Names) do
				local Value = Store and Store[Var]

				if Value == nil and Scope.Defaults then
					Value = Scope.Defaults[Var] -- Nothing saved for this on this type: show the default, not the last type's
				end

				if Value ~= nil and Apply(Var, Value) then
					Log("restored ", Var, " = ", tostring(Value), "  (", Ctx, ")")
				end
			end
		end
	end
end

Settle = function()
	if not State.Pending then return end

	local StartEpoch = State.Epoch
	local Skip       = false

	State.Chain = State.Chain + 1

	if State.Chain > MAX_CHAIN then
		Skip = true -- The menu keeps rebuilding itself; stop restoring so we can never loop.
	elseif IsUserBusy() then
		Skip = true -- The player already started dragging something; never fight them.

		Log("restore skipped, mouse button is down")
	end

	if not Skip then
		State.Applying = true

		local OK, Err = pcall(Restore)

		State.Applying = false

		if not OK then
			ErrorNoHalt("[ACF Menu Memory] " .. tostring(Err) .. "\n")
		end
	end

	-- If restoring made the menu rebuild, Bump() already started a new countdown and we stay pending.
	if Skip or State.Epoch == StartEpoch then
		State.Pending = false
		State.Chain   = 0

		ReadStable()
	end
end

Mem.Leave = Leave
Mem.Enter = Enter
Mem.Bump  = Bump
Mem.Note  = NoteChange

-- Backup, only used if something else replaced our ACF.SetClientData wrapper (see WrapSetClientData below).
-- While our wrapper is installed it already handles every type/page change, and this hook stays out of the way, so a
-- repeated "forced" set of the same type in the middle of editing can never start a restore.
-- (This only starts a build wait. The old type can no longer be saved at this point.)
hook.Add("ACF_OnUpdateClientData", "ACF Menu Memory", function(_, Key)
	if Mem.Wrapped[ACF.SetClientData] then return end

	if Triggers[Key] and Enabled:GetBool() and not State.Pending then
		State.Pending = true

		Mem.Bump()
	end
end)

--- Closing the spawn menu counts as leaving, so the values changed so far are saved.
hook.Add("OnSpawnMenuClose", "ACF Menu Memory", function()
	Mem.Leave()
end)

--- Wraps ACF.SetClientData so that every change is looked at BEFORE the normal code (and the menu) reacts to it.
--- At that moment the client data still holds the old type's values, which is what must be saved.
local function WrapSetClientData()
	local Current = ACF.SetClientData

	if not isfunction(Current) then return end
	if Mem.Wrapped[Current] then return end

	local function Wrapper(Key, Value, Forced)
		if isstring(Key) and Enabled:GetBool() then
			if Key == TOOL_KEY then
				Mem.Enter() -- Every page build sets the tool mode, even to the same value
			elseif Triggers[Key] then
				local New = Value

				if New == nil then New = false end

				if ACF.ClientData[Key] ~= New then
					Mem.Enter()
				end
			else
				Mem.Note(Key, Value)
			end
		end

		return Current(Key, Value, Forced)
	end

	Mem.Wrapped[Wrapper] = true
	ACF.SetClientData    = Wrapper
end

--- Every time a menu control gets linked to a client data variable, the menu is being (re)built. While we are waiting
--- for a build to finish this keeps the wait going. Outside of that it does nothing, so rebuilding part of the menu
--- while you are editing (changing the caliber rebuilds the ammo controls) never restores anything.
local function WrapPanelFunction(Name)
	local PanelMeta = FindMetaTable("Panel")
	local Current   = PanelMeta[Name]

	if not isfunction(Current) then return end
	if Mem.Wrapped[Current] then return end

	local function Wrapper(...)
		local Result = Current(...)

		if State.Pending then
			Mem.Bump()
		end

		return Result
	end

	Mem.Wrapped[Wrapper] = true
	PanelMeta[Name]      = Wrapper
end

WrapPanelFunction("SetClientData")
WrapSetClientData()

hook.Add("Initialize", "ACF Menu Memory", function()
	WrapPanelFunction("SetClientData")
	WrapSetClientData()
end)

concommand.Add("acf_menu_memory_clear", function()
	Mem.Data = {}

	MsgN("[ACF Menu Memory] Everything remembered by the menu was cleared.")
end)
