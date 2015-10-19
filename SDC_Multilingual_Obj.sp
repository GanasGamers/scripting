#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include "smlib/entities.inc"
#include "smlib/games/nmrih.inc"
//#include <system2>

//						White			Red			Orange			Yellow			Green
new g_Colors[5][3] = {	{255,255,255},	{255,0,0},	{255,128,0},	{255,255,0},	{0,255,0}};

public Plugin:myinfo = {
	name = "Multilingual Objective Beta",
	author = "Tast - SDC",
	description = "NMRiH Objective Multilingual",
	version = "1.40",
	url = "http://tast.xclub.tw/viewthread.php?tid=115"
};

new extraction_begin_available = 0
new ObjCounter = 0

new String:MapName[64]
new String:path[PLATFORM_MAX_PATH];
new String:ObjCfgPathN[512]

new Handle:AR_OriginObj = INVALID_HANDLE;
new Handle:AR_Obj = INVALID_HANDLE;
new Handle:AR_ObjPast = INVALID_HANDLE;

new obj_showserver = 1
new String:obj_language[8] = "jp"

new Handle:Cvar_ObjCode = INVALID_HANDLE;
new Handle:Cvar_ObjMess = INVALID_HANDLE;

public OnPluginStart(){
	LoadTranslations("SDC.Objective.phrases");
	AR_OriginObj 		= CreateArray(512);
	AR_Obj 				= CreateArray(512);
	AR_ObjPast 			= CreateArray(512);
	BuildPath(PathType:Path_SM, path, sizeof(path), "logs/obj.log");
	//-----------------------------------------------------------------------
	new String:Path_SM_Config[512]
	BuildPath(PathType:Path_SM, Path_SM_Config, sizeof(Path_SM_Config), "/configs/ObjectiveT");
	if(!DirExists(Path_SM_Config)) CreateDirectory(Path_SM_Config, 511);
	//BuildPath(PathType:Path_SM, Path_SM_Config, sizeof(Path_SM_Config), "/configs/ObjectiveT/Original");
	//if(!DirExists(Path_SM_Config)) CreateDirectory(Path_SM_Config, 511);
	//-----------------------------------------------------------------------
	Cvar_ObjCode = CreateConVar("obj_Code", 		"",	"Current Objective Code")
	Cvar_ObjMess = CreateConVar("obj_Mess", 		"",	"Current Objective Message")
	HookConVarChange(	CreateConVar("obj_showserver", 		"1",	"Show Objective on console")		, Cvar_ShowServer);
	HookConVarChange(	CreateConVar("obj_language", 		"jp",	"Server Objective Language")		, Cvar_Language);
	//-----------------------------------------------------------------------
	HookEvent("extraction_begin", Event_Extraction_Begin,EventHookMode_Pre);
	HookEvent("state_change", state_change,EventHookMode_Pre);
	//-----------------------------------------------------------------------
	//RegAdminCmd("objtest", Command_Test, ADMFLAG_ROOT);
	//RegAdminCmd("objtestAll", Command_Test2, ADMFLAG_ROOT);
	RegAdminCmd("nmrih_obj", Command_objective, ADMFLAG_ROOT);
	RegConsoleCmd("objs", Command_objectiveS, "Show the past objective list");
}

public Cvar_ShowServer(Handle:convar, const String:oldValue[], const String:newValue[]) 	{ obj_showserver = StringToInt(newValue); }
public Cvar_Language(Handle:convar, const String:oldValue[], const String:newValue[]) 	{
	strcopy(obj_language,sizeof(obj_language),newValue)
	//PrintToServer(newValue)
}

public Action:Command_objectiveS(id, Args) {
	if(GetArraySize(AR_ObjPast) <= 1) return;
	for(new i = 0; i < GetArraySize(AR_ObjPast);i++){
		new String:AR_buffer[512]
		GetArrayString(AR_ObjPast, i, AR_buffer, sizeof(AR_buffer));
		PrintToChat(id,"%d:%s",i,AR_buffer)
	}
}

