# Instructions for Codex agents

This repository does not include a Dart SDK. If a Codex agent needs to run Dart
commands, execute the `ci-setup-dart.sh` script first. This installs Dart and
exposes the `dart` command in the current session.

After running the script, run:

```
dart pub get
dart analyze
dart test
```

The CI pipeline already sets up Dart on GitHub Actions, so the script should **not** be called from CI workflows.
