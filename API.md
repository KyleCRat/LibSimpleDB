# LibSimpleDB-2.0 API

## Data Model

Paths contain one or more string or numeric keys. Nil, boolean, table, function,
thread, and userdata path keys are rejected. NaN is also rejected as a numeric
key.

Stored values must be SavedVariables-compatible primitives or plain, acyclic
tables. Table keys must be strings or numbers. Metatables and shared table
identity are not preserved when values are copied.

The data table supplied to `New()` or `SetData()` is retained by reference so
WoW can serialize it as the owning addon's SavedVariables table. Defaults and
tables supplied to `Set()` are copied.

Tables returned by `Get()`, `GetRaw()`, and `GetDefault()` are internal and must
be treated as read-only. Use `GetCopy()`, modify the copy, then call `Set()` so
ownership and callbacks remain predictable.

## Constructor

### `LibSimpleDB:New(data[, defaults])`

Create an instance backed by `data`. Copy `defaults` into instance-owned
storage. Both arguments must be tables when present.

## Reads

### `db:Get(key1, ...)`

Return the raw value at the path when present; otherwise return the value at the
same path in defaults. `false`, `0`, and the empty string are raw values and do
not fall back. This hot path creates no temporary tables.

Fallback is evaluated for the requested path. Raw and default tables are not
recursively merged into a materialized view when a parent table is returned.
Request a deeper leaf to receive fallback at that leaf.

### `db:GetRaw(key1, ...)`

Return only the raw SavedVariables value. This hot path creates no temporary
tables.

### `db:GetDefault(key1, ...)`

Return only the registered default. This hot path creates no temporary tables.

### `db:GetCopy(key1, ...)`

Return a detached deep copy of the effective value. Use this method when a table
must be edited and committed with `Set()`.

### `db:IsModified(key1, ...)`

Return `true` when a raw value exists and differs recursively from the current
default. Parent-table checks recursively compare the complete subtree and are
not intended for hot paths.

## Writes and Resets

### `db:Set(key1, ..., value)`

Copy and store a non-nil `value`. A nil final value uses `ResetPath()` semantics:
remove the raw override, prune empty raw ancestors, and fall back to the current
default. Nil path keys remain invalid. Nested writes replace scalar raw
intermediates with tables.

When the assigned value equals the current default recursively, remove the raw
override and prune empty raw ancestors. This keeps SavedVariables small and
allows later default changes to reach users. A wrong-shaped scalar intermediate
is replaced as part of the write before normalization, so stale scalar data does
not survive a nested assignment.

Return the new effective value.

### `db:ResetPath(key1, ...)`

Remove the raw override, prune empty raw ancestors, and fall back to the current
default. Return the new effective value.

### `db:Delete(key1, ...)`

Alias of `ResetPath()`. Deleting an override does not suppress a registered
default; use an explicit false or other domain value when suppression is
required.

### `db:Toggle(key1, ...)`

Store the Lua boolean inverse of the effective value and return it. Any truthy
value becomes `false`; `false` or nil becomes `true`.

### `db:Reset()`

Clear the current data table in place, preserving its SavedVariables identity.
Fire lifecycle event `OnReset`. Path callbacks do not fire for this bulk
operation. Return the data table.

### `db:SetData(data)`

Switch the instance to another data table, such as another profile or
per-character store. Fire `OnDataChanged` with the new and old tables. Passing
the active table is a no-op. Path callbacks do not fire. Return `data`.

### `db:RegisterDefaults(defaults)`

Copy and recursively merge defaults. New values overwrite conflicting existing
defaults; non-conflicting keys remain. Fire `OnDefaultsChanged`. Path callbacks
do not fire. Passing nil is a no-op that returns the current defaults table.

## Colors

Color values are plain tables with numeric `r`, `g`, `b`, and `a` components in
the inclusive range 0 through 1.

### `db:GetColor(key1, ...)`

Return effective `r, g, b, a` components. Return opaque white when the effective
value is missing or malformed. This hot path creates no temporary tables.

### `db:GetColorDefault(key1, ...)`

Return default `r, g, b, a` components or opaque white. This hot path creates no
temporary tables.

### `db:SetColor(key1, ..., color)`

Validate and copy the color table, store it through normal `Set()` semantics,
and return the stored effective table.

## Path Callbacks

Path callbacks use typed path keys rather than dotted strings. Numeric key `1`,
string key `"1"`, and string key `"a.b"` remain distinct.

Callbacks receive effective values:

```lua
local function OnChanged(db, newValue, oldValue, ...)
    local pathCount = select("#", ...)
end
```

Callbacks fire only when the effective value changes recursively. Registering
the same function twice for the same subscription is idempotent. Registering
one function for multiple matching subscriptions invokes it once per matching
subscription.

Dispatch snapshots matching callbacks before invoking them. Registrations and
removals made during dispatch apply to the next change. Callback errors are
reported through WoW's error handler and do not stop later callbacks.

### `db:RegisterCallback(callback, key1, ...)`

Register an exact-path callback.

### `db:UnregisterCallback(callback, key1, ...)`

Remove an exact-path callback and return whether it was registered.

### `db:RegisterTreeCallback(callback[, key1, ...])`

Register for changes at the path and every descendant. An empty path registers
for every path change in the instance.

### `db:UnregisterTreeCallback(callback[, key1, ...])`

Remove a tree callback and return whether it was registered.

### `db:UnregisterAllCallbacks([callback])`

With no argument, remove every path callback. With a function, remove that
function from every exact and tree subscription.

## Lifecycle Callbacks

Lifecycle callbacks receive `db, event, ...`. Supported events are:

| Event | Additional arguments |
|---|---|
| `OnReset` | none |
| `OnDataChanged` | `newData, oldData` |
| `OnDefaultsChanged` | `defaults` |

Lifecycle dispatch uses the same snapshot and error-isolation behavior as path
callbacks.

### `db:RegisterLifecycleCallback(event, callback)`

Register a lifecycle callback.

### `db:UnregisterLifecycleCallback(event, callback)`

Remove a lifecycle callback and return whether it was registered.

### `db:UnregisterAllLifecycleCallbacks([callback])`

With no argument, remove every lifecycle callback. With a function, remove that
function from all lifecycle events.

## LibStub Upgrade Contract

The library table, instance prototype, and instance metatable persist on the
LibStub-owned `LibSimpleDB-2.0` table. Loading a higher numeric minor updates the
prototype in place and removes stale methods, so existing `2.0` instances use
the newest implementation.

`LibSimpleDB-1.0` is a separate family. It is neither replaced nor migrated by
loading `LibSimpleDB-2.0`.
