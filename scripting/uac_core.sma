#define CHANGE_NICK_HOOK 2 // 0 - amxmodx, 1 - fakemeta, 2 - reapi

#include <amxmodx>
#include <uac>

#if CHANGE_NICK_HOOK == 1
#include <fakemeta>
#elseif CHANGE_NICK_HOOK == 2
#include <reapi>
#endif

#define CHECK_NATIVE_ARGS_NUM(%1,%2,%3) \
	if (%1 < %2) { \
		log_error(AMX_ERR_NATIVE, "Invalid num of arguments %d. Expected %d", %1, %2); \
		return %3; \
	}

#define CHECK_NATIVE_PLAYER(%1,%2) \
	if (!is_user_connected(%1)) { \
		log_error(AMX_ERR_NATIVE, "Invalid player %d", %1); \
		return %2; \
	}

#define TIMEOUT_TASK_ID 1

const MAX_KEY_LENGTH = MAX_AUTHID_LENGTH + 2;

enum {
	FWD_Loading,
	FWD_Loaded,
	FWD_Checking,
	FWD_Checked,
	FWD_Pushing,
	FWD_Pushed,

	FWD_LAST
};

new Forwards[FWD_LAST], FReturn;

enum _:LoadStatus {
	LoadSource,
	bool:LoadLoaded
};

new LoadStatusList[5][LoadStatus], LoadStatusNum, PluginLoadedNum;

enum {
	STATUS_LOADING,
	STATUS_LOADED
};

new Status;

new bool:NeedRecheck = false;

enum (+=1) {
	MODE_DISABLE = 0,
	MODE_NORMAL,
	MODE_KICK
}
// Mode of logging to a server
// 0 - disable logging, players won't be checked (and access won't be set)
// 1 - normal mode which obey flags set in accounts
// 2 - kick all players not on list
new Mode;

/**
* s - STEAM_ID
* i - IP
* n - NAME
* c - CASESENSITIVE
* t - CLAN TAG
*/
new SearchPriority[32];

new KickReason[64];
new PasswordField[10];

enum {
	DefaultAccessCvar,
	DefaultAccessFlags
}
enum (+=1) {
	DefaultAccessPlayer = 0,
	DefaultAccessHLTV,
	DefaultAccessBOT,
	
	DefaultAccessLast
}

new DefaultAccess[DefaultAccessLast][2];

enum (<<=1) {
	STATE_DISCONNECTED = 1,
	STATE_CONNECTING,
	STATE_CONNECTED,
}

#define STATES_SET_ID				1
#define add_user_state(%1,%2) 		set_user_flags(%1, %2, STATES_SET_ID)
#define get_user_state(%1,%2) 		(get_user_flags(%1, STATES_SET_ID) & %2)
#define remove_user_state(%1,%2) 	remove_user_flags(%1, %2, STATES_SET_ID)
#define clear_user_state(%1) 		remove_user_flags(%1, -1, STATES_SET_ID)
#define clear_privilege() arrayset(Privilege, 0 , sizeof Privilege)
#define clear_user_privilege(%1) arrayset(UsersPrivilege[%1], 0 , sizeof UsersPrivilege[])

enum CheckResult {
	CHECK_IGNORE,
	CHECK_DEFAULT,
	CHECK_SUCCESS,
	CHECK_KICK,
};

enum _:PrivilegeStruct {
	PrivilegeSource,
	PrivilegeId,
	PrivilegeAccess,
	PrivilegeFlags,
	PrivilegePassword[UAC_MAX_PASSWORD_LENGTH],
	PrivilegePrefix[UAC_MAX_PREFIX_LENGTH],
	PrivilegeExpired,
	PrivilegeOptions
};

new PluginId;
new Trie:Privileges, Privilege[PrivilegeStruct];
new UsersPrivilege[MAX_PLAYERS + 1][PrivilegeStruct];

new Snapshot:PrivilegesSnapshot = Invalid_Snapshot, PrivilegesIterate = 0;