public Action:Command_Test2(id, Args) {
	new entity = -1
	while((entity = Entity_FindByClassName(entity, "func_nmrih_extractionzone")) != INVALID_ENT_REFERENCE){
		//AcceptEntityInput(entity, "ObjectiveCompleteTriggerExtraction", -1, 8, 1);
		//AcceptEntityInput(entity, "ObjectiveComplete");
	}
}

public Action:Command_Test(id, Args) {
	ObjList(1);
	ObjConfig()
	//IsSystem2Functional()
}

public ObjList(type){
	new String:filePath[512]
	GetCurrentMap(MapName, sizeof(MapName));
	Format(filePath,sizeof(filePath),"maps/%s.nmo",MapName)
	BuildPath(Path_SM, ObjCfgPathN, sizeof(ObjCfgPathN), "/configs/ObjectiveT/%s.ini",MapName);
	
	FileUTF_BOM(ObjCfgPathN)
	
	if(!FileExists(filePath)) return;
	new Handle:file = OpenFile(filePath, "rb");
	
	//====================================================================================================
	//轉出所有字元 output all character one by one
	
	new String:buffer2[4096]
	while(!IsEndOfFile(file)){
		new buffer
		ReadFileCell(file, buffer, 1)
		Format(buffer2,sizeof(buffer2),"%c",buffer)
		PushArrayString(AR_OriginObj, buffer2);
	}
	CloseHandle(file);
	//====================================================================================================
	//開始分行分段 change the wrong char and convert to sentence
	
	new String:AR_bufferT[512]
	for(new i = 0; i < GetArraySize(AR_OriginObj); i++){
		new String:AR_buffer[512]
		GetArrayString(AR_OriginObj, i, AR_buffer, sizeof(AR_buffer));
		
		if(StrEqual(AR_buffer, "\"", false)){
			SetArrayString(AR_OriginObj, i, "'");
			Format(AR_buffer,sizeof(AR_buffer),"'")
			//LogToFileEx(path,"Error for char : \"")
		}
		
		if(StrEqual(AR_buffer, "\000", false)){ //this is null char
			SetArrayString(AR_OriginObj, i, "|n");
			Format(AR_buffer,sizeof(AR_buffer),"|n")
		}
		
		if(StrEqual(AR_buffer, "|n", false)){
				PushArrayString(AR_Obj, AR_bufferT);
				Format(AR_bufferT,sizeof(AR_bufferT),"")
		}
		else 	Format(AR_bufferT,sizeof(AR_bufferT),"%s%s",AR_bufferT,AR_buffer)
	}
	
	//====================================================================================================
	//透過地圖物件拿到標題碼並從陣列資料中提取原文 
	//Get the codeName from entity's targetname
	
	ClearArray(AR_OriginObj);
	new Handle:AR_ObjTemp = CreateArray(128);
	new maxEntities = GetMaxEntities();
	for (new entity = 0; entity < maxEntities; entity++) {
		if(!IsValidEntity(entity)) continue
		new String:ClassName[512]
		GetEntityClassname(entity, ClassName, sizeof(ClassName));
		if(StrContains(ClassName,"nmrih_objective_boundary",false) == -1) continue
		
		Entity_GetName(entity, ClassName, sizeof(ClassName))
		
		new String:AR_buffer[512]
		for(new i = 0; i < GetArraySize(AR_Obj);i++){
			new String:AR_bufferTemp1[512],String:AR_bufferTemp2[512]
			GetArrayString(AR_Obj, i, AR_bufferTemp1, sizeof(AR_bufferTemp1));
			if(StrEqual(AR_bufferTemp1,ClassName,false)){
				GetArrayString(AR_Obj, i - 1, AR_bufferTemp2, sizeof(AR_bufferTemp2));
				if(StrEqual(AR_bufferTemp2,"",false)) continue
				else strcopy(AR_buffer,sizeof(AR_buffer),AR_bufferTemp2)
			}
		}
		
		PushArrayString(AR_OriginObj, ClassName);
		PushArrayString(AR_ObjTemp, AR_buffer);
		//LogToFileEx(path,"[%d]%s : %s",locate,ClassName,AR_buffer)
	}
	
	ClearArray(AR_Obj);
	for(new i = 0; i < GetArraySize(AR_ObjTemp); i++){
		new String:AR_buffer[512]
		GetArrayString(AR_ObjTemp, i, AR_buffer, sizeof(AR_buffer));
		PushArrayString(AR_Obj, AR_buffer);
	}
	CloseHandle(AR_ObjTemp);
	
	//====================================================================================================
	//Game_text文字訊息支援 Supported to Game_text Entity
	//HammerID is Compatibility for same targetname of 2 more entity
	new ent = -1;
	while ((ent = FindEntityByClassname(ent, "game_text")) != -1){
		new String:GetName[512],String:m_iszMessage[512]
		Entity_GetName(ent, GetName, sizeof(GetName))
		GetEntPropString(ent, Prop_Data, "m_iszMessage", m_iszMessage, sizeof(m_iszMessage));
		ReplaceString(m_iszMessage, sizeof(m_iszMessage), "\n", "\\n", false);
		ReplaceString(m_iszMessage, sizeof(m_iszMessage), "\r", "\\r", false);
		ReplaceString(m_iszMessage, sizeof(m_iszMessage), "\"", "'", false);
		Format(GetName,sizeof(GetName),"<GameText>%d|%s",Entity_GetHammerId(ent),GetName)
		PushArrayString(AR_OriginObj, GetName);
		PushArrayString(AR_Obj, m_iszMessage);
	}
	
	//====================================================================================================
	//測試用資料陣列表述
	//if(!type) return
	/*
	for(new i = 0; i < GetArraySize(AR_Obj); i++){
		new String:AR_buffer[512]
		GetArrayString(AR_Obj, i, AR_buffer, sizeof(AR_buffer));
		//if(strlen(AR_buffer) > 2){
		//if(!StrEqual(AR_buffer, "", false)){
			//PrintToServer(AR_buffer)
		//LogToFileEx(path,AR_buffer)
	}
		
	for(new i = 0; i < GetArraySize(AR_OriginObj); i++){
		new String:AR_buffer[512]
		GetArrayString(AR_OriginObj, i, AR_buffer, sizeof(AR_buffer));
		//if(strlen(AR_buffer) > 1){
		//if(!StrEqual(AR_buffer, "", false)){
			//PrintToServer(AR_buffer)
		//LogToFileEx(path,AR_buffer)
		//}
	}
	*/
}

