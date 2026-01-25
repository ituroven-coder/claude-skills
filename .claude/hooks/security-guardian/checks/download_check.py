"""Download protection check."""

import json
import os
from pathlib import Path
from typing import Optional

from checks.base import CheckResult, SecurityCheck
from parsers.bash_parser import ParsedCommand, is_pipe_to_shell
from parsers.path_parser import get_project_root, resolve_path


class DownloadCheck(SecurityCheck):
    """Check for dangerous download operations."""

    name = "download_check"

    # Commands that download files
    DOWNLOAD_COMMANDS = {"curl", "wget", "fetch", "aria2c"}

    def __init__(self, config):
        super().__init__(config)
        self.project_root = get_project_root()
        self._downloaded_files: Optional[dict] = None

    def check_command(
        self,
        raw_command: str,
        parsed_commands: list[ParsedCommand],
    ) -> CheckResult:
        """Check download commands for safety."""
        # First check for pipe to shell (always blocked)
        shell_targets = self.config.bypass_prevention.block_shell_pipe_targets
        if is_pipe_to_shell(parsed_commands, shell_targets):
            return self._block(
                reason="Downloading and piping to shell detected",
                guidance="Cannot pipe downloads to shell. Download file, review, then run.",
            )

        for cmd in parsed_commands:
            if cmd.command in self.DOWNLOAD_COMMANDS:
                result = self._check_download(cmd)
                if not result.is_allowed:
                    return result

        return self._allow()

    def _check_download(self, cmd: ParsedCommand) -> CheckResult:
        """Check a single download command."""
        # Extract URL and output path
        url = self._extract_url(cmd)
        output_path = self._extract_output_path(cmd)

        if not url:
            return self._allow()

        # Get file extension from URL or output path
        extension = self._get_extension(url, output_path)

        # Check if extension requires user download
        require_user = self.config.download_protection.require_user_download
        if extension and any(ext for ext in require_user if extension.endswith(ext)):
            output_info = f" to {output_path}" if output_path else ""
            return self._block(
                reason=f"Download of executable file blocked: *{extension}",
                guidance=(
                    f"Cannot download executable files. "
                    f"Give user the command: `{cmd.command} {' '.join(cmd.flags)} {' '.join(cmd.args)}`"
                ),
            )

        # Auto-download data files are allowed
        auto_download = self.config.download_protection.auto_download
        if extension and any(ext for ext in auto_download if extension.endswith(ext)):
            return self._allow()

        # Archives can be downloaded but will be checked on unpack
        auto_with_check = self.config.download_protection.auto_download_but_check_unpack
        if extension and any(ext for ext in auto_with_check if extension.endswith(ext)):
            return self._allow()

        # Unknown extension - allow but track for execution check
        if self.config.download_protection.track_downloaded_executables:
            self._track_downloaded_file(url, output_path)

        return self._allow()

    def _extract_url(self, cmd: ParsedCommand) -> Optional[str]:
        """Extract URL from download command arguments."""
        for arg in cmd.args:
            if arg.startswith("http://") or arg.startswith("https://"):
                return arg
            if arg.startswith("ftp://"):
                return arg
        return None

    def _extract_output_path(self, cmd: ParsedCommand) -> Optional[str]:
        """Extract output path from download command flags."""
        flags_with_output = {"-o", "-O", "--output"}

        for i, flag in enumerate(cmd.flags):
            if flag in flags_with_output:
                # Output path might be in next arg
                remaining_args = cmd.args[:]
                for arg in remaining_args:
                    if not arg.startswith("-") and not arg.startswith("http"):
                        return arg

        # Check for -o=value or --output=value format
        for flag in cmd.flags:
            if flag.startswith("-o=") or flag.startswith("--output="):
                return flag.split("=", 1)[1]

        # For wget without -O, output is usually last part of URL
        return None

    def _get_extension(
        self, url: Optional[str], output_path: Optional[str]
    ) -> Optional[str]:
        """Get file extension from URL or output path."""
        # Prefer output path if available
        if output_path:
            path = Path(output_path)
            # Handle multiple extensions like .tar.gz
            suffixes = path.suffixes
            if suffixes:
                return "".join(suffixes)

        # Fall back to URL
        if url:
            # Remove query params
            clean_url = url.split("?")[0]
            path = Path(clean_url)
            suffixes = path.suffixes
            if suffixes:
                return "".join(suffixes)

        return None

    def _get_downloaded_files_path(self) -> Path:
        """Get path to downloaded files metadata."""
        metadata_path = self.config.download_protection.downloaded_files_metadata
        return self.project_root / metadata_path

    def _load_downloaded_files(self) -> dict:
        """Load downloaded files metadata."""
        if self._downloaded_files is not None:
            return self._downloaded_files

        metadata_path = self._get_downloaded_files_path()
        if metadata_path.exists():
            try:
                with open(metadata_path) as f:
                    self._downloaded_files = json.load(f)
            except (json.JSONDecodeError, OSError):
                self._downloaded_files = {}
        else:
            self._downloaded_files = {}

        return self._downloaded_files

    def _save_downloaded_files(self) -> None:
        """Save downloaded files metadata."""
        if self._downloaded_files is None:
            return

        metadata_path = self._get_downloaded_files_path()

        # Ensure parent directory exists
        metadata_path.parent.mkdir(parents=True, exist_ok=True)

        try:
            with open(metadata_path, "w") as f:
                json.dump(self._downloaded_files, f, indent=2)
        except OSError:
            pass  # Ignore write errors for metadata

    def _track_downloaded_file(self, url: str, output_path: Optional[str]) -> None:
        """Track a downloaded file for later execution check."""
        if not self.config.download_protection.track_downloaded_executables:
            return

        files = self._load_downloaded_files()

        # Use output path or derive from URL
        if output_path:
            resolved = str(resolve_path(output_path))
        else:
            # Extract filename from URL
            filename = url.split("/")[-1].split("?")[0]
            resolved = str(resolve_path(filename))

        files[resolved] = {
            "url": url,
            "downloaded_at": str(Path.cwd()),
            "checked_binary": False,
        }

        self._downloaded_files = files
        self._save_downloaded_files()

    def is_downloaded_file(self, path: str) -> bool:
        """Check if a file was previously downloaded."""
        files = self._load_downloaded_files()
        resolved = str(resolve_path(path))
        return resolved in files