public plugin_init() {
	PluginId = register_plugin("[UAC] Core", "1.0.0", "GM-X Team");

	register_concmd("amx_reloadadmins", "CmdReload", ADMIN_CFG);

#if defined _reapi_included
	RegisterHookChain(RG_CBasePlayer_SetClientUserInfoName, "CBasePlayer_SetClientUserInfoName_Post", true);
#elseif defined _fakemeta_included
	register_forward(FM_SetClientKeyValue, "SetCleintKeyValue_Post", true);
#endif
	
	new pcvar;
	pcvar = create_cvar("amx_mode", "1", .has_min=true, .min_val=0.0, .has_max=true, .max_val=2.0);
	bind_pcvar_num(pcvar, Mode);
	
	pcvar = create_cvar("pmm_search_priority", "sinct");
	bind_pcvar_string(pcvar, SearchPriority, charsmax(SearchPriority));

	pcvar = create_cvar("amx_password_field", "_pw");
	bind_pcvar_string(pcvar, PasswordField, charsmax(PasswordField));
	
	DefaultAccess[DefaultAccessPlayer][DefaultAccessCvar] = create_cvar("amx_default_access", "z");
	DefaultAccess[DefaultAccessHLTV][DefaultAccessCvar] = create_cvar("pmm_hltv_access", "a");
	DefaultAccess[DefaultAccessBOT][DefaultAccessCvar] = create_cvar("pmm_bot_access", "a");
	
	hook_cvar_change(DefaultAccess[DefaultAccessPlayer][DefaultAccessCvar], "CvarChangeAccess");
	hook_cvar_change(DefaultAccess[DefaultAccessHLTV][DefaultAccessCvar], "CvarChangeAccess");
	hook_cvar_change(DefaultAccess[DefaultAccessBOT][DefaultAccessCvar], "CvarChangeAccess");

	Privileges = TrieCreate();

	Forwards[FWD_Loading] = CreateMultiForward("UAC_Loading", ET_IGNORE, FP_CELL);
	Forwards[FWD_Loaded] = CreateMultiForward("UAC_Loaded", ET_IGNORE, FP_CELL);
	Forwards[FWD_Checking] = CreateMultiForward("UAC_Checking", ET_STOP, FP_CELL);
	Forwards[FWD_Checked] = CreateMultiForward("UAC_Checked", ET_IGNORE, FP_CELL, FP_CELL);
	Forwards[FWD_Pushing] = CreateMultiForward("UAC_Pushing", ET_IGNORE);
	Forwards[FWD_Pushed] = CreateMultiForward("UAC_Pushed", ET_IGNORE);

	loadStart(false);
}

public plugin_cfg() {
	Mode = get_cvar_num("amx_mode");
	for (new i = 0, flags[32]; i < DefaultAccessLast; i++) {
		get_pcvar_string(DefaultAccess[i][DefaultAccessCvar], flags, charsmax(flags));
		DefaultAccess[i][DefaultAccessFlags] = read_flags(flags);
	}
	checkAPIVersion();
}

public plugin_end() {
	TrieDestroy(Privileges);

	for (new i = 0; i < FWD_LAST; i++) {
		DestroyForward(Forwards[i]);
	}
	
	if (PrivilegesSnapshot != Invalid_Snapshot) {
		TrieSnapshotDestroy(PrivilegesSnapshot);
	}
}

public CvarChangeAccess(const pcvar, const oldValue[], const newValue[]) {
	for (new i = 0; i < DefaultAccessLast; i++) {
		if (pcvar == DefaultAccess[i][DefaultAccessCvar]) {
			DefaultAccess[i][DefaultAccessFlags] = read_flags(newValue);
			break;
		}
	}
}

public CmdReload(id, level) {
	if (~get_user_flags(id) & level) {
		console_print(id, "You have no access to that command");
		return PLUGIN_HANDLED;
	}

	loadStart(true);
	return PLUGIN_HANDLED;
}

