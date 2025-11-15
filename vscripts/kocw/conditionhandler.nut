// ============================================================================
// Condition Handler - Custom Player Conditions
// ============================================================================
// Port of conditionhandler.sp for VScript
// Manages custom conditions like Toxin, Angel Shield, Hydro Uber, etc.

// ============================================================================
// Condition Constants
// ============================================================================

const TFCC_TOXIN = 0;
const TFCC_HYDROPUMPHEAL = 1;
const TFCC_HYDROUBER = 2;
const TFCC_ANGELSHIELD = 3;
const TFCC_ANGELINVULN = 4;
const TFCC_TOXINUBER = 5;
const TFCC_LAST = 6;

// ============================================================================
// Configuration Constants
// ============================================================================

// Toxin
const TOXIN_FREQUENCY = 0.5;      // Tick interval in seconds
const TOXIN_DAMAGE = 2.0;         // Damage per tick
const TOXIN_HEALING_MULT = 0.25;  // Healing multiplier while under toxin
const TOXIN_DEFAULT_DURATION = 10.0; // Default duration when none specified
const TOXIN_SOUND = "items/powerup_pickup_plague_infected_loop.wav";
const TOXIN_PARTICLE = "toxin_particles";

// Angel Shield
const ANGEL_SHIELD_HEALTH = 80;
const ANGEL_SHIELD_DURATION = 8.0;
const ANGEL_INVULN_DURATION = 0.25;

// Hydro Uber
const HYDRO_UBER_HEAL_RATE = 36.0;
const HYDRO_UBER_DURATION = 12.0;
const HYDRO_UBER_RANGE = 540.0;
const HYDRO_UBER_FREQUENCY = 0.2;
const HYDRO_UBER_SOUND = "weapons/HPump_Uber.wav";

// Toxin Uber
const TOXIN_UBER_PULSE_RATE = 0.5;
const TOXIN_UBER_RANGE = 300.0;

// ============================================================================
// Global State
// ============================================================================

// Per-player condition data: playerIdx -> { condType -> { props } }
_playerConditions <- {};

// Particle/entity references
_toxinEmitters <- {};
_angelShields <- {};        // playerIdx -> shield entity
_toxinUberEmitters <- {};
_hydroUberEmitters <- {};

// Shield state
_shieldExpireTimes <- {};
_lastDamagedShield <- {};

// Toxin healing reduction tracking
_lastPlayerHealth <- {}; // Track last health for healing reduction

// Angel Shield damage tracking
_lastShieldCheckHealth <- {}; // Track health for shield damage detection

// ============================================================================
// Initialization
// ============================================================================

function Initialize() {
    printl("[ConditionHandler] System initialized");
    
    // Precache sounds and particles
    PrecacheSound(TOXIN_SOUND);
    PrecacheSound(HYDRO_UBER_SOUND);
    PrecacheSound("weapons/buffed_off.wav");
    PrecacheSound("weapons/teleporter_explode.wav");
    PrecacheModel("models/effects/resist_shield/resist_shield.mdl");
}

// ============================================================================
// Core Condition Management
// ============================================================================

