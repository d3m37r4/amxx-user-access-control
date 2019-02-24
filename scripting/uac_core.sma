// TODO: Add get* natives
// TODO: Add natives for itterate
// TODO: Kick player on bad password

#include <amxmodx>
#include "include/uac.inc"

#define CHECK_NATIVE_ARGS_NUM(%1,%2) \
	if (%1 < %2) { \
		log_error(AMX_ERR_NATIVE, "Invalid num of arguments %d. Expected %d", %1, %2); \
		return 0; \
	}

enum {
	FWD_Loading,
	FWD_Loaded,
	FWD_Checking,
	FWD_Checked,
	FWD_Added,

	FWD_LAST
};

new Forwards[FWD_LAST], FReturn;

enum _:LoadStatus {
	LoadSource,
	bool:LoadLoaded
};

new LoadStatusList[5][LoadStatus], LoadStatusNum;

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
	PrivilegePassword[34],
	PrivilegeNick[32],
	PrivilegeExpired,
	PrivilegeOptions
};

new Trie:Privileges, Privilege[PrivilegeStruct];

#define clear_privilege() arrayset(Privilege, 0 , sizeof Privilege)

public plugin_precache() {
	Privileges = TrieCreate();

	Forwards[FWD_Loading] = CreateMultiForward("UAC_Loading", ET_IGNORE, FP_CELL);
	Forwards[FWD_Loaded] = CreateMultiForward("UAC_Loaded", ET_IGNORE, FP_CELL);
	Forwards[FWD_Checking] = CreateMultiForward("UAC_Checking", ET_IGNORE, FP_CELL);
	Forwards[FWD_Checked] = CreateMultiForward("UAC_Checked", ET_IGNORE, FP_CELL, FP_CELL);
	Forwards[FWD_Added] = CreateMultiForward("UAC_Added", ET_IGNORE);

	// TODO: Move to reload configs
	for (new i = 0; i < sizeof LoadStatusList; i++) {
		arrayset(LoadStatusList[i], 0, sizeof LoadStatusList[]);
	}
	ExecuteForward(Forwards[FWD_Loading], FReturn, 0);
}

public plugin_init() {
	register_plugin("[UAC] Core", "1.0.0", "F@nt0M");
	
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
}

public plugin_cfg() {
	Mode = get_cvar_num("amx_mode");
	for (new i = 0, flags[32]; i < DefaultAccessLast; i++) {
		get_pcvar_string(DefaultAccess[i][DefaultAccessCvar], flags, charsmax(flags));
		DefaultAccess[i][DefaultAccessFlags] = read_flags(flags);
	}
}

