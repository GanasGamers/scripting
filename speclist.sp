
#pragma semicolon 1

#include <sourcemod>

#define SPECMODE_NONE 				0
#define SPECMODE_FIRSTPERSON 		4
#define SPECMODE_3RDPERSON 			5
#define SPECMODE_FREELOOK	 		6

#define UPDATE_INTERVAL 2.5
#define PLUGIN_VERSION "1.1.2c"

new Handle:HudHintTimers[MAXPLAYERS+1];
new Handle:sm_speclist_enabled;
new Handle:sm_speclist_allowed;
new Handle:sm_speclist_adminonly;
new Handle:sm_speclist_noadmins;
new bool:g_Enabled;
new bool:g_AdminOnly;
new bool:g_NoAdmins;
new bool:PlayerIsAdmin[MAXPLAYERS+1] = {false, ...};

new bool:useProtobuf = false;

public Plugin:myinfo =
{
	name = "Spectator List",
	author = "GoD-Tony",
	description = "View who is spectating you in CS:S",
	version = PLUGIN_VERSION,
	url = "http://www.sourcemod.net/"
};
 
public OnPluginStart()
{
	CreateConVar("sm_speclist_version", PLUGIN_VERSION, "Spectator List Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	sm_speclist_enabled = CreateConVar("sm_speclist_enabled","1","Enables the spectator list for all players by default.");
	sm_speclist_allowed = CreateConVar("sm_speclist_allowed","1","Allows players to enable spectator list manually when disabled by default.");
	sm_speclist_adminonly = CreateConVar("sm_speclist_adminonly","0","Only admins can use the features of this plugin.");
	sm_speclist_noadmins = CreateConVar("sm_speclist_noadmins", "0","Don't show non-admins that admins are spectating them.");
	
	RegConsoleCmd("sm_speclist", Command_SpecList);
	
	HookConVarChange(sm_speclist_enabled, OnConVarChange);
	HookConVarChange(sm_speclist_adminonly, OnConVarChange);
	HookConVarChange(sm_speclist_noadmins, OnConVarChange);
	
	g_Enabled = GetConVarBool(sm_speclist_enabled);
	g_AdminOnly = GetConVarBool(sm_speclist_adminonly);
	g_NoAdmins = GetConVarBool(sm_speclist_noadmins);
	
	AutoExecConfig(true, "plugin.speclist");
	
	if (GetUserMessageType() == UM_Protobuf)
	{
		useProtobuf = true;
	}
}

public OnConVarChange(Handle:hCvar, const String:oldValue[], const String:newValue[])
{
	if (hCvar == sm_speclist_enabled)
	{
		g_Enabled = GetConVarBool(sm_speclist_enabled);
		
		if (g_Enabled)
		{
			// Enable timers on all players in game.
			for (new i = 1; i <= MaxClients; i++) 
			{
				if (!IsClientInGame(i))
				{
					continue;
				}
				
				CreateHudHintTimer(i);
			}
		}
		else
		{
			// Kill all of the active timers.
			for (new i = 1; i <= MaxClients; i++)
			{
				KillHudHintTimer(i);
			}
		}
	}
	else if (hCvar == sm_speclist_adminonly)
	{
		g_AdminOnly = GetConVarBool(sm_speclist_adminonly);
		
		if (g_AdminOnly)
		{
			// Kill all of the active timers.
			for (new i = 1; i <= MaxClients; i++)
			{
				KillHudHintTimer(i);
			}
				
			// Enable timers on all admins in game.
			for (new i = 1; i <= MaxClients; i++) 
			{
				if (!IsClientInGame(i))
				{
					continue;
				}
				
				CreateHudHintTimer(i);
			}
		}
	}
	else if (hCvar == sm_speclist_noadmins)
	{
		g_NoAdmins = GetConVarBool(sm_speclist_noadmins);
		
		if (g_NoAdmins)
		{
			// Kill all of the active timers.
			for (new i = 1; i <= MaxClients; i++)
			{
				KillHudHintTimer(i);
			}
				
			// Enable timers on all players in game.
			for (new i = 1; i <= MaxClients; i++) 
			{
				if (!IsClientInGame(i))
				{
					continue;
				}
				
				CreateHudHintTimer(i);
			}
		}
	}
}

public OnClientPostAdminCheck(client)
{
	if (g_Enabled)
	{
		CreateHudHintTimer(client);
	}
	
	if (CheckCommandAccess(client, "show_spectate", ADMFLAG_GENERIC))
	{
		PlayerIsAdmin[client] = true;
	}
	else
	{
		PlayerIsAdmin[client] = false;
	}
}

public OnClientDisconnect(client)
{
	if (IsClientInGame(client))
	{
		PlayerIsAdmin[client] = false;
		KillHudHintTimer(client);
	}
}

// Using 'sm_speclist' to toggle the spectator list per player.
public Action:Command_SpecList(client, args)
{
	if (HudHintTimers[client] != INVALID_HANDLE)
	{
		KillHudHintTimer(client);
		ReplyToCommand(client, "[SM] Spectator list disabled.");
	}
	else if (g_Enabled || GetConVarBool(sm_speclist_allowed))
	{
		CreateHudHintTimer(client);
		ReplyToCommand(client, "[SM] Spectator list enabled.");
	}
	
	return Plugin_Handled;
}


public Action:Timer_UpdateHudHint(Handle:timer, any:client)
{
	new iSpecModeUser = GetEntProp(client, Prop_Send, "m_iObserverMode");
	new iSpecMode, iTarget, iTargetUser;
	new bool:bDisplayHint = false;
	
	decl String:szText[254];
	szText[0] = '\0';
	
	// Dealing with a client who is in the game and playing.
	if (IsPlayerAlive(client))
	{
		for (new i = 1; i <= MaxClients; i++) 
		{
			if (!IsClientInGame(i) || !IsClientObserver(i))
			{
				continue;
			}
			
			// The 'client' is not an admin and do not display admins is enabled and the client (i) is an admin, so ignore them.
			if (!PlayerIsAdmin[client] && (g_NoAdmins && PlayerIsAdmin[i]))
			{
				continue;
			}
			
			iSpecMode = GetEntProp(i, Prop_Send, "m_iObserverMode");
			
			// The client isn't spectating any one person, so ignore them.
			if (iSpecMode != SPECMODE_FIRSTPERSON && iSpecMode != SPECMODE_3RDPERSON)
			{
				continue;
			}
			
			// Find out who the client is spectating.
			iTarget = GetEntPropEnt(i, Prop_Send, "m_hObserverTarget");
			
			// Are they spectating our player?
			if (iTarget == client)
			{
				Format(szText, sizeof(szText), "%s%N\n", szText, i);
				bDisplayHint = true;
			}
		}
	}
	else if (iSpecModeUser == SPECMODE_FIRSTPERSON || iSpecModeUser == SPECMODE_3RDPERSON)
	{
		// Find out who the User is spectating.
		iTargetUser = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
		
		// Make sure client is spectating another player
		if (iTargetUser > 0 && iTargetUser <= MaxClients)
		{
			Format(szText, sizeof(szText), "Spectating %N:\n", iTargetUser);
		}
		
		for (new i = 1; i <= MaxClients; i++) 
		{			
			if (!IsClientInGame(i) || !IsClientObserver(i))
			{
				continue;
			}
			
			// The 'client' is not an admin and do not display admins is enabled and the client (i) is an admin, so ignore them.
			if (!PlayerIsAdmin[client] && (g_NoAdmins && PlayerIsAdmin[i]))
			{
				continue;
			}
			
			iSpecMode = GetEntProp(i, Prop_Send, "m_iObserverMode");
			
			// The client isn't spectating any one person, so ignore them.
			if (iSpecMode != SPECMODE_FIRSTPERSON && iSpecMode != SPECMODE_3RDPERSON)
			{
				continue;
			}
			
			// Find out who the client is spectating.
			iTarget = GetEntPropEnt(i, Prop_Send, "m_hObserverTarget");
			
			// Are they spectating the same player as User?
			if (iTarget == iTargetUser)
			{
				Format(szText, sizeof(szText), "%s%N\n", szText, i);
			}
		}
	}
	
	/* We do this to prevent displaying a message
		to a player if no one is spectating them anyway. */
	if (bDisplayHint)
	{
		Format(szText, sizeof(szText), "Spectating %N:\n%s", client, szText);
		bDisplayHint = false;
	}
	
	// Send our message
	new Handle:hBuffer = StartMessageOne("KeyHintText", client); 

	if (useProtobuf)
	{
		PbAddString(hBuffer, "hints", szText);
	}
	else
	{
		BfWriteByte(hBuffer, 1); 
		BfWriteString(hBuffer, szText); 
	}
	EndMessage();
	
	return Plugin_Continue;
}

CreateHudHintTimer(client)
{
	if (!g_AdminOnly || (g_AdminOnly && PlayerIsAdmin[client]))
	{
		HudHintTimers[client] = CreateTimer(UPDATE_INTERVAL, Timer_UpdateHudHint, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

KillHudHintTimer(client)
{
	if (HudHintTimers[client] != INVALID_HANDLE)
	{
		KillTimer(HudHintTimers[client]);
		HudHintTimers[client] = INVALID_HANDLE;
	}
}