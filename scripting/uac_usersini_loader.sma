#include <amxmodx>
#include <uac>

public plugin_init() {
	register_plugin("[UAC] Users INI Loader", UAC_VERSION_STR, "GM-X Team");
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
	new auth[MAX_AUTHID_LENGTH], password[UAC_MAX_PASSWORD_LENGTH], access[32], flags[32], expired[32], staticBanTime[2], expiredTime, options;

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
		arrayset(expired, 0, sizeof expired);
		arrayset(staticBanTime, 0, sizeof staticBanTime);

		if (parse(line, auth, charsmax(auth), password, charsmax(password), access, charsmax(access), flags, charsmax(flags), 
			staticBanTime, charsmax(staticBanTime), expired, charsmax(expired)) < 4) {
			continue;
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
			UAC_Push(id, auth, password, read_flags(access), read_flags(flags), "", expiredTime, options);
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