"""Read tool handler."""

from typing import Any

from handlers.base import ToolHandler, CheckResult
from checks import DirectoryCheck, SecretsCheck


class ReadHandler(ToolHandler):
    """Handler for Read tool invocations."""

    tool_name = "Read"

    def __init__(self, config):
        super().__init__(config)
        self.directory_check = DirectoryCheck(config)
        self.secrets_check = SecretsCheck(config)

    def handle(self, tool_input: dict[str, Any]) -> CheckResult:
        """Handle a Read tool invocation.

        Args:
            tool_input: Read tool input with 'file_path' field.

        Returns:
            CheckResult with status and guidance.
        """
        file_path = tool_input.get("file_path", "")

        if not file_path:
            return self._allow()

        # Check directory boundaries
        result = self.directory_check.check_path(file_path, operation="read")
        if not result.is_allowed:
            return result

        # Check secrets/protected files
        result = self.secrets_check.check_path(file_path, operation="read")
        if not result.is_allowed:
            return result

        return self._allow()
