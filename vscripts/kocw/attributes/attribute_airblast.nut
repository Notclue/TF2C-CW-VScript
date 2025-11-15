// ============================================================================
// Attribute: Airblast - Custom Airblast for Non-Flamethrower Weapons
// ============================================================================
// Port of attribute_airblast.sp for VScript
// Allows any weapon to have airblast functionality with custom particles and sounds

// ============================================================================
// Configuration Constants
// ============================================================================

// Attribute names
const ATTRIB_AIRBLAST_ENABLE = "custom airblast";
const ATTRIB_AIRBLAST_PARTICLE = "custom airblast particle";
const ATTRIB_AIRBLAST_SOUND = "custom airblast sound";
const ATTRIB_AIRBLAST_REFIRE = "mult airblast refire time";
const ATTRIB_AIRBLAST_COST = "airblast cost decreased";
const ATTRIB_AIRBLAST_SCALE = "deflection size multiplier";
const ATTRIB_AIRBLAST_SELF_PUSH = "apply self knockback airblast";
const ATTRIB_AIRBLAST_FLAGS = "airblast functionality flags";
const ATTRIB_AIRBLAST_NO_PUSH = "disable airblasting players";
const ATTRIB_AIRBLAST_DESTROY = "airblast_destroy_projectile";

// Sound effects
const AIRBLAST_SOUND = "Weapon_FlameThrower.AirBurstAttack";
const DEFLECT_SOUND = "Weapon_FlameThrower.AirBurstAttackDeflect";
const EXTINGUISH_SOUND = "TFPlayer.FlameOut";
const AIRBLAST_PLAYER_SOUND = "TFPlayer.AirBlastImpact";
const DELETE_AIRBLAST_SOUND = "Fire.Engulf";

// Particle effects
const AIRBLAST_PARTICLE = "pyro_blast";
const DEFLECT_PARTICLE = "deflect_fx";
const DELETE_PARTICLE = "explosioncore_sapperdestroyed";

// Airblast functionality flags
const AB_PUSH = 1;
const AB_EXTINGUISH = 2;
const AB_REFLECT = 4;

// Button constants
const IN_ATTACK2 = 2048;

// Default values
const DEFAULT_AIRBLAST_COST = 1.0;
const DEFAULT_AIRBLAST_REFIRE = 0.75;
const DEFAULT_AIRBLAST_SCALE = 1.0;
const AIRBLAST_DURATION = 0.06; // How long the airblast hitbox is active
const AIRBLAST_PUSH_FORCE = 500.0;
const AIRBLAST_DOT_THRESHOLD = 0.8; // How centered target must be to get pushed

// ============================================================================
// Global State
// ============================================================================

// Track players hit by current airblast to prevent multi-push
_airblasted <- {}; // playerIdx -> array of victim indices

// Track airblast end times
_airblastEndTime <- {}; // playerIdx -> timestamp

// Track last button state to detect presses
_lastButtons <- {}; // playerIdx -> button mask

// Track next allowed airblast time (for cooldown)
_nextAirblastTime <- {}; // playerIdx -> timestamp

// ============================================================================
// Initialization
// ============================================================================

function Initialize() {
    printl("[AttributeAirblast] System initialized");
    
    // Precache sounds
    PrecacheScriptSound(AIRBLAST_SOUND);
    PrecacheScriptSound(DELETE_AIRBLAST_SOUND);
    PrecacheScriptSound(EXTINGUISH_SOUND);
    PrecacheScriptSound(DEFLECT_SOUND);
    PrecacheScriptSound(AIRBLAST_PLAYER_SOUND);
}

// ============================================================================
// Weapon Detection
// ============================================================================

// Check if a weapon has custom airblast enabled
function HasCustomAirblast(weapon) {
    if (!weapon || !weapon.IsValid()) return false;
    
    // Check if weapon has the custom_airblast attribute
    try {
        local value = weapon.GetAttribute(ATTRIB_AIRBLAST_ENABLE, 0.0);
        return value != 0.0;
    } catch (e) {
        return false;
    }
}