// Add a condition to a player
function AddCond(player, condType, sourcePlayer = null, sourceWeapon = null) {
    if (!player || !player.IsValid()) return false;
    if (condType < 0 || condType >= TFCC_LAST) return false;
    
    local playerIdx = player.entindex();
    
    // Don't add if already has condition
    if (HasCond(player, condType)) {
        return false;
    }
    
    // Don't add negative conditions if player has angel shield/invuln
    if (IsNegativeCond(condType) && (HasCond(player, TFCC_ANGELSHIELD) || HasCond(player, TFCC_ANGELINVULN))) {
        return false;
    }
    
    // Initialize condition storage
    if (!(playerIdx in _playerConditions)) {
        _playerConditions[playerIdx] <- {};
    }
    
    // Create condition data
    _playerConditions[playerIdx][condType] <- {
        level = 0,
        expireTime = 0.0,
        nextTick = 0.0,
        sourcePlayer = sourcePlayer,
        sourceWeapon = sourceWeapon
    };
    
    // Call condition-specific add function
    local success = false;
    switch (condType) {
        case TFCC_TOXIN:
            success = AddToxin(player);
            break;
        case TFCC_ANGELSHIELD:
            success = AddAngelShield(player);
            break;
        case TFCC_ANGELINVULN:
            success = AddAngelInvuln(player);
            break;
        case TFCC_TOXINUBER:
            success = AddToxinUber(player);
            break;
        case TFCC_HYDROPUMPHEAL:
        case TFCC_HYDROUBER:
            success = true; // Placeholder for now
            break;
    }
    
    return success;
}

// Remove a condition from a player
function RemoveCond(player, condType) {
    if (!player || !player.IsValid()) return false;
    if (condType < 0 || condType >= TFCC_LAST) return false;
    
    if (!HasCond(player, condType)) {
        return false;
    }
    
    // Call condition-specific remove function
    switch (condType) {
        case TFCC_TOXIN:
            RemoveToxin(player);
            break;
        case TFCC_ANGELSHIELD:
            RemoveAngelShield(player);
            break;
        case TFCC_TOXINUBER:
            RemoveToxinUber(player);
            break;
    }
    
    // Clear condition data
    local playerIdx = player.entindex();
    if (playerIdx in _playerConditions && condType in _playerConditions[playerIdx]) {
        delete _playerConditions[playerIdx][condType];
    }
    
    return true;
}

// Check if player has a condition
function HasCond(player, condType) {
    if (!player || !player.IsValid()) return false;
    
    local playerIdx = player.entindex();
    return (playerIdx in _playerConditions && condType in _playerConditions[playerIdx]);
}

// Get condition duration remaining
function GetCondDuration(player, condType) {
    if (!HasCond(player, condType)) return 0.0;
    
    local playerIdx = player.entindex();
    local expireTime = _playerConditions[playerIdx][condType].expireTime;
    return expireTime - Time();
}

// Set condition duration
function SetCondDuration(player, condType, duration, additive = false) {
    if (!HasCond(player, condType)) return;
    
    local playerIdx = player.entindex();
    
    if (additive) {
        _playerConditions[playerIdx][condType].expireTime += duration;
    } else {
        _playerConditions[playerIdx][condType].expireTime = Time() + duration;
    }
}

// Get condition level (strength)
function GetCondLevel(player, condType) {
    if (!HasCond(player, condType)) return 0;
    
    local playerIdx = player.entindex();
    return _playerConditions[playerIdx][condType].level;
}

// Set condition level
function SetCondLevel(player, condType, level) {
    if (!HasCond(player, condType)) return;
    
    local playerIdx = player.entindex();
    _playerConditions[playerIdx][condType].level = level;
}

// Get condition source player
function GetCondSourcePlayer(player, condType) {
    if (!HasCond(player, condType)) return null;
    
    local playerIdx = player.entindex();
    return _playerConditions[playerIdx][condType].sourcePlayer;
}

// Get condition source weapon
function GetCondSourceWeapon(player, condType) {
    if (!HasCond(player, condType)) return null;
    
    local playerIdx = player.entindex();
    return _playerConditions[playerIdx][condType].sourceWeapon;
}

// Check if condition is negative (debuff)
function IsNegativeCond(condType) {
    return condType == TFCC_TOXIN;
}

// Clear all conditions from a player
function ClearConds(player) {
    if (!player || !player.IsValid()) return;
    
    for (local i = 0; i < TFCC_LAST; i++) {
        if (HasCond(player, i)) {
            RemoveCond(player, i);
        }
    }
}

// ============================================================================
// TOXIN Implementation
// ============================================================================

