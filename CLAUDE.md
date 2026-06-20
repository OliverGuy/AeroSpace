# CLAUDE.md

AeroSpace is an i3-like tiling window manager for macOS, written in Swift (SPM).
For deep background read `dev-docs/architecture.md` and `dev-docs/development.md`.

## Build / test / lint

```bash
swift build                       # fast debug build
swift test                        # all tests
swift test --filter MoveCommandTest   # one suite (or Suite/testMethod)
./format.sh                       # swiftformat (config: .swiftformat)
./lint.sh                         # lint (.swiftlint.yml)
./test.sh                         # full CI-equivalent: builds -warnings-as-errors, tests, lint, generate.sh, checks no uncommitted files
```

`./test.sh` builds with `-warnings-as-errors` and then runs `generate.sh` + `script/check-uncommitted-files.sh`, so **CI fails if generated files are stale or anything is uncommitted.** Run `./generate.sh` and commit the result whenever you touch a `.adoc` or a flag.

The lint step's unused-import/unused-code checks read the build output. If `./test.sh` reports an unused import in a file you never touched, it's almost always a stale `.build` left by compiling other commits (e.g. detached-HEAD per-commit builds) — `rm -rf .build` and re-run before trusting it.

## Commit hygiene

Follow `CONTRIBUTING.md`: each commit is an atomic change, **don't mix refactorings with functional changes** in one commit, and the message states what / why / how. When a fix only patches an earlier commit on the same unmerged branch, fold it into that commit rather than appending a `fix:`/`wip:` commit. Verify commits with `git diff <backup-branch>` (must be empty) plus building and testing the rewritten commits individually.

## Module layout (`Sources/`)

- `Common/` — shared client/server code. Command-line arg parsing lives here (`Common/cmdArgs/impl/*CmdArgs.swift`).
- `AppBundle/` — the `AeroSpace.app` server: command implementations, the tree model, config parsing.
- `Cli/` — the `aerospace` CLI client (parses args, forwards to server).
- `AppBundleTests/` — tests.

Client and server **both** parse args (client first for errors/help, server re-parses and runs).

## Tree model

Windows/containers form a per-workspace tree (`AppBundle/tree/`). Containers have a layout (`tiles`/`accordion`) and orientation (`h`/`v`); windows are leaves. Commands that restructure the tree: `move`, `join-with`, `split`. See the "Tree" section of `docs/guide.adoc`.

## Adding or changing a command flag (checklist)

A flag is NOT done until all of these are updated — we have been bitten by missing the last two:

1. **Args**: add the field + parser entry in `Sources/Common/cmdArgs/impl/<Cmd>CmdArgs.swift` (e.g. `trueBoolFlag(\.myFlag)`).
2. **Behavior**: use it in `Sources/AppBundle/command/impl/<Cmd>Command.swift`.
3. **Man page**: add it to the synopsis block AND the options list in `docs/aerospace-<cmd>.adoc`.
4. **Regenerate help**: run `./generate.sh` (or just `script/generate-cmd-help.sh`) — regenerates `Sources/Common/cmdHelpGenerated.swift`. Do not hand-edit generated files.
5. **Shell completion**: add the flag to the relevant rule in `grammar/commands-bnf-grammar.txt` (e.g. `<focus_direction_flag>`). This file is for shell completion only — it does NOT affect config/CLI parsing, but completion will be missing the flag if you skip it.

Config and CLI use the same `parseCommand`, so a flag that parses on the CLI also works in config — no separate config grammar.

## Adding a config option

1. Field in `Sources/AppBundle/config/Config.swift`.
2. Parser entry in `Sources/AppBundle/config/parseConfig.swift` (the `configParser` dict).
3. Document in `docs/config-examples/default-config.toml` and `docs/guide.adoc`.

## Test conventions

- Build trees with `TestWindow.new(id:parent:)` and `TilingContainer.newVTiles(...)`; focus with `.focusWindow()`.
- Assert structure with `container.layoutDescription` against `.h_tiles([...])` / `.v_tiles([...])` / `.window(id)`.
- Drive commands via `parseCommand("...").cmdOrDie.run(.defaultEnv, .emptyStdin)`.
- Parse config in tests with `parseConfig("...")` and check `.errors` / `.strErrors`.
- Normalization does NOT run in these direct `run()` tests — single-child containers are preserved, so assert the raw post-command tree.
