"""Pytest fixtures for Security Guardian tests."""

import os
import tempfile
from pathlib import Path

import pytest

from config import load_config, SecurityConfig


@pytest.fixture
def temp_project_dir():
    """Create a temporary project directory."""
    with tempfile.TemporaryDirectory() as tmpdir:
        # Create .git directory to mark as project root
        git_dir = Path(tmpdir) / ".git"
        git_dir.mkdir()

        # Set environment variable
        old_env = os.environ.get("CLAUDE_PROJECT_DIR")
        os.environ["CLAUDE_PROJECT_DIR"] = tmpdir

        yield Path(tmpdir)

        # Restore environment
        if old_env:
            os.environ["CLAUDE_PROJECT_DIR"] = old_env
        else:
            os.environ.pop("CLAUDE_PROJECT_DIR", None)


@pytest.fixture
def config():
    """Load default configuration."""
    return load_config()


@pytest.fixture
def minimal_config():
    """Create minimal configuration for testing."""
    return SecurityConfig()
