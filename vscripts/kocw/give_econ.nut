// ============================================================================
// Give Econ - Dynamic Weapon & Attribute Management
// ============================================================================
// Port of give_econ.sp for VScript
// Allows admins to give weapons and apply attributes dynamically

// Developer Steam IDs (authorized users)
// NEED TO REWORK THIS TO USE STEAMID3 FORMAT
DEV_LIST <- [
    "76561198069525597", // clue
    "76561198124781832", // vror (mentioned)
    "76561197973074856", // reagy
    "76561198045208572", // dan
    "76561198947729988", // daffy
    "76561198149855325", // colrot
    "76561198031608022", // kibbleknight
    "76561198071599417", // haau
    "76561198071732989", // majro
    "[U:1:342305250]", // gabe
    "76561198167640066", // wonders
    "76561198038214360", // negative_chill
    "76561198014234943", // fluffypaws
    "76561197993638233", // trotim
    "76561198825918211", // azzy
    "76561198082886322"  // panacek (for the funny)
];

// Per-player weapon tracking: playerIdx -> [weapon handles]
_playerWeapons <- {};

// Per-player loadout saving: playerIdx -> [{weaponIdentifier, slot}]
_playerLoadouts <- {};

// ============================================================================
// Initialization
// ============================================================================

function Initialize() {
    printl("[KOCW] Give Econ system initialized");
}

// ============================================================================
// Authorization
// ============================================================================

function IsPlayerAdmin(player) {
    if (!player || !player.IsValid()) return false;
    
    local steamID = player.GetNetworkIDString();
    
    foreach (devID in DEV_LIST) {
        if (steamID == devID) {
            return true;
        }
    }
    
    return false;
}

function CanPlayerUseWeapon(player, weaponIdentifier) {
    if (!player || !player.IsValid()) return false;
    
    // Check if it's an item ID that's restricted
    try {
        local itemID = weaponIdentifier.tointeger();
        
        if (itemID in _adminRestrictedWeapons) {
            local steamID = player.GetNetworkIDString();
            local allowedIDs = _adminRestrictedWeapons[itemID];
            
            // Check if player's Steam ID is in the allowed list
            foreach (allowedID in allowedIDs) {
                if (steamID == allowedID) {
                    return true;
                }
            }
            
            // Not in allowed list
            return false;
        }
    } catch (e) {
        // Not a number, not restricted
    }
    
    // Not restricted, anyone can use
    return true;
}

// ============================================================================
// Weapon Management
// ============================================================================

// Helper: Find player by name or index
function FindPlayer(identifier) {
    // Try as entity index first
    try {
        local idx = identifier.tointeger();
        local player = PlayerInstanceFromIndex(idx);
        if (player && player.IsValid()) {
            return player;
        }
    } catch (e) {
        // Not a number, try as name
    }
    
    // Search by name (partial match, case-insensitive)
    local searchName = identifier.tolower();
    local ent = null;
    while (ent = Entities.FindByClassname(ent, "player")) {
        if (ent && ent.IsValid()) {
            local playerName = ent.GetPlayerName().tolower();
            if (playerName.find(searchName) != null) {
                return ent;
            }
        }
    }
    
    return null;
}

