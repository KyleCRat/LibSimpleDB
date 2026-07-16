# LibSimpleDB

LibSimpleDB is an embedded World of Warcraft SavedVariables library for small
addons that need nested defaults, explicit reset behavior, structured change
callbacks, and profile data switching without AceDB.

The project intentionally has no standalone addon TOC. Consumer release
packages embed the tagged library source and load it after LibStub.

The current API family is `LibSimpleDB-2.0`. It targets WoW Interface `120007`
and Lua 5.1.

## Status

The `2.0.0` rewrite is under review. The implementation, tests, and benchmarks
are present, but the release must not be tagged until they have run with a
trusted Lua 5.1 runtime and the results have been reviewed. Consumer addons have
not been updated.

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

With Lua 5.1 installed on `PATH`:

```powershell
lua tests/run.lua
lua benchmarks/run.lua
```

The tests have no external Lua dependencies. GitHub or other CI automation
should use a reviewed Lua 5.1 installation source rather than downloading an
unreviewed runtime during the test job.

Benchmarks default to three runs and report per-operation medians. Compare the
working tree with the actual `1.0.0` tag through the same benchmark suite:

```powershell
lua benchmarks/run.lua
lua benchmarks/compare.lua
lua tests/tagged-compat.lua
```

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
