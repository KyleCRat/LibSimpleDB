local TAGGED_SOURCE = "1.0.0:LibSimpleDB-1.0.lua"

local function readFile(path)
    local handle, message = io.open(path, "rb")
    if not handle then
        error(message, 2)
    end
    local contents = handle:read("*a")
    handle:close()
    return contents
end

local function readTaggedSource()
    local command = ('git show "%s" 2>&1'):format(TAGGED_SOURCE)
    local pipe, message = io.popen(command, "r")
    if not pipe then
        error(("unable to run git show: %s"):format(tostring(message)), 2)
    end
    local source = pipe:read("*a")
    pipe:close()
    return source
end

local legacySource = readTaggedSource()
local currentSource = readFile("LibSimpleDB-2.0.lua")

local function loadSource(source, name)
    local chunk, message = loadstring(source, "@" .. name)
    if not chunk then
        error(message, 2)
    end
    chunk()
end

local function verify(legacyFirst)
    dofile("tests/libstub.lua")
    if legacyFirst then
        loadSource(legacySource, "1.0.0/LibSimpleDB-1.0.lua")
        loadSource(currentSource, "LibSimpleDB-2.0.lua")
    else
        loadSource(currentSource, "LibSimpleDB-2.0.lua")
        loadSource(legacySource, "1.0.0/LibSimpleDB-1.0.lua")
    end

    local legacy, legacyMinor = LibStub("LibSimpleDB-1.0")
    local current, currentMinor = LibStub("LibSimpleDB-2.0")
    assert(legacy ~= current, "API families share a library table")
    assert(legacyMinor == 2, "unexpected legacy minor")
    assert(currentMinor == 1, "unexpected current minor")

    local legacyDB = legacy:New({}, { value = 10 })
    local currentDB = current:New({}, { value = 20 })
    legacyDB:Set("value", 11)
    currentDB:Set("value", 21)
    assert(legacyDB:Get("value") == 11, "legacy instance was mutated by 2.0")
    assert(currentDB:Get("value") == 21, "current instance was mutated by 1.0")
end

verify(true)
io.write("ok 1 - tagged 1.0 loads before working-tree 2.0\n")
verify(false)
io.write("ok 2 - working-tree 2.0 loads before tagged 1.0\n")
io.write("\n2 passed, 0 failed\n")
