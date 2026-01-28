package checks

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/artwist-polyakov/security-guardian/internal/config"
	"github.com/artwist-polyakov/security-guardian/internal/parsers"
)

// CodeContentCheck checks script content for dangerous patterns.
type CodeContentCheck struct {
	BaseCheck
	projectRoot string
	config      *config.SecurityConfig

	// Compiled patterns
	networkPatterns   []*regexp.Regexp
	sensitivePatterns []*regexp.Regexp
	scanningPatterns  []*regexp.Regexp
	reconPatterns     []*regexp.Regexp
	dynamicPatterns   []*regexp.Regexp
	codePatterns      []codePatternItem
	envVarPatterns    []*regexp.Regexp
}

type codePatternItem struct {
	pattern     *regexp.Regexp
	description string
}

// NewCodeContentCheck creates a new CodeContentCheck instance.
func NewCodeContentCheck(cfg *config.SecurityConfig) *CodeContentCheck {
	c := &CodeContentCheck{
		BaseCheck:   BaseCheck{CheckName: "code_content_check"},
		projectRoot: parsers.GetProjectRoot(),
		config:      cfg,
	}
	c.compilePatterns()
	return c
}

// compilePatterns compiles regex patterns from config.
func (c *CodeContentCheck) compilePatterns() {
	ops := c.config.DangerousOperations

	c.networkPatterns = compilePatterns(ops.Network)
	c.sensitivePatterns = compilePatterns(ops.SensitiveAccess)
	c.scanningPatterns = compilePatterns(ops.SecretScanning)
	c.reconPatterns = compilePatterns(ops.SystemRecon)
	c.dynamicPatterns = compilePatterns(ops.DynamicExecution)

	// Compile code patterns from sensitive_files config
	for _, item := range c.config.SensitiveFiles.CodePatterns {
		if re := compilePattern(item.Pattern); re != nil {
			c.codePatterns = append(c.codePatterns, codePatternItem{
				pattern:     re,
				description: item.Description,
			})
		}
	}

	// Custom patterns
	for _, item := range c.config.SensitiveFiles.CustomPatterns {
		if re := compilePattern(item.Pattern); re != nil {
			c.codePatterns = append(c.codePatterns, codePatternItem{
				pattern:     re,
				description: item.Description,
			})
		}
	}

	// Secret env var patterns
	for _, varName := range c.config.SensitiveFiles.SecretEnvVars {
		pattern := fmt.Sprintf(`(getenv|environ)\s*[\[\(]['"]?%s['"]?[\]\)]`, regexp.QuoteMeta(varName))
		if re := compilePattern(pattern); re != nil {
			c.envVarPatterns = append(c.envVarPatterns, re)
		}
	}
}

// compilePatterns compiles a list of pattern strings.
func compilePatterns(patterns []string) []*regexp.Regexp {
	var result []*regexp.Regexp
	for _, p := range patterns {
		if re := compilePattern(p); re != nil {
			result = append(result, re)
		}
	}
	return result
}

// compilePattern compiles a single pattern string.
func compilePattern(pattern string) *regexp.Regexp {
	re, err := regexp.Compile(pattern)
	if err != nil {
		return nil
	}
	return re
}

// CheckCommand is not used for content check - use CheckContent instead.
func (c *CodeContentCheck) CheckCommand(rawCommand string, parsedCommands []*ParsedCommand) *CheckResult {
	return c.Allow()
}

// CheckContent checks script content for dangerous patterns.
func (c *CodeContentCheck) CheckContent(content string, filePath string) *CheckResult {
	if content == "" {
		return c.Allow()
	}

	fileName := filepath.Base(filePath)
	if filePath == "" {
		fileName = "script"
	}

	// Track found patterns
	var networkFound []string
	var sensitiveFound []string
	var scanningFound []string
	var reconFound []string
	var dynamicFound []string
	var codePatternFound []codePatternMatch
	var envVarFound []string

	// Check network patterns
	for _, re := range c.networkPatterns {
		if match := re.FindString(content); match != "" {
			networkFound = append(networkFound, c.findLineContext(content, match))
		}
	}

	// Check sensitive access patterns
	for _, re := range c.sensitivePatterns {
		if match := re.FindString(content); match != "" {
			sensitiveFound = append(sensitiveFound, c.findLineContext(content, match))
		}
	}

	// Check secret scanning patterns
	for _, re := range c.scanningPatterns {
		if match := re.FindString(content); match != "" {
			scanningFound = append(scanningFound, c.findLineContext(content, match))
		}
	}

	// Check system recon patterns
	for _, re := range c.reconPatterns {
		if match := re.FindString(content); match != "" {
			reconFound = append(reconFound, c.findLineContext(content, match))
		}
	}

	// Check dynamic execution patterns
	for _, re := range c.dynamicPatterns {
		if match := re.FindString(content); match != "" {
			dynamicFound = append(dynamicFound, c.findLineContext(content, match))
		}
	}

	// Check code patterns from config
	for _, item := range c.codePatterns {
		if match := item.pattern.FindString(content); match != "" {
			codePatternFound = append(codePatternFound, codePatternMatch{
				match:       match,
				description: item.description,
			})
		}
	}

	// Check secret env var patterns
	for _, re := range c.envVarPatterns {
		if match := re.FindString(content); match != "" {
			envVarFound = append(envVarFound, match)
		}
	}

	// EXFILTRATION RISK: network + sensitive access
	if len(networkFound) > 0 && (len(sensitiveFound) > 0 || len(codePatternFound) > 0 || len(envVarFound) > 0) {
		return c.buildExfiltrationWarning(fileName, networkFound, sensitiveFound, codePatternFound, envVarFound)
	}

	// SECRET SCANNING: dangerous by itself
	if len(scanningFound) > 0 {
		return c.Ask(
			fmt.Sprintf("Script %s contains secret scanning patterns", fileName),
			c.formatScanningWarning(scanningFound),
		)
	}

	// DYNAMIC EXECUTION: dangerous by itself
	if len(dynamicFound) > 0 {
		return c.Ask(
			fmt.Sprintf("Script %s uses dynamic code execution", fileName),
			c.formatDynamicWarning(dynamicFound),
		)
	}

	// SYSTEM RECON + NETWORK: could be data gathering
	if len(networkFound) > 0 && len(reconFound) > 0 {
		return c.Ask(
			fmt.Sprintf("Script %s gathers system info with network access", fileName),
			c.formatReconWarning(networkFound, reconFound),
		)
	}

	return c.Allow()
}