public ObjConfig(){
	new Handle:kv = CreateKeyValues("Objective");
	GetCurrentMap(MapName, sizeof(MapName));
	BuildPath(Path_SM, ObjCfgPathN, sizeof(ObjCfgPathN), "/configs/ObjectiveT/%s.ini",MapName);
	FileToKeyValues(kv, ObjCfgPathN)
	KvJumpToKey(kv, "Original",true)
		
	for(new i = 0; i < GetArraySize(AR_OriginObj); i++){
		new String:AR_buffer[512],String:AR_buffer2[512]
		GetArrayString(AR_OriginObj, i, AR_buffer, sizeof(AR_buffer));
		GetArrayString(AR_Obj, i, AR_buffer2, sizeof(AR_buffer2));
		KvSetString(kv, AR_buffer,AR_buffer2 );
	}
	
	KvRewind(kv);
	KeyValuesToFile(kv, ObjCfgPathN)
	CloseHandle(kv);
	
	//====================================================================================================
	//預先建立原文表 Create Original Code List
	
	//if(!FileExists(ObjCfgPathN, true)) return
	new Handle:kv3 = CreateKeyValues("Objective");
	if (FileToKeyValues(kv3, ObjCfgPathN)){
		KvJumpToKey(kv3, "Original",true)
		KvDeleteThis(kv3); //Delete old codes
		KvRewind(kv3);
		KvJumpToKey(kv3, "Original",true)
		
		for(new i = 0; i < GetArraySize(AR_OriginObj); i++){
			new String:AR_buffer[512],String:ObjectiveMessage[512]
			GetArrayString(AR_OriginObj, i, AR_buffer, sizeof(AR_buffer));
			GetArrayString(AR_Obj, i, ObjectiveMessage, sizeof(ObjectiveMessage));
			KvSetString(kv3, AR_buffer, ObjectiveMessage);
		}
		
		KvRewind(kv3);
		KeyValuesToFile(kv3, ObjCfgPathN)
	}
	
	CloseHandle(kv3);
}