public client_connect(id) {
	if (Status == STATUS_LOADING) {
		NeedRecheck = true;
	}
	clear_user_state(id);
	clear_user_privilege(id);
	remove_user_flags(id, -1);
}

public client_authorized(id) {
	add_user_state(id, STATE_CONNECTING);
	makeUserAccess(id, checkUserFlags(id));
}

public client_putinserver(id) {
	if (get_user_state(id, STATE_CONNECTING)) {
		remove_user_state(id, STATE_CONNECTING);
	} else {
		makeUserAccess(id, checkUserFlags(id));
	}
	add_user_state(id, STATE_CONNECTED);
}

public client_disconnected(id) {
	clear_user_state(id);
	add_user_state(id, STATE_DISCONNECTED);
	remove_user_flags(id, -1);
	set_user_flags(id, DefaultAccess[DefaultAccessPlayer][DefaultAccessFlags]);
}

public TaskLoadTimeout() {
	loadFinish(true);
}

#if defined _reapi_included
public CBasePlayer_SetClientUserInfoName_Post(const id, const infobuffer[], const name[]) {
	remove_user_flags(id, -1);
	makeUserAccess(id, checkUserFlags(id, name));
}
#elseif defined _fakemeta_included
public SetCleintKeyValue_Post(const id, const infobuffer[], const key[], const value[]) {
	if(strcmp(key, "name") == 0) {
		remove_user_flags(id, -1);
		makeUserAccess(id, checkUserFlags(id, value));
	}
}
#else
public client_infochanged(id) {
	if (!is_user_connected(id)) {
		return PLUGIN_CONTINUE;
	}

	new oldname[MAX_NAME_LENGTH], newname[MAX_NAME_LENGTH];
	get_user_name(id, oldname, charsmax(oldname));
	get_user_info(id, "name", newname, charsmax(newname));
	if (strcmp(oldname, newname) != 0) {
		remove_user_flags(id, -1);
		makeUserAccess(id, checkUserFlags(id, newname));
	}
	return PLUGIN_CONTINUE;
}
#endif

loadStart(const bool:reload) {
	if (reload) {
		TrieClear(Privileges);
		NeedRecheck = true;
	}
	Status = STATUS_LOADING;
	PluginLoadedNum = 0;

	for (new i = 0; i < sizeof LoadStatusList; i++) {
		arrayset(LoadStatusList[i], 0, sizeof LoadStatusList[]);
	}
	LoadStatusNum = 0;
	ExecuteForward(Forwards[FWD_Loading], FReturn, reload ? 1 : 0);
	set_task(5.0, "TaskLoadTimeout", TIMEOUT_TASK_ID);
}

loadFinish(const bool:timeout) {
	Status = STATUS_LOADED;

	if (NeedRecheck) {
		for (new player = 1; player <= MaxClients; player++) {
			if (is_user_connected(player)) {
				makeUserAccess(player, checkUserFlags(player));
			}
		}
	}

	if (!timeout) {
		remove_task(TIMEOUT_TASK_ID);
	}
	
	if (PrivilegesSnapshot != Invalid_Snapshot) {
		TrieSnapshotDestroy(PrivilegesSnapshot);
	}
	PrivilegesSnapshot = TrieSnapshotCreate(Privileges);

	ExecuteForward(Forwards[FWD_Loaded], FReturn, 0);
}

makeUserAccess(const id, CheckResult:result) {
	switch (result) {
		case CHECK_DEFAULT: {
			remove_user_flags(id);
			if (is_user_bot(id)) {
				set_user_flags(id, DefaultAccess[DefaultAccessPlayer][DefaultAccessFlags]);
			} else {
				set_user_flags(id, DefaultAccess[DefaultAccessBOT][DefaultAccessFlags]);
			}
			
		}

		case CHECK_SUCCESS: {
			remove_user_flags(id);
			set_user_flags(id, Privilege[PrivilegeAccess]);
			UsersPrivilege[id] = Privilege;
			printConsole(id, "* Privileges set");
		}

		case CHECK_KICK: {
			server_cmd("kick #%d ^"%s^"", get_user_userid(id), KickReason);
		}
	}
	ExecuteForward(Forwards[FWD_Checked], FReturn, id, result);
}

