local MAJOR, MINOR = "LibSimpleDB-1.0", 2
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
	return
end

-------------------------------------------------------------------------------
--- Internal Helpers
-------------------------------------------------------------------------------

local function traverse(tbl, keys, startIdx, endIdx)
	local current = tbl
	for i = startIdx, endIdx do
		if type(current) ~= "table" then
			return nil
		end
		current = current[keys[i]]
	end

	return current
end

local function traverseOrCreate(tbl, keys, startIdx, endIdx)
	local current = tbl
	for i = startIdx, endIdx do
		local key = keys[i]
		if type(current[key]) ~= "table" then
			current[key] = {}
		end
		current = current[key]
	end

	return current
end

local function deepCopy(src)
	if type(src) ~= "table" then
		return src
	end

	local copy = {}
	for k, v in pairs(src) do
		copy[k] = deepCopy(v)
	end

	return copy
end

local function deepMerge(dest, src)
	for k, v in pairs(src) do
		if type(v) == "table" and type(dest[k]) == "table" then
			deepMerge(dest[k], v)
		else
			dest[k] = deepCopy(v)
		end
	end
end

local function deepEqual(a, b)
	if type(a) ~= type(b) then
		return false
	end

	if type(a) ~= "table" then
		return a == b
	end

	for k, v in pairs(a) do
		if not deepEqual(v, b[k]) then
			return false
		end
	end

	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end

	return true
end

local function isColorTable(t)
	return type(t) == "table" and t.r ~= nil and t.g ~= nil and t.b ~= nil and t.a ~= nil
end

