local tests = {}
local passed = 0
local failed = 0
local callbackErrors = {}

_G.geterrorhandler = function()
    return function(message)
        callbackErrors[#callbackErrors + 1] = tostring(message)
    end
end

local function test(name, callback)
    tests[#tests + 1] = { name = name, callback = callback }
end

local function fail(message, level)
    error(message, (level or 1) + 1)
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        fail((message or "values differ") .. (": expected %s, got %s"):format(tostring(expected), tostring(actual)), 2)
    end
end

local function assertNil(actual, message)
    assertEqual(actual, nil, message)
end

local function assertTrue(actual, message)
    assertEqual(actual, true, message)
end

local function assertFalse(actual, message)
    assertEqual(actual, false, message)
end

local function assertDeepEqual(actual, expected, message)
    if type(actual) ~= type(expected) then
        fail(message or "value types differ", 2)
    end
    if type(actual) ~= "table" then
        assertEqual(actual, expected, message)
        return
    end

    for key, value in pairs(actual) do
        assertDeepEqual(value, expected[key], message)
    end
    for key in pairs(expected) do
        if actual[key] == nil then
            fail(message or ("missing key %s"):format(tostring(key)), 2)
        end
    end
end

local function assertError(callback, pattern)
    local ok, message = pcall(callback)
    if ok then
        fail("expected an error", 2)
    end
    if pattern and not tostring(message):find(pattern, 1, true) then
        fail(("expected error containing %q, got %q"):format(pattern, tostring(message)), 2)
    end
end

local function readFile(path)
    local handle, message = io.open(path, "rb")
    if not handle then
        error(message, 2)
    end
    local contents = handle:read("*a")
    handle:close()
    return contents
end

local librarySource = readFile("LibSimpleDB-2.0.lua")

local function loadLibrary(minor)
    local source = librarySource
    if minor then
        local replacements
        source, replacements = source:gsub(
            'local MAJOR, MINOR = "LibSimpleDB%-2%.0", 1',
            ('local MAJOR, MINOR = "LibSimpleDB-2.0", %d'):format(minor),
            1
        )
        assertEqual(replacements, 1, "failed to replace simulated library minor")
    end

    local chunk, message = loadstring(source, "@LibSimpleDB-2.0.lua")
    if not chunk then
        error(message, 2)
    end
    chunk()
    return LibStub("LibSimpleDB-2.0")
end

local function freshLibrary(minor)
    dofile("tests/libstub.lua")
    callbackErrors = {}
    return loadLibrary(minor or 1)
end

test("reports its API family and release minor", function()
    local library = freshLibrary()
    local major, minor = library:GetVersion()
    assertEqual(major, "LibSimpleDB-2.0")
    assertEqual(minor, 1)
    assertEqual(library.MAJOR, major)
    assertEqual(library.MINOR, minor)
end)

test("validates constructor arguments", function()
    local library = freshLibrary()
    assertError(function() library:New(nil) end, "data table")
    assertError(function() library:New({}, false) end, "defaults")
end)

test("reads raw values and default fallbacks without losing falsey values", function()
    local db = freshLibrary():New({ enabled = false, count = 0, label = "" }, {
        enabled = true,
        count = 4,
        label = "default",
        fallback = "yes",
    })

    assertFalse(db:Get("enabled"))
    assertEqual(db:Get("count"), 0)
    assertEqual(db:Get("label"), "")
    assertEqual(db:Get("fallback"), "yes")
    assertNil(db:Get("missing"))
    assertFalse(db:GetRaw("enabled"))
    assertNil(db:GetRaw("fallback"))
    assertEqual(db:GetDefault("count"), 4)
end)

test("supports deep string and numeric paths", function()
    local db = freshLibrary():New({}, { profiles = { [2] = { scale = 1.25 } } })
    assertEqual(db:Get("profiles", 2, "scale"), 1.25)
    assertEqual(db:Set("profiles", 2, "scale", 1.5), 1.5)
    assertEqual(db:GetRaw("profiles", 2, "scale"), 1.5)
end)

test("applies defaults per requested path without merging returned tables", function()
    local rawPanel = { scale = 1.5 }
    local db = freshLibrary():New({ panel = rawPanel }, {
        panel = { scale = 1, width = 200 },
    })
    assertEqual(db:Get("panel"), rawPanel)
    assertNil(db:Get("panel").width)
    assertEqual(db:Get("panel", "width"), 200)
end)

test("deep reads fall back after scalar raw intermediates", function()
    local db = freshLibrary():New({ panel = "legacy" }, {
        panel = { scale = 1 },
    })
    assertEqual(db:Get("panel", "scale"), 1)
    assertNil(db:GetRaw("panel", "scale"))
    assertEqual(db:GetDefault("panel", "scale"), 1)
end)

test("replaces scalar intermediate raw values during nested writes", function()
    local data = { display = "legacy" }
    local db = freshLibrary():New(data)
    db:Set("display", "font", "size", 14)
    assertEqual(data.display.font.size, 14)
end)

test("default-valued nested writes clear scalar intermediate overrides", function()
    local data = { display = "legacy" }
    local db = freshLibrary():New(data, { display = { scale = 1 } })
    db:Set("display", "scale", 1)
    assertNil(data.display)
    assertEqual(db:Get("display", "scale"), 1)
end)

test("rejects missing paths, nil keys, and nil Set values without mutation", function()
    local data = {}
    local db = freshLibrary():New(data)
    assertError(function() db:Get() end, "at least one path key")
    assertError(function() db:Get("missing", nil, "value") end, "path key 2")
    assertError(function() db:GetRaw("missing", nil, "value") end, "path key 2")
    assertError(function() db:GetDefault("missing", nil, "value") end, "path key 2")
    assertError(function() db:GetCopy("missing", nil, "value") end, "path key 2")
    assertError(function() db:GetColor("missing", nil, "value") end, "path key 2")
    assertError(function() db:GetColorDefault("missing", nil, "value") end, "path key 2")
    assertError(function() db:Set("a", nil, "value") end, "path key 2")
    assertError(function() db:Set("a", "b", nil) end, "must not be nil")
    assertNil(next(data))
end)

test("copies constructor defaults and Set table inputs", function()
    local defaults = { panel = { width = 100 } }
    local input = { alpha = 0.5 }
    local db = freshLibrary():New({}, defaults)
    defaults.panel.width = 200
    assertEqual(db:Get("panel", "width"), 100)

    db:Set("style", input)
    input.alpha = 1
    assertEqual(db:Get("style").alpha, 0.5)
end)

test("provides detached copies for callback-safe table editing", function()
    local db = freshLibrary():New({}, { panel = { width = 100 } })
    local copy = db:GetCopy("panel")
    copy.width = 140
    assertEqual(db:Get("panel", "width"), 100)
    db:Set("panel", copy)
    assertEqual(db:Get("panel", "width"), 140)
end)

test("normalizes values equal to defaults and prunes empty raw parents", function()
    local data = {}
    local db = freshLibrary():New(data, { panel = { scale = 1 } })
    db:Set("panel", "scale", 1.5)
    assertTrue(db:IsModified("panel", "scale"))
    db:Set("panel", "scale", 1)
    assertFalse(db:IsModified("panel", "scale"))
    assertNil(data.panel)
end)

test("ResetPath and Delete remove overrides and fall back to defaults", function()
    local data = {}
    local db = freshLibrary():New(data, { nested = { value = 10 } })
    db:Set("nested", "value", 20)
    assertEqual(db:ResetPath("nested", "value"), 10)
    assertNil(data.nested)
    db:Set("nested", "value", 30)
    assertEqual(db:Delete("nested", "value"), 10)
    assertNil(data.nested)
end)

test("ResetPath callbacks report effective values and ignore missing overrides", function()
    local db = freshLibrary():New({}, { value = 10 })
    local calls = {}
    db:RegisterCallback(function(_, newValue, oldValue)
        calls[#calls + 1] = { newValue, oldValue }
    end, "value")

    db:Set("value", 20)
    db:ResetPath("value")
    db:ResetPath("value")
    assertEqual(#calls, 2)
    assertEqual(calls[1][1], 20)
    assertEqual(calls[1][2], 10)
    assertEqual(calls[2][1], 10)
    assertEqual(calls[2][2], 20)
end)

test("resetting a missing leaf preserves sibling raw data", function()
    local data = { panel = { locked = true } }
    local db = freshLibrary():New(data, { panel = { scale = 1 } })
    local calls = 0
    db:RegisterCallback(function() calls = calls + 1 end, "panel", "scale")
    assertEqual(db:ResetPath("panel", "scale"), 1)
    assertTrue(data.panel.locked)
    assertEqual(calls, 0)
end)

test("Toggle writes the inverse of effective truthiness", function()
    local db = freshLibrary():New({}, { enabled = false, mode = "shown" })
    assertTrue(db:Toggle("enabled"))
    assertFalse(db:Toggle("mode"))
end)

test("RegisterDefaults copies input and overwrites conflicting defaults", function()
    local incoming = { panel = { width = 120, height = 40 } }
    local db = freshLibrary():New({}, { panel = { width = 100 }, enabled = true })
    db:RegisterDefaults(incoming)
    incoming.panel.width = 200
    assertEqual(db:Get("panel", "width"), 120)
    assertEqual(db:Get("panel", "height"), 40)
    assertTrue(db:Get("enabled"))
end)

test("color helpers validate, copy, and fall back consistently", function()
    local db = freshLibrary():New({ malformed = { r = 1 } }, {
        accent = { r = 0.1, g = 0.2, b = 0.3, a = 0.4 },
        malformedDefault = { r = 1 },
    })
    local r, g, b, a = db:GetColor("accent")
    assertEqual(r, 0.1)
    assertEqual(g, 0.2)
    assertEqual(b, 0.3)
    assertEqual(a, 0.4)

    r, g, b, a = db:GetColorDefault("accent")
    assertEqual(r, 0.1)
    assertEqual(g, 0.2)
    assertEqual(b, 0.3)
    assertEqual(a, 0.4)

    r, g, b, a = db:GetColor("malformed")
    assertEqual(r, 1)
    assertEqual(g, 1)
    assertEqual(b, 1)
    assertEqual(a, 1)

    r, g, b, a = db:GetColorDefault("malformedDefault")
    assertEqual(r, 1)
    assertEqual(g, 1)
    assertEqual(b, 1)
    assertEqual(a, 1)

    local color = { r = 0.8, g = 0.7, b = 0.6, a = 0.5 }
    db:SetColor("accent", color)
    color.r = 0
    r = db:GetColor("accent")
    assertEqual(r, 0.8)
    assertError(function()
        db:SetColor("accent", { r = 2, g = 0, b = 0, a = 1 })
    end, "from 0 to 1")
end)

test("exact callbacks receive effective values and typed path keys", function()
    local db = freshLibrary():New({}, { rows = { [1] = "default" } })
    local calls = {}
    local function callback(instance, newValue, oldValue, ...)
        calls[#calls + 1] = { instance, newValue, oldValue, ... }
    end

    db:RegisterCallback(callback, "rows", 1)
    db:Set("rows", 1, "updated")
    assertEqual(#calls, 1)
    assertEqual(calls[1][1], db)
    assertEqual(calls[1][2], "updated")
    assertEqual(calls[1][3], "default")
    assertEqual(calls[1][4], "rows")
    assertEqual(calls[1][5], 1)
end)

test("structured paths distinguish dotted, numeric, and string keys", function()
    local db = freshLibrary():New({})
    local dotted, numeric, stringKey = 0, 0, 0
    db:RegisterCallback(function() dotted = dotted + 1 end, "a.b")
    db:RegisterCallback(function() numeric = numeric + 1 end, 1)
    db:RegisterCallback(function() stringKey = stringKey + 1 end, "1")
    db:Set("a.b", true)
    db:Set(1, true)
    db:Set("1", true)
    assertEqual(dotted, 1)
    assertEqual(numeric, 1)
    assertEqual(stringKey, 1)
end)

test("tree callbacks match roots and descendants", function()
    local db = freshLibrary():New({})
    local rootCalls, panelCalls, exactCalls = 0, 0, 0
    db:RegisterTreeCallback(function() rootCalls = rootCalls + 1 end)
    db:RegisterTreeCallback(function() panelCalls = panelCalls + 1 end, "panel")
    db:RegisterCallback(function() exactCalls = exactCalls + 1 end, "panel", "scale")
    db:Set("panel", "scale", 1.2)
    db:Set("other", true)
    assertEqual(rootCalls, 2)
    assertEqual(panelCalls, 1)
    assertEqual(exactCalls, 1)
end)

test("unchanged effective values do not fire path callbacks", function()
    local db = freshLibrary():New({}, { scale = 1 })
    local calls = 0
    db:RegisterCallback(function() calls = calls + 1 end, "scale")
    db:Set("scale", 1)
    db:ResetPath("scale")
    assertEqual(calls, 0)
end)

test("callback registration changes apply after the current snapshot", function()
    local db = freshLibrary():New({})
    local firstCalls, removedCalls, addedCalls = 0, 0, 0
    local removed
    local added = function() addedCalls = addedCalls + 1 end
    local first = function(instance)
        firstCalls = firstCalls + 1
        instance:UnregisterCallback(removed, "value")
        instance:RegisterCallback(added, "value")
    end
    removed = function() removedCalls = removedCalls + 1 end

    db:RegisterCallback(first, "value")
    db:RegisterCallback(removed, "value")
    db:Set("value", 1)
    assertEqual(firstCalls, 1)
    assertEqual(removedCalls, 1)
    assertEqual(addedCalls, 0)
    db:Set("value", 2)
    assertEqual(firstCalls, 2)
    assertEqual(removedCalls, 1)
    assertEqual(addedCalls, 1)
end)

test("callback errors are reported without stopping later callbacks", function()
    local db = freshLibrary():New({})
    local laterCalls = 0
    db:RegisterCallback(function() error("expected callback failure") end, "value")
    db:RegisterCallback(function() laterCalls = laterCalls + 1 end, "value")
    db:Set("value", 1)
    assertEqual(laterCalls, 1)
    assertEqual(#callbackErrors, 1)
    assertTrue(callbackErrors[1]:find("expected callback failure", 1, true) ~= nil)
end)

test("duplicate registration is idempotent and unregister-all is supported", function()
    local db = freshLibrary():New({})
    local calls = 0
    local callback = function() calls = calls + 1 end
    db:RegisterCallback(callback, "value")
    db:RegisterCallback(callback, "value")
    db:Set("value", 1)
    assertEqual(calls, 1)
    db:UnregisterAllCallbacks(callback)
    db:Set("value", 2)
    assertEqual(calls, 1)
end)

test("one callback runs once per matching subscription", function()
    local db = freshLibrary():New({})
    local calls = 0
    local callback = function() calls = calls + 1 end
    db:RegisterTreeCallback(callback)
    db:RegisterTreeCallback(callback, "panel")
    db:RegisterCallback(callback, "panel", "scale")
    db:Set("panel", "scale", 1)
    assertEqual(calls, 3)

    db:UnregisterAllCallbacks(callback)
    db:Set("panel", "scale", 2)
    assertEqual(calls, 3)
end)

test("exact and tree callbacks unregister independently", function()
    local db = freshLibrary():New({})
    local exactCalls, treeCalls = 0, 0
    local exact = function() exactCalls = exactCalls + 1 end
    local tree = function() treeCalls = treeCalls + 1 end
    db:RegisterCallback(exact, "panel", "scale")
    db:RegisterTreeCallback(tree, "panel")
    assertTrue(db:UnregisterCallback(exact, "panel", "scale"))
    assertFalse(db:UnregisterCallback(exact, "panel", "scale"))
    assertTrue(db:UnregisterTreeCallback(tree, "panel"))
    assertFalse(db:UnregisterTreeCallback(tree, "panel"))
    db:Set("panel", "scale", 1)
    assertEqual(exactCalls, 0)
    assertEqual(treeCalls, 0)
end)

test("lifecycle callbacks cover defaults, data changes, and reset", function()
    local data = { value = 1 }
    local db = freshLibrary():New(data)
    local events = {}
    local function callback(_, event)
        events[#events + 1] = event
    end

    db:RegisterLifecycleCallback("OnDefaultsChanged", callback)
    db:RegisterLifecycleCallback("OnDataChanged", callback)
    db:RegisterLifecycleCallback("OnReset", callback)
    db:RegisterDefaults({ value = 0 })
    local replacement = { value = 2 }
    db:SetData(replacement)
    assertEqual(db:Reset(), replacement)
    assertNil(next(replacement))
    assertEqual(events[1], "OnDefaultsChanged")
    assertEqual(events[2], "OnDataChanged")
    assertEqual(events[3], "OnReset")
    assertError(function()
        db:RegisterLifecycleCallback("PLAYER_LOGIN", callback)
    end, "supported event")
end)

test("bulk lifecycle operations do not synthesize path callbacks", function()
    local db = freshLibrary():New({ value = 1 })
    local pathCalls = 0
    db:RegisterTreeCallback(function() pathCalls = pathCalls + 1 end)
    db:RegisterDefaults({ value = 0 })
    db:SetData({ value = 2 })
    db:Reset()
    assertEqual(pathCalls, 0)
end)

test("lifecycle errors and removals use snapshot dispatch", function()
    local db = freshLibrary():New({})
    local removedCalls, laterCalls = 0, 0
    local removed
    local first = function(instance)
        instance:UnregisterLifecycleCallback("OnReset", removed)
        error("lifecycle failure")
    end
    removed = function() removedCalls = removedCalls + 1 end
    local later = function() laterCalls = laterCalls + 1 end
    db:RegisterLifecycleCallback("OnReset", first)
    db:RegisterLifecycleCallback("OnReset", removed)
    db:RegisterLifecycleCallback("OnReset", later)
    db:Reset()
    assertEqual(removedCalls, 1)
    assertEqual(laterCalls, 1)
    assertEqual(#callbackErrors, 1)
end)

test("lifecycle additions apply after the current snapshot", function()
    local db = freshLibrary():New({})
    local addedCalls = 0
    local added = function() addedCalls = addedCalls + 1 end
    db:RegisterLifecycleCallback("OnReset", function(instance)
        instance:RegisterLifecycleCallback("OnReset", added)
    end)

    db:Reset()
    assertEqual(addedCalls, 0)
    db:Reset()
    assertEqual(addedCalls, 1)
end)

test("lifecycle callbacks receive documented data arguments", function()
    local original = {}
    local replacement = {}
    local db = freshLibrary():New(original)
    local seenNew, seenOld, seenDefaults
    db:RegisterLifecycleCallback("OnDataChanged", function(_, _, newData, oldData)
        seenNew = newData
        seenOld = oldData
    end)
    db:RegisterLifecycleCallback("OnDefaultsChanged", function(_, _, defaults)
        seenDefaults = defaults
    end)

    db:SetData(replacement)
    local registeredDefaults = db:RegisterDefaults({ enabled = true })
    assertEqual(seenNew, replacement)
    assertEqual(seenOld, original)
    assertEqual(seenDefaults, registeredDefaults)
end)

test("lifecycle callbacks support targeted and complete cleanup", function()
    local db = freshLibrary():New({})
    local calls = 0
    local callback = function() calls = calls + 1 end
    db:RegisterLifecycleCallback("OnReset", callback)
    db:RegisterLifecycleCallback("OnDefaultsChanged", callback)
    db:UnregisterAllLifecycleCallbacks(callback)
    db:Reset()
    db:RegisterDefaults({ value = 1 })
    assertEqual(calls, 0)

    db:RegisterLifecycleCallback("OnReset", callback)
    db:UnregisterAllLifecycleCallbacks()
    db:Reset()
    assertEqual(calls, 0)
end)

test("SetData ignores the same table and preserves profile table identity", function()
    local data = {}
    local db = freshLibrary():New(data)
    local calls = 0
    db:RegisterLifecycleCallback("OnDataChanged", function() calls = calls + 1 end)
    assertEqual(db:SetData(data), data)
    assertEqual(calls, 0)
    local replacement = {}
    assertEqual(db:SetData(replacement), replacement)
    db:Set("value", 1)
    assertEqual(replacement.value, 1)
    assertEqual(calls, 1)
end)

test("same-family minor upgrades update existing instances in place", function()
    local library = freshLibrary(1)
    local db = library:New({}, { value = 1 })
    local prototype = library._prototype
    local oldGet = db.Get
    prototype.StaleMethod = function() return true end

    local upgraded = loadLibrary(2)
    assertEqual(upgraded, library)
    assertEqual(upgraded._prototype, prototype)
    assertEqual(upgraded.MINOR, 2)
    assertTrue(db.Get ~= oldGet)
    assertNil(db.StaleMethod)
    assertEqual(db:Get("value"), 1)

    loadLibrary(1)
    assertEqual(library.MINOR, 2)
end)

test("1.0 and 2.0 API families coexist in both load orders", function()
    local function runOrder(legacyFirst)
        dofile("tests/libstub.lua")
        local function loadLegacy()
            local legacy = LibStub:NewLibrary("LibSimpleDB-1.0", 2)
            function legacy:New(data)
                return { data = data, family = "1.0" }
            end
        end

        if legacyFirst then
            loadLegacy()
            loadLibrary(1)
        else
            loadLibrary(1)
            loadLegacy()
        end

        local legacy = LibStub("LibSimpleDB-1.0")
        local current = LibStub("LibSimpleDB-2.0")
        assertTrue(legacy ~= current)
        assertEqual(legacy:New({}).family, "1.0")
        assertEqual(current:New({}, { value = 2 }):Get("value"), 2)
    end

    runOrder(true)
    runOrder(false)
end)

test("large defaults remain isolated across instances", function()
    local defaults = {}
    for index = 1, 250 do
        defaults[index] = { enabled = true, nested = { value = index } }
    end

    local library = freshLibrary()
    local first = library:New({}, defaults)
    local second = library:New({}, defaults)
    first:Set(100, "nested", "value", 999)
    assertEqual(first:Get(100, "nested", "value"), 999)
    assertEqual(second:Get(100, "nested", "value"), 100)
    assertEqual(defaults[100].nested.value, 100)
end)

test("rejects unsupported and cyclic assigned tables", function()
    local library = freshLibrary()
    local db = library:New({})
    assertError(function() library:New({}, { bad = function() end }) end, "SavedVariables-compatible")
    assertError(function() db:Set("bad", function() end) end, "SavedVariables-compatible")
    local cycle = {}
    cycle.self = cycle
    assertError(function() db:Set("cycle", cycle) end, "cyclic tables")
    assertNil(db:GetRaw("cycle"))

    assertError(function()
        db:Set("badKey", { [true] = "invalid" })
    end, "table keys")
    assertNil(db:GetRaw("badKey"))
end)

test("rejects NaN path keys", function()
    local db = freshLibrary():New({})
    local nan = 0 / 0
    assertError(function() db:Get(nan) end, "path key 1")
end)

for index = 1, #tests do
    local current = tests[index]
    local ok, message = pcall(current.callback)
    if ok then
        passed = passed + 1
        io.write(("ok %d - %s\n"):format(index, current.name))
    else
        failed = failed + 1
        io.write(("not ok %d - %s\n%s\n"):format(index, current.name, tostring(message)))
    end
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
if failed > 0 then
    os.exit(1)
end
