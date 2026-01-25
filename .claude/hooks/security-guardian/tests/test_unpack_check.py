"""Tests for unpack protection check."""

import pytest

from checks.unpack_check import UnpackCheck
from config import SecurityConfig
from parsers.bash_parser import parse_bash_command


@pytest.fixture
def unpack_check(temp_project_dir, config):
    """Create UnpackCheck with config."""
    return UnpackCheck(config)


class TestUnpackCheck:
    """Tests for UnpackCheck."""

    def test_tar_outside_project_blocked(self, unpack_check):
        """Test that tar extraction outside project is blocked."""
        cmd = "tar -C /tmp/outside -xf archive.tar"
        parsed = parse_bash_command(cmd)
        result = unpack_check.check_command(cmd, parsed)
        assert result.is_blocked

    def test_tar_relative_escape_blocked(self, unpack_check):
        """Test that tar with relative path escape is blocked."""
        cmd = "tar -C ../outside -xf archive.tar"
        parsed = parse_bash_command(cmd)
        result = unpack_check.check_command(cmd, parsed)
        assert result.is_blocked

    def test_unzip_outside_project_blocked(self, unpack_check):
        """Test that unzip outside project is blocked."""
        cmd = "unzip -d /tmp/outside file.zip"
        parsed = parse_bash_command(cmd)
        result = unpack_check.check_command(cmd, parsed)
        assert result.is_blocked

    def test_unzip_relative_escape_blocked(self, unpack_check):
        """Test that unzip with relative escape is blocked."""
        cmd = "unzip -d ../outside file.zip"
        parsed = parse_bash_command(cmd)
        result = unpack_check.check_command(cmd, parsed)
        assert result.is_blocked

    def test_bsdtar_substitution_blocked(self, unpack_check):
        """Test that bsdtar -s is blocked."""
        cmd = "bsdtar -s '/^/tmp/' -xf archive.tar"
        parsed = parse_bash_command(cmd)
        result = unpack_check.check_command(cmd, parsed)
        assert result.is_blocked

    def test_python_zipfile_outside_blocked(self, unpack_check):
        """Test that python zipfile extraction outside is blocked."""
        cmd = "python -m zipfile -e archive.zip /tmp/outside"
        parsed = parse_bash_command(cmd)
        result = unpack_check.check_command(cmd, parsed)
        assert result.is_blocked

    def test_tar_in_project_allowed(self, unpack_check, temp_project_dir):
        """Test that tar in project is allowed."""
        cmd = f"tar -xf archive.tar -C {temp_project_dir}"
        parsed = parse_bash_command(cmd)
        result = unpack_check.check_command(cmd, parsed)
        assert result.is_allowed

    def test_tar_current_dir_allowed(self, unpack_check):
        """Test that tar in current directory is allowed."""
        cmd = "tar -xf archive.tar"
        parsed = parse_bash_command(cmd)
        result = unpack_check.check_command(cmd, parsed)
        assert result.is_allowed

    def test_unzip_current_dir_allowed(self, unpack_check):
        """Test that unzip in current directory is allowed."""
        cmd = "unzip file.zip"
        parsed = parse_bash_command(cmd)
        result = unpack_check.check_command(cmd, parsed)
        assert result.is_allowed
