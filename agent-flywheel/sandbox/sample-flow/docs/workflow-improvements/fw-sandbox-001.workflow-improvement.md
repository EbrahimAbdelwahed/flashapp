# Workflow Improvement: Sandbox tool integration gap

        Status: Proposed
        Source: fw-sandbox-001

        ## Problem

        The file-based sandbox proves artifact shape but not live `br`/`bv`/Agent Mail integration.

        ## Evidence

        - The sandbox generates markdown artifacts only.

        ## Proposed Change

        Target:

        - `scripts/run-sandbox-flow.py`

        Change:

        Add a `--with-core-tools` mode after the tools are installed to create matching `br` issues and Agent Mail threads.

        ## Expected Benefit

        Proves the full coordination loop with real upstream tools.

        ## Risk / Cost

        Requires network/install setup and tool-specific command stability.

        ## Recommendation

        review-first

        ## Follow-Up Beads

        - `fw-002`: install and test `br`, `bv`, and Agent Mail.
