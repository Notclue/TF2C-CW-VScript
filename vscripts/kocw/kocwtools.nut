//=============================================================================
//
// KOCW Tools - VScript Edition
// Purpose: Standard utility functions for custom weapons and gameplay mechanics
// Ported from SourcePawn to Mapbase VScript
//
//=============================================================================

// Global constants for damage flags
const DMG_GENERIC = 0;
const DMG_CRUSH = 1;
const DMG_BULLET = 2;
const DMG_SLASH = 4;
const DMG_BURN = 8;
const DMG_VEHICLE = 16;
const DMG_FALL = 32;
const DMG_BLAST = 64;
const DMG_CLUB = 128;
const DMG_SHOCK = 256;
const DMG_SONIC = 512;
const DMG_ENERGYBEAM = 1024;
const DMG_PREVENT_PHYSICS_FORCE = 2048;
const DMG_NEVERGIB = 4096;
const DMG_ALWAYSGIB = 8192;
const DMG_DROWN = 16384;
const DMG_PARALYZE = 32768;
const DMG_NERVEGAS = 65536;
const DMG_POISON = 131072;
const DMG_RADIATION = 262144;
const DMG_DROWNRECOVER = 524288;
const DMG_ACID = 1048576;
const DMG_SLOWBURN = 2097152;
const DMG_REMOVENORAGDOLL = 4194304;
const DMG_PHYSGUN = 8388608;
const DMG_PLASMA = 16777216;
const DMG_AIRBOAT = 33554432;
const DMG_DISSOLVE = 67108864;
const DMG_BLAST_SURFACE = 134217728;
const DMG_DIRECT = 268435456;
const DMG_BUCKSHOT = 536870912;

// Heal flags
const HF_NONE = 0;
const HF_NOCRITHEAL = 1;
const HF_NOOVERHEAL = 2;

// Collision groups
const COLLISION_GROUP_NONE = 0;
const COLLISION_GROUP_DEBRIS = 1;
const COLLISION_GROUP_DEBRIS_TRIGGER = 2;
const COLLISION_GROUP_INTERACTIVE_DEBRIS = 3;
const COLLISION_GROUP_INTERACTIVE = 4;
const COLLISION_GROUP_PLAYER = 5;
const COLLISION_GROUP_BREAKABLE_GLASS = 6;
const COLLISION_GROUP_VEHICLE = 7;
const COLLISION_GROUP_PLAYER_MOVEMENT = 8;
const COLLISION_GROUP_NPC = 9;
const COLLISION_GROUP_IN_VEHICLE = 10;
const COLLISION_GROUP_WEAPON = 11;
const COLLISION_GROUP_VEHICLE_CLIP = 12;
const COLLISION_GROUP_PROJECTILE = 13;
const COLLISION_GROUP_DOOR_BLOCKER = 14;
const COLLISION_GROUP_PASSABLE_DOOR = 15;
const COLLISION_GROUP_DISSOLVING = 16;
const COLLISION_GROUP_PUSHAWAY = 17;

// Solid types
const SOLID_NONE = 0;
const SOLID_BSP = 1;
const SOLID_BBOX = 2;
const SOLID_OBB = 3;
const SOLID_OBB_YAW = 4;
const SOLID_CUSTOM = 5;
const SOLID_VPHYSICS = 6;

// Solid flags
const FSOLID_CUSTOMRAYTEST = 0x0001;
const FSOLID_CUSTOMBOXTEST = 0x0002;
const FSOLID_NOT_SOLID = 0x0004;
const FSOLID_TRIGGER = 0x0008;
const FSOLID_NOT_STANDABLE = 0x0010;
const FSOLID_VOLUME_CONTENTS = 0x0020;
const FSOLID_FORCE_WORLD_ALIGNED = 0x0040;
const FSOLID_USE_TRIGGER_BOUNDS = 0x0080;
const FSOLID_ROOT_PARENT_ALIGNED = 0x0100;
const FSOLID_TRIGGER_TOUCH_DEBRIS = 0x0200;

