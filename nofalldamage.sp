#pragma semicolon 1
#include <sdktools>
#include <sdkhooks>
#define PLUGIN_VERSION "0.1"
public Plugin:myinfo = {
	name = "No Fall Damage",
	author = "Mr Halt (a.k.a. 할짓없는놈, FineDrum)",
	description = "no falling damage",
	version = PLUGIN_VERSION,
	url = "www.sourcemod.net"
}
#define DMG_FALL   (1 << 5)
public OnClientPutInServer(client){
SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}
public Action:OnTakeDamage(client, &attacker, &inflictor, &Float:damage, &damagetype){
if (damagetype & DMG_FALL){
return Plugin_Handled;
}
return Plugin_Continue;
}
