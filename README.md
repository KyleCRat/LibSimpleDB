# LibSimpleDB

LibSimpleDB is an embedded World of Warcraft SavedVariables library for small
addons that need nested defaults, explicit reset behavior, structured change
callbacks, and profile data switching without AceDB.

The project intentionally has no standalone addon TOC. Consumer release
packages embed the tagged library source and load it after LibStub.

The current API family is `LibSimpleDB-2.0`. It targets WoW Interface `120007`
and Lua 5.1.

## Status

The `2.0.0` release candidate is implemented. Syntax checks, the Lua 5.1 test
suite, tagged-family compatibility tests, and repeatable 1.0-versus-2.0
benchmarks have run successfully. The measured CPU-for-allocation tradeoff is
accepted for the initial release.

The release remains pending implementation of `LibSimpleDBProfiles-1.0`, the
focused YvBags smoke test, and one final local verification run.
PhasedCombatTimer, RPGBossBar, and LootLevel migrations are deferred and do not
block `2.0.0`.

## Load and Create

Load LibStub before `embed.xml`, then request the API family:

```lua
local LibSimpleDB = LibStub("LibSimpleDB-2.0")

MyAddonDB = MyAddonDB or {}
local db = LibSimpleDB:New(MyAddonDB, {
    enabled = true,
    display = {
        scale = 1,
    },
})
```

`New()` retains the supplied SavedVariables data table by reference and copies
the defaults tree. Multiple instances therefore share no mutable defaults.

See [API.md](API.md) for the complete API and behavioral contracts.

## Embed a Tagged Release

Keep the repository name unversioned and select the embedded API-family path in
the consumer package:

```yaml
externals:
  Libs/LibSimpleDB-2.0:
    url: https://github.com/KyleCRat/LibSimpleDB.git
    tag: 2.0.0
```

Load the dependency in this order:

```text
Libs\LibStub\LibStub.lua
Libs\LibSimpleDB-2.0\embed.xml
```

The repository remains flat. Git tag `1.0.0` preserves the legacy family; tag
`2.0.0` will identify the first reviewed rewrite release.

## Migrating from 1.0

The rewrite intentionally changes API contracts. Important migrations are:

| 1.0 | 2.0 |
|---|---|
| `RegisterCallback("a.b", callback)` | `RegisterCallback(callback, "a", "b")` |
| wildcard dotted callbacks | `RegisterTreeCallback(callback, "a")` |
| `SetDefault(...)` | `ResetPath(...)` |
| `RegisterEvent(...)` | `RegisterLifecycleCallback(...)` |
| mutate a table returned by `Get()` | modify `GetCopy()` and commit with `Set()` |

`LibSimpleDB-1.0` and `LibSimpleDB-2.0` are separate LibStub families and can
load together while addons migrate.

See [MIGRATION.md](MIGRATION.md) for the complete source, behavior, callback,
lifecycle, data-ownership, and verification checklist.

## Development

With stock Lua 5.1 installed on `PATH`, run the complete verification set from
the repository root:

```powershell
luac -p LibSimpleDB-2.0.lua
lua tests/run.lua
lua tests/tagged-compat.lua
lua benchmarks/run.lua
lua benchmarks/compare.lua
```

The tests have no external Lua dependencies. Hosted CI/CD is intentionally not
configured; run this verification locally before pushing release changes or
tags to GitHub.

Benchmarks default to three runs and report per-operation medians.
`benchmarks/compare.lua` loads the actual `1.0.0` source from Git and compares
it with the working tree through the same suite.

The optional positional arguments are primary iterations, run count, and GC
mode, for example `lua benchmarks/compare.lua 500000 5 stopped`. See
[Performance.md](Performance.md) for the reviewed baseline and interpretation.

## Versioning

- Git tags use unprefixed SemVer: `2.0.0`, `2.0.1`, `2.1.0`.
- The LibStub family stays `LibSimpleDB-2.0` for all compatible `2.x` releases.
- The numeric LibStub minor increases for every implementation release.
- A future breaking API becomes `LibSimpleDB-3.0` and Git tag `3.0.0`.

## License

LibSimpleDB is available under the MIT License. See [LICENSE](LICENSE).
