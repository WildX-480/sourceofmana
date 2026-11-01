extends ServiceBase
class_name SQLService

#
var db : Object						= null
var backups : SQLBackups			= null
var queryMutex : Mutex				= Mutex.new()

# Migrations
func HasVersion() -> bool:
	var result = Query("SELECT name FROM sqlite_master WHERE type=\"table\" AND name=\"migration\"")
	return not result.is_empty()

func GetVersion() -> int:
	if HasVersion():
		var result = Query("SELECT version FROM migration LIMIT 1;")
		if not result.is_empty():
			return result[0].get("version", 0)
	return 0

func SetVersion(version : int):
	Query("UPDATE migration SET version = %d;" % version)

func ApplyMigrations():
	var currentVersion : int = GetVersion()
	var patches : PackedStringArray = FileSystem.ParseSQL(Path.MigrationRsc)
	var patchCount : int = patches.size()
	if patchCount == currentVersion:
		return

	while patchCount > currentVersion:
		if not ApplyMigration(patches[currentVersion]):
			return
		currentVersion += 1
		SetVersion(currentVersion)
	CompactDatabase()

func CompactDatabase():
	if ExecuteBindings("VACUUM;", []):
		Util.PrintInfo("SQL", "Database compacted")
	else:
		Util.PrintLog("SQL", "Database compaction failed: " + db.error_message)

func ApplyMigration(migrationFile : String) -> bool:
	var migration : String = FileAccess.get_file_as_string(migrationFile)
	queryMutex.lock()
	var success : bool = db.query(migration)
	var errorMessage : String = db.error_message
	if not success:
		db.query("ROLLBACK;")
	queryMutex.unlock()

	if not success:
		Util.PrintLog("SQL", "Migration %s failed: %s" % [migrationFile.get_file(), errorMessage])
		assert(false, "Migration %s failed: %s" % [migrationFile.get_file(), errorMessage])
	return success

# Accounts
func AddAccount(username : String, password : String, email : String) -> bool:
	var salt : String = Hasher.GenerateSalt()
	var hashedPassword : String = Hasher.HashPassword(password, salt)

	var accountData : Dictionary = {
		"username" : username,
		"password_salt" : salt,
		"password" : hashedPassword,
		"email" : email,
		"created_timestamp" : SQLCommons.Timestamp()
	}
	return InsertRow("account", accountData)

func RemoveAccount(accountID : int) -> bool:
	return ExecuteBindings("DELETE FROM account WHERE account_id = ?;", [accountID])

func HasAccount(username : String) -> bool:
	return not QueryBindings("SELECT account_id FROM account WHERE username = ?;", [username]).is_empty()

func ValidateAuthPassword(username : String, triedPassword : String) -> Peers.AccountData:
	var results : Array[Dictionary] = QueryBindings("SELECT account_id, password, password_salt, permission FROM account WHERE username = ?;", [username])
	assert(results.size() <= 1, "Duplicated account row")
	if not results.is_empty():
		var salt = results[0].get("password_salt", null)
		var correctPassword = results[0].get("password", null)
		var accountID = results[0].get("account_id", null)
		if salt and correctPassword and accountID and salt is String and correctPassword is String and accountID is int:
			var hashedTriedPassword : String = Hasher.HashPassword(triedPassword, salt)
			if hashedTriedPassword == correctPassword:
				var permission = results[0].get("permission", null)
				if not permission:
					permission = ActorCommons.Permission.NONE
				return Peers.AccountData.new(accountID, permission)
	return null

func UpdateAccount(accountID : int, platform : int = NetworkCommons.Platform.UNKNOWN) -> bool:
	var newTimestamp : int = SQLCommons.Timestamp()
	var data : Dictionary = {
		"last_timestamp": newTimestamp,
	}
	if platform != NetworkCommons.Platform.UNKNOWN:
		data["platform"] = platform
	return UpdateRow("account", "account_id = ?", [accountID], data)

