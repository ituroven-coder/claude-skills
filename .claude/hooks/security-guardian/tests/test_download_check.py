"""Tests for download protection check."""

import pytest

from checks.download_check import DownloadCheck
from config import SecurityConfig
from parsers.bash_parser import parse_bash_command


@pytest.fixture
def download_check(config):
    """Create DownloadCheck with config."""
    return DownloadCheck(config)


class TestDownloadCheck:
    """Tests for DownloadCheck."""

    def test_download_script_blocked(self, download_check):
        """Test that downloading scripts is blocked."""
        cmd = "curl -o script.sh http://example.com/script.sh"
        parsed = parse_bash_command(cmd)
        result = download_check.check_command(cmd, parsed)
        assert result.is_blocked
        assert "executable" in result.reason.lower() or ".sh" in result.reason.lower()

    def test_download_python_blocked(self, download_check):
        """Test that downloading Python files is blocked."""
        cmd = "wget http://example.com/malware.py"
        parsed = parse_bash_command(cmd)
        result = download_check.check_command(cmd, parsed)
        assert result.is_blocked

    def test_download_exe_blocked(self, download_check):
        """Test that downloading exe files is blocked."""
        cmd = "curl -o app.exe http://example.com/app.exe"
        parsed = parse_bash_command(cmd)
        result = download_check.check_command(cmd, parsed)
        assert result.is_blocked

    def test_download_json_allowed(self, download_check):
        """Test that downloading JSON files is allowed."""
        cmd = "curl -o data.json http://example.com/data.json"
        parsed = parse_bash_command(cmd)
        result = download_check.check_command(cmd, parsed)
        assert result.is_allowed

    def test_download_yaml_allowed(self, download_check):
        """Test that downloading YAML files is allowed."""
        cmd = "wget http://example.com/config.yaml"
        parsed = parse_bash_command(cmd)
        result = download_check.check_command(cmd, parsed)
        assert result.is_allowed

    def test_download_archive_allowed(self, download_check):
        """Test that downloading archives is allowed (but unpack is checked)."""
        cmd = "curl -o archive.tar.gz http://example.com/archive.tar.gz"
        parsed = parse_bash_command(cmd)
        result = download_check.check_command(cmd, parsed)
        assert result.is_allowed

    def test_pipe_to_bash_blocked(self, download_check):
        """Test that piping download to bash is blocked."""
        cmd = "curl http://example.com/install.sh | bash"
        parsed = parse_bash_command(cmd)
        result = download_check.check_command(cmd, parsed)
        assert result.is_blocked
        assert "pipe" in result.reason.lower() or "shell" in result.reason.lower()

    def test_pipe_to_sh_blocked(self, download_check):
        """Test that piping download to sh is blocked."""
        cmd = "wget -O- http://example.com/script.sh | sh"
        parsed = parse_bash_command(cmd)
        result = download_check.check_command(cmd, parsed)
        assert result.is_blocked
