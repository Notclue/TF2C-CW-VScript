// ============================================================================
// Attribute: Airburst - Airburst Sticky Bombs
// ============================================================================
// Port of attribute_airdet.sp for VScript
// Allows shooting sticky bombs mid-air to detonate them with distance-based damage

// ============================================================================
// Configuration Constants
// ============================================================================

// Attribute names
const ATTRIB_AIRDET_ENABLE = "custom airdet";

// Models and sounds
const STICKYBOMB_MODEL = "models/weapons/w_models/w_stickyrifle/c_stickybomb_rifle.mdl";
const FIRE_SOUND = "weapons/stickybomblauncher_shoot.wav";
const COLLIDER_MODEL = "models/props_gameplay/ball001.mdl";

// Gameplay values
const AIRDET_DAMAGE = 60.0;
const AIRDET_RADIUS = 75.0;
const AIRDET_DETONATE_DAMAGE = 215.0;
const AIRDET_DETONATE_RADIUS = 150.0;
const AIRDET_VELOCITY = 960.0;
const AIRDET_VELOCITY_UP = 200.0;
const AIRDET_IMPULSE = 600.0;
const AIRDET_MODEL_SCALE = 1.5;

// Timing
const AIRDET_PRIMARY_COOLDOWN = 0.3;
const AIRDET_SECONDARY_COOLDOWN = 0.6;

// Lag compensation
const BOMB_HISTORY_SIZE = 16;

// ============================================================================
// Global State
// ============================================================================

// Track all airdet bombs and their colliders
_airdetBombs <- {}; // bombIdx -> { collider: entity, history: array, lastIndex: int }

// Track weapon firing state for button detection
_lastWeaponButtons <- {}; // playerIdx -> { attack1: bool, attack2: bool }

// Track last time we checked for shooting (to avoid multiple checks per shot)
_lastShotCheckTime <- {}; // playerIdx -> float

// ============================================================================
// Initialization
// ============================================================================

function Initialize() {
    printl("[AttributeAirdet] System initialized");
    
    // Precache models and sounds
    PrecacheModel(STICKYBOMB_MODEL);
    PrecacheModel(COLLIDER_MODEL);
    PrecacheScriptSound(FIRE_SOUND);
}

// ============================================================================
// Weapon Detection
// ============================================================================

// Check if a weapon has airdet enabled
function HasAirdet(weapon) {
    if (!weapon || !weapon.IsValid()) return false;
    
    try {
        local value = weapon.GetAttribute(ATTRIB_AIRDET_ENABLE, 0.0);
        return value != 0.0;
    } catch (e) {
        return false;
    }
}

// ============================================================================
// Bomb Management
// ============================================================================

// Create a new airdet bomb with collision sphere
function CreateAirdetBomb(player, weapon, origin, angles, velocity) {
    if (!player || !player.IsValid()) {
        return null;
    }
    if (!weapon || !weapon.IsValid()) {
        return null;
    }
    
    // Create the grenade projectile with velocity (tf_projectile_pipe for impact detonation)
    local bomb = SpawnEntityFromTable("tf_projectile_pipe", {
        origin = origin,
        angles = angles,
        teamnum = player.GetTeam(),
        basevelocity = velocity
    });
    
    if (!bomb) {
        return null;
    }
    
    // Set bomb properties
    bomb.SetModel(STICKYBOMB_MODEL);
    
    NetProps.SetPropEntity(bomb, "m_hThrower", player);
    NetProps.SetPropEntity(bomb, "m_hOriginalLauncher", weapon);
    NetProps.SetPropFloat(bomb, "m_flModelScale", AIRDET_MODEL_SCALE);
    NetProps.SetPropFloat(bomb, "m_flDamage", AIRDET_DAMAGE);
    NetProps.SetPropFloat(bomb, "m_DmgRadius", AIRDET_RADIUS);
    
    // Set to detonate on impact with world
    // Couldn't get this to work, this is what i tried...
    // NetProps.SetPropInt(bomb, "m_bTouched", 1);
    
    // Try multiple methods to set velocity
    bomb.SetAbsVelocity(velocity);
    bomb.ApplyAbsVelocityImpulse(velocity);
    
    // Try to get physics object and apply velocity
    local physObj = bomb.GetPhysicsObject();
    if (physObj) {
        bomb.SetPhysVelocity(velocity);
        bomb.SetPhysAngularVelocity(Vector(0, 0, 0));
    }

    // Create invisible collision sphere
    local collider = SpawnEntityFromTable("prop_dynamic_override", {
        origin = origin,
        model = COLLIDER_MODEL,
        solid = 6, // SOLID_VPHYSICS
        effects = 0x020 // EF_NODRAW
    });
    
    if (!collider) {
        bomb.Kill();
        return null;
    }
    
    // Set collider to be damageable
    collider.SetOwner(bomb);
    NetProps.SetPropInt(collider, "m_takedamage", 2); // DAMAGE_YES
    
    // Initialize lag compensation history
    local bombIdx = bomb.entindex();
    _airdetBombs[bombIdx] <- {
        collider = collider,
        history = [],
        lastIndex = 0
    };
    
    // Initialize history array
    for (local i = 0; i < BOMB_HISTORY_SIZE; i++) {
        _airdetBombs[bombIdx].history.append({
            x = origin.x,
            y = origin.y,
            z = origin.z,
            time = -1.0
        });
    }
    
    return bomb;
}

