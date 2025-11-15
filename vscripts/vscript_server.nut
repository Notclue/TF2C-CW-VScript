//=============================================================================
//
// Purpose: Mod-specific overrides to VScript on the server.
//			Put your own functions below!
//
//=============================================================================

// Load KOCW libraries with error handling
try { IncludeScript("kocw/kocwtools"); } catch(e) { printl("[LOAD ERROR] kocwtools: " + e); }
try { IncludeScript("kocw/kocwcycle"); } catch(e) { printl("[LOAD ERROR] kocwcycle: " + e); }
try { IncludeScript("kocw/hudframework"); } catch(e) { printl("[LOAD ERROR] hudframework: " + e); }
try { IncludeScript("kocw/give_econ"); } catch(e) { printl("[LOAD ERROR] give_econ: " + e); }
try { IncludeScript("kocw/custom_entprops"); } catch(e) { printl("[LOAD ERROR] custom_entprops: " + e); }
try { IncludeScript("kocw/conditionhandler"); } catch(e) { printl("[LOAD ERROR] conditionhandler: " + e); }
try { IncludeScript("kocw/attributes/attribute_airblast"); } catch(e) { printl("[LOAD ERROR] attribute_airblast: " + e); }
try { IncludeScript("kocw/attributes/attribute_airdet"); } catch(e) { printl("[LOAD ERROR] attribute_airdet: " + e); }

//=============================================================================
// Server Initialization
//=============================================================================

// Create a think entity for continuous processing
::g_ThinkEntity <- null;

// Global think function for processing healers and other periodic tasks
::ServerThink <- function()
{
	// Process all active healers with error handling
	try
	{
		local deltaTime = 0.1; // Fixed delta time since we think every 0.1 seconds
		KOCWTools.ProcessHealers(deltaTime);
	}
	catch (err)
	{
		printl("[KOCWTools ERROR] ServerThink failed: " + err);
	}
	
	// Process KOCWCycle (RTV and map cycling)
	try
	{
		KOCWCycle.Think();
	}
	catch (err)
	{
		printl("[KOCWCycle ERROR] Think failed: " + err);
	}
	
	// Process HUDFramework (tracker updates and display)
	try
	{
		HUDFramework.Think();
	}
	catch (err)
	{
		printl("[HUDFramework ERROR] Think failed: " + err);
	}
	
	// Process ConditionHandler (custom conditions)
	try
	{
		ConditionHandler.Think();
	}
	catch (err)
	{
		printl("[ConditionHandler ERROR] Think failed: " + err);
	}
	
	// Process AttributeAirblast (custom airblast system)
	try
	{
		if ("AttributeAirblast" in getroottable() && "Think" in AttributeAirblast)
		{
			AttributeAirblast.Think();
		}
		else
		{
			printl("[AttributeAirblast ERROR] Not loaded or missing Think function!");
		}
	}
	catch (err)
	{
		printl("[AttributeAirblast ERROR] Think failed: " + err);
	}
	
	// Process AttributeAirdet (airburst sticky bombs)
	try
	{
		if ("AttributeAirdet" in getroottable() && "Think" in AttributeAirdet)
		{
			AttributeAirdet.Think();
		}
		else
		{
			printl("[AttributeAirdet ERROR] Not loaded or missing Think function!");
		}
	}
	catch (err)
	{
		printl("[AttributeAirdet ERROR] Think failed: " + err);
	}
	
	// Return interval for next think (0.1 = 10 times per second)
	return 0.1;
}

// Initialize or re-initialize the think system
function InitializeThinkSystem()
{
	// Clean up old think entity if it exists
	if (g_ThinkEntity && g_ThinkEntity.IsValid())
	{
		g_ThinkEntity.Kill();
	}
	
	// Create a new logic_script entity for thinking
	g_ThinkEntity = Entities.CreateByClassname("logic_script");
	
	if (g_ThinkEntity)
	{
		// Make sure it has a script scope
		g_ThinkEntity.ValidateScriptScope();
		local scope = g_ThinkEntity.GetScriptScope();
		
		// Assign our think function to the scope
		scope.Think <- ServerThink;
		
		// Start the think loop
		AddThinkToEnt(g_ThinkEntity, "Think");
		
		return true;
	}
	else
	{
		printl("[KOCWTools ERROR] Failed to create think entity!");
		return false;
	}
}

// Initialize server-side systems
function OnServerActivate()
{
	InitializeThinkSystem();
	
	if ("KOCWCycle" in getroottable() && "Initialize" in KOCWCycle)
		KOCWCycle.Initialize();
	
	if ("HUDFramework" in getroottable() && "Initialize" in HUDFramework)
		HUDFramework.Initialize();
}