//=============================================================================
// KOCW Tools Namespace
//=============================================================================
::KOCWTools <- {
    // Storage for damage hooks
    _damageHooks = []
    _damageHooksPost = []
    
    // Storage for healers and heal tracking
    _playerHealers = {}
    _healAccumulators = {}
    
    // Lag compensation tracking
    _lagCompensationActive = false
    
    version = "2.0-VScript"
}

//=============================================================================
// Entity Utility Functions
//=============================================================================

// Find entities within a sphere radius
// Returns an array of entities found
// NOTE: This function can be slow with large radius or many entities
function KOCWTools::FindEntitiesInSphere(origin, radius, startEntity = null)
{
    local entities = [];
    
    // Search for specific common entity types to avoid "*" wildcard
    local classnames = ["player", "prop_physics", "prop_dynamic", "npc_*"];
    
    foreach (classname in classnames)
    {
        local ent = null;
        local count = 0;
        
        while ((ent = Entities.FindByClassname(ent, classname)) != null)
        {
            if (ent == startEntity)
                continue;
            
            try {
                local distance = (ent.GetOrigin() - origin).Length();
                if (distance <= radius)
                {
                    entities.append(ent);
                }
            }
            catch (e) {
                // Entity might not have origin
            }
            
            count++;
            // Safety limit per classname
            if (count > 512)
            {
                printl("[KOCWTools WARNING] FindEntitiesInSphere hit limit for " + classname);
                break;
            }
        }
    }
    
    return entities;
}

// Find entities within a sphere by classname
function KOCWTools::FindEntitiesByClassInSphere(classname, origin, radius, startEntity = null)
{
    local entities = [];
    local ent = null;
    
    while ((ent = Entities.FindByClassname(ent, classname)) != null)
    {
        if (ent == startEntity)
            continue;
            
        local distance = (ent.GetOrigin() - origin).Length();
        if (distance <= radius)
        {
            entities.append(ent);
        }
        
        // Safety limit
        if (entities.len() > 2048)
        {
            printl("[KOCWTools WARNING] FindEntitiesByClassInSphere hit entity limit!");
            break;
        }
    }
    
    return entities;
}

// Get entity by index
function KOCWTools::GetEntityByIndex(index)
{
    return EntIndexToHScript(index);
}

//=============================================================================
// Collision and Physics Functions
//=============================================================================

// Set entity collision group
function KOCWTools::SetCollisionGroup(entity, collisionGroup)
{
    if (!entity || !entity.IsValid())
        return false;
    
    NetProps.SetPropInt(entity, "m_CollisionGroup", collisionGroup);
    return true;
}

// Get entity collision group
function KOCWTools::GetCollisionGroup(entity)
{
    if (!entity || !entity.IsValid())
        return COLLISION_GROUP_NONE;
    
    return NetProps.GetPropInt(entity, "m_CollisionGroup");
}

// Set entity solid type
function KOCWTools::SetSolid(entity, solidType)
{
    if (!entity || !entity.IsValid())
        return false;
    
    // Note: Direct solid type manipulation may be limited in VScript
    // This is a best-effort implementation
    entity.SetSolid(solidType);
    return true;
}

// Set entity solid flags
function KOCWTools::SetSolidFlags(entity, flags)
{
    if (!entity || !entity.IsValid())
        return false;
    
    // Store in entity scope for later retrieval
    entity.ValidateScriptScope();
    local scope = entity.GetScriptScope();
    scope._solidFlags <- flags;
    
    return true;
}

// Set entity size (bounding box)
function KOCWTools::SetSize(entity, mins, maxs)
{
    if (!entity || !entity.IsValid())
        return false;
    
    entity.SetSize(mins, maxs);
    return true;
}

//=============================================================================
// Vector and Math Utility Functions
//=============================================================================

// Remap a value from one range to another, clamped
function KOCWTools::RemapValClamped(val, minIn, maxIn, minOut, maxOut)
{
    if (val <= minIn)
        return minOut;
    if (val >= maxIn)
        return maxOut;
    
    local t = (val - minIn) / (maxIn - minIn);
    return minOut + (maxOut - minOut) * t;
}

