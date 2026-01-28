package checks

import (
	"fmt"
	"strings"

	"github.com/artwist-polyakov/security-guardian/internal/config"
	"github.com/artwist-polyakov/security-guardian/internal/parsers"
)

// DirectoryCheck checks that operations stay within allowed directory boundaries.
// This is the PRIMARY protection layer.
type DirectoryCheck struct {
	BaseCheck
	projectRoot  string
	allowedPaths []string
	config       *config.SecurityConfig
}

// NewDirectoryCheck creates a new DirectoryCheck instance.
func NewDirectoryCheck(cfg *config.SecurityConfig) *DirectoryCheck {
	projectRoot := cfg.Directories.ProjectRoot
	if projectRoot == "" {
		projectRoot = parsers.GetProjectRoot()
	} else {
		projectRoot = parsers.ResolvePath(projectRoot, "")
	}

	return &DirectoryCheck{
		BaseCheck:    BaseCheck{CheckName: "directory_check"},
		projectRoot:  projectRoot,
		allowedPaths: cfg.Directories.AllowedPaths,
		config:       cfg,
	}
}

// CheckCommand checks if command accesses paths outside allowed boundaries.
func (c *DirectoryCheck) CheckCommand(rawCommand string, parsedCommands []*ParsedCommand) *CheckResult {
	for _, cmd := range parsedCommands {
		// For commands that never take file path arguments (echo, printf, etc.),
		// still check redirects and pipes — they can write outside project.
		if nonPathCommands[cmd.Command] {
			// Check redirect targets (echo hi > /etc/passwd)
			for _, redir := range cmd.Redirects {
				result := c.CheckPath(redir, cmd.Command)
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
			continue
		}

		paths := parsers.ExtractPathsFromCommand((*parsers.ParsedCommand)(convertParsedCommand(cmd)))

		// For commands with a pattern first arg (grep, sed, awk),
		// skip the first arg which is a pattern, not a path.
		skipFirstArg := patternFirstArgCommands[cmd.Command]
		firstArgSkipped := false

		for _, pathStr := range paths {
			if skipFirstArg && !firstArgSkipped {
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
		// may have filtered out (e.g. bare symlink names without /, ., or ~ characters).
		// Only for commands known to take file paths as positional args,
		// to avoid false positives with pattern-based commands (grep, echo, etc.).
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

		// Recursively check piped commands
		if cmd.PipesTo != nil {
			result := c.CheckCommand(rawCommand, []*ParsedCommand{cmd.PipesTo})
			if !result.IsAllowed() {
				return result
			}
		}
	}

	return c.Allow()
}

// CheckPath checks if a path is within allowed boundaries.
func (c *DirectoryCheck) CheckPath(path string, operation string) *CheckResult {
	// Resolve path relative to project root
	resolved := parsers.ResolvePath(path, c.projectRoot)

	// Check for symlink escape - HARD DENY (security bypass)
	if parsers.IsSymlinkEscape(path, c.projectRoot, c.projectRoot) {
		return c.Deny(
			fmt.Sprintf("Symlink escape detected: '%s' resolves to '%s' outside project", path, resolved),
			"Symlink points outside project boundaries. This is a security bypass attempt.",
		)
	}

	// Check if within allowed paths
	if !parsers.IsPathWithinAllowed(resolved, c.projectRoot, c.allowedPaths) {
		// ALL paths outside project are DENIED
		// We don't know what sensitive files might exist on user's disk
		// (crypto wallets, password managers, bank certs, etc.)
		// If Claude needs something outside project, user should run command themselves
		return c.Deny(
			fmt.Sprintf("Path '%s' is outside project boundaries", resolved),
			c.getGuidanceForOperation(operation, path),
		)
	}

	return c.Allow()
}


// getGuidanceForOperation returns appropriate guidance based on operation type.
func (c *DirectoryCheck) getGuidanceForOperation(operation string, path string) string {
	switch operation {
	case "cat", "less", "head", "tail", "read":
		return fmt.Sprintf("Path is outside project. Give user the command: `cat %s`", path)
	case "rm", "unlink", "rmdir":
		return fmt.Sprintf("Cannot delete files outside project. Give user the command: `rm %s`", path)
	case "cp", "mv":
		return fmt.Sprintf("Cannot copy/move files outside project. Give user the command: `%s %s`", operation, path)
	case "find", "ls":
		return fmt.Sprintf("Cannot search outside project. Give user the command: `%s %s`", operation, path)
	case "echo", "tee", "write", ">", ">>":
		return fmt.Sprintf("Cannot write outside project. Give user the command for writing to %s", path)
	default:
		return fmt.Sprintf("Operation '%s' blocked outside project. Give user the command or add path to allowed_paths in config.", operation)
	}
}

// convertParsedCommand converts checks.ParsedCommand to parsers.ParsedCommand.
func convertParsedCommand(cmd *ParsedCommand) *parsers.ParsedCommand {
	if cmd == nil {
		return nil
	}
	result := &parsers.ParsedCommand{
		Command:           cmd.Command,
		Args:              cmd.Args,
		Flags:             cmd.Flags,
		Redirects:         cmd.Redirects,
		VariableAsCommand: cmd.VariableAsCommand,
		Raw:               cmd.Raw,
	}
	if cmd.PipesTo != nil {
		result.PipesTo = convertParsedCommand(cmd.PipesTo)
	}
	return result
}
