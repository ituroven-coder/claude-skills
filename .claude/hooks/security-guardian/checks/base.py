"""Base classes for security checks."""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import Enum
from typing import Any


class CheckStatus(Enum):
    """Result status of a security check."""

    ALLOW = "allow"
    BLOCK = "block"
    CONFIRM = "confirm"


@dataclass
class CheckResult:
    """Result of a security check."""

    status: CheckStatus
    reason: str = ""
    guidance: str = ""
    check_name: str = ""

    @property
    def is_allowed(self) -> bool:
        """Check if the result allows the operation."""
        return self.status == CheckStatus.ALLOW

    @property
    def is_blocked(self) -> bool:
        """Check if the result blocks the operation."""
        return self.status == CheckStatus.BLOCK

    @property
    def needs_confirmation(self) -> bool:
        """Check if the result requires user confirmation."""
        return self.status == CheckStatus.CONFIRM

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON output."""
        return {
            "status": self.status.value,
            "reason": self.reason,
            "guidance": self.guidance,
            "check_name": self.check_name,
        }


class SecurityCheck(ABC):
    """Base class for security checks."""

    name: str = "base"

    def __init__(self, config: Any):
        """Initialize check with configuration.

        Args:
            config: Security configuration.
        """
        self.config = config

    @abstractmethod
    def check_command(
        self,
        raw_command: str,
        parsed_commands: list,
    ) -> CheckResult:
        """Check a bash command for security issues.

        Args:
            raw_command: Original command string.
            parsed_commands: Parsed command objects.

        Returns:
            CheckResult with status and guidance.
        """
        pass

    def check_path(self, path: str, operation: str = "access") -> CheckResult:
        """Check a path for security issues.

        Args:
            path: Path to check.
            operation: Operation being performed (read, write, etc.).

        Returns:
            CheckResult with status and guidance.
        """
        return CheckResult(status=CheckStatus.ALLOW)

    def _allow(self) -> CheckResult:
        """Create an allow result."""
        return CheckResult(status=CheckStatus.ALLOW, check_name=self.name)

    def _block(self, reason: str, guidance: str = "") -> CheckResult:
        """Create a block result.

        Args:
            reason: Why the operation is blocked.
            guidance: Suggestion for Claude on how to proceed.

        Returns:
            CheckResult with BLOCK status.
        """
        return CheckResult(
            status=CheckStatus.BLOCK,
            reason=reason,
            guidance=guidance,
            check_name=self.name,
        )

    def _confirm(self, reason: str, guidance: str = "") -> CheckResult:
        """Create a confirmation-required result.

        Args:
            reason: Why confirmation is needed.
            guidance: Suggestion for Claude on how to proceed.

        Returns:
            CheckResult with CONFIRM status.
        """
        return CheckResult(
            status=CheckStatus.CONFIRM,
            reason=reason,
            guidance=guidance,
            check_name=self.name,
        )