// Item ID to classname mapping for common weapons
// Add more as needed
_itemIDToClass <- {
    // Scout
    [0] = "tf_weapon_bat",
    [13] = "tf_weapon_scattergun",
    [23] = "tf_weapon_pistol",
    [200] = "tf2c_weapon_nailgun",
    [201] = "tf2c_weapon_brick",
    
    // Soldier
    [6] = "tf_weapon_shovel",
    [10] = "tf_weapon_shotgun",
    [18] = "tf_weapon_rocketlauncher",
    [133] = "tf_wearable",
    [202] = "tf_weapon_rocketlauncher",
    [203] = "tf2c_weapon_anchor",
    
    // Pyro
    [2] = "tf_weapon_fireaxe",
    [12] = "tf_weapon_shotgun",
    [21] = "tf_weapon_flamethrower",
    [39] = "tf_weapon_flaregun",
    [204] = "tf2c_weapon_doubleshotgun",
    [206] = "tf2c_weapon_scythe",
    
    // Demoman
    [1] = "tf_weapon_bottle",
    [19] = "tf_weapon_grenade_launcher",
    [20] = "tf_weapon_pipebomblauncher",
    [213] = "tf_weapon_pipebomblauncher",
    [310] = "tf_weapon_grenade_mirv",
    [299] = "tf_wearable",
    [311] = "tf2c_weapon_cyclops",
    
    // Heavy
    [5] = "tf_weapon_fists",
    [11] = "tf_weapon_shotgun",
    [15] = "tf_weapon_minigun",
    [42] = "tf_weapon_lunchbox",
    [207] = "tf2c_weapon_aagun",
    [208] = "tf2c_weapon_chains",
    
    // Engineer
    [9] = "tf_weapon_shotgun",
    [7] = "tf_weapon_wrench",
    [22] = "tf_weapon_pistol",
    [25] = "tf_weapon_pda_engineer_build",
    [26] = "tf_weapon_pda_engineer_destroy",
    [204] = "tf_weapon_pda_engineer_build",
    [301] = "tf2c_weapon_coilgun",
    
    // Medic
    [8] = "tf_weapon_bonesaw",
    [17] = "tf_weapon_syringegun",
    [29] = "tf_weapon_medigun",
    [35] = "tf_weapon_medigun",
    [37] = "tf_weapon_bonesaw",
    [314] = "tf2c_weapon_taser",
    [315] = "tf2c_weapon_heallauncher",
    
    // Sniper
    [3] = "tf_weapon_club",
    [14] = "tf_weapon_sniperrifle",
    [16] = "tf_weapon_smg",
    [56] = "tf_weapon_compound_bow",
    [212] = "tf_weapon_club",
    [313] = "tf2c_weapon_hunting_revolver",
    
    // Spy
    [4] = "tf_weapon_knife",
    [24] = "tf_weapon_revolver",
    [27] = "tf_weapon_pda_spy",
    [210] = "tf2c_weapon_tranq",
    [30] = "tf_weapon_invis",
    [735] = "tf_weapon_sapper",
    [209] = "tf_weapon_invis",

    //Civilian
    [300] = "tf2c_weapon_umbrella",
    [312] = "tf2c_weapon_umbrella",

    //Admin Weapons
    [510] = "tf_weapon_minigun", //Gaben's Weapon
}

// Admin-restricted weapons: itemID -> [allowed Steam IDs]
// Only these specific Steam IDs can receive or give these weapons
_adminRestrictedWeapons <- {
    [510] = ["[U:1:342305250]"], // Gaben's Weapon
    [511] = ["[U:1:207374338]"], // Wonder's Weapon
}

