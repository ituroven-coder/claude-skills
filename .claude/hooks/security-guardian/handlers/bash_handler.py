"""Bash command handler."""

from typing import Any

from handlers.base import ToolHandler, CheckResult
from checks import (
    DirectoryCheck,
    GitCheck,
    DeletionCheck,
    BypassCheck,
    DownloadCheck,
    UnpackCheck,
    ExecutionCheck,
    SecretsCheck,
)
from parsers.bash_parser import parse_bash_command


class BashHandler(ToolHandler):
    """Handler for Bash tool invocations."""

    tool_name = "Bash"

    def __init__(self, config):
        super().__init__(config)
        # Initialize all checks
        self.checks = [
            DirectoryCheck(config),
            GitCheck(config),
            DeletionCheck(config),
            BypassCheck(config),
            DownloadCheck(config),
            UnpackCheck(config),
            ExecutionCheck(config),
            SecretsCheck(config),
        ]

    def handle(self, tool_input: dict[str, Any]) -> CheckResult:
        """Handle a Bash tool invocation.

        Args:
            tool_input: Bash tool input with 'command' field.

        Returns:
            CheckResult with status and guidance.
        """
        command = tool_input.get("command", "")

        if not command or not command.strip():
            return self._allow()

        # Parse command
        parsed_commands = parse_bash_command(command)

        if not parsed_commands:
            return self._allow()

        # Run all checks
        for check in self.checks:
            result = check.check_command(command, parsed_commands)
            if not result.is_allowed:
                return result

        return self._allow()
