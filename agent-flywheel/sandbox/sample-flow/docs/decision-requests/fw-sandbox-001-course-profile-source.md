# Decision Request: fw-sandbox-001-course-profile-source

        Status: Open
        Bead: fw-sandbox-001
        Agent: prompt-profile-worker

        ## Severity

        important

        ## Decision Type

        product

        ## Question

        Should course profiles start as built-in presets only, or should user-authored profiles be allowed in the first implementation?

        ## Context

        User-authored profiles increase flexibility but require validation, persistence, and abuse-resistant prompt composition.

        ## Options

        1. `presets-only`: Built-in profiles only.
           - Consequence: faster and safer first implementation.

        2. `user-authored`: Allow users to create profiles.
           - Consequence: more powerful but requires validation and UI.

        ## Recommendation

        Recommended option: `presets-only`

        Reason:

        It keeps the first implementation testable while leaving room for later user-authored profiles.

        ## Default If Unanswered

        Use `presets-only` for reversible planning artifacts. Do not implement persistence until confirmed.

        ## Links

        - `docs/tasks/fw-sandbox-001.md`

        ## Resolution

        Answered by:
        Answered at:
        Decision:
        Follow-up beads:
