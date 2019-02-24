#include <amxmodx>
#include "include/uac.inc"

public plugin_init() {
	register_plugin("[UAC] Users INI Loader", "1.0.0", "F@nt0M");
}

public UAC_Loading() {
	UAC_StartLoad();

	new fileName[128];
	get_localinfo("amxx_configsdir", fileName, charsmax(fileName));
	add(fileName, charsmax(fileName), "/users.ini");
	new file = fopen(fileName, "rt");
	if (!file) {
		UAC_FinishLoad();
		return;
	}

	new line[512], semicolonPos = 0;
	new sysTime = get_systime();
	new id = 0;
	new auth[44], password[34], access[32], flags[32], nick[32], expired[32], staticBanTime[2], expiredTime, options;

	while (!feof(file)) {
		arrayset(line, 0, sizeof line);
		fgets(file, line, charsmax(line));
		
		if ((semicolonPos = contain(line, ";")) > 0) {
			line[semicolonPos] = EOS;
		}

		trim(line);
		
		id++;
		if (line[0] == EOS || line[0]==';') {
			continue;
		}

		arrayset(auth, 0, sizeof auth);
		arrayset(password, 0, sizeof password);
		arrayset(access, 0, sizeof access);
		arrayset(flags, 0, sizeof flags);
		arrayset(nick, 0, sizeof nick);
		arrayset(expired, 0, sizeof expired);
		arrayset(staticBanTime, 0, sizeof staticBanTime);

		if (parse(line, auth, charsmax(auth), password, charsmax(password), access, charsmax(access), flags, charsmax(flags), 
			staticBanTime, charsmax(staticBanTime), expired, charsmax(expired), nick, charsmax(nick)) < 4) {
			continue;
		}

		if (nick[0] == EOS) {
			copy(nick, charsmax(nick), auth);
		}

		options = 0;
		if (!staticBanTime[0] || str_to_num(staticBanTime)) {
			options |= UAC_OPTIONS_STATIC_BANTIME;
		}

		expiredTime = expired[0] != EOS && strcmp(expired, "0") != 0 ? parse_time(expired, "%d.%m.%Y") : 0;

		new hashFile = 1;
		if (hashFile == 1 || (hashFile == 2 && isMD5(password))) {
			options |= UAC_OPTIONS_MD5;
		}

		if (expiredTime == 0 || expiredTime > sysTime) {
			UAC_Put(id, auth, password, read_flags(access), read_flags(flags), nick, expiredTime, options);
		}
	}
	fclose(file);
	UAC_FinishLoad();
}

stock bool:isMD5(const value[]) {
	new len = strlen(value);
	if (len != 32) {
		return false;
	}

	for (new i = 0; i < len; i++) {
		if (!('0' <= value[i] <= '9') && !('a' <= value[i] <= 'f') && !('A' <= value[i] <= 'F')) {
			return false;
		}
	}

	return true;
}