function GiveWeapon(player, weaponIdentifier, weaponSlot = -1, saveToLoadout = true) {
    if (!player || !player.IsValid()) {
        return null;
    }
    
    // Check if player is allowed to use this weapon
    if (!CanPlayerUseWeapon(player, weaponIdentifier)) {
        printl("[KOCW] Player " + player.GetPlayerName() + " not authorized for weapon: " + weaponIdentifier);
        return null;
    }
    
    try {
        // If weapon slot specified, remove existing weapon in that slot first
        if (weaponSlot >= 0) {
            local existingWeapon = player.GetWeaponInSlot(weaponSlot);
            if (existingWeapon && existingWeapon.IsValid()) {
                existingWeapon.Kill();
            }
        }
        
        local weapon = null;
        local isItemID = false;
        local itemID = -1;
        local weaponClass = null;
        
        // Check if identifier is a number (item definition index)
        try {
            itemID = weaponIdentifier.tointeger();
            isItemID = true;
            
            // Look up the weapon class from item ID
            if (itemID in _itemIDToClass) {
                weaponClass = _itemIDToClass[itemID];
            } else {
                // Fallback: try tf_weapon_item or generic class
                weaponClass = "tf_weapon_item";
                printl("[KOCW] Warning: Item ID " + itemID + " not in mapping, using tf_weapon_item");
            }
        } catch (e) {
            // Not a number, treat as classname
            isItemID = false;
            weaponClass = weaponIdentifier;
        }
        
        // Create the weapon using SpawnEntityFromTable (like give_tf_weapon does)
        weapon = SpawnEntityFromTable(weaponClass, {
            origin = player.GetOrigin(),
            angles = player.GetAbsAngles(),
            TeamNum = player.GetTeam(),
            effects = 129,
            CollisionGroup = 11
        });
        
        if (!weapon || !weapon.IsValid()) {
            printl("[KOCW] Failed to create weapon: " + weaponClass);
            return null;
        }
        
        // Set item definition index using netprops (like give_tf_weapon)
        if (isItemID) {
            NetProps.SetPropInt(weapon, "m_AttributeManager.m_Item.m_iItemDefinitionIndex", itemID);
            NetProps.SetPropInt(weapon, "m_AttributeManager.m_Item.m_iEntityLevel", 0);
            NetProps.SetPropBool(weapon, "m_AttributeManager.m_Item.m_bInitialized", true);
        }
        
        // Set weapon properties
        weapon.SetOwner(player);
        
        // Spawn the weapon
        DispatchSpawn(weapon);
        
        // Reapply provision to load schema attributes
        weapon.ReapplyProvision();
        
        // Equip the weapon to the player
        player.Weapon_Equip(weapon);
        
        // Track the weapon
        local playerIdx = player.entindex();
        if (!(playerIdx in _playerWeapons)) {
            _playerWeapons[playerIdx] <- [];
        }
        _playerWeapons[playerIdx].append(weapon);
        
        // Save to loadout for persistence across respawn/resupply (only if not already loading)
        if (saveToLoadout) {
            SaveWeaponToLoadout(player, weaponIdentifier, weaponSlot);
        }
        
        // Switch to the new weapon
        player.Weapon_Switch(weapon);
        
        return weapon;
    } catch (e) {
        printl("[KOCW] Error giving weapon: " + e);
        return null;
    }
}

function RemoveLastWeapon(player) {
    if (!player || !player.IsValid()) {
        return false;
    }
    
    local playerIdx = player.entindex();
    
    if (!(playerIdx in _playerWeapons) || _playerWeapons[playerIdx].len() == 0) {
        return false;
    }
    
    // Get the last weapon
    local weapon = _playerWeapons[playerIdx].pop();
    
    if (weapon && weapon.IsValid()) {
        // Remove it
        weapon.Kill();
        return true;
    }
    
    return false;
}

// ============================================================================
// Loadout Persistence
// ============================================================================

function SaveWeaponToLoadout(player, weaponIdentifier, slot = -1) {
    if (!player || !player.IsValid()) return;
    
    local playerIdx = player.entindex();
    
    if (!(playerIdx in _playerLoadouts)) {
        _playerLoadouts[playerIdx] <- [];
    }
    
    // Check if this weapon is already in the loadout (avoid duplicates)
    foreach (weaponInfo in _playerLoadouts[playerIdx]) {
        if (weaponInfo.identifier == weaponIdentifier && weaponInfo.slot == slot) {
            printl("[KOCW] Weapon already in loadout: " + weaponIdentifier);
            return;
        }
    }
    
    // Store weapon info
    local weaponInfo = {
        identifier = weaponIdentifier,
        slot = slot
    };
    
    _playerLoadouts[playerIdx].append(weaponInfo);
    printl("[KOCW] Saved weapon to loadout: " + weaponIdentifier);
}

function LoadPlayerLoadout(player) {
    if (!player || !player.IsValid()) return;
    
    local playerIdx = player.entindex();
    
    if (!(playerIdx in _playerLoadouts) || _playerLoadouts[playerIdx].len() == 0) return;
    
    // Kill any tracked weapons first to prevent duplicates
    if (playerIdx in _playerWeapons) {
        foreach (weapon in _playerWeapons[playerIdx]) {
            if (weapon && weapon.IsValid()) {
                weapon.Kill();
            }
        }
        delete _playerWeapons[playerIdx];
    }
    
    // Restore all saved weapons (pass false to avoid re-saving to loadout)
    foreach (weaponInfo in _playerLoadouts[playerIdx]) {
        GiveWeapon(player, weaponInfo.identifier, weaponInfo.slot, false);
    }
    
    printl("[KOCW] Restored " + _playerLoadouts[playerIdx].len() + " weapons for player");
}

