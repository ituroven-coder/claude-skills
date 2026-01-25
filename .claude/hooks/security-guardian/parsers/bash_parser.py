"""Bash command parser using bashlex AST."""

from dataclasses import dataclass, field
from typing import Optional

try:
    import bashlex
    BASHLEX_AVAILABLE = True
except ImportError:
    BASHLEX_AVAILABLE = False


@dataclass
class ParsedCommand:
    """Represents a parsed bash command."""

    command: str
    args: list[str] = field(default_factory=list)
    flags: list[str] = field(default_factory=list)
    pipes_to: Optional["ParsedCommand"] = None
    redirects: list[str] = field(default_factory=list)
    subcommands: list["ParsedCommand"] = field(default_factory=list)
    variable_as_command: bool = False
    raw: str = ""


def _extract_word_value(node) -> str:
    """Extract word value from bashlex node."""
    if hasattr(node, "word"):
        return node.word
    return ""


def _parse_command_node(node, raw_command: str) -> Optional[ParsedCommand]:
    """Parse a bashlex command node into ParsedCommand."""
    if node.kind == "command":
        parts = node.parts
        if not parts:
            return None

        # First part is the command
        cmd_node = parts[0]
        cmd_value = _extract_word_value(cmd_node)

        # Check if command is a variable expansion
        variable_as_command = False
        if cmd_value.startswith("$") or cmd_value.startswith("${"):
            variable_as_command = True

        args = []
        flags = []
        redirects = []

        for part in parts[1:]:
            if part.kind == "word":
                word = _extract_word_value(part)
                if word.startswith("-"):
                    flags.append(word)
                else:
                    args.append(word)
            elif part.kind == "redirect":
                # Extract redirect target
                if hasattr(part, "output"):
                    redirects.append(_extract_word_value(part.output))

        return ParsedCommand(
            command=cmd_value,
            args=args,
            flags=flags,
            redirects=redirects,
            variable_as_command=variable_as_command,
            raw=raw_command,
        )
    return None


def _parse_pipeline_node(node, raw_command: str) -> list[ParsedCommand]:
    """Parse a bashlex pipeline node into list of ParsedCommands."""
    commands = []
    for part in node.parts:
        if part.kind == "command":
            cmd = _parse_command_node(part, raw_command)
            if cmd:
                commands.append(cmd)
        elif part.kind == "compound":
            # Handle compound commands like subshells
            for subpart in getattr(part, "list", []):
                subcmds = _parse_node(subpart, raw_command)
                commands.extend(subcmds)

    # Link pipeline commands
    for i in range(len(commands) - 1):
        commands[i].pipes_to = commands[i + 1]

    return commands


def _parse_node(node, raw_command: str) -> list[ParsedCommand]:
    """Parse any bashlex node type."""
    commands = []

    if node.kind == "command":
        cmd = _parse_command_node(node, raw_command)
        if cmd:
            commands.append(cmd)
    elif node.kind == "pipeline":
        commands.extend(_parse_pipeline_node(node, raw_command))
    elif node.kind == "list":
        # Handle command lists (cmd1 && cmd2, cmd1 || cmd2, cmd1 ; cmd2)
        for part in node.parts:
            commands.extend(_parse_node(part, raw_command))
    elif node.kind == "compound":
        # Handle compound commands
        for part in getattr(node, "list", []):
            commands.extend(_parse_node(part, raw_command))

    return commands


def parse_bash_command(command: str) -> list[ParsedCommand]:
    """Parse a bash command string into structured ParsedCommand objects.

    Uses bashlex for AST parsing when available, falls back to simple
    string parsing otherwise.

    Args:
        command: Raw bash command string.

    Returns:
        List of ParsedCommand objects representing the command(s).
    """
    if not command or not command.strip():
        return []

    command = command.strip()

    if BASHLEX_AVAILABLE:
        try:
            parts = bashlex.parse(command)
            commands = []
            for part in parts:
                commands.extend(_parse_node(part, command))
            return commands
        except Exception:
            # Fall back to simple parsing on bashlex error
            pass

    # Simple fallback parsing
    return _simple_parse(command)


