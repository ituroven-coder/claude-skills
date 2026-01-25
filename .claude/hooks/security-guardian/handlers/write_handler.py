"""Write/Edit tool handler."""

from typing import Any

from handlers.base import ToolHandler, CheckResult
from checks import DirectoryCheck, SecretsCheck


class WriteHandler(ToolHandler):
    """Handler for Write and Edit tool invocations."""

    tool_name = "Write"

    def __init__(self, config):
        super().__init__(config)
        self.directory_check = DirectoryCheck(config)
        self.secrets_check = SecretsCheck(config)

    def handle(self, tool_input: dict[str, Any]) -> CheckResult:
        """Handle a Write/Edit tool invocation.

        Args:
            tool_input: Write/Edit tool input with 'file_path' field.

        Returns:
            CheckResult with status and guidance.
        """
        file_path = tool_input.get("file_path", "")

        if not file_path:
            return self._allow()

        # Check directory boundaries
        result = self.directory_check.check_path(file_path, operation="write")
        if not result.is_allowed:
            return result

        # Check protected files (no_modify)
        result = self.secrets_check.check_path(file_path, operation="write")
        if not result.is_allowed:
            return result

        return self._allow()


class EditHandler(WriteHandler):
    """Handler for Edit tool invocations (same as Write)."""

    tool_name = "Edit"


class NotebookEditHandler(WriteHandler):
    """Handler for NotebookEdit tool invocations."""

    tool_name = "NotebookEdit"

    def handle(self, tool_input: dict[str, Any]) -> CheckResult:
        """Handle a NotebookEdit tool invocation.

        Args:
            tool_input: NotebookEdit tool input with 'notebook_path' field.

        Returns:
            CheckResult with status and guidance.
        """
        # NotebookEdit uses 'notebook_path' instead of 'file_path'
        notebook_path = tool_input.get("notebook_path", "")

        if not notebook_path:
            return self._allow()

        # Check directory boundaries
        result = self.directory_check.check_path(notebook_path, operation="write")
        if not result.is_allowed:
            return result

        # Check protected files (no_modify)
        result = self.secrets_check.check_path(notebook_path, operation="write")
        if not result.is_allowed:
            return result

        return self._allow()
