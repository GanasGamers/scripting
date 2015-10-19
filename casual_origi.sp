/**
 * vim: set ts=4 :
 * =============================================================================
 * Casualmode Vote Plugin
 * Based on SourceMod Fun Votes Plugin
 * Implements extra fun vote commands.
 *
 * SourceMod (C)2004-2008 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id$
 */
//casualmode vote is based on funvotes, but is not integrated, to make updating easier

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#define PLUGIN_VERSION "1.0"

#define VOTE_NO "###no###"
#define VOTE_YES "###yes###"
new Handle:cvarBlockvote = INVALID_HANDLE;
new Blockvote = 0;
new Roundstartblock = 0;

public Plugin:myinfo =
{
	name = "Fun Votes Casualmodevote",
	author = "AlliedModders LLC, Timiditas",
	description = "change mode to a casual mode after vote succeed",
	version = PLUGIN_VERSION,
	url = "http://www.sourcemod.net/"
};

new Handle:g_hVoteMenu = INVALID_HANDLE;

new Handle:g_Cvar_Limit = INVALID_HANDLE;

// Menu API does not provide us with a way to pass multiple peices of data with a single
// choice, so some globals are used to hold stuff.
//
#define VOTE_CLIENTID	0
#define VOTE_USERID	1

#define VOTE_NAME	0
#define VOTE_AUTHID	1
#define	VOTE_IP		2
new String:g_voteInfo[3][65];	/* Holds the target's name, authid, and IP */

stock VoteMenuToNonSpecs(Handle:menu, time, flags=0)
{
	new num = MaxClients;
	//documentation says not to cache the value of MaxClients because its dynamic. I do it nonetheless in this case because of the "players" array
	//risking out-of-bounds access/runtime error
	
	new total;
	decl players[num];
	
	for (new i=1; i<=num; i++)
	{
		if(!IsClientInGame(i))
			continue;
		new cTeam = GetClientTeam(i);
		if ((cTeam < 2) || (cTeam > 3))
			continue;
		players[total++] = i;
	}
	return VoteMenu(menu, players, total, time, flags);
}

public OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("basevotes.phrases");
	LoadTranslations("casualmodevote.phrases");

	CreateConVar("casualmodevote_version", PLUGIN_VERSION, "Casualmode vote version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	RegAdminCmd("sm_votecasualmode", Command_VoteCasualmode, ADMFLAG_VOTE, "sm_votecasualmode");
	g_Cvar_Limit = CreateConVar("sm_vote_casualmode", "0.60", "percent required for successful casualmode vote.", 0, true, 0.05, true, 1.0);
	HookEvent("round_start", EventRoundStart);
	RegConsoleCmd("casual", Chathandler);
}
public EventRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	Roundstartblock = 1;
}

public Handler_VoteCallback(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_End)
	{
		VoteMenuClose();
	}
	else if (action == MenuAction_Display)
	{
	 	decl String:title[64];
		GetMenuTitle(menu, title, sizeof(title));
	 	decl String:buffer[255];
		Format(buffer, sizeof(buffer), "%T", title, param1, g_voteInfo[VOTE_NAME]);

		new Handle:panel = Handle:param2;
		SetPanelTitle(panel, buffer);
	}
	else if (action == MenuAction_DisplayItem)
	{
		decl String:display[64];
		GetMenuItem(menu, param2, "", 0, _, display, sizeof(display));
	 
	 	if (strcmp(display, VOTE_NO) == 0 || strcmp(display, VOTE_YES) == 0)
	 	{
			decl String:buffer[255];
			Format(buffer, sizeof(buffer), "%T", display, param1);

			return RedrawMenuItem(buffer);
		}
	}
	else if (action == MenuAction_VoteCancel && param1 == VoteCancel_NoVotes)
	{
		PrintToChatAll("[SM] %t", "No Votes Cast");
	}
	else if (action == MenuAction_VoteEnd)
	{
		decl String:item[64];
		new Float:percent, Float:limit, votes, totalVotes;

		GetMenuVoteInfo(param2, votes, totalVotes);
		GetMenuItem(menu, param1, item, sizeof(item));
		
		if (strcmp(item, VOTE_NO) == 0 && param1 == 1)
		{
			votes = totalVotes - votes; // Reverse the votes to be in relation to the Yes option.
		}
		
		percent = GetVotePercent(votes, totalVotes);
		
		limit = GetConVarFloat(g_Cvar_Limit);
		
		//New round has started. Running vote is obsolete.
		if (Roundstartblock == 1)
			return 0;
		
		// A multi-argument vote is "always successful", but have to check if its a Yes/No vote.
		if ((strcmp(item, VOTE_YES) == 0 && FloatCompare(percent,limit) < 0 && param1 == 0) || (strcmp(item, VOTE_NO) == 0 && param1 == 1))
		{
			PrintToChatAll("[SM] %t", "Vote Failed", RoundToNearest(100.0*limit), RoundToNearest(100.0*percent), totalVotes);
		}
		else
		{
			PrintToChatAll("[SM] %t", "Vote Successful", RoundToNearest(100.0*percent), totalVotes);
			ServerCommand("sv_difficulty casual");
			PrintToChatAll("[SM] %t", "Change mode to Casual mode after map load.");
		}
	}
	
	return 0;
}

VoteMenuClose()
{
	CloseHandle(g_hVoteMenu);
	g_hVoteMenu = INVALID_HANDLE;
}

Float:GetVotePercent(votes, totalVotes)
{
	return FloatDiv(float(votes),float(totalVotes));
}

bool:TestVoteDelay(client)
{
 	new delay = CheckVoteDelay();
 	
 	if (delay > 0)
 	{
 		if (delay > 60)
 		{
 			ReplyToCommand(client, "[SM] %t", "Vote Delay Minutes", delay % 60);
 		}
 		else
 		{
 			ReplyToCommand(client, "[SM] %t", "Vote Delay Seconds", delay);
 		}
 		
 		return false;
 	}
 	
	return true;
}

DisplayVoteCasualModeMenu(client)
{
	if (IsVoteInProgress())
	{
		ReplyToCommand(client, "[SM] %t", "Vote in Progress");
		return;
	}	
	
	if (!TestVoteDelay(client))
	{
		if(client > 0)
			return;
	}
	Roundstartblock = 0;
	
	g_voteInfo[VOTE_NAME][0] = '\0';

	g_hVoteMenu = CreateMenu(Handler_VoteCallback, MenuAction:MENU_ACTIONS_ALL);
	
	SetMenuTitle(g_hVoteMenu, "Change Casual mode?");
		
	AddMenuItem(g_hVoteMenu, VOTE_YES, "Yes");
	AddMenuItem(g_hVoteMenu, VOTE_NO, "No");
	SetMenuExitButton(g_hVoteMenu, false);
	VoteMenuToNonSpecs(g_hVoteMenu, 6);
}

public Action:Command_VoteCasualmode(client, args)
{
	if (args > 0)
	{
		ReplyToCommand(client, "[SM] Usage: sm_casual");
		return Plugin_Handled;	
	}
	
	DisplayVoteCasualModeMenu(client);
	
	return Plugin_Handled;
}

public SettingChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	Blockvote = GetConVarInt(cvarBlockvote);
}

public Action:Chathandler(client, args)
{
	if(Blockvote == 1)
	{
		PrintToChat(client, "%t", "Vote is blocked for the moment");
		return;
	}
	
	DisplayVoteCasualModeMenu(client);
}