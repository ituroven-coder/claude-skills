"""Bash command handler."""

import re
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
    CodeContentCheck,
)
from parsers.bash_parser import parse_bash_command, ParsedCommand


# Pattern to detect script execution commands
SCRIPT_EXECUTION_PATTERNS = [
    # Python
    re.compile(r"^python3?\s+(.+\.py)\b"),
    re.compile(r"^python3?\s+-m\s+"),  # module execution
    # Bash/Shell
    re.compile(r"^(?:ba)?sh\s+(.+\.sh)\b"),
    re.compile(r"^source\s+(.+\.sh)\b"),
    re.compile(r"^\.\s+(.+\.sh)\b"),
    # Ruby
    re.compile(r"^ruby\s+(.+\.rb)\b"),
    # Perl
    re.compile(r"^perl\s+(.+\.pl)\b"),
    # Node
    re.compile(r"^node\s+(.+\.js)\b"),
]


class BashHandler(ToolHandler):
    """Handler for Bash tool invocations."""

    tool_name = "Bash"

    def __init__(self, config):
        super().__init__(config)
        # Initialize all checks in priority order:
        # 1. Security bypass checks (hard blocks first)
        # 2. Directory boundary checks
        # 3. Operation-specific checks
        self.checks = [
            BypassCheck(config),      # Security bypasses first (eval, pipe to shell)
            UnpackCheck(config),       # Archive security (bsdtar -s bypass)
            DirectoryCheck(config),    # Boundary protection
            GitCheck(config),          # Git operations
            DeletionCheck(config),     # Deletion protection
            DownloadCheck(config),     # Download protection
            ExecutionCheck(config),    # Execution protection
            SecretsCheck(config),      # Secrets protection
        ]
        self.code_content_check = CodeContentCheck(config)

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

        # Check content of scripts being executed
        result = self._check_script_execution(command, parsed_commands)
        if not result.is_allowed:
            return result

        return self._allow()

    def _check_script_execution(
        self,
        command: str,
        parsed_commands: list[ParsedCommand],
    ) -> CheckResult:
        """Check content of scripts being executed.

        Args:
            command: Raw command string.
            parsed_commands: Parsed commands.

        Returns:
            CheckResult with status and guidance.
        """
        for cmd in parsed_commands:
            # Check for script execution patterns
            script_path = self._extract_script_path(cmd)
            if script_path:
                result = self.code_content_check.check_file(script_path)
                if not result.is_allowed:
                    return result

        return self._allow()

    def _extract_script_path(self, cmd: ParsedCommand) -> str | None:
        """Extract script path from a command.

        Args:
            cmd: Parsed command.

        Returns:
            Script path if found, None otherwise.
        """
        full_cmd = cmd.command
        if cmd.args:
            full_cmd = f"{cmd.command} {' '.join(cmd.args)}"

        for pattern in SCRIPT_EXECUTION_PATTERNS:
            match = pattern.search(full_cmd)
            if match and match.lastindex:
                return match.group(1)

        # Also check direct execution of .py/.sh files via arguments
        if cmd.command in ("python", "python3", "bash", "sh", "ruby", "perl", "node"):
            for arg in cmd.args:
                if arg.endswith((".py", ".sh", ".bash", ".rb", ".pl", ".js")):
                    return arg

        return None
