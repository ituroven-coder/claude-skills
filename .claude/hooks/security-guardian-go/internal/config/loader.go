package config

import (
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

// expandEnvVars expands environment variables in a string.
func expandEnvVars(value string) string {
	return os.ExpandEnv(value)
}

// expandConfigEnvVars recursively expands environment variables in config.
func expandConfigEnvVars(config *SecurityConfig) {
	// Expand directories
	config.Directories.ProjectRoot = expandEnvVars(config.Directories.ProjectRoot)
	for i := range config.Directories.AllowedPaths {
		config.Directories.AllowedPaths[i] = expandEnvVars(config.Directories.AllowedPaths[i])
	}

	// Expand download protection
	config.DownloadProtection.DownloadedFilesMetadata = expandEnvVars(config.DownloadProtection.DownloadedFilesMetadata)

	// Expand logging
	config.Logging.LogDirectory = expandEnvVars(config.Logging.LogDirectory)
}

// LoadConfig loads security configuration from a YAML file.
// If configPath is empty, it looks for security_config.yaml in the same directory as the executable.
func LoadConfig(configPath string) (*SecurityConfig, error) {
	if configPath == "" {
		// Try to find config relative to executable
		execPath, err := os.Executable()
		if err == nil {
			configPath = filepath.Join(filepath.Dir(execPath), "internal", "config", "security_config.yaml")
		}
	}

	// If still empty or file doesn't exist, try relative to working directory
	if configPath == "" {
		configPath = "internal/config/security_config.yaml"
	}

	// Check if file exists
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		// Return default config if file doesn't exist
		return DefaultConfig(), nil
	}

	data, err := os.ReadFile(configPath)
	if err != nil {
		// Return default config on read error
		return DefaultConfig(), nil
	}

	// Start with defaults
	config := DefaultConfig()

	// Parse YAML into config
	if err := yaml.Unmarshal(data, config); err != nil {
		// Return default config on parse error
		return DefaultConfig(), nil
	}

	// Expand environment variables
	expandConfigEnvVars(config)

	return config, nil
}

// LoadConfigFromBytes loads configuration from YAML bytes.
func LoadConfigFromBytes(data []byte) (*SecurityConfig, error) {
	config := DefaultConfig()

	if err := yaml.Unmarshal(data, config); err != nil {
		return nil, err
	}

	expandConfigEnvVars(config)

	return config, nil
}

// FindConfigPath looks for configuration file in common locations.
func FindConfigPath() string {
	// Check environment variable
	if path := os.Getenv("SECURITY_GUARDIAN_CONFIG"); path != "" {
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}

	// Check CLAUDE_PROJECT_DIR
	if projectDir := os.Getenv("CLAUDE_PROJECT_DIR"); projectDir != "" {
		path := filepath.Join(projectDir, ".claude", "hooks", "security-guardian-go", "internal", "config", "security_config.yaml")
		if _, err := os.Stat(path); err == nil {
			return path
		}
		// Also check old location
		path = filepath.Join(projectDir, ".claude", "hooks", "security-guardian", "config", "security_config.yaml")
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}

	// Check relative to executable
	if execPath, err := os.Executable(); err == nil {
		execDir := filepath.Dir(execPath)

		// Check same directory as executable
		path := filepath.Join(execDir, "security_config.yaml")
		if _, err := os.Stat(path); err == nil {
			return path
		}

		// Check internal/config relative to executable
		path = filepath.Join(execDir, "internal", "config", "security_config.yaml")
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}

	// Check relative to working directory
	paths := []string{
		"security_config.yaml",
		"internal/config/security_config.yaml",
		".claude/hooks/security-guardian-go/internal/config/security_config.yaml",
		".claude/hooks/security-guardian/config/security_config.yaml",
	}

	for _, path := range paths {
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}

	return ""
}

// GetProjectRoot returns the project root directory.
// It uses CLAUDE_PROJECT_DIR env var if set, otherwise searches for .git directory.
func GetProjectRoot() string {
	// Check environment variable first
	if envRoot := os.Getenv("CLAUDE_PROJECT_DIR"); envRoot != "" {
		if absPath, err := filepath.Abs(envRoot); err == nil {
			return absPath
		}
		return envRoot
	}

	// Try to find .git directory
	cwd, err := os.Getwd()
	if err != nil {
		return "."
	}

	current := cwd
	for {
		gitPath := filepath.Join(current, ".git")
		if _, err := os.Stat(gitPath); err == nil {
			return current
		}

		parent := filepath.Dir(current)
		if parent == current {
			break
		}
		current = parent
	}

	// Fall back to current working directory
	return cwd
}

// IsInCIEnvironment checks if running in a CI environment.
func IsInCIEnvironment() bool {
	ciVars := []string{"CI", "GITHUB_ACTIONS", "GITLAB_CI", "JENKINS_URL", "CIRCLECI", "TRAVIS"}
	for _, v := range ciVars {
		if os.Getenv(v) != "" {
			return true
		}
	}
	return false
}

// ExpandPath expands ~ and environment variables in a path.
func ExpandPath(path string) string {
	// Expand ~
	if strings.HasPrefix(path, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			path = filepath.Join(home, path[2:])
		}
	} else if path == "~" {
		if home, err := os.UserHomeDir(); err == nil {
			path = home
		}
	}

	// Expand environment variables
	path = os.ExpandEnv(path)

	return path
}
