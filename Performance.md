# Performance Verification

This document records the Lua 5.1 performance review for the unreleased
`LibSimpleDB-2.0`, minor `1`, against the tagged `1.0.0` implementation
(`LibSimpleDB-1.0`, minor `2`).

## Reproducing the Benchmarks

Run commands from the repository root with stock Lua 5.1:

```powershell
lua benchmarks/run.lua
lua benchmarks/compare.lua
```

Both commands default to 250,000 primary iterations and three independent runs.
Override those values with positional arguments:

```powershell
lua benchmarks/compare.lua 500000 5
lua benchmarks/compare.lua 250000 3 enabled
```

The optional third argument selects `stopped` or `enabled` garbage collection.
Stopped mode is the default and reports cumulative allocation. Enabled mode
includes collector CPU cost and reports only the retained-memory delta observed
at the end of each operation.

`benchmarks/compare.lua` loads the legacy implementation directly from Git with
`git show 1.0.0:LibSimpleDB-1.0.lua`. It then runs both API families through the
same benchmark suite and adapters for their differing callback APIs. No legacy
source copy or generated benchmark file is required.

Each operation warms up first, performs a full collection, stops garbage
collection during measurement, and records:

- CPU time from `os.clock()`.
- Cumulative allocation from `collectgarbage("count")` while collection is
  stopped.
- The median of all requested runs.

The callback allocation numbers are cumulative allocations, not retained
memory. For example, 39,062.5 KiB across 250,000 writes is 160 bytes per changed
write.

## Reviewed Results

The following medians were recorded on 2026-07-14 with stock Lua 5.1.5 on
Windows. Primary operations used 250,000 iterations, `IsModified()` used 1,000,
and construction used 100.

| Operation | 1.0 CPU | 2.0 CPU | CPU change | Allocation KiB, 1.0 to 2.0 |
|---|---:|---:|---:|---:|
| Get one raw key | 0.055 s | 0.044 s | -20.0% | 19,531.250 to 0 |
| Get four raw keys | 0.107 s | 0.187 s | +74.8% | 31,250.000 to 0 |
| Get default fallback | 0.074 s | 0.045 s | -39.2% | 19,531.250 to 0 |
| GetRaw four keys | 0.105 s | 0.183 s | +74.3% | 31,250.000 to 0 |
| GetDefault four keys | 0.102 s | 0.182 s | +78.4% | 31,250.000 to 0 |
| GetColor default | 0.109 s | 0.184 s | +68.8% | 19,531.250 to 0 |
| GetColorDefault | 0.078 s | 0.155 s | +98.7% | 19,531.250 to 0 |
| Set, no callbacks | 0.119 s | 0.245 s | +105.9% | 42,968.750 to 0 |
| Set, exact callback | 0.143 s | 0.358 s | +150.3% | 42,968.750 to 39,062.500 |
| Set, wildcard/root tree callback | 0.156 s | 0.382 s | +144.9% | 42,968.750 to 39,062.500 |
| IsModified large parent | 0.235 s | 0.230 s | -2.1% | 78.125 to 0 |
| Construct large defaults | 0.017 s | 0.031 s | +82.4% | 6,700.781 to 6,628.906 |

Supplemental runs with garbage collection enabled produced the same CPU trend.
Collection overhead did not offset the deep-read and write regressions.

## Interpretation

The explicit allocation goals pass:

- `Get()`, `GetRaw()`, `GetDefault()`, `GetColor()`, and `GetColorDefault()`
  allocate no temporary memory in the measured paths.
- Writes with no callbacks allocate no temporary memory and do not construct
  callback path strings.
- Callback writes allocate about 160 bytes per changed write for the structured
  path and dispatch snapshots, down from about 176 bytes per legacy write.
- Large-parent `IsModified()` no longer allocates a temporary vararg table.

CPU results are mixed. One-key reads and default fallback improve, but deep
reads are roughly 70% slower, callback-free writes are about twice as slow, and
callback writes are more than twice as slow. These operations remain below two
microseconds per call in this runtime, but the regression is relevant to addons
that perform many nested reads per event.

The documented release criterion that benchmarks demonstrate the expected
improvement is therefore only partially satisfied. Before tagging `2.0.0`, the
project must either:

1. Optimize the repeated path validation and traversal work, then rerun the
   comparison; or
2. Explicitly accept and document the CPU-for-allocation tradeoff based on
   focused consumer smoke tests in the WoW client.

## Remaining Verification

- Smoke-test `LootLevel`, `PhasedCombatTimer`, `RPGBossBar`, and `YvBags` with
  the release candidate and real embedded LibStub copies.
- Run `lua tests/tagged-compat.lua` to verify the actual tagged legacy source and
  working-tree rewrite in both load orders.
- Record new benchmark results here whenever a performance-sensitive
  implementation change alters the comparison materially.