// Remove bomb and its collider
function RemoveBomb(bombIdx) {
    if (!(bombIdx in _airdetBombs)) return;
    
    local bombData = _airdetBombs[bombIdx];
    
    // Remove collider
    if (bombData.collider && bombData.collider.IsValid()) {
        bombData.collider.Kill();
    }
    
    // Clean up tracking
    delete _airdetBombs[bombIdx];
}

// Update bomb position history for lag compensation
function UpdateBombHistory(bombIdx, position) {
    if (!(bombIdx in _airdetBombs)) return;
    
    local bombData = _airdetBombs[bombIdx];
    local newIndex = (bombData.lastIndex + 1) % BOMB_HISTORY_SIZE;
    
    bombData.history[newIndex].x = position.x;
    bombData.history[newIndex].y = position.y;
    bombData.history[newIndex].z = position.z;
    bombData.history[newIndex].time = Time();
    
    bombData.lastIndex = newIndex;
}

// Get lag-compensated position for a bomb
function GetLagCompensatedPosition(bombIdx, latency) {
    if (!(bombIdx in _airdetBombs)) return null;
    
    local bombData = _airdetBombs[bombIdx];
    local targetTime = Time() - latency;
    
    // If latency is very low, just use current position
    if (latency < 0.016) {
        local currentIdx = bombData.lastIndex;
        return Vector(
            bombData.history[currentIdx].x,
            bombData.history[currentIdx].y,
            bombData.history[currentIdx].z
        );
    }
    
    // Find closest historical position
    local bestIndex = 0;
    local bestTimeDiff = 100.0;
    
    for (local i = 0; i < BOMB_HISTORY_SIZE; i++) {
        local historyTime = bombData.history[i].time;
        if (historyTime < 0.0) continue; // Not initialized yet
        
        local timeDiff = targetTime - historyTime;
        if (timeDiff < bestTimeDiff && timeDiff > 0.0) {
            bestIndex = i;
            bestTimeDiff = timeDiff;
        }
    }
    
    return Vector(
        bombData.history[bestIndex].x,
        bombData.history[bestIndex].y,
        bombData.history[bestIndex].z
    );
}

// ============================================================================
// Weapon Actions
// ============================================================================

// Handle secondary attack (fire airburst sticky)
function FireAirdetSticky(player, weapon) {
    if (!player || !player.IsValid()) {
        return false;
    }
    if (!weapon || !weapon.IsValid()) {
        return false;
    }
    
    // Get eye position and angles
    local eyePos = player.EyePosition();
    local eyeAngles = player.EyeAngles();
    
    // Calculate velocity from eye angles
    local forward = eyeAngles.Forward();
    local up = eyeAngles.Up();
    
    // Spawn grenade further forward to avoid player collision (32 units ahead)
    local spawnPos = eyePos + (forward * 32.0);
    
    local velocity = (forward * AIRDET_VELOCITY) + (up * AIRDET_VELOCITY_UP);
    
    // Play sound
    EmitSoundOn(FIRE_SOUND, player);
    
    // Create the bomb
    local bomb = CreateAirdetBomb(player, weapon, spawnPos, eyeAngles, velocity);
    
    if (!bomb) {
        return false;
    }
    
    // Set weapon animation (mode 1 = secondary attack)
    NetProps.SetPropInt(weapon, "m_iWeaponMode", 1);
    
    return true;
}

