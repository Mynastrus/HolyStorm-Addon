local addonVersion = "2.4.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Dungeons")

local SNAPSHOT_VERSION = 5

local function isSecret(value)
	if issecretvalue then
		local ok, secret = pcall(issecretvalue, value)
		if not ok or secret == true then return true end
	end
	return false
end

local function safeNumber(value, minimum, integer)
	if isSecret(value) or value == nil or type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
	if minimum ~= nil and value < minimum then return nil end
	if integer and value % 1 ~= 0 then return nil end
	return value
end

local function safeString(value)
	if isSecret(value) or value == nil or type(value) ~= "string" or value == "" then return nil end
	return value
end

local function safeCall(fn, ...)
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end

local function safeArray(values, integerMinimum)
	if isSecret(values) or type(values) ~= "table" then return nil end
	local result = {}
	for index, value in ipairs(values) do
		local number = safeNumber(value, integerMinimum or 0, true)
		if not number then return nil end
		result[index] = number
	end
	return result
end

local function safeDate(value)
	if isSecret(value) or type(value) ~= "table" then return nil end
	-- Current Retail MapSeasonBestInfo uses CalendarTime.monthDay. Older
	-- MythicPlusDate snapshots used day; normalize both to the stored `day` key.
	local dayValue = value.monthDay
	if dayValue == nil then dayValue = value.day end
	local day = safeNumber(dayValue, 1, true)
	if not day then return nil end
	local result = {}
	for _, key in ipairs({ "year", "month", "day", "hour", "minute", "weekday" }) do
		local number = key == "day" and day or safeNumber(value[key], 0, true)
		if not number then return nil end
		result[key] = number
	end
	return result
end

local function safeRun(value, overTime)
	if isSecret(value) then return false, "SECRET_BEST_RUN" end
	if value == nil then return nil end
	if type(value) ~= "table" then return false, "INVALID_BEST_RUN" end
	local level = safeNumber(value.level, 0, true)
	local score = safeNumber(value.dungeonScore, 0)
	if score == nil then score = safeNumber(value.score, 0) end
	local duration = safeNumber(value.durationSec, 0)
	local date = safeDate(value.completionDate)
	local affixIDs = safeArray(value.affixIDs, 1)
	if not level or not score or not duration or not date or not affixIDs then
		if not date then return false, "INVALID_BEST_RUN_COMPLETION_DATE" end
		if not level or not score or not duration then return false, "INVALID_BEST_RUN_FIELDS" end
		return false, "INVALID_BEST_RUN_AFFIXES"
	end
	return {
		level = level,
		score = score,
		durationSec = duration,
		completionDate = date,
		affixIDs = affixIDs,
		overTime = overTime,
	}
end

