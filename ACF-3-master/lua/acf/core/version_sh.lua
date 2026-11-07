local ACF = ACF
local Realm = SERVER and "Server" or "Client"

-- GGG ACF3 "Freedom Edition": what this copy of ACF calls itself.
-- ACF.Edition is the id. It is sent to clients inside ACF.Extensions (see the end of this file) so a client can tell if the server runs
-- the same edition, which is why it keeps the spelling earlier copies of this edition already send. ACF.EditionDisplay is how chat writes it.
ACF.Edition        = "GGG acf3 freedom edition"
ACF.EditionDisplay = 'GGG ACF3 "Freedom Edition"'
ACF.EditionBranch  = "beta"

--- Converts a local time to UTC for comparison
local function LocalToUTC(time)
	return os.time(os.date("!*t", time)) or 0 -- WHY WOULD IT EVER BE NIL :(
end

--- Returns the current git branch name
local function GetGitHead(Path)
	local HeadFile = Path .. "/.git/HEAD"
	if not file.Exists(HeadFile, "GAME") then return end

	local content = file.Read(HeadFile, "GAME")
	if not content then return end

	local _, _, head = content:find("refs/heads/(.+)$")  -- Extract the branch name from the content, e.g. "master" from "ref: refs/heads/master"
	if not head then return end

	return head:Trim()
end

--- Returns the current git commit SHA and date for a given branch
local function GetGitCommit(Path, Head)
	if not Head then return end

	local RefPath = Path .. "/.git/refs/heads/" .. Head

	if not file.Exists(RefPath, "GAME") then return end

	local sha = file.Read(RefPath, "GAME")
	if not sha then return end

	local BranchSha = string.GetFileFromFilename(Head) .. "-" .. sha:Trim():sub(1, 7)
	local Time = file.Time(RefPath, "GAME")
	return BranchSha, Time
end

--- Returns the git owner from the URL of the remote repository
local function GetGitOwner(Path)
	local FetchPath = Path .. "/.git/FETCH_HEAD"
	if not file.Exists(FetchPath, "GAME") then return end

	local Fetch = file.Read(FetchPath, "GAME")
	if not Fetch then return end

	local Start, End = Fetch:find("github.com[/]?[:]?[%w_-]+/") -- Extract the owner name from the URL, e.g. "ACF-3" from "github.com/ACF-3/ACF-3"
	if not Start then return end

	return Fetch:sub(Start + 11, End - 1)
end

--- Returns a table with information about the most recent commit on the current branch.
--- Handles git, workshop and zip installations.
function ACF.CheckLocalVersion(Owner, Name, Path)
	local Result = {
		realm = Realm,
		path  = Path,
		head  = "master",
		code  = "Not Installed",
		date  = 0,
		owner = Owner
	}

	-- Default result if no installation found
	if not Path then return Result end

	-- Git installation
	if file.Exists(Path .. "/.git/HEAD", "GAME") then
		local Head = GetGitHead(Path)
		local Code, Date = GetGitCommit(Path, Head)

		Result.head  = Head or "master"
		Result.owner = GetGitOwner(Path) -- Makes sure the owner of the repo is correct, deals with forks

		if Code and Date then
			Result.code = "Git-" .. Code
			Result.date = LocalToUTC(Date)
		end

		return Result
	end

	-- Workshop install
	local WorkshopPath = "data_static/acf/" .. string.lower(Name) .. "-version.txt"
	if file.Exists(WorkshopPath, "GAME") then
		local FileData = file.Read(WorkshopPath, "GAME"):Trim()
		local Code = FileData:sub(1, 7)
		local Date = file.Time(WorkshopPath, "GAME")

		Result.code = "Git-master-" .. Code
		Result.date = LocalToUTC(Date)

		return Result
	end

	-- ZIP install
	if file.Exists(Path .. "/LICENSE", "GAME") then
		Result.code = "ZIP-Unknown"
		Result.date = LocalToUTC(file.Time(Path .. "/LICENSE", "GAME"))

		return Result
	end

	return Result
end

--- Convert GitHub date string to epoch
local function GitDateToEpoch(dateStr)
	local year, month, day, hour, min, sec = dateStr:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
	return os.time({
		year = tonumber(year),
		month = tonumber(month),
		day = tonumber(day),
		hour = tonumber(hour),
		min = tonumber(min),
		sec = tonumber(sec)
	})
end

--- Retrieves the title and body from a git commit message
local function GitTitleBody(Message)
	if not Message then return end

	local Start = Message:find("\n\n")

	Message = Message:Replace("\n\n", "\n"):gsub("[\r]*[\n]+[%s]+", "\n- ")

	local Title = Start and Message:sub(1, Start - 1) or Message
	local Body  = Start and Message:sub(Start + 1, #Message) or "No Commit Message"

	return Title, Body
end

--- Fetches the (latest) commit given a url and runs the callback with the commit information
local function FetchCommit(url, callback)
	ACF.StartRequest(url,
	function(body, _, _, _)
		local data = util.JSONToTable(body)
		if not data then ACF.PrintLog("HTTP_Error", "Failed to fetch commit information") return end

		local raw = data[1] or data
		if not raw or not raw.commit then ACF.PrintLog("HTTP_Error", "Failed to fetch commit information") return end

		local Title, Body = GitTitleBody(raw.commit.message)

		callback({
			short_sha = raw.sha:sub(1, 7),
			title     = Title,
			body      = Body,
			author    = raw.commit.author.name,
			date      = GitDateToEpoch(raw.commit.author.date),
			url       = raw.html_url
		})
	end,
	function(_)
		ACF.PrintLog("HTTP_Error", "Failed to fetch commit information")
	end
	)
end

--- Get information about the latest commit for a given repo and branch
--- Example usage: lua_run ACF.GetLatestCommit("ACF-Team", "ACF-3", "master", function(commit) PrintTable(commit) end)
function ACF.GetLatestCommit(owner, repo, branch, callback)
	FetchCommit(("https://api.github.com/repos/%s/%s/commits?per_page=1&sha=%s"):format(owner, repo, branch), callback)
end

--- Get information about a specific commit by SHA
--- Example usage: lua_run ACF.GetCommit("ACF-Team", "ACF-3", "abc1234", function(commit) PrintTable(commit) end)
function ACF.GetCommit(owner, repo, sha, callback)
	FetchCommit(("https://api.github.com/repos/%s/%s/commits/%s"):format(owner, repo, sha), callback)
end

ACF.Extensions = ACF.Extensions or {}
ACF.ExtensionOrders = ACF.ExtensionOrders or {}
function ACF.AddRepository(Owner, Name)
	if ACF.Extensions[Name] then return end
	local info = debug.getinfo(2, "S")
	local Path = string.Split(info.short_src, "/lua/")[1]

	local Version = ACF.CheckLocalVersion(Owner, Name, Path)
	ACF.Extensions[Name] = ACF.Extensions[Name] or {}
	ACF.Extensions[Name].Version = Version -- Version info for this repository
	table.insert(ACF.ExtensionOrders, Name)
end

ACF.AddRepository("ACF-Team", "ACF-3")

-- Marks this copy as the freedom edition. Everything in ACF.Extensions is sent to clients below, so a client can tell what the server runs.
ACF.Extensions["ACF-3"].Edition       = ACF.Edition
ACF.Extensions["ACF-3"].EditionBranch = ACF.EditionBranch

-- Upstream asked api.github.com for the newest ACF-3 commit when the server started and told players in chat if they or the server were
-- out of date. That is removed here: no web request is made and no "out of date" chat notice exists. The notice at the bottom replaces it.
-- ACF.GetLatestCommit / ACF.GetCommit above are kept, unused, for pointing at our own repository once it is public.

-- Realm specific stuff (so small it probably doesn't need to be in separate files)
if SERVER then
	-- Send this server's version info (including the edition marker above) to every player as they load in
	util.AddNetworkString("ACF_VersionInfo")
	hook.Add("ACF_OnLoadPlayer", "ACF_SendVersionInfo", function(ply)
		net.Start("ACF_VersionInfo")
		net.WriteString(util.TableToJSON(ACF.Extensions or {}))
		net.Send(ply)
	end)
elseif CLIENT then
	local EditionName = ACF.EditionDisplay .. " " .. ACF.EditionBranch .. " branch" -- GGG ACF3 "Freedom Edition" beta branch

	-- Receive version info from server
	net.Receive("ACF_VersionInfo", function()
		ACF.ServerExtensions = util.JSONToTable(net.ReadString())
	end)

	-- Text from the server is shortened and kept to strings before it goes into chat
	local function Clean(Value)
		return string.sub(tostring(Value), 1, 60)
	end

	-- Tells the player once, in chat: that they have this edition, whether the server has it too, and which ACF branch the server is on.
	local function PrintEditionNotice()
		local Messages = ACF.Utilities.Messages
		local Server   = ACF.ServerExtensions and ACF.ServerExtensions["ACF-3"]

		Messages.PrintChat("Info", "You have the " .. EditionName .. " installed.")

		if not istable(Server) then
			Messages.PrintChat("Info", "The server did not send any ACF version info, so it does not have it installed. Its branch is unknown.")
			return
		end

		if Server.Edition == nil then
			Messages.PrintChat("Info", "The server does not have it installed.")
		elseif Server.Edition == ACF.Edition and Server.EditionBranch == ACF.EditionBranch then
			Messages.PrintChat("Info", "The server has it installed too.")
		else
			-- Same edition on another branch is written the same way as above; anything else is text from the server and is shown as it is
			local Name = Server.Edition == ACF.Edition and ACF.EditionDisplay or Clean(Server.Edition)

			Messages.PrintChat("Info", "The server has the " .. Name .. " " .. Clean(Server.EditionBranch) .. " branch installed, which is not the same as yours.")
		end

		-- The branch is only real for git (and workshop, which is always master) installs. A zip install has no way to tell.
		local Version = istable(Server.Version) and Server.Version or {}
		local Code    = isstring(Version.code) and Version.code or ""

		if string.sub(Code, 1, 4) == "Git-" and isstring(Version.head) then
			Messages.PrintChat("Info", "The server's ACF branch is " .. Clean(Version.head) .. " (" .. Clean(Code) .. ").")
		else
			Messages.PrintChat("Info", "The server's ACF branch could not be told (it is not a git install).")
		end
	end

	-- Shown on the player's first key press, the same moment the old out-of-date notice used, so the chat is actually on screen.
	-- It waits up to 10 seconds for the server's info; a server that never sends any is reported as such.
	hook.Add("InitPostEntity", "ACF Edition Notice", function()
		local Start = SysTime()

		hook.Add("CreateMove", "ACF Edition Notice", function(Move)
			if Move:GetButtons() == 0 then return end
			if not ACF.ServerExtensions and SysTime() - Start < 10 then return end

			hook.Remove("CreateMove", "ACF Edition Notice")
			PrintEditionNotice()
		end)

		hook.Remove("InitPostEntity", "ACF Edition Notice")
	end)
end