# Characters
func AddCharacter(accountID : int, nickname : String, stats : Dictionary, traits : Dictionary, attributes : Dictionary) -> bool:
	var charData : Dictionary = {
		"account_id": accountID,
		"nickname": nickname,
		"created_timestamp": SQLCommons.Timestamp()
	}
	var ret : bool = InsertRow("character", charData)
	if ret:
		var charID : int = GetCharacterID(accountID, nickname)
		ret = ret and UpdateRow("stat", "char_id = ?", [charID], stats)
		ret = ret and UpdateRow("trait", "char_id = ?", [charID], traits)
		ret = ret and UpdateRow("attribute", "char_id = ?", [charID], attributes)
	return ret

func RemoveCharacter(charID : int) -> bool:
	if charID != NetworkCommons.PeerUnknownID:
		return ExecuteBindings("DELETE FROM character WHERE char_id = ?;", [charID])
	return false

func GetCharacters(accountID : int) -> PackedInt64Array:
	var charIDs : Array[int] = []
	for result in QueryBindings("SELECT char_id FROM character WHERE account_id = ?;", [accountID]):
		charIDs.append(result["char_id"])
	return charIDs

func GetCharacterInfo(charID : int) -> Dictionary:
	var results : Array[Dictionary] = Query("SELECT * \
FROM character \
INNER JOIN stat ON character.char_id = stat.char_id \
INNER JOIN trait ON character.char_id = trait.char_id \
INNER JOIN attribute ON character.char_id = attribute.char_id \
WHERE character.char_id = %d;" % charID)
	assert(results.size() == 1, "Character information tables are missing")
	return {} if results.is_empty() else results[0]

func RefreshCharacter(player : PlayerAgent) -> bool:
	var charID : int = Peers.GetCharacter(player.peerID)
	if charID == NetworkCommons.PeerUnknownID:
		return false

	queryMutex.lock()
	Query("BEGIN TRANSACTION;")
	var success : bool = UpdateAttribute(charID, player.stat)
	success = success and UpdateTrait(charID, player.stat)
	success = success and UpdateStat(charID, player.stat)
	success = success and UpdateCharacter(player)
	success = success and UpdateProgress(charID, player.progress)
	Query("COMMIT;")
	queryMutex.unlock()

	return success

func HasCharacter(nickname : String) -> bool:
	return not QueryBindings("SELECT char_id FROM character WHERE nickname = ?;", [nickname]).is_empty()

func CharacterLogin(charID : int) -> bool:
	return UpdateRow("character", "char_id = ?", [charID], {"last_timestamp": SQLCommons.Timestamp()})

# Character
func GetCharacterID(accountID : int, nickname : String) -> int:
	var results : Array[Dictionary] = QueryBindings("SELECT char_id FROM character WHERE account_id = ? AND nickname = ?;", [accountID, nickname])
	assert(results.size() <= 1, "Duplicated character row for account %d and nickname '%s'" % [accountID, nickname])
	return NetworkCommons.PeerUnknownID if results.is_empty() else results[0]["char_id"]

func GetCharacter(charID : int) -> Dictionary:
	var results : Array[Dictionary] = QueryBindings("SELECT * FROM character WHERE char_id = ?;", [charID])
	assert(results.size() <= 1, "Duplicated character row %d" % charID)
	return {} if results.is_empty() else results[0]

func UpdateCharacter(player : PlayerAgent) -> bool:
	if player == null:
		return false

	var charID : int = Peers.GetCharacter(player.peerID)
	if charID == NetworkCommons.PeerUnknownID:
		return false

	var map : WorldMap = WorldAgent.GetMapFromAgent(player)
	var newTimestamp : int = SQLCommons.Timestamp()
	var data : Dictionary = {}

	if map != null and not map.HasFlags(WorldMap.Flags.NO_REJOIN) and ActorCommons.IsAlive(player):
		data["pos_x"] = player.position.x
		data["pos_y"] = player.position.y
		data["pos_map"] = map.id
	else:
		data["pos_x"] = player.respawnDestination.pos.x
		data["pos_y"] = player.respawnDestination.pos.y
		data["pos_map"] = player.respawnDestination.mapID

	data["respawn_x"] = player.respawnDestination.pos.x
	data["respawn_y"] = player.respawnDestination.pos.y
	data["respawn_map"] = player.respawnDestination.mapID

	if player.exploreOrigin != null:
		data["explore_x"] = player.exploreOrigin.pos.x
		data["explore_y"] = player.exploreOrigin.pos.y

	var timeUpdated : bool = ExecuteBindings("UPDATE character SET total_time = IFNULL(total_time, 0) + ? - IFNULL(last_timestamp, ?), last_timestamp = ? WHERE char_id = ?;", [newTimestamp, newTimestamp, newTimestamp, charID])
	return timeUpdated and UpdateRow("character", "char_id = ?", [charID], data)

