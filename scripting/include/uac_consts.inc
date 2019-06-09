#if defined _uac_consts_included
	#endinput
#endif

#define _uac_consts_included

#define UAC_GROUP_MAX_TITLE_LENGTH 32

enum (<<=1) {
	UAC_OPTIONS_MD5 = 1,
	UAC_OPTIONS_STATIC_BANTIME,
	UAC_OPTIONS_RESERVED_NICK,
}

enum UAC_CheckResult {
	UAC_CHECK_IGNORE,
	UAC_CHECK_DEFAULT,
	UAC_CHECK_SUCCESS,
	UAC_CHECK_KICK,
};
