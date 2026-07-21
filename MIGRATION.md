# Migrating From LibSimpleDB 1.0 To 2.0

LibSimpleDB 2.0 is a breaking rewrite with a separate LibStub API family. It is
not an in-place minor upgrade of `LibSimpleDB-1.0`.

This guide covers the source and behavioral changes required to migrate an
addon from tagged release `1.0.0` (`LibSimpleDB-1.0`, minor `2`) to the
unreleased `LibSimpleDB-2.0`, minor `1` release candidate.

## Migration Summary

| 1.0 | 2.0 |
|---|---|
| `LibStub("LibSimpleDB-1.0")` | `LibStub("LibSimpleDB-2.0")` |
| `LibSimpleDB-1.0.lua` | `LibSimpleDB-2.0.lua` |
| `RegisterCallback("a.b", callback)` | `RegisterCallback(callback, "a", "b")` |
| `RegisterCallback("a.*", callback)` | `RegisterTreeCallback(callback, "a")` |
| `RegisterCallback("*", callback)` | `RegisterTreeCallback(callback)` |
| callback receives `path, newValue, oldValue` | callback receives `db, newValue, oldValue, ...path` |
| `SetDefault(...)` | `ResetPath(...)` |
| `RegisterEvent(event, callback)` | `RegisterLifecycleCallback(event, callback)` |
| `UnregisterEvent(event, callback)` | `UnregisterLifecycleCallback(event, callback)` |
| lifecycle callback receives `event, db, ...` | lifecycle callback receives `db, event, ...` |
| mutate a table returned by `Get()` | modify `GetCopy()` and commit with `Set()` |

## Update The Embedded Dependency

Load LibStub first, then the 2.0 source:

```text
Libs\LibStub\LibStub.lua
Libs\LibSimpleDB-2.0\embed.xml
```

Update direct source references:

```xml
<Ui>
    <Script file="LibSimpleDB-2.0.lua"/>
</Ui>
```

Update the requested LibStub family:

```lua
-- 1.0
local LibSimpleDB = LibStub("LibSimpleDB-1.0")

-- 2.0
local LibSimpleDB = LibStub("LibSimpleDB-2.0")
```

When `2.0.0` is released, consumer packages should pin the reviewed tag:

```yaml
externals:
  Libs/LibSimpleDB-2.0:
    url: https://github.com/KyleCRat/LibSimpleDB.git
    tag: 2.0.0
```

Do not replace the 1.0 family globally for every addon at once. Independently
installed addons may continue loading `LibSimpleDB-1.0` while migrated addons
load `LibSimpleDB-2.0`. The families coexist as separate LibStub libraries.

## Constructor And Data Ownership

The constructor signature remains:

```lua
local db = LibSimpleDB:New(data, defaults)
```

Both supplied arguments must be tables when present. The `data` table is
retained by reference so WoW can persist the owning addon's SavedVariables.
Defaults are copied into instance-owned storage.

The normal migration for an unchanged SavedVariables schema is:

```lua
MyAddonDB = MyAddonDB or {}

local db = LibStub("LibSimpleDB-2.0"):New(MyAddonDB, {
    enabled = true,
    display = {
        scale = 1,
    },
})
```

No SavedVariables rewrite is required merely because the LibStub family
changes. Schema migrations are still required when the addon changes its own
stored key layout, such as introducing a profile container.

## Do Not Depend On Instance Internals

Legacy instances stored copied methods and fields such as `data` and `defaults`
directly on the instance table. The 2.0 instance uses a persistent
metatable-backed prototype so existing instances can receive later same-family
minor implementations.

Do not:

```lua
local rawData = db.data
local defaults = db.defaults

for key, method in pairs(db) do
    -- Copy or inspect database methods.
end
```

Keep the addon-owned SavedVariables reference when direct ownership is needed,
and use the documented database methods for reads, writes, defaults, reset, and
data-root switching.