#define IN_Compass		(1 << 28) //Objective button
public Action:OnPlayerRunCmd(client, &buttons, &impulsre, Float:vel[3], Float:angles[3], &weapon){
	if(buttons & IN_Compass) Command_objective2(client,1)
}

public state_change(Handle:event, const String:name[], bool:dontBroadcast){
	//PrintToChatAll("%s:state%d , game_type%d",name,GetEventInt(event, "state"),GetEventInt(event, "game_type"))
	//game_type 0 = NMO ; 1 = NMS
	//state 2 Practice End Freeze
	//state 3 Round Start
	//state 5 All Extracted
	//state 6 Extraction Expired
	//state 7 ??????? some time it showed up,but unknow reason.
	//state 8 Round End
	
	new states = GetEventInt(event, "state")
	if(states == 0){
		//PrintToServer("states:%d",states)
	}
	if(states == 1){
		//PrintToServer("states:%d",states)
		ShowCustomObjectiveText("OnStart","",0,1)
	}
	if(states == 2){
		//PrintToServer("states:%d",states)
		ShowCustomObjectiveText("OnStart","",0,1)
	}
	if(states == 2 || states == 3){
		extraction_begin_available = 1
		GameTextSetting()
	}
	if(states == 5){
		ShowCustomObjectiveText("OnAllPlayersExtracted","",0,1)
		extraction_begin_available = 0
	}
	if(states == 6){
		ShowCustomObjectiveText("OnExtractionExpired","",0,1)
		extraction_begin_available = 0
	}
}

public GameTextSetting(){
	new ent = -1;
	while ((ent = FindEntityByClassname(ent, "game_text")) != -1){
		new String:GetName[512],String:m_iszMessage[512]
		Entity_GetName(ent, GetName, sizeof(GetName))
		Format(GetName,sizeof(GetName),"<GameText>%d|%s",Entity_GetHammerId(ent),GetName)
		ShowCustomObjectiveText(GetName,m_iszMessage,sizeof(m_iszMessage))
		ReplaceString(m_iszMessage, sizeof(m_iszMessage), "\\n", "\n", false);
		if(!StrEqual(m_iszMessage,"NoData",false)) DispatchKeyValue(ent,"message",m_iszMessage );
	}
}

//==================================================================================================
//Common
public OnMapStart(){
	extraction_begin_available = 0
	GetCurrentMap(MapName, sizeof(MapName));
	
	HookEntityOutput("nmrih_objective_boundary", "OnObjectiveBegin", OnObjectiveBegin);
	
	BuildPath(Path_SM, ObjCfgPathN, sizeof(ObjCfgPathN), "/configs/ObjectiveT/%s.ini",MapName);
	new String:filePath[512]
	Format(filePath,sizeof(filePath),"maps/%s.nmo",MapName)
	if(!FileExists(filePath, true)/* || !FileExists(ObjCfgPathN, true)*/) return
	
	ObjList(0)
	ObjConfig()
	GameTextSetting()
}