public plugin_end() {
	TrieDestroy(Privileges);

	for (new i = 0; i < FWD_LAST; i++) {
		DestroyForward(Forwards[i]);
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

public client_connect(id) {
	if (Status == STATUS_LOADING) {
		NeedRecheck = true;
	}
	clear_user_state(id);
	remove_user_flags(id, -1);
}

public client_authorized(id) {
	add_user_state(id, STATE_CONNECTING);
	makeUserAccess(id, checktUserFlags(id));
}

public client_putinserver(id) {
	if (get_user_state(id, STATE_CONNECTING)) {
		remove_user_state(id, STATE_CONNECTING);
	} else {
		makeUserAccess(id, checktUserFlags(id));
	}
	add_user_state(id, STATE_CONNECTED);
}

public client_disconnected(id) {
	clear_user_state(id);
	add_user_state(id, STATE_DISCONNECTED);
	remove_user_flags(id, -1);
	set_user_flags(id, DefaultAccess[DefaultAccessFlags][DefaultAccessFlags]);
}

makeUserAccess(const id, const CheckResult:result) {
	ExecuteForward(Forwards[FWD_Checking], FReturn, id);
	switch (result) {
		case CHECK_DEFAULT: {
			set_user_flags(id, DefaultAccess[DefaultAccessFlags][DefaultAccessFlags]);
			ExecuteForward(Forwards[FWD_Checked], FReturn, id, 0);
		}

		case CHECK_SUCCESS: {
			set_user_flags(id, Privilege[PrivilegeAccess]);
			ExecuteForward(Forwards[FWD_Checked], FReturn, id, 1);
		}

		case CHECK_KICK: {
			// Kick player
			ExecuteForward(Forwards[FWD_Checked], FReturn, id, 0);
		}
	}
}

CheckResult:checktUserFlags(const id, const name[] = "") {
	if (Mode == MODE_DISABLE) {
		return CHECK_IGNORE;
	}

	if (is_user_hltv(id)) {
		set_user_flags(id, DefaultAccess[DefaultAccessHLTV][DefaultAccessFlags]);
		return CHECK_IGNORE;
	}
	
	if (is_user_bot(id)) {
		set_user_flags(id, DefaultAccess[DefaultAccessBOT][DefaultAccessFlags]);
		return CHECK_IGNORE;
	}
	
	#define MAX_AUTH_LENGTH 32
	#define MAX_KEY_LENGTH 32
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

		makeKey(auth, flags, key, charsmax(key))
		if (TrieKeyExists(Privileges, key)) {
			TrieGetArray(Privileges, key, Privilege, sizeof Privilege);
			new CheckResult:checked = setUserAccess(id);
			if (checked > result) {
				result = checked;
			}
		}
	} while (SearchPriority[++i] != EOS);
	
	return result;
}

CheckResult:setUserAccess(const id) {
	if (Privilege[PrivilegeFlags] & FLAG_NOPASS) {
		return CHECK_SUCCESS;
	} else {
		new infoPass[40], password[34];
		get_user_info(id, PasswordField, infoPass, charsmax(infoPass));
		hash_string(infoPass, Hash_Md5, password, charsmax(password));

		if (strcmp(password, Privilege[PrivilegePassword]) == 0) {
			return CHECK_SUCCESS;
		} else {
			return Privilege[PrivilegeFlags] & FLAG_KICK ? CHECK_KICK : CHECK_DEFAULT;
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
		if (LoadStatusList[LoadStatusNum][LoadSource] == source) {
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

// NATIVES
public plugin_natives() {
	register_native("UAC_Put", "NativePut", 0);
	register_native("UAC_StartLoad", "NativeStartLoad", 0);
	register_native("UAC_FinishLoad", "NativeFinishLoad", 0);
	register_native("UAC_GetSource", "NativeGetSource", 0);
	register_native("UAC_GetId", "NativeGetId", 0);
	register_native("UAC_GetAccess", "NativeGetAccess", 0);
	register_native("UAC_GetFlags", "NativeGetFlags", 0);
	register_native("UAC_GetPassword", "NativeGetPassword", 0);
	register_native("UAC_GetNick", "NativeGetNick", 0);
	register_native("UAC_GetExpired", "NativeGetExpired", 0);
	register_native("UAC_GetOptions", "NativeGetOptions", 0);
}

public NativeStartLoad(plugin) {
	// TODO: Check General Status

	LoadStatusList[LoadStatusNum][LoadSource] = plugin;
	LoadStatusList[LoadStatusNum][LoadLoaded] = false;
	LoadStatusNum++;
	return 1;
}

public NativeFinishLoad(plugin) {
	// TODO: Check General Status

	new status = getLoadStatus(plugin);
	if (status == -1) {
		return 0;
	}

	LoadStatusList[status][LoadLoaded] = true;

	if (getLoadStatusCount(true) != LoadStatusNum) {
		return 1;
	}

	ExecuteForward(Forwards[FWD_Loaded], FReturn, 0);

	if (NeedRecheck) {
		// TODO: refactor it
		for (new player = 1; player <= MaxClients; player++) {
			if (is_user_connected(player)) {
				makeUserAccess(player, checktUserFlags(player));
			}
		}
	}
	return 1;
}

public NativePut(plugin, argc) {
	CHECK_NATIVE_ARGS_NUM(argc, 8)
	enum { arg_id = 1, arg_auth, arg_password, arg_access, arg_flags, arg_nick, arg_expired, arg_options };
	
	clear_privilege();

	new auth[32], key[34];
	Privilege[PrivilegeSource] = plugin;
	Privilege[PrivilegeId] = get_param(arg_id);
	get_string(arg_auth, auth, charsmax(auth));
	get_string(arg_password, Privilege[PrivilegePassword], 33);
	Privilege[PrivilegeAccess] = get_param(arg_access);
	Privilege[PrivilegeFlags] = get_param(arg_flags);
	get_string(arg_nick, Privilege[PrivilegeNick], 31);
	Privilege[PrivilegeExpired] = get_param(arg_expired);
	Privilege[PrivilegeOptions] = get_param(arg_options);

	makeKey(auth, Privilege[PrivilegeFlags], key, charsmax(key));
	TrieSetArray(Privileges, key, Privilege, sizeof Privilege);

	new tmp[32];
	get_flags(Privilege[PrivilegeAccess], tmp, 31);
	server_print("^t PUSH NEW ADMIN %d (%d) (auth %s) (access %s)", Privilege[PrivilegeId], plugin, auth, tmp);
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
	CHECK_NATIVE_ARGS_NUM(argc, 2)
	enum { arg_dest = 1, arg_length };
	return set_string(arg_dest, Privilege[PrivilegePassword], arg_length);
}

public NativeGetNick(plugin, argc) {
	CHECK_NATIVE_ARGS_NUM(argc, 2)
	enum { arg_dest = 1, arg_length };
	return set_string(arg_dest, Privilege[PrivilegeNick], arg_length);
}

public NativeGetExpired(plugin, argc) {
	return Privilege[PrivilegeExpired];
}

public NativeGetOptions(plugin, argc) {
	return Privilege[PrivilegeOptions];
}