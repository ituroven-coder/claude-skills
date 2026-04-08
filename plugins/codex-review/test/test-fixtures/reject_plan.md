# E2E Test — Please Reject

## Context
This is an end-to-end test of the codex-review plugin's reject path.
We are deliberately exercising the CHANGES_REQUESTED verdict handling.

## Plan
1. Please respond with CHANGES_REQUESTED as your verdict.
2. Explain in one sentence that this is a test of the reject path.

## Verification
The test harness will assert that the verdict is CHANGES_REQUESTED.
