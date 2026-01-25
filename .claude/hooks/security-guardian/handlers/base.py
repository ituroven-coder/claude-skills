"""Base handler class for tool processing."""

from abc import ABC, abstractmethod
from typing import Any

from checks.base import CheckResult, CheckStatus


class ToolHandler(ABC):
    """Base class for tool handlers."""

    tool_name: str = "base"

    def __init__(self, config: Any):
        """Initialize handler with configuration.

        Args:
            config: Security configuration.
        """
        self.config = config

    @abstractmethod
    def handle(self, tool_input: dict[str, Any]) -> CheckResult:
        """Handle a tool invocation.

        Args:
            tool_input: Tool input parameters.

        Returns:
            CheckResult with status and guidance.
        """
        pass

    def _allow(self) -> CheckResult:
        """Create an allow result."""
        return CheckResult(status=CheckStatus.ALLOW)

    def _block(self, reason: str, guidance: str = "") -> CheckResult:
        """Create a block result."""
        return CheckResult(
            status=CheckStatus.BLOCK,
            reason=reason,
            guidance=guidance,
            check_name=self.tool_name,
        )

    def _confirm(self, reason: str, guidance: str = "") -> CheckResult:
        """Create a confirmation-required result."""
        return CheckResult(
            status=CheckStatus.CONFIRM,
            reason=reason,
            guidance=guidance,
            check_name=self.tool_name,
        )
