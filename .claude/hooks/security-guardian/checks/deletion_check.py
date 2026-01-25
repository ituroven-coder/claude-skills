"""File deletion security check."""

from pathlib import Path

from checks.base import CheckResult, SecurityCheck
from parsers.bash_parser import ParsedCommand, extract_paths_from_command
from parsers.path_parser import get_project_root, is_path_within_allowed, resolve_path


class DeletionCheck(SecurityCheck):
    """Check for dangerous file deletion operations."""

    name = "deletion_check"

    # Commands that delete files
    DELETE_COMMANDS = {"rm", "rmdir", "unlink", "shred"}

    # Dangerous flags for rm
    DANGEROUS_RM_FLAGS = {"-r", "-R", "--recursive", "-rf", "-fr", "-Rf", "-fR"}

    def __init__(self, config):
        super().__init__(config)
        self.project_root = get_project_root()
        self.allowed_paths = config.directories.allowed_paths

    def check_command(
        self,
        raw_command: str,
        parsed_commands: list[ParsedCommand],
    ) -> CheckResult:
        """Check deletion commands for safety."""
        for cmd in parsed_commands:
            if cmd.command in self.DELETE_COMMANDS:
                result = self._check_deletion(cmd)
                if not result.is_allowed:
                    return result

            # Check piped commands
            if cmd.pipes_to:
                result = self.check_command(raw_command, [cmd.pipes_to])
                if not result.is_allowed:
                    return result

        return self._allow()

    def _check_deletion(self, cmd: ParsedCommand) -> CheckResult:
        """Check a single deletion command."""
        paths = extract_paths_from_command(cmd)
        has_recursive = any(f in self.DANGEROUS_RM_FLAGS for f in cmd.flags)
        has_force = "-f" in cmd.flags or "--force" in cmd.flags

        for path_str in paths:
            resolved = resolve_path(path_str)

            # Check if path is outside project
            if not is_path_within_allowed(
                resolved, self.project_root, self.allowed_paths
            ):
                return self._block(
                    reason=f"Cannot delete files outside project: {path_str}",
                    guidance=f"Give user the command: `rm {' '.join(cmd.flags)} {path_str}`",
                )

            # Check for dangerous recursive deletion of important paths
            if has_recursive:
                result = self._check_dangerous_recursive_delete(resolved, path_str, cmd)
                if not result.is_allowed:
                    return result

        return self._allow()

    def _check_dangerous_recursive_delete(
        self, resolved: Path, original_path: str, cmd: ParsedCommand
    ) -> CheckResult:
        """Check for dangerous recursive deletion patterns."""
        # Get path relative to project root
        try:
            rel_path = resolved.relative_to(self.project_root)
            rel_str = str(rel_path)
        except ValueError:
            # Already handled by directory check
            return self._allow()

        # Check protected directories
        protected = self._get_protected_directories()
        for protected_path in protected:
            if rel_str == protected_path or rel_str.startswith(protected_path + "/"):
                return self._block(
                    reason=f"Cannot recursively delete protected path: {original_path}",
                    guidance=f"Path '{original_path}' is protected. Give user the command if needed.",
                )

        # Warn about recursive deletion at project root
        if resolved == self.project_root or rel_str == ".":
            return self._block(
                reason="Cannot recursively delete project root",
                guidance="Deleting entire project is blocked. Be more specific about what to delete.",
            )

        return self._allow()

    def _get_protected_directories(self) -> list[str]:
        """Get list of protected directories that shouldn't be recursively deleted."""
        # Extract from no_modify patterns
        protected = []
        for pattern in self.config.protected_paths.no_modify:
            # Remove glob wildcards to get base path
            base = pattern.split("*")[0].rstrip("/")
            if base and base != ".":
                protected.append(base)

        # Always protect .git
        if ".git" not in protected:
            protected.append(".git")

        return protected
