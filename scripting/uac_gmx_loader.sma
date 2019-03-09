#include <amxmodx>
#include <json>
#include "include/uac.inc"

new FilePath[64];
new bool:Loaded = false;

enum {
	GMX_REQ_STATUS_ERROR = 0,
	GMX_REQ_STATUS_OK = 1
};

enum AUTH_TYPE {
	AUTH_TYPE_STEAM,
	AUTH_TYPE_STEAM_AND_PASS,
	AUTH_TYPE_NICK_AND_PASS,
	AUTH_TYPE_STEAM_AND_HASH,
	AUTH_TYPE_NICK_AND_HASH
};

#define MAX_GROUP_TITLE_LENGTH 32

enum _:GroupInfo {
	GroupId,
	GroupTitle[MAX_GROUP_TITLE_LENGTH],
	GroupFlags,
	GroupPriority
}

new Array:Groups = Invalid_Array, GroupsNum, Group[GroupInfo];

native GamexMakeRequest(const endpoint[], JSON:data, const callback[], const param = 0);

public plugin_init() {
	register_plugin("[UAC] GM-X Loader", "1.0.0", "F@nt0M");
}

public UAC_Loading() {
	UAC_StartLoad();

	new bool:needRequest = true;
	if (!Loaded) {
		get_localinfo("amxx_datadir", FilePath, charsmax(FilePath));
		add(FilePath, charsmax(FilePath), "/gmx/privileges.json");
		if (file_exists(FilePath)) {
			new JSON:data = json_parse(FilePath, true);
			if (data != Invalid_JSON && parseData(data)) {
				needRequest = false;
			}
		}
	}

	if (needRequest) {
		GamexMakeRequest("server/privileges", Invalid_JSON, "OnResponse");
	} else {
		UAC_FinishLoad();
	}
	Loaded = true;
}

public OnResponse(const status, const JSON:data, const userid) {
	if (status != GMX_REQ_STATUS_OK) {
		UAC_FinishLoad();
		return;
	}

	parseData(data);
	UAC_FinishLoad();
	
	json_serial_to_file(data, FilePath, false);
	UAC_FinishLoad();
}

bool:parseData(const JSON:data) {
	if (!json_is_object(data)) {
		server_print("^t IS NOT OBJECT")
		return false;
	}

	new JSON:tmp;
	if (json_object_has_value(data, "groups", JSONArray)) {
		tmp = json_object_get_value(data, "groups");
		parseGroups(tmp);
		json_free(tmp);
	}
	if (json_object_has_value(data, "privileges", JSONArray)) {
		tmp = json_object_get_value(data, "privileges");
		parsePrivileges(tmp);
		json_free(tmp);
	}

	return true;
}

parseGroups(const JSON:data) {
	if (Groups == Invalid_Array) {
		Groups = ArrayCreate(GroupInfo, 1);
	} else {
		ArrayClear(Groups);
	}
	for (new i = 0, n = json_array_get_count(data), JSON:tmp; i < n; i++) {
		tmp = json_array_get_value(data, i);
		if (json_is_object(tmp)) {
			arrayset(Group, 0, sizeof Group);
			Group[GroupId] = json_object_has_value(tmp, "id", JSONNumber) ? json_object_get_number(tmp, "id") : 0;
			if (json_object_has_value(tmp, "title", JSONString)) {
				json_object_get_string(tmp, "title", Group[GroupTitle], charsmax(Group[GroupTitle]));
			}
			Group[GroupFlags] = json_object_has_value(tmp, "flags", JSONNumber) ? json_object_get_number(tmp, "flags") : 0;
			Group[GroupPriority] = json_object_has_value(tmp, "priority", JSONNumber) ? json_object_get_number(tmp, "priority") : 0;
			ArrayPushArray(Groups, Group, sizeof Group);
		}
		json_free(tmp);
	}
	GroupsNum = ArraySize(Groups);
}