def _simple_parse(command: str) -> list[ParsedCommand]:
    """Simple string-based command parsing as fallback."""
    commands = []

    # Split by pipes first
    pipe_parts = command.split("|")

    for i, part in enumerate(pipe_parts):
        part = part.strip()
        if not part:
            continue

        # Split by && and ; for command lists
        for subpart in _split_command_list(part):
            subpart = subpart.strip()
            if not subpart:
                continue

            tokens = subpart.split()
            if not tokens:
                continue

            cmd_name = tokens[0]
            args = []
            flags = []

            for token in tokens[1:]:
                if token.startswith("-"):
                    flags.append(token)
                else:
                    args.append(token)

            variable_as_command = cmd_name.startswith("$")

            cmd = ParsedCommand(
                command=cmd_name,
                args=args,
                flags=flags,
                variable_as_command=variable_as_command,
                raw=command,
            )
            commands.append(cmd)

    # Link pipeline commands
    for i in range(len(commands) - 1):
        if i < len(pipe_parts) - 1:
            commands[i].pipes_to = commands[i + 1]

    return commands


def _split_command_list(command: str) -> list[str]:
    """Split command by && and ; while respecting quotes."""
    parts = []
    current = []
    in_quotes = False
    quote_char = None
    i = 0

    while i < len(command):
        char = command[i]

        if char in ('"', "'") and (i == 0 or command[i - 1] != "\\"):
            if not in_quotes:
                in_quotes = True
                quote_char = char
            elif char == quote_char:
                in_quotes = False
                quote_char = None
            current.append(char)
        elif not in_quotes:
            if char == ";" or (char == "&" and i + 1 < len(command) and command[i + 1] == "&"):
                if current:
                    parts.append("".join(current))
                    current = []
                if char == "&":
                    i += 1  # Skip second &
            else:
                current.append(char)
        else:
            current.append(char)

        i += 1

    if current:
        parts.append("".join(current))

    return parts


def extract_paths_from_command(parsed_cmd: ParsedCommand) -> list[str]:
    """Extract all file/directory paths from a parsed command.

    Args:
        parsed_cmd: ParsedCommand to extract paths from.

    Returns:
        List of path strings found in the command.
    """
    paths = []

    # Add all args as potential paths
    paths.extend(parsed_cmd.args)

    # Add redirect targets
    paths.extend(parsed_cmd.redirects)

    # Filter to only path-like strings (containing / or starting with . or ~)
    path_like = []
    for p in paths:
        if "/" in p or p.startswith(".") or p.startswith("~"):
            path_like.append(p)
        # Also include if it looks like a filename with extension
        elif "." in p and not p.startswith("-"):
            path_like.append(p)

    return path_like


def get_git_subcommand_and_flags(parsed_cmds: list[ParsedCommand]) -> tuple[str, list[str]]:
    """Extract git subcommand and its flags from parsed commands.

    Args:
        parsed_cmds: List of parsed commands.

    Returns:
        Tuple of (subcommand, flags) for the first git command found.
    """
    for cmd in parsed_cmds:
        if cmd.command == "git" and cmd.args:
            subcommand = cmd.args[0]
            # Flags are both from the git command and could be in args
            flags = cmd.flags.copy()
            # Some args might actually be flags (like push --force)
            for arg in cmd.args[1:]:
                if arg.startswith("-"):
                    flags.append(arg)
            return subcommand, flags
    return "", []


def is_pipe_to_shell(parsed_cmds: list[ParsedCommand], shell_targets: list[str]) -> bool:
    """Check if any command pipes to a shell.

    Args:
        parsed_cmds: List of parsed commands.
        shell_targets: List of shell command names to check for.

    Returns:
        True if a pipe to shell is detected.
    """
    for cmd in parsed_cmds:
        if cmd.pipes_to:
            target_cmd = cmd.pipes_to.command
            # Check if target is a shell
            for shell in shell_targets:
                if target_cmd == shell or target_cmd.endswith("/" + shell):
                    return True
    return False
