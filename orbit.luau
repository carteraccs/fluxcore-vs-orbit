--[[
 ____  _                  _                      __ ____  
|  _ \| | __ _ _ __   ___| |_ __ _ _ __ _   _   / // __ \ 
| |_) | |/ _` | '_ \ / _ \ __/ _` | '__| | | | / // / _` |
|  __/| | (_| | | | |  __/ || (_| | |  | |_| | \ \ | (_| |
|_|   |_|\__,_|_| |_|\___|\__\__,_|_|   \__, |  \_\ \__,_|
            _     _ _                   |___/      \____/ 
  ___  _ __| |__ (_) |_                                   
 / _ \| '__| '_ \| | __|                                  
| (_) | |  | |_) | | |_                                   
 \___/|_|  |_.__/|_|\__|       
 
 Hii! Thank you for using Planetary | Sessions Board! @TiiLxm
]]

local Config = require(script.Parent)
local httpservice = game:GetService("HttpService")
local Player = game:GetService("Players")
local Screen = script.Parent.Parent.Screen.SurfaceGui
local SessionsScreen = Screen.Sessions
local NoPlanned = Screen.NoPlanned
local ErrorScreen = Screen.ErrorScreen
local SessionFrame = SessionsScreen.ScrollingFrame.SessionFrame.Frame
local type = ""
local rn = DateTime.now()
local tomorrow = DateTime.fromUnixTimestamp(rn.UnixTimestamp + (86400))

local httperrors = {
	[100] = "Continue", [101] = "Switching Protocols", [102] = "Processing", [103] = "Early Hints",
	[200] = "OK", [201] = "Created", [202] = "Accepted", [203] = "Non-Authoritative Information",
	[204] = "No Content", [205] = "Reset Content", [206] = "Partial Content", [207] = "Multi-Status",
	[208] = "Already Reported", [226] = "IM Used",
	[300] = "Multiple Choices", [301] = "Moved Permanently", [302] = "Found", [303] = "See Other",
	[304] = "Not Modified", [305] = "Use Proxy", [307] = "Temporary Redirect", [308] = "Permanent Redirect",
	[400] = "Bad Request", [401] = "Unauthorized", [402] = "Payment Required", [403] = "Forbidden",
	[404] = "Not Found", [405] = "Method Not Allowed", [406] = "Not Acceptable",
	[407] = "Proxy Authentication Required", [408] = "Request Timeout", [409] = "Conflict",
	[410] = "Gone", [411] = "Length Required", [412] = "Precondition Failed", [413] = "Content Too Large",
	[414] = "URI Too Long", [415] = "Unsupported Media Type", [416] = "Range Not Satisfiable",
	[417] = "Expectation Failed", [418] = "I'm a teapot", [421] = "Misdirected Request",
	[422] = "Unprocessable Content", [423] = "Locked", [424] = "Failed Dependency", [425] = "Too Early",
	[426] = "Upgrade Required", [428] = "Precondition Required", [429] = "Too Many Requests",
	[431] = "Request Header Fields Too Large", [451] = "Unavailable For Legal Reasons",
	[500] = "Internal Server Error", [501] = "Not Implemented", [502] = "Bad Gateway",
	[503] = "Service Unavailable", [504] = "Gateway Timeout", [505] = "HTTP Version Not Supported",
	[506] = "Variant Also Negotiates", [507] = "Insufficient Storage", [508] = "Loop Detected",
	[510] = "Not Extended", [511] = "Network Authentication Required",
}

local function LogService(report: string, type: "warn" | "info")
	local Time = DateTime.now():FormatUniversalTime("HH:mm:ss", "en-us")
	if not report then warn("[" .. Time .." - Sessions Board]: Nothing to report!") return end
	if not type then warn("[" .. Time .." - Sessions Board]: Type of report not chosen!") return end

	if type == "warn" then
		warn("[" .. Time .." - Sessions Board]: " .. report)
	else
		print("[" .. Time .." - Sessions Board]: " .. report)
	end
end

if not httpservice.HttpEnabled then
	error("[Planetary | Sessions Board] HTTP requests disabled. Enable in Game Settings > Security > Allow HTTP requests.")
end

if #Config.api_key == 0 then
	LogService("API key hasn't been set.", "warn")
	return
end

if #Config.baseurl == 0 then
	LogService("Base URL hasn't been set.", "warn")
	return
end

if #Config.workspace_id == 0 then
	LogService("Workspace ID hasn't been set.", "warn")
	return
end

if #Config.event_type == 0 then
	LogService("Event type hasn't been set.", "warn")
	return
end

if not Config.renew_sessions then
	LogService("Renew sessions hasn't been set.", "warn")
	return
end

if not Config.duration then
	LogService("Session duration hasn't been set.", "warn")
	return
end

if #Config.clock_format == 0 then
	LogService("Clock format hasn't been set.", "warn")
	return
end

if string.lower(Config.event_type) == "event" then
	type = "events"
elseif string.lower(Config.event_type) == "shift" then
	type = "shifts"
elseif string.lower(Config.event_type) == "training" then
	type = "trainings"
else
	type = "sessions"
end

local function isAllowedSessionType(sessionCategory)
	local selectedFilter = string.lower(Config.event_type)
	if selectedFilter == "all" then
		return true
	end
	local normalizedCategory = string.lower(sessionCategory or "")
	return normalizedCategory == selectedFilter
end

local function isLive(currentTime, startTime): boolean
	local endtime = startTime + (Config.duration * 60)
	return currentTime >= startTime and currentTime <= endtime
end

local function formatTimeRemaining(seconds)
	if seconds <= 0 then
		return "Occurring"
	end

	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60

	if days > 0 then
		return string.format("%dd %dh %dm", days, hours, minutes)
	elseif hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm %ds", minutes, secs)
	else
		return string.format("%ds", secs)
	end
end

local function GetInstance()
	local Payload = {
		Url = Config.baseurl .. "api/public/v1/workspace/" .. Config.workspace_id .."/info",
		Method = "GET",
		Headers = {
			["Content-Type"] = "application/json",
			["Authorization"] = "Bearer " .. Config.api_key
		}
	}

	local success, response = pcall(function()
		return httpservice:RequestAsync(Payload)
	end)

	if success and response.StatusCode == 200 then
		LogService("Successfully connected to Planetary API", "info")
		return httpservice:JSONDecode(response.Body)
	else
		LogService("Failed to connect to Planetary API: " .. tostring(response), "warn")
		return nil
	end
end

local function getSessions()
	local startDate = rn:FormatUniversalTime("YYYY-MM-DDT00:00:00Z", "en-us")
	local endDate = tomorrow:FormatUniversalTime("YYYY-MM-DDTHH:mm:ssZ", "en-us")

	local categoryParam = string.lower(Config.event_type) ~= "all" 
		and ("&category=" .. string.lower(Config.event_type)) 
		or ""

	local Payload = {
		Url = Config.baseurl .. "api/public/v1/workspace/" .. Config.workspace_id 
			.. "/sessions/calendar?startDate=" .. startDate .. "&endDate=" .. endDate .. categoryParam,
		Method = "GET",
		Headers = {
			["Authorization"] = "Bearer " .. Config.api_key
		}
	}

	for attempt = 1, 3 do
		local success, response = pcall(function() 
			return httpservice:RequestAsync(Payload) 
		end)

		if success and response.Success then
			local decodeSuccess, decoded = pcall(function() 
				return httpservice:JSONDecode(response.Body) 
			end)

			if decodeSuccess then
				LogService("Successfully fetched " .. #(decoded.sessions or {}) .. " sessions", "info")
				return decoded.sessions or {}
			end

			LogService("Failed to decode response on attempt " .. attempt, "warn")
		else
			LogService("Failed to fetch data on attempt " .. attempt .. ": " .. tostring(response), "warn")

			if not success or not response.Success then
				ErrorScreen.Visible = true
				local decodeSuccess, decoded = pcall(function() 
					return httpservice:JSONDecode(response.Body) 
				end)

				if decodeSuccess then
					ErrorScreen.ErrorLabel.Text = response.StatusCode 
						.. " (" .. httperrors[response.StatusCode] or nil .. ") - " .. decoded.error or nil
				else
					ErrorScreen.ErrorLabel.Text = response.StatusCode 
						.. " (" .. httperrors[response.StatusCode] or nil .. ") - Unable to grab response error"
				end
			end
		end

		task.wait(1)
	end

	return {}
end

local function InitTopbar()
	local sessionTypeText = ({
		shift = "Upcoming Shifts",
		training = "Upcoming Trainings",
		event = "Upcoming Events",
		all = "Upcoming Sessions"
	})[string.lower(Config.event_type)] or "Upcoming Sessions"

	SessionsScreen.Topbar.Left.SessionType.Text = sessionTypeText
end

local function getCohostInfo(userId)
	local payload = {
		Url = "https://users.roproxy.com/v1/users/" .. userId,
		Method = "GET"
	}

	local success, response = pcall(function()
		return httpservice:RequestAsync(payload)
	end)

	if success and response.Success then
		local decodeSuccess, decoded = pcall(function() 
			return httpservice:JSONDecode(response.Body) 
		end)

		if decodeSuccess then
			print(decoded)
			return decoded
		end
	end

	return nil
end

local function createSessionFrame(session)
	local newSession = SessionFrame:Clone()
	newSession.TextButton.Visible = false

	if session.host then
		local hostSuccess, hostInfo = pcall(function()
			return Player:GetNameFromUserIdAsync(session.host.userId)
		end)

		if hostSuccess then
			newSession.Hosts.Host.TextLabel.Text = "Host: " .. hostInfo
			newSession.Hosts.Host.hostImage.ImageLabel.Image = 
				Player:GetUserThumbnailAsync(session.host.userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size352x352)
		end
	else
		newSession.Hosts.Host.TextLabel.Text = "UNCLAIMED"
		newSession.Hosts.Host.hostImage.ImageLabel.Image = 
			Player:GetUserThumbnailAsync(1, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size352x352)
	end

	if session.participants and #session.participants > 0 then
		local cohostData = getCohostInfo(session.participants[1].userId)

		if cohostData then
			local rest = ""
			if #session.participants > 1 then
				rest = ", and " .. (#session.participants - 1) .. " other cohost" 
					.. (#session.participants > 2 and "s" or "") .. "."
			end

			newSession.Hosts.Cohost.TextLabel.Text = "Cohost: " .. cohostData.name .. rest
			newSession.Hosts.Cohost.CohostImage.ImageLabel.Image = 
				Player:GetUserThumbnailAsync(cohostData.id, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size352x352)
		else
			newSession.Hosts.Cohost:Destroy()
		end
	else
		newSession.Hosts.Cohost:Destroy()
	end

	local sessionStartTime = DateTime.fromIsoDate(session.date).UnixTimestamp
	local currentTime = DateTime.now().UnixTimestamp
	local timeUntilStart = sessionStartTime - currentTime

	if not (game.GameId == session.type.gameId) and session.host then
		if (Config.join_button.appear_before_start >= timeUntilStart / 60) and (session.status == "scheduled") then
			newSession.TextButton.Visible = true
			newSession.TextButton:SetAttribute("placeid", session.type.gameId)
		elseif session.status == "started" then
			newSession.TextButton.Visible = true
			newSession.TextButton.Interactable = false
			newSession.TextButton.BackgroundColor = Color3.new(0.211765, 0.211765, 0.211765)
			newSession.TextButton.Text = "LOCKED"
		end
		newSession.TextButton.Script.Enabled = true
	end

	if not isLive(currentTime, sessionStartTime) then
		newSession.LiveFrame:Destroy()
	end

	if timeUntilStart > 0 then
		local timeText = formatTimeRemaining(timeUntilStart)
		newSession.EventTime.Text = "This session will start in " .. timeText
		newSession.EventTime:SetAttribute("time", session.date)
		newSession.EventTime.Script.Enabled = true
	else
		newSession.EventTime.Text = "Occurring now"
	end

	newSession.EventInfo.EventName.Text = session.name
	return newSession
end

local function PopulateSessions()
	for _, child in pairs(SessionsScreen.ScrollingFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	NoPlanned.Visible = false
	ErrorScreen.Visible = false

	local sessions = getSessions()
	local displayedCount = 0

	for _, session in pairs(sessions) do
		if Config.only_show_claimed then
			if not session.host then
				continue
			end
		end

		local sessionStartTime = DateTime.fromIsoDate(session.date).UnixTimestamp
		local sessionEndTime = sessionStartTime + (Config.duration * 60)
		local currentTime = DateTime.now().UnixTimestamp

		if currentTime > sessionEndTime then
			continue
		end

		local sessionCategory = session.type.category
		
		if isAllowedSessionType(sessionCategory) then
			local sessionFrame = createSessionFrame(session)
			sessionFrame.Parent = SessionsScreen.ScrollingFrame
			sessionFrame.Visible = true
			displayedCount = displayedCount + 1
		end
	end

	if displayedCount == 0 then
		NoPlanned.Visible = true
		NoPlanned.TextLabel.Text = "Woah! No " .. type .. "?"
		LogService("No sessions to display", "info")
	end
end

local function Init()
	local success, err = pcall(function()
		
		local PlaceHolder = Screen:WaitForChild("Placeholder")
		if PlaceHolder then
			PlaceHolder:Destroy()
		end
		Screen.Sessions.Visible = true
		Screen.NoPlanned.Visible = false
		Screen.ErrorScreen.Visible = false

		local Instance = GetInstance()
		InitTopbar()
		SessionsScreen.Lowbar.TextLabel.Text = "This board will update every " .. Config.renew_sessions .. " seconds"

		while true do
			PopulateSessions()
			task.wait(Config.renew_sessions)
		end
	end)

	if not success then
		LogService("Error occurred: " .. tostring(err), "warn")
		ErrorScreen.Visible = true
		ErrorScreen.ErrorLabel.Text = "An internal error occurred while running the board.\n" .. tostring(err)

		task.wait(30)
		Init()
	end
end

Init()
