"""Tests for secrets check."""

import pytest
from pathlib import Path

from checks.secrets_check import SecretsCheck
from config import SecurityConfig
from parsers.bash_parser import parse_bash_command


@pytest.fixture
def secrets_check(temp_project_dir, config):
    """Create SecretsCheck with temp project."""
    return SecretsCheck(config)


class TestSecretsCheck:
    """Tests for SecretsCheck."""

    def test_env_file_blocked(self, secrets_check, temp_project_dir):
        """Test that .env file is blocked."""
        env_file = temp_project_dir / ".env"
        env_file.touch()

        result = secrets_check.check_path(str(env_file), operation="cat")
        assert result.is_blocked
        assert ".env" in result.reason.lower() or "secrets" in result.reason.lower()

    def test_env_example_allowed(self, secrets_check, temp_project_dir):
        """Test that .env.example is allowed."""
        env_example = temp_project_dir / ".env.example"
        env_example.touch()

        result = secrets_check.check_path(str(env_example), operation="cat")
        assert result.is_allowed

    def test_env_template_allowed(self, secrets_check, temp_project_dir):
        """Test that .env.template is allowed."""
        env_template = temp_project_dir / ".env.template"
        env_template.touch()

        result = secrets_check.check_path(str(env_template), operation="cat")
        assert result.is_allowed

    def test_nested_env_blocked(self, secrets_check, temp_project_dir):
        """Test that nested .env is blocked."""
        nested_dir = temp_project_dir / "config"
        nested_dir.mkdir()
        env_file = nested_dir / ".env"
        env_file.touch()

        result = secrets_check.check_path(str(env_file), operation="cat")
        assert result.is_blocked

    def test_env_local_blocked(self, secrets_check, temp_project_dir):
        """Test that .env.local is blocked."""
        env_file = temp_project_dir / ".env.local"
        env_file.touch()

        result = secrets_check.check_path(str(env_file), operation="cat")
        assert result.is_blocked

    def test_guidance_mentions_example(self, secrets_check, temp_project_dir):
        """Test that guidance mentions .env.example."""
        # Create .env and .env.example
        env_file = temp_project_dir / ".env"
        env_file.touch()
        env_example = temp_project_dir / ".env.example"
        env_example.touch()

        result = secrets_check.check_path(str(env_file), operation="cat")
        assert result.is_blocked
        assert ".env.example" in result.guidance


class TestProtectedPaths:
    """Tests for protected paths modification."""

    def test_git_directory_protected(self, secrets_check, temp_project_dir):
        """Test that .git directory is protected."""
        git_config = temp_project_dir / ".git" / "config"

        result = secrets_check.check_path(str(git_config), operation="write")
        assert result.is_blocked

    def test_settings_json_protected(self, secrets_check, temp_project_dir):
        """Test that settings.json is protected."""
        settings = temp_project_dir / ".claude" / "settings.json"
        settings.parent.mkdir(parents=True, exist_ok=True)
        settings.touch()

        result = secrets_check.check_path(str(settings), operation="write")
        assert result.is_blocked

    def test_regular_file_allowed(self, secrets_check, temp_project_dir):
        """Test that regular files can be written."""
        regular_file = temp_project_dir / "src" / "main.py"
        regular_file.parent.mkdir(parents=True, exist_ok=True)
        regular_file.touch()

        result = secrets_check.check_path(str(regular_file), operation="write")
        assert result.is_allowed
