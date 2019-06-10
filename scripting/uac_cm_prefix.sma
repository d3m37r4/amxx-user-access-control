#include <amxmodx>
#include <uac>

public plugin_init() {
	register_plugin("[UAC] CM Prefix", "1.0.0", "GM-X Team");
}

public UAC_Checked(const id, const UAC_CheckResult:found) {
	if (found != UAC_CHECK_SUCCESS) {
		return;
	}

	new prefix[UAC_MAX_PREFIX_LENGTH];
	UAC_GetPrefix(prefix, charsmax(prefix));

	server_cmd("cm_set_prefix #%d ^"%s^"", get_user_userid(id), prefix);
}
