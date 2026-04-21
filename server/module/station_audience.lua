local stationAudiences = {}

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

local function formatAudienceIds(list)
	if type(list) ~= "table" or #list <= 0 then
		return "none"
	end
	local parts = {}
	for i = 1, #list do
		parts[#parts + 1] = tostring(list[i])
	end
	return table.concat(parts, ",")
end

local function isPlayerOnline(source)
	local sid = tonumber(source) or 0
	if sid <= 0 then
		return false
	end
	local name = GetPlayerName(sid)
	return type(name) == 'string' and name ~= ''
end

local function normalizeAudienceKey(key)
	key = tostring(key or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if key == "" then
		return nil
	end
	return key
end

local function getAudience(key)
	local normalized = normalizeAudienceKey(key)
	if not normalized then
		return nil, nil
	end

	local audience = stationAudiences[normalized]
	if not audience then
		audience = {
			listeners = {},
			speakers = {}
		}
		stationAudiences[normalized] = audience
	end

	return normalized, audience
end

local function buildAudienceSpeakerList(audience, listenerSource)
	local speakers = {}
	if type(audience) ~= "table" then
		return speakers
	end

	for source, enabled in pairs(audience.speakers or {}) do
		local sid = tonumber(source) or 0
		if enabled and sid > 0 and sid ~= tonumber(listenerSource) and isPlayerOnline(sid) then
			speakers[#speakers + 1] = sid
		end
	end

	table.sort(speakers, function(a, b)
		return a < b
	end)

	return speakers
end

local function buildAudienceListenerList(audience, speakerSource)
	local listeners = {}
	if type(audience) ~= "table" then
		return listeners
	end

	for source, enabled in pairs(audience.listeners or {}) do
		local sid = tonumber(source) or 0
		if enabled and sid > 0 and sid ~= tonumber(speakerSource) and isPlayerOnline(sid) then
			listeners[#listeners + 1] = sid
		end
	end

	table.sort(listeners, function(a, b)
		return a < b
	end)

	return listeners
end

local function syncAudienceToListener(key, listenerSource)
	local audience = stationAudiences[key]
	if not audience then
		stationAudienceTrace('server-sync', 'speakers->listener key=%s listener=%s count=0', tostring(key), tostring(listenerSource))
		TriggerClientEvent('pma-voice:syncStationAudienceSpeakers', listenerSource, key, {})
		return
	end

	local speakerList = buildAudienceSpeakerList(audience, listenerSource)
	stationAudienceTrace('server-sync', 'speakers->listener key=%s listener=%s count=%s', tostring(key), tostring(listenerSource), tostring(countEnabledTargets(audience.speakers)))
	stationAudienceTrace('server-sync-detail', 'speakers->listener key=%s listener=%s speakers=%s', tostring(key), tostring(listenerSource), formatAudienceIds(speakerList))
	TriggerClientEvent(
		'pma-voice:syncStationAudienceSpeakers',
		listenerSource,
		key,
		speakerList
	)
end

local function syncAudienceToSpeaker(key, speakerSource)
	local audience = stationAudiences[key]
	if not audience then
		stationAudienceTrace('server-sync', 'listeners->speaker key=%s speaker=%s count=0', tostring(key), tostring(speakerSource))
		TriggerClientEvent('pma-voice:syncStationAudienceListeners', speakerSource, key, {})
		return
	end

	local listenerList = buildAudienceListenerList(audience, speakerSource)
	stationAudienceTrace('server-sync', 'listeners->speaker key=%s speaker=%s count=%s', tostring(key), tostring(speakerSource), tostring(countEnabledTargets(audience.listeners)))
	stationAudienceTrace('server-sync-detail', 'listeners->speaker key=%s speaker=%s listeners=%s', tostring(key), tostring(speakerSource), formatAudienceIds(listenerList))
	TriggerClientEvent(
		'pma-voice:syncStationAudienceListeners',
		speakerSource,
		key,
		listenerList
	)
end

local function refreshAudienceListeners(key)
	local audience = stationAudiences[key]
	if not audience then
		return
	end

	for source, enabled in pairs(audience.listeners or {}) do
		local sid = tonumber(source) or 0
		if enabled and sid > 0 and isPlayerOnline(sid) then
			syncAudienceToListener(key, sid)
		end
	end
end

local function refreshAudienceSpeakers(key)
	local audience = stationAudiences[key]
	if not audience then
		return
	end

	for source, enabled in pairs(audience.speakers or {}) do
		local sid = tonumber(source) or 0
		if enabled and sid > 0 and isPlayerOnline(sid) then
			syncAudienceToSpeaker(key, sid)
		end
	end
end

local function pruneAudienceIfEmpty(key)
	local audience = stationAudiences[key]
	if not audience then
		return
	end
	if next(audience.listeners) == nil and next(audience.speakers) == nil then
		stationAudiences[key] = nil
	end
end

function setStationAudienceListener(source, audienceKey, enabled)
	local key, audience = getAudience(audienceKey)
	if not key then
		return false
	end

	local sid = tonumber(source) or 0
	if not isPlayerOnline(sid) then
		return false
	end

	local nextEnabled = enabled == true
	if nextEnabled then
		audience.listeners[sid] = true
	else
		audience.listeners[sid] = nil
	end

	stationAudienceTrace('server-listener', 'key=%s source=%s enabled=%s total=%s', tostring(key), tostring(sid), tostring(nextEnabled), tostring(countEnabledTargets(audience.listeners)))
	stationAudienceTrace('server-listener-detail', 'key=%s listeners=%s', tostring(key), formatAudienceIds(buildAudienceListenerList(audience, 0)))
	syncAudienceToListener(key, sid)
	refreshAudienceSpeakers(key)
	pruneAudienceIfEmpty(key)
	return true
end

function setStationAudienceSpeakers(audienceKey, speakerServerIds)
	local key, audience = getAudience(audienceKey)
	if not key then
		return false
	end

	local nextSpeakers = {}
	if type(speakerServerIds) == 'table' then
		for i = 1, #speakerServerIds do
			local sid = tonumber(speakerServerIds[i]) or 0
			if isPlayerOnline(sid) then
				nextSpeakers[sid] = true
			end
		end
	end

	audience.speakers = nextSpeakers
	stationAudienceTrace('server-speakers', 'key=%s total=%s', tostring(key), tostring(countEnabledTargets(nextSpeakers)))
	stationAudienceTrace('server-speakers-detail', 'key=%s speakers=%s', tostring(key), formatAudienceIds(buildAudienceSpeakerList(audience, 0)))
	refreshAudienceListeners(key)
	refreshAudienceSpeakers(key)
	pruneAudienceIfEmpty(key)
	return true
end

exports('setStationAudienceListener', setStationAudienceListener)
exports('setStationAudienceSpeakers', setStationAudienceSpeakers)

RegisterNetEvent('pma-voice:setStationAudienceListener', function(audienceKey, enabled)
	setStationAudienceListener(source, audienceKey, enabled)
end)

AddEventHandler('playerDropped', function()
	local source = source
	for key, audience in pairs(stationAudiences) do
		local changed = false
		if audience.listeners[source] then
			audience.listeners[source] = nil
			changed = true
		end
		if audience.speakers[source] then
			audience.speakers[source] = nil
			changed = true
		end
		if changed then
			stationAudienceTrace('server-drop', 'source=%s key=%s listeners=%s speakers=%s', tostring(source), tostring(key), tostring(countEnabledTargets(audience.listeners)), tostring(countEnabledTargets(audience.speakers)))
			refreshAudienceListeners(key)
			refreshAudienceSpeakers(key)
			pruneAudienceIfEmpty(key)
		end
	end
end)