parsePrivileges(const JSON:data) {
	new now = get_systime(0);
	new id, auth[44], password[34], access, flags, nick[32], expired, options, authTypeStr[32], AUTH_TYPE:authType;
	for (new i = 0, n = json_array_get_count(data), JSON:tmp; i < n; i++) {
		tmp = json_array_get_value(data, i);
		if (!json_is_object(tmp)) {
			json_free(tmp);
			continue;
		}

		arrayset(auth, 0, sizeof auth);
		arrayset(password, 0, sizeof password);
		arrayset(nick, 0, sizeof nick);
		access = 0;
		flags = 0;
		expired = 0;
		options = 0;

		id = json_object_has_value(tmp, "id", JSONNumber) ? json_object_get_number(tmp, "id") : 0;
		if (json_object_has_value(tmp, "password", JSONString)) {
			json_object_get_string(tmp, "password", password, charsmax(password));
		}

		if (json_object_has_value(tmp, "auth_type", JSONString)) {
			json_object_get_string(tmp, "auth_type", authTypeStr, charsmax(authTypeStr));
			authType = getAuthType(authTypeStr);
		} else {
			authType = AUTH_TYPE_STEAM;
		}
		
		switch (authType) {
			case AUTH_TYPE_STEAM: {
				flags |= FLAG_AUTHID | FLAG_NOPASS;
				if (json_object_has_value(tmp, "steamid", JSONString)) {
					json_object_get_string(tmp, "steamid", auth, charsmax(auth));
				}
			}

			case AUTH_TYPE_STEAM_AND_PASS: {
				flags |= FLAG_AUTHID | FLAG_KICK;
				if (json_object_has_value(tmp, "steamid", JSONString)) {
					json_object_get_string(tmp, "steamid", auth, charsmax(auth));
				}
				options |= UAC_OPTIONS_MD5;
			}

			case AUTH_TYPE_NICK_AND_PASS: {
				flags |= FLAG_KICK;
				if (json_object_has_value(tmp, "nick", JSONString)) {
					json_object_get_string(tmp, "nick", auth, charsmax(auth));
				}
				options |= UAC_OPTIONS_MD5;
			}
		}

		if (json_object_has_value(tmp, "nick", JSONString)) {
			json_object_get_string(tmp, "nick", nick, charsmax(nick));
		}

		parseUserPrivileges(tmp, access, expired);

		if (expired == 0 || expired < now) {
			server_print("^t password '%s'", password)
			UAC_Put(id, auth, password, access, flags, nick, expired, options);
		}
		json_free(tmp);
	}
}

parseUserPrivileges(const JSON:data, &access, &expired) {
	if (!json_object_has_value(data, "privileges", JSONArray)) {
		return;
	}

	new JSON:tmp = json_object_get_value(data, "privileges");
	for (new i = 0, n = json_array_get_count(tmp), JSON:privilege, group_id, priority = -1; i < n; i++) {
		privilege = json_array_get_value(tmp, i);
		group_id = json_object_has_value(privilege, "group_id", JSONNumber) ? json_object_get_number(privilege, "group_id") : 0;
		if (!getGroup(group_id)) {
			continue;
		}

		access |= Group[GroupFlags];
		if (Group[GroupPriority] > priority) {
			priority = Group[GroupPriority];

			if (json_object_has_value(privilege, "expired_at", JSONNull)) {
				expired = 0;
			} else if (json_object_has_value(privilege, "expired_at", JSONNumber)) {
				expired = json_object_get_number(privilege, "expired_at");
			}
		}
		json_free(privilege);
	}
	json_free(tmp);
}

AUTH_TYPE:getAuthType(const authType[]) {
	if (strcmp(authType, "steamid_pass") == 0) {
		return AUTH_TYPE_STEAM_AND_PASS;
	} else if (strcmp(authType, "nick_pass") == 0) {
		return AUTH_TYPE_NICK_AND_PASS;
	} else if (strcmp(authType, "steamid_hash") == 0) {
		return AUTH_TYPE_STEAM_AND_HASH;
	} else if (strcmp(authType, "nick_hash") == 0) {
		return AUTH_TYPE_NICK_AND_HASH;
	} else {
		return AUTH_TYPE_STEAM;
	}
}

bool:getGroup(const id) {
	if (id == 0) {
		return false;
	}

	for (new i = 0; i < GroupsNum; i++) {
		if (ArrayGetArray(Groups, i, Group, sizeof Group) && Group[GroupId] == id) {
			return true;
		}
	}

	return false;
}