CheckResult:checkUserFlags(const id, const name[] = "") {
	ExecuteForward(Forwards[FWD_Checking], FReturn, id);
	if (FReturn == PLUGIN_HANDLED) {
		return CHECK_IGNORE;
	}

	if (Mode == MODE_DISABLE) {
		return CHECK_IGNORE;
	}

	if (is_user_hltv(id)) {
		set_user_flags(id, DefaultAccess[DefaultAccessHLTV][DefaultAccessFlags]);
		return CHECK_IGNORE;
	}
	
	if (is_user_bot(id)) {
		return CHECK_DEFAULT;
	}
	
	#define MAX_AUTH_LENGTH 32
	new auth[MAX_AUTH_LENGTH], key[MAX_KEY_LENGTH], i = 0, flags, CheckResult:result = CHECK_DEFAULT;
	do {
		switch (SearchPriority[i]) {
			case 's': {
				get_user_authid(id, auth, charsmax(auth));
				flags = FLAG_AUTHID;
			}

			case 'i': {
				get_user_ip(id, auth, charsmax(auth), 1);
				flags = FLAG_IP;
			}

			case 'n', 'c': {
				if (name[0] != EOS) {
					copy(auth, charsmax(auth), name);
				} else {
					get_user_name(id, auth, charsmax(auth));
				}

				if (SearchPriority[i] == 'c') {
					strtolower(auth);
					flags = FLAG_CASE_SENSITIVE;
				} else {
					flags = 0;
				}
			}

			default: {
				flags = -1;
			}
		}

		if (flags == -1) {
			continue;
		}

		makeKey(auth, flags, key, charsmax(key));
		if (TrieKeyExists(Privileges, key)) {
			TrieGetArray(Privileges, key, Privilege, sizeof Privilege);
			new CheckResult:checked = setUserAccess(id);
			if (checked > result) {
				result = checked;
			}
		}
	} while (SearchPriority[++i] != EOS);
	if (Mode == MODE_KICK && result == CHECK_DEFAULT) {
		KickReason = "You have no entry to the server...";
		return CHECK_KICK;
	}
	return result;
}

CheckResult:setUserAccess(const id) {
	if (Privilege[PrivilegeFlags] & FLAG_NOPASS) {
		return CHECK_SUCCESS;
	} else {
		new password[UAC_MAX_PASSWORD_LENGTH];
		if (Privilege[PrivilegeOptions] & UAC_OPTIONS_MD5) {
			new infoPass[40];
			get_user_info(id, PasswordField, infoPass, charsmax(infoPass));
			hash_string(infoPass, Hash_Md5, password, charsmax(password));
		} else {
			get_user_info(id, PasswordField, password, charsmax(password));
		}

		if (strcmp(password, Privilege[PrivilegePassword]) == 0) {
			return CHECK_SUCCESS;
		} else if (Privilege[PrivilegeFlags] & FLAG_KICK) {
			KickReason = "Invalid Password!";
			return CHECK_KICK;
		} else {
			return CHECK_DEFAULT;
		}
	}
}

makeKey(const auth[], const flags, key[], len) {
	if (flags & FLAG_AUTHID) {
		formatex(key, len, "s%s", auth);
	} else if (flags & FLAG_IP) {
		formatex(key, len, "i%s", auth);
	} else if (flags & FLAG_CASE_SENSITIVE) {
		formatex(key, len, "c%s", auth);
		strtolower(key);
	} else {
		formatex(key, len, "n%s", auth);
	}
}

getLoadStatus(const source) {
	for (new i = 0; i < LoadStatusNum; i++) {
		if (LoadStatusList[i][LoadSource] == source) {
			return i;
		}
	}

	return -1;
}

