#!/usr/bin/env python3
"""Security Guardian - Main entry point for Claude Code hooks.

This script is called by Claude Code hooks to validate tool invocations
before they are executed.

Usage:
    main.py < hook_input.json

The script reads hook input from stdin and outputs the result to stdout.
Exit codes:
    0 - Allow (operation can proceed)
    2 - Block (operation is blocked, output contains reason)
"""

import json
import logging
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

from config import load_config
from checks.base import CheckResult, CheckStatus
from handlers.bash_handler import BashHandler
from handlers.read_handler import ReadHandler
from handlers.write_handler import WriteHandler, EditHandler, NotebookEditHandler
from handlers.glob_grep_handler import GlobGrepHandler, GrepHandler
from messages.guidance import format_block_message, format_confirm_message


def setup_logging(config) -> logging.Logger:
    """Setup logging based on configuration."""
    logger = logging.getLogger("security-guardian")

    if not config.logging.enabled:
        logger.disabled = True
        return logger

    logger.setLevel(logging.INFO)

    # Expand log directory path
    log_dir = Path(os.path.expandvars(config.logging.log_directory))
    log_dir.mkdir(parents=True, exist_ok=True)

    # Create log file with date
    log_file = log_dir / f"security-guardian-{datetime.now():%Y-%m-%d}.log"

    # Setup file handler with rotation
    handler = logging.FileHandler(log_file, encoding="utf-8")
    handler.setFormatter(
        logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
    )
    logger.addHandler(handler)

    return logger


def get_handler(tool_name: str, config):
    """Get appropriate handler for tool.

    Args:
        tool_name: Name of the tool being invoked.
        config: Security configuration.

    Returns:
        Handler instance or None if tool is not handled.
    """
    handlers = {
        "Bash": BashHandler,
        "Read": ReadHandler,
        "Write": WriteHandler,
        "Edit": EditHandler,
        "NotebookEdit": NotebookEditHandler,
        "Glob": GlobGrepHandler,
        "Grep": GrepHandler,
    }

    handler_class = handlers.get(tool_name)
    if handler_class:
        return handler_class(config)
    return None


def process_hook_input(hook_input: dict[str, Any], config) -> CheckResult:
    """Process hook input and return check result.

    Args:
        hook_input: Hook input dictionary from Claude Code.
        config: Security configuration.

    Returns:
        CheckResult with status and guidance.
    """
    tool_name = hook_input.get("tool_name", "")
    tool_input = hook_input.get("tool_input", {})

    # Get handler for tool
    handler = get_handler(tool_name, config)

    if handler is None:
        # Tool not handled, allow by default
        return CheckResult(status=CheckStatus.ALLOW)

    # Run handler
    return handler.handle(tool_input)


def main():
    """Main entry point."""
    # Load configuration
    config_path = Path(__file__).parent / "config" / "security_config.yaml"
    config = load_config(config_path)

    # Setup logging
    logger = setup_logging(config)

    # Read hook input from stdin
    try:
        hook_input_raw = sys.stdin.read()
        hook_input = json.loads(hook_input_raw)
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse hook input: {e}")
        # Allow on parse error to not break Claude
        sys.exit(0)
    except Exception as e:
        logger.error(f"Failed to read hook input: {e}")
        sys.exit(0)

    # Process input
    try:
        result = process_hook_input(hook_input, config)
    except Exception as e:
        logger.error(f"Error processing hook: {e}")
        # Allow on error to not break Claude
        sys.exit(0)

    # Log if enabled
    if config.logging.log_blocked and not result.is_allowed:
        tool_name = hook_input.get("tool_name", "unknown")
        logger.info(
            f"[{result.status.value.upper()}] {tool_name}: {result.reason}"
        )

    # Output result
    if result.is_blocked:
        print(format_block_message(result))
        sys.exit(2)
    elif result.needs_confirmation:
        print(format_confirm_message(result))
        sys.exit(2)
    else:
        # Allow - exit 0 with no output
        sys.exit(0)


if __name__ == "__main__":
    main()