The legacy `FireCallbacks()` and `FireEvent()` dispatch helpers are not part of
the 2.0 API. Do not synthesize notifications manually. Commit path changes
through database mutators and bulk changes through the documented lifecycle
operations.

`LibSimpleDB:GetVersion()` is available when diagnostics need the active API
family and LibStub minor.

## Path Rules

Every public path must contain at least one key. Path keys must be strings or
non-NaN numbers.

These now produce controlled errors:

```lua
db:Get()
db:Get("display", nil, "scale")
db:Get({ "display", "scale" })
db:Set("display", true, "scale", 1)
```

Do not rely on the 1.0 behavior of collecting varargs into a table and deriving
arity with `#`. That behavior could truncate paths containing nil and cause a
write to target the wrong key.

Numeric and string keys remain distinct:

```lua
db:Get("rows", 1)
db:Get("rows", "1")
```

Strings containing dots are literal keys, not callback path separators:

```lua
db:Get("display.scale")
db:Get("display", "scale")
```

## Read Semantics And Table Editing

`Get()`, `GetRaw()`, and `GetDefault()` retain their basic roles:

```lua
db:Get("display", "scale")
db:GetRaw("display", "scale")
db:GetDefault("display", "scale")
```

`Get()` returns the raw value when present and otherwise reads the same path
from defaults. Raw and default parent tables are not recursively merged when a
parent table is returned.

Tables returned by normal reads are internal references and must be treated as
read-only. Code like this must be migrated:

```lua
-- 1.0: silently mutates an internal raw/default table and fires no callback
local display = db:Get("display")
display.scale = 1.2
```

Use the explicit copy-and-commit workflow:

```lua
local display = db:GetCopy("display")
display.scale = 1.2
db:Set("display", display)
```

`GetCopy()` returns a detached recursive copy of the effective value. Committing
through `Set()` applies validation, ownership, normalization, and callbacks.

## Set And Stored Values

`Set()` accepts one or more path keys followed by a value:

```lua
db:Set("display", "scale", 1.2)
```

Non-nil values must be SavedVariables-compatible primitives or acyclic tables.
Tables are recursively validated and copied into plain storage, and their keys
must be strings or numbers. Metatables and shared table identity are not
preserved. Functions, threads, userdata, cyclic tables, and unsupported table
keys are rejected.

A nil final value resets the path:

```lua
db:Set("display", "scale", nil)
```

This is equivalent to `db:ResetPath("display", "scale")`. It removes the raw
override and prunes empty raw parents. When a default exists, that default
becomes the new effective value; nil is not stored as an override. `ResetPath()`
and its `Delete()` alias remain available when an explicit reset operation makes
the caller clearer.

All path keys must be strings or numbers. Nil is valid only as the final value,
not inside a path:

```lua
db:Set("display", nil, 1.2) -- Rejected: the second path key is nil
```

Nested writes replace wrong-shaped scalar intermediates with tables. When a
stored value recursively equals the current default, `Set()` removes the raw
override and prunes empty raw ancestors. This keeps SavedVariables small and
allows later default changes to reach the user.

`Set()` returns the new effective value. Path callbacks fire only when that
effective value changes.

## Replace SetDefault With ResetPath

`SetDefault()` has been removed.

In 1.0, `SetDefault()` copied the current default into SavedVariables as a raw
override. That could bloat storage and prevent later default changes from
applying.

Use `ResetPath()` in 2.0:

```lua
-- 1.0
db:SetDefault("display", "scale")

-- 2.0
db:ResetPath("display", "scale")
```

`ResetPath()` removes the raw override, prunes empty raw parents, returns the new
effective value, and falls back to the current default.

`Delete()` is an alias of `ResetPath()` in 2.0. Deleting a raw override does not
suppress a registered default. Store an explicit domain value such as `false`
when suppression is required.

## Effective Callback Values

Path callbacks now report effective values consistently.

Suppose the default is `1` and the raw value is `2`:

```lua
db:ResetPath("display", "scale")
```

The callback receives new value `1` and old value `2`. Legacy deletion could
report new value `nil` even though a default immediately became effective.

