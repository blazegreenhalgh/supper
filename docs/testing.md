# Running tests

Run domain and persistence tests with `swift test`. These do not need an iOS
simulator, API key or iCloud account. CI reports them as the separate `core` job
before starting the UI workers.

The UI suite uses fixture recipes and offline service responses. CI builds the
app and test bundle once per worker, then uses `test-without-building` for one
simulator session. Four suites run on separate workers: discovery, chat, editor
and library. `.github/scripts/ui_test_shards.py` defines both the worker matrix
and test selections, and rejects missing, duplicate or stale assignments.

The previous two workers spent 9–10 minutes each executing tests and another
4 minutes starting/stopping the simulator session. The four suites divide the
same tests into roughly 4.5–5 minutes of execution each, based on passing run
[35107921038](https://github.com/blazegreenhalgh/supper/actions/runs/35107921038).
Runner startup and build times vary; four workers use more total runner minutes
to reduce elapsed time. Assertions, native animation checks and screenshots
remain enabled.

## Running a focused UI check

Use an available simulator name from `xcrun simctl list devices available`.
Build the test bundle once, then select the affected test instead of running
every UI flow during development:

```sh
xcodebuild -project Supper.xcodeproj -scheme Supper \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/SupperTests \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS=Tests/UI/Simulator.entitlements \
  build-for-testing

xcodebuild -project Supper.xcodeproj -scheme Supper \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/SupperTests -parallel-testing-enabled NO \
  -only-testing:SupperUITests/SupperUITests/testDiscoverySwipeDiscardsAndKeeps \
  test-without-building
```

Rebuild after source changes. The example test checks discovery saves into
Explore, moving a recipe in both directions, and Search finding it afterward.
`python3 .github/scripts/ui_test_shards.py --suite discovery` prints the selection
arguments for the complete discovery suite.

CI retries only classified simulator launch/termination failures once, after
verifying the original run completed every selected test. Assertions, unknown
errors and incomplete runs fail. Both result bundles and the original log are
retained as artifacts. Superseded runs on the same branch are cancelled.
