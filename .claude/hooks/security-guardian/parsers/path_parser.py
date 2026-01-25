"""Path resolution and validation utilities."""

import os
import subprocess
from pathlib import Path
from typing import Optional


def get_project_root() -> Path:
    """Detect project root directory.

    Looks for .git directory or uses CLAUDE_PROJECT_DIR env var.

    Returns:
        Path to project root.
    """
    # Check environment variable first
    env_root = os.environ.get("CLAUDE_PROJECT_DIR")
    if env_root:
        return Path(env_root).resolve()

    # Try to find .git directory
    current = Path.cwd()
    while current != current.parent:
        if (current / ".git").exists():
            return current
        current = current.parent

    # Fall back to current working directory
    return Path.cwd().resolve()


def resolve_path(path_str: str, base_dir: Optional[Path] = None) -> Path:
    """Resolve a path string to absolute path, following symlinks.

    Args:
        path_str: Path string to resolve (can be relative or absolute).
        base_dir: Base directory for relative paths. Uses cwd if None.

    Returns:
        Resolved absolute path (symlinks resolved via realpath).
    """
    if base_dir is None:
        base_dir = Path.cwd()

    # Expand environment variables and user home
    expanded = os.path.expandvars(os.path.expanduser(path_str))

    # Create path object
    path = Path(expanded)

    # Make absolute if relative
    if not path.is_absolute():
        path = base_dir / path

    # Resolve symlinks and normalize (realpath equivalent)
    try:
        return path.resolve()
    except (OSError, RuntimeError):
        # If resolve fails (e.g., path doesn't exist), normalize without resolving
        return Path(os.path.normpath(path))


def is_path_within_allowed(
    path: Path,
    project_root: Path,
    allowed_paths: list[str],
) -> bool:
    """Check if a path is within allowed directories.

    Args:
        path: Resolved absolute path to check.
        project_root: Project root directory.
        allowed_paths: List of additional allowed path patterns.

    Returns:
        True if path is within allowed boundaries.
    """
    # Resolve project root too
    project_root = project_root.resolve()

    # Check if within project
    try:
        path.relative_to(project_root)
        return True
    except ValueError:
        pass

    # Check allowed paths
    for allowed in allowed_paths:
        allowed_path = resolve_path(allowed)
        try:
            path.relative_to(allowed_path)
            return True
        except ValueError:
            continue

    return False


def is_symlink_escape(
    path_str: str,
    project_root: Path,
    base_dir: Optional[Path] = None,
) -> bool:
    """Check if a path uses symlinks to escape project boundaries.

    This detects when a symlink within the project points to a location
    outside the project. System symlinks (like /var -> /private/var on macOS)
    are NOT considered escapes.

    Args:
        path_str: Original path string.
        project_root: Project root directory.
        base_dir: Base directory for resolving relative paths.

    Returns:
        True if the resolved path escapes project boundaries via symlink.
    """
    # Resolve both paths fully to handle system symlinks like /var -> /private/var
    resolved = resolve_path(path_str, base_dir=base_dir)
    project_resolved = project_root.resolve()

    # Check if resolved path is within project
    try:
        resolved.relative_to(project_resolved)
        return False  # Path is within project after resolution - no escape
    except ValueError:
        pass

    # Path is outside project after resolution - check if this is due to
    # a symlink WITHIN the project pointing outside (which is an escape)
    # vs just being outside to begin with (which is handled by is_path_within_allowed)

    original = Path(os.path.expandvars(os.path.expanduser(path_str)))
    if not original.is_absolute():
        original = (base_dir or Path.cwd()) / original

    # Normalize without resolving symlinks
    original_normalized = Path(os.path.normpath(original))

    # Check if original path (before symlink resolution) appears to be inside project
    # We need to check each component to see if there's a symlink inside project
    # pointing outside
    try:
        # Build path component by component to find symlinks
        check_path = Path("/")
        inside_project = False

        for part in original_normalized.parts[1:]:  # Skip root
            check_path = check_path / part

            # Check if we've entered the project directory
            try:
                check_path.resolve().relative_to(project_resolved)
                inside_project = True
            except ValueError:
                pass

            # If we're inside the project and hit a symlink that goes outside, it's an escape
            if inside_project and check_path.exists() and check_path.is_symlink():
                target = check_path.resolve()
                try:
                    target.relative_to(project_resolved)
                except ValueError:
                    # Symlink inside project points outside - this is an escape
                    return True

    except (OSError, RuntimeError):
        pass

    # Not a symlink escape - just a path that was outside to begin with
    return False


def is_git_tracked(file_path: Path, project_root: Path) -> bool:
    """Check if a file is tracked by git.

    Args:
        file_path: Path to check.
        project_root: Project root with .git directory.

    Returns:
        True if file is tracked by git.
    """
    try:
        result = subprocess.run(
            ["git", "ls-files", "--error-unmatch", str(file_path)],
            cwd=project_root,
            capture_output=True,
            timeout=5,
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return False


def check_archive_path_traversal(archive_path: str) -> bool:
    """Check if an archive extraction path contains traversal attacks.

    This checks for relative path traversal (e.g., ../outside) which could
    escape the extraction directory. Absolute paths are NOT considered
    traversal since they're explicitly specified by the user.

    Args:
        archive_path: Path from archive entry or extraction target.

    Returns:
        True if path contains relative traversal patterns like ..
    """
    # Normalize and check for relative traversal (..)
    # Absolute paths are allowed since they're explicit user choices
    normalized = os.path.normpath(archive_path)
    return normalized.startswith("..")


def is_in_ci_environment() -> bool:
    """Check if running in a CI environment.

    Returns:
        True if CI environment variables are detected.
    """
    ci_vars = ["CI", "GITHUB_ACTIONS", "GITLAB_CI", "JENKINS_URL", "CIRCLECI", "TRAVIS"]
    for var in ci_vars:
        if os.environ.get(var):
            return True
    return False
