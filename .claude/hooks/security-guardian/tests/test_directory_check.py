"""Tests for directory boundary check."""

import os
import tempfile
from pathlib import Path

import pytest

from checks.directory_check import DirectoryCheck
from config import SecurityConfig


@pytest.fixture
def directory_check(temp_project_dir, config):
    """Create DirectoryCheck with temp project."""
    return DirectoryCheck(config)


class TestDirectoryCheck:
    """Tests for DirectoryCheck."""

    def test_path_inside_project_allowed(self, directory_check, temp_project_dir):
        """Test that paths inside project are allowed."""
        # Create a file inside project
        test_file = temp_project_dir / "test.txt"
        test_file.touch()

        result = directory_check.check_path(str(test_file), operation="cat")
        assert result.is_allowed

    def test_path_outside_project_blocked(self, directory_check):
        """Test that paths outside project are blocked."""
        result = directory_check.check_path("/etc/passwd", operation="cat")
        assert result.is_blocked
        assert "outside project" in result.reason.lower()

    def test_relative_path_escape_blocked(self, directory_check):
        """Test that relative path escape is blocked."""
        result = directory_check.check_path("../../../etc/passwd", operation="cat")
        assert result.is_blocked

    def test_home_directory_blocked(self, directory_check):
        """Test that home directory access is blocked."""
        result = directory_check.check_path("~/notes.txt", operation="cat")
        assert result.is_blocked

    def test_symlink_escape_blocked(self, directory_check, temp_project_dir):
        """Test that symlink escape is blocked."""
        # Create a symlink pointing outside project
        link_path = temp_project_dir / "escape_link"
        try:
            link_path.symlink_to("/etc")
        except OSError:
            pytest.skip("Cannot create symlinks")

        result = directory_check.check_path(str(link_path / "passwd"), operation="cat")
        assert result.is_blocked
        assert "symlink" in result.reason.lower() or "outside" in result.reason.lower()

    def test_command_with_outside_path_blocked(self, directory_check, config):
        """Test command that accesses outside path is blocked."""
        from parsers.bash_parser import parse_bash_command

        parsed = parse_bash_command("cat /home/user/secret.txt")
        result = directory_check.check_command("cat /home/user/secret.txt", parsed)
        assert result.is_blocked

    def test_command_inside_project_allowed(self, directory_check, temp_project_dir):
        """Test command inside project is allowed."""
        from parsers.bash_parser import parse_bash_command

        test_file = temp_project_dir / "file.txt"
        test_file.touch()

        cmd = f"cat {test_file}"
        parsed = parse_bash_command(cmd)
        result = directory_check.check_command(cmd, parsed)
        assert result.is_allowed


class TestAllowedPaths:
    """Tests for allowed paths configuration."""

    def test_allowed_path_access(self, temp_project_dir):
        """Test that explicitly allowed paths work."""
        # Create a temp directory outside project
        with tempfile.TemporaryDirectory() as allowed_dir:
            config = SecurityConfig()
            config.directories.allowed_paths = [allowed_dir]

            check = DirectoryCheck(config)

            # Access to allowed path should work
            result = check.check_path(f"{allowed_dir}/file.txt", operation="cat")
            assert result.is_allowed
