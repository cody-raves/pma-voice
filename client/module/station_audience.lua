local stationAudienceSubscriptions = {}
local stationAudienceSpeakerData = {}
local stationAudienceListenerData = {}

local function countEnabledTargets(tbl)
	local count = 0
	if type(tbl) ~= "table" then
		return 0
	end
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

local function formatTargetIds(targets)
	if type(targets) ~= "table" then
		return "none"
	end
	local ids = {}
	for serverId, enabled in pairs(targets) do
		local sid = tonumber(serverId) or 0
		if enabled and sid > 0 then
			ids[#ids + 1] = sid
		end
	end
	if #ids <= 0 then
		return "none"
	end
	table.sort(ids, function(a, b)
		return a < b
	end)
	for i = 1, #ids do
		ids[i] = tostring(ids[i])
	end
	return table.concat(ids, ",")
end

local function normalizeAudienceKey(key)
	key = tostring(key or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if key == "" then
		return nil
	end
	return key
end

local function rebuildStationAudienceMonitorTargets()
	local nextTargets = {}

	for _, speakers in pairs(stationAudienceSpeakerData) do
		if type(speakers) == "table" then
			for serverId, enabled in pairs(speakers) do
				local sid = tonumber(serverId) or 0
				if enabled and sid > 0 and sid ~= playerServerId then
					nextTargets[sid] = true
				end
			end
		end
	end

	for sid, _ in pairs(stationAudienceMonitorTargets) do
		if not nextTargets[sid] then
			if not radioData[sid] and not callData[sid] then
				toggleVoice(sid, false, 'call')
			end
		end
	end

	for sid, _ in pairs(nextTargets) do
		if not stationAudienceMonitorTargets[sid] then
			toggleVoice(sid, true, 'call')
		end
	end

	stationAudienceMonitorTargets = nextTargets
	stationAudienceTrace('client-monitor', 'rebuilt monitor targets count=%s', tostring(countEnabledTargets(nextTargets)))
	stationAudienceTrace('client-monitor-detail', 'targets=%s', formatTargetIds(nextTargets))
end

local function rebuildStationAudienceTransmitTargets()
	local nextTargets = {}

	for _, listeners in pairs(stationAudienceListenerData) do
		if type(listeners) == "table" then
			for serverId, enabled in pairs(listeners) do
				local sid = tonumber(serverId) or 0
				if enabled and sid > 0 and sid ~= playerServerId then
					nextTargets[sid] = true
				end
			end
		end
	end

	stationAudienceTransmitTargets = nextTargets
	stationAudienceTrace('client-transmit', 'rebuilt transmit targets count=%s', tostring(countEnabledTargets(nextTargets)))
	stationAudienceTrace('client-transmit-detail', 'targets=%s', formatTargetIds(nextTargets))
	rebuildVoiceTargetPlayers()
end

RegisterNetEvent('pma-voice:syncStationAudienceSpeakers', function(audienceKey, speakers)
	local key = normalizeAudienceKey(audienceKey)
	if not key then
		return
	end

	local nextSpeakers = {}
	if type(speakers) == "table" then
		for i = 1, #speakers do
			local sid = tonumber(speakers[i]) or 0
			if sid > 0 and sid ~= playerServerId then
				nextSpeakers[sid] = true
			end
		end
	end

	stationAudienceSpeakerData[key] = nextSpeakers
	stationAudienceTrace('client-sync', 'speakers key=%s count=%s', tostring(key), tostring(countEnabledTargets(nextSpeakers)))
	stationAudienceTrace('client-sync-detail', 'speakers key=%s targets=%s', tostring(key), formatTargetIds(nextSpeakers))
	rebuildStationAudienceMonitorTargets()
end)

RegisterNetEvent('pma-voice:syncStationAudienceListeners', function(audienceKey, listeners)
	local key = normalizeAudienceKey(audienceKey)
	if not key then
		return
	end

	local nextListeners = {}
	if type(listeners) == "table" then
		for i = 1, #listeners do
			local sid = tonumber(listeners[i]) or 0
			if sid > 0 and sid ~= playerServerId then
				nextListeners[sid] = true
			end
		end
	end

	stationAudienceListenerData[key] = nextListeners
	stationAudienceTrace('client-sync', 'listeners key=%s count=%s', tostring(key), tostring(countEnabledTargets(nextListeners)))
	stationAudienceTrace('client-sync-detail', 'listeners key=%s targets=%s', tostring(key), formatTargetIds(nextListeners))
	rebuildStationAudienceTransmitTargets()
end)

local function setStationAudienceListener(audienceKey, enabled)
	local key = normalizeAudienceKey(audienceKey)
	if not key then
		return
	end

	local nextEnabled = enabled == true
	if stationAudienceSubscriptions[key] == nextEnabled then
		return
	end

	stationAudienceSubscriptions[key] = nextEnabled
	stationAudienceTrace('client-sub', 'listener key=%s enabled=%s', tostring(key), tostring(nextEnabled))
	TriggerServerEvent('pma-voice:setStationAudienceListener', key, nextEnabled)

	if not nextEnabled then
		stationAudienceSpeakerData[key] = {}
		stationAudienceListenerData[key] = {}
		rebuildStationAudienceMonitorTargets()
		rebuildStationAudienceTransmitTargets()
	end
end

exports('setStationAudienceListener', setStationAudienceListener)
exports('SetStationAudienceListener', setStationAudienceListener)

AddEventHandler('onClientResourceStart', function(resource)
	if resource ~= GetCurrentResourceName() then
		return
	end
	stationAudienceTrace('client-start', 'station audience module ready player=%s', tostring(playerServerId))
end)

AddEventHandler('onClientResourceStop', function(resource)
	if resource ~= GetCurrentResourceName() then
		return
	end

	for key, enabled in pairs(stationAudienceSubscriptions) do
		if enabled then
			TriggerServerEvent('pma-voice:setStationAudienceListener', key, false)
		end
	end
end)
