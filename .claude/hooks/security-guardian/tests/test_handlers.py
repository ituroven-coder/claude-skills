"""Tests for tool handlers."""

import pytest

from handlers.bash_handler import BashHandler
from handlers.read_handler import ReadHandler
from handlers.write_handler import WriteHandler
from handlers.glob_grep_handler import GlobGrepHandler
from config import SecurityConfig


@pytest.fixture
def bash_handler(temp_project_dir, config):
    """Create BashHandler with config."""
    return BashHandler(config)


@pytest.fixture
def read_handler(temp_project_dir, config):
    """Create ReadHandler with config."""
    return ReadHandler(config)


@pytest.fixture
def write_handler(temp_project_dir, config):
    """Create WriteHandler with config."""
    return WriteHandler(config)


@pytest.fixture
def glob_handler(temp_project_dir, config):
    """Create GlobGrepHandler with config."""
    return GlobGrepHandler(config)


class TestBashHandler:
    """Tests for BashHandler."""

    def test_handle_safe_command(self, bash_handler, temp_project_dir):
        """Test handling safe command."""
        test_file = temp_project_dir / "test.txt"
        test_file.touch()

        result = bash_handler.handle({"command": f"cat {test_file}"})
        assert result.is_allowed

    def test_handle_dangerous_command(self, bash_handler):
        """Test handling dangerous command."""
        result = bash_handler.handle({"command": "cat /etc/passwd"})
        assert result.is_blocked

    def test_handle_empty_command(self, bash_handler):
        """Test handling empty command."""
        result = bash_handler.handle({"command": ""})
        assert result.is_allowed

    def test_handle_git_force_push(self, bash_handler):
        """Test handling git push --force."""
        result = bash_handler.handle({"command": "git push --force origin main"})
        assert result.is_blocked


class TestReadHandler:
    """Tests for ReadHandler."""

    def test_handle_read_in_project(self, read_handler, temp_project_dir):
        """Test reading file in project."""
        test_file = temp_project_dir / "test.txt"
        test_file.touch()

        result = read_handler.handle({"file_path": str(test_file)})
        assert result.is_allowed

    def test_handle_read_outside_project(self, read_handler):
        """Test reading file outside project."""
        result = read_handler.handle({"file_path": "/etc/passwd"})
        assert result.is_blocked

    def test_handle_read_env_file(self, read_handler, temp_project_dir):
        """Test reading .env file."""
        env_file = temp_project_dir / ".env"
        env_file.touch()

        result = read_handler.handle({"file_path": str(env_file)})
        assert result.is_blocked

    def test_handle_read_env_example(self, read_handler, temp_project_dir):
        """Test reading .env.example file."""
        env_example = temp_project_dir / ".env.example"
        env_example.touch()

        result = read_handler.handle({"file_path": str(env_example)})
        assert result.is_allowed


class TestWriteHandler:
    """Tests for WriteHandler."""

    def test_handle_write_in_project(self, write_handler, temp_project_dir):
        """Test writing file in project."""
        test_file = temp_project_dir / "new_file.txt"

        result = write_handler.handle({"file_path": str(test_file)})
        assert result.is_allowed

    def test_handle_write_outside_project(self, write_handler):
        """Test writing file outside project."""
        result = write_handler.handle({"file_path": "/tmp/outside.txt"})
        assert result.is_blocked

    def test_handle_write_settings(self, write_handler, temp_project_dir):
        """Test writing settings.json."""
        settings = temp_project_dir / ".claude" / "settings.json"
        settings.parent.mkdir(parents=True, exist_ok=True)

        result = write_handler.handle({"file_path": str(settings)})
        assert result.is_blocked


class TestGlobHandler:
    """Tests for GlobGrepHandler."""

    def test_handle_glob_in_project(self, glob_handler, temp_project_dir):
        """Test glob in project."""
        result = glob_handler.handle({"path": str(temp_project_dir)})
        assert result.is_allowed

    def test_handle_glob_outside_project(self, glob_handler):
        """Test glob outside project."""
        result = glob_handler.handle({"path": "/home"})
        assert result.is_blocked

    def test_handle_glob_no_path(self, glob_handler):
        """Test glob without path (defaults to cwd)."""
        result = glob_handler.handle({})
        assert result.is_allowed