local function buildDotPath(keys, startIdx, endIdx)
	local parts = {}
	for i = startIdx, endIdx do
		parts[#parts + 1] = tostring(keys[i])
	end

	return table.concat(parts, ".")
end

-------------------------------------------------------------------------------
--- Callback System
-------------------------------------------------------------------------------

local function matchesPattern(pattern, path)
	if pattern == "*" then
		return true
	end

	if pattern == path then
		return true
	end

	-- Wildcard: "health.*" matches "health.font.size"
	if pattern:sub(-2) == ".*" then
		local prefix = pattern:sub(1, -3)
		if path == prefix or path:sub(1, #prefix + 1) == prefix .. "." then
			return true
		end
	end

	return false
end

local CallbackMixin = {}

function CallbackMixin:RegisterCallback(path, callback)
	if type(path) ~= "string" or type(callback) ~= "function" then
		error("Usage: db:RegisterCallback(path, callback) — path must be string, callback must be function", 2)
	end

	self._callbacks[path] = self._callbacks[path] or {}
	self._callbacks[path][callback] = true
end

function CallbackMixin:UnregisterCallback(path, callback)
	if self._callbacks[path] then
		self._callbacks[path][callback] = nil
	end
end

function CallbackMixin:FireCallbacks(dotPath, newValue, oldValue)
	for pattern, callbacks in pairs(self._callbacks) do
		if matchesPattern(pattern, dotPath) then
			for callback in pairs(callbacks) do
				callback(dotPath, newValue, oldValue)
			end
		end
	end
end

-------------------------------------------------------------------------------
--- Lifecycle Event System
-------------------------------------------------------------------------------

local EventMixin = {}

function EventMixin:RegisterEvent(event, callback)
	if type(event) ~= "string" or type(callback) ~= "function" then
		error("Usage: db:RegisterEvent(event, callback)", 2)
	end

	self._events[event] = self._events[event] or {}
	self._events[event][callback] = true
end

function EventMixin:UnregisterEvent(event, callback)
	if self._events[event] then
		self._events[event][callback] = nil
	end
end

function EventMixin:FireEvent(event, ...)
	if not self._events[event] then
		return
	end

	for callback in pairs(self._events[event]) do
		callback(event, self, ...)
	end
end

-------------------------------------------------------------------------------
--- DB Instance Methods
-------------------------------------------------------------------------------

local DBMethods = {}

function DBMethods:Get(...)
	local keys = { ... }
	local numKeys = #keys
	if numKeys == 0 then
		return nil
	end

	local db_value = traverse(self.data, keys, 1, numKeys)
	if db_value ~= nil then
		return db_value
	end

	return traverse(self.defaults, keys, 1, numKeys)
end

function DBMethods:GetRaw(...)
	local keys = { ... }
	if #keys == 0 then
		return nil
	end

	return traverse(self.data, keys, 1, #keys)
end

function DBMethods:Set(...)
	local args = { ... }
	local numArgs = #args
	if numArgs < 2 then
		error("Usage: db:Set(key1, ..., keyN, value) — requires at least one key and a value", 2)
	end

	local value = args[numArgs]
	local parent = traverseOrCreate(self.data, args, 1, numArgs - 2)
	local finalKey = args[numArgs - 1]
	local oldValue = parent[finalKey]
	parent[finalKey] = value

	local dotPath = buildDotPath(args, 1, numArgs - 1)
	self:FireCallbacks(dotPath, value, oldValue)
end

function DBMethods:Delete(...)
	local keys = { ... }
	local numKeys = #keys
	if numKeys == 0 then
		return
	end

	local parent = traverse(self.data, keys, 1, numKeys - 1)
	if type(parent) ~= "table" then
		return
	end

	local finalKey = keys[numKeys]
	local oldValue = parent[finalKey]
	parent[finalKey] = nil

	local dotPath = buildDotPath(keys, 1, numKeys)
	self:FireCallbacks(dotPath, nil, oldValue)
end

function DBMethods:GetDefault(...)
	local keys = { ... }
	if #keys == 0 then
		return nil
	end

	return traverse(self.defaults, keys, 1, #keys)
end

function DBMethods:SetDefault(...)
	local keys = { ... }
	local numKeys = #keys
	if numKeys == 0 then
		return nil
	end

	local default_value = traverse(self.defaults, keys, 1, numKeys)
	if default_value == nil then
		return nil
	end

	if type(default_value) == "table" then
		default_value = deepCopy(default_value)
	end

	local parent = traverseOrCreate(self.data, keys, 1, numKeys - 1)
	local finalKey = keys[numKeys]
	local oldValue = parent[finalKey]
	parent[finalKey] = default_value

	local dotPath = buildDotPath(keys, 1, numKeys)
	self:FireCallbacks(dotPath, default_value, oldValue)

	return default_value
end

function DBMethods:IsModified(...)
	local keys = { ... }
	if #keys == 0 then
		return false
	end

	local db_value = traverse(self.data, keys, 1, #keys)
	if db_value == nil then
		return false
	end

	local default_value = traverse(self.defaults, keys, 1, #keys)

	return not deepEqual(db_value, default_value)
end

function DBMethods:Toggle(...)
	local keys = { ... }
	local numKeys = #keys
	if numKeys == 0 then
		return
	end

	local current = self:Get(unpack(keys))
	local newValue = not current

	local parent = traverseOrCreate(self.data, keys, 1, numKeys - 1)
	local finalKey = keys[numKeys]
	local oldValue = parent[finalKey]
	parent[finalKey] = newValue

	local dotPath = buildDotPath(keys, 1, numKeys)
	self:FireCallbacks(dotPath, newValue, oldValue)

	return newValue
end

function DBMethods:Reset()
	wipe(self.data)
	self:FireEvent("OnReset")
end

function DBMethods:SetData(data)
	if type(data) ~= "table" then
		error("Usage: db:SetData(table)", 2)
	end

	self.data = data
	self:FireEvent("OnDataChanged")
end

-------------------------------------------------------------------------------
--- Color Helpers
-------------------------------------------------------------------------------

function DBMethods:GetColor(...)
	local color = self:Get(...)
	if isColorTable(color) then
		return color.r, color.g, color.b, color.a
	end

	return 1, 1, 1, 1
end

function DBMethods:GetColorDefault(...)
	local keys = { ... }
	local color = traverse(self.defaults, keys, 1, #keys)
	if isColorTable(color) then
		return color.r, color.g, color.b, color.a
	end

	return 1, 1, 1, 1
end

function DBMethods:SetColor(...)
	local args = { ... }
	local numArgs = #args
	if numArgs < 2 then
		error("Usage: db:SetColor(key1, ..., keyN, colorTable)", 2)
	end

	local new_color = args[numArgs]
	if not isColorTable(new_color) then
		error("LibSimpleDB: SetColor: last argument must be a color table {r, g, b, a}", 2)
	end

	local keys = {}
	for i = 1, numArgs - 1 do
		keys[i] = args[i]
	end

	local existing = traverse(self.data, keys, 1, #keys)
	local dotPath = buildDotPath(keys, 1, #keys)
	local oldValue

	if isColorTable(existing) then
		oldValue = { r = existing.r, g = existing.g, b = existing.b, a = existing.a }
		existing.r = new_color.r
		existing.g = new_color.g
		existing.b = new_color.b
		existing.a = new_color.a
	else
		local parent = traverseOrCreate(self.data, keys, 1, #keys - 1)
		oldValue = parent[keys[#keys]]
		parent[keys[#keys]] = {
			r = new_color.r,
			g = new_color.g,
			b = new_color.b,
			a = new_color.a,
		}
	end

	self:FireCallbacks(dotPath, new_color, oldValue)
end

-------------------------------------------------------------------------------
--- RegisterDefaults
-------------------------------------------------------------------------------

function DBMethods:RegisterDefaults(defaults)
	if defaults == nil then
		return
	end

	if type(defaults) ~= "table" then
		error("Usage: db:RegisterDefaults(defaults) — defaults must be a table", 2)
	end

	deepMerge(self.defaults, defaults)
end

-------------------------------------------------------------------------------
--- Constructor
-------------------------------------------------------------------------------

function lib:New(data, defaults)
	if type(data) ~= "table" then
		error("Usage: LibSimpleDB:New(data, defaults) — data must be a table", 2)
	end

	local db = {
		data = data,
		defaults = defaults and deepCopy(defaults) or {},
		_callbacks = {},
		_events = {},
	}

	for k, v in pairs(DBMethods) do
		db[k] = v
	end

	for k, v in pairs(CallbackMixin) do
		db[k] = v
	end

	for k, v in pairs(EventMixin) do
		db[k] = v
	end

	return db
end