getLoadStatusCount(const bool:loaded = true) {
	new result = 0;
	for (new i = 0; i < LoadStatusNum; i++) {
		if (LoadStatusList[LoadStatusNum][LoadLoaded] == loaded) {
			result++;
		}
	}

	return result;
}

printConsole(id, const msg[]) {
	message_begin(MSG_ONE, SVC_PRINT, .player = id);
	write_string(msg);
	message_end();
}

// NATIVES
public plugin_natives() {
	register_native("UAC_Push", "NativePush", 0);
	register_native("UAC_StartLoad", "NativeStartLoad", 0);
	register_native("UAC_FinishLoad", "NativeFinishLoad", 0);
	register_native("UAC_GetSource", "NativeGetSource", 0);
	register_native("UAC_GetId", "NativeGetId", 0);
	register_native("UAC_GetAccess", "NativeGetAccess", 0);
	register_native("UAC_GetFlags", "NativeGetFlags", 0);
	register_native("UAC_GetPassword", "NativeGetPassword", 0);
	register_native("UAC_GetPrefix", "NativeGetPrefix", 0);
	register_native("UAC_GetExpired", "NativeGetExpired", 0);
	register_native("UAC_SetAccess", "NativeSetAccess", 0);
	register_native("UAC_GetOptions", "NativeGetOptions", 0);
	register_native("UAC_CheckPlayer", "NativeCheckPlayer", 0);
	register_native("UAC_IterReset", "NativeIterReset", 0);
	register_native("UAC_IterEnded", "NativeIterEnded", 0);
	register_native("UAC_IterNext", "NativeIterNext", 0);
	register_native("UAC_GetPlayerPrivilege", "NativeGetPlayerPrivilege", 0);
}

public NativeStartLoad(plugin) {
	if (Status == STATUS_LOADED) {
		return 0;
	}

	LoadStatusList[LoadStatusNum][LoadSource] = plugin;
	LoadStatusList[LoadStatusNum][LoadLoaded] = false;
	LoadStatusNum++;

	new pluginName[64];
	get_plugin(plugin, .filename = pluginName, .len1 = charsmax(pluginName));
	log_amx("Module %s start loading privileges", pluginName);
	return 1;
}

public NativeFinishLoad(plugin) {
	if (Status == STATUS_LOADED) {
		return 0;
	}

	new status = getLoadStatus(plugin);
	if (status == -1) {
		return 0;
	}

	LoadStatusList[status][LoadLoaded] = true;
	new pluginName[64];
	get_plugin(plugin, .filename = pluginName, .len1 = charsmax(pluginName));
	log_amx("Module %s finish loading privileges. Loaded %d privileges", pluginName, PluginLoadedNum);
	PluginLoadedNum = 0;

	if (getLoadStatusCount(true) != LoadStatusNum) {
		return 1;
	}

	loadFinish(false);
	return 1;
}

public NativePush(plugin, argc) {
	CHECK_NATIVE_ARGS_NUM(argc, 8, 0)
	enum { arg_id = 1, arg_auth, arg_password, arg_access, arg_flags, arg_prefix, arg_expired, arg_options };
	
	clear_privilege();

	new auth[MAX_AUTHID_LENGTH], key[MAX_KEY_LENGTH];
	Privilege[PrivilegeSource] = plugin;
	Privilege[PrivilegeId] = get_param(arg_id);
	get_string(arg_auth, auth, charsmax(auth));
	get_string(arg_password, Privilege[PrivilegePassword], charsmax(Privilege[PrivilegePassword]));
	Privilege[PrivilegeAccess] = get_param(arg_access);
	Privilege[PrivilegeFlags] = get_param(arg_flags);
	get_string(arg_prefix, Privilege[PrivilegePrefix], charsmax(Privilege[PrivilegePrefix]));
	Privilege[PrivilegeExpired] = get_param(arg_expired);
	Privilege[PrivilegeOptions] = get_param(arg_options);

	makeKey(auth, Privilege[PrivilegeFlags], key, charsmax(key));
	TrieSetArray(Privileges, key, Privilege, sizeof Privilege);
	PluginLoadedNum++;
	
	if (Status == STATUS_LOADED) {
		if (PrivilegesSnapshot != Invalid_Snapshot) {
			TrieSnapshotDestroy(PrivilegesSnapshot);
		}
		PrivilegesSnapshot = TrieSnapshotCreate(Privileges);
	}

	return 1;
}

