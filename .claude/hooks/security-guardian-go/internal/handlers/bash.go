package handlers

import (
	"path/filepath"
	"regexp"
	"strings"

	"github.com/artwist-polyakov/security-guardian/internal/checks"
	"github.com/artwist-polyakov/security-guardian/internal/config"
	"github.com/artwist-polyakov/security-guardian/internal/parsers"
)

// BashHandler handles Bash tool invocations.
type BashHandler struct {
	BaseHandler
	checks           []checks.SecurityCheck
	codeContentCheck *checks.CodeContentCheck
}

// Script execution patterns
var scriptExecutionPatterns = []*regexp.Regexp{
	regexp.MustCompile(`^python3?\s+(.+\.py)\b`),
	regexp.MustCompile(`^python3?\s+-m\s+`),
	regexp.MustCompile(`^(?:ba)?sh\s+(.+\.sh)\b`),
	regexp.MustCompile(`^source\s+(.+\.sh)\b`),
	regexp.MustCompile(`^\.\s+(.+\.sh)\b`),
	regexp.MustCompile(`^ruby\s+(.+\.rb)\b`),
	regexp.MustCompile(`^perl\s+(.+\.pl)\b`),
	regexp.MustCompile(`^node\s+(.+\.js)\b`),
}

// NewBashHandler creates a new BashHandler instance.
func NewBashHandler(cfg *config.SecurityConfig) *BashHandler {
	bypassCheck := checks.NewBypassCheck(cfg)
	unpackCheck := checks.NewUnpackCheck(cfg)
	directoryCheck := checks.NewDirectoryCheck(cfg)
	gitCheck := checks.NewGitCheck(cfg)
	deletionCheck := checks.NewDeletionCheck(cfg)
	downloadCheck := checks.NewDownloadCheck(cfg)
	executionCheck := checks.NewExecutionCheck(cfg)
	secretsCheck := checks.NewSecretsCheck(cfg)

	// Link execution check with download check for file tracking
	executionCheck.SetDownloadCheck(downloadCheck)

	return &BashHandler{
		BaseHandler: BaseHandler{
			ToolName: "Bash",
			Config:   cfg,
		},
		checks: []checks.SecurityCheck{
			bypassCheck,     // Security bypasses first (eval, pipe to shell)
			directoryCheck,  // Boundary protection (before unpack so DENY overrides ASK)
			unpackCheck,     // Archive security (bsdtar -s bypass)
			gitCheck,        // Git operations
			deletionCheck,   // Deletion protection
			downloadCheck,   // Download protection
			executionCheck,  // Execution protection
			secretsCheck,    // Secrets protection
		},
		codeContentCheck: checks.NewCodeContentCheck(cfg),
	}
}

// Handle handles a Bash tool invocation.
func (h *BashHandler) Handle(toolInput map[string]interface{}) *checks.CheckResult {
	command := GetString(toolInput, "command")

	if command == "" || strings.TrimSpace(command) == "" {
		return h.Allow()
	}

	// Parse command
	parsedCommands := parsers.ParseBashCommand(command)
	if len(parsedCommands) == 0 {
		return h.Allow()
	}

	// Convert to checks.ParsedCommand
	checkCommands := convertParsedCommands(parsedCommands)

	// Run all checks
	for _, check := range h.checks {
		result := check.CheckCommand(command, checkCommands)
		if !result.IsAllowed() {
			return result
		}
	}

	// Check content of scripts being executed
	result := h.checkScriptExecution(command, checkCommands)
	if !result.IsAllowed() {
		return result
	}

	return h.Allow()
}

// checkScriptExecution checks content of scripts being executed.
func (h *BashHandler) checkScriptExecution(command string, parsedCommands []*checks.ParsedCommand) *checks.CheckResult {
	for _, cmd := range parsedCommands {
		scriptPath := h.extractScriptPath(cmd)
		if scriptPath != "" {
			result := h.codeContentCheck.CheckFile(scriptPath)
			if !result.IsAllowed() {
				return result
			}
		}
	}

	return h.Allow()
}

// extractScriptPath extracts script path from a command.
func (h *BashHandler) extractScriptPath(cmd *checks.ParsedCommand) string {
	fullCmd := cmd.Command
	if len(cmd.Args) > 0 {
		fullCmd = cmd.Command + " " + strings.Join(cmd.Args, " ")
	}

	for _, pattern := range scriptExecutionPatterns {
		match := pattern.FindStringSubmatch(fullCmd)
		if len(match) > 1 {
			return match[1]
		}
	}

	// Also check direct execution of script files via arguments
	interpreters := map[string]bool{
		"python":  true,
		"python3": true,
		"bash":    true,
		"sh":      true,
		"ruby":    true,
		"perl":    true,
		"node":    true,
	}

	if interpreters[cmd.Command] {
		scriptExts := []string{".py", ".sh", ".bash", ".rb", ".pl", ".js"}
		for _, arg := range cmd.Args {
			for _, ext := range scriptExts {
				if strings.HasSuffix(arg, ext) {
					return arg
				}
			}
		}
	}

	// Detect direct script execution: ./script.sh, path/to/script.py, etc.
	// When a script is invoked directly (not via interpreter), cmd.Command IS the script path.
	if cmd.Command != "" && !interpreters[cmd.Command] {
		scriptExts := []string{".py", ".sh", ".bash", ".rb", ".pl", ".js"}
		cmdBase := filepath.Base(cmd.Command)
		for _, ext := range scriptExts {
			if strings.HasSuffix(cmdBase, ext) {
				return cmd.Command
			}
		}
	}

	return ""
}

// convertParsedCommands converts parsers.ParsedCommand to checks.ParsedCommand.
func convertParsedCommands(cmds []*parsers.ParsedCommand) []*checks.ParsedCommand {
	result := make([]*checks.ParsedCommand, len(cmds))
	for i, cmd := range cmds {
		result[i] = convertParserCommand(cmd)
	}
	return result
}

// convertParserCommand converts a single parsers.ParsedCommand to checks.ParsedCommand.
func convertParserCommand(cmd *parsers.ParsedCommand) *checks.ParsedCommand {
	if cmd == nil {
		return nil
	}
	result := &checks.ParsedCommand{
		Command:           cmd.Command,
		Args:              cmd.Args,
		Flags:             cmd.Flags,
		Redirects:         cmd.Redirects,
		VariableAsCommand: cmd.VariableAsCommand,
		Raw:               cmd.Raw,
	}
	if cmd.PipesTo != nil {
		result.PipesTo = convertParserCommand(cmd.PipesTo)
	}
	return result
}

// ScriptExtensions returns script file extensions.
func ScriptExtensions() map[string]bool {
	return map[string]bool{
		".py":   true,
		".sh":   true,
		".bash": true,
		".rb":   true,
		".pl":   true,
		".js":   true,
	}
}

// IsScriptFile checks if file is a script that needs content checking.
func IsScriptFile(filePath string) bool {
	ext := strings.ToLower(filepath.Ext(filePath))
	return ScriptExtensions()[ext]
}
