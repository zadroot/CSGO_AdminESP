/**
* CS:GO Admin ESP by Root
*
* Description:
*   Plugin show positions of all players through walls to admin when he/she is observing, dead or spectate.
*
* Version 2.0
* Changelog & more info at http://goo.gl/4nKhJ
*/

// ====[ INCLUDES ]=======================================================================
#undef REQUIRE_EXTENSIONS
#include <cstrike> // constants
#include <sdkhooks> // transmit hook
#undef REQUIRE_PLUGIN
#tryinclude <CustomPlayerSkins> // required plugin

// ====[ CONSTANTS ]======================================================================
#define PLUGIN_NAME    "CS:GO Admin ESP"
#define PLUGIN_VERSION "2.0"

// ====[ VARIABLES ]======================================================================
new	Handle:AdminESP,
#if defined _CustomPlayerSkins_included
	Handle:AdminESP_Mode,
	Handle:AdminESP_Dead,
	Handle:AdminESP_TColor,
	Handle:AdminESP_CTColor,
#endif
	Handle:mp_teammates_are_enemies,
	bool:IsUsingESP[MAXPLAYERS + 1];

// ====[ PLUGIN ]=========================================================================
public Plugin:myinfo =
{
	name        = PLUGIN_NAME,
	author      = "Root",
	description = "ESP/WH for Admins",
	version     = PLUGIN_VERSION,
	url         = "forums.alliedmods.net/showthread.php?p=211117"
}


/* OnPluginStart()
 *
 * When the plugin starts up.
 * --------------------------------------------------------------------------------------- */