# Stats
func GetAttribute(charID : int) -> Dictionary:
	var results : Array[Dictionary] = QueryBindings("SELECT * FROM attribute WHERE char_id = ?;", [charID])
	assert(results.size() == 1, "Character attribute row is missing")
	return {} if results.is_empty() else results[0]

func UpdateAttribute(charID : int, stats : ActorStats) -> bool:
	if stats == null:
		return false

	var data : Dictionary = {
		"strength" = stats.strength,
		"vitality" = stats.vitality,
		"agility" = stats.agility,
		"endurance" = stats.endurance,
		"concentration" = stats.concentration
	}
	return UpdateRow("attribute", "char_id = ?", [charID], data)

func GetTrait(charID : int) -> Dictionary:
	var results : Array[Dictionary] = QueryBindings("SELECT * FROM trait WHERE char_id = ?;", [charID])
	assert(results.size() == 1, "Character trait row is missing")
	return {} if results.is_empty() else results[0]

func UpdateTrait(charID : int, stats : ActorStats) -> bool:
	if stats == null:
		return false

	var data : Dictionary = {
		"hairstyle" = stats.hairstyle,
		"haircolor" = stats.haircolor,
		"race" = stats.race,
		"skintone" = stats.skintone,
		"gender" = stats.gender,
		"shape" = stats.shape,
		"spirit" = stats.spirit
	}
	return UpdateRow("trait", "char_id = ?", [charID], data)

func GetStat(charID : int) -> Dictionary:
	var results : Array[Dictionary] = QueryBindings("SELECT * FROM stat WHERE char_id = ?;", [charID])
	assert(results.size() == 1, "Character stat row is missing")
	return {} if results.is_empty() else results[0]

func UpdateStat(charID : int, stats : ActorStats) -> bool:
	if stats == null:
		return false

	var data : Dictionary = {
		"level" = stats.level,
		"experience" = stats.experience,
		"gp" = stats.gp,
		"health" = max(1, stats.health),
		"mana" = stats.mana,
		"stamina" = stats.stamina,
		"karma" = stats.karma
	}
	return UpdateRow("stat", "char_id = ?", [charID], data)

# Inventory
func AddItem(charID : int, itemID : int, customfield : String, itemCount : int = 1, storageType : int = 0) -> bool:
	return ExecuteBindings("INSERT INTO item (item_id, char_id, count, storage, customfield) VALUES (?, ?, ?, ?, ?) \
ON CONFLICT (char_id, item_id, storage, customfield) DO UPDATE SET count = count + excluded.count;", [itemID, charID, itemCount, storageType, customfield])

func SetItem(charID : int, itemID : int, customfield : String, itemCount : int, storageType : int = 0) -> bool:
	if itemCount <= 0:
		return ExecuteBindings("DELETE FROM item WHERE char_id = ? AND item_id = ? AND storage = ? AND customfield = ?;", [charID, itemID, storageType, customfield])
	return ExecuteBindings("INSERT INTO item (item_id, char_id, count, storage, customfield) VALUES (?, ?, ?, ?, ?) \
ON CONFLICT (char_id, item_id, storage, customfield) DO UPDATE SET count = excluded.count;", [itemID, charID, itemCount, storageType, customfield])

func GetStorage(charID : int, storageType : int = 0) -> Array[Dictionary]:
	return QueryBindings("SELECT * FROM item WHERE char_id = ? AND storage = ?;", [charID, storageType])

