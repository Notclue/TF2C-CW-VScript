// ============================================================================
// HUD Framework - VScript Edition
// Purpose: HUD tracker system for displaying custom resource meters
// Ported from SourcePawn to Mapbase VScript
// ============================================================================

// Tracker flags
const RTF_NONE = 0;
const RTF_PERCENTAGE = 2;      // Display value as a percentage (1 << 1)
const RTF_DING = 4;            // Play sound when fully charged (1 << 2)
const RTF_RECHARGES = 8;       // Automatically recharge over time (1 << 3)
const RTF_NOOVERWRITE = 16;    // Do not overwrite existing tracker (1 << 4)
const RTF_CLEARONSPAWN = 32;   // Reset on respawning (1 << 5)
const RTF_FORWARDONFULL = 64;  // Fire callback when fully charged (1 << 6)

const TRACKER_MAX_LENGTH = 64;
const UPDATE_INTERVAL = 0.2; // Update every 0.2 seconds

// ============================================================================
// HUD Framework Namespace
// ============================================================================

::HUDFramework <- {
    // Storage: playerIndex -> array of trackers
    _playerTrackers = {}
    
    // Update tracking
    _lastUpdateTime = 0.0
    _updateInterval = UPDATE_INTERVAL
    
    // HUD positioning
    _hudX = 0.77
    _hudY = 0.89
    _hudHorizontalSpacing = 0.075  // Space between tracker boxes
    
    // Callbacks for full charge events
    _onRechargeCallbacks = []
    
    version = "1.3-VScript"
}

// ============================================================================
// Resource Tracker Class
// ============================================================================

class ResourceTracker {
    name = "";
    value = 0.0;
    maxValue = 0.0;
    rechargeRate = 0.0;
    flags = RTF_NONE;
    
    constructor(trackerName) {
        name = trackerName;
    }
    
    function HasFlags(checkFlags) {
        return (flags & checkFlags) == checkFlags;
    }
    
    function GetDisplayValue() {
        if (HasFlags(RTF_PERCENTAGE)) {
            return (maxValue > 0) ? ((value / maxValue) * 100.0) : 0.0;
        }
        return value;
    }
    
    function IsFull() {
        return value >= maxValue;
    }
}

// ============================================================================
// Initialization
// ============================================================================

function HUDFramework::Initialize() {
    printl("[HUDFramework] Initializing...")
    
    this._playerTrackers.clear()
    this._lastUpdateTime = Time()
    
    printl("[HUDFramework] Initialized successfully")
}

function HUDFramework::OnPlayerSpawn(player) {
    if (!player || !player.IsValid()) {
        return
    }
    
    local playerIdx = player.entindex().tostring()
    
    if (playerIdx in this._playerTrackers) {
        local trackers = this._playerTrackers[playerIdx]
        
        // Clear trackers that have RTF_CLEARONSPAWN flag
        for (local i = trackers.len() - 1; i >= 0; i--) {
            local tracker = trackers[i]
            if (tracker.HasFlags(RTF_CLEARONSPAWN)) {
                tracker.value = 0.0
            }
        }
    }
}

function HUDFramework::OnPlayerDisconnect(player) {
    if (!player || !player.IsValid()) {
        return
    }
    
    local playerIdx = player.entindex().tostring()
    
    // Clean up all HUD entities for this player (up to 10 possible trackers)
    for (local i = 0; i < 10; i++) {
        local hudEntityName = "hudframework_text_" + playerIdx + "_" + i
        local hudEntity = Entities.FindByName(null, hudEntityName)
        if (hudEntity && hudEntity.IsValid()) {
            hudEntity.Kill()
        }
    }
    
    // Remove tracker data
    if (playerIdx in this._playerTrackers) {
        delete this._playerTrackers[playerIdx]
    }
}

// ============================================================================
// Tracker Management Functions
// ============================================================================