public OnEntityCreated(entity, const String:classname[]){}
//==================================================================================================
//Objective Message
public Event_Extraction_Begin(Handle:hEvent, const String:name[], bool:dontBroadcast){
	/*
	new entity = -1
	if((entity = Entity_FindByClassName(entity, "nmrih_extract_point")) != INVALID_ENT_REFERENCE){
		//new String:CodeString[16]
		//GetEntPropString(entity, Prop_Data, "m_flExtractionTime", CodeString, sizeof(CodeString), 0);
		//PrintToChatAll("m_flExtractionTime:%s",CodeString)
		
		//PrintToChatAll("逃跑倒數:%d秒",RoundToNearest (GetEntPropFloat(entity, Prop_Data, "m_flExtractionTime")))
	}
	*/
	
	if(!extraction_begin_available) return
	ShowCustomObjectiveText("ExtractionBegin","",0,1)
	extraction_begin_available = 0
}

new String:ObjectiveNowText[256]
public Action:Command_objective2(id, Args){
	new String:ObjectiveNowingText[256]
	strcopy(ObjectiveNowingText, sizeof(ObjectiveNowingText), ObjectiveNowText)
	
	if(!strlen(ObjectiveNowingText) || StrEqual(ObjectiveNowingText,"NoData",false)) 
		Format(ObjectiveNowingText,sizeof(ObjectiveNowingText),"%t","NoObjectiveExists")
		
	PrintCenterText(id, ObjectiveNowingText);
	PrintHintText(id, "%t：%s","Mission",ObjectiveNowingText)
	SendDialogToOne(id, "%t：%s","Mission",ObjectiveNowingText)
	
	if(!Args) PrintToChat(id,"\x04(All) %t\x01：%s","Mission",ObjectiveNowingText)
}

public Action:Command_objective(id, Args){
	new String:Lists[2048]
	Format(Lists,sizeof(Lists),"===================================================================")
	for(new i = 0;i < GetArraySize(AR_OriginObj);i++){
		new String:CodeName[256],String:CodeMess[512],String:Message[512]
		GetArrayString(AR_OriginObj,i,CodeName,sizeof(CodeName))
		GetArrayString(AR_Obj,i,CodeMess,sizeof(CodeMess))
		ShowCustomObjectiveText(CodeName,Message,sizeof(Message))
		Format(Lists,sizeof(Lists),"%s\n#%d:%s - %s\n    %s",Lists,i,CodeName,CodeMess,Message)
	}
	Format(Lists,sizeof(Lists),"%s\n===================================================================",Lists)
	PrintToConsole(id,Lists)
}

public OnObjectiveBegin(const String:output[], caller, activator, Float:delay){
	ObjCounter++
	new String:ClassName[512]
	Entity_GetName(activator, ClassName, sizeof(ClassName));
	ShowCustomObjectiveText(ClassName)
}

stock ShowCustomObjectiveTextCommon(CommonType,const String:MSG[] = ""){
	new String:ObjectiveMessage[512]
	
	new Handle:kv = CreateKeyValues("Objective");
	if (FileToKeyValues(kv, ObjCfgPathN)){
		KvJumpToKey(kv, obj_language,true)
		KvGetString(kv, MSG,ObjectiveMessage, sizeof(ObjectiveMessage),"NoData")
		
		if(StrEqual(ObjectiveMessage,"NoData",false)){
			Format(ObjectiveMessage,sizeof(ObjectiveMessage),"%t",MSG)
			Format(ObjectiveNowText,sizeof(ObjectiveNowText),"%t",MSG)
		}
		else {
			strcopy(ObjectiveNowText, sizeof(ObjectiveMessage), ObjectiveMessage);
		}
	}
	CloseHandle(kv);
	
	DisplayCenterTextToAll(ObjectiveMessage)
	PrintHintTextAll(ObjectiveMessage)
	PrintToChatAll("\x04(All) %t\x01：%s","Mission",ObjectiveMessage)
	SendDialogToAll(ObjectiveMessage)
	
	if(obj_showserver){
		PrintToServer("ObjCode : %s",MSG)
		PrintToServer("ObjMess : %s",ObjectiveMessage)
	}
}