# Equipment
func GetEquipment(charID : int) -> Dictionary:
	var results : Array[Dictionary] = QueryBindings("SELECT * FROM equipment WHERE char_id = ?;", [charID])
	assert(results.size() <= 1, "Duplicated equipment on character %d" % charID)
	return {} if results.is_empty() else results[0]

func UpdateEquipment(charID : int, data : Dictionary) -> bool:
	return UpdateRow("equipment", "char_id = ?", [charID], data)

# Progress
func UpdateProgress(charID : int, progress : ActorProgress) -> bool:
	progress.bestiaryMutex.lock()
	var bestiary : Dictionary = progress.bestiary.duplicate()
	progress.bestiaryMutex.unlock()

	var success : bool = true
	for entryID in bestiary:
		success = SetBestiary(charID, entryID, bestiary[entryID]) and success
	return success

# Skill
func SetSkill(charID : int, skillID : int, value : int) -> bool:
	return ExecuteBindings("INSERT INTO skill (char_id, skill_id, level) VALUES (?, ?, ?) \
ON CONFLICT (char_id, skill_id) DO UPDATE SET level = excluded.level;", [charID, skillID, value])

func RemoveSkill(charID : int, skillID : int) -> bool:
	return ExecuteBindings("DELETE FROM skill WHERE char_id = ? AND skill_id = ?;", [charID, skillID])

func GetSkills(charID : int) -> Array[Dictionary]:
	return QueryBindings("SELECT * FROM skill WHERE char_id = ?;", [charID])

# Bestiary
func SetBestiary(charID : int, mobID : int, value : int) -> bool:
	return ExecuteBindings("INSERT INTO bestiary (char_id, mob_id, killed_count) VALUES (?, ?, ?) \
ON CONFLICT (char_id, mob_id) DO UPDATE SET killed_count = excluded.killed_count;", [charID, mobID, value])

func GetBestiaries(charID : int) -> Array[Dictionary]:
	return QueryBindings("SELECT * FROM bestiary WHERE char_id = ?;", [charID])

# Quest
func SetQuest(charID : int, questID : int, value : int) -> bool:
	return ExecuteBindings("INSERT INTO quest (char_id, quest_id, state) VALUES (?, ?, ?) \
ON CONFLICT (char_id, quest_id) DO UPDATE SET state = excluded.state;", [charID, questID, value])

func GetQuests(charID : int) -> Array[Dictionary]:
	return QueryBindings("SELECT * FROM quest WHERE char_id = ?;", [charID])

# Auth Token
func AddAuthToken(accountID : int, tokenHash : String, ipAddress : String) -> bool:
	ExecuteBindings("DELETE FROM auth_token WHERE account_id = ? AND ip_address = ?;", [accountID, ipAddress])
	var now : int = SQLCommons.Timestamp()
	var data : Dictionary = {
		"token_hash": tokenHash,
		"account_id": accountID,
		"ip_address": ipAddress,
		"created_timestamp": now,
		"expires_timestamp": now + NetworkCommons.TokenExpirySec,
	}
	return InsertRow("auth_token", data)

func ValidateAuthToken(accountID : int, tokenHash : String, ipAddress : String) -> Peers.AccountData:
	var results : Array[Dictionary] = QueryBindings("SELECT auth_token.account_id, auth_token.expires_timestamp, account.permission FROM auth_token INNER JOIN account ON auth_token.account_id = account.account_id WHERE auth_token.account_id = ? AND auth_token.token_hash = ? AND auth_token.ip_address = ?;", [accountID, tokenHash, ipAddress])
	if not results.is_empty():
		if results[0].get("expires_timestamp", 0) <= SQLCommons.Timestamp():
			RemoveAuthToken(accountID, tokenHash)
			return null
		var permission : Variant = results[0].get("permission", null)
		if not permission:
			permission = ActorCommons.Permission.NONE
		return Peers.AccountData.new(accountID, permission)
	return null

