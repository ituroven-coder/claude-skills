package checks

import (
	"fmt"
	"path/filepath"
	"strings"

	"github.com/artwist-polyakov/security-guardian/internal/config"
	"github.com/artwist-polyakov/security-guardian/internal/parsers"
)

// DeletionCheck checks for dangerous file deletion operations.
type DeletionCheck struct {
	BaseCheck
	projectRoot  string
	allowedPaths []string
	config       *config.SecurityConfig
}

// Delete commands
var deleteCommands = map[string]bool{
	"rm":     true,
	"rmdir":  true,
	"unlink": true,
	"shred":  true,
}

// Dangerous rm flags
var dangerousRmFlags = map[string]bool{
	"-r":          true,
	"-R":          true,
	"--recursive": true,
	"-rf":         true,
	"-fr":         true,
	"-Rf":         true,
	"-fR":         true,
}

// NewDeletionCheck creates a new DeletionCheck instance.
func NewDeletionCheck(cfg *config.SecurityConfig) *DeletionCheck {
	return &DeletionCheck{
		BaseCheck:    BaseCheck{CheckName: "deletion_check"},
		projectRoot:  parsers.GetProjectRoot(),
		allowedPaths: cfg.Directories.AllowedPaths,
		config:       cfg,
	}
}

// CheckCommand checks deletion commands for safety.
func (c *DeletionCheck) CheckCommand(rawCommand string, parsedCommands []*ParsedCommand) *CheckResult {
	for _, cmd := range parsedCommands {
		if deleteCommands[cmd.Command] {
			result := c.checkDeletion(cmd)
			if !result.IsAllowed() {
				return result
			}
		}

		// Check piped commands
		if cmd.PipesTo != nil {
			result := c.CheckCommand(rawCommand, []*ParsedCommand{cmd.PipesTo})
			if !result.IsAllowed() {
				return result
			}
		}
	}

	return c.Allow()
}

// checkDeletion checks a single deletion command.
func (c *DeletionCheck) checkDeletion(cmd *ParsedCommand) *CheckResult {
	paths := parsers.ExtractPathsFromCommand(convertParsedCommand(cmd))
	hasRecursive := c.hasDangerousFlags(cmd.Flags)

	// Check for glob patterns in args that ExtractPathsFromCommand may have filtered out.
	// Commands like "rm -rf *" are dangerous even though "*" isn't a path-like string.
	if hasRecursive && len(paths) == 0 {
		for _, arg := range cmd.Args {
			if containsGlob(arg) {
				return c.Ask(
					fmt.Sprintf("Recursive deletion with glob pattern: %s %s", cmd.Command, arg),
					fmt.Sprintf("Glob-based recursive deletion is dangerous. Give user the command: `%s %s %s`",
						cmd.Command, strings.Join(cmd.Flags, " "), strings.Join(cmd.Args, " ")),
				)
			}
		}
	}

	for _, pathStr := range paths {
		resolved := parsers.ResolvePath(pathStr, c.projectRoot)

		// Check if path is outside project - ASK (user can confirm)
		if !parsers.IsPathWithinAllowed(resolved, c.projectRoot, c.allowedPaths) {
			return c.Ask(
				fmt.Sprintf("Cannot delete files outside project: %s", pathStr),
				fmt.Sprintf("Give user the command: `rm %s %s`", strings.Join(cmd.Flags, " "), pathStr),
			)
		}

		// Check for dangerous recursive deletion of important paths
		if hasRecursive {
			result := c.checkDangerousRecursiveDelete(resolved, pathStr, cmd)
			if !result.IsAllowed() {
				return result
			}
		}
	}

	return c.Allow()
}

// containsGlob checks if a string contains shell glob characters.
func containsGlob(s string) bool {
	return strings.ContainsAny(s, "*?[")
}

// hasDangerousFlags checks if any dangerous flags are present.
// Handles both exact matches (-r, -rf) and combined short flags (-rfv, -Rfi).
func (c *DeletionCheck) hasDangerousFlags(flags []string) bool {
	for _, f := range flags {
		// Exact match first
		if dangerousRmFlags[f] {
			return true
		}
		// Check combined short flags: -rfv contains 'r', -Rfi contains 'R'
		if strings.HasPrefix(f, "-") && !strings.HasPrefix(f, "--") && len(f) > 2 {
			for _, ch := range f[1:] {
				if ch == 'r' || ch == 'R' {
					return true
				}
			}
		}
	}
	return false
}

// checkDangerousRecursiveDelete checks for dangerous recursive deletion patterns.
func (c *DeletionCheck) checkDangerousRecursiveDelete(resolved string, originalPath string, cmd *ParsedCommand) *CheckResult {
	// Get path relative to project root
	relStr, err := relPath(c.projectRoot, resolved)
	if err != nil || strings.HasPrefix(relStr, "..") {
		// Already handled by directory check
		return c.Allow()
	}

	// Check protected directories - ASK (user can confirm)
	protected := c.getProtectedDirectories()
	for _, protectedPath := range protected {
		// Block deleting protected path or its children
		if relStr == protectedPath || strings.HasPrefix(relStr, protectedPath+"/") {
			return c.Ask(
				fmt.Sprintf("Cannot recursively delete protected path: %s", originalPath),
				fmt.Sprintf("Path '%s' is protected. Give user the command if needed.", originalPath),
			)
		}
		// Block deleting ancestor directories that contain protected paths
		if strings.HasPrefix(protectedPath, relStr+"/") {
			return c.Ask(
				fmt.Sprintf("Cannot recursively delete directory containing protected path: %s", originalPath),
				fmt.Sprintf("Path '%s' contains protected content '%s'. Give user the command if needed.", originalPath, protectedPath),
			)
		}
	}

	// Warn about recursive deletion at project root - ASK (user can confirm)
	if resolved == c.projectRoot || relStr == "." {
		return c.Ask(
			"Cannot recursively delete project root",
			"Deleting entire project is blocked. Be more specific about what to delete.",
		)
	}

	return c.Allow()
}

// getProtectedDirectories returns list of protected directories.
func (c *DeletionCheck) getProtectedDirectories() []string {
	var protected []string

	for _, pattern := range c.config.ProtectedPaths.NoModify {
		// Remove glob wildcards to get base path
		base := strings.Split(pattern, "*")[0]
		base = strings.TrimSuffix(base, "/")
		if base != "" && base != "." {
			protected = append(protected, base)
		}
	}

	// Always protect .git
	hasGit := false
	for _, p := range protected {
		if p == ".git" {
			hasGit = true
			break
		}
	}
	if !hasGit {
		protected = append(protected, ".git")
	}

	return protected
}

// relPath returns the relative path from base to target using filepath.Rel.
// Both paths are canonicalized (symlinks resolved) before comparison.
func relPath(base, target string) (string, error) {
	// Canonicalize both paths to handle symlinks (e.g. /var vs /private/var on macOS)
	if resolved, err := filepath.EvalSymlinks(base); err == nil {
		base = resolved
	}
	if resolved, err := filepath.EvalSymlinks(target); err == nil {
		target = resolved
	}
	return filepath.Rel(base, target)
}