// Get attribute value from weapon with default fallback
function GetWeaponAttribute(weapon, attributeName, defaultValue) {
    if (!weapon || !weapon.IsValid()) return defaultValue;
    
    try {
        return weapon.GetAttribute(attributeName, defaultValue);
    } catch (e) {
        return defaultValue;
    }
}

// ============================================================================
// Airblast Execution
// ============================================================================

// Perform airblast from a weapon
function DoAirblast(player, weapon) {
    if (!player || !player.IsValid()) return false;
    if (!weapon || !weapon.IsValid()) return false;
    
    local playerIdx = player.entindex();
    local currentTime = Time();
    
    // Check cooldown
    if (playerIdx in _nextAirblastTime) {
        if (currentTime < _nextAirblastTime[playerIdx]) {
            return false; // Still on cooldown
        }
    }
    
    // Get airblast settings from attributes
    local ammoCost = GetWeaponAttribute(weapon, ATTRIB_AIRBLAST_COST, DEFAULT_AIRBLAST_COST);
    local refireTime = GetWeaponAttribute(weapon, ATTRIB_AIRBLAST_REFIRE, DEFAULT_AIRBLAST_REFIRE);
    local scale = GetWeaponAttribute(weapon, ATTRIB_AIRBLAST_SCALE, DEFAULT_AIRBLAST_SCALE);
    local flagsValue = GetWeaponAttribute(weapon, ATTRIB_AIRBLAST_FLAGS, -1.0);
    local noPushValue = GetWeaponAttribute(weapon, ATTRIB_AIRBLAST_NO_PUSH, 0.0);
    local destroyValue = GetWeaponAttribute(weapon, ATTRIB_AIRBLAST_DESTROY, 0.0);
    local selfPushValue = GetWeaponAttribute(weapon, ATTRIB_AIRBLAST_SELF_PUSH, 0.0);
    
    // Determine flags
    local flags = AB_PUSH | AB_EXTINGUISH | AB_REFLECT;
    if (flagsValue >= 0.0) {
        flags = flagsValue.tointeger();
    }
    if (noPushValue != 0.0) {
        flags = flags & ~AB_PUSH;
    }
    
    local shouldDestroy = (destroyValue != 0.0);
    
    // Check and consume ammo
    local currentAmmo = weapon.Clip1();
    if (currentAmmo < ammoCost) {
        return false; // Not enough ammo
    }
    
    // Consume ammo
    weapon.SetClip1(currentAmmo - ammoCost.tointeger());
    
    // Set cooldown
    _nextAirblastTime[playerIdx] <- currentTime + refireTime;
    
    // Play airblast sound
    local customSound = GetWeaponAttribute(weapon, ATTRIB_AIRBLAST_SOUND, 0.0);
    if (customSound != 0.0) {
        // Would use custom sound here if we could read string attributes
        EmitSoundOn(AIRBLAST_SOUND, player);
    } else {
        EmitSoundOn(AIRBLAST_SOUND, player);
    }
    
    // Create airblast particles
    DoAirblastParticles(player, weapon);
    
    // Set airblast end time
    _airblastEndTime[playerIdx] <- Time() + AIRBLAST_DURATION;
    
    // Clear previous airblast victims
    if (!(playerIdx in _airblasted)) {
        _airblasted[playerIdx] <- [];
    } else {
        _airblasted[playerIdx].clear();
    }
    
    // Apply self-knockback if enabled
    if (selfPushValue != 0.0) {
        local angles = player.EyeAngles();
        local backward = angles.Forward() * -1.0;
        backward.Norm();
        
        local selfPushForce = AIRBLAST_PUSH_FORCE * selfPushValue;
        local selfVelocity = backward * selfPushForce;
        
        // Add to existing velocity instead of setting
        local currentVel = player.GetAbsVelocity();
        player.SetAbsVelocity(currentVel + selfVelocity);
    }
    
    // Process airblast hitbox
    ProcessAirblastHitbox(player, weapon, flags, scale, shouldDestroy);
    
    return true;
}