func RefreshAuthToken(accountID : int, ipAddress : String) -> bool:
	return ExecuteBindings("UPDATE auth_token SET expires_timestamp = ? WHERE account_id = ? AND ip_address = ?;", [SQLCommons.Timestamp() + NetworkCommons.TokenExpirySec, accountID, ipAddress])

func RemoveAuthToken(accountID : int, tokenHash : String) -> bool:
	return ExecuteBindings("DELETE FROM auth_token WHERE account_id = ? AND token_hash = ?;", [accountID, tokenHash])

func CleanExpiredTokens():
	ExecuteBindings("DELETE FROM auth_token WHERE expires_timestamp <= ?;", [SQLCommons.Timestamp()])

func GetAccountEmail(accountID : int) -> String:
	var results : Array[Dictionary] = QueryBindings("SELECT email FROM account WHERE account_id = ?;", [accountID])
	if not results.is_empty():
		var email : Variant = results[0].get("email", null)
		if email is String:
			return email
	return ""

func CheckAccountPassword(accountID : int, triedPassword : String) -> bool:
	var results : Array[Dictionary] = QueryBindings("SELECT password, password_salt FROM account WHERE account_id = ?;", [accountID])
	if results.is_empty():
		return false
	return Hasher.HashPassword(triedPassword, results[0]["password_salt"]) == results[0]["password"]

func UpdateAccountPassword(accountID : int, newPassword : String) -> bool:
	var salt : String = Hasher.GenerateSalt()
	var hashedPassword : String = Hasher.HashPassword(newPassword, salt)
	return ExecuteBindings("UPDATE account SET password = ?, password_salt = ? WHERE account_id = ?;", [hashedPassword, salt, accountID])

func RemoveAllAuthTokens(accountID : int) -> bool:
	return ExecuteBindings("DELETE FROM auth_token WHERE account_id = ?;", [accountID])

# Ban
func BanAccount(accountID : int, unbanTimestamp : int, reason : String = "") -> bool:
	return ExecuteBindings("INSERT INTO ban (account_id, banned_timestamp, unban_timestamp, reason) VALUES (?, ?, ?, ?) \
ON CONFLICT (account_id) DO UPDATE SET banned_timestamp = excluded.banned_timestamp, unban_timestamp = excluded.unban_timestamp, reason = excluded.reason;", [accountID, SQLCommons.Timestamp(), unbanTimestamp, reason])

func UnbanAccount(accountID : int) -> bool:
	return ExecuteBindings("DELETE FROM ban WHERE account_id = ?;", [accountID])

func LoadBans() -> Dictionary[int, int]:
	var bans : Dictionary[int, int] = {}
	var now : int = SQLCommons.Timestamp()
	var results : Array[Dictionary] = Query("SELECT account_id, unban_timestamp FROM ban WHERE unban_timestamp > %d;" % now)
	for row in results:
		bans[row["account_id"]] = row["unban_timestamp"]
	return bans

# IP Ban
func BanIPRange(ipRange : String, reason : String = "") -> bool:
	return ExecuteBindings("INSERT INTO ip_ban (ip_range, banned_timestamp, reason) VALUES (?, ?, ?) \
ON CONFLICT (ip_range) DO UPDATE SET banned_timestamp = excluded.banned_timestamp, reason = excluded.reason;", [ipRange, SQLCommons.Timestamp(), reason])

func UnbanIPRange(ipRange : String) -> bool:
	return ExecuteBindings("DELETE FROM ip_ban WHERE ip_range = ?;", [ipRange])

func LoadIPBans() -> Dictionary[String, String]:
	var bans : Dictionary[String, String] = {}
	var results : Array[Dictionary] = Query("SELECT ip_range, reason FROM ip_ban;")
	for row in results:
		bans[row["ip_range"]] = row.get("reason", "")
	return bans

func GetIPBanList(filter : String = "") -> Array[Dictionary]:
	if filter.is_empty():
		return Query("SELECT ip_range, banned_timestamp, reason FROM ip_ban;")
	return QueryBindings("SELECT ip_range, banned_timestamp, reason FROM ip_ban WHERE ip_range LIKE ?;", ["%" + filter + "%"])

