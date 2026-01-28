package checks

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/artwist-polyakov/security-guardian/internal/config"
	"github.com/artwist-polyakov/security-guardian/internal/parsers"
)

// DownloadCheck checks for dangerous download operations.
type DownloadCheck struct {
	BaseCheck
	projectRoot     string
	config          *config.SecurityConfig
	downloadedFiles map[string]interface{}
}

// Download commands
var downloadCommands = map[string]bool{
	"curl":   true,
	"wget":   true,
	"fetch":  true,
	"aria2c": true,
}

// Script extensions
var scriptExtensions = map[string]bool{
	".py":   true,
	".sh":   true,
	".bash": true,
	".rb":   true,
	".pl":   true,
	".js":   true,
}

// Binary extensions
var binaryExtensions = map[string]bool{
	".exe": true,
	".app": true,
	".dmg": true,
	".pkg": true,
	".deb": true,
	".bin": true,
	".msi": true,
}

// NewDownloadCheck creates a new DownloadCheck instance.
func NewDownloadCheck(cfg *config.SecurityConfig) *DownloadCheck {
	return &DownloadCheck{
		BaseCheck:   BaseCheck{CheckName: "download_check"},
		projectRoot: parsers.GetProjectRoot(),
		config:      cfg,
	}
}

// CheckCommand checks download commands for safety.
func (c *DownloadCheck) CheckCommand(rawCommand string, parsedCommands []*ParsedCommand) *CheckResult {
	// First check for pipe to shell (always HARD DENY)
	shellTargets := c.config.BypassPrevention.BlockShellPipeTargets
	parserCmds := make([]*parsers.ParsedCommand, len(parsedCommands))
	for i, cmd := range parsedCommands {
		parserCmds[i] = convertParsedCommand(cmd)
	}

	if parsers.IsPipeToShell(parserCmds, shellTargets) {
		return c.Deny(
			"Downloading and piping to shell detected",
			"Cannot pipe downloads to shell. Download file, review, then run.",
		)
	}

	for _, cmd := range parsedCommands {
		if downloadCommands[cmd.Command] {
			result := c.checkDownload(cmd)
			if !result.IsAllowed() {
				return result
			}
		}
	}

	return c.Allow()
}

// checkDownload checks a single download command.
func (c *DownloadCheck) checkDownload(cmd *ParsedCommand) *CheckResult {
	url := c.extractURL(cmd)
	outputPath := c.extractOutputPath(cmd)

	if url == "" {
		return c.Allow()
	}

	// Get file extension
	extension := c.getExtension(url, outputPath)

	// Scripts are allowed - they will be checked by CodeContentCheck when executed
	if extension != "" {
		for scriptExt := range scriptExtensions {
			if strings.HasSuffix(extension, scriptExt) {
				if c.config.DownloadProtection.TrackDownloadedExecutables {
					c.trackDownloadedFile(url, outputPath)
				}
				return c.Allow()
			}
		}
	}

	// Binary executables - ASK (can't content-check them)
	if extension != "" {
		for binaryExt := range binaryExtensions {
			if strings.HasSuffix(extension, binaryExt) {
				return c.Ask(
					fmt.Sprintf("Download of binary executable: *%s", extension),
					fmt.Sprintf("Binary files cannot be content-checked. Give user the command: `%s %s %s`",
						cmd.Command, strings.Join(cmd.Flags, " "), strings.Join(cmd.Args, " ")),
				)
			}
		}
	}

	// Auto-download data files are allowed
	for _, ext := range c.config.DownloadProtection.AutoDownload {
		if extension != "" && strings.HasSuffix(extension, ext) {
			return c.Allow()
		}
	}

	// Archives can be downloaded but will be checked on unpack
	for _, ext := range c.config.DownloadProtection.AutoDownloadButCheckUnpack {
		if extension != "" && strings.HasSuffix(extension, ext) {
			return c.Allow()
		}
	}

	// Unknown extension - allow but track for execution check
	if c.config.DownloadProtection.TrackDownloadedExecutables {
		c.trackDownloadedFile(url, outputPath)
	}

	return c.Allow()
}

// extractURL extracts URL from download command arguments.
func (c *DownloadCheck) extractURL(cmd *ParsedCommand) string {
	for _, arg := range cmd.Args {
		if strings.HasPrefix(arg, "http://") || strings.HasPrefix(arg, "https://") || strings.HasPrefix(arg, "ftp://") {
			return arg
		}
	}
	return ""
}

