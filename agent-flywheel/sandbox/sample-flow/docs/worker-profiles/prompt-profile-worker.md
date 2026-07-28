# Worker Profile: prompt-profile-worker

        ## Reuse Trigger

        Use this worker when a bead changes course-aware prompt policy, prompt metadata, output schemas, or eval fixtures.

        ## Mandate

        Produce prompt-system artifacts that are versioned, testable, and grounded in the current spec.

        ## Scope

        In scope:

        - Prompt metadata.
        - Course profile policy constraints.
        - Eval fixture outlines.

        Out of scope:

        - Provider-specific SDK calls.
        - Product UI implementation.

        ## Required Context

        Read first:

        - `docs/specs/sample-course-profile.spec.md`
        - `docs/tasks/fw-sandbox-001.md`

        Current-doc research:

        - not needed for this sandbox.

        ## Allowed Files

        May edit:

        - `sandbox/sample-flow/docs/**`

        May inspect:

        - `study-agent-devkit/templates/**`

        Do not edit:

        - product code outside `sandbox/sample-flow/`

        ## Forbidden Decisions

        Stop and report back before deciding:

        - canonical prompt registry schema;
        - provider choice;
        - persistent data model.

        ## Quality Gates

        - Every prompt behavior change has an eval note.
        - Every generated study object mentions provenance expectations.
        - Scope remains sandbox-only.

        ## Verification

        Run:

        ```bash
        scripts/run-sandbox-flow.py --clean
        ```

        ## Report Format

        Return:

        - files changed;
        - verification results;
        - constraints followed;
        - unresolved questions;
        - recommended next worker or review step.
