---
name: verify
description: Run Swift unit tests (xcodebuild). Use after code changes to verify nothing is broken.
---

Run the Swift test suite:

```bash
cd /Users/sanyasamineva/Desktop/govorun-app && xcodebuild test -scheme Govorun -destination 'platform=macOS' 2>&1
```

If tests fail:
1. Show the failing test names and assertion messages
2. Identify which source files are likely involved
3. Suggest fixes based on the error messages

If all tests pass, report the count and confirm success.

Known flaky test: `test_stop_then_start_relaunches_worker` — race condition, not a blocker.
