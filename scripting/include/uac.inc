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

native UAC_GetSource();
native UAC_GetId();
native UAC_GetAccess();
native UAC_GetFlags();
native UAC_GetPassword(dest[], length);
native UAC_GetNick(dest[], length);
native UAC_GetExpired();
native UAC_GetOptions();

// native UAC_ItterReset();
// native UAC_ItterNext();
// native UAC_ItterLast();