function HUDFramework::CreateTracker(player, name, overwrite = true) {
    if (!player || !player.IsValid()) {
        return false
    }
    
    local playerIdx = player.entindex().tostring()
    
    // Initialize player's tracker array if needed
    if (!(playerIdx in this._playerTrackers)) {
        this._playerTrackers[playerIdx] <- []
    }
    
    // Check if tracker already exists
    local existingIdx = this._FindTracker(player, name)
    
    if (existingIdx != -1) {
        if (!overwrite) {
            return false // Don't overwrite existing
        }
        
        // Remove old tracker
        this._playerTrackers[playerIdx].remove(existingIdx)
    }
    
    // Create new tracker
    local tracker = ResourceTracker(name)
    this._playerTrackers[playerIdx].append(tracker)
    
    return true
}

function HUDFramework::RemoveTracker(player, name) {
    if (!player || !player.IsValid()) {
        return false
    }
    
    local playerIdx = player.entindex().tostring()
    
    if (!(playerIdx in this._playerTrackers)) {
        return false
    }
    
    local idx = this._FindTracker(player, name)
    if (idx == -1) {
        return false
    }
    
    this._playerTrackers[playerIdx].remove(idx)
    return true
}

function HUDFramework::GetTracker(player, name) {
    if (!player || !player.IsValid()) {
        return null
    }
    
    local playerIdx = player.entindex().tostring()
    
    if (!(playerIdx in this._playerTrackers)) {
        return null
    }
    
    local idx = this._FindTracker(player, name)
    if (idx == -1) {
        return null
    }
    
    return this._playerTrackers[playerIdx][idx]
}

function HUDFramework::_FindTracker(player, name) {
    local playerIdx = player.entindex().tostring()
    
    if (!(playerIdx in this._playerTrackers)) {
        return -1
    }
    
    local trackers = this._playerTrackers[playerIdx]
    
    for (local i = 0; i < trackers.len(); i++) {
        if (trackers[i].name == name) {
            return i
        }
    }
    
    return -1
}

// ============================================================================
// Tracker Value Functions
// ============================================================================

function HUDFramework::GetValue(player, name) {
    local tracker = this.GetTracker(player, name)
    if (!tracker) {
        return 0.0
    }
    
    return tracker.value
}

function HUDFramework::SetValue(player, name, value) {
    local tracker = this.GetTracker(player, name)
    if (!tracker) {
        return false
    }
    
    local oldValue = tracker.value
    local wasFull = tracker.IsFull()
    
    // Clamp to max
    tracker.value = (value > tracker.maxValue) ? tracker.maxValue : value
    if (tracker.value < 0.0) {
        tracker.value = 0.0
    }
    
    // Check if just became full
    if (!wasFull && tracker.IsFull()) {
        this._OnTrackerFull(player, tracker)
    }
    
    return true
}

function HUDFramework::AddValue(player, name, amount) {
    local currentValue = this.GetValue(player, name)
    return this.SetValue(player, name, currentValue + amount)
}

function HUDFramework::SetMax(player, name, maxValue) {
    local tracker = this.GetTracker(player, name)
    if (!tracker) {
        return false
    }
    
    tracker.maxValue = maxValue
    
    // Clamp current value if needed
    if (tracker.value > tracker.maxValue) {
        tracker.value = tracker.maxValue
    }
    
    return true
}

function HUDFramework::SetRechargeRate(player, name, ratePerSecond) {
    local tracker = this.GetTracker(player, name)
    if (!tracker) {
        return false
    }
    
    // Convert rate per second to rate per update interval
    tracker.rechargeRate = ratePerSecond * this._updateInterval
    
    return true
}

function HUDFramework::SetFlags(player, name, flags) {
    local tracker = this.GetTracker(player, name)
    if (!tracker) {
        return false
    }
    
    tracker.flags = flags
    
    return true
}

// ============================================================================
// Think/Update Functions
// ============================================================================