stock ShowCustomObjectiveText(const String:MSG[] = "",String:CallBack[] = "",size = 0,IsCommon = 0){
	if(!strlen(MSG)) return
	
	new String:ObjectiveMessage[512]
	
	new CommonType = -1
	if(StrEqual(MSG,"ExtractionBegin",false)) 		CommonType = 0
	if(StrEqual(MSG,"OnAllPlayersExtracted",false)) CommonType = 1
	if(StrEqual(MSG,"OnExtractionExpired",false)) 	CommonType = 2
	if(StrEqual(MSG,"OnStart",false)) 				CommonType = 3
	
	if(CommonType != -1){
		ShowCustomObjectiveTextCommon(CommonType,MSG)
		return;
	}
	
	new Handle:kv = CreateKeyValues("Objective");
	if (FileToKeyValues(kv, ObjCfgPathN)){
		KvJumpToKey(kv, obj_language,true)
		KvGetString(kv, MSG,ObjectiveMessage, sizeof(ObjectiveMessage),"NoData")
		strcopy(CallBack, size, ObjectiveMessage);
		
		if(StrEqual(ObjectiveMessage,"NoData")){
			KvSetString(kv, MSG, "NoData");
			KvRewind(kv);
			KeyValuesToFile(kv, ObjCfgPathN)
			
			new String:AR_buffer[512], locate = FindStringInArray(AR_OriginObj, MSG);
			if(locate == -1){
				PrintToServer("Array Error:%s",MSG)
				return;
			}
			GetArrayString(AR_Obj, locate, AR_buffer, sizeof(AR_buffer));
			strcopy(CallBack, size, ObjectiveMessage);
			strcopy(ObjectiveMessage,sizeof(ObjectiveMessage),AR_buffer)
			
			if(StrContains(MSG,"<GameText>",false) != -1){
				strcopy(CallBack, size, "NoData");
				//PrintToServer("GameText NoData : %s",MSG)
			}
		}
	
		if(strlen(ObjectiveMessage) && !size){
			DisplayCenterTextToAll(ObjectiveMessage)
			PrintHintTextAll(ObjectiveMessage)
			PrintToChatAll("\x04(All) %t\x01：%s","Mission",ObjectiveMessage)
			SendDialogToAll(ObjectiveMessage)
			
			SetConVarString(Cvar_ObjCode, MSG, true, false);
			SetConVarString(Cvar_ObjMess, ObjectiveMessage, true, false);
			
			//if(obj_showserver) PrintToServer("MSG:%s - %s",MSG,ObjectiveMessage)
			if(obj_showserver){
				PrintToServer("ObjCode (%d) %s",ObjCounter,MSG)
				PrintToServer("ObjMess (%d) %s",ObjCounter,ObjectiveMessage)
			}
		}
	}
	if(StrContains(MSG,"<GameText>",false) == -1){
		strcopy(ObjectiveNowText,sizeof(ObjectiveNowText),ObjectiveMessage)
	}
	else {
		PushArrayString(AR_ObjPast,ObjectiveMessage);
	}
	
	CloseHandle(kv);
}