function AddToxin(player) {
    local playerIdx = player.entindex();
    
    // Play loop sound
    player.EmitSound(TOXIN_SOUND);
    
    // Set default duration if not already set
    if (_playerConditions[playerIdx][TFCC_TOXIN].expireTime == 0.0) {
        SetCondDuration(player, TFCC_TOXIN, TOXIN_DEFAULT_DURATION);
    }
    
    // Set next tick time to now so first tick happens immediately
    _playerConditions[playerIdx][TFCC_TOXIN].nextTick = Time();
    
    // Remove old emitter if exists
    RemoveToxinEmitter(player);
    
    // Create particle emitter and parent it to the player
    local emitter = SpawnEntityFromTable("info_particle_system", {
        origin = player.GetOrigin(),
        effect_name = TOXIN_PARTICLE
    });
    
    if (emitter) {
        // Parent to player so it follows them
        emitter.SetOwner(player);
        EntFireByHandle(emitter, "SetParent", "!activator", 0.0, player, player);
        EntFireByHandle(emitter, "Start", "", 0.01, null, null);
        _toxinEmitters[playerIdx] <- emitter;
    }
    
    return true;
}

function RemoveToxin(player) {
    local playerIdx = player.entindex();
    
    // Stop sound properly
    EmitSoundEx({
        sound_name = TOXIN_SOUND,
        entity = player,
        flags = 4 // SND_STOP
    });
    
    // Remove emitter
    RemoveToxinEmitter(player);
    
    // Clean up health tracking
    if (playerIdx in _lastPlayerHealth) {
        delete _lastPlayerHealth[playerIdx];
    }
}

function RemoveToxinEmitter(player) {
 
	local playerIdx = player.entindex();
    
    if (playerIdx in _toxinEmitters && _toxinEmitters[playerIdx] && _toxinEmitters[playerIdx].IsValid()) {
        EntFireByHandle(_toxinEmitters[playerIdx], "Stop", "", 0.0, null, null);
        _toxinEmitters[playerIdx].Kill();
    }
    
    if (playerIdx in _toxinEmitters) {
        delete _toxinEmitters[playerIdx];
    }
}

function TickToxin(player) {
    local playerIdx = player.entindex();
    
    // Check if expired (0 means infinite duration)
    local expireTime = _playerConditions[playerIdx][TFCC_TOXIN].expireTime;
    if (expireTime > 0 && expireTime <= Time()) {
        RemoveCond(player, TFCC_TOXIN);
        return;
    }
    
    // Check if time to tick
    if (Time() < _playerConditions[playerIdx][TFCC_TOXIN].nextTick) {
        return;
    }
    
    // Get damage source
    local sourcePlayer = GetCondSourcePlayer(player, TFCC_TOXIN);
    
    // Deal damage - use sourcePlayer as attacker if available, otherwise use player (self-damage)
    local attacker = (sourcePlayer && sourcePlayer.IsValid()) ? sourcePlayer : player;
    player.TakeDamage(TOXIN_DAMAGE, 0, attacker);
    
    // Set next tick time
    _playerConditions[playerIdx][TFCC_TOXIN].nextTick = Time() + TOXIN_FREQUENCY;
}

// ============================================================================
// ANGEL SHIELD Implementation
// ============================================================================

function AddAngelShield(player) {
    local playerIdx = player.entindex();
    
    // Set duration and health
    SetCondDuration(player, TFCC_ANGELSHIELD, ANGEL_SHIELD_DURATION);
    SetCondLevel(player, TFCC_ANGELSHIELD, ANGEL_SHIELD_HEALTH);
    
    _shieldExpireTimes[playerIdx] <- Time() + ANGEL_SHIELD_DURATION;
    _lastDamagedShield[playerIdx] <- Time();
    
    // Initialize health tracking for damage detection
    _lastShieldCheckHealth[playerIdx] <- player.GetHealth();
    
    // Remove old shield if exists
    RemoveAngelShieldEntities(player);
    
    // Create shield prop
    local teamNum = player.GetTeam() - 2;
    local shield = SpawnEntityFromTable("prop_dynamic", {
        origin = player.GetOrigin(),
        model = "models/effects/resist_shield/resist_shield.mdl",
        skin = teamNum,
        disableshadows = 1
    });
    
    if (shield) {
        shield.SetOwner(player);
        _angelShields[playerIdx] <- shield;
    }
    
    // Clear negative conditions
    player.RemoveCond(64); // Bleeding
    player.RemoveCond(22); // OnFire
    RemoveCond(player, TFCC_TOXIN);
    
    return true;
}

