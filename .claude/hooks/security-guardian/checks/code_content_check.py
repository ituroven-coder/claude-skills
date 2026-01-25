"""Code content check for detecting dangerous patterns in scripts.

This check analyzes script content for dangerous combinations that
indicate potential exfiltration or malicious behavior:
- Network + sensitive access = exfiltration risk
- Secret scanning patterns (grep password, find .env)
- Dynamic execution (exec, eval)
- System reconnaissance
"""

import re
from pathlib import Path
from typing import Optional

from checks.base import CheckResult, SecurityCheck


class CodeContentCheck(SecurityCheck):
    """Check script content for dangerous patterns."""

    name = "code_content_check"

    def __init__(self, config):
        super().__init__(config)
        # Compile regex patterns from config
        self._compile_patterns()

    def _compile_patterns(self):
        """Compile regex patterns from config."""
        ops = self.config.dangerous_operations

        self.network_patterns = [
            re.compile(p) for p in ops.network
        ]
        self.sensitive_patterns = [
            re.compile(p) for p in ops.sensitive_access
        ]
        self.scanning_patterns = [
            re.compile(p) for p in ops.secret_scanning
        ]
        self.recon_patterns = [
            re.compile(p) for p in ops.system_recon
        ]
        self.dynamic_patterns = [
            re.compile(p) for p in ops.dynamic_execution
        ]

        # Compile code patterns from sensitive_files config
        self.code_patterns = []
        for item in self.config.sensitive_files.code_patterns:
            self.code_patterns.append({
                "pattern": re.compile(item.pattern),
                "description": item.description,
            })

        # Custom patterns
        for item in self.config.sensitive_files.custom_patterns:
            self.code_patterns.append({
                "pattern": re.compile(item.pattern),
                "description": item.description,
            })

        # Secret env var patterns
        self.env_var_patterns = []
        for var in self.config.sensitive_files.secret_env_vars:
            # Match os.getenv('VAR'), os.environ['VAR'], os.environ.get('VAR')
            self.env_var_patterns.append(
                re.compile(
                    rf"(getenv|environ)\s*[\[\(]['\"]?{re.escape(var)}['\"]?[\]\)]"
                )
            )

    def check_command(self, raw_command: str, parsed_commands: list) -> CheckResult:
        """Not used for content check - use check_content instead."""
        return self._allow()

    def check_content(
        self,
        content: str,
        file_path: Optional[str] = None,
    ) -> CheckResult:
        """Check script content for dangerous patterns.

        Args:
            content: Script content to check.
            file_path: Optional file path for context in messages.

        Returns:
            CheckResult with status and guidance.
        """
        if not content:
            return self._allow()

        file_name = Path(file_path).name if file_path else "script"

        # Track found patterns
        network_found = []
        sensitive_found = []
        scanning_found = []
        recon_found = []
        dynamic_found = []
        code_pattern_found = []
        env_var_found = []

        # Check network patterns
        for pattern in self.network_patterns:
            match = pattern.search(content)
            if match:
                network_found.append(self._find_line_context(content, match))

        # Check sensitive access patterns
        for pattern in self.sensitive_patterns:
            match = pattern.search(content)
            if match:
                sensitive_found.append(self._find_line_context(content, match))

        # Check secret scanning patterns (dangerous by itself!)
        for pattern in self.scanning_patterns:
            match = pattern.search(content)
            if match:
                scanning_found.append(self._find_line_context(content, match))

        # Check system recon patterns
        for pattern in self.recon_patterns:
            match = pattern.search(content)
            if match:
                recon_found.append(self._find_line_context(content, match))

        # Check dynamic execution patterns (dangerous by itself!)
        for pattern in self.dynamic_patterns:
            match = pattern.search(content)
            if match:
                dynamic_found.append(self._find_line_context(content, match))

        # Check code patterns from config
        for item in self.code_patterns:
            match = item["pattern"].search(content)
            if match:
                code_pattern_found.append({
                    "match": match.group(0),
                    "description": item["description"],
                })

        # Check secret env var patterns
        for pattern in self.env_var_patterns:
            match = pattern.search(content)
            if match:
                env_var_found.append(match.group(0))

        # EXFILTRATION RISK: network + sensitive access
        if network_found and (sensitive_found or code_pattern_found or env_var_found):
            return self._build_exfiltration_warning(
                file_name,
                network_found,
                sensitive_found,
                code_pattern_found,
                env_var_found,
            )

        # SECRET SCANNING: dangerous by itself
        if scanning_found:
            return self._ask(
                reason=f"Script {file_name} contains secret scanning patterns",
                guidance=self._format_scanning_warning(scanning_found),
            )

        # DYNAMIC EXECUTION: dangerous by itself
        if dynamic_found:
            return self._ask(
                reason=f"Script {file_name} uses dynamic code execution",
                guidance=self._format_dynamic_warning(dynamic_found),
            )

        # SYSTEM RECON + NETWORK: could be data gathering
        if network_found and recon_found:
            return self._ask(
                reason=f"Script {file_name} gathers system info with network access",
                guidance=self._format_recon_warning(network_found, recon_found),
            )

        # All checks passed
        return self._allow()

    def check_file(self, file_path: str) -> CheckResult:
        """Check a file for dangerous patterns.

        Args:
            file_path: Path to file to check.

        Returns:
            CheckResult with status and guidance.
        """
        path = Path(file_path)

        if not path.exists():
            return self._allow()

        # Only check script files
        if path.suffix not in (".py", ".sh", ".bash", ".rb", ".pl", ".js"):
            return self._allow()

        try:
            content = path.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            return self._allow()

        return self.check_content(content, file_path)

    def _find_line_context(self, content: str, match: re.Match) -> str:
        """Find the line number and context for a match."""
        start = match.start()
        line_num = content[:start].count("\n") + 1
        # Get the matched text
        matched = match.group(0)
        return f"{matched} (line {line_num})"

    def _build_exfiltration_warning(
        self,
        file_name: str,
        network: list,
        sensitive: list,
        code_patterns: list,
        env_vars: list,
    ) -> CheckResult:
        """Build exfiltration risk warning."""
        parts = [f"EXFILTRATION RISK: {file_name} contains:"]

        parts.append("  Network calls:")
        for n in network[:3]:  # Limit to 3
            parts.append(f"    - {n}")

        if sensitive:
            parts.append("  Sensitive file access:")
            for s in sensitive[:3]:
                parts.append(f"    - {s}")

        if code_patterns:
            parts.append("  Secret access patterns:")
            for p in code_patterns[:3]:
                parts.append(f"    - {p['description']}: {p['match']}")

        if env_vars:
            parts.append("  Secret env vars:")
            for e in env_vars[:3]:
                parts.append(f"    - {e}")

        parts.append("\nThis could be an attempt to send your secrets externally.")

        return self._ask(
            reason=f"Script {file_name} has network + sensitive data access (exfiltration risk)",
            guidance="\n".join(parts),
        )

    def _format_scanning_warning(self, patterns: list) -> str:
        """Format secret scanning warning."""
        lines = ["Script searches for secrets/passwords:"]
        for p in patterns[:5]:
            lines.append(f"  - {p}")
        lines.append("\nThis could be attempting to find and collect credentials.")
        return "\n".join(lines)

    def _format_dynamic_warning(self, patterns: list) -> str:
        """Format dynamic execution warning."""
        lines = ["Script uses dynamic code execution:"]
        for p in patterns[:5]:
            lines.append(f"  - {p}")
        lines.append("\nexec/eval/compile can hide malicious code.")
        return "\n".join(lines)

    def _format_recon_warning(self, network: list, recon: list) -> str:
        """Format reconnaissance warning."""
        lines = ["Script gathers system info with network access:"]
        lines.append("  Network:")
        for n in network[:3]:
            lines.append(f"    - {n}")
        lines.append("  System info:")
        for r in recon[:3]:
            lines.append(f"    - {r}")
        lines.append("\nCould be fingerprinting your system.")
        return "\n".join(lines)
