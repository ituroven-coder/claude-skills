"""Git operations security check."""

from checks.base import CheckResult, SecurityCheck
from parsers.bash_parser import ParsedCommand, get_git_subcommand_and_flags
from parsers.path_parser import is_in_ci_environment


class GitCheck(SecurityCheck):
    """Check for destructive git operations."""

    name = "git_check"

    # Map of operation patterns to their safer alternatives
    SAFER_ALTERNATIVES = {
        "push --force": "Use --force-with-lease instead: `git push --force-with-lease`",
        "push -f": "Use --force-with-lease instead: `git push --force-with-lease`",
        "reset --hard": "Consider `git stash` first, or give user: `git reset --hard`",
        "branch -D": "Give user the command: `git branch -D <branch>`",
        "clean -fd": "Try `git clean -fd --dry-run` first, or give user: `git clean -fd`",
        "reflog expire": "Give user the command: `git reflog expire`",
    }

    def check_command(
        self,
        raw_command: str,
        parsed_commands: list[ParsedCommand],
    ) -> CheckResult:
        """Check git command for destructive operations."""
        subcommand, flags = get_git_subcommand_and_flags(parsed_commands)

        if not subcommand:
            return self._allow()

        # Build operation string for matching
        operation = self._build_operation_string(subcommand, flags)

        # Check if explicitly allowed
        if self._is_allowed(operation):
            return self._allow()

        # Check if hard blocked
        if self._is_hard_blocked(operation):
            return self._block(
                reason=f"Destructive git operation blocked: {operation}",
                guidance=self._get_safer_alternative(operation),
            )

        # Check if CI auto-allow
        if is_in_ci_environment() and self._is_ci_auto_allowed(operation):
            return self._allow()

        # Check if confirmation required
        if self._needs_confirmation(operation):
            return self._confirm(
                reason=f"Git operation requires confirmation: {operation}",
                guidance=self._get_safer_alternative(operation),
            )

        return self._allow()

    def _build_operation_string(self, subcommand: str, flags: list[str]) -> str:
        """Build operation string from subcommand and flags."""
        # Normalize flags
        normalized_flags = []
        for flag in flags:
            # Handle combined flags like -fd
            if flag.startswith("-") and not flag.startswith("--"):
                if len(flag) > 2:
                    # Expand combined flags
                    for char in flag[1:]:
                        normalized_flags.append(f"-{char}")
                else:
                    normalized_flags.append(flag)
            else:
                normalized_flags.append(flag)

        # Build various operation formats to match against
        operations = [subcommand]
        for flag in normalized_flags:
            operations.append(f"{subcommand} {flag}")

        # Also build combined operation string
        if normalized_flags:
            full_op = f"{subcommand} {' '.join(sorted(normalized_flags))}"
            operations.append(full_op)

        return " ".join([subcommand] + sorted(normalized_flags))

    def _is_allowed(self, operation: str) -> bool:
        """Check if operation is explicitly allowed."""
        for pattern in self.config.git.allowed:
            if self._matches_pattern(operation, pattern):
                return True
        return False

    def _is_hard_blocked(self, operation: str) -> bool:
        """Check if operation is hard blocked."""
        for pattern in self.config.git.hard_blocked:
            if self._matches_pattern(operation, pattern):
                # But check if --force-with-lease is present (allowed)
                if "--force-with-lease" in operation:
                    return False
                return True
        return False

    def _is_ci_auto_allowed(self, operation: str) -> bool:
        """Check if operation is auto-allowed in CI."""
        for pattern in self.config.git.ci_auto_allow:
            if self._matches_pattern(operation, pattern):
                return True
        return False

    def _needs_confirmation(self, operation: str) -> bool:
        """Check if operation needs confirmation."""
        for pattern in self.config.git.confirm_required:
            if self._matches_pattern(operation, pattern):
                return True
        return False

    def _matches_pattern(self, operation: str, pattern: str) -> bool:
        """Check if operation matches a pattern.

        Handles patterns like:
        - "push --force" matches "push --force origin main"
        - "clean -fd" matches "clean -f -d"
        """
        pattern_parts = pattern.split()
        operation_parts = operation.split()

        if not pattern_parts:
            return False

        # First part (subcommand) must match
        if pattern_parts[0] != operation_parts[0]:
            return False

        # Expand combined short flags (e.g., -fd -> -f, -d)
        def expand_flags(flags: list[str]) -> set[str]:
            result = set()
            for flag in flags:
                if flag.startswith("--"):
                    result.add(flag)
                elif flag.startswith("-") and len(flag) > 2:
                    # Combined flags like -fd
                    for char in flag[1:]:
                        result.add(f"-{char}")
                else:
                    result.add(flag)
            return result

        pattern_flags = expand_flags(pattern_parts[1:])
        operation_flags = expand_flags(operation_parts[1:])

        return pattern_flags.issubset(operation_flags)

    def _get_safer_alternative(self, operation: str) -> str:
        """Get safer alternative suggestion for operation."""
        for pattern, suggestion in self.SAFER_ALTERNATIVES.items():
            if self._matches_pattern(operation, pattern):
                return suggestion
        return f"Give user the command: `git {operation}`"
