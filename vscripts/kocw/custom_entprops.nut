// ============================================================================
// Custom Entity Properties
// ============================================================================
// Port of custom_entprops.sp for VScript
// Allows storing custom properties on entities using string keys

// Global storage for entity properties
// Structure: entityIndex -> { propertyName -> value }
_entityProperties <- {};

// ============================================================================
// Initialization
// ============================================================================

function Initialize() {
    printl("[CustomEntProps] System initialized");
}

// ============================================================================
// Property Management
// ============================================================================

// Set a custom property on an entity
// entity: The entity handle
// propertyName: String key for the property
// value: Any value (int, float, string, bool, handle, etc.)
function SetCustomProp(entity, propertyName, value) {
    if (!entity || !entity.IsValid()) {
        printl("[CustomEntProps] Error: Invalid entity for SetCustomProp");
        return false;
    }
    
    local entIndex = entity.entindex();
    
    // Create property table for this entity if it doesn't exist
    if (!(entIndex in _entityProperties)) {
        _entityProperties[entIndex] <- {};
    }
    
    // Store the property
    _entityProperties[entIndex][propertyName] <- value;
    return true;
}

// Get a custom property from an entity
// entity: The entity handle
// propertyName: String key for the property
// defaultValue: Value to return if property doesn't exist (optional)
// Returns: The property value, or defaultValue if not found
function GetCustomProp(entity, propertyName, defaultValue = null) {
    if (!entity || !entity.IsValid()) {
        printl("[CustomEntProps] Error: Invalid entity for GetCustomProp");
        return defaultValue;
    }
    
    local entIndex = entity.entindex();
    
    // Check if entity has any properties
    if (!(entIndex in _entityProperties)) {
        return defaultValue;
    }
    
    // Check if property exists
    if (!(propertyName in _entityProperties[entIndex])) {
        return defaultValue;
    }
    
    return _entityProperties[entIndex][propertyName];
}

// Check if an entity has a custom property
// entity: The entity handle
// propertyName: String key for the property
// Returns: true if property exists, false otherwise
function HasCustomProp(entity, propertyName) {
    if (!entity || !entity.IsValid()) {
        return false;
    }
    
    local entIndex = entity.entindex();
    
    if (!(entIndex in _entityProperties)) {
        return false;
    }
    
    return (propertyName in _entityProperties[entIndex]);
}

// Remove a specific custom property from an entity
// entity: The entity handle
// propertyName: String key for the property
// Returns: true if property was removed, false if it didn't exist
function RemoveCustomProp(entity, propertyName) {
    if (!entity || !entity.IsValid()) {
        return false;
    }
    
    local entIndex = entity.entindex();
    
    if (!(entIndex in _entityProperties)) {
        return false;
    }
    
    if (!(propertyName in _entityProperties[entIndex])) {
        return false;
    }
    
    delete _entityProperties[entIndex][propertyName];
    return true;
}

// Remove all custom properties from an entity
// entity: The entity handle
function ClearEntityProps(entity) {
    if (!entity || !entity.IsValid()) {
        return;
    }
    
    local entIndex = entity.entindex();
    
    if (entIndex in _entityProperties) {
        delete _entityProperties[entIndex];
    }
}

// Get all property names for an entity
// entity: The entity handle
// Returns: Array of property name strings
function GetCustomPropNames(entity) {
    local propNames = [];
    
    if (!entity || !entity.IsValid()) {
        return propNames;
    }
    
    local entIndex = entity.entindex();
    
    if (!(entIndex in _entityProperties)) {
        return propNames;
    }
    
    // Collect all property names
    foreach (propName, value in _entityProperties[entIndex]) {
        propNames.append(propName);
    }
    
    return propNames;
}

// Increment a numeric custom property
// entity: The entity handle
// propertyName: String key for the property
// amount: Amount to increment by (default 1)
// Returns: New value after incrementing
function IncrementCustomProp(entity, propertyName, amount = 1) {
    local currentValue = GetCustomProp(entity, propertyName, 0);
    local newValue = currentValue + amount;
    SetCustomProp(entity, propertyName, newValue);
    return newValue;
}

// ============================================================================
// Cleanup (called when entities are destroyed)
// ============================================================================

// Call this when an entity is about to be destroyed
// This prevents memory leaks from accumulating entity data
function OnEntityDestroyed(entity) {
    if (!entity) return;
    
    local entIndex = entity.entindex();
    
    if (entIndex in _entityProperties) {
        delete _entityProperties[entIndex];
    }
}

// Clean up properties for entities that no longer exist
// This is a maintenance function that can be called periodically
function CleanupInvalidEntities() {
    local toRemove = [];
    
    // Find entity indices that no longer have valid entities
    foreach (entIndex, props in _entityProperties) {
        local entity = EntIndexToHScript(entIndex);
        if (!entity || !entity.IsValid()) {
            toRemove.append(entIndex);
        }
    }
    
    // Remove them
    foreach (entIndex in toRemove) {
        delete _entityProperties[entIndex];
    }
    
    if (toRemove.len() > 0) {
        printl("[CustomEntProps] Cleaned up " + toRemove.len() + " invalid entities");
    }
}

// ============================================================================
// Public API
// ============================================================================

::CustomEntProps <- {
    // Set a custom property on an entity
    Set = function(entity, propertyName, value) {
        return ::SetCustomProp(entity, propertyName, value);
    }
    
    // Get a custom property from an entity
    Get = function(entity, propertyName, defaultValue = null) {
        return ::GetCustomProp(entity, propertyName, defaultValue);
    }
    
    // Check if an entity has a custom property
    Has = function(entity, propertyName) {
        return ::HasCustomProp(entity, propertyName);
    }
    
    // Remove a specific property
    Remove = function(entity, propertyName) {
        return ::RemoveCustomProp(entity, propertyName);
    }
    
    // Clear all properties from an entity
    Clear = function(entity) {
        return ::ClearEntityProps(entity);
    }
    
    // Get all property names for an entity
    GetNames = function(entity) {
        return ::GetCustomPropNames(entity);
    }
    
    // Increment a numeric property
    Increment = function(entity, propertyName, amount = 1) {
        return ::IncrementCustomProp(entity, propertyName, amount);
    }
    
    // Cleanup functions
    OnEntityDestroyed = function(entity) {
        return ::OnEntityDestroyed(entity);
    }
    
    CleanupInvalid = function() {
        return ::CleanupInvalidEntities();
    }
}

// ============================================================================
// Auto-initialize
// ============================================================================
if (!("_customEntPropsInitialized" in getroottable())) {
    _customEntPropsInitialized <- true;
    Initialize();
}