// Create airblast particle effects
function DoAirblastParticles(player, weapon) {
    if (!player || !player.IsValid()) return;
    if (!weapon || !weapon.IsValid()) return;
    
    // Try to get weapon's attachment point
    local attachmentId = weapon.LookupAttachment("muzzle");
    local particleOrigin;
    local particleAngles;
    
    if (attachmentId > 0) {
        // Get muzzle attachment position
        particleOrigin = weapon.GetAttachmentOrigin(attachmentId);
        particleAngles = weapon.GetAttachmentAngles(attachmentId);
    } else {
        // Fallback to eye position if no muzzle attachment
        particleOrigin = player.EyePosition();
        particleAngles = player.EyeAngles();
        local forward = particleAngles.Forward();
        particleOrigin = particleOrigin + (forward * 32.0);
    }
    
    // Create particle effect parented to weapon
    local particle = SpawnEntityFromTable("info_particle_system", {
        origin = particleOrigin,
        angles = particleAngles,
        effect_name = AIRBLAST_PARTICLE,
        start_active = 1
    });
    
    if (particle) {
        // Parent to weapon if possible
        if (attachmentId > 0) {
            particle.SetParent(weapon, "muzzle");
        }
        EntFireByHandle(particle, "Kill", "", 1.0, null, null);
    }
}

// Process airblast hitbox and affect entities
function ProcessAirblastHitbox(player, weapon, flags, scale, shouldDestroy = false) {
    if (!player || !player.IsValid()) return;
    
    local origin = player.EyePosition();
    local angles = player.EyeAngles();
    local forward = angles.Forward();
    
    // Calculate airblast box dimensions
    local blastSize = Vector(128.0, 128.0, 64.0) * scale;
    local blastDist = 128.0 * scale;
    
    // Box center is in front of player
    local boxCenter = origin + (forward * blastDist);
    
    // Find all entities in the airblast box
    local mins = boxCenter - blastSize;
    local maxs = boxCenter + blastSize;
    
    // Check players
    local ent = null;
    while ((ent = Entities.FindByClassnameWithin(ent, "player", boxCenter, blastDist * 2)) != null) {
        if (!ent.IsValid() || ent == player) continue;
        if (ent.GetHealth() <= 0) continue;
        
        // Check if entity is in the box and in front of player
        if (IsInAirblastBox(player, ent, origin, forward, boxCenter, blastSize)) {
            ProcessAirblastPlayer(player, ent, weapon, flags, forward, angles);
        }
    }
    
    // Check projectiles
    if (flags & AB_REFLECT) {
        ProcessAirblastProjectiles(player, weapon, flags, origin, forward, boxCenter, blastSize, shouldDestroy);
    }
}

// Check if entity is within airblast box
function IsInAirblastBox(player, target, origin, forward, boxCenter, blastSize) {
    if (!target || !target.IsValid()) return false;
    
    local targetPos = target.GetCenter();
    
    // Check if in front of player
    local toTarget = targetPos - origin;
    local dot = toTarget.Dot(forward);
    if (dot < 0) return false;
    
    // Check if within box bounds (simple sphere check for now)
    local dist = (targetPos - boxCenter).Length();
    return dist <= blastSize.Length();
}

// Process airblast effect on a player
function ProcessAirblastPlayer(attacker, victim, weapon, flags, forward, angles) {
    if (!attacker || !victim) return;
    
    local attackerIdx = attacker.entindex();
    local victimIdx = victim.entindex();
    
    // Check if already airblasted this player
    if (attackerIdx in _airblasted) {
        foreach (idx in _airblasted[attackerIdx]) {
            if (idx == victimIdx) return;
        }
    }
    
    local sameTeam = (victim.GetTeam() == attacker.GetTeam());
    
    // Push enemy players
    if ((flags & AB_PUSH) && !sameTeam) {
        // Calculate push direction
        local victimPos = victim.GetCenter();
        local attackerPos = attacker.GetCenter();
        local toVictim = victimPos - attackerPos;
        toVictim.Norm();
        
        // Check if victim is centered enough in the airblast
        local toVictim2D = Vector(toVictim.x, toVictim.y, 0);
        toVictim2D.Norm();
        local forward2D = Vector(forward.x, forward.y, 0);
        forward2D.Norm();
        
        local dot = toVictim2D.Dot(forward2D);
        
        if (dot >= AIRBLAST_DOT_THRESHOLD) {
            // Calculate push direction (limit upward angle)
            local pushAngles = Vector(angles.x, angles.y, angles.z);
            pushAngles.x = min(-45.0, pushAngles.x);
            
            // Apply push force
            local pushDir = pushAngles.Forward();
            pushDir.Norm();
            local velocity = pushDir * AIRBLAST_PUSH_FORCE;
            
            // Apply velocity to victim
            victim.SetAbsVelocity(velocity);
            
            // Play sound
            EmitSoundOn(AIRBLAST_PLAYER_SOUND, victim);
            
            // Mark as airblasted
            if (!(attackerIdx in _airblasted)) {
                _airblasted[attackerIdx] <- [];
            }
            _airblasted[attackerIdx].append(victimIdx);
        }
    }
    
    // Extinguish teammates (or anyone if not restricting to team)
    if (flags & AB_EXTINGUISH) {
        if (sameTeam && victim.InCond(22)) { // TF_COND_BURNING
            victim.RemoveCond(22);
            EmitSoundOn(EXTINGUISH_SOUND, victim);
        }
    }
}

