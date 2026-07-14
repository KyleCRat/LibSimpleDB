local TAGGED_SOURCE = "1.0.0:LibSimpleDB-1.0.lua"

local function loadTaggedSource()
    local command = ('git show "%s" 2>&1'):format(TAGGED_SOURCE)
    local pipe, message = io.popen(command, "r")
    if not pipe then
        error(("unable to run git show: %s"):format(tostring(message)), 2)
    end

    local source = pipe:read("*a")
    pipe:close()
    local chunk, loadError = loadstring(source, "@1.0.0/LibSimpleDB-1.0.lua")
    if not chunk then
        error(("unable to load %s: %s"):format(TAGGED_SOURCE, tostring(loadError)), 2)
    end
    chunk()
end

dofile("tests/libstub.lua")
loadTaggedSource()
dofile("LibSimpleDB-2.0.lua")

local suite = dofile("benchmarks/suite.lua")
local legacy, legacyMinor = LibStub("LibSimpleDB-1.0")
local current = LibStub("LibSimpleDB-2.0")
local options = suite.ParseOptions(arg)

local legacyAdapter = {
    name = "LibSimpleDB-1.0",
    minor = legacyMinor,
    new = function(data, defaults)
        return legacy:New(data, defaults)
    end,
    registerExact = function(db, callback)
        db:RegisterCallback("write", callback)
    end,
    unregisterExact = function(db, callback)
        db:UnregisterCallback("write", callback)
    end,
    registerTree = function(db, callback)
        db:RegisterCallback("*", callback)
    end,
    unregisterTree = function(db, callback)
        db:UnregisterCallback("*", callback)
    end,
}

local currentAdapter = {
    name = "LibSimpleDB-2.0",
    minor = current.MINOR,
    new = function(data, defaults)
        return current:New(data, defaults)
    end,
    registerExact = function(db, callback)
        db:RegisterCallback(callback, "write")
    end,
    unregisterExact = function(db, callback)
        db:UnregisterCallback(callback, "write")
    end,
    registerTree = function(db, callback)
        db:RegisterTreeCallback(callback)
    end,
    unregisterTree = function(db, callback)
        db:UnregisterTreeCallback(callback)
    end,
}

io.write(("Comparing working tree against git tag source %s\n\n"):format(TAGGED_SOURCE))
local legacySummary = suite.Run(legacyAdapter, options)
io.write("\n")
local currentSummary = suite.Run(currentAdapter, options)
suite.PrintComparison(legacySummary, currentSummary)
