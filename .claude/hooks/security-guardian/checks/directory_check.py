"""Directory boundary check - PRIMARY PROTECTION."""

from pathlib import Path

from checks.base import CheckResult, CheckStatus, SecurityCheck
from parsers.bash_parser import ParsedCommand, extract_paths_from_command
from parsers.path_parser import (
    get_project_root,
    is_path_within_allowed,
    is_symlink_escape,
    resolve_path,
)


class DirectoryCheck(SecurityCheck):
    """Check that operations stay within allowed directory boundaries.

    This is the PRIMARY protection layer. All file operations must
    target paths within the project root or explicitly allowed directories.
    """

    name = "directory_check"

    def __init__(self, config):
        super().__init__(config)
        self.project_root = self._get_project_root()
        self.allowed_paths = config.directories.allowed_paths

    def _get_project_root(self) -> Path:
        """Get project root from config or auto-detect."""
        if self.config.directories.project_root:
            return resolve_path(self.config.directories.project_root)
        return get_project_root()

    def check_command(
        self,
        raw_command: str,
        parsed_commands: list[ParsedCommand],
    ) -> CheckResult:
        """Check if command accesses paths outside allowed boundaries."""
        for cmd in parsed_commands:
            paths = extract_paths_from_command(cmd)
            for path_str in paths:
                result = self.check_path(path_str, operation=cmd.command)
                if not result.is_allowed:
                    return result

            # Recursively check piped commands
            if cmd.pipes_to:
                result = self.check_command(raw_command, [cmd.pipes_to])
                if not result.is_allowed:
                    return result

        return self._allow()

    def check_path(self, path: str, operation: str = "access") -> CheckResult:
        """Check if a path is within allowed boundaries.

        Args:
            path: Path string to check.
            operation: Operation being performed.

        Returns:
            CheckResult indicating if access is allowed.
        """
        # Resolve path relative to project root (not cwd, which may be security-guardian dir)
        resolved = resolve_path(path, base_dir=self.project_root)

        # Check for symlink escape
        if is_symlink_escape(path, self.project_root, base_dir=self.project_root):
            return self._block(
                reason=f"Symlink escape detected: '{path}' resolves to '{resolved}' outside project",
                guidance=(
                    f"Symlink points outside project boundaries. "
                    f"Give user the command: `{operation} {path}`"
                ),
            )

        # Check if within allowed paths
        if not is_path_within_allowed(resolved, self.project_root, self.allowed_paths):
            return self._block(
                reason=f"Path '{resolved}' is outside project boundaries",
                guidance=self._get_guidance_for_operation(operation, path),
            )

        return self._allow()

    def _get_guidance_for_operation(self, operation: str, path: str) -> str:
        """Get appropriate guidance based on operation type."""
        if operation in ("cat", "less", "head", "tail", "read"):
            return f"Path is outside project. Give user the command: `cat {path}`"
        elif operation in ("rm", "unlink", "rmdir"):
            return f"Cannot delete files outside project. Give user the command: `rm {path}`"
        elif operation in ("cp", "mv"):
            return f"Cannot copy/move files outside project. Give user the command: `{operation} {path}`"
        elif operation in ("find", "ls"):
            return f"Cannot search outside project. Give user the command: `{operation} {path}`"
        elif operation in ("echo", "tee", "write", ">", ">>"):
            return f"Cannot write outside project. Give user the command for writing to {path}"
        else:
            return (
                f"Operation '{operation}' blocked outside project. "
                f"Give user the command or add path to allowed_paths in config."
            )
