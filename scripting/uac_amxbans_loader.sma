#include <amxmodx>
#include <sqlx>
#include "include/uac.inc"

new Prefix[10] = "amx";
new Address[MAX_IP_WITH_PORT_LENGTH] = "";
new Handle:Tuple = Empty_Handle;

public plugin_init() {
    register_plugin("[UAC] AmxBans Loader", "1.0.0", "F@nt0M");
}

public plugin_end() {
	if (Tuple != Empty_Handle) {
		SQL_FreeHandle(Tuple);
	}
}

public UAC_Loading() {
	UAC_StartLoad();

	if (!makeDBTuble()) {
		loadFormBackup();
		UAC_FinishLoad();
		return;
	}
	
	new query[512];
	formatex(
		query, charsmax(query), 
		"SELECT aa.id, CONVERT(aa.steamid, BINARY) steamid, aa.password, aa.access, ads.custom_flags, aa.flags, CONVERT(aa.nickname, BINARY) nickname, \
		IF(ads.use_static_bantime = 'yes', 1, 0) use_static_bantime, aa.expired, si.id server_id FROM %s_amxadmins aa \
		JOIN %s_admins_servers ads ON aa.id = ads.admin_id JOIN %s_serverinfo si ON ads.server_id = si.id WHERE si.address = '%s' && (aa.expired = 0 OR aa.expired > %d)",
		Prefix, Prefix, Prefix, Address, get_systime()
	);

	SQL_ThreadQuery(Tuple, "LoadmDBHandle", query);
}

public LoadmDBHandle(failstate, Handle:query, const error[], errornum, const data[], size, Float:queuetime) {
	if (failstate != TQUERY_SUCCESS) {
		SQL_Error(query, error, errornum, failstate);
		SQL_FreeHandle(query);
		loadFormBackup();
		UAC_FinishLoad();
		return;
	}

	new backup[128], num = 0;
	get_localinfo("amxx_datadir", backup, charsmax(backup));
	add(backup, charsmax(backup), "/uac_amxx_users.bak");
	new file = fopen(backup, "wb");

	if (file) {
		fwrite(file, 1, BLOCK_BYTE);
		fwrite(file, num, BLOCK_INT);
	}
	
	new qcolId = SQL_FieldNameToNum(query, "id");
	new qcolAuth = SQL_FieldNameToNum(query, "steamid");
	new qcolPass = SQL_FieldNameToNum(query, "password");
	new qcolAccess = SQL_FieldNameToNum(query, "access");
	new qcolCustomAccess = SQL_FieldNameToNum(query, "custom_flags");
	new qcolFlags = SQL_FieldNameToNum(query, "flags");
	new qcolNick = SQL_FieldNameToNum(query, "nickname");
	new qcolStatic = SQL_FieldNameToNum(query, "use_static_bantime");
	new qcolExpired = SQL_FieldNameToNum(query, "expired");
	
	new id, auth[44], password[34], access[32], flags[32], nick[32], expired, options;
	while (SQL_MoreResults(query)) {
		arrayset(auth, 0, sizeof auth);
		arrayset(password, 0, sizeof password);
		arrayset(access, 0, sizeof access);
		arrayset(flags, 0, sizeof flags);
		arrayset(nick, 0, sizeof nick);
		options = UAC_OPTIONS_MD5;

		id = SQL_ReadResult(query, qcolId);
		SQL_ReadResult(query, qcolAuth, auth, charsmax(auth));
		SQL_ReadResult(query, qcolPass, password, charsmax(password));
		SQL_ReadResult(query, qcolCustomAccess, access, charsmax(access));
		if (access[0] == EOS) {
			SQL_ReadResult(query, qcolAccess, access, charsmax(access));
		}
		SQL_ReadResult(query, qcolFlags, flags, charsmax(flags));
		SQL_ReadResult(query, qcolNick, nick, charsmax(nick));
		if (SQL_ReadResult(query, qcolStatic) == 1) {
			options |= UAC_OPTIONS_STATIC_BANTIME;
		}
		expired = SQL_ReadResult(query, qcolExpired);
		UAC_Push(id, auth, password, read_flags(access), read_flags(flags), nick, expired, options);

		if (file) {
			fwrite(file, id, BLOCK_INT);
			fwrite_blocks(file, auth, sizeof auth, BLOCK_CHAR);
			fwrite_blocks(file, password, sizeof password, BLOCK_CHAR);
			fwrite(file, read_flags(access), BLOCK_INT);
			fwrite(file, read_flags(flags), BLOCK_INT);
			fwrite_blocks(file, nick, sizeof nick, BLOCK_CHAR);
			fwrite(file, expired, BLOCK_INT);
			fwrite(file, options, BLOCK_INT);
		}
		num++;
		
		SQL_NextRow(query);
	}
	SQL_FreeHandle(query);
	if (file) {
		fseek(file, 1, SEEK_SET);
		fwrite(file, num, BLOCK_INT);
		fclose(file);
	}
	UAC_FinishLoad();
}

