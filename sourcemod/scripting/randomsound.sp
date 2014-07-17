#include <sourcemod>
#include <emitsoundany>
#include <string>
#include <regex>

/*
 *	Random Sound Plugin (rds)
 *  	based on quakesound plugin
 *
 *	v 1.0 - add random sounds for css/csgo
 *	
 *  	v 1.1 - add client preference / store it on server side
 *  
 *
 */

#pragma semicolon 1

//sound event count
#define ALL_SOUNDS 29
#define NUM_SOUNDS 28
#define MAX_FILE_LEN 150
#define PATH_FOLDER "folder"
#define PATTERN_SEARCH "pattern"
#define UNDEFINED_TIME -1.0
#define KILL_ENUM_NUM 11

//sn - storage name

#define SN_ALLSOUND			"allsound"
#define SN_ROUNDFREEZEEND	"roundfreezeend"
#define SN_ROUNDEND			"roundend"
#define SN_QUAKE			"quake"
#define SN_JOINGAME 		"joingame"

#define ON_SOUND 0
#define OFF_SOUND 1

enum SoundType
{
#define SOUNDS(%1,%2) %1
	#include <random_sounds>
#undef SOUNDS
};

enum SoundSetting
{
	NOBODY = 0,
	CLIENT,
	ATTACKER_VICTIM,
	ALL
};


enum MenuField
{
	SOUNDS_STATUS = 0,
	// TEXT_STATUS,
	ROUNDFREEZEEND_STATUS,
	ROUNDEND_STATUS,
	QUAKESOUND_STATUS,
	JOINGAME_STATUS,
};

static const String:g_SoundNames[ALL_SOUNDS][] = 
{
#define SOUNDS(%1,%2) %2
	#include <random_sounds>
#undef SOUNDS
};

new Handle:g_SoundList[NUM_SOUNDS] = {INVALID_HANDLE, ...};
new Handle:g_Volume = INVALID_HANDLE;
new Handle:g_Enable = INVALID_HANDLE;
new Handle:g_SoundDelay = INVALID_HANDLE;
new Handle:g_ComboDelay = INVALID_HANDLE;
new Handle:g_DisplayTime = INVALID_HANDLE;
new Handle:g_HelpEnable = INVALID_HANDLE;
new Handle:g_HelpDelay = INVALID_HANDLE;
new Handle:g_HelpTimers[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};

//client preference storage
new Handle:g_CPStorage = INVALID_HANDLE; 
new String:g_CPPath[MAX_FILE_LEN];

new bool:g_FirstBlood = false;
new bool:g_IsHooked = false;
new bool:g_LateLoaded = false;

new SoundSetting:g_SoundsSetting[NUM_SOUNDS] = {ALL, ...};
new SoundType:g_KillNumSetting[50];
new g_PlayerKills[MAXPLAYERS + 1] = {0, ...};
new g_HeadShots[MAXPLAYERS + 1] = {0, ...};
new g_ClientSoundSetPreference[MAXPLAYERS + 1][NUM_SOUNDS];
new g_ClientSoundEnable[MAXPLAYERS + 1] = {ON_SOUND, ...};
new Float:g_LastKillTime[MAXPLAYERS + 1] = {UNDEFINED_TIME, ...};
new g_ComboScore[MAXPLAYERS + 1] = {0, ...};

public Plugin:myinfo =
{
	name = "Random Sounds (rds)",
	description = "play random sounds on events",
	author = "Exeorb Dev Team",
	version = "1.1",
	url = "exeorb.com"
};

stock bool:IsCSS()
{
	return GetEngineVersion() == Engine_CSGO; 
}

stock bool:IsCSGO()
{
	return GetEngineVersion() == Engine_CSS;
}

