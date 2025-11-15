// ============================================================================
// KOCWCycle - Rock The Vote and Map Cycling System
// Ported from SourcePawn to VScript for Mapbase
// ============================================================================

// Global state
::KOCWCycle <- {
    // Map lists
    baseMapList = []
    activeMapList = []
    
    // RTV state
    bInChange = false
    bRTVAllowed = false
    iVotesNeeded = 0
    iVotes = 0
    votedPlayers = {} // userid -> bool
    
    // ConVars (stored as floats/ints)
    cvRTVPlayersNeeded = 0.60
    cvRTVMinPlayers = 0
    cvRTVInitialDelay = 30.0
    
    // Timers
    initTime = 0.0
    lastUpdateTime = 0.0
    changeMapTime = 0.0
}

// ============================================================================
// Initialization
// ============================================================================

function KOCWCycle::Initialize() {
    printl("[KOCWCycle] Initializing...")
    
    // Reset state
    this.baseMapList.clear()
    this.activeMapList.clear()
    this.votedPlayers.clear()
    this.bInChange = false
    this.bRTVAllowed = false
    this.iVotes = 0
    this.iVotesNeeded = 0
    
    // Load map list
    this.LoadMapList()
    
    // Set initial delay timer
    this.initTime = Time()
    
    // Update client counts
    this.UpdateClientCounts()
    
    // Select initial next map
    this.SelectNextMap()
    
    printl("[KOCWCycle] Initialized successfully")
}

function KOCWCycle::OnMapEnd() {
    this.bRTVAllowed = false
    this.iVotes = 0
    this.iVotesNeeded = 0
    this.bInChange = false
    this.votedPlayers.clear()
}

// ============================================================================
// Client Management
// ============================================================================

function KOCWCycle::GetClientCount(inGameOnly = true) {
    local count = 0
    local player = null
    
    while ((player = Entities.FindByClassname(player, "player")) != null) {
        if (player.IsValid()) {
            // Check if player is actually connected (has valid netprops)
            try {
                local health = NetProps.GetPropInt(player, "m_iHealth")
                if (health != null) {
                    count++
                }
            } catch (e) {
                // Player not fully connected
            }
        }
    }
    
    return count
}

function KOCWCycle::UpdateClientCounts() {
    local totalVoters = this.GetClientCount(true)
    this.iVotesNeeded = ceil(this.cvRTVPlayersNeeded * totalVoters).tointeger()
    
    // Check if we should start RTV
    if (this.iVotes > 0 && totalVoters > 0 && this.iVotes >= this.iVotesNeeded && this.bRTVAllowed) {
        this.StartRTV()
    }
}

function KOCWCycle::OnPlayerConnected(userid) {
    // Update vote counts when player connects
    this.UpdateClientCounts()
}

function KOCWCycle::OnPlayerDisconnected(userid) {
    // Remove player's vote if they had voted
    if (userid.tostring() in this.votedPlayers) {
        if (this.votedPlayers[userid.tostring()]) {
            this.iVotes--
            delete this.votedPlayers[userid.tostring()]
        }
    }
    
    // Update vote counts
    this.UpdateClientCounts()
}

// ============================================================================
// Map List Management
// ============================================================================

