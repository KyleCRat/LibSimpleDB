local MAJOR, MINOR = "LibSimpleDB-2.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
    return
end

local error = error
local getErrorHandler = geterrorhandler
local next = next
local pairs = pairs
local pcall = pcall
local select = select
local setmetatable = setmetatable
local type = type
local unpack = unpack

local prototype = lib._prototype
if not prototype then
    prototype = {}
    lib._prototype = prototype
end
local methods = {}

local instanceMetatable = lib._instanceMetatable
if not instanceMetatable then
    instanceMetatable = {}
    lib._instanceMetatable = instanceMetatable
end
instanceMetatable.__index = prototype

local exactCallbacksKey = lib._exactCallbacksKey or {}
local treeCallbacksKey = lib._treeCallbacksKey or {}
lib._exactCallbacksKey = exactCallbacksKey
lib._treeCallbacksKey = treeCallbacksKey

local lifecycleEvents = {
    OnDataChanged = true,
    OnDefaultsChanged = true,
    OnReset = true,
}

-------------------------------------------------------------------------------
-- Value and path helpers
-------------------------------------------------------------------------------

local function isPathKey(key)
    local keyType = type(key)
    return keyType == "string" or (keyType == "number" and key == key)
end

local function validatePath(operation, count, ...)
    if count < 1 then
        error(("Usage: db:%s(key1, ...) requires at least one path key"):format(operation), 3)
    end

    for index = 1, count do
        if not isPathKey(select(index, ...)) then
            error(("LibSimpleDB: %s: path key %d must be a string or number"):format(operation, index), 3)
        end
    end
end

local function copyValue(value, ancestors)
    local valueType = type(value)
    if valueType == "nil" or valueType == "boolean" or valueType == "number" or valueType == "string" then
        return value
    end

    if valueType ~= "table" then
        error("LibSimpleDB: values must be SavedVariables-compatible primitives or tables", 3)
    end

    ancestors = ancestors or {}
    if ancestors[value] then
        error("LibSimpleDB: cyclic tables are not supported", 3)
    end
    ancestors[value] = true

    local copy = {}
    for key, child in pairs(value) do
        if not isPathKey(key) then
            error("LibSimpleDB: table keys must be strings or numbers", 3)
        end
        copy[key] = copyValue(child, ancestors)
    end

    ancestors[value] = nil
    return copy
end

local function deepEqual(left, right)
    if type(left) ~= type(right) then
        return false
    end

    if type(left) ~= "table" then
        return left == right
    end

    for key, value in pairs(left) do
        if not deepEqual(value, right[key]) then
            return false
        end
    end

    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end

    return true
end