function HUDFramework::Think() {
    local currentTime = Time()
    local deltaTime = currentTime - this._lastUpdateTime
    
    // Only update at specified intervals
    if (deltaTime < this._updateInterval) {
        return
    }
    
    this._lastUpdateTime = currentTime
    
    // Process all players
    local player = null
    while ((player = Entities.FindByClassname(player, "player")) != null) {
        if (player.IsValid()) {
            this._ProcessPlayerTrackers(player)
            this._DisplayPlayerTrackers(player)
        }
    }
}

function HUDFramework::_ProcessPlayerTrackers(player) {
    local playerIdx = player.entindex().tostring()
    
    if (!(playerIdx in this._playerTrackers)) {
        return
    }
    
    local trackers = this._playerTrackers[playerIdx]
    
    foreach (tracker in trackers) {
        // Recharge if enabled
        if (tracker.HasFlags(RTF_RECHARGES)) {
            local oldValue = tracker.value
            local wasFull = tracker.IsFull()
            
            tracker.value += tracker.rechargeRate
            
            // Clamp to max
            if (tracker.value > tracker.maxValue) {
                tracker.value = tracker.maxValue
            }
            
            // Check if just became full
            if (!wasFull && tracker.IsFull()) {
                this._OnTrackerFull(player, tracker)
            }
        }
    }
}

function HUDFramework::_DisplayPlayerTrackers(player) {
    local playerIdx = player.entindex().tostring()
    
    if (!(playerIdx in this._playerTrackers)) {
        return
    }
    
    local trackers = this._playerTrackers[playerIdx]
    
    if (trackers.len() == 0) {
        return
    }
    
    // Display each tracker in its own colored box, stacked horizontally
    foreach (idx, tracker in trackers) {
        local displayValue = tracker.GetDisplayValue().tointeger()
        
        // Format: "NAME\nVALUE" for centered box display
        local displayText = tracker.name.toupper() + "\n"
        
        if (tracker.HasFlags(RTF_PERCENTAGE)) {
            displayText += displayValue + "%"
        } else {
            displayText += displayValue.tostring()
        }
        
        // Calculate X position for this tracker (stack horizontally, right to left)
        local xPos = this._hudX - (this._hudHorizontalSpacing * idx)
        
        // Choose color based on charge level
        local color = this._GetTrackerColor(tracker)
        
        // Display this tracker's HUD box
        this._DisplayHUDText(player, displayText, xPos, this._hudY, idx, color)
    }
}

function HUDFramework::_DisplayHUDText(player, text, xPos, yPos, trackerIdx, color) {
    local playerIdx = player.entindex().tostring()
    local hudEntityName = "hudframework_text_" + playerIdx + "_" + trackerIdx
    
    // Find or create game_text entity for this tracker
    local hudEntity = Entities.FindByName(null, hudEntityName)
    
    if (!hudEntity || !hudEntity.IsValid()) {
        // Create a new game_text entity
        hudEntity = Entities.CreateByClassname("game_text")
        if (!hudEntity) {
            return // Failed to create
        }
        
        hudEntity.__KeyValueFromString("targetname", hudEntityName)
        hudEntity.__KeyValueFromString("channel", (1 + trackerIdx).tostring())
        hudEntity.__KeyValueFromString("effect", "0") // No special effect
        hudEntity.__KeyValueFromString("fadein", "0")
        hudEntity.__KeyValueFromString("fadeout", "0.1")
        hudEntity.__KeyValueFromString("fxtime", "0")
        hudEntity.__KeyValueFromString("holdtime", "0.3")
        hudEntity.__KeyValueFromString("x", xPos.tostring())
        hudEntity.__KeyValueFromString("y", yPos.tostring())
        hudEntity.__KeyValueFromString("spawnflags", "1") // All players
    }
    
    // Update color and text
    // Keep text color white, use charge color for background
    hudEntity.__KeyValueFromString("color", "255 255 255") // White text
    local colorStr = color.r + " " + color.g + " " + color.b
    hudEntity.__KeyValueFromString("color2", colorStr) // Background color
    hudEntity.__KeyValueFromString("message", text)
    
    // Display to player
    try {
        DoEntFireByInstanceHandle(hudEntity, "Display", "", 0, player, player)
    } catch (e) {
        // Fallback: try alternate method
        EntFireByHandle(hudEntity, "Display", "", 0, player, player)
    }
}

