#if defined _uac_included
	#endinput
#endif

#define _uac_included

enum (<<=1) {
	UAC_OPTIONS_MD5 = 1,
	UAC_OPTIONS_STATIC_BANTIME,
	UAC_OPTIONS_RESERVED_NICK,
}

native UAC_Put(const id, const authid[], const password[], const access, const flags, const nick[], const expired, const otpions);


forward UAC_Loading(const reload);
forward UAC_Loaded(const reload);
forward UAC_Checking(const id);
forward UAC_Checked(const id, const bool:found);

native UAC_StartLoad();
native UAC_FinishLoad();

// native UAC_GetUserSource(const id);
// native UAC_GetUserId(const id);
// native UAC_GetUserNick(const id, nick[], length);
// native UAC_GetuserExpired(const id);
// native UAC_GetUserOptions(const id);

// native UAC_ItterReset();
// native UAC_ItterNext();
// native UAC_ItterLast();