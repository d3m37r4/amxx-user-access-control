#include <amxmodx>
#include "include/uac.inc"

new LogFile;

public plugin_init() {
	register_plugin("[UAC] Logger", "1.0.0", "GM-X Team");
}

public plugin_cfg() {
	new path[128];
	get_localinfo("amxx_logs", path, charsmax(path));

	add(path, charsmax(path), "/user-access-control");
	if (!dir_exists(path)) {
		mkdir(path);
	}

	new time[16];
	get_time("/L%Y%m%d.log", time, charsmax(time));
	add(path, charsmax(path), time);

	new map[64];
	get_mapname(map, charsmax(map));

	LogFile = fopen(path, "at");
	if (!LogFile) {
		set_fail_state("Couldn't open %s for write. Check permissions.", path);
	} else {
		fprintf(LogFile, "Start of log session (map %s)", map);
	}
}

public plugin_end() {
	fclose(LogFile);
}

public UAC_Checked(const id, const UAC_CheckResult:found) {
	if (found != UAC_CHECK_SUCCESS) {
		return;
	}

	new name[MAX_NAME_LENGTH], steamid[MAX_AUTHID_LENGTH], ip[MAX_IP_LENGTH], access[32], prefix[MAX_PREFIX_LENGTH], expired[32];
	
	get_user_name(id, name, charsmax(name));
	get_user_authid(id, steamid, charsmax(steamid));
	get_user_ip(id, ip, charsmax(ip), 1);
	get_flags(UAC_GetAccess(), access, charsmax(access));
	UAC_GetPrefix(prefix, charsmax(prefix));
	if (UAC_GetExpired() > 0) {
		format_time(expired, charsmax(expired), "%d.%m.%Y - %H:%M:%S", UAC_GetExpired());
	} else {
		expired = "never";
	}
	fprintf(
		LogFile, 
		"Client '%s' (steamid '%s')(ip '%s') became an admin (access ^"%s^") (prefix ^"%s^") (id %d) (expired %s)^n",
		name, steamid, ip, access, prefix,  UAC_GetId(), expired
	);

	server_print(
		"Client '%s' (steamid '%s')(ip '%s') became an admin (access ^"%s^") (prefix ^"%s^") (id %d) (expired %s)",
		name, steamid, ip, access, prefix,  UAC_GetId(), expired
	);
}