function HUDFramework::_GetTrackerColor(tracker) {
    // Calculate fill percentage
    local fillPercent = 0.0
    if (tracker.maxValue > 0) {
        fillPercent = tracker.value / tracker.maxValue
    }
    
    // Color scheme based on charge level
    if (fillPercent >= 1.0) {
        // Full - Bright green
        return { r = 100, g = 255, b = 100 }
    } else if (fillPercent >= 0.75) {
        // High - Green
        return { r = 80, g = 200, b = 80 }
    } else if (fillPercent >= 0.50) {
        // Medium - Yellow-orange
        return { r = 200, g = 150, b = 50 }
    } else if (fillPercent >= 0.25) {
        // Low - Orange
        return { r = 200, g = 100, b = 50 }
    } else {
        // Very low - Red
        return { r = 180, g = 50, b = 50 }
    }
}

// ============================================================================
// Event Callbacks
// ============================================================================

function HUDFramework::_OnTrackerFull(player, tracker) {
    // Play ding sound if enabled
    if (tracker.HasFlags(RTF_DING)) {
        try {
            player.EmitSound("TFPlayer.Recharged")
        } catch (e) {
            // Sound not available
        }
    }
    
    // Fire callbacks if enabled
    if (tracker.HasFlags(RTF_FORWARDONFULL)) {
        foreach (callback in this._onRechargeCallbacks) {
            try {
                callback(player, tracker.name, tracker.value)
            } catch (e) {
                printl("[HUDFramework] Error in recharge callback: " + e)
            }
        }
    }
}

function HUDFramework::AddRechargeCallback(callback) {
    this._onRechargeCallbacks.append(callback)
}

// ============================================================================
// Utility Functions
// ============================================================================

function HUDFramework::GetAllTrackers(player) {
    if (!player || !player.IsValid()) {
        return []
    }
    
    local playerIdx = player.entindex().tostring()
    
    if (!(playerIdx in this._playerTrackers)) {
        return []
    }
    
    return this._playerTrackers[playerIdx]
}

function HUDFramework::ClearAllTrackers(player) {
    if (!player || !player.IsValid()) {
        return false
    }
    
    local playerIdx = player.entindex().tostring()
    
    if (playerIdx in this._playerTrackers) {
        this._playerTrackers[playerIdx].clear()
        return true
    }
    
    return false
}

// ============================================================================
// Helper Functions (convenience wrappers)
// ============================================================================

// Quick setup for a simple percentage tracker
function HUDFramework::CreatePercentageTracker(player, name, maxValue, rechargeRate = 0.0) {
    this.CreateTracker(player, name, true)
    this.SetMax(player, name, maxValue)
    this.SetValue(player, name, 0.0)
    
    local flags = RTF_PERCENTAGE
    if (rechargeRate > 0.0) {
        flags = flags | RTF_RECHARGES
        this.SetRechargeRate(player, name, rechargeRate)
    }
    
    this.SetFlags(player, name, flags)
}

// Quick setup for a charge meter with ding
function HUDFramework::CreateChargeMeter(player, name, maxValue, rechargeRate = 0.0) {
    this.CreateTracker(player, name, true)
    this.SetMax(player, name, maxValue)
    this.SetValue(player, name, 0.0)
    
    local flags = RTF_PERCENTAGE | RTF_DING
    if (rechargeRate > 0.0) {
        flags = flags | RTF_RECHARGES
        this.SetRechargeRate(player, name, rechargeRate)
    }
    
    this.SetFlags(player, name, flags)
}

// ============================================================================
// Initialization
// ============================================================================

printl("=================================================")
printl(" HUD Framework VScript Library Loaded")
printl(" Version: " + HUDFramework.version)
printl(" Ported from SourcePawn to VScript for Mapbase")
printl("=================================================")
