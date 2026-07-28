# Core Tools Install Approval

The live flywheel integration requires upstream Agent Flywheel tools:

- `br` from `beads_rust`
- `bv` from `beads_viewer`
- `mcp-agent-mail` / `am` from `mcp_agent_mail_rust`

## Why Approval Is Required

Installing these tools requires:

- network access to GitHub;
- executing upstream installer scripts;
- writing binaries and configuration outside this repository;
- possible shell/profile/config changes depending on upstream installers.

The execution request was intentionally rejected once because the install command used three unpinned `curl | bash` installers. That is a reasonable safety block.

## Exact Command Proposed

From `study-agent-devkit/`:

```bash
scripts/install-core-tools.sh --execute
```

That currently expands to:

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh?$(date +%s)" | bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh?$(date +%s)" | bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail_rust/main/install.sh?$(date +%s)" | bash
```

## Safer Alternative

If you prefer not to run remote installers, install the tools manually following their upstream README files, then run:

```bash
scripts/check-flywheel.sh
scripts/run-core-tools-smoke.sh --clean --require-tools
```

## Acceptance Criteria After Install

- `br` is available on PATH.
- `bv` is available on PATH.
- `mcp-agent-mail` or `am` is available on PATH.
- `scripts/check-flywheel.sh` reports the tools as available.
- `scripts/run-core-tools-smoke.sh --clean --require-tools` passes.

## Required User Approval Text

To let Codex attempt the install, explicitly say that you approve running:

```text
scripts/install-core-tools.sh --execute
```

and that you understand it will execute remote installer scripts from GitHub and write outside the workspace.