function ClearPlayerLoadout(player) {
    if (!player || !player.IsValid()) return;
    
    local playerIdx = player.entindex();
    
    // Kill all tracked weapons first
    if (playerIdx in _playerWeapons) {
        foreach (weapon in _playerWeapons[playerIdx]) {
            if (weapon && weapon.IsValid()) {
                weapon.Kill();
            }
        }
        delete _playerWeapons[playerIdx];
    }
    
    // Clear the saved loadout
    if (playerIdx in _playerLoadouts) {
        delete _playerLoadouts[playerIdx];
        printl("[KOCW] Cleared loadout for player");
    }
    
    // Remove all weapons from player
    for (local slot = 0; slot < 8; slot++) {
        local weapon = NetProps.GetPropEntityArray(player, "m_hMyWeapons", slot);
        if (weapon && weapon.IsValid()) {
            weapon.Kill();
        }
    }
    
    // Regenerate player's loadout (true = respawn, false = just regenerate)
    player.Regenerate(false);
}

function AddAttributeToWeapon(weapon, attributeName, value, duration = -1) {
    if (!weapon || !weapon.IsValid()) {
        return false;
    }
    
    try {
        weapon.AddAttribute(attributeName, value, duration);
        weapon.ReapplyProvision();
        return true;
    } catch (e) {
        printl("[KOCW] Failed to add attribute: " + e);
        return false;
    }
}

function RemoveAttributeFromWeapon(weapon, attributeName) {
    if (!weapon || !weapon.IsValid()) {
        return false;
    }
    
    try {
        weapon.RemoveAttribute(attributeName);
        weapon.ReapplyProvision();
        return true;
    } catch (e) {
        printl("[KOCW] Failed to remove attribute: " + e);
        return false;
    }
}

// ============================================================================
// Event Handlers
// ============================================================================

function OnPlayerDisconnect(player) {
    if (!player) return;
    
    local playerIdx = player.entindex();
    
    // Clear tracking for this player
    if (playerIdx in _playerWeapons) {
        delete _playerWeapons[playerIdx];
    }
    
    // Clear loadout for this player
    if (playerIdx in _playerLoadouts) {
        delete _playerLoadouts[playerIdx];
    }
}

function OnPlayerSpawn(player) {
    if (!player) return;
    
    local playerIdx = player.entindex();
    
    // Clear weapon tracking on spawn (weapons are removed by game)
    if (playerIdx in _playerWeapons) {
        delete _playerWeapons[playerIdx];
    }
    
    // Restore saved loadout after a short delay
    // (need to wait for game to give default weapons first)
    EntFireByHandle(player, "RunScriptCode", "LoadPlayerLoadout(self)", 0.1, null, player);
}

function OnPlayerResupply(player) {
    if (!player) return;
    
    local playerIdx = player.entindex();
    
    // Clear weapon tracking (weapons are removed by resupply)
    if (playerIdx in _playerWeapons) {
        delete _playerWeapons[playerIdx];
    }
    
    // Restore saved loadout after a short delay
    EntFireByHandle(player, "RunScriptCode", "LoadPlayerLoadout(self)", 0.1, null, player);
}

// ============================================================================
// Chat Command Handler (used by vscript_server.nut player_say event)
// ============================================================================
// Commands: !giveweapon, !addattr, !removeattr, !removeweapon
// Returns true if message should be hidden from chat

// Helper: Parse arguments respecting quotes
function ParseArgs(text) {
    local args = [];
    local current = "";
    local inQuote = false;
    local quoteChar = null;
    
    for (local i = 0; i < text.len(); i++) {
        local c = text[i].tochar();
        
        if (!inQuote && (c == "'" || c == "\"")) {
            inQuote = true;
            quoteChar = c;
        } else if (inQuote && c == quoteChar) {
            inQuote = false;
            quoteChar = null;
        } else if (!inQuote && c == " ") {
            if (current.len() > 0) {
                args.append(current);
                current = "";
            }
        } else {
            current += c;
        }
    }
    
    if (current.len() > 0) {
        args.append(current);
    }
    
    return args;
}

