package checks

import (
	"fmt"
	"sort"
	"strings"

	"github.com/artwist-polyakov/security-guardian/internal/config"
	"github.com/artwist-polyakov/security-guardian/internal/parsers"
)

// GitCheck checks for destructive git operations.
type GitCheck struct {
	BaseCheck
	config *config.SecurityConfig
}

// SaferAlternatives maps operation patterns to their safer alternatives.
var SaferAlternatives = map[string]string{
	"push --force": "Use --force-with-lease instead: `git push --force-with-lease`",
	"push -f":      "Use --force-with-lease instead: `git push --force-with-lease`",
	"reset --hard": "Consider `git stash` first, or give user: `git reset --hard`",
	"branch -D":    "Give user the command: `git branch -D <branch>`",
	"clean -fd":    "Try `git clean -fd --dry-run` first, or give user: `git clean -fd`",
	"reflog expire": "Give user the command: `git reflog expire`",
}

// NewGitCheck creates a new GitCheck instance.
func NewGitCheck(cfg *config.SecurityConfig) *GitCheck {
	return &GitCheck{
		BaseCheck: BaseCheck{CheckName: "git_check"},
		config:    cfg,
	}
}

// CheckCommand checks git command for destructive operations.
func (c *GitCheck) CheckCommand(rawCommand string, parsedCommands []*ParsedCommand) *CheckResult {
	// Convert to parsers.ParsedCommand
	parserCmds := make([]*parsers.ParsedCommand, len(parsedCommands))
	for i, cmd := range parsedCommands {
		parserCmds[i] = convertParsedCommand(cmd)
	}

	subcommand, flags := parsers.GetGitSubcommandAndFlags(parserCmds)

	if subcommand == "" {
		return c.Allow()
	}

	// Build operation string for matching
	operation := c.buildOperationString(subcommand, flags)

	// Check if explicitly allowed
	if c.isAllowed(operation) {
		return c.Allow()
	}

	// Check if hard blocked - DENY (no confirmation possible)
	if c.isHardBlocked(operation) {
		return c.Deny(
			fmt.Sprintf("Destructive git operation blocked: %s", operation),
			c.getSaferAlternative(operation),
		)
	}

	// Check if CI auto-allow
	if parsers.IsInCIEnvironment() && c.isCIAutoAllowed(operation) {
		return c.Allow()
	}

	// Check if confirmation required
	if c.needsConfirmation(operation) {
		return c.Confirm(
			fmt.Sprintf("Git operation requires confirmation: %s", operation),
			c.getSaferAlternative(operation),
		)
	}

	return c.Allow()
}

// buildOperationString builds operation string from subcommand and flags.
func (c *GitCheck) buildOperationString(subcommand string, flags []string) string {
	// Normalize flags
	var normalizedFlags []string
	for _, flag := range flags {
		if strings.HasPrefix(flag, "-") && !strings.HasPrefix(flag, "--") {
			if len(flag) > 2 {
				// Expand combined flags
				for _, char := range flag[1:] {
					normalizedFlags = append(normalizedFlags, fmt.Sprintf("-%c", char))
				}
			} else {
				normalizedFlags = append(normalizedFlags, flag)
			}
		} else {
			normalizedFlags = append(normalizedFlags, flag)
		}
	}

	sort.Strings(normalizedFlags)
	if len(normalizedFlags) > 0 {
		return subcommand + " " + strings.Join(normalizedFlags, " ")
	}
	return subcommand
}

// isAllowed checks if operation is explicitly allowed.
func (c *GitCheck) isAllowed(operation string) bool {
	for _, pattern := range c.config.Git.Allowed {
		if c.matchesPattern(operation, pattern) {
			return true
		}
	}
	return false
}

// isHardBlocked checks if operation is hard blocked.
func (c *GitCheck) isHardBlocked(operation string) bool {
	for _, pattern := range c.config.Git.HardBlocked {
		if c.matchesPattern(operation, pattern) {
			// But check if --force-with-lease is present (allowed)
			if strings.Contains(operation, "--force-with-lease") {
				return false
			}
			return true
		}
	}
	return false
}

// isCIAutoAllowed checks if operation is auto-allowed in CI.
func (c *GitCheck) isCIAutoAllowed(operation string) bool {
	for _, pattern := range c.config.Git.CIAutoAllow {
		if c.matchesPattern(operation, pattern) {
			return true
		}
	}
	return false
}

// needsConfirmation checks if operation needs confirmation.
func (c *GitCheck) needsConfirmation(operation string) bool {
	for _, pattern := range c.config.Git.ConfirmRequired {
		if c.matchesPattern(operation, pattern) {
			return true
		}
	}
	return false
}

// matchesPattern checks if operation matches a pattern.
func (c *GitCheck) matchesPattern(operation string, pattern string) bool {
	patternParts := strings.Fields(pattern)
	operationParts := strings.Fields(operation)

	if len(patternParts) == 0 {
		return false
	}

	// First part (subcommand) must match
	if patternParts[0] != operationParts[0] {
		return false
	}

	// Expand combined short flags
	patternFlags := expandFlags(patternParts[1:])
	operationFlags := expandFlags(operationParts[1:])

	// Check if pattern flags are subset of operation flags
	for pf := range patternFlags {
		if _, ok := operationFlags[pf]; !ok {
			return false
		}
	}

	return true
}

// expandFlags expands combined short flags and returns as a set.
func expandFlags(flags []string) map[string]bool {
	result := make(map[string]bool)
	for _, flag := range flags {
		if strings.HasPrefix(flag, "--") {
			result[flag] = true
		} else if strings.HasPrefix(flag, "-") && len(flag) > 2 {
			// Combined flags like -fd
			for _, char := range flag[1:] {
				result[fmt.Sprintf("-%c", char)] = true
			}
		} else {
			result[flag] = true
		}
	}
	return result
}

// getSaferAlternative gets safer alternative suggestion for operation.
func (c *GitCheck) getSaferAlternative(operation string) string {
	for pattern, suggestion := range SaferAlternatives {
		if c.matchesPattern(operation, pattern) {
			return suggestion
		}
	}
	return fmt.Sprintf("Give user the command: `git %s`", operation)
}