// Process projectile reflection/deletion
function ProcessAirblastProjectiles(player, weapon, flags, origin, forward, boxCenter, blastSize, shouldDestroy = false) {
    // Find projectiles in area
    local projectileClasses = [
        "tf_projectile_rocket",
        "tf_projectile_pipe",
        "tf_projectile_pipe_remote",
        "tf_projectile_arrow",
        "tf_projectile_flare",
        "tf_projectile_jar",
        "tf_projectile_jar_milk",
        "tf_projectile_energy_ball",
        "tf_projectile_healing_bolt"
    ];
    
    foreach (className in projectileClasses) {
        local proj = null;
        while ((proj = Entities.FindByClassnameWithin(proj, className, boxCenter, blastSize.Length())) != null) {
            if (!proj.IsValid()) continue;
            
            // Check team
            if (proj.GetTeam() == player.GetTeam()) continue;
            
            // Check if in box
            if (!IsInAirblastBox(player, proj, origin, forward, boxCenter, blastSize)) continue;
            
            // Reflect or destroy projectile
            AirblastProjectile(player, proj, weapon, forward, shouldDestroy);
        }
    }
}

// Reflect or destroy a projectile
function AirblastProjectile(player, projectile, weapon, direction, shouldDestroy = false) {
    if (!projectile || !projectile.IsValid()) return;
    
    local projPos = projectile.GetOrigin();
    
    if (shouldDestroy) {
        // Create deletion particle
        DispatchParticleEffect(DELETE_PARTICLE, projPos, Vector(0, 0, 0));
        
        // Play sound
        EmitSoundOn(DELETE_AIRBLAST_SOUND, projectile);
        
        // Remove projectile
        projectile.Kill();
    } else {
        // Create deflection particle
        DispatchParticleEffect(DEFLECT_PARTICLE, projPos, Vector(0, 0, 0));
        
        // Play sound
        EmitSoundOn(DEFLECT_SOUND, projectile);
        
        // Change ownership and direction
        projectile.SetTeam(player.GetTeam());
        NetProps.SetPropEntity(projectile, "m_hOwnerEntity", player);
        
        // Set mini-crit damage
        try {
            NetProps.SetPropBool(projectile, "m_bCritical", false);
            NetProps.SetPropInt(projectile, "m_iDeflected", 1); // Mark as deflected for mini-crit
        } catch (e) {}
        
        // Reflect velocity
        local speed = projectile.GetAbsVelocity().Length();
        local newVelocity = direction * speed;
        projectile.SetAbsVelocity(newVelocity);
    }
}

// ============================================================================
// Think Processing
// ============================================================================

