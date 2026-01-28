package handlers

import (
	"github.com/artwist-polyakov/security-guardian/internal/checks"
	"github.com/artwist-polyakov/security-guardian/internal/config"
)

// ReadHandler handles Read tool invocations.
type ReadHandler struct {
	BaseHandler
	directoryCheck *checks.DirectoryCheck
	secretsCheck   *checks.SecretsCheck
}

// NewReadHandler creates a new ReadHandler instance.
func NewReadHandler(cfg *config.SecurityConfig) *ReadHandler {
	return &ReadHandler{
		BaseHandler: BaseHandler{
			ToolName: "Read",
			Config:   cfg,
		},
		directoryCheck: checks.NewDirectoryCheck(cfg),
		secretsCheck:   checks.NewSecretsCheck(cfg),
	}
}

// Handle handles a Read tool invocation.
func (h *ReadHandler) Handle(toolInput map[string]interface{}) *checks.CheckResult {
	filePath := GetString(toolInput, "file_path")

	if filePath == "" {
		return h.Allow()
	}

	// Check directory boundaries
	result := h.directoryCheck.CheckPath(filePath, "read")
	if !result.IsAllowed() {
		return result
	}

	// Check secrets/protected files
	result = h.secretsCheck.CheckPath(filePath, "read")
	if !result.IsAllowed() {
		return result
	}

	return h.Allow()
}