local function safeAffixScores(values)
	if isSecret(values) or type(values) ~= "table" then return nil end
	local result = {}
	for _, value in ipairs(values) do
		if isSecret(value) or type(value) ~= "table" then return nil end
		local score = safeNumber(value.score, 0)
		local level = safeNumber(value.level, 0, true)
		local duration = safeNumber(value.durationSec, 0)
		if not score or not level or not duration then return nil end
		local entry = { score = score, level = level, durationSec = duration }
		local name = safeString(value.name)
		if name then entry.name = name end
		if type(value.overTime) == "boolean" and not isSecret(value.overTime) then entry.overTime = value.overTime end
		result[#result + 1] = entry
	end
	return result
end

local function validVault(vault, weeklyIdentity)
	if vault == nil then return true end
	if type(vault) ~= "table" or vault.currentPeriod ~= true or not weeklyIdentity then return false end
	if type(vault.activities) ~= "table" or not safeNumber(vault.progress, 0, true) then return false end
	local ids, indexes, completed, count = {}, {}, {}, 0
	for _, activity in ipairs(vault.activities) do
		if type(activity) ~= "table" then return false end
		local id = safeNumber(activity.id, 1, true)
		local index = safeNumber(activity.index, 1, true)
		local progress = safeNumber(activity.progress, 0)
		local threshold = safeNumber(activity.threshold, 0)
		local level = safeNumber(activity.level, 0, true)
		if not id or not index or not progress or not threshold or not level or ids[id] or indexes[index] then return false end
		ids[id], indexes[index] = true, true
		count = count + 1
		if progress >= threshold then completed[index] = true end
	end
	local completedCount = 0
	for _ in pairs(completed) do completedCount = completedCount + 1 end
	return vault.progress == completedCount and count == #vault.activities
end

local function validateMythicPlus(data, collectionReason, collectionDiagnostics)
	if isSecret(data) or type(data) ~= "table" then
		if collectionReason then return false, collectionReason, collectionDiagnostics and collectionDiagnostics.retryable == true end
		return false, "INVALID_MYTHICPLUS_DATA", false
	end
	if data.schemaVersion ~= SNAPSHOT_VERSION or data.snapshotVersion ~= SNAPSHOT_VERSION then return false, "UNSUPPORTED_MYTHICPLUS_SCHEMA", false end
	if not safeNumber(data.seasonId, 1, true) then return false, "UNKNOWN_MYTHICPLUS_SEASON", true end
	if data.displaySeasonId ~= nil and not safeNumber(data.displaySeasonId, 1, true) then return false, "INVALID_MYTHICPLUS_DISPLAY_SEASON", false end
	if not safeNumber(data.overallScore, 0) then return false, "UNKNOWN_MYTHICPLUS_RATING", true end
	if data.poolComplete ~= true or type(data.dungeons) ~= "table" or #data.dungeons == 0 or data.dungeonCount ~= #data.dungeons then return false, "INCOMPLETE_MYTHICPLUS_POOL", true end
	if type(data.scoreDataReady) ~= "boolean" or not data.scoreDataReady then return false, "INCOMPLETE_MYTHICPLUS_SCORES", true end
	local seen, count = {}, 0
	for _, dungeon in ipairs(data.dungeons) do
		if isSecret(dungeon) or type(dungeon) ~= "table" then return false, "INVALID_MYTHICPLUS_DUNGEON", false end
		local id = safeNumber(dungeon.challengeMapId, 1, true)
		if not id or seen[id] then return false, "INVALID_OR_DUPLICATE_MYTHICPLUS_MAP", false end
		seen[id] = true
		if not safeString(dungeon.name) or not safeNumber(dungeon.instanceId, 1, true) or not safeNumber(dungeon.mapId, 1, true) or not safeNumber(dungeon.timeLimit, 1) then return false, "INCOMPLETE_MYTHICPLUS_MAP", true end
		if not safeNumber(dungeon.score, 0) then return false, "INCOMPLETE_MYTHICPLUS_DUNGEON_SCORE", true end
		if dungeon.affixScores ~= nil and type(dungeon.affixScores) ~= "table" then return false, "INVALID_MYTHICPLUS_AFFIX_SCORES", false end
		for _, field in ipairs({ "bestInTime", "bestOverTime" }) do
			local run = dungeon[field]
			if run ~= nil then
				local validRun, runReason = safeRun(run)
				if validRun == false then return false, runReason or "INVALID_MYTHICPLUS_BEST_RUN", false end
			end
		end
		for _, score in ipairs(dungeon.affixScores or {}) do
			if type(score) ~= "table" or not safeNumber(score.score, 0) or not safeNumber(score.level, 0, true) or not safeNumber(score.durationSec, 0) then return false, "INVALID_MYTHICPLUS_AFFIX_SCORE", false end
		end
		count = count + 1
	end
	if count ~= data.dungeonCount then return false, "INCOMPLETE_MYTHICPLUS_POOL", true end
	local week = data.weeklyIdentity
	if week ~= nil and not safeNumber(week, 1, true) then return false, "INVALID_MYTHICPLUS_WEEK", false end
	if not validVault(data.greatVaultMythicPlus, week) then return false, "INVALID_MYTHICPLUS_VAULT", false end
	return true
end

if HolyStorm.PlayerData then
	HolyStorm.PlayerData:RegisterBlock("mythicPlus", {
		fields = { "mythicPlus" }, event = "HS_MYTHICPLUS_UPDATED", staleAfter = 21600,
		owner = "mythicPlus", schemaVersion = SNAPSHOT_VERSION, snapshotVersion = SNAPSHOT_VERSION,
		capability = "character.scan.mythicplus", scanProvider = "mythicPlus", validate = validateMythicPlus,
	})
end

local metadata = {
	id = "mythicPlus", name = "MythicPlus", displayName = L["DISPLAY_NAME"], description = L["DESCRIPTION"],
	version = addonVersion, moduleType = "feature", category = "feature",
	permissions = { "sync-send", "sync-receive" }, dependencies = { "core" },
	capabilities = { "character.scan.mythicplus" }, ui = {}, options = {}, administration = {},
	data = { block = "mythicPlus", snapshotType = "mythicplus", schemaVersion = SNAPSHOT_VERSION, capability = "character.scan.mythicplus" },
	sync = { domains = { "character" } }, enabledByDefault = true,
	ruleFields = {{
		id="mythicplus.rating", aliases = { "mythicScore" }, type = "number", name = L["RULE_FIELD_RATING"],
		nameKey = "RULE_FIELD_RATING", description = L["RULE_FIELD_RATING_DESC"], descriptionKey = "RULE_FIELD_RATING_DESC",
		category = L["DISPLAY_NAME"], dependencies = { "mythicPlus" }, unit = "rating",
		resolver = function(context)
			local block = context.character and context.character.mythicPlus or HolyStorm.Data.CharacterStore:GetBlock(context.characterUUID, "mythicPlus")
			return block and safeNumber(block.overallScore, 0) or nil
		end,
	}},
}

local function captureVault()
	local weekly, dateTime = C_WeeklyRewards, C_DateAndTime
	local enum = Enum and Enum.WeeklyRewardChestThresholdType
	local vaultType = enum and enum.MythicPlus
	if type(weekly) ~= "table" or type(dateTime) ~= "table" or vaultType == nil then return nil end
	local weekOK, week = safeCall(dateTime.GetWeeklyResetStartTime)
	week = weekOK and safeNumber(week, 1, true) or nil
	if not week then return nil end
	local periodOK, current = safeCall(weekly.AreRewardsForCurrentRewardPeriod)
	if not periodOK or current ~= true then return nil end
	local activitiesOK, raw = safeCall(weekly.GetActivities, vaultType)
	if not activitiesOK or isSecret(raw) or type(raw) ~= "table" then return nil end
	local result, ids, indexes, progress = {}, {}, {}, 0
	for _, value in ipairs(raw) do
		if isSecret(value) or type(value) ~= "table" then return nil end
		local id = safeNumber(value.id, 1, true)
		local index = safeNumber(value.index, 1, true)
		local activityProgress = safeNumber(value.progress, 0)
		local threshold = safeNumber(value.threshold, 0)
		local level = safeNumber(value.level, 0, true)
		if not id or not index or not activityProgress or not threshold or not level or ids[id] or indexes[index] then return nil end
		ids[id], indexes[index] = true, true
		local activity = { id = id, index = index, progress = activityProgress, threshold = threshold, level = level }
		local tier = safeNumber(value.activityTierID, 0, true)
		local activityType = safeNumber(value.type, 0, true)
		if tier then activity.activityTierID = tier end
		if activityType then activity.type = activityType end
		if activityProgress >= threshold then progress = progress + 1 end
		result[#result + 1] = activity
	end
	table.sort(result, function(a, b) return a.index < b.index end)
	return week, { currentPeriod = true, progress = progress, activities = result }
end

HolyStorm:RegisterModule(metadata, function(Module)
	HolyStorm:ApplyModuleMetadata(Module, metadata)

	function Module:GetCharacterSnapshot(guid)
		return HolyStorm.Data.CharacterStore:GetBlock(guid, "mythicPlus")
	end

	function Module:Validate(snapshot, collectionReason, collectionDiagnostics)
		return validateMythicPlus(snapshot, collectionReason, collectionDiagnostics)
	end

	function Module:NeedsBootstrapRefresh(snapshot)
		local valid = validateMythicPlus(snapshot)
		if not valid then return true, "MYTHICPLUS_SNAPSHOT_INCOMPLETE" end
		local api = C_MythicPlus
		if type(api) ~= "table" or type(api.GetCurrentSeason) ~= "function" then return false, "CURRENT_SEASON_UNAVAILABLE" end
		local ok, season = safeCall(api.GetCurrentSeason)
		season = ok and safeNumber(season, 1, true) or nil
		if season and season ~= snapshot.seasonId then return true, "SEASON_MISMATCH" end
		if snapshot.weeklyIdentity and C_DateAndTime and type(C_DateAndTime.GetWeeklyResetStartTime) == "function" then
			local weekOK, week = safeCall(C_DateAndTime.GetWeeklyResetStartTime)
			week = weekOK and safeNumber(week, 1, true) or nil
			if week and week ~= snapshot.weeklyIdentity then return true, "WEEKLY_RESET_MISMATCH" end
		end
		return false, "BLOCK_FRESH"
	end

	function Module:RequestData(force)
		if self.initialDataRequested and not force then return false end
		self.initialDataRequested = true
		local api = C_MythicPlus
		if type(api) ~= "table" then return false end
		local requested = false
		for _, name in ipairs({ "RequestMapInfo", "RequestRewards" }) do
			if type(api[name]) == "function" then
				local ok = safeCall(api[name])
				requested = requested or ok
			end
		end
		return requested
	end

	local function scanFailure(reason, details, retryable)
		details = details or {}
		details.retryable = retryable == true
		return nil, reason, details
	end

	function Module:Collect()
		local mythicPlus, challengeMode = C_MythicPlus, C_ChallengeMode
		if type(mythicPlus) ~= "table" or type(challengeMode) ~= "table" then return scanFailure("RETAIL_API_UNAVAILABLE", { season = "UNKNOWN", rating = "UNKNOWN", maps = 0 }, false) end
		local seasonOK, season = safeCall(mythicPlus.GetCurrentSeason)
		season = seasonOK and safeNumber(season, 1, true) or nil
		local ratingOK, rating = safeCall(challengeMode.GetOverallDungeonScore)
		rating = ratingOK and safeNumber(rating, 0) or nil
		local mapsOK, mapIDs = safeCall(challengeMode.GetMapTable)
		local mapCount = 0
		if mapsOK and not isSecret(mapIDs) and type(mapIDs) == "table" then mapCount = #mapIDs end
		local baseDiagnostics = { season = season or "UNKNOWN", rating = rating or "UNKNOWN", maps = mapCount }
		if not season then return scanFailure("UNKNOWN_MYTHICPLUS_SEASON", baseDiagnostics, true) end
		if not rating then return scanFailure("UNKNOWN_MYTHICPLUS_RATING", baseDiagnostics, true) end
		if not mapsOK or isSecret(mapIDs) or type(mapIDs) ~= "table" or #mapIDs == 0 then return scanFailure("DUNGEON_POOL_NOT_READY", baseDiagnostics, true) end
		baseDiagnostics.expectedMaps = #mapIDs
		local displaySeason
		if type(mythicPlus.GetCurrentUIDisplaySeason) == "function" then
			local displayOK, value = safeCall(mythicPlus.GetCurrentUIDisplaySeason)
			displaySeason = displayOK and safeNumber(value, 1, true) or nil
		end
		local dungeonIDs, seen = {}, {}
		for _, rawID in ipairs(mapIDs) do
			local id = safeNumber(rawID, 1, true)
			if not id then return scanFailure("INVALID_DUNGEON_POOL", baseDiagnostics, false) end
			if seen[id] then return scanFailure("DUPLICATE_DUNGEON_MAP", baseDiagnostics, false) end
			seen[id] = true
			dungeonIDs[#dungeonIDs + 1] = id
		end
		table.sort(dungeonIDs)
		baseDiagnostics.maps = #dungeonIDs
		local snapshot = {
			schemaVersion = SNAPSHOT_VERSION, snapshotVersion = SNAPSHOT_VERSION,
			seasonId = season, displaySeasonId = displaySeason, overallScore = rating,
			dungeonCount = #dungeonIDs, dungeons = {}, poolComplete = false,
			scoreDataReady = false, updatedAt = HolyStorm.Utils.Now(),
		}
		for _, id in ipairs(dungeonIDs) do
			local infoOK, name, instanceID, timeLimit, texture, backgroundTexture, mapID = safeCall(challengeMode.GetMapUIInfo, id)
			local mapDiagnostics = { season = season, rating = rating, maps = #dungeonIDs, expectedMaps = #dungeonIDs, mapId = id }
			if not infoOK or not safeString(name) or not safeNumber(instanceID, 1, true) or not safeNumber(timeLimit, 1) or not safeNumber(mapID, 1, true) then return scanFailure("DUNGEON_MAP_INFO_NOT_READY", mapDiagnostics, true) end
			if type(mythicPlus.GetSeasonBestForMap) ~= "function" then return scanFailure("BEST_RUN_API_UNAVAILABLE", mapDiagnostics, false) end
			local bestOK, inTime, overTime = safeCall(mythicPlus.GetSeasonBestForMap, id)
			if not bestOK then return scanFailure("BEST_RUN_API_ERROR", mapDiagnostics, false) end
			local bestInTime, inTimeReason = safeRun(inTime, false)
			local bestOverTime, overTimeReason = safeRun(overTime, true)
			if bestInTime == false then return scanFailure(inTimeReason or "INVALID_BEST_RUN", mapDiagnostics, false) end
			if bestOverTime == false then return scanFailure(overTimeReason or "INVALID_BEST_RUN", mapDiagnostics, false) end
			-- Blizzard's Challenges UI selects the higher dungeonScore from the two
			-- documented best-run slots and displays zero when neither slot exists.
			local dungeonScore = 0
			if bestInTime and bestOverTime then dungeonScore = bestInTime.score > bestOverTime.score and bestInTime.score or bestOverTime.score
			elseif bestInTime then dungeonScore = bestInTime.score
			elseif bestOverTime then dungeonScore = bestOverTime.score end
			-- Affix detail is explicitly MayReturnNothing in the Retail API. Keep
			-- unavailable detail unknown; the authoritative map score above comes
			-- from Blizzard's non-optional best-run API.
			local affixScores
			if type(mythicPlus.GetSeasonBestAffixScoreInfoForMap) == "function" then
				local scoresOK, scoresRaw = safeCall(mythicPlus.GetSeasonBestAffixScoreInfoForMap, id)
				if scoresOK and not isSecret(scoresRaw) and type(scoresRaw) == "table" then affixScores = safeAffixScores(scoresRaw) end
			end
			local dungeon = {
				challengeMapId = id, name = name, instanceId = instanceID, mapId = mapID,
				timeLimit = timeLimit, score = dungeonScore,
			}
			if affixScores then dungeon.affixScores = affixScores end
			local icon = safeNumber(texture, 0, true)
			local background = safeNumber(backgroundTexture, 0, true)
			if icon then dungeon.texture = icon end
			if background then dungeon.background = background end
			if bestInTime then dungeon.bestInTime = bestInTime end
			if bestOverTime then dungeon.bestOverTime = bestOverTime end
			snapshot.dungeons[#snapshot.dungeons + 1] = dungeon
		end
		snapshot.poolComplete = #snapshot.dungeons == #dungeonIDs
		snapshot.scoreDataReady = snapshot.poolComplete
		local week, vault = captureVault()
		if week and vault then snapshot.weeklyIdentity, snapshot.greatVaultMythicPlus = week, vault end
		local valid, reason, retryable = validateMythicPlus(snapshot)
		if not valid then return scanFailure(reason or "INVALID_MYTHICPLUS_SNAPSHOT", baseDiagnostics, retryable) end
		return snapshot
	end

	function Module:Commit(snapshot)
		local guid = UnitGUID("player")
		return HolyStorm.PlayerData:WriteOwnedBlock(guid, "mythicPlus", snapshot, "blizzard")
	end

	function Module:Queue(sync, delay)
		return HolyStorm.Snapshots:Queue("mythicplus", function() return Module:Collect() end,
			function(snapshot, reason, diagnostics) return Module:Validate(snapshot, reason, diagnostics) end,
			function(snapshot, force) return Module:Commit(snapshot, force, sync) end,
			{
				source = "MythicPlus", delay = delay or 1.5, retryDelay = 2.5, maxRetries = 3, priority = 4,
				onValidationFailure = function(reason, disposition, retryCount, maxRetries, diagnostics)
					diagnostics = type(diagnostics) == "table" and diagnostics or {}
					HolyStorm.Logger:Write("WARN", "MythicPlus", "validation", "MythicPlus validation: " .. disposition, {
						reason = reason,
						season = diagnostics.season or "UNKNOWN",
						rating = diagnostics.rating or "UNKNOWN",
						maps = diagnostics.maps or 0,
						expectedMaps = diagnostics.expectedMaps or 0,
						mapId = diagnostics.mapId,
						retryCount = retryCount,
						maxRetries = maxRetries,
					})
				end,
			})
	end

	function Module:OnInitialize()
		HolyStorm.CharacterScans:RegisterProvider("MythicPlus", {
			block = "mythicPlus", capability = "character.scan.mythicplus", addonId = "mythicPlus", order = 20,
			needsRefresh = function(snapshot) return Module:NeedsBootstrapRefresh(snapshot) end,
			request = function(sync, reason)
				if reason == "INITIAL_MISSING_BLOCK" or reason == "INITIAL_STALE_BLOCK" or reason == "INITIAL_INCOMPLETE_BLOCK" or reason == "SEASON_MISMATCH" or reason == "WEEKLY_RESET_MISMATCH" then Module:RequestData(false)
				elseif reason == "CAPABILITY" then Module:RequestData(true) end
				local shortDelay = reason == "CHALLENGE_MODE_COMPLETED" or reason == "CHALLENGE_MODE_MAPS_UPDATE" or reason == "MYTHIC_PLUS_NEW_WEEKLY_RECORD" or reason == "WEEKLY_REWARDS_UPDATE"
				local _, workflowId = Module:Queue(sync, shortDelay and 0.5 or 1.5)
				return workflowId
			end,
		})
		HolyStorm:RegisterCapability("MythicPlus", "character.scan.mythicplus", function(_, sync, reason)
			return HolyStorm.CharacterScans:Request("mythicPlus", reason or "CAPABILITY", sync, { order = 20 })
		end)
	end

	function Module:OnEnable()
		if not C_MythicPlus or not C_ChallengeMode then self:Disable(); return end
		self.initialDataRequested = false
		for _, eventName in ipairs({ "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_MAPS_UPDATE", "MYTHIC_PLUS_NEW_WEEKLY_RECORD", "WEEKLY_REWARDS_UPDATE" }) do
			local name = eventName
			HolyStorm.Events:Register(name, "mythicplus", function()
				HolyStorm.CharacterScans:Request("mythicPlus", name, true, { order = 20 })
			end)
		end
		local context = self.loadContext
		if context and context.reason == "event" then HolyStorm.CharacterScans:Request("mythicPlus", context.trigger, true, { order = 20 }) end
	end

	function Module:OnDisable()
		self.initialDataRequested = false
		HolyStorm.Events:UnregisterOwner("mythicplus")
		HolyStorm.Snapshots:Cancel("mythicplus")
	end
end)
