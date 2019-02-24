#include <amxmodx>
#include "include/uac.inc"

new LogFile;

public plugin_init() {
	register_plugin("[UAC] AmxBans Loader", "1.0.0", "F@nt0M");
}

public plugin_cfg() {
	new path[128];
	get_localinfo("amxx_logs", path, charsmax(path));

	add(path, charsmax(path), "/adminload");
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