// Game event: Map end
::OnGameEvent_teamplay_round_win <- function(params)
{
	// Handle map end for cycling
	if ("KOCWCycle" in getroottable() && "OnMapEnd" in KOCWCycle)
		KOCWCycle.OnMapEnd();
}

// Game event: Player connected
::OnGameEvent_player_connect <- function(params)
{
	if ("userid" in params)
	{
		if ("KOCWCycle" in getroottable() && "OnPlayerConnected" in KOCWCycle)
			KOCWCycle.OnPlayerConnected(params.userid);
	}
}

// Game event: Player disconnected
::OnGameEvent_player_disconnect <- function(params)
{
	if ("userid" in params)
	{
		local player = GetPlayerFromUserID(params.userid);
		if (player && player.IsValid())
		{
			if ("HUDFramework" in getroottable() && "OnPlayerDisconnect" in HUDFramework)
				HUDFramework.OnPlayerDisconnect(player);
			if ("GiveEcon" in getroottable() && "OnPlayerDisconnect" in GiveEcon)
				GiveEcon.OnPlayerDisconnect(player);
			if ("ConditionHandler" in getroottable() && "OnPlayerDisconnect" in ConditionHandler)
				ConditionHandler.OnPlayerDisconnect(player);
			if ("AttributeAirblast" in getroottable() && "OnPlayerDisconnect" in AttributeAirblast)
				AttributeAirblast.OnPlayerDisconnect(player);
			if ("AttributeAirdet" in getroottable() && "OnPlayerDisconnect" in AttributeAirdet)
				AttributeAirdet.OnPlayerDisconnect(player);
		}
		
		if ("KOCWCycle" in getroottable() && "OnPlayerDisconnected" in KOCWCycle)
			KOCWCycle.OnPlayerDisconnected(params.userid);
	}
}

// Re-initialize think on player spawn (in case it got killed)
::OnGameEvent_player_spawn <- function(params)
{
	// Check if think entity still exists
	if (!g_ThinkEntity || !g_ThinkEntity.IsValid())
	{
		InitializeThinkSystem();
	}
	
	// Handle HUD tracker resets and weapon cleanup
	if ("userid" in params)
	{
		local player = GetPlayerFromUserID(params.userid);
		if (player && player.IsValid())
		{
			if ("HUDFramework" in getroottable() && "OnPlayerSpawn" in HUDFramework)
				HUDFramework.OnPlayerSpawn(player);
			if ("GiveEcon" in getroottable() && "OnPlayerSpawn" in GiveEcon)
				GiveEcon.OnPlayerSpawn(player);
		}
	}
}

// Game event: Player chat message (for RTV and GiveEcon commands)
::OnGameEvent_player_say <- function(params)
{
	// Get the player who sent the message
	if ("userid" in params && "text" in params)
	{
		local player = GetPlayerFromUserID(params.userid);
		if (player && player.IsValid())
		{
			// Check RTV command
			if ("KOCWCycle" in getroottable() && "CheckRTVCommand" in KOCWCycle)
				KOCWCycle.CheckRTVCommand(player, params.text);
			
			// Check GiveEcon commands (!giveweapon, !addattr, etc.)
			if ("OnPlayerSayGiveEcon" in getroottable())
			{
				OnPlayerSayGiveEcon(player, params.text);
			}
			else if ("GiveEcon" in getroottable() && "OnPlayerSay" in GiveEcon)
			{
				GiveEcon.OnPlayerSay(player, params.text);
			}
		}
	}
}

// Game event: Player death
::OnGameEvent_player_death <- function(params)
{
	if ("userid" in params)
	{
		local player = GetPlayerFromUserID(params.userid);
		if (player && player.IsValid())
		{
			if ("ConditionHandler" in getroottable() && "OnPlayerDeath" in ConditionHandler)
				ConditionHandler.OnPlayerDeath(player);
		}
	}
}

// Game event: Player touches resupply cabinet
::OnGameEvent_post_inventory_application <- function(params)
{
	if ("userid" in params)
	{
		local player = GetPlayerFromUserID(params.userid);
		if (player && player.IsValid())
		{
			if ("GiveEcon" in getroottable() && "OnPlayerResupply" in GiveEcon)
				GiveEcon.OnPlayerResupply(player);
		}
	}
}

// Safely collect game event callbacks with error handling
try
{
	if (typeof this == "table")
	{
		__CollectGameEventCallbacks(this);
	}
	else
	{
		__CollectGameEventCallbacks(getroottable());
	}
}
catch (err)
{
	printl("[VScript ERROR] Failed to collect game event callbacks: " + err);
	printl("[VScript ERROR] Attempting to continue without event callbacks...");
}

// Call initialization when script loads
try
{
	OnServerActivate();
}
catch (err)
{
	printl("[VScript ERROR] OnServerActivate failed: " + err);
}