// extractOutputPath extracts output path from download command flags.
// We check Flags for -o=value format and also scan the raw command for
// the token following `-o`/`--output`.
// NOTE: -O (uppercase, curl --remote-name) does NOT take an argument —
// it uses the filename from the URL. Only -o/--output take a path.
func (c *DownloadCheck) extractOutputPath(cmd *ParsedCommand) string {
	// Check for -o=value or --output=value format first
	for _, flag := range cmd.Flags {
		if strings.HasPrefix(flag, "-o=") || strings.HasPrefix(flag, "--output=") {
			return strings.SplitN(flag, "=", 2)[1]
		}
	}

	// Check if -o/--output is present
	hasLowercaseO := false
	for _, flag := range cmd.Flags {
		if flag == "-o" || flag == "--output" {
			hasLowercaseO = true
			break
		}
	}

	if !hasLowercaseO {
		return ""
	}

	// Scan raw command to find the token right after -o/--output.
	// This avoids misidentifying values of other flags (like -H) as output path.
	if cmd.Raw != "" {
		tokens := tokenizeRaw(cmd.Raw)
		for i, tok := range tokens {
			if (tok == "-o" || tok == "--output") && i+1 < len(tokens) {
				next := tokens[i+1]
				if !strings.HasPrefix(next, "-") {
					return next
				}
			}
		}
	}

	return ""
}

// tokenizeRaw splits a raw command string into tokens respecting quotes.
func tokenizeRaw(command string) []string {
	var tokens []string
	var current strings.Builder
	inQuotes := false
	quoteChar := byte(0)

	for i := 0; i < len(command); i++ {
		ch := command[i]
		if inQuotes {
			if ch == quoteChar {
				inQuotes = false
			} else {
				current.WriteByte(ch)
			}
		} else {
			switch ch {
			case '\'', '"':
				inQuotes = true
				quoteChar = ch
			case ' ', '\t':
				if current.Len() > 0 {
					tokens = append(tokens, current.String())
					current.Reset()
				}
			case '&', '|', ';':
				if current.Len() > 0 {
					tokens = append(tokens, current.String())
					current.Reset()
				}
			default:
				current.WriteByte(ch)
			}
		}
	}
	if current.Len() > 0 {
		tokens = append(tokens, current.String())
	}
	return tokens
}

// getExtension gets file extension from URL or output path.
func (c *DownloadCheck) getExtension(url string, outputPath string) string {
	// Prefer output path if available
	if outputPath != "" {
		ext := filepath.Ext(outputPath)
		// Handle multiple extensions like .tar.gz
		base := strings.TrimSuffix(outputPath, ext)
		ext2 := filepath.Ext(base)
		if ext2 != "" {
			return ext2 + ext
		}
		return ext
	}

	// Fall back to URL
	if url != "" {
		cleanURL := strings.Split(url, "?")[0]
		ext := filepath.Ext(cleanURL)
		base := strings.TrimSuffix(cleanURL, ext)
		ext2 := filepath.Ext(base)
		if ext2 != "" {
			return ext2 + ext
		}
		return ext
	}

	return ""
}

// trackDownloadedFile tracks a downloaded file for later execution check.
func (c *DownloadCheck) trackDownloadedFile(url string, outputPath string) {
	if !c.config.DownloadProtection.TrackDownloadedExecutables {
		return
	}

	files := c.loadDownloadedFiles()

	var resolved string
	if outputPath != "" {
		resolved = parsers.ResolvePath(outputPath, c.projectRoot)
	} else {
		// Extract filename from URL
		filename := filepath.Base(strings.Split(url, "?")[0])
		resolved = parsers.ResolvePath(filename, c.projectRoot)
	}

	files[resolved] = map[string]interface{}{
		"url":            url,
		"downloaded_at":  time.Now().UTC().Format(time.RFC3339),
		"checked_binary": false,
	}

	c.downloadedFiles = files
	c.saveDownloadedFiles()
}

// loadDownloadedFiles loads downloaded files metadata.
func (c *DownloadCheck) loadDownloadedFiles() map[string]interface{} {
	if c.downloadedFiles != nil {
		return c.downloadedFiles
	}

	metadataPath := filepath.Join(c.projectRoot, c.config.DownloadProtection.DownloadedFilesMetadata)
	data, err := os.ReadFile(metadataPath)
	if err != nil {
		c.downloadedFiles = make(map[string]interface{})
		return c.downloadedFiles
	}

	files := make(map[string]interface{})
	if err := json.Unmarshal(data, &files); err != nil {
		c.downloadedFiles = make(map[string]interface{})
		return c.downloadedFiles
	}

	c.downloadedFiles = files
	return files
}

// saveDownloadedFiles saves downloaded files metadata.
func (c *DownloadCheck) saveDownloadedFiles() {
	if c.downloadedFiles == nil {
		return
	}

	metadataPath := filepath.Join(c.projectRoot, c.config.DownloadProtection.DownloadedFilesMetadata)

	// Ensure parent directory exists
	dir := filepath.Dir(metadataPath)
	os.MkdirAll(dir, 0755)

	data, err := json.MarshalIndent(c.downloadedFiles, "", "  ")
	if err != nil {
		return
	}

	os.WriteFile(metadataPath, data, 0644)
}

// IsDownloadedFile checks if a file was previously downloaded.
func (c *DownloadCheck) IsDownloadedFile(path string) bool {
	files := c.loadDownloadedFiles()
	resolved := parsers.ResolvePath(path, c.projectRoot)
	_, ok := files[resolved]
	return ok
}