function RemoveAngelShield(player) {
    RemoveAngelShieldEntities(player);
    
    local playerIdx = player.entindex();
    
    // Play break effects
    player.EmitSound("weapons/teleporter_explode.wav");
    
    // Clear timers
    if (playerIdx in _shieldExpireTimes) {
        delete _shieldExpireTimes[playerIdx];
    }
    
    // Clean up health tracking
    if (playerIdx in _lastShieldCheckHealth) {
        delete _lastShieldCheckHealth[playerIdx];
    }
}

function RemoveAngelShieldEntities(player) {
    local playerIdx = player.entindex();
    
    if (playerIdx in _angelShields && _angelShields[playerIdx] && _angelShields[playerIdx].IsValid()) {
        _angelShields[playerIdx].Kill();
    }
    
    if (playerIdx in _angelShields) {
        delete _angelShields[playerIdx];
    }
}

// Update shield position to follow player
function UpdateAngelShieldPosition(player) {
    local playerIdx = player.entindex();
    
    if (!(playerIdx in _angelShields)) return;
    
    local shield = _angelShields[playerIdx];
    if (!shield || !shield.IsValid()) return;
    
    // Update shield position to match player
    shield.SetAbsOrigin(player.GetOrigin());
}

function AngelShieldTakeDamage(player, damage) {
    local playerIdx = player.entindex();
    
    if (!HasCond(player, TFCC_ANGELSHIELD)) return;
    
    // Reduce shield health
    local currentHealth = GetCondLevel(player, TFCC_ANGELSHIELD);
    SetCondLevel(player, TFCC_ANGELSHIELD, currentHealth - damage);
    
    _lastDamagedShield[playerIdx] = Time();
    
    // Play sound
    player.EmitSound("Player.ResistanceHeavy");
    
    // Check if shield broke
    if (GetCondLevel(player, TFCC_ANGELSHIELD) <= 0) {
        RemoveCond(player, TFCC_ANGELSHIELD);
        AddCond(player, TFCC_ANGELINVULN);
    }
}

// ============================================================================
// ANGEL INVULN Implementation
// ============================================================================

function AddAngelInvuln(player) {
    SetCondDuration(player, TFCC_ANGELINVULN, ANGEL_INVULN_DURATION);
    return true;
}

// ============================================================================
// TOXIN UBER Implementation
// ============================================================================

function AddToxinUber(player) {
    local playerIdx = player.entindex();
    
    // Remove old emitter
    RemoveToxinUberEmitter(player);
    
    // Create particle emitter
    local teamNum = player.GetTeam() - 2;
    local particleName = "biowastepump_uber_red";
    
    switch (teamNum) {
        case 1: particleName = "biowastepump_uber_blue"; break;
        case 2: particleName = "biowastepump_uber_green"; break;
        case 3: particleName = "biowastepump_uber_yellow"; break;
    }
    
    local emitter = SpawnEntityFromTable("info_particle_system", {
        origin = player.GetOrigin(),
        effect_name = particleName
    });
    
    if (emitter) {
        emitter.SetOwner(player);
        EntFireByHandle(emitter, "SetParent", "!activator", 0.0, player, player);
        EntFireByHandle(emitter, "Start", "", 0.01, null, null);
        _toxinUberEmitters[playerIdx] <- emitter;
    }
    
    return true;
}