stock LogSoundsList()
{
	decl String:name[MAX_FILE_LEN];
	for(new soundKey = 0; soundKey < NUM_SOUNDS; ++soundKey)
	{
		PrintToServer("%s", g_SoundNames[soundKey]);
		new Handle:sounds = g_SoundList[soundKey];
		if (sounds == INVALID_HANDLE)
		{
			PrintToServer("empty");
		}
		else
		{
			for (new i = 0; i < GetArraySize(sounds); ++i)
			{
				GetArrayString(sounds, i, name, sizeof(name));
				PrintToServer("%s", name);
			}
		}
	}
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
   g_LateLoaded = late;
   return APLRes_Success;
}

public OnPluginStart()
{
	if (!IsCSS() && !IsCSGO())
	{
		SetFailState("Plugin enable only on css and csgo:(");
	}

	g_Enable = CreateConVar("rds_enable", "1", "Enable the plugin");
	g_Volume = CreateConVar("rds_volume", "1.0", "Volume: should be a number between 0.0. and 1.0");
	g_SoundDelay = CreateConVar("rds_sound_delay", "0.5", "Sound Delay");
	g_ComboDelay = CreateConVar("rds_combo_delay", "2.0", "Max delay between combos");
	g_DisplayTime = CreateConVar("rds_display_time", "20", "Maximum time to leave menu on the screen");
	g_HelpEnable = CreateConVar("rds_help_enable", "1", "Enable help advertisement");
	g_HelpDelay = CreateConVar("rds_help_delay", "30.0", "Maximum time between help advertisement");

	HookConVarChange(g_Enable, EnableChanged);

	RegConsoleCmd("rds", Menu);

	AutoExecConfig(true, "rds");

	g_CPStorage = CreateKeyValues("RandomSoundUserPref");

	BuildPath(Path_SM, g_CPPath, MAX_FILE_LEN, "data/rds_storage.txt");

	if(!FileToKeyValues(g_CPStorage, g_CPPath))
	{
		KeyValuesToFile(g_CPStorage, g_CPPath);
	}

	// if (g_LateLoaded)
	// {

	// }
}

public OnMapStart()
{
	LoadSoundList();
	PrepareSounds();
}

public OnConfigsExecuted()
{
	HookEvents();
}

