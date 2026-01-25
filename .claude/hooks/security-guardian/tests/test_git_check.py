"""Tests for git operations check."""

import os
import pytest

from checks.git_check import GitCheck
from config import SecurityConfig
from parsers.bash_parser import parse_bash_command


@pytest.fixture
def git_check(config):
    """Create GitCheck with config."""
    return GitCheck(config)


class TestGitCheck:
    """Tests for GitCheck."""

    def test_push_force_blocked(self, git_check):
        """Test that git push --force is blocked."""
        cmd = "git push --force origin main"
        parsed = parse_bash_command(cmd)
        result = git_check.check_command(cmd, parsed)
        assert result.is_blocked
        assert "--force-with-lease" in result.guidance

    def test_push_force_with_lease_allowed(self, git_check):
        """Test that git push --force-with-lease is allowed."""
        cmd = "git push --force-with-lease origin main"
        parsed = parse_bash_command(cmd)
        result = git_check.check_command(cmd, parsed)
        assert result.is_allowed

    def test_reset_hard_confirm(self, git_check):
        """Test that git reset --hard requires confirmation."""
        cmd = "git reset --hard HEAD~1"
        parsed = parse_bash_command(cmd)
        result = git_check.check_command(cmd, parsed)
        assert result.needs_confirmation or result.is_blocked

    def test_branch_delete_confirm(self, git_check):
        """Test that git branch -D requires confirmation."""
        cmd = "git branch -D feature-branch"
        parsed = parse_bash_command(cmd)
        result = git_check.check_command(cmd, parsed)
        assert result.needs_confirmation or result.is_blocked

    def test_clean_fd_confirm(self, git_check):
        """Test that git clean -fd requires confirmation."""
        cmd = "git clean -fd"
        parsed = parse_bash_command(cmd)
        result = git_check.check_command(cmd, parsed)
        assert result.needs_confirmation or result.is_blocked

    def test_clean_dry_run_allowed(self, git_check):
        """Test that git clean --dry-run is allowed."""
        cmd = "git clean -fd --dry-run"
        parsed = parse_bash_command(cmd)
        result = git_check.check_command(cmd, parsed)
        assert result.is_allowed

    def test_normal_push_allowed(self, git_check):
        """Test that normal git push is allowed."""
        cmd = "git push origin main"
        parsed = parse_bash_command(cmd)
        result = git_check.check_command(cmd, parsed)
        assert result.is_allowed

    def test_normal_commit_allowed(self, git_check):
        """Test that git commit is allowed."""
        cmd = "git commit -m 'message'"
        parsed = parse_bash_command(cmd)
        result = git_check.check_command(cmd, parsed)
        assert result.is_allowed


class TestCIAutoAllow:
    """Tests for CI auto-allow."""

    def test_clean_in_ci_allowed(self, config):
        """Test that git clean is allowed in CI."""
        # Set CI environment
        old_ci = os.environ.get("CI")
        os.environ["CI"] = "true"

        try:
            git_check = GitCheck(config)
            cmd = "git clean -fd"
            parsed = parse_bash_command(cmd)
            result = git_check.check_command(cmd, parsed)
            assert result.is_allowed
        finally:
            if old_ci:
                os.environ["CI"] = old_ci
            else:
                os.environ.pop("CI", None)

    def test_reset_hard_in_ci_allowed(self, config):
        """Test that git reset --hard is allowed in CI."""
        old_ci = os.environ.get("CI")
        os.environ["CI"] = "true"

        try:
            git_check = GitCheck(config)
            cmd = "git reset --hard HEAD"
            parsed = parse_bash_command(cmd)
            result = git_check.check_command(cmd, parsed)
            assert result.is_allowed
        finally:
            if old_ci:
                os.environ["CI"] = old_ci
            else:
                os.environ.pop("CI", None)
