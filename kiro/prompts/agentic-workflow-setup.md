Run the agentic-workflow `setup` workflow in Kiro CLI, in the main thread (only the main thread may ask the user).

If you cannot call `invoke_sub_agent`, you are not in the right agent: tell the user to restart with `kiro-cli --agent agentic-workflow` (or switch with `/agent`) and stop.

1. `~/.kiro/agentic-workflow-plugin/kiro/HOST.md` maps the Claude Code names, tools and permission text of the shared files to Kiro. It is already loaded in the `agentic-workflow` agent; otherwise read it with `read_file`. Where it disagrees with the next file, HOST.md wins; its "Setup and permissions on Kiro" section lists what setup does differently.
2. Read `~/.kiro/agentic-workflow-plugin/skills/setup/SKILL.md` with `read_file` (ignore its frontmatter) and follow it from its first heading, using the arguments below as its `$ARGUMENTS`. Read `~/.kiro/agentic-workflow-plugin/skills/start/references/config-schema.md` when it says so.

Arguments: $ARGUMENTS
