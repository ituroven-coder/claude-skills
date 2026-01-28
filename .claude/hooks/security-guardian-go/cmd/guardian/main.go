// Package main provides the CLI entry point for Security Guardian.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"time"

	"github.com/artwist-polyakov/security-guardian/internal/checks"
	"github.com/artwist-polyakov/security-guardian/internal/config"
	"github.com/artwist-polyakov/security-guardian/internal/handlers"
	"github.com/artwist-polyakov/security-guardian/internal/messages"
)

// HookInput represents the input from Claude Code hooks.
type HookInput struct {
	ToolName  string                 `json:"tool_name"`
	ToolInput map[string]interface{} `json:"tool_input"`
}

// HookOutput represents the output for Claude Code hooks.
type HookOutput struct {
	PermissionDecision string `json:"permissionDecision"`
	Message            string `json:"message,omitempty"`
}

func main() {
	// Load configuration
	configPath := config.FindConfigPath()
	cfg, err := config.LoadConfig(configPath)
	if err != nil {
		// Use default config on error
		cfg = config.DefaultConfig()
	}

	// Setup logging
	logger := setupLogging(cfg)

	// Read hook input from stdin
	inputData, err := io.ReadAll(os.Stdin)
	if err != nil {
		logger.Printf("Failed to read hook input: %v", err)
		os.Exit(0) // Allow on error to not break Claude
	}

	var hookInput HookInput
	if err := json.Unmarshal(inputData, &hookInput); err != nil {
		logger.Printf("Failed to parse hook input: %v", err)
		os.Exit(0) // Allow on parse error to not break Claude
	}

	// Log all tool calls if enabled (helps diagnose model behavior, e.g. GLM/zclaude)
	if cfg.Logging.LogAllCalls {
		logger.Printf("[CALL] %s %s", hookInput.ToolName, sanitizeToolInput(hookInput))
	}

	// Process input
	result := processHookInput(hookInput, cfg)

	// Log blocked/denied if enabled
	if cfg.Logging.LogBlocked && !result.IsAllowed() {
		logger.Printf("[%s] %s: %s", result.Status, hookInput.ToolName, result.Reason)
	}

	// Output JSON with permissionDecision for non-allowed operations
	decision := result.PermissionDecisionValue()

	switch decision {
	case checks.DecisionDeny:
		output := HookOutput{
			PermissionDecision: "deny",
			Message:            messages.FormatBlockMessage(result),
		}
		json.NewEncoder(os.Stdout).Encode(output)
		os.Exit(0) // exit 0 so Claude Code processes JSON

	case checks.DecisionAsk:
		output := HookOutput{
			PermissionDecision: "ask",
			Message:            messages.FormatConfirmMessage(result),
		}
		json.NewEncoder(os.Stdout).Encode(output)
		os.Exit(0) // exit 0 so Claude Code processes JSON

	default:
		// ALLOW - exit 0 with no output
		os.Exit(0)
	}
}

// processHookInput processes hook input and returns check result.
func processHookInput(hookInput HookInput, cfg *config.SecurityConfig) *checks.CheckResult {
	handler := getHandler(hookInput.ToolName, cfg)
	if handler == nil {
		// Tool not handled, allow by default
		return checks.Allow("unknown")
	}

	return handler.Handle(hookInput.ToolInput)
}

// getHandler returns appropriate handler for tool.
func getHandler(toolName string, cfg *config.SecurityConfig) handlers.ToolHandler {
	switch toolName {
	case "Bash":
		return handlers.NewBashHandler(cfg)
	case "Read":
		return handlers.NewReadHandler(cfg)
	case "Write":
		return handlers.NewWriteHandler(cfg)
	case "Edit":
		return handlers.NewEditHandler(cfg)
	case "NotebookEdit":
		return handlers.NewNotebookEditHandler(cfg)
	case "Glob":
		return handlers.NewGlobGrepHandler(cfg)
	case "Grep":
		return handlers.NewGrepHandler(cfg)
	default:
		return nil
	}
}

// sanitizeToolInput returns a short, safe representation of tool input for logging.
// Truncates long values (file content) and masks sensitive patterns.
func sanitizeToolInput(input HookInput) string {
	parts := make([]string, 0, len(input.ToolInput))
	for k, v := range input.ToolInput {
		s := fmt.Sprintf("%v", v)
		// Truncate long values (e.g. file content in Write tool)
		if len(s) > 200 {
			s = s[:200] + "..."
		}
		parts = append(parts, fmt.Sprintf("%s=%q", k, s))
	}
	if len(parts) == 0 {
		return "{}"
	}
	return "{" + fmt.Sprintf("%s", joinStrings(parts, ", ")) + "}"
}

// joinStrings joins strings with separator (avoids importing strings package).
func joinStrings(ss []string, sep string) string {
	result := ""
	for i, s := range ss {
		if i > 0 {
			result += sep
		}
		result += s
	}
	return result
}

// setupLogging sets up logging based on configuration.
func setupLogging(cfg *config.SecurityConfig) *log.Logger {
	logger := log.New(io.Discard, "", 0)

	if !cfg.Logging.Enabled {
		return logger
	}

	// Expand log directory path
	logDir := os.ExpandEnv(cfg.Logging.LogDirectory)
	if err := os.MkdirAll(logDir, 0755); err != nil {
		return logger
	}

	// Create log file with date
	logFile := filepath.Join(logDir, fmt.Sprintf("security-guardian-%s.log", time.Now().Format("2006-01-02")))

	f, err := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return logger
	}

	logger = log.New(f, "", log.LstdFlags)
	return logger
}
