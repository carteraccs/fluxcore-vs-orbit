--[[
Credits to Planetary for their System

Reconfigured to be used for Fluxcore.
]]

local Config = require(script.Parent)
local httpservice = game:GetService("HttpService")
local Player = game:GetService("Players")

local Screen = script.Parent.Parent.Screen.SurfaceGui
local SessionsScreen = Screen.Sessions
local NoPlanned = Screen.NoPlanned
local ErrorScreen = Screen.ErrorScreen
local SessionFrame = SessionsScreen.ScrollingFrame.SessionFrame.Frame

local typeLabel = ""

local httperrors = {
	[200] = "OK", [400] = "Bad Request", [401] = "Unauthorized", [403] = "Forbidden",
	[404] = "Not Found", [429] = "Too Many Requests", [500] = "Internal Server Error",
	[502] = "Bad Gateway", [503] = "Service Unavailable", [504] = "Gateway Timeout",
}

local function LogService(report: string, kind: "warn" | "info")
	local Time = DateTime.now():FormatUniversalTime("HH:mm:ss", "en-us")
	if kind == "warn" then
		warn("[" .. Time .. " - Fluxcore Sessions]: " .. tostring(report))
	else
		print("[" .. Time .. " - Fluxcore Sessions]: " .. tostring(report))
	end
end

if not httpservice.HttpEnabled then
	error("[Fluxcore | Sessions] HTTP requests disabled. Enable in Game Settings > Security.")
end

if #Config.api_key == 0 then LogService("API key hasn't been set.", "warn") return end
if #Config.baseurl == 0 then LogService("Base URL hasn't been set.", "warn") return end
if #Config.event_type == 0 then LogService("Event type hasn't been set.", "warn") return end
if not Config.renew_sessions then LogService("Renew sessions hasn't been set.", "warn") return end
if not Config.duration then LogService("Session duration hasn't been set.", "warn") return end
if #Config.clock_format == 0 then LogService("Clock format hasn't been set.", "warn") return end

local et = string.lower(Config.event_type)
if et == "event" then typeLabel = "events"
elseif et == "shift" then typeLabel = "shifts"
elseif et == "training" then typeLabel = "trainings"
else typeLabel = "sessions" end

local function isAllowedSessionType(sessionCategory)
	local selectedFilter = string.lower(Config.event_type)
	if selectedFilter == "all" then return true end
	return string.lower(sessionCategory or "") == selectedFilter
end

local function isLive(currentTime, startTime, duration): boolean
	local endtime = startTime + (duration * 60)
	return currentTime >= startTime and currentTime <= endtime
end

local function formatTimeRemaining(seconds)
	if seconds <= 0 then return "Occurring" end
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

