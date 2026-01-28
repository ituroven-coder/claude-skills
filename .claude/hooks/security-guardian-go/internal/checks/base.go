// Package checks provides security check implementations.
package checks

// CheckStatus represents the result status of a security check.
type CheckStatus string

const (
	// StatusAllow indicates the operation is permitted.
	StatusAllow CheckStatus = "allow"
	// StatusBlock indicates the operation is blocked.
	StatusBlock CheckStatus = "block"
	// StatusConfirm indicates the operation requires user confirmation.
	StatusConfirm CheckStatus = "confirm"
)

// PermissionDecision represents the permission decision type for Claude Code hooks.
type PermissionDecision string

const (
	// DecisionAllow indicates the operation is permitted.
	DecisionAllow PermissionDecision = "allow"
	// DecisionAsk indicates user confirmation is needed (soft block).
	DecisionAsk PermissionDecision = "ask"
	// DecisionDeny indicates hard block, no confirmation possible.
	DecisionDeny PermissionDecision = "deny"
)

// CheckResult represents the result of a security check.
type CheckResult struct {
	Status    CheckStatus        `json:"status"`
	Reason    string             `json:"reason"`
	Guidance  string             `json:"guidance"`
	CheckName string             `json:"check_name"`
	Decision  PermissionDecision `json:"decision,omitempty"`
}

// IsAllowed returns true if the result allows the operation.
func (r *CheckResult) IsAllowed() bool {
	return r.Status == StatusAllow
}

// IsBlocked returns true if the result blocks the operation.
func (r *CheckResult) IsBlocked() bool {
	return r.Status == StatusBlock
}

// NeedsConfirmation returns true if the result requires user confirmation.
func (r *CheckResult) NeedsConfirmation() bool {
	return r.Status == StatusConfirm
}

// PermissionDecisionValue returns the permission decision for JSON output.
// If Decision is explicitly set, use it. Otherwise, derive from Status.
func (r *CheckResult) PermissionDecisionValue() PermissionDecision {
	if r.Decision != "" {
		return r.Decision
	}
	switch r.Status {
	case StatusAllow:
		return DecisionAllow
	case StatusConfirm:
		return DecisionAsk
	default:
		return DecisionDeny
	}
}

// ToMap converts the result to a map for JSON output.
func (r *CheckResult) ToMap() map[string]interface{} {
	return map[string]interface{}{
		"status":    string(r.Status),
		"reason":    r.Reason,
		"guidance":  r.Guidance,
		"check_name": r.CheckName,
		"decision":  string(r.PermissionDecisionValue()),
	}
}

// Allow creates an allow result.
func Allow(checkName string) *CheckResult {
	return &CheckResult{
		Status:    StatusAllow,
		CheckName: checkName,
	}
}

// Block creates a block result with default DENY decision.
func Block(checkName, reason, guidance string) *CheckResult {
	return &CheckResult{
		Status:    StatusBlock,
		Reason:    reason,
		Guidance:  guidance,
		CheckName: checkName,
	}
}

// Deny creates a hard deny result (no user confirmation possible).
func Deny(checkName, reason, guidance string) *CheckResult {
	return &CheckResult{
		Status:    StatusBlock,
		Reason:    reason,
		Guidance:  guidance,
		CheckName: checkName,
		Decision:  DecisionDeny,
	}
}

// Ask creates a deny result with guidance to run the command manually.
// In YOLO mode (--dangerously-skip-permissions) ASK is auto-approved,
// which makes it equivalent to ALLOW. Since this hook is designed
// specifically for YOLO mode, all ASK decisions are elevated to DENY
// with a clear instruction for the user to run the command themselves.
func Ask(checkName, reason, guidance string) *CheckResult {
	return &CheckResult{
		Status:    StatusBlock,
		Reason:    reason,
		Guidance:  guidance,
		CheckName: checkName,
		Decision:  DecisionDeny,
	}
}

// Confirm creates a deny result (elevated from ASK for YOLO mode).
// Same as Ask() — in YOLO mode, all confirmations become hard denies.
func Confirm(checkName, reason, guidance string) *CheckResult {
	return &CheckResult{
		Status:    StatusBlock,
		Reason:    reason,
		Guidance:  guidance,
		CheckName: checkName,
		Decision:  DecisionDeny,
	}
}

// ParsedCommand represents a parsed bash command (imported from parsers).
// This is a forward declaration to avoid circular imports.
type ParsedCommand struct {
	Command           string
	Args              []string
	Flags             []string
	PipesTo           *ParsedCommand
	Redirects         []string
	Subcommands       []*ParsedCommand
	VariableAsCommand bool
	Raw               string
}

// SecurityCheck is the interface for all security checks.
type SecurityCheck interface {
	// Name returns the check name.
	Name() string
	// CheckCommand checks a bash command for security issues.
	CheckCommand(rawCommand string, parsedCommands []*ParsedCommand) *CheckResult
	// CheckPath checks a path for security issues.
	CheckPath(path string, operation string) *CheckResult
}

// BaseCheck provides common functionality for security checks.
type BaseCheck struct {
	CheckName string
	Config    interface{}
}

// Name returns the check name.
func (b *BaseCheck) Name() string {
	return b.CheckName
}

// Allow creates an allow result for this check.
func (b *BaseCheck) Allow() *CheckResult {
	return Allow(b.CheckName)
}

// Block creates a block result for this check.
func (b *BaseCheck) Block(reason, guidance string) *CheckResult {
	return Block(b.CheckName, reason, guidance)
}

// Deny creates a deny result for this check.
func (b *BaseCheck) Deny(reason, guidance string) *CheckResult {
	return Deny(b.CheckName, reason, guidance)
}

// Ask creates a deny result for this check (elevated from ASK for YOLO mode).
func (b *BaseCheck) Ask(reason, guidance string) *CheckResult {
	return Ask(b.CheckName, reason, guidance)
}

// Confirm creates a deny result for this check (elevated from ASK for YOLO mode).
func (b *BaseCheck) Confirm(reason, guidance string) *CheckResult {
	return Confirm(b.CheckName, reason, guidance)
}

// CheckPath default implementation allows all paths.
func (b *BaseCheck) CheckPath(path string, operation string) *CheckResult {
	return b.Allow()
}