// Clamp a value between min and max
function KOCWTools::Clamp(val, min, max)
{
    if (val < min)
        return min;
    if (val > max)
        return max;
    return val;
}

// Linear interpolation
function KOCWTools::Lerp(t, a, b)
{
    return a + (b - a) * t;
}

// Get the distance between two vectors
function KOCWTools::VectorDistance(vec1, vec2)
{
    local diff = vec2 - vec1;
    return diff.Length();
}

// Normalize a vector
function KOCWTools::VectorNormalize(vec)
{
    local len = vec.Length();
    if (len > 0.0)
    {
        return Vector(vec.x / len, vec.y / len, vec.z / len);
    }
    return Vector(0, 0, 0);
}

//=============================================================================
// Player and Combat Character Functions
//=============================================================================

// Check if an entity is a valid player
function KOCWTools::IsValidPlayer(entity)
{
    if (!entity || !entity.IsValid())
        return false;
    
    return entity.GetClassname() == "player";
}

// Get player health
function KOCWTools::GetPlayerHealth(player)
{
    if (!KOCWTools.IsValidPlayer(player))
        return 0;
    
    return player.GetHealth();
}

// Get player max health
function KOCWTools::GetPlayerMaxHealth(player)
{
    if (!KOCWTools.IsValidPlayer(player))
        return 0;
    
    return player.GetMaxHealth();
}

// Set player health
function KOCWTools::SetPlayerHealth(player, health)
{
    if (!KOCWTools.IsValidPlayer(player))
        return false;
    
    player.SetHealth(health);
    return true;
}

// Get player armor
function KOCWTools::GetPlayerArmor(player)
{
    if (!KOCWTools.IsValidPlayer(player))
        return 0;
    
    return NetProps.GetPropInt(player, "m_ArmorValue");
}

// Set player armor
function KOCWTools::SetPlayerArmor(player, armor)
{
    if (!KOCWTools.IsValidPlayer(player))
        return false;
    
    NetProps.SetPropInt(player, "m_ArmorValue", armor);
    return true;
}

// Get player's active weapon
function KOCWTools::GetActiveWeapon(player)
{
    if (!KOCWTools.IsValidPlayer(player))
        return null;
    
    return NetProps.GetPropEntity(player, "m_hActiveWeapon");
}

// Get weapon in specific slot
function KOCWTools::GetWeaponInSlot(player, slot)
{
    if (!KOCWTools.IsValidPlayer(player))
        return null;
    
    // This may need to be adapted based on the game's weapon system
    return NetProps.GetPropEntityArray(player, "m_hMyWeapons", slot);
}

// Get player's team
function KOCWTools::GetPlayerTeam(player)
{
    if (!player || !player.IsValid())
        return 0;
    
    return player.GetTeam();
}

// Set player's team
function KOCWTools::SetPlayerTeam(player, team)
{
    if (!player || !player.IsValid())
        return false;
    
    player.SetTeam(team);
    return true;
}

//=============================================================================
// Weapon Functions
//=============================================================================

// Get weapon clip ammo
function KOCWTools::GetWeaponClip(weapon)
{
    if (!weapon || !weapon.IsValid())
        return 0;
    
    return NetProps.GetPropInt(weapon, "m_iClip1");
}

// Set weapon clip ammo
function KOCWTools::SetWeaponClip(weapon, ammo)
{
    if (!weapon || !weapon.IsValid())
        return false;
    
    NetProps.SetPropInt(weapon, "m_iClip1", ammo);
    return true;
}

// Get weapon owner
function KOCWTools::GetWeaponOwner(weapon)
{
    if (!weapon || !weapon.IsValid())
        return null;
    
    return NetProps.GetPropEntity(weapon, "m_hOwner");
}

//=============================================================================
// Damage System Functions
//=============================================================================

// Register a damage hook
// callback signature: function(victim, attacker, inflictor, damage, damageType)
// Should return modified damage value or null to use original
function KOCWTools::AddDamageHook(callback)
{
    _damageHooks.append(callback);
}