function OnPlayerSayGiveEcon(player, text) {
    local args = ParseArgs(text);
    if (args.len() == 0) return false;
    
    local command = args[0].tolower();
    
    // Check if it's one of our commands
    if (command != "!giveweapon" && command != "!addattr" && 
        command != "!removeattr" && command != "!removeweapon" && 
        command != "!clearloadout") {
        return false;
    }
    
    // Check admin permission
    if (!IsPlayerAdmin(player)) {
        ClientPrint(player, 3, "\x07FF3333[KOCW]\x01 You are not authorized");
        return true;
    }
    
    // Handle !giveweapon <classname|itemID> [target] [slot]
    if (command == "!giveweapon") {
        if (args.len() < 2) {
            ClientPrint(player, 3, "\x07FFAA33[KOCW]\x01 Usage: !giveweapon <classname|itemID> [target] [slot]");
            ClientPrint(player, 3, "\x07FFAA33[KOCW]\x01 Example: !giveweapon tf_weapon_rocketlauncher");
            ClientPrint(player, 3, "\x07FFAA33[KOCW]\x01 Example: !giveweapon 210 Gaben");
            ClientPrint(player, 3, "\x07FFAA33[KOCW]\x01 Example: !giveweapon tf_weapon_shotgun Gaben 1");
            return true;
        }
        
        try {
            local targetPlayer = player;
            local weaponSlot = -1;
            
            // Check if target player specified
            if (args.len() >= 3) {
                targetPlayer = FindPlayer(args[2]);
                if (!targetPlayer) {
                    ClientPrint(player, 3, "\x07FF3333[KOCW]\x01 Player not found: " + args[2]);
                    return true;
                }
            }
            
            // Check if weapon slot specified
            if (args.len() >= 4) {
                try {
                    weaponSlot = args[3].tointeger();
                } catch (e) {
                    ClientPrint(player, 3, "\x07FF3333[KOCW]\x01 Invalid slot number");
                    return true;
                }
            }
            
            // Check if target player can use this weapon
            if (!CanPlayerUseWeapon(targetPlayer, args[1])) {
                local targetName = targetPlayer.GetPlayerName();
                ClientPrint(player, 3, "\x07FF3333[KOCW]\x01 " + targetName + " is not authorized for this weapon");
                return true;
            }
            
            local weapon = GiveWeapon(targetPlayer, args[1], weaponSlot);
            if (weapon) {
                local targetName = targetPlayer.GetPlayerName();
                if (targetPlayer == player) {
                    ClientPrint(player, 3, "\x0799FF99[KOCW]\x01 Gave weapon: " + args[1]);
                } else {
                    ClientPrint(player, 3, "\x0799FF99[KOCW]\x01 Gave " + args[1] + " to " + targetName);
                    ClientPrint(targetPlayer, 3, "\x0799FF99[KOCW]\x01 You received: " + args[1]);
                }
            } else {
                ClientPrint(player, 3, "\x07FF3333[KOCW]\x01 Failed to give weapon");
            }
        } catch (ex) {
            ClientPrint(player, 3, "\x07FF3333[KOCW]\x01 Failed: " + ex);
        }
        return true;
    }
    
    // Handle !addattr <name> <value1> [value2] [value3] ... [target]
    // Multiple values will be combined into a space-separated string
    if (command == "!addattr") {
        if (args.len() < 3) {
            ClientPrint(player, 3, "\x07FFAA33[KOCW]\x01 Usage: !addattr 'attribute' <value1> [value2] [value3] ... [target]");
            ClientPrint(player, 3, "\x07FFAA33[KOCW]\x01 Example: !addattr 'fire rate bonus' 0.5");
            ClientPrint(player, 3, "\x07FFAA33[KOCW]\x01 Example: !addattr 'damage bonus' 2.0 Gaben");
            ClientPrint(player, 3, "\x07FFAA33[KOCW]\x01 Example: !addattr 'custom attribute' 192.0 0.0 4.5");
            return true;
        }
        
        local targetPlayer = player;
        local attrName = args[1];
        local values = [];
        local targetArgIndex = -1;
        
        // Collect all numeric values starting from args[2]
        // Stop when we hit a non-numeric value (potential player name)
        for (local i = 2; i < args.len(); i++) {
            try {
                local val = args[i].tofloat();
                values.append(val);
            } catch (e) {
                // Not a number, assume it's a player name
                targetArgIndex = i;
                break;
            }
        }
        
        // If we found no values, show error
        if (values.len() == 0) {
            ClientPrint(player, 3, "\x07FF3333[KOCW]\x01 No valid numeric values provided");
            return true;
        }
        
        // Check if a target player was specified
        if (targetArgIndex != -1) {
            targetPlayer = FindPlayer(args[targetArgIndex]);
            if (!targetPlayer) {
                ClientPrint(player, 3, "\x07FF3333[KOCW]\x01 Player not found: " + args[targetArgIndex]);
                return true;
            }
        }
        
        // Get the player's currently active weapon
        local weapon = targetPlayer.GetActiveWeapon();
        if (!weapon || !weapon.IsValid()) {
            local targetName = targetPlayer.GetPlayerName();
            ClientPrint(player, 3, "\x07FF3333[KOCW]\x01 " + targetName + " has no active weapon");
            return true;
        }
        
        try {
            // Apply each value separately as a float
            local valueStr = "";
            
            if (values.len() > 1) {
                // Multiple values: apply each one
                foreach (idx, val in values) {
                    AddAttributeToWeapon(weapon, attrName, val, -1);
                    valueStr += val;
                    if (idx < values.len() - 1) valueStr += " ";
                }
            } else {
                // Single value
                AddAttributeToWeapon(weapon, attrName, values[0], -1);
                valueStr = values[0].tostring();
            }
            
            local targetName = targetPlayer.GetPlayerName();
            if (targetPlayer == player) {
                ClientPrint(player, 3, "\x0799FF99[KOCW]\x01 Added: " + attrName + " = " + valueStr);
            } else {
                ClientPrint(player, 3, "\x0799FF99[KOCW]\x01 Added " + attrName + " to " + targetName + "'s weapon");
                ClientPrint(targetPlayer, 3, "\x0799FF99[KOCW]\x01 Attribute added: " + attrName + " = " + valueStr);
            }
        } catch (ex) {
            ClientPrint(player, 3, "\x07FF3333[KOCW]\x01 Failed: " + ex);
        }
        return true;
    }
    
    // Handle !removeattr <name> [target]
    if (command == "!removeattr") {
        if (args.len() < 2) {
            ClientPrint(player, 3, "\x07FFAA33[KOCW]\x01 Usage: !removeattr 'attribute' [target]");
            return true;
        }
        
        local targetPlayer = player;
        
        // Check if target player specified
        if (args.len() >= 3) {
            targetPlayer = FindPlayer(args[2]);
            if (!targetPlayer) {
                ClientPrint(player, 3, "\x07FF3333[KOCW]\x01 Player not found: " + args[2]);
                return true;
            }
        }
        
        // Get the player's currently active weapon
        local weapon = targetPlayer.GetActiveWeapon();
        if (!weapon || !weapon.IsValid()) {
            local targetName = targetPlayer.GetPlayerName();
            ClientPrint(player, 3, "\x07FF3333[KOCW]\x01 " + targetName + " has no active weapon");
            return true;
        }
        
        try {
            RemoveAttributeFromWeapon(weapon, args[1]);
            local targetName = targetPlayer.GetPlayerName();
            if (targetPlayer == player) {
                ClientPrint(player, 3, "\x0799FF99[KOCW]\x01 Removed: " + args[1]);
            } else {
                ClientPrint(player, 3, "\x0799FF99[KOCW]\x01 Removed " + args[1] + " from " + targetName + "'s weapon");
                ClientPrint(targetPlayer, 3, "\x0799FF99[KOCW]\x01 Attribute removed: " + args[1]);
            }
        } catch (ex) {
            ClientPrint(player, 3, "\x07FF3333[KOCW]\x01 Failed: " + ex);
        }
        return true;
    }
    
    // Handle !removeweapon [target]
    if (command == "!removeweapon") {
        local targetPlayer = player;
        
        // Check if target player specified
        if (args.len() >= 2) {
            targetPlayer = FindPlayer(args[1]);
            if (!targetPlayer) {
                ClientPrint(player, 3, "\x07FF3333[KOCW]\x01 Player not found: " + args[1]);
                return true;
            }
        }
        
        try {
            RemoveLastWeapon(targetPlayer);
            local targetName = targetPlayer.GetPlayerName();
            if (targetPlayer == player) {
                ClientPrint(player, 3, "\x0799FF99[KOCW]\x01 Removed last weapon");
            } else {
                ClientPrint(player, 3, "\x0799FF99[KOCW]\x01 Removed weapon from " + targetName);
                ClientPrint(targetPlayer, 3, "\x0799FF99[KOCW]\x01 Your last weapon was removed");
            }
        } catch (ex) {
            ClientPrint(player, 3, "\x07FF3333[KOCW]\x01 Failed: " + ex);
        }
        return true;
    }
    
    // Handle !clearloadout [target]
    if (command == "!clearloadout") {
        local targetPlayer = player;
        
        // Check if target player specified
        if (args.len() >= 2) {
            targetPlayer = FindPlayer(args[1]);
            if (!targetPlayer) {
                ClientPrint(player, 3, "\x07FF3333[KOCW]\x01 Player not found: " + args[1]);
                return true;
            }
        }
        
        try {
            ClearPlayerLoadout(targetPlayer);
            local targetName = targetPlayer.GetPlayerName();
            if (targetPlayer == player) {
                ClientPrint(player, 3, "\x0799FF99[KOCW]\x01 Cleared your saved loadout");
            } else {
                ClientPrint(player, 3, "\x0799FF99[KOCW]\x01 Cleared loadout for " + targetName);
                ClientPrint(targetPlayer, 3, "\x0799FF99[KOCW]\x01 Your saved loadout was cleared");
            }
        } catch (ex) {
            ClientPrint(player, 3, "\x07FF3333[KOCW]\x01 Failed: " + ex);
        }
        return true;
    }
    
    return false;
}

