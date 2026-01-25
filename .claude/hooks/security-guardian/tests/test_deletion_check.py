"""Tests for deletion check."""

import pytest

from checks.deletion_check import DeletionCheck
from config import SecurityConfig
from parsers.bash_parser import parse_bash_command


@pytest.fixture
def deletion_check(temp_project_dir, config):
    """Create DeletionCheck with config."""
    return DeletionCheck(config)


class TestDeletionCheck:
    """Tests for DeletionCheck."""

    def test_rm_outside_project_blocked(self, deletion_check):
        """Test that rm outside project is blocked."""
        cmd = "rm /home/user/file.txt"
        parsed = parse_bash_command(cmd)
        result = deletion_check.check_command(cmd, parsed)
        assert result.is_blocked

    def test_rm_rf_outside_project_blocked(self, deletion_check):
        """Test that rm -rf outside project is blocked."""
        cmd = "rm -rf ~/Documents"
        parsed = parse_bash_command(cmd)
        result = deletion_check.check_command(cmd, parsed)
        assert result.is_blocked

    def test_rm_in_project_allowed(self, deletion_check, temp_project_dir):
        """Test that rm in project is allowed."""
        test_file = temp_project_dir / "test.txt"
        test_file.touch()

        cmd = f"rm {test_file}"
        parsed = parse_bash_command(cmd)
        result = deletion_check.check_command(cmd, parsed)
        assert result.is_allowed

    def test_rm_rf_node_modules_allowed(self, deletion_check, temp_project_dir):
        """Test that rm -rf node_modules is allowed."""
        node_modules = temp_project_dir / "node_modules"
        node_modules.mkdir()

        cmd = f"rm -rf {node_modules}"
        parsed = parse_bash_command(cmd)
        result = deletion_check.check_command(cmd, parsed)
        assert result.is_allowed

    def test_rm_git_directory_blocked(self, deletion_check, temp_project_dir):
        """Test that rm -rf .git is blocked."""
        git_dir = temp_project_dir / ".git"

        cmd = f"rm -rf {git_dir}"
        parsed = parse_bash_command(cmd)
        result = deletion_check.check_command(cmd, parsed)
        assert result.is_blocked

    def test_rm_project_root_blocked(self, deletion_check, temp_project_dir):
        """Test that rm -rf project root is blocked."""
        cmd = f"rm -rf {temp_project_dir}"
        parsed = parse_bash_command(cmd)
        result = deletion_check.check_command(cmd, parsed)
        assert result.is_blocked

    def test_unlink_outside_blocked(self, deletion_check):
        """Test that unlink outside project is blocked."""
        cmd = "unlink /etc/important.conf"
        parsed = parse_bash_command(cmd)
        result = deletion_check.check_command(cmd, parsed)
        assert result.is_blocked
