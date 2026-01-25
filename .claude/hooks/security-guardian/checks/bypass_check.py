"""Bypass prevention check - detect attempts to circumvent security."""

import re

from checks.base import CheckResult, SecurityCheck
from parsers.bash_parser import ParsedCommand, is_pipe_to_shell


class BypassCheck(SecurityCheck):
    """Check for attempts to bypass security measures."""

    name = "bypass_check"

    def check_command(
        self,
        raw_command: str,
        parsed_commands: list[ParsedCommand],
    ) -> CheckResult:
        """Check command for bypass attempts."""
        # Check for hard blocked patterns
        result = self._check_hard_blocked(raw_command, parsed_commands)
        if not result.is_allowed:
            return result

        # Check for variable as command
        result = self._check_variable_as_command(parsed_commands)
        if not result.is_allowed:
            return result

        # Check for pipe to shell
        result = self._check_pipe_to_shell(parsed_commands)
        if not result.is_allowed:
            return result

        # Check for shell -c execution
        result = self._check_shell_exec(raw_command, parsed_commands)
        if not result.is_allowed:
            return result

        # Check for interpreter with network calls
        result = self._check_interpreter_network(raw_command, parsed_commands)
        if not result.is_allowed:
            return result

        return self._allow()

    def _check_hard_blocked(
        self, raw_command: str, parsed_commands: list[ParsedCommand]
    ) -> CheckResult:
        """Check for hard blocked commands like eval."""
        for cmd in parsed_commands:
            for blocked in self.config.bypass_prevention.hard_blocked:
                if cmd.command == blocked:
                    return self._block(
                        reason=f"Command '{blocked}' is blocked (potential bypass)",
                        guidance="Use explicit commands instead of eval/exec.",
                    )

            # Check piped commands
            if cmd.pipes_to:
                result = self._check_hard_blocked(raw_command, [cmd.pipes_to])
                if not result.is_allowed:
                    return result

        return self._allow()

    def _check_variable_as_command(
        self, parsed_commands: list[ParsedCommand]
    ) -> CheckResult:
        """Check for variable expansion used as command."""
        if not self.config.bypass_prevention.block_variable_as_command:
            return self._allow()

        for cmd in parsed_commands:
            if cmd.variable_as_command:
                return self._block(
                    reason="Variable used as command (potential bypass)",
                    guidance="Use explicit commands. Variable expansion as command is blocked.",
                )

        return self._allow()

    def _check_pipe_to_shell(self, parsed_commands: list[ParsedCommand]) -> CheckResult:
        """Check for piping output to shell."""
        shell_targets = self.config.bypass_prevention.block_shell_pipe_targets

        if is_pipe_to_shell(parsed_commands, shell_targets):
            return self._block(
                reason="Piping to shell detected (dangerous pattern)",
                guidance="Cannot pipe to shell. Download file first, review, then execute.",
            )

        return self._allow()

    def _check_shell_exec(
        self, raw_command: str, parsed_commands: list[ParsedCommand]
    ) -> CheckResult:
        """Check for shell -c execution patterns."""
        for pattern in self.config.bypass_prevention.block_shell_exec_patterns:
            # Check both raw command and parsed commands
            if pattern in raw_command:
                return self._block(
                    reason=f"Shell exec pattern detected: {pattern}",
                    guidance="Direct shell execution with -c is blocked. Run commands directly.",
                )

        # Also check parsed commands
        for cmd in parsed_commands:
            if cmd.command in ("sh", "bash", "zsh", "dash", "ksh", "ash"):
                if "-c" in cmd.flags:
                    return self._block(
                        reason=f"Shell exec detected: {cmd.command} -c",
                        guidance="Direct shell execution is blocked. Run the inner command directly.",
                    )
            elif cmd.command == "env":
                # Check for env -i bash/sh
                for arg in cmd.args:
                    if arg in ("bash", "sh", "zsh"):
                        return self._block(
                            reason="env shell execution detected",
                            guidance="Shell execution via env is blocked.",
                        )
            elif cmd.command == "busybox":
                # Check for busybox sh
                if "sh" in cmd.args:
                    return self._block(
                        reason="busybox shell execution detected",
                        guidance="Shell execution via busybox is blocked.",
                    )

        return self._allow()

    def _check_interpreter_network(
        self, raw_command: str, parsed_commands: list[ParsedCommand]
    ) -> CheckResult:
        """Check for interpreter inline code with network calls."""
        # Get patterns from config
        interpreter_patterns = (
            self.config.bypass_prevention.confirm_interpreter_inline_with_network
        )
        network_patterns = self.config.bypass_prevention.network_patterns
        obfuscation_patterns = self.config.bypass_prevention.obfuscation_patterns
        rce_patterns = self.config.bypass_prevention.rce_patterns_require_network

        # Check if command uses inline interpreter
        is_inline_interpreter = False
        for pattern in interpreter_patterns:
            if pattern in raw_command:
                is_inline_interpreter = True
                break

        if not is_inline_interpreter:
            return self._allow()

        # Check for network patterns
        has_network = False
        for pattern in network_patterns:
            if pattern in raw_command:
                has_network = True
                break

        # Check for obfuscation
        has_obfuscation = False
        for pattern in obfuscation_patterns:
            if pattern in raw_command:
                has_obfuscation = True
                break

        # Check for RCE patterns (only if network is present)
        has_rce = False
        for pattern in rce_patterns:
            if pattern in raw_command:
                has_rce = True
                break

        # Determine action based on patterns found
        if has_network:
            return self._confirm(
                reason="Inline interpreter code with network calls detected",
                guidance="This code makes network calls. Verify it's safe before allowing.",
            )

        if has_obfuscation:
            return self._confirm(
                reason="Inline interpreter code with potential obfuscation detected",
                guidance="This code uses import obfuscation. Verify it's safe.",
            )

        if has_rce and has_network:
            return self._confirm(
                reason="Potential RCE pattern with network access detected",
                guidance="This code pattern could execute remote code. Verify carefully.",
            )

        # Allow plain inline code without network
        return self._allow()
