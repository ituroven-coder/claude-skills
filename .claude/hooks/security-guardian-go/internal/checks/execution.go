package checks

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/artwist-polyakov/security-guardian/internal/config"
	"github.com/artwist-polyakov/security-guardian/internal/parsers"
)

// Note: Using custom timeout handling instead of context.Context

// ExecutionCheck checks for chmod +x on downloaded or suspicious files.
type ExecutionCheck struct {
	BaseCheck
	projectRoot   string
	config        *config.SecurityConfig
	downloadCheck *DownloadCheck
}

// Binary magic bytes for detection
var binaryMagic = map[string][]byte{
	"ELF executable":      {0x7f, 'E', 'L', 'F'},
	"Windows PE":          {'M', 'Z'},
	"Mach-O 32-bit":       {0xfe, 0xed, 0xfa, 0xce},
	"Mach-O 64-bit":       {0xfe, 0xed, 0xfa, 0xcf},
	"Mach-O universal":    {0xca, 0xfe, 0xba, 0xbe},
	"Script with shebang": {'#', '!'},
}

// NewExecutionCheck creates a new ExecutionCheck instance.
func NewExecutionCheck(cfg *config.SecurityConfig) *ExecutionCheck {
	return &ExecutionCheck{
		BaseCheck:   BaseCheck{CheckName: "execution_check"},
		projectRoot: parsers.GetProjectRoot(),
		config:      cfg,
	}
}

// SetDownloadCheck sets the download check instance for file tracking.
func (c *ExecutionCheck) SetDownloadCheck(dc *DownloadCheck) {
	c.downloadCheck = dc
}

// CheckCommand checks chmod commands for safety.
func (c *ExecutionCheck) CheckCommand(rawCommand string, parsedCommands []*ParsedCommand) *CheckResult {
	for _, cmd := range parsedCommands {
		if cmd.Command == "chmod" {
			result := c.checkChmod(cmd)
			if !result.IsAllowed() {
				return result
			}
		}
	}

	return c.Allow()
}

// checkChmod checks a chmod command for making downloaded files executable.
func (c *ExecutionCheck) checkChmod(cmd *ParsedCommand) *CheckResult {
	// Check if making executable (+x)
	if !c.isMakingExecutable(cmd) {
		return c.Allow()
	}

	// Get target paths directly from Args (not ExtractPathsFromCommand which
	// filters out bare filenames like "payload" without extension or path separator).
	for _, pathStr := range cmd.Args {
		// Skip mode arguments (like +x, 755, u+x, a+rx)
		if strings.HasPrefix(pathStr, "+") || isNumeric(pathStr) ||
			(len(pathStr) >= 2 && (pathStr[0] == 'u' || pathStr[0] == 'g' || pathStr[0] == 'o' || pathStr[0] == 'a') && strings.Contains(pathStr, "+")) {
			continue
		}

		resolved := parsers.ResolvePath(pathStr, c.projectRoot)

		// Check if git-tracked (allowed)
		if c.config.DownloadProtection.GitTrackedAllow {
			if parsers.IsGitTracked(resolved, c.projectRoot) {
				continue
			}
		}

		// Check if previously downloaded
		if c.downloadCheck != nil && c.downloadCheck.IsDownloadedFile(pathStr) {
			return c.Confirm(
				fmt.Sprintf("chmod +x on downloaded file: %s", pathStr),
				fmt.Sprintf("File was downloaded from internet. Give user: `chmod +x %s`", pathStr),
			)
		}

		// Check file type if enabled
		if c.config.DownloadProtection.DetectBinaryByMagic {
			result := c.checkBinaryType(resolved, pathStr)
			if result != nil && !result.IsAllowed() {
				return result
			}
		}
	}

	return c.Allow()
}

// isMakingExecutable checks if chmod command makes file executable.
func (c *ExecutionCheck) isMakingExecutable(cmd *ParsedCommand) bool {
	allArgs := append(cmd.Args, cmd.Flags...)
	for _, arg := range allArgs {
		// +x, a+x, u+x, g+x, o+x patterns
		if strings.Contains(arg, "+x") {
			return true
		}
		// Numeric modes: 7xx, x7x, xx7 (contains execute bit)
		if isNumeric(arg) && len(arg) >= 3 {
			for _, digit := range arg {
				if digit >= '0' && digit <= '7' {
					d := int(digit - '0')
					if d&1 != 0 { // Execute bit set
						return true
					}
				}
			}
		}
	}
	return false
}

// checkBinaryType checks file type using file command or magic bytes.
func (c *ExecutionCheck) checkBinaryType(path string, originalPath string) *CheckResult {
	info, err := os.Stat(path)
	if err != nil || info.IsDir() {
		return nil
	}

	// Try file command first with timeout
	cmd := exec.Command("file", "-b", path)

	done := make(chan []byte, 1)
	errChan := make(chan error, 1)
	go func() {
		out, err := cmd.Output()
		if err != nil {
			errChan <- err
		} else {
			done <- out
		}
	}()

	var output []byte
	select {
	case output = <-done:
		err = nil
	case err = <-errChan:
	case <-time.After(5 * time.Second):
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
		err = fmt.Errorf("timeout")
	}

	if err == nil {
		outputLower := strings.ToLower(string(output))
		if strings.Contains(outputLower, "executable") ||
			strings.Contains(outputLower, "script") ||
			strings.Contains(outputLower, "elf") ||
			strings.Contains(outputLower, "mach-o") ||
			strings.Contains(outputLower, "pe32") {
			return c.Confirm(
				fmt.Sprintf("chmod +x on binary/script file: %s", originalPath),
				fmt.Sprintf("File appears to be executable. Give user: `chmod +x %s`", originalPath),
			)
		}
		return nil
	}

	// Fallback to magic bytes if file command unavailable
	if c.config.DownloadProtection.FileCommandFallback {
		return c.checkMagicBytes(path, originalPath)
	}

	return nil
}

// checkMagicBytes checks file type by reading magic bytes.
func (c *ExecutionCheck) checkMagicBytes(path string, originalPath string) *CheckResult {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()

	header := make([]byte, 8)
	n, err := f.Read(header)
	if err != nil || n < 2 {
		return nil
	}

	for fileType, magic := range binaryMagic {
		if bytes.HasPrefix(header[:n], magic) {
			return c.Confirm(
				fmt.Sprintf("chmod +x on %s: %s", fileType, originalPath),
				fmt.Sprintf("File is %s. Give user: `chmod +x %s`", fileType, originalPath),
			)
		}
	}

	return nil
}

// isNumeric checks if a string is all digits.
func isNumeric(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}