function RemoveToxinUber(player) {
    RemoveToxinUberEmitter(player);
}

function RemoveToxinUberEmitter(player) {
    local playerIdx = player.entindex();
    
    if (playerIdx in _toxinUberEmitters && _toxinUberEmitters[playerIdx] && _toxinUberEmitters[playerIdx].IsValid()) {
        EntFireByHandle(_toxinUberEmitters[playerIdx], "Stop", "", 0.0, null, null);
        _toxinUberEmitters[playerIdx].Kill();
    }
    
    if (playerIdx in _toxinUberEmitters) {
        delete _toxinUberEmitters[playerIdx];
    }
}

function TickToxinUber(player) {
    local playerIdx = player.entindex();
    
    // Check if expired
    if (_playerConditions[playerIdx][TFCC_TOXINUBER].expireTime < Time()) {
        RemoveCond(player, TFCC_TOXINUBER);
        return;
    }
    
    // Apply toxin to nearby enemies
    local origin = player.GetOrigin();
    local sourcePlayer = GetCondSourcePlayer(player, TFCC_TOXINUBER);
    
    local ent = null;
    while ((ent = Entities.FindByClassnameWithin(ent, "player", origin, TOXIN_UBER_RANGE)) != null) {
        if (ent.IsValid() && ent != player && ent.GetTeam() != player.GetTeam()) {
            if (ent.GetHealth() > 0) {
                AddCond(ent, TFCC_TOXIN, sourcePlayer, null);
                SetCondDuration(ent, TFCC_TOXIN, TOXIN_UBER_PULSE_RATE * 2, true);
            }
        }
    }
}

// ============================================================================
// Think/Update Processing
// ============================================================================

function Think() {
    // Process all players with conditions
    local player = null;
    while ((player = Entities.FindByClassname(player, "player")) != null) {
        if (!player.IsValid() || player.GetHealth() <= 0) continue;
        
        local playerIdx = player.entindex();
        
        // Handle toxin healing reduction
        if (HasCond(player, TFCC_TOXIN)) {
            local currentHealth = player.GetHealth();
            
            // Track previous health
            if (!(playerIdx in _lastPlayerHealth)) {
                _lastPlayerHealth[playerIdx] <- currentHealth;
            }
            
            local lastHealth = _lastPlayerHealth[playerIdx];
            
            // If player gained health, reduce it
            if (currentHealth > lastHealth) {
                local healAmount = currentHealth - lastHealth;
                local reducedHeal = healAmount * TOXIN_HEALING_MULT;
                local healthToRemove = healAmount - reducedHeal;
                
                player.SetHealth(currentHealth - healthToRemove);
                currentHealth = player.GetHealth();
            }
            
            _lastPlayerHealth[playerIdx] = currentHealth;
        } else {
            // Update health tracking even without toxin
            if (playerIdx in _lastPlayerHealth) {
                _lastPlayerHealth[playerIdx] = player.GetHealth();
            }
        }
        
        // Handle angel shield damage absorption
        if (HasCond(player, TFCC_ANGELSHIELD)) {
            local currentHealth = player.GetHealth();
            
            // Track previous health
            if (!(playerIdx in _lastShieldCheckHealth)) {
                _lastShieldCheckHealth[playerIdx] <- currentHealth;
            }
            
            local lastHealth = _lastShieldCheckHealth[playerIdx];
            
            // If player lost health, absorb it with shield
            if (currentHealth < lastHealth) {
                local damageAmount = lastHealth - currentHealth;
                
                // Get shield health
                local shieldHealth = GetCondLevel(player, TFCC_ANGELSHIELD);
                
                if (shieldHealth > 0) {
                    // Shield absorbs the damage
                    SetCondLevel(player, TFCC_ANGELSHIELD, shieldHealth - damageAmount);
                    _lastDamagedShield[playerIdx] = Time();
                    
                    // Restore player health
                    player.SetHealth(lastHealth);
                    currentHealth = lastHealth;
                    
                    // Play sound
                    player.EmitSound("Player.ResistanceHeavy");
                    
                    // Check if shield broke
                    if (GetCondLevel(player, TFCC_ANGELSHIELD) <= 0) {
                        RemoveCond(player, TFCC_ANGELSHIELD);
                        AddCond(player, TFCC_ANGELINVULN);
                    }
                }
            }
            
            _lastShieldCheckHealth[playerIdx] = currentHealth;
        } else {
            // Update health tracking
            if (playerIdx in _lastShieldCheckHealth) {
                _lastShieldCheckHealth[playerIdx] = player.GetHealth();
            }
        }
        
        // Check for expired conditions
        if (playerIdx in _playerConditions) {
            foreach (condType, data in _playerConditions[playerIdx]) {
                if (data.expireTime > 0 && data.expireTime <= Time()) {
                    RemoveCond(player, condType);
                }
            }
        }
        
        // Tick active conditions
        if (HasCond(player, TFCC_TOXIN)) TickToxin(player);
        if (HasCond(player, TFCC_TOXINUBER)) TickToxinUber(player);
        
        // Update shield position
        if (HasCond(player, TFCC_ANGELSHIELD)) UpdateAngelShieldPosition(player);
    }
}

