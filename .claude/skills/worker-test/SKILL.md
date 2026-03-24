---
name: worker-test
description: Run Python worker tests (pytest). Use when modifying worker/server.py or worker logic.
---

Run the Python worker test suite:

```bash
cd /Users/sanyasamineva/Desktop/govorun-app/worker && python3 -m pytest test_server.py -v 2>&1
```

If tests fail:
1. Show the failing test names and assertion messages
2. Identify the relevant code in worker/server.py
3. Suggest fixes

If all tests pass, report the count and confirm success.
