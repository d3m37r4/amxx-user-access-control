#include <amxmodx>
#include <amxmisc>
#include <uac>

public plugin_init() {
	register_plugin("[UAC] Commands", UAC_VERSION_STR, "GM-X Team");

	register_dictionary("admincmd.txt")
	register_dictionary("common.txt")
	register_dictionary("adminhelp.txt")

	register_concmd("amx_who", "cmdWho", ADMIN_ADMIN, "- displays who is on server");
}

public cmdWho(id, level, cid) {
	if (!cmd_access(id, level, cid, 1))
		return PLUGIN_HANDLED

	new players[MAX_PLAYERS], inum, cl_on_server[64], authid[32], name[MAX_NAME_LENGTH], flags, sflags[32], plr
	new lImm[16], lRes[16], lAccess[16], lYes[16], lNo[16]
	
	formatex(lImm, charsmax(lImm), "%L", id, "IMMU")
	formatex(lRes, charsmax(lRes), "%L", id, "RESERV")
	formatex(lAccess, charsmax(lAccess), "%L", id, "ACCESS")
	formatex(lYes, charsmax(lYes), "%L", id, "YES")
	formatex(lNo, charsmax(lNo), "%L", id, "NO")
	
	get_players(players, inum)
	format(cl_on_server, charsmax(cl_on_server), "%L", id, "CLIENTS_ON_SERVER")
	console_print(id, "^n%s:^n #  %-16.15s %-20s %-8s %-4.3s %-4.3s %s", cl_on_server, "nick", "authid", "userid", lImm, lRes, lAccess)
	
	for (new a = 0; a < inum; ++a)
	{
		plr = players[a]
		get_user_authid(plr, authid, charsmax(authid))
		get_user_name(plr, name, charsmax(name))
		flags = get_user_flags(plr)
		get_flags(flags, sflags, charsmax(sflags))
		console_print(id, "%2d  %-16.15s %-20s %-8d %-6.5s %-6.5s %s", plr, name, authid, 
		get_user_userid(plr), (flags&ADMIN_IMMUNITY) ? lYes : lNo, (flags&ADMIN_RESERVATION) ? lYes : lNo, sflags)
	}
	
	console_print(id, "%L", id, "TOTAL_NUM", inum)
	get_user_authid(id, authid, charsmax(authid))
	get_user_name(id, name, charsmax(name))
	log_amx("Cmd: ^"%s<%d><%s><>^" ask for players list", name, get_user_userid(id), authid) 
	
	return PLUGIN_HANDLED
}