// Register a post-damage hook (after damage is applied)
function KOCWTools::AddDamageHookPost(callback)
{
    _damageHooksPost.append(callback);
}

// Apply damage to an entity
function KOCWTools::DealDamage(victim, damage, attacker = null, inflictor = null, damageType = DMG_GENERIC)
{
    if (!victim || !victim.IsValid())
        return 0;
    
    // Process damage hooks
    local modifiedDamage = damage;
    foreach (hook in _damageHooks)
    {
        local result = hook(victim, attacker, inflictor, modifiedDamage, damageType);
        if (result != null)
            modifiedDamage = result;
    }
    
    // Apply damage
    if (modifiedDamage > 0)
    {
        victim.TakeDamage(modifiedDamage, damageType, attacker);
    }
    
    // Process post-damage hooks
    foreach (hook in _damageHooksPost)
    {
        hook(victim, attacker, inflictor, modifiedDamage, damageType);
    }
    
    return modifiedDamage;
}

// Apply knockback/push from damage
function KOCWTools::ApplyPushFromDamage(victim, direction, force)
{
    if (!victim || !victim.IsValid())
        return false;
    
    local normalized = KOCWTools.VectorNormalize(direction);
    local velocity = Vector(
        normalized.x * force,
        normalized.y * force,
        normalized.z * force
    );
    
    // Apply velocity to entity
    victim.ApplyAbsVelocityImpulse(velocity);
    return true;
}

//=============================================================================
// Healing System Functions
//=============================================================================

// Initialize player heal tracking
function KOCWTools::_InitPlayerHealTracking(player)
{
    local playerIdx = player.entindex().tostring();
    
    if (!(playerIdx in _healAccumulators))
        _healAccumulators[playerIdx] <- 0.0;
    
    if (!(playerIdx in _playerHealers))
        _playerHealers[playerIdx] <- [];
}

// Heal a player with optional flags
function KOCWTools::HealPlayer(player, amount, healer = null, flags = HF_NONE)
{
    if (!KOCWTools.IsValidPlayer(player))
        return 0;
    
    KOCWTools._InitPlayerHealTracking(player);
    local playerIdx = player.entindex().tostring();
    
    local maxHealth = player.GetMaxHealth();
    local currentHealth = player.GetHealth();
    
    // Calculate overheal multiplier (default 1.5x)
    local overhealMult = 1.5;
    local buffedMax = maxHealth * overhealMult;
    local buffedMaxRounded = (buffedMax / 5.0).tointeger() * 5;
    
    local healAmount = amount;
    
    // Apply crit heal bonus based on time since last damage
    if (!(flags & HF_NOCRITHEAL))
    {
        // This would need access to last damage time
        // For now, use a simplified version
        healAmount *= 1.5; // Could be 1.0 to 3.0 based on time
    }
    
    // Add to accumulator for fractional healing
    _healAccumulators[playerIdx] = _healAccumulators[playerIdx] + healAmount;
    local healRounded = _healAccumulators[playerIdx].tointeger();
    _healAccumulators[playerIdx] = _healAccumulators[playerIdx] - healRounded;
    
    // Calculate actual heal amount
    local maxAllowedHeal = buffedMaxRounded - currentHealth;
    if (flags & HF_NOOVERHEAL)
        maxAllowedHeal = maxHealth - currentHealth;
    
    healRounded = (healRounded < maxAllowedHeal) ? healRounded : maxAllowedHeal;
    
    if (healRounded > 0)
    {
        player.SetHealth(currentHealth + healRounded);
    }
    
    return healRounded;
}

// Add a continuous healer to a player
function KOCWTools::AddPlayerHealer(receiver, healer, healRate)
{
    if (!KOCWTools.IsValidPlayer(receiver) || !KOCWTools.IsValidPlayer(healer))
        return false;
    
    KOCWTools._InitPlayerHealTracking(receiver);
    local playerIdx = receiver.entindex().tostring();
    
    local healerData = {
        healer = healer,
        rate = healRate,
        startTime = Time()
    };
    
    _playerHealers[playerIdx].append(healerData);
    return true;
}