local function clearTable(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function traverse(root, count, ...)
    local current = root
    for index = 1, count do
        if type(current) ~= "table" then
            return nil
        end
        current = current[select(index, ...)]
    end
    return current
end

local function traverseValidated(root, operation, count, ...)
    if count < 1 then
        error(("Usage: db:%s(key1, ...) requires at least one path key"):format(operation), 3)
    end

    local current = root
    for index = 1, count do
        local key = select(index, ...)
        if not isPathKey(key) then
            error(("LibSimpleDB: %s: path key %d must be a string or number"):format(operation, index), 3)
        end

        if type(current) == "table" then
            current = current[key]
        else
            current = nil
        end
    end
    return current
end

local function getEffective(db, count, ...)
    local value = traverse(db._data, count, ...)
    if value ~= nil then
        return value
    end
    return traverse(db._defaults, count, ...)
end

local function setRaw(root, count, value, ...)
    local current = root
    for index = 1, count - 1 do
        local key = select(index, ...)
        local child = current[key]
        if type(child) ~= "table" then
            child = {}
            current[key] = child
        end
        current = child
    end
    current[select(count, ...)] = value
end

local function removeRaw(current, index, count, ...)
    local key = select(index, ...)
    if index == count then
        if current[key] == nil then
            return false, next(current) == nil
        end
        current[key] = nil
        return true, next(current) == nil
    end

    local child = current[key]
    if type(child) ~= "table" then
        return false, next(current) == nil
    end

    local removed, childIsEmpty = removeRaw(child, index + 1, count, ...)
    if removed and childIsEmpty then
        current[key] = nil
    end
    return removed, next(current) == nil
end

local function mergeDefaults(destination, source)
    for key, value in pairs(source) do
        if type(value) == "table" and type(destination[key]) == "table" then
            mergeDefaults(destination[key], value)
        else
            destination[key] = value
        end
    end
end

-------------------------------------------------------------------------------
-- Callback helpers
-------------------------------------------------------------------------------

local function reportCallbackError(message)
    if type(getErrorHandler) ~= "function" then
        return
    end

    local ok, handler = pcall(getErrorHandler)
    if ok and type(handler) == "function" then
        pcall(handler, message)
    end
end

local function callCallback(callback, ...)
    local ok, message = pcall(callback, ...)
    if not ok then
        reportCallbackError(message)
    end
end

local function getCallbackNode(root, count, create, ...)
    local current = root
    for index = 1, count do
        local key = select(index, ...)
        local child = current[key]
        if not child then
            if not create then
                return nil
            end
            child = {}
            current[key] = child
        end
        current = child
    end
    return current
end

local function addBucketCallbacks(snapshot, bucket)
    if not bucket then
        return
    end
    for callback in pairs(bucket) do
        snapshot[#snapshot + 1] = callback
    end
end

local function dispatchPathCallbacks(db, newValue, oldValue, pathCount, ...)
    if db._callbackCount == 0 then
        return
    end

    local path = {}
    for index = 1, pathCount do
        path[index] = select(index, ...)
    end

    local snapshot = {}
    local node = db._callbackRoot
    addBucketCallbacks(snapshot, node[treeCallbacksKey])

    for index = 1, pathCount do
        node = node[path[index]]
        if not node then
            break
        end
        addBucketCallbacks(snapshot, node[treeCallbacksKey])
    end

    if node then
        addBucketCallbacks(snapshot, node[exactCallbacksKey])
    end

    for index = 1, #snapshot do
        callCallback(snapshot[index], db, newValue, oldValue, unpack(path, 1, pathCount))
    end
end

local function removeCallbackFromTree(node, callback)
    local removed = 0
    local exact = node[exactCallbacksKey]
    if exact and exact[callback] then
        exact[callback] = nil
        removed = removed + 1
    end

    local tree = node[treeCallbacksKey]
    if tree and tree[callback] then
        tree[callback] = nil
        removed = removed + 1
    end

    for key, child in pairs(node) do
        if key ~= exactCallbacksKey and key ~= treeCallbacksKey then
            removed = removed + removeCallbackFromTree(child, callback)
        end
    end
    return removed
end

local function dispatchLifecycle(db, event, ...)
    local callbacks = db._lifecycleCallbacks[event]
    if not callbacks then
        return
    end

    local snapshot = {}
    for callback in pairs(callbacks) do
        snapshot[#snapshot + 1] = callback
    end

    for index = 1, #snapshot do
        callCallback(snapshot[index], db, event, ...)
    end
end

local function writeValue(db, value, pathCount, ...)
    local storedValue = copyValue(value)
    local oldValue = getEffective(db, pathCount, ...)
    local defaultValue = traverse(db._defaults, pathCount, ...)

    if deepEqual(storedValue, defaultValue) then
        setRaw(db._data, pathCount, storedValue, ...)
        removeRaw(db._data, 1, pathCount, ...)
    else
        setRaw(db._data, pathCount, storedValue, ...)
    end

    local newValue = getEffective(db, pathCount, ...)
    if not deepEqual(newValue, oldValue) then
        dispatchPathCallbacks(db, newValue, oldValue, pathCount, ...)
    end
    return newValue
end

local function resetValue(db, pathCount, ...)
    local oldValue = getEffective(db, pathCount, ...)
    removeRaw(db._data, 1, pathCount, ...)
    local newValue = getEffective(db, pathCount, ...)
    if not deepEqual(newValue, oldValue) then
        dispatchPathCallbacks(db, newValue, oldValue, pathCount, ...)
    end
    return newValue
end

-------------------------------------------------------------------------------
-- Reads and writes
-------------------------------------------------------------------------------

function methods:Get(...)
    local count = select("#", ...)

    if count == 1 then
        validatePath("Get", count, ...)
        local key = ...
        local value = self._data[key]
        if value ~= nil then
            return value
        end
        return self._defaults[key]
    end

    local value = traverseValidated(self._data, "Get", count, ...)
    if value ~= nil then
        return value
    end
    return traverse(self._defaults, count, ...)
end

function methods:GetRaw(...)
    local count = select("#", ...)

    if count == 1 then
        validatePath("GetRaw", count, ...)
        return self._data[(...)]
    end
    return traverseValidated(self._data, "GetRaw", count, ...)
end

function methods:GetDefault(...)
    local count = select("#", ...)

    if count == 1 then
        validatePath("GetDefault", count, ...)
        return self._defaults[(...)]
    end
    return traverseValidated(self._defaults, "GetDefault", count, ...)
end

function methods:GetCopy(...)
    local count = select("#", ...)
    local value = traverseValidated(self._data, "GetCopy", count, ...)
    if value == nil then
        value = traverse(self._defaults, count, ...)
    end
    return copyValue(value)
end

function methods:Set(...)
    local argumentCount = select("#", ...)
    if argumentCount < 2 then
        error("Usage: db:Set(key1, ..., keyN, value) requires a path and value", 2)
    end

    local pathCount = argumentCount - 1
    validatePath("Set", pathCount, ...)
    local value = select(argumentCount, ...)
    if value == nil then
        return resetValue(self, pathCount, ...)
    end

    return writeValue(self, value, pathCount, ...)
end

function methods:ResetPath(...)
    local count = select("#", ...)
    validatePath("ResetPath", count, ...)
    return resetValue(self, count, ...)
end

methods.Delete = methods.ResetPath

function methods:IsModified(...)
    local count = select("#", ...)
    local rawValue = traverseValidated(self._data, "IsModified", count, ...)
    if rawValue == nil then
        return false
    end
    return not deepEqual(rawValue, traverse(self._defaults, count, ...))
end

function methods:Toggle(...)
    local count = select("#", ...)
    validatePath("Toggle", count, ...)
    return writeValue(self, not getEffective(self, count, ...), count, ...)
end

function methods:Reset()
    clearTable(self._data)
    dispatchLifecycle(self, "OnReset")
    return self._data
end

function methods:SetData(data)
    if type(data) ~= "table" then
        error("Usage: db:SetData(data) requires a table", 2)
    end
    if data == self._data then
        return data
    end

    local oldData = self._data
    self._data = data
    dispatchLifecycle(self, "OnDataChanged", data, oldData)
    return data
end

function methods:RegisterDefaults(defaults)
    if defaults == nil then
        return self._defaults
    end
    if type(defaults) ~= "table" then
        error("Usage: db:RegisterDefaults(defaults) requires a table or nil", 2)
    end

    mergeDefaults(self._defaults, copyValue(defaults))
    dispatchLifecycle(self, "OnDefaultsChanged", self._defaults)
    return self._defaults
end

-------------------------------------------------------------------------------
-- Color helpers
-------------------------------------------------------------------------------

local function isColorComponent(value)
    return type(value) == "number" and value >= 0 and value <= 1
end

local function isColorTable(value)
    return type(value) == "table"
        and isColorComponent(value.r)
        and isColorComponent(value.g)
        and isColorComponent(value.b)
        and isColorComponent(value.a)
end

local function unpackColor(value)
    if isColorTable(value) then
        return value.r, value.g, value.b, value.a
    end
    return 1, 1, 1, 1
end

function methods:GetColor(...)
    local count = select("#", ...)
    if count == 1 then
        validatePath("GetColor", count, ...)
        local key = ...
        local value = self._data[key]
        if value == nil then
            value = self._defaults[key]
        end
        return unpackColor(value)
    end

    local value = traverseValidated(self._data, "GetColor", count, ...)
    if value == nil then
        value = traverse(self._defaults, count, ...)
    end
    return unpackColor(value)
end

function methods:GetColorDefault(...)
    local count = select("#", ...)
    if count == 1 then
        validatePath("GetColorDefault", count, ...)
        return unpackColor(self._defaults[(...)])
    end
    return unpackColor(traverseValidated(self._defaults, "GetColorDefault", count, ...))
end

function methods:SetColor(...)
    local argumentCount = select("#", ...)
    if argumentCount < 2 then
        error("Usage: db:SetColor(key1, ..., keyN, color) requires a path and color table", 2)
    end

    local pathCount = argumentCount - 1
    validatePath("SetColor", pathCount, ...)
    local color = select(argumentCount, ...)
    if not isColorTable(color) then
        error("LibSimpleDB: SetColor: color must contain numeric r, g, b, and a values from 0 to 1", 2)
    end

    local storedColor = {
        r = color.r,
        g = color.g,
        b = color.b,
        a = color.a,
    }
    return writeValue(self, storedColor, pathCount, ...)
end

-------------------------------------------------------------------------------
-- Structured path callbacks
-------------------------------------------------------------------------------

function methods:RegisterCallback(callback, ...)
    if type(callback) ~= "function" then
        error("Usage: db:RegisterCallback(callback, key1, ...) requires a function", 2)
    end

    local count = select("#", ...)
    validatePath("RegisterCallback", count, ...)
    local node = getCallbackNode(self._callbackRoot, count, true, ...)
    local callbacks = node[exactCallbacksKey]
    if not callbacks then
        callbacks = {}
        node[exactCallbacksKey] = callbacks
    end
    if not callbacks[callback] then
        callbacks[callback] = true
        self._callbackCount = self._callbackCount + 1
    end
    return callback
end

function methods:RegisterTreeCallback(callback, ...)
    if type(callback) ~= "function" then
        error("Usage: db:RegisterTreeCallback(callback, ...) requires a function", 2)
    end

    local count = select("#", ...)
    if count > 0 then
        validatePath("RegisterTreeCallback", count, ...)
    end
    local node = getCallbackNode(self._callbackRoot, count, true, ...)
    local callbacks = node[treeCallbacksKey]
    if not callbacks then
        callbacks = {}
        node[treeCallbacksKey] = callbacks
    end
    if not callbacks[callback] then
        callbacks[callback] = true
        self._callbackCount = self._callbackCount + 1
    end
    return callback
end

local function unregisterPathCallback(db, callback, bucketKey, operation, ...)
    if type(callback) ~= "function" then
        error(("Usage: db:%s(callback, ...) requires a function"):format(operation), 3)
    end

    local count = select("#", ...)
    if bucketKey == exactCallbacksKey or count > 0 then
        validatePath(operation, count, ...)
    end
    local node = getCallbackNode(db._callbackRoot, count, false, ...)
    local callbacks = node and node[bucketKey]
    if not callbacks or not callbacks[callback] then
        return false
    end

    callbacks[callback] = nil
    db._callbackCount = db._callbackCount - 1
    return true
end

function methods:UnregisterCallback(callback, ...)
    return unregisterPathCallback(self, callback, exactCallbacksKey, "UnregisterCallback", ...)
end

function methods:UnregisterTreeCallback(callback, ...)
    return unregisterPathCallback(self, callback, treeCallbacksKey, "UnregisterTreeCallback", ...)
end

function methods:UnregisterAllCallbacks(callback)
    if callback == nil then
        self._callbackRoot = {}
        self._callbackCount = 0
        return
    end
    if type(callback) ~= "function" then
        error("Usage: db:UnregisterAllCallbacks([callback])", 2)
    end

    local removed = removeCallbackFromTree(self._callbackRoot, callback)
    self._callbackCount = self._callbackCount - removed
end

-------------------------------------------------------------------------------
-- Lifecycle callbacks
-------------------------------------------------------------------------------

function methods:RegisterLifecycleCallback(event, callback)
    if not lifecycleEvents[event] or type(callback) ~= "function" then
        error("Usage: db:RegisterLifecycleCallback(event, callback) requires a supported event and function", 2)
    end

    local callbacks = self._lifecycleCallbacks[event]
    if not callbacks then
        callbacks = {}
        self._lifecycleCallbacks[event] = callbacks
    end
    callbacks[callback] = true
    return callback
end

function methods:UnregisterLifecycleCallback(event, callback)
    local callbacks = self._lifecycleCallbacks[event]
    if not callbacks or not callbacks[callback] then
        return false
    end
    callbacks[callback] = nil
    return true
end

function methods:UnregisterAllLifecycleCallbacks(callback)
    if callback == nil then
        self._lifecycleCallbacks = {}
        return
    end
    if type(callback) ~= "function" then
        error("Usage: db:UnregisterAllLifecycleCallbacks([callback])", 2)
    end

    for _, callbacks in pairs(self._lifecycleCallbacks) do
        callbacks[callback] = nil
    end
end

-------------------------------------------------------------------------------
-- Library API
-------------------------------------------------------------------------------

for key in pairs(prototype) do
    prototype[key] = nil
end
for key, method in pairs(methods) do
    prototype[key] = method
end

lib.MAJOR = MAJOR
lib.MINOR = MINOR

function lib:GetVersion()
    return MAJOR, MINOR
end

function lib:New(data, defaults)
    if type(data) ~= "table" then
        error("Usage: LibSimpleDB:New(data, defaults) requires a data table", 2)
    end
    if defaults ~= nil and type(defaults) ~= "table" then
        error("Usage: LibSimpleDB:New(data, defaults) requires defaults to be a table or nil", 2)
    end

    return setmetatable({
        _data = data,
        _defaults = defaults and copyValue(defaults) or {},
        _callbackRoot = {},
        _callbackCount = 0,
        _lifecycleCallbacks = {},
    }, instanceMetatable)
end