local function getSessions()
	local categoryParam = string.lower(Config.event_type) ~= "all"
		and ("?category=" .. string.lower(Config.event_type) .. "&today=true")
		or "?today=true"

	-- Fluxcore endpoint: https://fluxcore.works/api/v1/sessions
	local Payload = {
		Url = Config.baseurl .. "sessions" .. categoryParam,
		Method = "GET",
		Headers = {
			["x-api-key"] = Config.api_key,
			["Content-Type"] = "application/json",
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
			if decodeSuccess and type(decoded) == "table" then
				local list = decoded.sessions or {}
				LogService("Successfully fetched " .. #list .. " sessions", "info")
				return list
			end
			LogService("Failed to decode response on attempt " .. attempt, "warn")
		else
			LogService("Failed to fetch on attempt " .. attempt .. ": " .. tostring(response and response.StatusMessage or "no response"), "warn")
			if success and not response.Success then
				ErrorScreen.Visible = true
				local code = response.StatusCode
				local msg = httperrors[code] or "Unknown"
				local body = ""
				local ok, decoded = pcall(function() return httpservice:JSONDecode(response.Body) end)
				if ok and decoded and decoded.error then body = " - " .. tostring(decoded.error) end
				ErrorScreen.ErrorLabel.Text = tostring(code) .. " (" .. msg .. ")" .. body
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

local function safeThumbnail(userId)
	local ok, img = pcall(function()
		return Player:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size352x352)
	end)
	if ok then return img end
	return ""
end

local function createSessionFrame(session)
	local newSession = SessionFrame:Clone()
	newSession.TextButton.Visible = false

	-- Host
	if session.host and session.host.userId then
		newSession.Hosts.Host.TextLabel.Text = "Host: " .. tostring(session.host.username or "Unknown")
		newSession.Hosts.Host.hostImage.ImageLabel.Image = safeThumbnail(session.host.userId)
	else
		newSession.Hosts.Host.TextLabel.Text = "UNCLAIMED"
		newSession.Hosts.Host.hostImage.ImageLabel.Image = safeThumbnail(1)
	end

	-- Co-host / participants
	if session.participants and #session.participants > 0 then
		local first = session.participants[1]
		local rest = ""
		if #session.participants > 1 then
			rest = ", and " .. (#session.participants - 1) .. " other"
				.. (#session.participants > 2 and "s" or "") .. "."
		end
		newSession.Hosts.Cohost.TextLabel.Text = "Cohost: " .. first.username .. rest
		newSession.Hosts.Cohost.CohostImage.ImageLabel.Image = safeThumbnail(first.userId)
	else
		if newSession.Hosts:FindFirstChild("Cohost") then
			newSession.Hosts.Cohost:Destroy()
		end
	end

	local sessionStartTime = DateTime.fromIsoDate(session.date).UnixTimestamp
	local currentTime = DateTime.now().UnixTimestamp
	local timeUntilStart = sessionStartTime - currentTime
	local duration = session.duration or Config.duration
	local gameId = session.type and session.type.gameId or 0

	if gameId ~= 0 and game.GameId ~= gameId and session.host then
		if (Config.join_button.appear_before_start >= timeUntilStart / 60) and (session.status == "scheduled") then
			newSession.TextButton.Visible = true
			newSession.TextButton:SetAttribute("placeid", gameId)
		elseif session.status == "started" then
			newSession.TextButton.Visible = true
			newSession.TextButton.Interactable = false
			newSession.TextButton.BackgroundColor3 = Color3.new(0.211765, 0.211765, 0.211765)
			newSession.TextButton.Text = "LOCKED"
		end
		if newSession.TextButton:FindFirstChild("Script") then
			newSession.TextButton.Script.Enabled = true
		end
	end

	if not isLive(currentTime, sessionStartTime, duration) then
		if newSession:FindFirstChild("LiveFrame") then
			newSession.LiveFrame:Destroy()
		end
	end

	if timeUntilStart > 0 then
		local timeText = formatTimeRemaining(timeUntilStart)
		newSession.EventTime.Text = "This session will start in " .. timeText
		newSession.EventTime:SetAttribute("time", session.date)
		if newSession.EventTime:FindFirstChild("Script") then
			newSession.EventTime.Script.Enabled = true
		end
	else
		newSession.EventTime.Text = "Occurring now"
	end

	newSession.EventInfo.EventName.Text = session.name
	return newSession
end

local function PopulateSessions()
	for _, child in pairs(SessionsScreen.ScrollingFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	NoPlanned.Visible = false
	ErrorScreen.Visible = false

	local sessions = getSessions()
	local displayedCount = 0

	for _, session in pairs(sessions) do
		if Config.only_show_claimed and not session.host then
			continue
		end
		local sessionStartTime = DateTime.fromIsoDate(session.date).UnixTimestamp
		local duration = session.duration or Config.duration
		local sessionEndTime = sessionStartTime + (duration * 60)
		local currentTime = DateTime.now().UnixTimestamp
		if currentTime > sessionEndTime then continue end

		local sessionCategory = session.type and session.type.category or session.category
		if isAllowedSessionType(sessionCategory) then
			local sessionFrame = createSessionFrame(session)
			sessionFrame.Parent = SessionsScreen.ScrollingFrame
			sessionFrame.Visible = true
			displayedCount += 1
		end
	end

	if displayedCount == 0 then
		NoPlanned.Visible = true
		NoPlanned.TextLabel.Text = "Woah! No " .. typeLabel .. " today?"
		LogService("No sessions to display", "info")
	end
end

local function Init()
	local success, err = pcall(function()
		local PlaceHolder = Screen:FindFirstChild("Placeholder")
		if PlaceHolder then PlaceHolder:Destroy() end
		Screen.Sessions.Visible = true
		Screen.NoPlanned.Visible = false
		Screen.ErrorScreen.Visible = false
		InitTopbar()
		SessionsScreen.Lowbar.TextLabel.Text = "This board updates every " .. Config.renew_sessions .. " seconds"
		while true do
			PopulateSessions()
			task.wait(Config.renew_sessions)
		end
	end)
	if not success then
		LogService("Error: " .. tostring(err), "warn")
		ErrorScreen.Visible = true
		ErrorScreen.ErrorLabel.Text = "An internal error occurred.\n" .. tostring(err)
		task.wait(30)
		Init()
	end
end

Init()