//==================================================================================================
//Stock
DisplayCenterTextToAll(String:message[]){
	for (new i = 1; i <= 8; i++){
		if (!IsClientInGame(i) || IsFakeClient(i)) continue;
		PrintCenterText(i, "%s", message);
	}
}
PrintHintTextAll(String:message[]){
	new String:message2[256]
	Format(message2,sizeof(message2),"%t：%s","Mission",message)
	for (new i = 1; i <= 8; i++){
		if (!IsClientInGame(i) || IsFakeClient(i)) continue;
		PrintHintText(i, message2);
	}
}
SendDialogToAll(String:ObjectiveMessage[]){
	new String:ObjectiveMessage2[256]
	Format(ObjectiveMessage2,sizeof(ObjectiveMessage2),"%t：%s","Mission",ObjectiveMessage)
	for (new i = 1; i <= 8; i++){
		if (!IsClientInGame(i) || IsFakeClient(i)) continue;
		SendDialogToOne(i,ObjectiveMessage2);
	}
}
SendDialogToOne(client, String:text[], any:...){
	if (!IsClientInGame(client) || IsFakeClient(client)) return;
	
	new String:message[100];
	VFormat(message, sizeof(message), text, 3);	
	
	SetRandomSeed(GetRandomInt(1, 9999));
	new color2 = GetRandomInt(0,4)
	
	new Handle:kv = CreateKeyValues("Stuff", "title", message);
	KvSetColor(kv, "color", g_Colors[color2][0], g_Colors[color2][1], g_Colors[color2][2], 255);
	KvSetNum(kv, "level", 1);
	KvSetNum(kv, "time", 1);
	CreateDialog(client, kv, DialogType_Msg);
	CloseHandle(kv);
}
//移除UTF-8標記，用來支援記事本
//check and remove UTF-8 Bom
public FileUTF_BOM(const String:PathUTF[]){ 
	if(!FileExists(PathUTF)) return false
	new Handle:file = OpenFile(PathUTF, "rb");
	new String:buffer2[10]
	for(new i = 0;i < 3;i++){
		new buffer
		ReadFileCell(file, buffer, 1)
		Format(buffer2,sizeof(buffer2),"%x%s",buffer,buffer2)
	}
	CloseHandle(file);
	
	if(!StrEqual(buffer2,"bfbbef",false)) return false
	
	PrintToServer("File has UTF-8 Bom , removing")
	
	new Handle:AR_FileCell 		= CreateArray(1);
	new Handle:file2 = OpenFile(PathUTF, "r+b");
	while(!IsEndOfFile(file2)){
		new buffer
		ReadFileCell(file2, buffer, 1)
		PushArrayCell(AR_FileCell, buffer);
	}
	CloseHandle(file2);
	
	new Handle:file3 = OpenFile(PathUTF, "w+b");
	for(new i = 3;i < GetArraySize(AR_FileCell) - 1;i++){
		WriteFileCell(file3, GetArrayCell(AR_FileCell, i), 1)
	}
	CloseHandle(file3);
	
	return true
}

stock GetCurrObjEnt(){
	new maxEntities = GetMaxEntities();
	for (new entity = 0; entity < maxEntities; entity++) {
		new String:ClassName[64]
		GetEntityClassname(entity, ClassName, sizeof(ClassName));
		if(!IsValidEntity(entity) || !StrEqual(ClassName,"nmrih_objective_boundary",false)) continue;
		
		new m_bActive = GetEntProp(entity, Prop_Send, "m_bActive", 1)
		if(m_bActive) return entity
	}
	return -1;
}

/*
stock IsSystem2Functional(){
	new String:Error[512]
	if(GetExtensionFileStatus("system2.ext", Error, sizeof(Error)) == 1) return true
	
	new String:system2PathW[512],String:system2PathL[512]
	BuildPath(Path_SM, system2PathW, sizeof(system2PathW), "/extensions/system2.ext.dll");
	BuildPath(Path_SM, system2PathL, sizeof(system2PathL), "/extensions/system2.ext.so");
	if(!FileExists(system2PathW) && !FileExists(system2PathL)) return false
	
	ServerCommand("sm exts load system2.ext")
	
	new ExType = GetExtensionFileStatus("system2.ext", Error, sizeof(Error));
	//PrintToServer("System2:Type-%d,Error-%s",ExType,Error)
	if(ExType == -2){
		PrintToServer("SDC_Multilingual_Obj:System2模塊缺失 %s",Error)
		PrintToServer("SDC_Multilingual_Obj:Lost module named System2[%s]",Error)
	}
	else if(ExType == -1){
		PrintToServer("SDC_Multilingual_Obj:System2模塊載入失敗 %s",Error)
		PrintToServer("SDC_Multilingual_Obj:module System2 load error[%s]",Error)
	}
	else if(ExType == 0){
		PrintToServer("SDC_Multilingual_Obj:System2模塊回報錯誤 %s",Error)
		PrintToServer("SDC_Multilingual_Obj:module System2 loaded but reported an error[%s]",Error)
	}
	else if(ExType == 1) return true
	return false
}
*/