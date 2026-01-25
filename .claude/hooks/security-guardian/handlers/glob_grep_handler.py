"""Glob and Grep tool handler."""

from typing import Any

from handlers.base import ToolHandler, CheckResult
from checks import DirectoryCheck


class GlobGrepHandler(ToolHandler):
    """Handler for Glob and Grep tool invocations."""

    tool_name = "Glob"

    def __init__(self, config):
        super().__init__(config)
        self.directory_check = DirectoryCheck(config)

    def handle(self, tool_input: dict[str, Any]) -> CheckResult:
        """Handle a Glob/Grep tool invocation.

        Args:
            tool_input: Glob/Grep tool input with 'path' field.

        Returns:
            CheckResult with status and guidance.
        """
        # Get path from input (both Glob and Grep use 'path')
        path = tool_input.get("path", "")

        # If no path specified, default is current directory (allowed)
        if not path:
            return self._allow()

        # Check directory boundaries
        result = self.directory_check.check_path(path, operation="find")
        if not result.is_allowed:
            return result

        return self._allow()


class GrepHandler(GlobGrepHandler):
    """Handler for Grep tool invocations (same as Glob for path checking)."""

    tool_name = "Grep"
