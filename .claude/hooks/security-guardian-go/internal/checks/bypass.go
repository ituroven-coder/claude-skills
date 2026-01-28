package checks

import (
	"fmt"
	"strings"

	"github.com/artwist-polyakov/security-guardian/internal/config"
	"github.com/artwist-polyakov/security-guardian/internal/parsers"
)

// BypassCheck checks for attempts to bypass security measures.
type BypassCheck struct {
	BaseCheck
	config *config.SecurityConfig
}

// NewBypassCheck creates a new BypassCheck instance.
func NewBypassCheck(cfg *config.SecurityConfig) *BypassCheck {
	return &BypassCheck{
		BaseCheck: BaseCheck{CheckName: "bypass_check"},
		config:    cfg,
	}
}

// CheckCommand checks command for bypass attempts.
func (c *BypassCheck) CheckCommand(rawCommand string, parsedCommands []*ParsedCommand) *CheckResult {
	// Check for hard blocked patterns
	if result := c.checkHardBlocked(rawCommand, parsedCommands); !result.IsAllowed() {
		return result
	}

	// Check for variable as command
	if result := c.checkVariableAsCommand(parsedCommands); !result.IsAllowed() {
		return result
	}

	// Check for pipe to shell
	if result := c.checkPipeToShell(parsedCommands); !result.IsAllowed() {
		return result
	}

	// Check for shell -c execution
	if result := c.checkShellExec(rawCommand, parsedCommands); !result.IsAllowed() {
		return result
	}

	// Check for interpreter with network calls
	if result := c.checkInterpreterNetwork(rawCommand); !result.IsAllowed() {
		return result
	}

	return c.Allow()
}

// checkHardBlocked checks for hard blocked commands like eval.
func (c *BypassCheck) checkHardBlocked(rawCommand string, parsedCommands []*ParsedCommand) *CheckResult {
	for _, cmd := range parsedCommands {
		for _, blocked := range c.config.BypassPrevention.HardBlocked {
			if cmd.Command == blocked {
				return c.Deny(
					fmt.Sprintf("Command '%s' is blocked (potential bypass)", blocked),
					"Use explicit commands instead of eval/exec.",
				)
			}
		}

		// Check piped commands
		if cmd.PipesTo != nil {
			result := c.checkHardBlocked(rawCommand, []*ParsedCommand{cmd.PipesTo})
			if !result.IsAllowed() {
				return result
			}
		}
	}

	return c.Allow()
}

// checkVariableAsCommand checks for variable expansion used as command.
func (c *BypassCheck) checkVariableAsCommand(parsedCommands []*ParsedCommand) *CheckResult {
	if !c.config.BypassPrevention.BlockVariableAsCommand {
		return c.Allow()
	}

	for _, cmd := range parsedCommands {
		if cmd.VariableAsCommand {
			return c.Deny(
				"Variable used as command (potential bypass)",
				"Use explicit commands. Variable expansion as command is blocked.",
			)
		}
	}

	return c.Allow()
}

// checkPipeToShell checks for piping output to shell.
func (c *BypassCheck) checkPipeToShell(parsedCommands []*ParsedCommand) *CheckResult {
	shellTargets := c.config.BypassPrevention.BlockShellPipeTargets

	// Convert to parsers.ParsedCommand for the helper function
	parserCmds := make([]*parsers.ParsedCommand, len(parsedCommands))
	for i, cmd := range parsedCommands {
		parserCmds[i] = convertParsedCommand(cmd)
	}

	if parsers.IsPipeToShell(parserCmds, shellTargets) {
		return c.Deny(
			"Piping to shell detected (dangerous pattern)",
			"Cannot pipe to shell. Download file first, review, then execute.",
		)
	}

	return c.Allow()
}

// checkShellExec checks for shell -c execution patterns.
func (c *BypassCheck) checkShellExec(rawCommand string, parsedCommands []*ParsedCommand) *CheckResult {
	for _, pattern := range c.config.BypassPrevention.BlockShellExecPatterns {
		if strings.Contains(rawCommand, pattern) {
			return c.Deny(
				fmt.Sprintf("Shell exec pattern detected: %s", pattern),
				"Direct shell execution with -c is blocked. Run commands directly.",
			)
		}
	}

	// Also check parsed commands
	for _, cmd := range parsedCommands {
		switch cmd.Command {
		case "sh", "bash", "zsh", "dash", "ksh", "ash":
			if containsFlag(cmd.Flags, "-c") {
				return c.Deny(
					fmt.Sprintf("Shell exec detected: %s -c", cmd.Command),
					"Direct shell execution is blocked. Run the inner command directly.",
				)
			}
		case "env":
			// Check for env -i bash/sh
			for _, arg := range cmd.Args {
				if arg == "bash" || arg == "sh" || arg == "zsh" {
					return c.Deny(
						"env shell execution detected",
						"Shell execution via env is blocked.",
					)
				}
			}
		case "busybox":
			// Check for busybox sh
			if containsArg(cmd.Args, "sh") {
				return c.Deny(
					"busybox shell execution detected",
					"Shell execution via busybox is blocked.",
				)
			}
		}
	}

	return c.Allow()
}

// checkInterpreterNetwork checks for interpreter inline code with network calls.
func (c *BypassCheck) checkInterpreterNetwork(rawCommand string) *CheckResult {
	bp := c.config.BypassPrevention

	// Check if command uses inline interpreter
	isInlineInterpreter := false
	for _, pattern := range bp.ConfirmInterpreterInlineWithNetwork {
		if strings.Contains(rawCommand, pattern) {
			isInlineInterpreter = true
			break
		}
	}

	if !isInlineInterpreter {
		return c.Allow()
	}

	// Check for network patterns
	hasNetwork := false
	for _, pattern := range bp.NetworkPatterns {
		if strings.Contains(rawCommand, pattern) {
			hasNetwork = true
			break
		}
	}

	// Check for obfuscation
	hasObfuscation := false
	for _, pattern := range bp.ObfuscationPatterns {
		if strings.Contains(rawCommand, pattern) {
			hasObfuscation = true
			break
		}
	}

	// Check for RCE patterns
	hasRCE := false
	for _, pattern := range bp.RCEPatternsRequireNetwork {
		if strings.Contains(rawCommand, pattern) {
			hasRCE = true
			break
		}
	}

	// Determine action based on patterns found
	if hasNetwork {
		return c.Confirm(
			"Inline interpreter code with network calls detected",
			"This code makes network calls. Verify it's safe before allowing.",
		)
	}

	if hasObfuscation {
		return c.Confirm(
			"Inline interpreter code with potential obfuscation detected",
			"This code uses import obfuscation. Verify it's safe.",
		)
	}

	if hasRCE && hasNetwork {
		return c.Confirm(
			"Potential RCE pattern with network access detected",
			"This code pattern could execute remote code. Verify carefully.",
		)
	}

	// Allow plain inline code without network
	return c.Allow()
}

// containsFlag checks if a flag is in the list.
func containsFlag(flags []string, target string) bool {
	for _, f := range flags {
		if f == target {
			return true
		}
	}
	return false
}

// containsArg checks if an argument is in the list.
func containsArg(args []string, target string) bool {
	for _, a := range args {
		if a == target {
			return true
		}
	}
	return false
}