public NativeGetSource(plugin, argc) {
	return Privilege[PrivilegeSource];
}

public NativeGetId(plugin, argc) {
	return Privilege[PrivilegeId];
}

public NativeGetAccess(plugin, argc) {
	return Privilege[PrivilegeAccess];
}

public NativeGetFlags(plugin, argc) {
	return Privilege[PrivilegeFlags];
}

public NativeGetPassword(plugin, argc) {
	CHECK_NATIVE_ARGS_NUM(argc, 2, 0)
	enum { arg_dest = 1, arg_length };
	return set_string(arg_dest, Privilege[PrivilegePassword], get_param(arg_length));
}

public NativeGetPrefix(plugin, argc) {
	CHECK_NATIVE_ARGS_NUM(argc, 2, 0)
	enum { arg_dest = 1, arg_length };
	return set_string(arg_dest, Privilege[PrivilegePrefix], get_param(arg_length));
}

public NativeGetExpired(plugin, argc) {
	return Privilege[PrivilegeExpired];
}

public NativeGetOptions(plugin, argc) {
	return Privilege[PrivilegeOptions];
}

public NativeSetAccess(plugin, argc) {
	CHECK_NATIVE_ARGS_NUM(argc, 1, 0)
	enum { arg_access = 1 };
	Privilege[PrivilegeAccess] = get_param(arg_access);
	return 1;
}

public CheckResult:NativeCheckPlayer(plugin, argc) {
	CHECK_NATIVE_ARGS_NUM(argc, 1, CHECK_IGNORE)
	enum { arg_player = 1 };
	new player = get_param(arg_player);
	CHECK_NATIVE_PLAYER(player, CHECK_IGNORE)

	remove_user_flags(player, -1);
	new CheckResult:result = checkUserFlags(player);
	makeUserAccess(player, result);
	return result;
}

public NativeIterReset(plugin, argc) {
	PrivilegesIterate = 0;
	return 1;
}

public bool:NativeIterEnded(plugin, argc) {
	return bool:(PrivilegesIterate >= TrieSnapshotLength(PrivilegesSnapshot) - 1);
}

public NativeIterNext(plugin, argc) {
	PrivilegesIterate++;
	new key[MAX_KEY_LENGTH];
	TrieSnapshotGetKey(PrivilegesSnapshot, PrivilegesIterate, key, charsmax(key));
	TrieGetArray(Privileges, key, Privilege, sizeof Privilege);
	return 1;
}

public NativeGetPlayerPrivilege(plugin, argc) {
	CHECK_NATIVE_ARGS_NUM(argc, 1, 0)
	enum { arg_player = 1 };
	new player = get_param(arg_player);
	CHECK_NATIVE_PLAYER(player, 0)
	
	Privilege = UsersPrivilege[player];
	return 1;
}

checkAPIVersion() {
	for(new i, n = get_pluginsnum(), status[2], func; i < n; i++) {
		if(i == PluginId) {
			continue;
		}

		get_plugin(i, .status = status, .len5 = charsmax(status));

		//status debug || status running
		if(status[0] != 'd' && status[0] != 'r') {
			continue;
		}
	
		func = get_func_id("__uac_version_check", i);

		if(func == -1) {
			continue;
		}

		if(callfunc_begin_i(func, i) == 1) {
			callfunc_push_int(UAC_MAJOR_VERSION);
			callfunc_push_int(UAC_MINOR_VERSION);
			callfunc_end();
		}
	}
}