public Action:TimerAnnounce(Handle:timer, any:client)
{
	if (!client || !IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Stop;

	PrintToChat(client, "%s", "say !rds for sound settings");
	return Plugin_Continue;
}

public OnPluginEnd()
{
	for(new soundKey = 0; soundKey < NUM_SOUNDS; ++soundKey)
	{
		if (g_SoundList[soundKey] != INVALID_HANDLE)
		{
			CloseHandle(g_SoundList[soundKey]);
		}
	}
	UnhookEvents();
}

static LoadSoundList()
{
	new Handle:kvQSL = CreateKeyValues("RandomSoundsList");
	decl String:fileQSL[MAX_FILE_LEN];
	decl FileType:ftype;
	decl String:path[64], String:pattern[64];
	decl String:fullPath[64];
	decl String:sound[192];
	decl String:error[192];

	BuildPath(Path_SM, fileQSL, MAX_FILE_LEN, "configs/rds_list.cfg");

	if (!FileExists(fileQSL))
	{
		SetFailState("configs/rds_list.cfg not found");
	}

	if (!FileToKeyValues(kvQSL, fileQSL))
	{
		SetFailState("configs/rds_list.cfg not correctly structured");
	}

	for(new soundKey = 0; soundKey < NUM_SOUNDS; ++soundKey) 
	{
		KvRewind(kvQSL);

		KvJumpToKey(kvQSL, g_SoundNames[soundKey]);

		KvGetString(kvQSL, PATTERN_SEARCH, pattern, sizeof(pattern));
		KvGetString(kvQSL, PATH_FOLDER, path, sizeof(path));
		g_SoundsSetting[soundKey] = SoundSetting:KvGetNum(kvQSL, "config", cell:ALL);


		Format(fullPath, sizeof(fullPath), "sound/%s", path);

		new Handle:dir = OpenDirectory(fullPath);

		if (dir == INVALID_HANDLE)
		{
			SetFailState("Can't open %s", fullPath);
		}

		if (StrEqual(pattern, ""))
		{
			continue;
		}

		g_SoundList[soundKey] = CreateArray(257);
		Format(pattern, sizeof(pattern), "%s\\w*\\.mp3$", pattern);

		new Handle:regex = CompileRegex(pattern, PCRE_MULTILINE, error, sizeof(error));
	
		if (regex == INVALID_HANDLE)
		{
			SetFailState("%s", error);
		}

		if(SoundType:soundKey >= KILL1 && SoundType:soundKey <= KILL11)
		{
			g_KillNumSetting[KvGetNum(kvQSL, "kills")] = SoundType:soundKey;
		}

		while (ReadDirEntry(dir, sound, sizeof(sound), ftype))
		{
			if (ftype != FileType_File)
			{
				continue;
			}

			if (MatchRegex(regex, sound) > 0)
			{
				new String:tmp[MAX_FILE_LEN];
				Format(tmp, sizeof(tmp), "%s/%s", path, sound);
				PushArrayString(g_SoundList[soundKey], tmp);
			}
		}

		if (!GetArraySize(g_SoundList[soundKey]))
		{
			CloseHandle(g_SoundList[soundKey]);
			g_SoundList[soundKey] = INVALID_HANDLE;
		}

		CloseHandle(regex);
		CloseHandle(dir);
	}

	CloseHandle(kvQSL);
}

static PrepareSounds()
{
	for(new soundKey = 0; soundKey < NUM_SOUNDS; ++soundKey)
	{
		new Handle:sounds = g_SoundList[soundKey];
		if (sounds == INVALID_HANDLE)
		{
			continue;
		}

		decl String:name[MAX_FILE_LEN];
		decl String:download[MAX_FILE_LEN];

		for (new i = 0; i < GetArraySize(sounds); ++i)
		{
			GetArrayString(sounds, i, name, sizeof(name));
			Format(download, MAX_FILE_LEN, "sound/%s", name);
			AddFileToDownloadsTable(download);
			PrecacheSoundAny(name);
		}
	}
}

static LoadClientPreferenceFor(client)
{
	decl String:steamId[20];
	GetClientAuthString(client, steamId, sizeof(steamId));
	KvRewind(g_CPStorage);

	if (KvJumpToKey(g_CPStorage, steamId))
	{
		g_ClientSoundEnable[client] = bool:KvGetNum(g_CPStorage, SN_ALLSOUND, ON_SOUND);
		g_ClientSoundSetPreference[client][ROUNDFREEZEEND] = bool:KvGetNum(g_CPStorage, SN_ROUNDFREEZEEND, ON_SOUND);
		g_ClientSoundSetPreference[client][ROUNDEND] = bool:KvGetNum(g_CPStorage, SN_ROUNDEND, ON_SOUND);
		g_ClientSoundSetPreference[client][JOINGAME] = bool:KvGetNum(g_CPStorage, SN_JOINGAME, ON_SOUND);

		for (new SoundType:key = FIRSTBLOOD; key <= MONSTERKILL; ++key)
		{
			g_ClientSoundSetPreference[client][key] = bool:KvGetNum(g_CPStorage, SN_QUAKE, ON_SOUND);
		}

		for (new SoundType:key = KILL1; key <= KILL11; ++key)
		{
			g_ClientSoundSetPreference[client][key] = bool:KvGetNum(g_CPStorage, SN_QUAKE, ON_SOUND);
		}
	}
	else
	{
		KvJumpToKey(g_CPStorage, steamId, true);
		KvSetNum(g_CPStorage, SN_ALLSOUND, ON_SOUND);
		KvSetNum(g_CPStorage, SN_ROUNDFREEZEEND, ON_SOUND);
		KvSetNum(g_CPStorage, SN_ROUNDEND, ON_SOUND);
		KvSetNum(g_CPStorage, SN_QUAKE, ON_SOUND);
		KvSetNum(g_CPStorage, SN_JOINGAME, ON_SOUND);
	}
	
}

public Action:APlaySoundToClient(Handle:timer, Handle:pack)
{
	decl String:sound[MAX_FILE_LEN];
	new client;

	ResetPack(pack, false);

	client = ReadPackCell(pack);
	ReadPackString(pack, sound, sizeof(sound));

	if (client && IsClientInGame(client) && !IsFakeClient(client))
	{
		EmitSoundToClientAny(client, sound, _, _, _, _, GetConVarFloat(g_Volume));
	}

	KillTimer(timer, false);
}

static PlaySoundToClient(client, const String:sound[], SoundType:key)
{
	if (g_ClientSoundEnable[client] == OFF_SOUND || g_ClientSoundSetPreference[client][key] == OFF_SOUND)
		return;
	new Handle:pack;
	CreateDataTimer(GetConVarFloat(g_SoundDelay), APlaySoundToClient, pack);
	WritePackCell(pack, client);
	WritePackString(pack, sound);
}

static PlaySound(SoundType:key, victim = 0, attacker = 0)
{
	if (!GetConVarBool(g_Enable))
	{
		return;
	}

	new Handle:sounds = g_SoundList[key];
	if (sounds == INVALID_HANDLE)
	{
		return;
	}

	new random = GetRandomInt(0, GetArraySize(sounds) - 1);
	new String:sound[MAX_FILE_LEN];
	GetArrayString(sounds, random, sound, sizeof(sound));

	switch(g_SoundsSetting[key])
	{
		case CLIENT : 
		{
			PlaySoundToClient(victim, sound, key);
		}
		case ATTACKER_VICTIM : 
		{
			PlaySoundToClient(victim, sound, key);
			PlaySoundToClient(attacker, sound, key);
		}
		case ALL : 
		{
			new playersConnected = GetMaxClients();
			for (new i = 1; i < playersConnected; ++i)
			{
				PlaySoundToClient(i, sound, key);
			}
		}
	}
}

static AllReset()
{
	for(new i = 1; i < MAXPLAYERS + 1; ++i)
	{
		g_PlayerKills[i] = 0;
		g_LastKillTime[i] = UNDEFINED_TIME;
		g_HeadShots[i] = 0;
		g_ComboScore[i] = 0;
	}
	g_FirstBlood = false;

	KvRewind(g_CPStorage);
	KeyValuesToFile(g_CPStorage, g_CPPath);
}

public OnClientPutInServer(client)
{
	if (GetConVarBool(g_Enable))
	{
		if (client && !IsFakeClient(client))
		{
			LoadClientPreferenceFor(client);

			PlaySound(JOINGAME, client);

			if (GetConVarBool(g_HelpEnable))
			{
				g_HelpTimers[client] = CreateTimer(GetConVarFloat(g_HelpDelay), TimerAnnounce, client, 
						TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}
}

public EventPlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new SoundType:stype = UNDEFINED;
	decl String:weapon[64];
	new victimId = GetEventInt(event, "userid");
	new attackerId = GetEventInt(event, "attacker");
	new attackerClient = GetClientOfUserId(attackerId);
	new victimClient = GetClientOfUserId(victimId);
	new bool:headshot = GetEventBool(event, "headshot");
	GetEventString(event, "weapon", weapon, sizeof(weapon));

	if (victimClient)
	{
		g_PlayerKills[victimClient] = 0;
	}

	if (victimId != attackerId)
	{
		if (attackerClient)
		{
			++g_PlayerKills[attackerClient];
		}

		if (GetClientTeam(attackerClient) == GetClientTeam(victimClient))
		{
			stype = TEAMKILL;
		}
		else
		{
			if (headshot)
			{
				switch(++g_HeadShots[attackerClient])
				{
					case 3 : stype = HEADSHOT3;
					case 5 : stype = HEADSHOT5;
					default : stype = HEADSHOT1;
				}
			}

			if (g_KillNumSetting[g_PlayerKills[attackerClient]])
			{
				stype = g_KillNumSetting[g_PlayerKills[attackerClient]];
			}

			if (IsGrenade(weapon))
			{
				stype = GRENADE;
			}

			if (IsKnife(weapon))
			{
				stype = KNIFE;
			}

			if((GetEngineTime() - g_LastKillTime[attackerClient]) < GetConVarFloat(g_ComboDelay) 
				|| g_LastKillTime[attackerClient] == UNDEFINED_TIME) 
			{
				switch(++g_ComboScore[attackerClient])
				{
					case 2:
						stype = DOUBLEKILL;
					case 3:
						stype = TRIPLEKILL;
					case 4:
						stype = QUAD;
					case 5:
						stype = MONSTERKILL;
				}
			}
			else
			{
				g_ComboScore[attackerClient] = 0;
			}

			g_LastKillTime[attackerClient] = GetEngineTime();
		}

		if (!g_FirstBlood)
		{
			g_FirstBlood = true;
			stype = FIRSTBLOOD;
		}
	}
	else
	{
		stype = SUICIDE;
	}

	if (stype != UNDEFINED)
	{
		PlaySound(stype, victimClient, attackerClient);
	}
}

public EventFreezeEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	PlaySound(ROUNDFREEZEEND);
}

public EventRoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	PlaySound(ROUNDEND);
}

public EventRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	AllReset();
	PlaySound(ROUNDSTART);
}

public EventGameEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	PlaySound(GAMEEND);
}

static IsGrenade(String:weapon[])
{
	if (IsCSGO())
	{
		return StrEqual(weapon,"inferno") || StrEqual(weapon,"hegrenade") || 
		StrEqual(weapon,"flashbang") || StrEqual(weapon,"decoy") || StrEqual(weapon,"smokegrenade");
	}
	if (IsCSS())
	{
		return StrEqual(weapon, "hegrenade") || StrEqual(weapon, "smokegrenade") || StrEqual(weapon, "flashbang");
	}
	return false;
}

static IsKnife(String:weapon[])
{
	if (IsCSGO())
	{
		return StrEqual(weapon,"knife_default_ct") || StrEqual(weapon,"knife_default_t") ||
			StrEqual(weapon,"knifegg") || StrEqual(weapon,"knife_flip") || 
			StrEqual(weapon,"knife_gut") || StrEqual(weapon,"knife_karambit") || 
			StrEqual(weapon,"bayonet") || StrEqual(weapon,"knife_m9_bayonet");
	}
	if (IsCSS())
	{
		return StrEqual(weapon, "knife");
	}
	return false;
}

static AddMenuItemWithBuffer(Handle:hmenu, pref, const String:text[])
{
	if (hmenu == INVALID_HANDLE)
		return;

	new String:buffer[100];

	if (pref == OFF_SOUND)
	{
		Format(buffer, sizeof(buffer), "enable %s", text);
	}
	else
	{
		Format(buffer, sizeof(buffer), "disable %s", text);
	}

	AddMenuItem(hmenu, text, buffer);
}

