dofile("tests/libstub.lua")
dofile("LibSimpleDB-2.0.lua")

local suite = dofile("benchmarks/suite.lua")
local library = LibStub("LibSimpleDB-2.0")

local adapter = {
    name = "LibSimpleDB-2.0",
    minor = library.MINOR,
    new = function(data, defaults)
        return library:New(data, defaults)
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

suite.Run(adapter, suite.ParseOptions(arg))
