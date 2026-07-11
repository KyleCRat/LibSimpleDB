dofile("tests/libstub.lua")
dofile("LibSimpleDB-2.0.lua")

local LibSimpleDB = LibStub("LibSimpleDB-2.0")
local iterations = tonumber(arg and arg[1]) or 250000

local defaults = {
    one = 1,
    nested = {
        second = {
            third = {
                fourth = 4,
            },
        },
    },
    fallback = 10,
    color = { r = 0.1, g = 0.2, b = 0.3, a = 1 },
    large = {},
}

for index = 1, 250 do
    defaults.large[index] = {
        enabled = true,
        nested = { value = index },
    }
end

local data = {
    one = 2,
    nested = {
        second = {
            third = {
                fourth = 5,
            },
        },
    },
    write = false,
}

local legacyLargeOverride = {}
for index = 1, 250 do
    legacyLargeOverride[index] = {
        enabled = true,
        nested = { value = index },
    }
end

local db = LibSimpleDB:New(data, defaults)
local legacyStyleDB = LibSimpleDB:New({ large = legacyLargeOverride }, defaults)

local function measure(name, count, callback)
    local warmup = math.min(count, 10000)
    for index = 1, warmup do
        callback(index)
    end

    collectgarbage("collect")
    collectgarbage("stop")
    local memoryBefore = collectgarbage("count")
    local started = os.clock()
    for index = 1, count do
        callback(index)
    end
    local elapsed = os.clock() - started
    local memoryAfter = collectgarbage("count")
    collectgarbage("restart")

    io.write(("%-32s %8.4f s  %+10.3f KiB\n"):format(
        name,
        elapsed,
        memoryAfter - memoryBefore
    ))
end

io.write(("LibSimpleDB-2.0 minor %d, %d primary iterations\n\n"):format(
    LibSimpleDB.MINOR,
    iterations
))

measure("Get one raw key", iterations, function()
    db:Get("one")
end)

measure("Get four raw keys", iterations, function()
    db:Get("nested", "second", "third", "fourth")
end)

measure("Get default fallback", iterations, function()
    db:Get("fallback")
end)

measure("GetRaw four keys", iterations, function()
    db:GetRaw("nested", "second", "third", "fourth")
end)

measure("GetDefault four keys", iterations, function()
    db:GetDefault("nested", "second", "third", "fourth")
end)

measure("GetColor default", iterations, function()
    db:GetColor("color")
end)

measure("Set no callbacks", iterations, function(index)
    db:Set("write", index % 2 == 0)
end)

local exactCallback = function() end
db:RegisterCallback(exactCallback, "write")
measure("Set exact callback", iterations, function(index)
    db:Set("write", index % 2 == 0)
end)
db:UnregisterAllCallbacks()

local treeCallback = function() end
db:RegisterTreeCallback(treeCallback)
measure("Set root tree callback", iterations, function(index)
    db:Set("write", index % 2 == 0)
end)
db:UnregisterAllCallbacks()

measure("IsModified large parent", math.max(1000, math.floor(iterations / 250)), function()
    legacyStyleDB:IsModified("large")
end)

measure("Construct large defaults", math.max(100, math.floor(iterations / 2500)), function()
    LibSimpleDB:New({}, defaults)
end)