loadFormBackup() {
	new path[128];
	get_localinfo("amxx_datadir", path, charsmax(path));
	add(path, charsmax(path), "/uac_amxx_users.bak");
	
	new file = fopen(path, "rb");
	if (!file) {
		return;
	}
	
	new version;
	fread(file, version, BLOCK_BYTE);
	if (version != 1) {
		return;
	}

	new now = get_systime(0);
	
	new num, loaded = 0;
	fread(file, num, BLOCK_INT);

	new id, auth[44], password[34], access, flags, nick[32], expired, options;
	while (loaded < num && !feof(file)) {
		arrayset(auth, 0, sizeof auth);
		arrayset(password, 0, sizeof password);
		arrayset(nick, 0, sizeof nick);
		fread(file, id, BLOCK_INT);
		fread_blocks(file, auth, sizeof auth, BLOCK_CHAR);
		fread_blocks(file, password, sizeof password, BLOCK_CHAR);
		fread(file, access, BLOCK_INT);
		fread(file, flags, BLOCK_INT);
		fread_blocks(file, nick, sizeof nick, BLOCK_CHAR);
		fread(file, expired, BLOCK_INT);
		fread(file, options, BLOCK_INT);

		if (expired == 0 || expired >= now) {
			UAC_Push(id, auth, password, access, flags, nick, expired, options);
		}

		loaded++;
	}
	
	fclose(file);
}

bool:makeDBTuble() {
	if (Tuple != Empty_Handle) {
		return true;
	}

	new fileName[128];
	get_localinfo("amxx_configsdir", fileName, charsmax(fileName));
	add(fileName, charsmax(fileName), "/uac_amxbans_loader.ini");

	new file = fopen(fileName, "rt");
	if (!file) {
		return false;
	}

	new line[64], key[32], value[32];
	new host[64] = "127.0.0.1", user[64] = "root", pass[64] = "", db[64] = "amx", charset[10] = "latin1", timeout = 5;
	new semicolonPos;
	while (!feof(file)) {
		fgets(file, line, charsmax(line));

		if ((semicolonPos = contain(line, ";")) != -1) {
			line[semicolonPos] = EOS;
		}

		trim(line);

		if (line[0] == EOS || line[0] == ';') {
			continue;
		}

		arrayset(key, 0, sizeof key);
		arrayset(value, 0, sizeof value);
		strtok2(line, key, charsmax(key), value, charsmax(value), '=', 0);
		trim(key);
		trim(value);
		remove_quotes(key);
		remove_quotes(value);

		if (strcmp(key, "hostname") == 0) {
			copy(host, charsmax(host), value);
		} else if (strcmp(key, "username") == 0) {
			copy(user, charsmax(user), value);
		} else if (strcmp(key, "password") == 0) {
			copy(pass, charsmax(pass), value);
		} else if (strcmp(key, "database") == 0) {
			copy(db, charsmax(db), value);
		} else if (strcmp(key, "prefix") == 0) {
			copy(Prefix, charsmax(Prefix), value);
		} else if (strcmp(key, "timeout") == 0) {
			timeout = str_to_num(value)
		} else if (strcmp(key, "charset") == 0) {
			copy(charset, charsmax(charset), value);
		} else if (strcmp(key, "address") == 0) {
			copy(Address, charsmax(Address), value);
		}
	}

	fclose(file);

	if (Address[0] == EOS){
		get_user_ip(0, Address, charsmax(Address), 0);
	} else if (contain(Address, ":") == -1) {
		add(Address, charsmax(Address), ":27015");
	}
	
	new type[10];
	SQL_GetAffinity(type, charsmax(type));
	if (strcmp(type, "mysql") != 0 && !SQL_SetAffinity("mysql")) {
	    log_amx("Failed to set affinity from %s to mysql", type);
	    return false;
	}
	
	Tuple = SQL_MakeDbTuple(host, user, pass, db, timeout);
	SQL_SetCharset(Tuple, charset);
	return true;
}

SQL_Error(Handle:query, const error[], errornum, failstate) {
	switch (failstate) {
		case TQUERY_CONNECT_FAILED: {
			log_amx("Connection failed!");
			log_amx("Message: %s (%d)", error, errornum);
		}

		case TQUERY_QUERY_FAILED: {
			new qstring[512];
			SQL_GetQueryString(query, qstring, charsmax(qstring));
			log_amx( "Query failed!");
			log_amx("Message: %s (%d)", error, errornum);
			log_amx("Query statement: %s", qstring);
		}
	}
}