public Action:Menu(client, args)
{
	new Handle:hmenu = CreateMenu(AMenuHandler);
	SetMenuTitle(hmenu, "rds menu");
	
	AddMenuItemWithBuffer(hmenu, g_ClientSoundEnable[client], "all sounds");

	AddMenuItemWithBuffer(hmenu, g_ClientSoundSetPreference[client][ROUNDFREEZEEND], "round freeze end");

	AddMenuItemWithBuffer(hmenu, g_ClientSoundSetPreference[client][ROUNDEND], "round end");

	//enough to check only one quake event
	AddMenuItemWithBuffer(hmenu, g_ClientSoundSetPreference[client][FIRSTBLOOD], "quake sounds");

	AddMenuItemWithBuffer(hmenu, g_ClientSoundSetPreference[client][JOINGAME], "join game sounds");

	DisplayMenu(hmenu, client, GetConVarInt(g_DisplayTime));

	return Plugin_Handled;
}


public AMenuHandler(Handle:menu, MenuAction:action, client, field)
{
	if (action == MenuAction_Select)
	{
		KvRewind(g_CPStorage);
		decl String:steamId[20];
		GetClientAuthString(client, steamId, sizeof(steamId));
		KvJumpToKey(g_CPStorage, steamId);

		switch(MenuField:field)
		{
			case SOUNDS_STATUS:
			{
				g_ClientSoundEnable[client] = !g_ClientSoundEnable[client];
				KvSetNum(g_CPStorage, SN_ALLSOUND, g_ClientSoundEnable[client]);
			}

			case ROUNDFREEZEEND_STATUS:
			{
				g_ClientSoundSetPreference[client][ROUNDFREEZEEND] = !g_ClientSoundSetPreference[client][ROUNDFREEZEEND];
				KvSetNum(g_CPStorage, SN_ROUNDFREEZEEND, g_ClientSoundSetPreference[client][ROUNDFREEZEEND]);
			}

			case ROUNDEND_STATUS:
			{
				g_ClientSoundSetPreference[client][ROUNDEND] = !g_ClientSoundSetPreference[client][ROUNDEND];
				KvSetNum(g_CPStorage, SN_ROUNDEND, g_ClientSoundSetPreference[client][ROUNDEND]);
			}

			case QUAKESOUND_STATUS:
			{
				for (new SoundType:key = FIRSTBLOOD; key <= MONSTERKILL; ++key)
				{
					g_ClientSoundSetPreference[client][key] = !g_ClientSoundSetPreference[client][key];
				}

				for (new SoundType:key = KILL1; key <= KILL11; ++key)
				{
					g_ClientSoundSetPreference[client][key] = !g_ClientSoundSetPreference[client][key];
				}

				KvSetNum(g_CPStorage, SN_QUAKE, g_ClientSoundSetPreference[client][FIRSTBLOOD]);
			}

			case JOINGAME_STATUS:
			{
				g_ClientSoundSetPreference[client][JOINGAME] = !g_ClientSoundSetPreference[client][JOINGAME];
				KvSetNum(g_CPStorage, SN_JOINGAME, g_ClientSoundSetPreference[client][JOINGAME]);
			}
		}
	}
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

static HookEvents()
{
	if (!g_IsHooked)
	{
		HookEvent("player_death", EventPlayerDeath);
		HookEvent("round_freeze_end", EventFreezeEnd, EventHookMode_PostNoCopy);
		HookEvent("round_end", EventRoundEnd, EventHookMode_PostNoCopy);
		HookEvent("round_start", EventRoundStart, EventHookMode_PostNoCopy);
		HookEvent("game_end", EventGameEnd, EventHookMode_PostNoCopy);
		HookEvent("round_start", EventRoundStart, EventHookMode_PostNoCopy);
		g_IsHooked = true;
	}
}

static UnhookEvents()
{
	if (g_IsHooked)
	{
		UnhookEvent("player_death", EventPlayerDeath);
		UnhookEvent("round_freeze_end", EventFreezeEnd, EventHookMode_PostNoCopy);
		UnhookEvent("round_end", EventRoundEnd, EventHookMode_PostNoCopy);
		UnhookEvent("round_start", EventRoundStart, EventHookMode_PostNoCopy);
		UnhookEvent("game_end", EventGameEnd, EventHookMode_PostNoCopy);
		UnhookEvent("round_start", EventRoundStart, EventHookMode_PostNoCopy);
		g_IsHooked = false;
	}
}

public EnableChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if(GetConVarBool(convar)) 
	{
		HookEvents();
	}
	else
	{
		UnhookEvents();
	}
}