function Think() {
    local currentTime = Time();
    
    // Check all players for Mouse 2 press
    local player = null;
    while ((player = Entities.FindByClassname(player, "player")) != null) {
        if (!player.IsValid() || player.GetHealth() <= 0) continue;
        
        local playerIdx = player.entindex();
        local buttons = player.GetButtons();
        
        // Get last button state
        local lastButtons = 0;
        if (playerIdx in _lastButtons) {
            lastButtons = _lastButtons[playerIdx];
        }
        
        // Check if we're currently airblasting
        local isAirblasting = false;
        if (playerIdx in _airblastEndTime) {
            isAirblasting = (currentTime <= _airblastEndTime[playerIdx]);
        }
        
        // Disable Mouse 1 (primary attack) while airblasting
        if (isAirblasting) {
            player.DisableButtons(1); // IN_ATTACK = 1
        } else {
            player.EnableButtons(1);
        }
        
        // Check if Mouse 2 was just pressed (not held)
        local attack2Pressed = (buttons & IN_ATTACK2) != 0;
        local attack2WasPressed = (lastButtons & IN_ATTACK2) != 0;
        
        if (attack2Pressed && !attack2WasPressed) {
            // Mouse 2 was just pressed
            local weapon = player.GetActiveWeapon();
            if (weapon && weapon.IsValid()) {
                if (HasCustomAirblast(weapon)) {
                    DoAirblast(player, weapon);
                }
            }
        }
        
        // Store current button state
        _lastButtons[playerIdx] <- buttons;
    }
    
    // Process ongoing airblasts
    foreach (playerIdx, endTime in _airblastEndTime) {
        if (currentTime <= endTime) {
            // Airblast is still active, continue processing
            local player = GetPlayerByIndex(playerIdx);
            if (player && player.IsValid()) {
                local weapon = player.GetActiveWeapon();
                if (weapon && weapon.IsValid()) {
                    // Get flags and scale from weapon attributes
                    local flags = AB_PUSH | AB_EXTINGUISH | AB_REFLECT;
                    local flagsValue = GetWeaponAttribute(weapon, ATTRIB_AIRBLAST_FLAGS, -1.0);
                    if (flagsValue >= 0.0) {
                        flags = flagsValue.tointeger();
                    }
                    local noPushValue = GetWeaponAttribute(weapon, ATTRIB_AIRBLAST_NO_PUSH, 0.0);
                    if (noPushValue != 0.0) {
                        flags = flags & ~AB_PUSH;
                    }
                    
                    local scale = GetWeaponAttribute(weapon, ATTRIB_AIRBLAST_SCALE, DEFAULT_AIRBLAST_SCALE);
                    local shouldDestroy = (GetWeaponAttribute(weapon, ATTRIB_AIRBLAST_DESTROY, 0.0) != 0.0);
                    
                    // Continue processing airblast hitbox
                    ProcessAirblastHitbox(player, weapon, flags, scale, shouldDestroy);
                }
            }
        } else {
            // Airblast ended, clear victims list
            if (playerIdx in _airblasted) {
                _airblasted[playerIdx].clear();
            }
        }
    }
}

// ============================================================================
// Event Handlers
// ============================================================================

function OnPlayerDisconnect(player) {
    if (!player) return;
    local playerIdx = player.entindex();
    
    if (playerIdx in _airblasted) {
        delete _airblasted[playerIdx];
    }
    
    if (playerIdx in _airblastEndTime) {
        delete _airblastEndTime[playerIdx];
    }
    
    if (playerIdx in _lastButtons) {
        delete _lastButtons[playerIdx];
    }
    
    if (playerIdx in _nextAirblastTime) {
        delete _nextAirblastTime[playerIdx];
    }
}

// ============================================================================
// Utility Functions
// ============================================================================

function GetPlayerByIndex(idx) {
    local player = null;
    while ((player = Entities.FindByClassname(player, "player")) != null) {
        if (player.entindex() == idx) {
            return player;
        }
    }
    return null;
}

// ============================================================================
// Public API
// ============================================================================

::AttributeAirblast <- {
    // Core functions
    DoAirblast = function(player, weapon) {
        return ::DoAirblast(player, weapon);
    },
    
    HasCustomAirblast = function(weapon) {
        return ::HasCustomAirblast(weapon);
    },
    
    // Event handlers
    OnPlayerDisconnect = function(player) {
        return ::OnPlayerDisconnect(player);
    },
    
    Think = function() {
        return ::Think();
    }
}

// ============================================================================
// Auto-initialize
// ============================================================================
if (!("_attributeAirblastInitialized" in getroottable())) {
    _attributeAirblastInitialized <- true;
    Initialize();
}
