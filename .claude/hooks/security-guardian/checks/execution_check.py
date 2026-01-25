"""Execution permission check for downloaded files."""

import subprocess
from pathlib import Path
from typing import Optional, TYPE_CHECKING

from checks.base import CheckResult, SecurityCheck
from parsers.bash_parser import ParsedCommand, extract_paths_from_command
from parsers.path_parser import get_project_root, is_git_tracked, resolve_path

if TYPE_CHECKING:
    from checks.download_check import DownloadCheck


class ExecutionCheck(SecurityCheck):
    """Check for chmod +x on downloaded or suspicious files."""

    name = "execution_check"

    # Binary magic bytes for detection
    BINARY_MAGIC = {
        b"\x7fELF": "ELF executable",
        b"MZ": "Windows PE executable",
        b"\xfe\xed\xfa\xce": "Mach-O 32-bit",
        b"\xfe\xed\xfa\xcf": "Mach-O 64-bit",
        b"\xca\xfe\xba\xbe": "Mach-O universal",
        b"#!": "Script with shebang",
    }

    def __init__(self, config):
        super().__init__(config)
        self.project_root = get_project_root()
        # Create download check instance for tracking
        self._download_check: Optional["DownloadCheck"] = None

    def _get_download_check(self):
        """Lazy load download check for file tracking."""
        if self._download_check is None:
            from checks.download_check import DownloadCheck
            self._download_check = DownloadCheck(self.config)
        return self._download_check

    def check_command(
        self,
        raw_command: str,
        parsed_commands: list[ParsedCommand],
    ) -> CheckResult:
        """Check chmod commands for safety."""
        for cmd in parsed_commands:
            if cmd.command == "chmod":
                result = self._check_chmod(cmd)
                if not result.is_allowed:
                    return result

        return self._allow()

    def _check_chmod(self, cmd: ParsedCommand) -> CheckResult:
        """Check a chmod command for making downloaded files executable."""
        # Check if making executable (+x)
        is_making_executable = self._is_making_executable(cmd)
        if not is_making_executable:
            return self._allow()

        # Get target paths
        paths = extract_paths_from_command(cmd)

        for path_str in paths:
            # Skip mode arguments (like +x, 755)
            if path_str.startswith("+") or path_str.isdigit():
                continue

            resolved = resolve_path(path_str)

            # Check if git-tracked (allowed)
            if self.config.download_protection.git_tracked_allow:
                if is_git_tracked(resolved, self.project_root):
                    continue

            # Check if previously downloaded
            download_check = self._get_download_check()
            if download_check.is_downloaded_file(path_str):
                return self._confirm(
                    reason=f"chmod +x on downloaded file: {path_str}",
                    guidance=f"File was downloaded from internet. Give user: `chmod +x {path_str}`",
                )

            # Check file type if enabled
            if self.config.download_protection.detect_binary_by_magic:
                result = self._check_binary_type(resolved, path_str)
                if result is not None and not result.is_allowed:
                    return result

        return self._allow()

    def _is_making_executable(self, cmd: ParsedCommand) -> bool:
        """Check if chmod command makes file executable."""
        for arg in cmd.args + cmd.flags:
            # +x, a+x, u+x, g+x, o+x patterns
            if "+x" in arg:
                return True
            # Numeric modes: 7xx, x7x, xx7 (contains execute bit)
            if arg.isdigit() and len(arg) >= 3:
                for digit in arg:
                    if int(digit) & 1:  # Execute bit set
                        return True
        return False

    def _check_binary_type(
        self, path: Path, original_path: str
    ) -> Optional[CheckResult]:
        """Check file type using file command or magic bytes."""
        if not path.exists():
            return None

        # Try file command first
        try:
            result = subprocess.run(
                ["file", "-b", str(path)],
                capture_output=True,
                text=True,
                timeout=5,
            )
            if result.returncode == 0:
                output = result.stdout.lower()
                if any(
                    t in output
                    for t in ["executable", "script", "elf", "mach-o", "pe32"]
                ):
                    return self._confirm(
                        reason=f"chmod +x on binary/script file: {original_path}",
                        guidance=f"File appears to be executable. Give user: `chmod +x {original_path}`",
                    )
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            # Fallback to magic bytes if file command unavailable
            if self.config.download_protection.file_command_fallback:
                return self._check_magic_bytes(path, original_path)

        return None

    def _check_magic_bytes(
        self, path: Path, original_path: str
    ) -> Optional[CheckResult]:
        """Check file type by reading magic bytes."""
        try:
            with open(path, "rb") as f:
                header = f.read(8)

            for magic, file_type in self.BINARY_MAGIC.items():
                if header.startswith(magic):
                    return self._confirm(
                        reason=f"chmod +x on {file_type}: {original_path}",
                        guidance=f"File is {file_type}. Give user: `chmod +x {original_path}`",
                    )
        except (OSError, IOError):
            pass

        return None
