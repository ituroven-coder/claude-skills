"""Secrets protection check - additional layer for files inside project."""

import fnmatch
from pathlib import Path

from checks.base import CheckResult, SecurityCheck
from parsers.bash_parser import ParsedCommand, extract_paths_from_command
from parsers.path_parser import get_project_root, resolve_path


class SecretsCheck(SecurityCheck):
    """Check for access to secret/sensitive files inside project."""

    name = "secrets_check"

    def __init__(self, config):
        super().__init__(config)
        self.project_root = get_project_root()

    def check_command(
        self,
        raw_command: str,
        parsed_commands: list[ParsedCommand],
    ) -> CheckResult:
        """Check for access to protected files."""
        for cmd in parsed_commands:
            paths = extract_paths_from_command(cmd)
            for path_str in paths:
                result = self.check_path(path_str, operation=cmd.command)
                if not result.is_allowed:
                    return result

        return self._allow()

    def check_path(self, path: str, operation: str = "access") -> CheckResult:
        """Check if a path matches protected patterns.

        Args:
            path: Path string to check.
            operation: Operation being performed (read, write, etc.).

        Returns:
            CheckResult indicating if access is allowed.
        """
        resolved = resolve_path(path)

        # Get relative path to project
        try:
            rel_path = resolved.relative_to(self.project_root)
            rel_str = str(rel_path)
        except ValueError:
            # Path outside project - handled by DirectoryCheck
            return self._allow()

        # Check no_read_content patterns
        if self._is_write_operation(operation):
            if self._matches_no_modify(rel_str):
                return self._block(
                    reason=f"Cannot modify protected file: {path}",
                    guidance=f"File is protected. Cannot modify {path}.",
                )
        else:
            if self._matches_no_read(rel_str):
                return self._block(
                    reason=f"Cannot read secrets file: {path}",
                    guidance=self._get_secrets_guidance(path, rel_str),
                )

        return self._allow()

    def _is_write_operation(self, operation: str) -> bool:
        """Check if operation is a write operation."""
        write_ops = {
            "write",
            "edit",
            "tee",
            "echo",
            ">",
            ">>",
            "cp",
            "mv",
            "rm",
            "touch",
            "sed",
            "awk",
        }
        return operation.lower() in write_ops

    def _matches_no_read(self, rel_path: str) -> bool:
        """Check if path matches no_read_content patterns."""
        patterns = self.config.protected_paths.no_read_content

        # Get just the filename for simple matching
        filename = Path(rel_path).name

        # First check negation patterns (they take precedence)
        for pattern in patterns:
            if pattern.startswith("!"):
                negated = pattern[1:]
                # Remove **/ prefix for fnmatch
                if negated.startswith("**/"):
                    negated = negated[3:]
                if fnmatch.fnmatch(filename, negated) or fnmatch.fnmatch(rel_path, negated):
                    return False  # Explicitly allowed

        # Then check blocking patterns
        for pattern in patterns:
            if not pattern.startswith("!"):
                # Remove **/ prefix for fnmatch
                clean_pattern = pattern
                if clean_pattern.startswith("**/"):
                    clean_pattern = clean_pattern[3:]
                # Match against filename or full relative path
                if fnmatch.fnmatch(filename, clean_pattern) or fnmatch.fnmatch(rel_path, clean_pattern):
                    return True

        return False

    def _matches_no_modify(self, rel_path: str) -> bool:
        """Check if path matches no_modify patterns."""
        patterns = self.config.protected_paths.no_modify

        for pattern in patterns:
            if fnmatch.fnmatch(rel_path, pattern):
                return True

        return False

    def _get_secrets_guidance(self, path: str, rel_path: str) -> str:
        """Get appropriate guidance for secrets access."""
        # Check if there's an example file
        if ".env" in rel_path:
            example_path = rel_path.replace(".env", ".env.example")
            example_full = self.project_root / example_path

            if example_full.exists():
                return (
                    f"Cannot read {path} (secrets file). "
                    f"Look at {example_path} for structure, then ask user for values."
                )

            return (
                f"Cannot read {path} (secrets file). "
                f"Ask user what environment variables are needed."
            )

        return f"Cannot read {path} (protected file). Ask user for needed information."