// CheckFile checks a file for dangerous patterns.
// The filePath is resolved against project root to ensure correct file access
// regardless of the hook's working directory.
func (c *CodeContentCheck) CheckFile(filePath string) *CheckResult {
	ext := filepath.Ext(filePath)
	scriptExts := map[string]bool{".py": true, ".sh": true, ".bash": true, ".rb": true, ".pl": true, ".js": true}

	if !scriptExts[ext] {
		return c.Allow()
	}

	// Resolve path against project root so relative paths work
	// even when the hook is invoked from a different cwd
	resolved := parsers.ResolvePath(filePath, c.projectRoot)

	content, err := os.ReadFile(resolved)
	if err != nil {
		return c.Allow()
	}

	return c.CheckContent(string(content), filePath)
}

type codePatternMatch struct {
	match       string
	description string
}

// findLineContext finds the line number and context for a match.
func (c *CodeContentCheck) findLineContext(content string, match string) string {
	idx := strings.Index(content, match)
	if idx < 0 {
		return match
	}
	lineNum := strings.Count(content[:idx], "\n") + 1
	return fmt.Sprintf("%s (line %d)", match, lineNum)
}

// buildExfiltrationWarning builds exfiltration risk warning.
func (c *CodeContentCheck) buildExfiltrationWarning(fileName string, network []string, sensitive []string, codePatterns []codePatternMatch, envVars []string) *CheckResult {
	var parts []string
	parts = append(parts, fmt.Sprintf("EXFILTRATION RISK: %s contains:", fileName))

	parts = append(parts, "  Network calls:")
	for i, n := range network {
		if i >= 3 {
			break
		}
		parts = append(parts, fmt.Sprintf("    - %s", n))
	}

	if len(sensitive) > 0 {
		parts = append(parts, "  Sensitive file access:")
		for i, s := range sensitive {
			if i >= 3 {
				break
			}
			parts = append(parts, fmt.Sprintf("    - %s", s))
		}
	}

	if len(codePatterns) > 0 {
		parts = append(parts, "  Secret access patterns:")
		for i, p := range codePatterns {
			if i >= 3 {
				break
			}
			parts = append(parts, fmt.Sprintf("    - %s: %s", p.description, p.match))
		}
	}

	if len(envVars) > 0 {
		parts = append(parts, "  Secret env vars:")
		for i, e := range envVars {
			if i >= 3 {
				break
			}
			parts = append(parts, fmt.Sprintf("    - %s", e))
		}
	}

	parts = append(parts, "\nThis could be an attempt to send your secrets externally.")

	return c.Ask(
		fmt.Sprintf("Script %s has network + sensitive data access (exfiltration risk)", fileName),
		strings.Join(parts, "\n"),
	)
}

// formatScanningWarning formats secret scanning warning.
func (c *CodeContentCheck) formatScanningWarning(patterns []string) string {
	lines := []string{"Script searches for secrets/passwords:"}
	for i, p := range patterns {
		if i >= 5 {
			break
		}
		lines = append(lines, fmt.Sprintf("  - %s", p))
	}
	lines = append(lines, "\nThis could be attempting to find and collect credentials.")
	return strings.Join(lines, "\n")
}

// formatDynamicWarning formats dynamic execution warning.
func (c *CodeContentCheck) formatDynamicWarning(patterns []string) string {
	lines := []string{"Script uses dynamic code execution:"}
	for i, p := range patterns {
		if i >= 5 {
			break
		}
		lines = append(lines, fmt.Sprintf("  - %s", p))
	}
	lines = append(lines, "\nexec/eval/compile can hide malicious code.")
	return strings.Join(lines, "\n")
}

// formatReconWarning formats reconnaissance warning.
func (c *CodeContentCheck) formatReconWarning(network []string, recon []string) string {
	lines := []string{"Script gathers system info with network access:"}
	lines = append(lines, "  Network:")
	for i, n := range network {
		if i >= 3 {
			break
		}
		lines = append(lines, fmt.Sprintf("    - %s", n))
	}
	lines = append(lines, "  System info:")
	for i, r := range recon {
		if i >= 3 {
			break
		}
		lines = append(lines, fmt.Sprintf("    - %s", r))
	}
	lines = append(lines, "\nCould be fingerprinting your system.")
	return strings.Join(lines, "\n")
}