// ============================================================================
// Public API (for other scripts to use)
// ============================================================================

// These functions can be called from other scripts using GiveEcon::FunctionName()
::GiveEcon <- {
    // Give a weapon to a player
    GiveWeapon = function(player, weaponClassname) {
        return ::GiveWeapon(player, weaponClassname);
    }
    
    // Add an attribute to a weapon
    AddAttribute = function(weapon, attributeName, value, duration = -1) {
        return ::AddAttributeToWeapon(weapon, attributeName, value, duration);
    }
    
    // Remove an attribute from a weapon
    RemoveAttribute = function(weapon, attributeName) {
        return ::RemoveAttributeFromWeapon(weapon, attributeName);
    }
    
    // Check if a player is an admin
    IsAdmin = function(player) {
        return ::IsPlayerAdmin(player);
    }
    
    // Event handlers
    OnPlayerDisconnect = function(player) {
        return ::OnPlayerDisconnect(player);
    }
    
    OnPlayerSpawn = function(player) {
        return ::OnPlayerSpawn(player);
    }
    
    OnPlayerResupply = function(player) {
        return ::OnPlayerResupply(player);
    }
    
    // Loadout management
    SaveWeaponToLoadout = function(player, weaponIdentifier, slot = -1) {
        return ::SaveWeaponToLoadout(player, weaponIdentifier, slot);
    }
    
    LoadPlayerLoadout = function(player) {
        return ::LoadPlayerLoadout(player);
    }
    
    ClearPlayerLoadout = function(player) {
        return ::ClearPlayerLoadout(player);
    }
}

// ============================================================================
// Auto-initialize
// ============================================================================
if (!("_giveEconInitialized" in getroottable())) {
    _giveEconInitialized <- true;
    Initialize();
}
