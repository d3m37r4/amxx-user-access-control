#if defined _uac_included
	#endinput
#endif

#define _uac_included

#include <uac_consts>

#define UAC_MAJOR_VERSION			0
#define UAC_MINOR_VERSION			1
#define UAC_MAINTENANCE_VERSION		1

stock const UAC_API_VERSION_STR[] = "0.1.0";

forward UAC_Loading(const reload);
forward UAC_Loaded(const reload);
forward UAC_Checking(const id);
forward UAC_Checked(const id, const UAC_CheckResult:result);
forward UAC_Pushing();
forward UAC_Pushed();

native UAC_StartLoad();
native UAC_FinishLoad();
native UAC_Push(const id, const authid[], const password[], const access, const flags, const prefix[], const expired, const otpions);
native UAC_GetSource();
native UAC_GetId();
native UAC_GetAccess();
native UAC_GetFlags();
native UAC_GetPassword(dest[], const length);
native UAC_GetPrefix(dest[], const length);
native UAC_GetExpired();
native UAC_GetOptions();
native UAC_SetAccess(const access);
native UAC_CheckPlayer(id);
native UAC_IterReset();
native UAC_IterEnded();
native UAC_IterNext();
native UAC_GetPlayerPrivilege(const player);

/*
* This is callback from GMX Core that gives major/minor versions for verifying compatibility for GMX versions.
* Do not modify this!
*/
public __uac_version_check(const majorVersion, const minorVersion) {
	if(majorVersion != UAC_MAJOR_VERSION) {
		set_fail_state("Api major version mismatch; expected %d, real %d", UAC_MAJOR_VERSION, majorVersion);
		return;
	}

	if(minorVersion < UAC_MINOR_VERSION){
		set_fail_state("Api minor version mismatch; expected at least %d, real %d", UAC_MINOR_VERSION, minorVersion);
		return;
	}
}