function KOCWCycle::LoadMapList() {
    // Try multiple possible paths for mapcycle.txt
    local possiblePaths = [
        "cfg/mapcycle.txt",
        "../cfg/mapcycle.txt",
        "../../cfg/mapcycle.txt",
        "mapcycle.txt"
    ]
    
    local mapcycleContent = null
    local loadedFrom = null
    
    foreach (path in possiblePaths) {
        mapcycleContent = FileToString(path)
        if (mapcycleContent != null) {
            loadedFrom = path
            break
        }
    }
    
    if (mapcycleContent != null) {
        // Parse the file content line by line
        local lines = split(mapcycleContent, "\n")
        
        foreach (line in lines) {
            // Remove whitespace and comments
            line = strip(line)
            
            // Skip empty lines and comments
            if (line.len() == 0 || line[0] == '/' || line[0] == '#') {
                continue
            }
            
            // Add map to list
            this.baseMapList.append(line)
        }
        
        printl("[KOCWCycle] Loaded " + this.baseMapList.len() + " maps from " + loadedFrom)
    } else {
        // Fallback to hardcoded list if file not found
        printl("[KOCWCycle] Warning: Could not load mapcycle.txt from any path, using default map list")
        
        this.baseMapList = [
            "cp_dustbowl",
            "ctf_2fort",
            "pl_goldrush",
            "koth_harvest_final",
            "cp_granary",
            "ctf_turbine",
            "pl_badwater",
            "koth_viaduct",
            "cp_gravelpit",
            "ctf_doublecross",
            "pl_upward",
            "koth_lakeside",
            "cp_steel",
            "ctf_sawmill",
            "pl_thundermountain"
        ]
        
        printl("[KOCWCycle] Loaded " + this.baseMapList.len() + " default maps")
    }
}

function KOCWCycle::GetMapPrefix(mapName) {
    local underscorePos = mapName.find("_")
    if (underscorePos != null) {
        return mapName.slice(0, underscorePos)
    }
    return mapName
}

function KOCWCycle::ResetActiveMapList() {
    // Copy base map list to temp array
    local tempList = []
    foreach (map in this.baseMapList) {
        tempList.append(map)
    }
    
    // Clear active list
    this.activeMapList.clear()
    
    local lastPrefix = ""
    local tries = 0
    local maxTries = 100
    
    // Shuffle maps avoiding consecutive prefixes
    while (tempList.len() > 0 && tries < maxTries) {
        local index = RandomInt(0, tempList.len() - 1)
        local map = tempList[index]
        local prefix = this.GetMapPrefix(map)
        
        // Try to avoid same prefix as last map
        if (prefix == lastPrefix && tries < tempList.len()) {
            tries++
            continue
        }
        
        // Add to active list and remove from temp
        this.activeMapList.append(map)
        tempList.remove(index)
        lastPrefix = prefix
        tries = 0
    }
    
    printl("[KOCWCycle] Shuffled map list: " + this.activeMapList.len() + " maps")
}

function KOCWCycle::SelectNextMap() {
    // Refill active list if empty
    if (this.activeMapList.len() < 1) {
        this.ResetActiveMapList()
    }
    
    // Get first map from active list
    local newMap = this.activeMapList[0]
    this.activeMapList.remove(0)
    
    // In VScript, we can't directly set nextmap, but we can store it
    // The actual map change would need to be triggered via server command
    printl("[KOCWCycle] Selected next map: " + newMap)
    
    // Store for later use
    if (!("nextMap" in getroottable())) {
        ::nextMap <- newMap
    } else {
        ::nextMap = newMap
    }
    
    return newMap
}

// ============================================================================
// RTV Logic
// ============================================================================

function KOCWCycle::CheckRTVCommand(player, text) {
    if (!player || !player.IsValid()) {
        return false
    }
    
    // Normalize text
    local lowerText = text.tolower()
    
    // Check for RTV commands
    if (lowerText == "rtv" || lowerText == "!rtv" || lowerText == "rockthevote" || lowerText == "/rtv") {
        this.AttemptRTV(player)
        return true
    }
    
    return false
}

