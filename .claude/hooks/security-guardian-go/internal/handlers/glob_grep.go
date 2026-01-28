package handlers

import (
	"strings"

	"github.com/artwist-polyakov/security-guardian/internal/checks"
	"github.com/artwist-polyakov/security-guardian/internal/config"
	"github.com/artwist-polyakov/security-guardian/internal/parsers"
)

// GlobGrepHandler handles Glob and Grep tool invocations.
type GlobGrepHandler struct {
	BaseHandler
	directoryCheck *checks.DirectoryCheck
	secretsCheck   *checks.SecretsCheck
}

// NewGlobGrepHandler creates a new GlobGrepHandler instance.
func NewGlobGrepHandler(cfg *config.SecurityConfig) *GlobGrepHandler {
	return &GlobGrepHandler{
		BaseHandler: BaseHandler{
			ToolName: "Glob",
			Config:   cfg,
		},
		directoryCheck: checks.NewDirectoryCheck(cfg),
		secretsCheck:   checks.NewSecretsCheck(cfg),
	}
}

// Handle handles a Glob/Grep tool invocation.
func (h *GlobGrepHandler) Handle(toolInput map[string]interface{}) *checks.CheckResult {
	// Get path from input (both Glob and Grep use 'path')
	path := GetString(toolInput, "path")

	// Also check the pattern field — if it contains a path outside the project,
	// it indicates the operation targets that directory (e.g. pattern="/etc/*", "~/Documents/*")
	pattern := GetString(toolInput, "pattern")
	if path == "" && pattern != "" {
		// Expand ~/... and $HOME/... before checking
		expanded := parsers.ExpandPath(pattern)
		if strings.HasPrefix(expanded, "/") {
			path = expanded
		}
	}

	// If no path specified, default is current directory (allowed)
	if path == "" {
		return h.Allow()
	}

	// Check directory boundaries
	result := h.directoryCheck.CheckPath(path, "find")
	if !result.IsAllowed() {
		return result
	}

	// Check secrets/sensitive file access
	result = h.secretsCheck.CheckPath(path, "read")
	if !result.IsAllowed() {
		return result
	}

	return h.Allow()
}

// GrepHandler handles Grep tool invocations (same as Glob for path checking).
type GrepHandler struct {
	GlobGrepHandler
}

// NewGrepHandler creates a new GrepHandler instance.
func NewGrepHandler(cfg *config.SecurityConfig) *GrepHandler {
	h := NewGlobGrepHandler(cfg)
	h.ToolName = "Grep"
	return &GrepHandler{GlobGrepHandler: *h}
}