// Handle primary attack hitting a bomb
function DetonateBombAtCollider(bomb, collider, weapon, attacker) {
    if (!bomb || !bomb.IsValid()) return;
    if (!weapon || !weapon.IsValid()) return;
    if (!attacker || !attacker.IsValid()) return;
    
    local bombIdx = bomb.entindex();
    
    // Get positions for distance calculation
    local attackerPos = attacker.GetOrigin();
    local colliderPos = collider.GetOrigin();
    
    // Calculate distance-based damage (simplified - TF2's damage falloff)
    local distance = (colliderPos - attackerPos).Length();
    local damage = AIRDET_DETONATE_DAMAGE;
    
    // Simple linear falloff (TF2 uses more complex formula)
    if (distance > 512.0) {
        damage = damage * 0.5; // 50% at long range
    } else if (distance > 0.0) {
        local falloff = 1.0 - ((distance - 0.0) / (512.0 - 0.0)) * 0.5;
        damage = damage * falloff;
    }
    
    // Move bomb to collider position
    bomb.SetOrigin(colliderPos);
    
    // Set detonation damage and radius
    NetProps.SetPropFloat(bomb, "m_flDamage", damage);
    NetProps.SetPropFloat(bomb, "m_DmgRadius", AIRDET_DETONATE_RADIUS);
    
    // Remove from tracking before detonation
    RemoveBomb(bombIdx);
    
    // Detonate the bomb
    EntFireByHandle(bomb, "Detonate", "", 0.0, null, null);
}

// Check if player is shooting at their bombs using actual trace line
function CheckPlayerShootingBombs(player, weapon) {
    if (!player || !player.IsValid()) return;
    if (!weapon || !weapon.IsValid()) return;
    
    local playerIdx = player.entindex();
    local currentTime = Time();
    
    // Rate limit checks to once every 0.05 seconds for responsiveness
    if (playerIdx in _lastShotCheckTime) {
        if (currentTime - _lastShotCheckTime[playerIdx] < 0.05) {
            return;
        }
    }
    _lastShotCheckTime[playerIdx] <- currentTime;
    
    local eyePos = player.EyePosition();
    local eyeAngles = player.EyeAngles();
    local forward = eyeAngles.Forward();
    local traceEnd = eyePos + (forward * 8192.0);
    
    // Perform actual trace line
    local trace = {
        start = eyePos,
        end = traceEnd,
        ignore = player
    };
    
    TraceLineEx(trace);
    
    // Check if we hit one of our bomb colliders
    if ("hit" in trace && trace.hit) {
        local hitEntity = trace.enthit;
        
        if (hitEntity && hitEntity.IsValid()) {
            // Check all our bombs to see if this is one of our colliders
            foreach (bombIdx, bombData in _airdetBombs) {
                local bomb = GetEntityByIndex(bombIdx);
                if (!bomb || !bomb.IsValid()) continue;
                
                // Only detonate our own bombs
                local launcher = NetProps.GetPropEntity(bomb, "m_hOriginalLauncher");
                if (launcher != weapon) continue;
                
                local collider = bombData.collider;
                if (!collider || !collider.IsValid()) continue;
                
                // Check if we hit this bomb's collider
                if (hitEntity == collider) {
                    local distance = (trace.pos - eyePos).Length();
                    DetonateBombAtCollider(bomb, collider, weapon, player);
                    return;
                }
            }
        }
    }
}

// ============================================================================
// Think Processing
// ============================================================================

function Think() {
    local currentTime = Time();
    
    // Update bomb position history
    foreach (bombIdx, bombData in _airdetBombs) {
        local bomb = GetEntityByIndex(bombIdx);
        if (!bomb || !bomb.IsValid()) {
            RemoveBomb(bombIdx);
            continue;
        }
        
        local bombPos = bomb.GetOrigin();
        UpdateBombHistory(bombIdx, bombPos);
        
        // Update collider position to match bomb
        if (bombData.collider && bombData.collider.IsValid()) {
            bombData.collider.SetOrigin(bombPos);
        }
    }
    
    // Check all players for weapon actions
    local player = null;
    while ((player = Entities.FindByClassname(player, "player")) != null) {
        if (!player.IsValid() || player.GetHealth() <= 0) continue;
        
        local playerIdx = player.entindex();
        local weapon = player.GetActiveWeapon();
        
        if (!weapon || !weapon.IsValid()) continue;
        if (!HasAirdet(weapon)) continue;
        
        // Get button states
        local buttons = player.GetButtons();
        local attack1 = (buttons & 1) != 0; // IN_ATTACK
        local attack2 = (buttons & 2048) != 0; // IN_ATTACK2
        
        // Get last button states
        local lastAttack1 = false;
        local lastAttack2 = false;
        if (playerIdx in _lastWeaponButtons) {
            lastAttack1 = _lastWeaponButtons[playerIdx].attack1;
            lastAttack2 = _lastWeaponButtons[playerIdx].attack2;
        } else {
            _lastWeaponButtons[playerIdx] <- { attack1 = false, attack2 = false };
        }
        
        // Handle primary attack (shoot bombs)
        // Check when player presses fire button
        if (attack1 && !lastAttack1) {
            CheckPlayerShootingBombs(player, weapon);
        }
        
        // Handle secondary attack (fire sticky)
        if (attack2 && !lastAttack2) {
            // Check primary attack cooldown (use primary since secondary might not be initialized)
            local nextPrimary = NetProps.GetPropFloat(weapon, "m_flNextPrimaryAttack");
            
            if (currentTime >= nextPrimary) {
                // Check ammo
                local clip = weapon.Clip1();
                
                if (clip > 0) {
                    if (FireAirdetSticky(player, weapon)) {
                        // Consume ammo
                        weapon.SetClip1(clip - 1);
                        
                        // Set cooldowns
                        NetProps.SetPropFloat(weapon, "m_flNextPrimaryAttack", currentTime + AIRDET_PRIMARY_COOLDOWN);
                        NetProps.SetPropFloat(weapon, "m_flNextSecondaryAttack", currentTime + AIRDET_SECONDARY_COOLDOWN);
                    }
                }
            }
        }
        
        // Store current button state
        _lastWeaponButtons[playerIdx].attack1 = attack1;
        _lastWeaponButtons[playerIdx].attack2 = attack2;
    }
}

