# Instructions for Codex agents

This repository does not include a Dart SDK. If a Codex agent needs to run Dart
commands, execute the `ci-setup-dart.sh` script first. This installs Dart and
exposes the `dart` command in the current session.

After running the script, run:

```
dart pub get
dart analyze
```

For running tests locally, Chrome needs to be installed.

- Set the environment variable `CHROME_EXECUTABLE` to the Chrome binary path.
- If running as root or in containers, you may need to pass `--no-sandbox` to Chrome. One approach is to create a wrapper script exposing this flag and set `CHROME_EXECUTABLE` to that script.
- Execute `dart test` to run all unit tests.

The CI pipeline already sets up Dart on GitHub Actions, so the scripts should **not** be called from CI workflows.