// ============================================================================
// Event Handlers
// ============================================================================

function OnPlayerDisconnect(player) {
    if (!player) return;
    local playerIdx = player.entindex();
    
    ClearConds(player);
    
    // Clean up health tracking
    if (playerIdx in _lastPlayerHealth) {
        delete _lastPlayerHealth[playerIdx];
    }
}

function OnPlayerDeath(player) {
    if (!player) return;
    local playerIdx = player.entindex();
    
    ClearConds(player);
    
    // Clean up health tracking
    if (playerIdx in _lastPlayerHealth) {
        delete _lastPlayerHealth[playerIdx];
    }
}

// ============================================================================
// Public API
// ============================================================================

::ConditionHandler <- {
    // Condition constants
    TOXIN = TFCC_TOXIN,
    HYDROPUMPHEAL = TFCC_HYDROPUMPHEAL,
    HYDROUBER = TFCC_HYDROUBER,
    ANGELSHIELD = TFCC_ANGELSHIELD,
    ANGELINVULN = TFCC_ANGELINVULN,
    TOXINUBER = TFCC_TOXINUBER,
    
    // Core functions
    AddCond = function(player, condType, sourcePlayer = null, sourceWeapon = null) {
        return ::AddCond(player, condType, sourcePlayer, sourceWeapon);
    },
    
    RemoveCond = function(player, condType) {
        return ::RemoveCond(player, condType);
    },
    
    HasCond = function(player, condType) {
        return ::HasCond(player, condType);
    },
    
    GetDuration = function(player, condType) {
        return ::GetCondDuration(player, condType);
    },
    
    SetDuration = function(player, condType, duration, additive = false) {
        return ::SetCondDuration(player, condType, duration, additive);
    },
    
    GetLevel = function(player, condType) {
        return ::GetCondLevel(player, condType);
    },
    
    SetLevel = function(player, condType, level) {
        return ::SetCondLevel(player, condType, level);
    },
    
    ClearAll = function(player) {
        return ::ClearConds(player);
    },
    
    // Event handlers
    OnPlayerDisconnect = function(player) {
        return ::OnPlayerDisconnect(player);
    },
    
    OnPlayerDeath = function(player) {
        return ::OnPlayerDeath(player);
    },
    
    Think = function() {
        return ::Think();
    }
}

// ============================================================================
// Auto-initialize
// ============================================================================
if (!("_conditionHandlerInitialized" in getroottable())) {
    _conditionHandlerInitialized <- true;
    Initialize();
}
