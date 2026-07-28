# Worker Brief: fw-sandbox-001

        ## Assignment

        Use `prompt-profile-worker` to draft prompt-profile sandbox artifacts for `fw-sandbox-001`.

        ## Read First

        - `docs/specs/sample-course-profile.spec.md`
        - `docs/tasks/fw-sandbox-001.md`
        - `docs/worker-profiles/prompt-profile-worker.md`

        ## Scope

        You may change:

        - `sandbox/sample-flow/docs/**`

        Do not change:

        - files outside `sandbox/sample-flow/`

        ## Requirements

        - Keep the task linked to `fw-sandbox-001`.
        - Create a decision request instead of asking an unstructured chat question.

        ## Verification

        Run:

        ```bash
        scripts/run-sandbox-flow.py --clean
        ```

        ## Report Back

        Return changed files, verification result, constraints followed, unresolved questions, and next step.
