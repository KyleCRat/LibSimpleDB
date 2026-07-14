local suite = {}

local DEFAULT_ITERATIONS = 250000
local DEFAULT_RUNS = 3

local function positiveInteger(value, defaultValue, label)
    if value == nil then
        return defaultValue
    end

    local number = tonumber(value)
    if not number or number < 1 or number ~= math.floor(number) then
        error(("%s must be a positive integer"):format(label), 3)
    end
    return number
end

function suite.ParseOptions(arguments)
    arguments = arguments or {}
    local gcMode = arguments[3] or "stopped"
    if gcMode ~= "stopped" and gcMode ~= "enabled" then
        error("GC mode must be 'stopped' or 'enabled'", 2)
    end
    return {
        iterations = positiveInteger(arguments[1], DEFAULT_ITERATIONS, "iterations"),
        runs = positiveInteger(arguments[2], DEFAULT_RUNS, "runs"),
        gcMode = gcMode,
    }
end

local function buildDefaults()
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
    return defaults
end

local function buildContext(adapter)
    local defaults = buildDefaults()
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

    local largeOverride = {}
    for index = 1, 250 do
        largeOverride[index] = {
            enabled = true,
            nested = { value = index },
        }
    end

    return {
        defaults = defaults,
        db = adapter.new(data, defaults),
        largeDB = adapter.new({ large = largeOverride }, defaults),
    }
end

local function measure(name, count, callback, gcMode)
    local warmup = math.min(count, 10000)
    for index = 1, warmup do
        callback(index)
    end

    collectgarbage("collect")
    if gcMode == "stopped" then
        collectgarbage("stop")
    end
    local memoryBefore = collectgarbage("count")
    local started = os.clock()
    for index = 1, count do
        callback(index)
    end
    local elapsed = os.clock() - started
    local memoryAfter = collectgarbage("count")
    if gcMode == "stopped" then
        collectgarbage("restart")
    end

    return {
        name = name,
        count = count,
        elapsed = elapsed,
        memory = memoryAfter - memoryBefore,
    }
end

local function runOnce(adapter, options)
    local iterations = options.iterations
    local context = buildContext(adapter)
    local db = context.db
    local results = {}

    local function add(name, count, callback)
        results[#results + 1] = measure(name, count, callback, options.gcMode)
    end

    add("Get one raw key", iterations, function()
        db:Get("one")
    end)

    add("Get four raw keys", iterations, function()
        db:Get("nested", "second", "third", "fourth")
    end)

    add("Get default fallback", iterations, function()
        db:Get("fallback")
    end)

    add("GetRaw four keys", iterations, function()
        db:GetRaw("nested", "second", "third", "fourth")
    end)

    add("GetDefault four keys", iterations, function()
        db:GetDefault("nested", "second", "third", "fourth")
    end)

    add("GetColor default", iterations, function()
        db:GetColor("color")
    end)

    add("GetColorDefault", iterations, function()
        db:GetColorDefault("color")
    end)

    add("Set no callbacks", iterations, function(index)
        db:Set("write", index % 2 == 0)
    end)

    local exactCallback = function() end
    adapter.registerExact(db, exactCallback)
    add("Set exact callback", iterations, function(index)
        db:Set("write", index % 2 == 0)
    end)
    adapter.unregisterExact(db, exactCallback)

    local treeCallback = function() end
    adapter.registerTree(db, treeCallback)
    add("Set tree callback", iterations, function(index)
        db:Set("write", index % 2 == 0)
    end)
    adapter.unregisterTree(db, treeCallback)

    add("IsModified large parent", math.max(1000, math.floor(iterations / 250)), function()
        context.largeDB:IsModified("large")
    end)

    add("Construct large defaults", math.max(100, math.floor(iterations / 2500)), function()
        adapter.new({}, context.defaults)
    end)

    return results
end

local function median(values)
    local ordered = {}
    for index = 1, #values do
        ordered[index] = values[index]
    end
    table.sort(ordered)

    local middle = math.floor(#ordered / 2) + 1
    if #ordered % 2 == 1 then
        return ordered[middle]
    end
    return (ordered[middle - 1] + ordered[middle]) / 2
end

local function summarize(allResults)
    local summary = {}
    for resultIndex = 1, #allResults[1] do
        local elapsed = {}
        local memory = {}
        for runIndex = 1, #allResults do
            elapsed[runIndex] = allResults[runIndex][resultIndex].elapsed
            memory[runIndex] = allResults[runIndex][resultIndex].memory
        end

        summary[resultIndex] = {
            name = allResults[1][resultIndex].name,
            count = allResults[1][resultIndex].count,
            elapsed = median(elapsed),
            memory = median(memory),
        }
    end
    summary.gcMode = allResults.gcMode
    return summary
end

local function printResults(results)
    for index = 1, #results do
        local result = results[index]
        io.write(("%-32s %8.4f s  %+10.3f KiB\n"):format(
            result.name,
            result.elapsed,
            result.memory
        ))
    end
end

function suite.Run(adapter, options)
    options = options or suite.ParseOptions()
    local allResults = {}

    io.write(("%s minor %d, %d primary iterations, %d runs, GC %s\n"):format(
        adapter.name,
        adapter.minor,
        options.iterations,
        options.runs,
        options.gcMode
    ))

    for runIndex = 1, options.runs do
        io.write(("\nRun %d of %d\n"):format(runIndex, options.runs))
        allResults[runIndex] = runOnce(adapter, options)
        printResults(allResults[runIndex])
    end

    allResults.gcMode = options.gcMode
    local summary = summarize(allResults)
    io.write(("\nMedian of %d runs\n"):format(options.runs))
    printResults(summary)
    return summary
end

function suite.PrintComparison(legacy, current)
    assert(legacy.gcMode == current.gcMode, "benchmark GC modes differ")
    local memoryHeading = legacy.gcMode == "stopped"
        and "Allocation KiB (1 -> 2)"
        or "Memory delta KiB (1 -> 2)"
    io.write("\nMedian comparison\n")
    io.write(("%-32s %10s %10s %10s %23s\n"):format(
        "Operation",
        "1.0 s",
        "2.0 s",
        "CPU delta",
        memoryHeading
    ))

    for index = 1, #legacy do
        local oldResult = legacy[index]
        local newResult = current[index]
        assert(oldResult.name == newResult.name, "benchmark result order differs")
        local delta = ((newResult.elapsed / oldResult.elapsed) - 1) * 100
        io.write(("%-32s %10.4f %10.4f %+9.1f%% %10.3f -> %-10.3f\n"):format(
            oldResult.name,
            oldResult.elapsed,
            newResult.elapsed,
            delta,
            oldResult.memory,
            newResult.memory
        ))
    end
end

return suite
