package checks

import (
	"fmt"
	"strings"

	"github.com/artwist-polyakov/security-guardian/internal/config"
	"github.com/artwist-polyakov/security-guardian/internal/parsers"
)

// UnpackCheck checks for dangerous archive unpacking operations.
type UnpackCheck struct {
	BaseCheck
	projectRoot  string
	allowedPaths []string
	config       *config.SecurityConfig
}

// Unpack commands
var unpackCommands = map[string]bool{
	"tar":     true,
	"unzip":   true,
	"unrar":   true,
	"7z":      true,
	"7za":     true,
	"bsdtar":  true,
	"gunzip":  true,
	"bunzip2": true,
	"unxz":    true,
}

// Python unpack patterns
var pythonUnpackPatterns = []string{
	"python -m zipfile -e",
	"python3 -m zipfile -e",
	"python -m tarfile -e",
	"python3 -m tarfile -e",
}

// Security bypass patterns (hard deny)
var securityBypassPatterns = []string{
	"bsdtar -s",
}

// NewUnpackCheck creates a new UnpackCheck instance.
func NewUnpackCheck(cfg *config.SecurityConfig) *UnpackCheck {
	return &UnpackCheck{
		BaseCheck:    BaseCheck{CheckName: "unpack_check"},
		projectRoot:  parsers.GetProjectRoot(),
		allowedPaths: cfg.Directories.AllowedPaths,
		config:       cfg,
	}
}

// CheckCommand checks unpack commands for safety.
func (c *UnpackCheck) CheckCommand(rawCommand string, parsedCommands []*ParsedCommand) *CheckResult {
	// Check for security bypass patterns first - DENY (no confirmation)
	for _, pattern := range securityBypassPatterns {
		if strings.Contains(rawCommand, pattern) {
			return c.Deny(
				fmt.Sprintf("Security bypass pattern: %s", pattern),
				fmt.Sprintf("%s can bypass path protection. Not allowed.", pattern),
			)
		}
	}

	// Check for blocked patterns in raw command - ASK (user can confirm)
	for _, pattern := range c.config.UnpackProtection.BlockedPatterns {
		if strings.Contains(rawCommand, pattern) {
			return c.Ask(
				fmt.Sprintf("Blocked unpack pattern: %s", pattern),
				fmt.Sprintf("Unpack to allowed directory only. Give user: `%s`", rawCommand),
			)
		}
	}

	// Check for Python unpack modules
	for _, pattern := range pythonUnpackPatterns {
		if strings.Contains(rawCommand, pattern) {
			result := c.checkPythonUnpack(rawCommand)
			if !result.IsAllowed() {
				return result
			}
		}
	}

	// Check each unpack command
	for _, cmd := range parsedCommands {
		if unpackCommands[cmd.Command] {
			result := c.checkUnpack(cmd, rawCommand)
			if !result.IsAllowed() {
				return result
			}
		}
	}

	return c.Allow()
}

// checkUnpack checks a single unpack command.
func (c *UnpackCheck) checkUnpack(cmd *ParsedCommand, rawCommand string) *CheckResult {
	targetDir := c.extractTargetDirectory(cmd)

	if targetDir != "" {
		// Check if target is outside project - ASK (user can confirm)
		resolved := parsers.ResolvePath(targetDir, c.projectRoot)
		if !parsers.IsPathWithinAllowed(resolved, c.projectRoot, c.allowedPaths) {
			return c.Ask(
				fmt.Sprintf("Unpack target outside project: %s", targetDir),
				fmt.Sprintf("Cannot unpack outside project. Give user: `%s`", rawCommand),
			)
		}

		// Check for path traversal - DENY (security bypass)
		if parsers.CheckArchivePathTraversal(targetDir) {
			return c.Deny(
				fmt.Sprintf("Path traversal in unpack target: %s", targetDir),
				"Path traversal detected. This is a security bypass.",
			)
		}
	}

	// Check bsdtar -s (renaming can bypass protection) - DENY
	if cmd.Command == "bsdtar" && containsFlag(cmd.Flags, "-s") {
		return c.Deny(
			"bsdtar -s (substitution) can bypass path protection",
			"bsdtar -s is blocked as it can bypass security.",
		)
	}

	return c.Allow()
}

// extractTargetDirectory extracts target directory from unpack command.
func (c *UnpackCheck) extractTargetDirectory(cmd *ParsedCommand) string {
	rawTokens := strings.Fields(cmd.Raw)

	// tar: -C, --directory
	if cmd.Command == "tar" || cmd.Command == "bsdtar" {
		for i, token := range rawTokens {
			if (token == "-C" || token == "--directory") && i+1 < len(rawTokens) {
				return rawTokens[i+1]
			}
			if strings.HasPrefix(token, "-C") && len(token) > 2 {
				return token[2:]
			}
			if strings.HasPrefix(token, "--directory=") {
				return strings.SplitN(token, "=", 2)[1]
			}
			if strings.HasPrefix(token, "--one-top-level=") {
				return strings.SplitN(token, "=", 2)[1]
			}
		}
	}

	// unzip: -d
	if cmd.Command == "unzip" {
		for i, token := range rawTokens {
			if token == "-d" && i+1 < len(rawTokens) {
				return rawTokens[i+1]
			}
			if strings.HasPrefix(token, "-d") && len(token) > 2 {
				return token[2:]
			}
		}
	}

	// 7z: -o
	if cmd.Command == "7z" || cmd.Command == "7za" {
		for _, token := range rawTokens {
			if strings.HasPrefix(token, "-o") && len(token) > 2 {
				return token[2:]
			}
		}
	}

	return ""
}

// checkPythonUnpack checks Python zipfile/tarfile module usage.
func (c *UnpackCheck) checkPythonUnpack(rawCommand string) *CheckResult {
	parts := strings.Fields(rawCommand)

	// Find the -e flag and get the target
	for i, part := range parts {
		if part == "-e" && i+2 < len(parts) {
			targetDir := parts[i+2]
			resolved := parsers.ResolvePath(targetDir, c.projectRoot)

			if !parsers.IsPathWithinAllowed(resolved, c.projectRoot, c.allowedPaths) {
				return c.Ask(
					fmt.Sprintf("Python unpack target outside project: %s", targetDir),
					fmt.Sprintf("Cannot unpack outside project. Give user: `%s`", rawCommand),
				)
			}
		}
	}

	return c.Allow()
}
