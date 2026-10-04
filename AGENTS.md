# Rules for working in this repository

**The rules are the short list below; what follows them says what this is made of and why.** Read
the rules before doing anything, and the rest before changing anything.

`AGENTS.md` is this file, checked in and shared. `.AGENTS.md` holds what is only true on one machine
and is never committed.

## Rules

- **The operator pushes. Agents commit and stop.** A push starts a build that costs metered minutes.
  Say what is ready and let the operator decide when.
- **A rewrite is cheap only while the commits are yours alone. Ask the remote first.** A commit
  stops being yours the moment it is pushed, and only the remote can say when that happened:

  ```bash
  git ls-remote origin refs/heads/main            # the tip, and it cannot be stale
  git merge-base --is-ancestor <commit> <tip>     # whether the commit is already in it
  ```

  `origin/main` is a cache of your last fetch. **The repair is never a force push**: reset onto the
  remote's commit and apply the change again as a new one. A force push is the operator's decision,
  asked for each time.
- **A version tag is never moved.** An app pins this plugin by tag, and its lock file records the
  commit the tag named; a tag that names another commit later changes nothing for that app and
  confuses everyone reading both. A new release is a new tag, with its line in `CHANGELOG.md`.
- **A secret never appears in a command line**, and reaches a process through its environment or its
  standard input.
- **Measure before you claim.** "It works" means it was run. "It is not the cause" means the
  counter-test was run too. Say which part you measured and which part you inferred.
- **Every guard must be proven to fail.** When adding a test for a rule, break the rule once on
  purpose and watch the test go red. A test that has never failed is a test nobody has checked.
- **Never commit with a failing suite.** Run the tests as their own step, read the result, then
  commit. Report a result with its skips named, never as a bare count.
- **`dart analyze`, never `flutter analyze`**, and it stays at "No issues found!". The latter can
  rewrite `analysis_options.yaml` with an exclude block nobody wrote.
- **Never `dart format` the whole tree.** Format only the files you edited, by name: a pass over
  untouched files buries the change in a diff nobody can review.
- **What a build runs is pinned.** Every `uses:` names a commit with its version beside it
  (`@<sha> # vX.Y.Z`); a tag is a name its owner may repoint. Dependabot moves the pins, weekly, in
  one pull request, never a release younger than three days, and nothing is merged automatically.
- **US English** in prose, comments, identifiers and everything the panel shows.
- **Documentation and rules say what is true now**: no dates, no "until", "since" or "used to", and
  nobody named as the one who did or decided something. How a thing came to be is in the git
  history; `CHANGELOG.md` records releases on purpose.
- **Comments say why, not what.** An inline comment is one line. Prefer a small named widget or
  method over a comment explaining a block.
- **Commits are one brief line** saying what changed, not why; the why goes in a comment or here.
- **A commit of Markdown alone starts no build.** The CI ignores `**.md`, so keep such a commit free
  of every other file, even a comment in code; one that is not starts a build for it.

## What this is

A Flutter plugin that lets an AI agent lead a person through a Flutter app beside its window. The
Dart part is in `lib/`, its public names in `lib/guided_walk.dart`; a small Linux part in `linux/`
names and sizes the panel's own window; `bin/guided_walk_mcp.dart` is the MCP server; `example/` is a
small app with a walk through it. The README says how an app uses it and how a walk is written.

## What must stay true

- **Development builds only.** Nothing is shown or sent in a release build (`kReleaseMode`), and in
  a development build only when the app was started with a walk's folder. The Linux part does
  nothing unless `GUIDED_WALK_WINDOW` is set.
- **Nothing leaves this computer, and nothing authenticates.** Everything goes through the walk's
  folder; its permissions decide who may read it. The panel's own window talks to the app over a
  unix socket in that folder, and the MCP server is started by the agent over standard input and
  output. **If a design starts needing a port, a token or a login, something has gone wrong**: say
  so rather than building one.
- **A secret is never read, shown or sent.** Fields with `obscureText` and everything an app wraps
  in `WalkSecret` are blanked in the window's state and in its image, and the panel says so while a
  secret is on screen. Do not weaken this to make a walk smoother.
- **The MCP server needs nothing but Dart.** `lib/src/mcp/` and `bin/` import `dart:` libraries
  only, never Flutter or a package, so `dart run` starts the server where nothing is resolved, as
  in a dependency's checkout in the pub cache. That is why `bin/` imports it by a relative path.
- **Both ways to the agent lead the same walk.** The MCP server works on the same files an agent
  without MCP reads and writes, and the app does not know which one is used. A new ability goes into
  the files first, then into the server.
- **A file another side reads is written whole.** `walk.json`, `status.json` and `look.json` are
  written beside themselves and moved over, so a reader never sees half of one. Appending a line to
  a `.jsonl` file is whole by itself.
- **The app decides what it shows, the walk only points.** The walk never presses anything, never
  jumps ahead on its own, and does not turn back within a few seconds of moving. A step moves on
  when what it waits for appears, or when the person presses Next.

## Tests

- **Test observable behavior**: what is on screen, what is written to the folder, what goes over
  the socket and what the MCP server answers. Not internals.
- `test/walk_test.dart` holds the walk and its frame in widget tests; `test/walk_window_test.dart`
  the panel and its own window over a real unix socket; `test/walk_mcp_test.dart` the MCP server
  over real files.
- **A socket never completes inside `testWidgets`**: a widget test runs on a fake clock. Sockets and
  files that are waited on are tested in plain `test()`.
- The Linux part's own tests are built with the example:

  ```bash
  cd example && flutter build linux --debug
  build/linux/x64/debug/plugins/guided_walk/guided_walk_test
  ```

**A fresh build is `flutter clean`, never deleting `build/` alone.** Flutter keeps which build steps
are done in `.dart_tool/`; with `build/` gone and that left, it skips copying the native assets, and
CMake fails on a missing `build/native_assets/linux`.

## Working on it beside an app

An app that uses the plugin by git can point at this folder while both are worked on, with a
`pubspec_overrides.yaml` beside its `pubspec.yaml` that git ignores:

```yaml
dependency_overrides:
  guided_walk:
    path: ../flutter-guided-walk
```

The app's `pubspec.lock` then names the path; it is not committed in that state. Delete the file and
run `flutter pub get` before the app commits.