Callbacks fire only when the effective value changes recursively. Writing a
value equal to the current effective value does not produce a notification.

## Migrate Exact Path Callbacks

The callback and path argument order has changed.

```lua
-- 1.0
local function OnScaleChanged(path, newValue, oldValue)
    ApplyScale(newValue)
end

db:RegisterCallback("display.scale", OnScaleChanged)
```

```lua
-- 2.0
local function OnScaleChanged(instance, newValue, oldValue, ...)
    ApplyScale(newValue)
end

db:RegisterCallback(OnScaleChanged, "display", "scale")
```

Unregistration uses the same new order:

```lua
-- 1.0
db:UnregisterCallback("display.scale", OnScaleChanged)

-- 2.0
db:UnregisterCallback(OnScaleChanged, "display", "scale")
```

The 2.0 callback receives:

```text
db, effectiveNewValue, effectiveOldValue, key1, ..., keyN
```

Use `select("#", ...)` when callback code needs the exact path length.

## Migrate Wildcard Callbacks

Dotted wildcard patterns have been replaced by typed tree callbacks.

```lua
-- 1.0: every path
db:RegisterCallback("*", OnAnyChange)

-- 2.0: every path
db:RegisterTreeCallback(OnAnyChange)
```

```lua
-- 1.0: display and every descendant
db:RegisterCallback("display.*", OnDisplayChange)

-- 2.0: display and every descendant
db:RegisterTreeCallback(OnDisplayChange, "display")
```

Unregister tree callbacks explicitly:

```lua
db:UnregisterTreeCallback(OnDisplayChange, "display")
```

`UnregisterAllCallbacks()` is new:

```lua
db:UnregisterAllCallbacks()
db:UnregisterAllCallbacks(OnDisplayChange)
```

The structured callback path distinguishes numeric keys, string keys, and keys
containing dots. One callback registered for multiple matching subscriptions is
invoked once per matching subscription.

Callback dispatch snapshots matching registrations before invocation. Adding
or removing a registration during a callback affects the next change, not the
current dispatch. Callback errors are reported through WoW's error handler and
do not stop later callbacks.

## Migrate Lifecycle Events

Replace the frame-like event API with explicit lifecycle callbacks:

```lua
-- 1.0
local function OnReset(event, instance)
    RefreshSettings()
end

db:RegisterEvent("OnReset", OnReset)
```

```lua
-- 2.0
local function OnReset(instance, event)
    RefreshSettings()
end

db:RegisterLifecycleCallback("OnReset", OnReset)
```

The argument order changes from `event, db, ...` to `db, event, ...`.

Only these lifecycle events are supported:

| Event | Additional arguments |
|---|---|
| `OnReset` | none |
| `OnDataChanged` | `newData, oldData` |
| `OnDefaultsChanged` | `defaults` |

Unregister with:

```lua
db:UnregisterLifecycleCallback("OnReset", OnReset)
db:UnregisterAllLifecycleCallbacks()
db:UnregisterAllLifecycleCallbacks(OnReset)
```

`Reset()`, `SetData()`, and `RegisterDefaults()` are bulk operations. They fire
lifecycle callbacks and do not synthesize per-path callbacks.

Lifecycle dispatch uses the same snapshot and callback-error isolation rules as
path dispatch.

## Reset, SetData, And Defaults

`Reset()` clears the active data table in place, preserves its identity, fires
`OnReset`, and returns the data table.

`SetData(data)` retains the supplied table, fires `OnDataChanged` with new and
old tables, and returns the new table. Passing the active data table is a no-op.
This method is the supported primitive for profile or data-root switching.

`RegisterDefaults(defaults)` copies and recursively merges incoming defaults.
Incoming values overwrite conflicts while non-conflicting keys remain. It fires
`OnDefaultsChanged`. Passing nil is a no-op that returns the current defaults.

Consumers that cache applied settings should refresh after these lifecycle
events.

## Color Helpers