func GetAccountID(username : String) -> int:
	var results : Array[Dictionary] = QueryBindings("SELECT account_id FROM account WHERE username = ?;", [username])
	if not results.is_empty():
		return results[0].get("account_id", NetworkCommons.PeerUnknownID)
	return NetworkCommons.PeerUnknownID

func SetPermission(accountID : int, permission : int) -> bool:
	return UpdateRow("account", "account_id = ?", [accountID], {"permission": permission})

func GetBanList(filter : String = "") -> Array[Dictionary]:
	var now : int = SQLCommons.Timestamp()
	if filter.is_empty():
		return Query("SELECT ban.account_id, account.username, ban.unban_timestamp, ban.reason FROM ban INNER JOIN account ON ban.account_id = account.account_id WHERE ban.unban_timestamp > %d;" % now)
	return QueryBindings("SELECT ban.account_id, account.username, ban.unban_timestamp, ban.reason FROM ban INNER JOIN account ON ban.account_id = account.account_id WHERE ban.unban_timestamp > ? AND account.username LIKE ?;", [now, "%" + filter + "%"])

# Commons
func Query(query : String) -> Array[Dictionary]:
	var data : Array[Dictionary] = []
	queryMutex.lock()
	if db.query(query):
		data = db.query_result
	queryMutex.unlock()
	return data

func QueryBindings(query : String, params : Array) -> Array[Dictionary]:
	var data : Array[Dictionary] = []
	queryMutex.lock()
	if db.query_with_bindings(query, params):
		data = db.query_result
	queryMutex.unlock()
	return data

func ExecuteBindings(query : String, params : Array) -> bool:
	queryMutex.lock()
	var ret : bool = db.query_with_bindings(query, params)
	queryMutex.unlock()
	return ret

func QuoteColumn(column : String) -> String:
	return "\"" + column.replace("\"", "\"\"") + "\""

func InsertRow(table : String, data : Dictionary) -> bool:
	var columns : PackedStringArray = []
	var placeholders : PackedStringArray = []
	for column : String in data:
		columns.append(QuoteColumn(column))
		placeholders.append("?")
	return ExecuteBindings("INSERT INTO %s (%s) VALUES (%s);" % [table, ", ".join(columns), ", ".join(placeholders)], data.values())

func UpdateRow(table : String, condition : String, conditionParams : Array, data : Dictionary) -> bool:
	if data.is_empty():
		return true
	var assignments : PackedStringArray = []
	for column : String in data:
		assignments.append(QuoteColumn(column) + " = ?")
	return ExecuteBindings("UPDATE %s SET %s WHERE %s;" % [table, ", ".join(assignments), condition], data.values() + conditionParams)

func Backup(targetPath : String) -> bool:
	queryMutex.lock()
	var ret : bool = db.backup_to(targetPath)
	queryMutex.unlock()
	return ret

#
func _post_launch():
	var dbPath : String = SQLCommons.GetDBPath()
	if not FileSystem.FileExists(dbPath) and not SQLCommons.CopyDatabase(dbPath):
		return

	db = SQLite.new()
	db.path = dbPath
	db.verbosity_level = SQLCommons.Verbosity

	if not db.open_db():
		assert(false, "Failed to open database: "+ db.error_message)
	else:
		if not LauncherCommons.isWeb:
			Query("PRAGMA journal_mode=WAL;")
			Query("PRAGMA synchronous=NORMAL;")
			Query("PRAGMA busy_timeout=5000;")
		if not Launcher.Debug and not LauncherCommons.isWeb:
			backups = SQLBackups.new()

	ApplyMigrations()
	Peers.bannedAccounts = LoadBans()
	Peers.bannedIPRanges = LoadIPBans()
	CleanExpiredTokens()

	isInitialized = true

	if backups:
		backups.Start()

func Destroy():
	if backups:
		backups.Stop()
	if db:
		db.close_db()

func Wipe():
	for table in ["account", "attribute", "auth_token", "ban", "bestiary", "character", "equipment", "ip_ban", "item", "quest", "skill", "sqlite_sequence", "stat", "trait"]:
		Query("DELETE FROM %s;" % table)