// ============================================================================
// Damage Handling
// ============================================================================

// Called when a collider takes damage
function OnColliderDamage(collider, damageInfo) {
    if (!collider || !collider.IsValid()) return;
    
    // Get the bomb this collider belongs to
    local bomb = collider.GetOwner();
    if (!bomb || !bomb.IsValid()) return;
    
    // Get the weapon that fired
    local weapon = damageInfo.GetWeapon();
    if (!weapon || !weapon.IsValid()) return;
    
    // Check if it's the same weapon that launched the bomb
    local launcher = NetProps.GetPropEntity(bomb, "m_hOriginalLauncher");
    if (weapon != launcher) return;
    
    // Check if it's bullet damage (hitscan)
    local damageType = damageInfo.GetDamageType();
    if (!(damageType & 2)) return; // DMG_BULLET = 2
    
    // Get attacker
    local attacker = damageInfo.GetAttacker();
    if (!attacker || !attacker.IsValid()) return;
    
    // Detonate the bomb
    DetonateBombAtCollider(bomb, collider, weapon, attacker);
}

// ============================================================================
// Event Handlers
// ============================================================================

function OnPlayerDisconnect(player) {
    if (!player) return;
    local playerIdx = player.entindex();
    
    // Clean up button tracking
    if (playerIdx in _lastWeaponButtons) {
        delete _lastWeaponButtons[playerIdx];
    }
    
    // Clean up shot check tracking
    if (playerIdx in _lastShotCheckTime) {
        delete _lastShotCheckTime[playerIdx];
    }
    
    // Clean up any bombs owned by this player
    local toRemove = [];
    foreach (bombIdx, bombData in _airdetBombs) {
        local bomb = GetEntityByIndex(bombIdx);
        if (bomb && bomb.IsValid()) {
            local thrower = NetProps.GetPropEntity(bomb, "m_hThrower");
            if (thrower == player) {
                toRemove.append(bombIdx);
            }
        }
    }
    
    foreach (bombIdx in toRemove) {
        RemoveBomb(bombIdx);
    }
}

function OnEntityKilled(entity) {
    if (!entity) return;
    
    local classname = entity.GetClassname();
    if (classname == "tf_projectile_pipe" || classname == "tf_projectile_pipe_remote") {
        // Bomb was destroyed, clean up
        local bombIdx = entity.entindex();
        RemoveBomb(bombIdx);
    }
}

// ============================================================================
// Utility Functions
// ============================================================================

function GetEntityByIndex(idx) {
    local ent = null;
    while ((ent = Entities.Next(ent)) != null) {
        if (ent.entindex() == idx) {
            return ent;
        }
    }
    return null;
}

// ============================================================================
// Public API
// ============================================================================

::AttributeAirdet <- {
    // Core functions
    HasAirdet = function(weapon) {
        return ::HasAirdet(weapon);
    },
    
    FireAirdetSticky = function(player, weapon) {
        return ::FireAirdetSticky(player, weapon);
    },
    
    OnColliderDamage = function(collider, damageInfo) {
        return ::OnColliderDamage(collider, damageInfo);
    },
    
    // Event handlers
    OnPlayerDisconnect = function(player) {
        return ::OnPlayerDisconnect(player);
    },
    
    OnEntityKilled = function(entity) {
        return ::OnEntityKilled(entity);
    },
    
    Think = function() {
        return ::Think();
    }
}

// ============================================================================
// Auto-initialize
// ============================================================================
if (!("_attributeAirdetInitialized" in getroottable())) {
    _attributeAirdetInitialized <- true;
    Initialize();
}