// Package messages provides guidance messages for blocked operations.
package messages

import (
	"fmt"
	"strings"

	"github.com/artwist-polyakov/security-guardian/internal/checks"
)

// FormatBlockMessage formats a DENY message for Claude (hard block, no confirmation possible).
func FormatBlockMessage(result *checks.CheckResult) string {
	parts := []string{fmt.Sprintf("BLOCKED: %s", result.Reason)}

	if result.Guidance != "" {
		parts = append(parts, fmt.Sprintf("Guidance: %s", result.Guidance))
	}

	return strings.Join(parts, "\n")
}

// FormatConfirmMessage formats an ASK message for Claude (soft block, user can confirm).
func FormatConfirmMessage(result *checks.CheckResult) string {
	parts := []string{fmt.Sprintf("CONFIRM: %s", result.Reason)}

	if result.Guidance != "" {
		parts = append(parts, fmt.Sprintf("Guidance: %s", result.Guidance))
	}

	return strings.Join(parts, "\n")
}

// Predefined guidance messages for common scenarios.
var GuidanceMessages = map[string]string{
	// Directory boundaries
	"path_outside_project": "Path is outside project boundaries. Give user the command to execute: `%s`",
	"symlink_escape":       "Symlink resolves outside project. Give user the command: `%s`",

	// Git operations
	"git_force_push":    "Force push blocked. Suggest --force-with-lease: `git push --force-with-lease`",
	"git_reset_hard":    "Hard reset requires confirmation. Suggest: `git stash` first, or give user: `git reset --hard`",
	"git_branch_delete": "Branch deletion requires confirmation. Give user: `git branch -D %s`",
	"git_clean":         "Git clean requires confirmation. Try --dry-run first: `git clean -fd --dry-run`",

	// Secrets
	"env_file":     "Cannot read .env file. Look at .env.example for structure, ask user for values.",
	"secrets_file": "Cannot read secrets file. Ask user what information is needed.",

	// Downloads
	"download_executable": "Cannot download executable files. Give user: `%s`",
	"pipe_to_shell":       "Cannot pipe downloads to shell. Download file first, review it, then execute.",

	// Execution
	"chmod_downloaded": "chmod +x on downloaded file requires confirmation. Give user: `chmod +x %s`",

	// Bypass
	"shell_exec":          "Direct shell execution blocked. Run the inner command directly without shell wrapper.",
	"variable_as_command": "Variable used as command. Use explicit command names.",
	"eval_blocked":        "eval is blocked. Use explicit commands instead.",
}

// GetGuidance returns a predefined guidance message with formatting.
func GetGuidance(key string, args ...interface{}) string {
	template, ok := GuidanceMessages[key]
	if !ok {
		return ""
	}
	if len(args) > 0 {
		return fmt.Sprintf(template, args...)
	}
	return template
}