// Remove a healer from a player
function KOCWTools::RemovePlayerHealer(receiver, healer)
{
    if (!KOCWTools.IsValidPlayer(receiver))
        return false;
    
    local playerIdx = receiver.entindex().tostring();
    
    if (!(playerIdx in _playerHealers))
        return false;
    
    local healers = _playerHealers[playerIdx];
    for (local i = healers.len() - 1; i >= 0; i--)
    {
        if (healers[i].healer == healer)
        {
            healers.remove(i);
            return true;
        }
    }
    
    return false;
}

// Process all active healers (should be called regularly, e.g., in Think)
function KOCWTools::ProcessHealers(deltaTime)
{
    // Iterate over all entries in the healers table
    foreach (playerIdxStr, healers in _playerHealers)
    {
        // Skip if no healers for this player
        if (healers.len() == 0)
            continue;
        
        // Convert string index back to integer and get player entity
        local playerIdx = playerIdxStr.tointeger();
        local player = null;
        
        try {
            player = EntIndexToHScript(playerIdx);
        }
        catch (e) {
            continue;
        }
        
        if (!player || !player.IsValid())
            continue;
        
        // Process each healer for this player
        foreach (healerData in healers)
        {
            if (healerData.healer && healerData.healer.IsValid())
            {
                local healAmount = healerData.rate * deltaTime;
                KOCWTools.HealPlayer(player, healAmount, healerData.healer, HF_NOCRITHEAL);
            }
        }
    }
}

//=============================================================================
// Think/Timer Functions
//=============================================================================

// Schedule a function to be called after a delay
function KOCWTools::ScheduleThink(entity, thinkFunc, delay, context = "")
{
    if (!entity || !entity.IsValid())
        return false;
    
    entity.ValidateScriptScope();
    local scope = entity.GetScriptScope();
    
    local thinkName = context != "" ? context : "KOCWThink_" + Time();
    scope[thinkName] <- thinkFunc;
    
    // Set up think function
    entity.SetThink(thinkFunc, thinkName, delay);
    
    return true;
}

//=============================================================================
// Lag Compensation Functions
//=============================================================================

// Start lag compensation for a player
function KOCWTools::StartLagCompensation(player)
{
    if (!KOCWTools.IsValidPlayer(player))
        return false;
    
    // I have no fucking idea how to do true lag compensation in VScript
    // So uh... this is a placeholder for the concept
    _lagCompensationActive = true;
    
    return true;
}

// End lag compensation for a player
function KOCWTools::FinishLagCompensation(player)
{
    if (!KOCWTools.IsValidPlayer(player))
        return false;
    
    _lagCompensationActive = false;
    
    return true;
}

//=============================================================================
// Utility Functions
//=============================================================================

// Print debug message
function KOCWTools::DebugPrint(message)
{
    printl("[KOCWTools] " + message);
}

// Print warning message
function KOCWTools::DebugWarning(message)
{
    printl("[KOCWTools WARNING] " + message);
}

// Print error message
function KOCWTools::DebugError(message)
{
    printl("[KOCWTools ERROR] " + message);
}

// Check if a trace hits something
function KOCWTools::TraceLine(start, end, ignore = null)
{
    local traceTable = {
        start = start,
        end = end,
        ignore = ignore,
        mask = MASK_SOLID
    };
    
    if (TraceLineEx(traceTable))
    {
        return {
            hit = traceTable.hit,
            pos = traceTable.pos,
            normal = traceTable.normal,
            entity = traceTable.enthit,
            fraction = traceTable.fraction
        };
    }
    
    return null;
}

// Get a random float between min and max
function KOCWTools::RandomFloat(min, max)
{
    return min + (max - min) * RandomFloat(0.0, 1.0);
}

// Get a random integer between min and max (inclusive)
function KOCWTools::RandomInt(min, max)
{
    return RandomInt(min, max);
}

//=============================================================================
// Initialization
//=============================================================================

printl("=================================================");
printl(" KOCWTools VScript Library Loaded");
printl(" Version: " + KOCWTools.version);
printl(" Ported from SourcePawn to VScript for Mapbase");
printl("=================================================");
