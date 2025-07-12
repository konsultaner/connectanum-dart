# Instructions for Codex agents

This repository does not include a Dart SDK. If a Codex agent needs to run Dart
commands, execute the `codex.sh` script first. This installs Dart and
exposes the `dart` command in the current session. At the same time it prepares
the chrome executable to be able to run dart tests in headless chrome.

The CI pipeline already sets up Dart on GitHub Actions, so the scripts should **not** be called from CI workflows.

After running the script, run:

```
dart pub get
```

## Before creating pull requests

- write unit tests for new code lines
- test all code on chromium and dart-vm
- have 100% coverage on new code line
- run `dart format .` to format all files
- run `dart analyze` again
- check `dart outdated`