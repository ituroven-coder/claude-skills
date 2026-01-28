package handlers

import (
	"github.com/artwist-polyakov/security-guardian/internal/checks"
	"github.com/artwist-polyakov/security-guardian/internal/config"
)

// WriteHandler handles Write and Edit tool invocations.
type WriteHandler struct {
	BaseHandler
	directoryCheck   *checks.DirectoryCheck
	secretsCheck     *checks.SecretsCheck
	codeContentCheck *checks.CodeContentCheck
}

// NewWriteHandler creates a new WriteHandler instance.
func NewWriteHandler(cfg *config.SecurityConfig) *WriteHandler {
	return &WriteHandler{
		BaseHandler: BaseHandler{
			ToolName: "Write",
			Config:   cfg,
		},
		directoryCheck:   checks.NewDirectoryCheck(cfg),
		secretsCheck:     checks.NewSecretsCheck(cfg),
		codeContentCheck: checks.NewCodeContentCheck(cfg),
	}
}

// Handle handles a Write/Edit tool invocation.
func (h *WriteHandler) Handle(toolInput map[string]interface{}) *checks.CheckResult {
	filePath := GetString(toolInput, "file_path")
	content := GetString(toolInput, "content")

	if filePath == "" {
		return h.Allow()
	}

	// Check directory boundaries
	result := h.directoryCheck.CheckPath(filePath, "write")
	if !result.IsAllowed() {
		return result
	}

	// Check protected files (no_modify)
	result = h.secretsCheck.CheckPath(filePath, "write")
	if !result.IsAllowed() {
		return result
	}

	// Check content for dangerous patterns (for script files)
	if IsScriptFile(filePath) && content != "" {
		result = h.codeContentCheck.CheckContent(content, filePath)
		if !result.IsAllowed() {
			return result
		}
	}

	return h.Allow()
}

// EditHandler handles Edit tool invocations (same as Write).
type EditHandler struct {
	WriteHandler
}

// NewEditHandler creates a new EditHandler instance.
func NewEditHandler(cfg *config.SecurityConfig) *EditHandler {
	h := NewWriteHandler(cfg)
	h.ToolName = "Edit"
	return &EditHandler{WriteHandler: *h}
}

// NotebookEditHandler handles NotebookEdit tool invocations.
type NotebookEditHandler struct {
	BaseHandler
	directoryCheck   *checks.DirectoryCheck
	secretsCheck     *checks.SecretsCheck
	codeContentCheck *checks.CodeContentCheck
}

// NewNotebookEditHandler creates a new NotebookEditHandler instance.
func NewNotebookEditHandler(cfg *config.SecurityConfig) *NotebookEditHandler {
	return &NotebookEditHandler{
		BaseHandler: BaseHandler{
			ToolName: "NotebookEdit",
			Config:   cfg,
		},
		directoryCheck:   checks.NewDirectoryCheck(cfg),
		secretsCheck:     checks.NewSecretsCheck(cfg),
		codeContentCheck: checks.NewCodeContentCheck(cfg),
	}
}

// Handle handles a NotebookEdit tool invocation.
func (h *NotebookEditHandler) Handle(toolInput map[string]interface{}) *checks.CheckResult {
	notebookPath := GetString(toolInput, "notebook_path")
	newSource := GetString(toolInput, "new_source")
	cellType := GetString(toolInput, "cell_type")

	if notebookPath == "" {
		return h.Allow()
	}

	// Check directory boundaries
	result := h.directoryCheck.CheckPath(notebookPath, "write")
	if !result.IsAllowed() {
		return result
	}

	// Check protected files (no_modify)
	result = h.secretsCheck.CheckPath(notebookPath, "write")
	if !result.IsAllowed() {
		return result
	}

	// Check code cell content for dangerous patterns
	if cellType == "code" && newSource != "" {
		result = h.codeContentCheck.CheckContent(newSource, notebookPath+" (cell)")
		if !result.IsAllowed() {
			return result
		}
	}

	return h.Allow()
}
