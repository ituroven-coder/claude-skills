"""Pydantic models for Security Guardian configuration."""

import os
from pathlib import Path
from typing import Optional

import yaml
from pydantic import BaseModel, Field


class DirectoriesConfig(BaseModel):
    """Directory boundaries configuration."""

    project_root: Optional[str] = None
    allowed_paths: list[str] = Field(default_factory=list)


class GitConfig(BaseModel):
    """Git operations configuration."""

    hard_blocked: list[str] = Field(default_factory=list)
    confirm_required: list[str] = Field(default_factory=list)
    allowed: list[str] = Field(default_factory=list)
    ci_auto_allow: list[str] = Field(default_factory=list)


class BypassPreventionConfig(BaseModel):
    """Bypass prevention configuration."""

    blocked_outside_project: list[str] = Field(default_factory=list)
    hard_blocked: list[str] = Field(default_factory=list)
    block_variable_as_command: bool = True
    block_shell_pipe_targets: list[str] = Field(default_factory=list)
    block_shell_exec_patterns: list[str] = Field(default_factory=list)
    confirm_interpreter_inline_with_network: list[str] = Field(default_factory=list)
    network_patterns: list[str] = Field(default_factory=list)
    obfuscation_patterns: list[str] = Field(default_factory=list)
    rce_patterns_require_network: list[str] = Field(default_factory=list)


class DownloadProtectionConfig(BaseModel):
    """Download protection configuration."""

    require_user_download: list[str] = Field(default_factory=list)
    auto_download_but_check_unpack: list[str] = Field(default_factory=list)
    auto_download: list[str] = Field(default_factory=list)
    block_pipe_to_shell: bool = True
    track_downloaded_executables: bool = True
    downloaded_files_metadata: str = ".claude/hooks/security-guardian/.downloaded.json"
    detect_binary_by_magic: bool = True
    git_tracked_allow: bool = True
    file_command_fallback: bool = True


class UnpackProtectionConfig(BaseModel):
    """Archive unpacking protection configuration."""

    check_extracted_files: bool = True
    check_archive_path_traversal: bool = True
    blocked_patterns: list[str] = Field(default_factory=list)


class ProtectedPathsConfig(BaseModel):
    """Protected paths configuration."""

    no_modify: list[str] = Field(default_factory=list)
    no_read_content: list[str] = Field(default_factory=list)


class LoggingConfig(BaseModel):
    """Logging configuration."""

    enabled: bool = True
    log_blocked: bool = True
    log_directory: str = "${HOME}/.claude/logs/security-guardian"
    log_content: bool = False
    max_log_size_mb: int = 10
    max_log_files: int = 5


class SecurityConfig(BaseModel):
    """Main security configuration model."""

    directories: DirectoriesConfig = Field(default_factory=DirectoriesConfig)
    git: GitConfig = Field(default_factory=GitConfig)
    bypass_prevention: BypassPreventionConfig = Field(
        default_factory=BypassPreventionConfig
    )
    download_protection: DownloadProtectionConfig = Field(
        default_factory=DownloadProtectionConfig
    )
    unpack_protection: UnpackProtectionConfig = Field(
        default_factory=UnpackProtectionConfig
    )
    protected_paths: ProtectedPathsConfig = Field(default_factory=ProtectedPathsConfig)
    logging: LoggingConfig = Field(default_factory=LoggingConfig)


def expand_env_vars(value: str) -> str:
    """Expand environment variables in a string."""
    if not isinstance(value, str):
        return value
    return os.path.expandvars(value)


def expand_config_env_vars(config_dict: dict) -> dict:
    """Recursively expand environment variables in config dictionary."""
    result = {}
    for key, value in config_dict.items():
        if isinstance(value, dict):
            result[key] = expand_config_env_vars(value)
        elif isinstance(value, list):
            result[key] = [
                expand_env_vars(item) if isinstance(item, str) else item
                for item in value
            ]
        elif isinstance(value, str):
            result[key] = expand_env_vars(value)
        else:
            result[key] = value
    return result


def load_config(config_path: Optional[Path] = None) -> SecurityConfig:
    """Load security configuration from YAML file.

    Args:
        config_path: Path to config file. If None, uses default location.

    Returns:
        SecurityConfig instance.
    """
    if config_path is None:
        # Default to config file in same directory as this module
        config_path = Path(__file__).parent / "security_config.yaml"

    if not config_path.exists():
        # Return default config if file doesn't exist
        return SecurityConfig()

    with open(config_path) as f:
        config_dict = yaml.safe_load(f) or {}

    # Expand environment variables
    config_dict = expand_config_env_vars(config_dict)

    return SecurityConfig(**config_dict)
