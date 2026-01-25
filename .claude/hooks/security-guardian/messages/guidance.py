"""Guidance messages for Claude when operations are blocked."""

from checks.base import CheckResult


def format_block_message(result: CheckResult) -> str:
    """Format a block message for Claude.

    Args:
        result: CheckResult with block status.

    Returns:
        Formatted message string.
    """
    parts = [
        f"🛡️ Security Guardian: Operation blocked",
        f"",
        f"Reason: {result.reason}",
    ]

    if result.guidance:
        parts.append(f"")
        parts.append(f"Guidance: {result.guidance}")

    if result.check_name:
        parts.append(f"")
        parts.append(f"Check: {result.check_name}")

    return "\n".join(parts)


def format_confirm_message(result: CheckResult) -> str:
    """Format a confirmation request message for Claude.

    Args:
        result: CheckResult with confirm status.

    Returns:
        Formatted message string.
    """
    parts = [
        f"⚠️ Security Guardian: Confirmation required",
        f"",
        f"Reason: {result.reason}",
    ]

    if result.guidance:
        parts.append(f"")
        parts.append(f"Guidance: {result.guidance}")

    if result.check_name:
        parts.append(f"")
        parts.append(f"Check: {result.check_name}")

    return "\n".join(parts)


# Predefined guidance messages for common scenarios
GUIDANCE_MESSAGES = {
    # Directory boundaries
    "path_outside_project": (
        "Path is outside project boundaries. "
        "Give user the command to execute: `{command}`"
    ),
    "symlink_escape": (
        "Symlink resolves outside project. "
        "Give user the command: `{command}`"
    ),
    # Git operations
    "git_force_push": (
        "Force push blocked. "
        "Suggest --force-with-lease: `git push --force-with-lease`"
    ),
    "git_reset_hard": (
        "Hard reset requires confirmation. "
        "Suggest: `git stash` first, or give user: `git reset --hard`"
    ),
    "git_branch_delete": (
        "Branch deletion requires confirmation. "
        "Give user: `git branch -D {branch}`"
    ),
    "git_clean": (
        "Git clean requires confirmation. "
        "Try --dry-run first: `git clean -fd --dry-run`"
    ),
    # Secrets
    "env_file": (
        "Cannot read .env file. "
        "Look at .env.example for structure, ask user for values."
    ),
    "secrets_file": (
        "Cannot read secrets file. "
        "Ask user what information is needed."
    ),
    # Downloads
    "download_executable": (
        "Cannot download executable files. "
        "Give user: `{command}`"
    ),
    "pipe_to_shell": (
        "Cannot pipe downloads to shell. "
        "Download file first, review it, then execute."
    ),
    # Execution
    "chmod_downloaded": (
        "chmod +x on downloaded file requires confirmation. "
        "Give user: `chmod +x {path}`"
    ),
    # Bypass
    "shell_exec": (
        "Direct shell execution blocked. "
        "Run the inner command directly without shell wrapper."
    ),
    "variable_as_command": (
        "Variable used as command. "
        "Use explicit command names."
    ),
    "eval_blocked": (
        "eval is blocked. "
        "Use explicit commands instead."
    ),
}


def get_guidance(key: str, **kwargs) -> str:
    """Get a predefined guidance message with formatting.

    Args:
        key: Guidance message key.
        **kwargs: Format arguments for the message.

    Returns:
        Formatted guidance message.
    """
    template = GUIDANCE_MESSAGES.get(key, "")
    if template and kwargs:
        try:
            return template.format(**kwargs)
        except KeyError:
            return template
    return template
