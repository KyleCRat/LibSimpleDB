# LibSimpleDB-2.0 engineering guide

Use StyLua 2.5.2 and Selene 0.31.0 with the checked-in Lua 5.1 configuration.
Run these checks from this repository's root before handing off Lua changes:

```powershell
stylua --check .
selene .
lua tests/run.lua
lua tests/tagged-compat.lua
git diff --check
```

Require zero formatting or lint findings, including warnings. Compile every
changed Lua file with `luac -p` using Lua 5.1. Preserve the existing test suite
and mixed-version coverage when changing public behavior.

Apply formatting with `stylua --verify .`; add `--respect-ignores` when passing
individual files. Do not install tools, add package managers or change global
shell settings without explicit permission. Do not build a permanent custom
style parser or linter. Narrow, read-only, one-off structural checks, such as
XML include resolution, are allowed.

Use four spaces, UTF-8, LF and final newlines. Keep nonempty functions,
callbacks, loops and multi-branch conditionals multiline. Simple single-branch
conditionals may collapse within the 80-column guide, including indentation;
empty functions may stay inline. Keep unrelated statements on separate lines.
Small tuples, colors and short choice records may stay inline. Give larger
tables readable structure, separate logical phases with blank lines and review
naming and complexity even when the tools pass.

Verify new `wow.yml` globals against the runtime or the fixture providing them;
never add names merely to silence findings. Prefix intentionally unused
parameters with `_`. Keep lint exceptions narrow and explain their contract.
Preserve excluded generated data and upstream fixture style.

Preserve public API compatibility, LibStub version negotiation and mixed-addon
load order. Do not commit, tag or push unless requested.
