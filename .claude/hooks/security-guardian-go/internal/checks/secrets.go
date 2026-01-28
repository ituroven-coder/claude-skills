package checks

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/artwist-polyakov/security-guardian/internal/config"
	"github.com/artwist-polyakov/security-guardian/internal/parsers"
)

// SecretsCheck checks for access to secret/sensitive files inside project.
type SecretsCheck struct {
	BaseCheck
	projectRoot string
	config      *config.SecurityConfig
}

// NewSecretsCheck creates a new SecretsCheck instance.
func NewSecretsCheck(cfg *config.SecurityConfig) *SecretsCheck {
	projectRoot := cfg.Directories.ProjectRoot
	if projectRoot == "" {
		projectRoot = parsers.GetProjectRoot()
	} else {
		projectRoot = parsers.ResolvePath(projectRoot, "")
	}

	return &SecretsCheck{
		BaseCheck:   BaseCheck{CheckName: "secrets_check"},
		projectRoot: projectRoot,
		config:      cfg,
	}
}

// fileArgCommands lists commands whose positional arguments are typically file paths.
// For these commands, bare filenames (without /, ., ~) are also checked against secrets patterns.
// Commands like grep, echo, awk, sed take patterns/text as args and should NOT be scanned.
var fileArgCommands = map[string]bool{
	"cat": true, "less": true, "more": true, "head": true, "tail": true,
	"mv": true, "cp": true, "rm": true, "chmod": true, "chown": true,
	"chgrp": true, "touch": true, "stat": true, "file": true,
	"ln": true, "readlink": true, "realpath": true,
	"source": true, "open": true, "xdg-open": true,
	"nano": true, "vim": true, "vi": true, "code": true,
}

// patternFirstArgCommands lists commands whose first positional argument is a pattern,
// not a file path. For these commands, the first arg should be skipped during path checks.
// e.g. grep ".env" README.md — ".env" is a search pattern, not a file.
var patternFirstArgCommands = map[string]bool{
	"grep": true, "egrep": true, "fgrep": true, "rg": true,
	"sed": true, "awk": true, "gawk": true,
	"expr": true,
}

// nonPathCommands lists commands whose ALL positional arguments are non-paths.
// None of their args should be checked as file paths.
var nonPathCommands = map[string]bool{
	"echo": true, "printf": true, "export": true, "unset": true,
	"alias": true, "unalias": true, "set": true,
	"true": true, "false": true, "test": true, "[": true,
}

// CheckCommand checks for access to protected files.
func (c *SecretsCheck) CheckCommand(rawCommand string, parsedCommands []*ParsedCommand) *CheckResult {
	for _, cmd := range parsedCommands {
		// For commands that never take file path arguments (echo, printf, etc.),
		// still check redirect targets (echo secret > .env.bak could write secrets).
		if nonPathCommands[cmd.Command] {
			for _, redir := range cmd.Redirects {
				result := c.CheckPath(redir, "write")
				if !result.IsAllowed() {
					return result
				}
			}
			continue
		}

		// Get path-like args from the command
		paths := parsers.ExtractPathsFromCommand(convertParsedCommand(cmd))

		// For commands with a pattern first arg (grep, sed, awk),
		// skip the first arg which is a pattern, not a path.
		skipFirstArg := patternFirstArgCommands[cmd.Command]
		firstArgSkipped := false

		for _, pathStr := range paths {
			if skipFirstArg && !firstArgSkipped {
				// Check if this path corresponds to the first positional arg
				if len(cmd.Args) > 0 && pathStr == cmd.Args[0] {
					firstArgSkipped = true
					continue
				}
			}
			result := c.CheckPath(pathStr, cmd.Command)
			if !result.IsAllowed() {
				return result
			}
		}

		// For file-operating commands, also check bare args that ExtractPathsFromCommand
		// may have filtered out (e.g. bare filenames like "id_rsa" without /, ., or ~).
		if fileArgCommands[cmd.Command] {
			for _, arg := range cmd.Args {
				if strings.HasPrefix(arg, "-") {
					continue
				}
				// Skip args already covered by ExtractPathsFromCommand
				if strings.Contains(arg, "/") || strings.HasPrefix(arg, ".") || strings.HasPrefix(arg, "~") || strings.Contains(arg, ".") {
					continue
				}
				result := c.CheckPath(arg, cmd.Command)
				if !result.IsAllowed() {
					return result
				}
			}
		}
	}

	return c.Allow()
}

// CheckPath checks if a path matches protected patterns.
func (c *SecretsCheck) CheckPath(path string, operation string) *CheckResult {
	// Resolve relative to project root
	resolved := parsers.ResolvePath(path, c.projectRoot)

	// Get relative path to project
	relStr, err := filepath.Rel(c.projectRoot, resolved)
	if err != nil || strings.HasPrefix(relStr, "..") {
		// Path outside project - handled by DirectoryCheck
		return c.Allow()
	}

	// Check patterns based on operation type
	if c.isWriteOperation(operation) {
		if c.matchesNoModify(relStr) {
			return c.Deny(
				fmt.Sprintf("Cannot modify protected file: %s", path),
				fmt.Sprintf("File is protected. Cannot modify %s.", path),
			)
		}
		// Writing to secrets files is also forbidden (e.g. echo secret > .env)
		if c.matchesNoRead(relStr) {
			return c.Deny(
				fmt.Sprintf("Cannot write to secrets file: %s", path),
				fmt.Sprintf("File %s is a secrets file. Cannot write to it.", path),
			)
		}
	} else {
		if c.matchesNoRead(relStr) {
			return c.Deny(
				fmt.Sprintf("Cannot read secrets file: %s", path),
				c.getSecretsGuidance(path, relStr),
			)
		}
	}

	return c.Allow()
}