Color values must contain numeric `r`, `g`, `b`, and `a` components in the
inclusive range `0` through `1`.

```lua
db:SetColor("display", "color", {
    r = 0.2,
    g = 0.4,
    b = 0.8,
    a = 1,
})
```

`SetColor()` validates and copies the color table before storing it through
normal Set semantics. Malformed effective/default colors return opaque white
from `GetColor()` or `GetColorDefault()`.

Legacy code that stored missing, non-numeric, NaN, infinite, or out-of-range
components must normalize those values before calling `SetColor()`.

## Toggle And IsModified

`Toggle()` continues to store and return the Lua boolean inverse of the
effective value. It now uses the same copied-write, normalization, effective
callback, and unchanged-value rules as `Set()`.

`IsModified()` returns true when a raw value exists and differs recursively
from the current default. Parent-path checks compare the complete subtree and
should not be placed in hot paths.

## Multiple API Families And Upgrade Behavior

Do not attempt to convert an existing `LibSimpleDB-1.0` instance into a 2.0
instance. Construct a new 2.0 instance from the addon's SavedVariables table.

Both families may load in either order:

```lua
local legacy = LibStub("LibSimpleDB-1.0")
local current = LibStub("LibSimpleDB-2.0")
```

They have independent LibStub registrations and instances. Loading one family
does not replace or update the other.

Within the 2.0 family, later LibStub minors update a persistent prototype in
place. Existing 2.0 instances receive newer method implementations when a
higher minor loads.

## Suggested Migration Sequence

1. Update the embedded folder, source filename, and requested LibStub family.
2. Keep the existing SavedVariables table and defaults unless the addon also
   needs a schema migration.
3. Replace every `SetDefault()` call with reviewed `ResetPath()` behavior.
4. Review nil writes as reset operations; use `ResetPath()` or `Delete()` where
   explicit reset intent improves clarity.
5. Rewrite exact callbacks with callback-first structured paths.
6. Replace wildcard patterns with `RegisterTreeCallback()`.
7. Update callback argument order and use effective new/old values.
8. Replace lifecycle event registration and update lifecycle argument order.
9. Replace mutations of returned tables with `GetCopy()` plus `Set()`.
10. Normalize color values before `SetColor()`.
11. Refresh cached settings on bulk lifecycle/profile changes.
12. Test reload persistence and SavedVariables output.
13. Test with legacy and current API families loaded together.

## Migration Checklist

- [ ] Every embed path references `LibSimpleDB-2.0`.
- [ ] Every LibStub request uses `LibSimpleDB-2.0`.
- [ ] No code calls `SetDefault()`.
- [ ] Every nil `Set()` value is an intentional reset, and no path contains a
  nil key.
- [ ] No code mutates tables returned by normal reads.
- [ ] Exact callbacks use callback-first typed path arguments.
- [ ] Wildcard callbacks use tree registrations.
- [ ] Callback functions accept `db, newValue, oldValue, ...path`.
- [ ] Lifecycle callbacks use the new registration names and argument order.
- [ ] Cached settings refresh after reset, data/profile switch, and default
  changes.
- [ ] Color writes satisfy the strict component contract.
- [ ] Addon-owned SavedVariables migrations complete before constructing the DB.
- [ ] First load, existing data, reload, reset, callbacks, and profile/data-root
  switching have been smoke-tested.
- [ ] Legacy 1.0 and current 2.0 consumers coexist in the same client session.

## Verification Commands

From the LibSimpleDB repository root with Lua 5.1:

```powershell
luac -p LibSimpleDB-2.0.lua
lua tests/run.lua
lua tests/tagged-compat.lua
lua benchmarks/run.lua
lua benchmarks/compare.lua
```

These checks run locally; the project does not use hosted CI/CD. Each migrated
addon still requires focused in-game testing with its own SavedVariables,
callback registrations, cached settings, and embedded dependency load order.

See [API.md](API.md) for the complete 2.0 contract and
[Performance.md](Performance.md) for the reviewed performance behavior.
