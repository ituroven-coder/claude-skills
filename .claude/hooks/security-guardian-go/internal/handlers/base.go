// Package handlers provides tool handlers for processing tool invocations.
package handlers

import (
	"github.com/artwist-polyakov/security-guardian/internal/checks"
	"github.com/artwist-polyakov/security-guardian/internal/config"
)

// ToolHandler is the interface for tool handlers.
type ToolHandler interface {
	// Name returns the handler name.
	Name() string
	// Handle handles a tool invocation.
	Handle(toolInput map[string]interface{}) *checks.CheckResult
}

// BaseHandler provides common functionality for tool handlers.
type BaseHandler struct {
	ToolName string
	Config   *config.SecurityConfig
}

// Name returns the handler name.
func (h *BaseHandler) Name() string {
	return h.ToolName
}

// Allow creates an allow result.
func (h *BaseHandler) Allow() *checks.CheckResult {
	return checks.Allow(h.ToolName)
}

// Block creates a block result.
func (h *BaseHandler) Block(reason, guidance string) *checks.CheckResult {
	return checks.Block(h.ToolName, reason, guidance)
}

// Deny creates a deny result.
func (h *BaseHandler) Deny(reason, guidance string) *checks.CheckResult {
	return checks.Deny(h.ToolName, reason, guidance)
}

// Ask creates an ask result.
func (h *BaseHandler) Ask(reason, guidance string) *checks.CheckResult {
	return checks.Ask(h.ToolName, reason, guidance)
}

// Confirm creates a confirm result.
func (h *BaseHandler) Confirm(reason, guidance string) *checks.CheckResult {
	return checks.Confirm(h.ToolName, reason, guidance)
}

// GetString gets a string value from tool input.
func GetString(input map[string]interface{}, key string) string {
	if v, ok := input[key]; ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return ""
}

// GetBool gets a bool value from tool input.
func GetBool(input map[string]interface{}, key string) bool {
	if v, ok := input[key]; ok {
		if b, ok := v.(bool); ok {
			return b
		}
	}
	return false
}