// isWriteOperation checks if operation is a write operation.
func (c *SecretsCheck) isWriteOperation(operation string) bool {
	writeOps := map[string]bool{
		"write": true,
		"edit":  true,
		"tee":   true,
		"echo":  true,
		">":     true,
		">>":    true,
		"cp":    true,
		"mv":    true,
		"rm":    true,
		"touch": true,
		"sed":   true,
		"awk":   true,
	}
	return writeOps[strings.ToLower(operation)]
}

// matchesNoRead checks if path matches no_read_content or forbidden_read patterns.
func (c *SecretsCheck) matchesNoRead(relPath string) bool {
	// Combine protected_paths.no_read_content and sensitive_files.forbidden_read
	var allPatterns []string
	allPatterns = append(allPatterns, c.config.ProtectedPaths.NoReadContent...)
	allPatterns = append(allPatterns, c.config.SensitiveFiles.ForbiddenRead...)

	filename := filepath.Base(relPath)

	// First check negation patterns (they take precedence)
	for _, pattern := range allPatterns {
		if strings.HasPrefix(pattern, "!") {
			negated := pattern[1:]
			// Remove **/ prefix
			if strings.HasPrefix(negated, "**/") {
				negated = negated[3:]
			}
			if matchGlob(filename, negated) || matchGlob(relPath, negated) {
				return false // Explicitly allowed
			}
		}
	}

	// Then check blocking patterns
	for _, pattern := range allPatterns {
		if !strings.HasPrefix(pattern, "!") {
			cleanPattern := pattern
			if strings.HasPrefix(cleanPattern, "**/") {
				cleanPattern = cleanPattern[3:]
			}
			if matchGlob(filename, cleanPattern) || matchGlob(relPath, cleanPattern) {
				return true
			}
		}
	}

	return false
}

// matchesNoModify checks if path matches no_modify patterns.
func (c *SecretsCheck) matchesNoModify(relPath string) bool {
	patterns := c.config.ProtectedPaths.NoModify

	for _, pattern := range patterns {
		if matchGlob(relPath, pattern) {
			return true
		}
	}

	return false
}

// getSecretsGuidance returns appropriate guidance for secrets access.
func (c *SecretsCheck) getSecretsGuidance(path string, relPath string) string {
	if strings.Contains(relPath, ".env") {
		examplePath := strings.Replace(relPath, ".env", ".env.example", 1)
		exampleFull := filepath.Join(c.projectRoot, examplePath)

		if _, err := os.Stat(exampleFull); err == nil {
			return fmt.Sprintf("Cannot read %s (secrets file). Look at %s for structure, then ask user for values.",
				path, examplePath)
		}

		return fmt.Sprintf("Cannot read %s (secrets file). Ask user what environment variables are needed.", path)
	}

	return fmt.Sprintf("Cannot read %s (protected file). Ask user for needed information.", path)
}

// matchGlob performs simple glob matching.
func matchGlob(name string, pattern string) bool {
	// Handle ** (matches any path component)
	if strings.Contains(pattern, "**") {
		// Split pattern by **
		parts := strings.Split(pattern, "**")
		if len(parts) == 2 {
			prefix := parts[0]
			suffix := parts[1]

			// PREFIX/** should also match PREFIX itself
			// e.g. ".git/**" should match ".git" to prevent renaming/moving .git
			trimmedPrefix := strings.TrimSuffix(prefix, "/")
			if trimmedPrefix != "" && name == trimmedPrefix {
				return true
			}

			// Check if name starts with prefix and ends with suffix
			if prefix != "" && !strings.HasPrefix(name, prefix) {
				return false
			}
			suffix = strings.TrimPrefix(suffix, "/")
			if suffix != "" && !strings.HasSuffix(name, suffix) && !matchSimpleGlob(filepath.Base(name), suffix) {
				return false
			}
			return true
		}
	}

	return matchSimpleGlob(name, pattern)
}

// matchSimpleGlob performs simple glob matching with * and ?.
func matchSimpleGlob(name string, pattern string) bool {
	// Convert to regex-like matching
	i, j := 0, 0
	starIdx, matchIdx := -1, -1

	for i < len(name) {
		if j < len(pattern) && (pattern[j] == '?' || pattern[j] == name[i]) {
			i++
			j++
		} else if j < len(pattern) && pattern[j] == '*' {
			starIdx = j
			matchIdx = i
			j++
		} else if starIdx != -1 {
			j = starIdx + 1
			matchIdx++
			i = matchIdx
		} else {
			return false
		}
	}

	for j < len(pattern) && pattern[j] == '*' {
		j++
	}

	return j == len(pattern)
}