public OnPluginStart()
{
	// Magical cvar to enable glows on everyone
	mp_teammates_are_enemies = FindConVar("mp_teammates_are_enemies");

	// Log error and disable plugin if mod is not supported
	if (mp_teammates_are_enemies == INVALID_HANDLE)
		SetFailState("Fatal Error: Could not find \"mp_teammates_are_enemies\" console variable! Disabling plugin...");

	// Create plugin console variables on success
	CreateConVar("sm_csgo_adminesp_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NOTIFY|FCVAR_DONTRECORD);
	AdminESP         = CreateConVar("sm_csgo_adminesp",         "1",              "Whether or not automatically enable ESP/WH when Admin with cheat flag (Default: \"n\") observe", FCVAR_PLUGIN, true, 0.0, true, 1.0);
#if defined _CustomPlayerSkins_included
	AdminESP_Mode    = CreateConVar("sm_csgo_adminesp_mode",    "0",              "Determines mode for Admin ESP:\n0 = Red glow\n1 = Colored glow (cpu intensive)",                 FCVAR_PLUGIN, true, 0.0, true, 1.0);
	AdminESP_Dead    = CreateConVar("sm_csgo_adminesp_dead",    "1",              "If colored glow mode is set, detemines whether or not enable glow only when Admin is observing", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	AdminESP_TColor  = CreateConVar("sm_csgo_adminesp_tcolor",  "192 160 96 128", "Determines R G B A glow colors for Terrorists team\nSet to \"0 0 0 0\" to disable",              FCVAR_PLUGIN);
	AdminESP_CTColor = CreateConVar("sm_csgo_adminesp_ctcolor", "96 128 192 128", "Determines R G B A glow colors for Counter-Terrorists team\nSet to \"0 0 0 0\" to disable",      FCVAR_PLUGIN);
#endif
	// Hook ConVar change
	HookConVarChange(AdminESP, OnConVarChange);

	// Manually trigger OnConVarChange to hook plugin's events
	OnConVarChange(AdminESP, "0", "1");

	// Generate plugin config in cfg/sourcemod folder
	AutoExecConfig(true, "csgo_admin_esp");
}

/* OnConVarChange()
 *
 * Called when a convar's value is changed.
 * --------------------------------------------------------------------------------------- */
public OnConVarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	// Since old/newValue's is strings, convert them to integers
	switch (StringToInt(newValue))
	{
		// Unhook all needed events on plugin disabling
		case false:
		{
			UnhookEvent("player_spawn", OnPlayerEvents, EventHookMode_Post);
			UnhookEvent("player_death", OnPlayerEvents, EventHookMode_Post);
			UnhookEvent("player_team",  OnPlayerEvents, EventHookMode_Post);
		}
		case true:
		{
			HookEvent("player_spawn", OnPlayerEvents, EventHookMode_Post);
			HookEvent("player_death", OnPlayerEvents, EventHookMode_Post);
			HookEvent("player_team",  OnPlayerEvents, EventHookMode_Post);
		}
	}
}

/* OnPlayerEvents()
 *
 * Called when player spawns, dies or changes team.
 * --------------------------------------------------------------------------------------- */
public OnPlayerEvents(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Retrieve client ids from event
	new clientID = GetEventInt(event, "userid");
	new client   = GetClientOfUserId(clientID);

	if (IsValidClient(client))
	{
		// When the player spawns
		if (name[7] == 's')
		{
#if defined _CustomPlayerSkins_included
			if (GetConVarBool(AdminESP_Mode))
			{
				// Attach custom player model and enable glow after 0.1 delay on spawning
				CreateTimer(0.1, Timer_SetupGlow, clientID, TIMER_FLAG_NO_MAPCHANGE);

				// When admin spawns, check whether or not disable 'dead ESP'
				if (!GetConVarBool(AdminESP_Dead))
				{
					return;
				}
			}
#endif
			if (IsUsingESP[client])
			{
				// Disable previous WH state
				DisableESP(client);
			}
		}

		// Enable ESP when player dies or changes own team
		else
		{
			EnableESP(client);
		}
	}
}
#if defined _CustomPlayerSkins_included
/* Timer_SetupGlow()
 *
 * Sets player skin and enables glow.
 * --------------------------------------------------------------------------------------- */
public Action:Timer_SetupGlow(Handle:timer, any:client)
{
	// Validate client on delayed callback
	if ((client = GetClientOfUserId(client)))
	{
		decl String:model[PLATFORM_MAX_PATH];

		// Retrieve current player model
		GetClientModel(client, model, sizeof(model));

		// Assign custom player skin same as current player model
		CPS_SetSkin(client, model);

		// Retrieve skin entity from core plugin
		new skin = CPS_GetSkin(client);

		// Declare convar strings to properly colorize players
		decl String:TColors[32],  String:expT[4][sizeof(TColors)],
			 String:CTColors[32], String:expCT[4][sizeof(CTColors)];

		// Get values from plugin convars
		GetConVarString(AdminESP_TColor,  TColors,  sizeof(TColors));
		GetConVarString(AdminESP_CTColor, CTColors, sizeof(CTColors));

		// Get rid of spaces to get all RGBA values
		ExplodeString(TColors,  " ", expT,  sizeof(expT),  sizeof(expT[]));
		ExplodeString(CTColors, " ", expCT, sizeof(expCT), sizeof(expCT[]));

		switch (GetClientTeam(client))
		{
			// Set T colors for Terrorists team and CT for Counter-Terrorists
			case CS_TEAM_T:  SetupGlow(skin, StringToInt(expT[0]),  StringToInt(expT[1]),  StringToInt(expT[2]),  StringToInt(expT[3]));
			case CS_TEAM_CT: SetupGlow(skin, StringToInt(expCT[0]), StringToInt(expCT[1]), StringToInt(expCT[2]), StringToInt(expCT[3]));
		}

		// Hook SetTransmit for custom player model entity
		SDKHookEx(skin, SDKHook_SetTransmit, OnSetTransmit);
	}
}

/* OnSetTransmit()
 *
 * Transmit hook for custom player skins.
 * --------------------------------------------------------------------------------------- */
public Action:OnSetTransmit(entity, client)
{
	// If player is not having access to ESP, dont show custom player skins, which is glows
	return !IsUsingESP[client] ? Plugin_Handled : Plugin_Continue;
}

/* SetupGlow()
 *
 * Sets glow for player assigned skins depends on their team and a color settings.
 * --------------------------------------------------------------------------------------- */
SetupGlow(entity, r, g, b, a)
{
	static offset;

	// Get sendprop offset for given entity
	if (!offset && (offset = GetEntSendPropOffs(entity, "m_clrGlow")) == -1)
	{
		LogError("Unable to find offset: \"m_clrGlow\"!");
		return;
	}

	// Enable normal glow for custom player skin
	SetEntProp(entity, Prop_Send, "m_bShouldGlow", true, true);

	// And then setup glow color by offset
	SetEntData(entity, offset, r, _, true);    // Red color
	SetEntData(entity, offset + 1, g, _, true) // Green
	SetEntData(entity, offset + 2, b, _, true) // Blue
	SetEntData(entity, offset + 3, a, _, true) // It's alpha
}
#endif
/* EnableESP()
 *
 * Enables ESP for specified client.
 * --------------------------------------------------------------------------------------- */
EnableESP(client)
{
	// Magic stuff
	if ((IsUsingESP[client] = CheckCommandAccess(client, "csgo_admin_esp", ADMFLAG_CHEATS)))
	{
#if defined _CustomPlayerSkins_included
		if (!GetConVarBool(AdminESP_Mode))
#endif
			SendConVarValue(client, mp_teammates_are_enemies, "1");
	}
}

/* DisableESP()
 *
 * Disables ESP for specified client.
 * --------------------------------------------------------------------------------------- */
DisableESP(client)
{
	// Client is no longer used ESP
	IsUsingESP[client] = false;
#if defined _CustomPlayerSkins_included
	if (!GetConVarBool(AdminESP_Mode))
#endif
		SendConVarValue(client, mp_teammates_are_enemies, "0");
}

/* IsValidClient()
 *
 * Checks if a client is valid.
 * --------------------------------------------------------------------------------------- */
bool:IsValidClient(client)
{
	return (1 <= client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client)) ? true : false;
}