function KOCWCycle::AttemptRTV(player) {
    if (!player || !player.IsValid()) {
        return
    }
    
    // Check if RTV is allowed
    if (!this.bRTVAllowed) {
        // Check if initial delay has passed
        local currentTime = Time()
        if (currentTime - this.initTime < this.cvRTVInitialDelay) {
            local timeLeft = (this.cvRTVInitialDelay - (currentTime - this.initTime)).tointeger()
            ClientPrint(player, 3, "\x073EFF3E[KOCW]\x01 RTV will be available in " + timeLeft + " seconds")
            return
        } else {
            this.bRTVAllowed = true
        }
    }
    
    // Check minimum players
    local clientCount = this.GetClientCount(true)
    if (clientCount < this.cvRTVMinPlayers) {
        ClientPrint(player, 3, "\x073EFF3E[KOCW]\x01 Need at least " + this.cvRTVMinPlayers + " players for RTV")
        return
    }
    
    // Get player userid
    local userid = 0
    try {
        userid = NetProps.GetPropInt(player, "m_iUserID")
    } catch (e) {
        printl("[KOCWCycle] Error getting userid: " + e)
        return
    }
    
    local useridStr = userid.tostring()
    
    // Check if already voted
    if (useridStr in this.votedPlayers && this.votedPlayers[useridStr]) {
        ClientPrint(player, 3, "\x073EFF3E[KOCW]\x01 You have already voted for RTV (" + this.iVotes + "/" + this.iVotesNeeded + ")")
        return
    }
    
    // Register vote
    this.iVotes++
    this.votedPlayers[useridStr] <- true
    
    // Get player name
    local playerName = "Player"
    try {
        playerName = NetProps.GetPropString(player, "m_szNetname")
    } catch (e) {
        // Use default name
    }
    
    // Announce vote to all players
    PrintToChatAll("\x073EFF3E[KOCW]\x01 " + playerName + " wants to rock the vote (" + this.iVotes + "/" + this.iVotesNeeded + ")")
    
    // Check if we have enough votes
    if (this.iVotes >= this.iVotesNeeded) {
        this.StartRTV()
    }
}

function KOCWCycle::StartRTV() {
    if (this.bInChange) {
        return
    }
    
    // Get next map
    local nextMap = "nextMap" in getroottable() ? ::nextMap : "Unknown"
    
    // Announce map change to all players
    PrintToChatAll("\x073EFF3E[KOCW]\x01 Vote passed! Changing to " + nextMap + " in 5 seconds...")
    
    this.bInChange = true
    this.changeMapTime = Time() + 5.0
    
    this.ResetRTV()
    this.bRTVAllowed = false
}

function KOCWCycle::ChangeMap() {
    if (!this.bInChange) {
        return
    }
    
    local nextMap = "nextMap" in getroottable() ? ::nextMap : null
    if (nextMap) {
        printl("[KOCWCycle] Executing map change to: " + nextMap)
        
        // Execute server command to change map
        // Note: In VScript, we need to use SendToConsole which may not work in all contexts
        // Alternative: Use a point_servercommand entity
        SendToConsole("changelevel " + nextMap)
    }
    
    this.bInChange = false
}

function KOCWCycle::ResetRTV() {
    this.iVotes = 0
    this.votedPlayers.clear()
}

// ============================================================================
// Think/Update Function (called from vscript_server.nut)
// ============================================================================

function KOCWCycle::Think() {
    local currentTime = Time()
    
    // Enable RTV after initial delay
    if (!this.bRTVAllowed && currentTime - this.initTime >= this.cvRTVInitialDelay) {
        this.bRTVAllowed = true
    }
    
    // Update client counts periodically (every 10 seconds)
    if (currentTime - this.lastUpdateTime >= 10.0) {
        this.UpdateClientCounts()
        this.lastUpdateTime = currentTime
    }
    
    // Check if it's time to change map
    if (this.bInChange && this.changeMapTime > 0 && currentTime >= this.changeMapTime) {
        this.ChangeMap()
    }
}

// ============================================================================
// Utility Functions
// ============================================================================

// Helper to print to all players' chat
function PrintToChatAll(message) {
    // Print to all players using the built-in ClientPrint function
    // destination: 2 = console, 3 = chat, 4 = center
    local player = null
    while ((player = Entities.FindByClassname(player, "player")) != null) {
        if (player.IsValid()) {
            ClientPrint(player, 3, message)
        }
    }
    // Also print to console for logging
    printl(message)
}

// Helper to print message using ShowMessage (HUD text for all players)
function ShowMessageToAll(message) {
    ShowMessage(message)
    printl(message)
}

// Initialize on load
printl("===========================================")
printl("KOCWCycle VScript Library Loaded")
printl("===========================================")
