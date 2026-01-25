"""Archive unpacking security check."""

from pathlib import Path

from checks.base import CheckResult, SecurityCheck
from parsers.bash_parser import ParsedCommand, extract_paths_from_command
from parsers.path_parser import (
    check_archive_path_traversal,
    get_project_root,
    is_path_within_allowed,
    resolve_path,
)


class UnpackCheck(SecurityCheck):
    """Check for dangerous archive unpacking operations."""

    name = "unpack_check"

    # Commands that unpack archives
    UNPACK_COMMANDS = {
        "tar",
        "unzip",
        "unrar",
        "7z",
        "7za",
        "bsdtar",
        "gunzip",
        "bunzip2",
        "unxz",
    }

    # Python module unpack patterns
    PYTHON_UNPACK_PATTERNS = [
        "python -m zipfile -e",
        "python3 -m zipfile -e",
        "python -m tarfile -e",
        "python3 -m tarfile -e",
    ]

    def __init__(self, config):
        super().__init__(config)
        self.project_root = get_project_root()
        self.allowed_paths = config.directories.allowed_paths

    def check_command(
        self,
        raw_command: str,
        parsed_commands: list[ParsedCommand],
    ) -> CheckResult:
        """Check unpack commands for safety."""
        # Check for blocked patterns in raw command
        for pattern in self.config.unpack_protection.blocked_patterns:
            if pattern in raw_command:
                return self._block(
                    reason=f"Blocked unpack pattern: {pattern}",
                    guidance=f"Unpack to allowed directory only. Give user: `{raw_command}`",
                )

        # Check for Python unpack modules
        for pattern in self.PYTHON_UNPACK_PATTERNS:
            if pattern in raw_command:
                result = self._check_python_unpack(raw_command)
                if not result.is_allowed:
                    return result

        # Check each unpack command
        for cmd in parsed_commands:
            if cmd.command in self.UNPACK_COMMANDS:
                result = self._check_unpack(cmd, raw_command)
                if not result.is_allowed:
                    return result

        return self._allow()

    def _check_unpack(self, cmd: ParsedCommand, raw_command: str) -> CheckResult:
        """Check a single unpack command."""
        target_dir = self._extract_target_directory(cmd)

        if target_dir:
            # Check if target is outside project
            resolved = resolve_path(target_dir)
            if not is_path_within_allowed(
                resolved, self.project_root, self.allowed_paths
            ):
                return self._block(
                    reason=f"Unpack target outside project: {target_dir}",
                    guidance=f"Cannot unpack outside project. Give user: `{raw_command}`",
                )

            # Check for path traversal
            if check_archive_path_traversal(target_dir):
                return self._block(
                    reason=f"Path traversal in unpack target: {target_dir}",
                    guidance="Path traversal detected. Give user the command.",
                )

        # Check bsdtar -s (renaming can bypass protection)
        if cmd.command == "bsdtar" and "-s" in cmd.flags:
            return self._block(
                reason="bsdtar -s (substitution) can bypass path protection",
                guidance="bsdtar -s is blocked. Give user the command.",
            )

        return self._allow()

    def _extract_target_directory(self, cmd: ParsedCommand) -> str | None:
        """Extract target directory from unpack command."""
        # Get all tokens from raw command for proper parsing
        raw_tokens = cmd.raw.split() if cmd.raw else []

        # tar: -C, --directory
        if cmd.command in ("tar", "bsdtar"):
            # Check raw tokens for -C or --directory followed by path
            for i, token in enumerate(raw_tokens):
                if token in ("-C", "--directory") and i + 1 < len(raw_tokens):
                    return raw_tokens[i + 1]
                if token.startswith("-C") and len(token) > 2:
                    return token[2:]
                if token.startswith("--directory="):
                    return token.split("=", 1)[1]
                if token.startswith("--one-top-level="):
                    return token.split("=", 1)[1]

        # unzip: -d
        if cmd.command == "unzip":
            for i, token in enumerate(raw_tokens):
                if token == "-d" and i + 1 < len(raw_tokens):
                    return raw_tokens[i + 1]
                if token.startswith("-d") and len(token) > 2:
                    return token[2:]

        # 7z: -o
        if cmd.command in ("7z", "7za"):
            for token in raw_tokens:
                if token.startswith("-o") and len(token) > 2:
                    return token[2:]

        return None

    def _check_python_unpack(self, raw_command: str) -> CheckResult:
        """Check Python zipfile/tarfile module usage."""
        # Extract target directory from command
        # Format: python -m zipfile -e archive.zip target_dir
        parts = raw_command.split()

        # Find the -e flag and get the target
        try:
            e_index = parts.index("-e")
            if e_index + 2 < len(parts):
                target_dir = parts[e_index + 2]
                resolved = resolve_path(target_dir)

                if not is_path_within_allowed(
                    resolved, self.project_root, self.allowed_paths
                ):
                    return self._block(
                        reason=f"Python unpack target outside project: {target_dir}",
                        guidance=f"Cannot unpack outside project. Give user: `{raw_command}`",
                    )
        except (ValueError, IndexError):
            pass

        return self._allow()
