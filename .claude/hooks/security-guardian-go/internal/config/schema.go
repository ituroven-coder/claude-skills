// Package config provides configuration loading and schema definitions.
package config

// DirectoriesConfig holds directory boundaries configuration.
type DirectoriesConfig struct {
	ProjectRoot  string   `yaml:"project_root"`
	AllowedPaths []string `yaml:"allowed_paths"`
}

// GitConfig holds git operations configuration.
type GitConfig struct {
	HardBlocked     []string `yaml:"hard_blocked"`
	ConfirmRequired []string `yaml:"confirm_required"`
	Allowed         []string `yaml:"allowed"`
	CIAutoAllow     []string `yaml:"ci_auto_allow"`
}

// BypassPreventionConfig holds bypass prevention configuration.
type BypassPreventionConfig struct {
	BlockedOutsideProject             []string `yaml:"blocked_outside_project"`
	HardBlocked                       []string `yaml:"hard_blocked"`
	BlockVariableAsCommand            bool     `yaml:"block_variable_as_command"`
	BlockShellPipeTargets             []string `yaml:"block_shell_pipe_targets"`
	BlockShellExecPatterns            []string `yaml:"block_shell_exec_patterns"`
	ConfirmInterpreterInlineWithNetwork []string `yaml:"confirm_interpreter_inline_with_network"`
	NetworkPatterns                   []string `yaml:"network_patterns"`
	ObfuscationPatterns               []string `yaml:"obfuscation_patterns"`
	RCEPatternsRequireNetwork         []string `yaml:"rce_patterns_require_network"`
}

// DownloadProtectionConfig holds download protection configuration.
type DownloadProtectionConfig struct {
	RequireUserDownload       []string `yaml:"require_user_download"`
	AutoDownloadButCheckUnpack []string `yaml:"auto_download_but_check_unpack"`
	AutoDownload              []string `yaml:"auto_download"`
	BlockPipeToShell          bool     `yaml:"block_pipe_to_shell"`
	TrackDownloadedExecutables bool     `yaml:"track_downloaded_executables"`
	DownloadedFilesMetadata   string   `yaml:"downloaded_files_metadata"`
	DetectBinaryByMagic       bool     `yaml:"detect_binary_by_magic"`
	GitTrackedAllow           bool     `yaml:"git_tracked_allow"`
	FileCommandFallback       bool     `yaml:"file_command_fallback"`
}

// UnpackProtectionConfig holds archive unpacking protection configuration.
type UnpackProtectionConfig struct {
	CheckExtractedFiles       bool     `yaml:"check_extracted_files"`
	CheckArchivePathTraversal bool     `yaml:"check_archive_path_traversal"`
	BlockedPatterns           []string `yaml:"blocked_patterns"`
}

// ProtectedPathsConfig holds protected paths configuration.
type ProtectedPathsConfig struct {
	NoModify      []string `yaml:"no_modify"`
	NoReadContent []string `yaml:"no_read_content"`
}

// CodePattern represents a code pattern for sensitive file detection.
type CodePattern struct {
	Pattern     string `yaml:"pattern"`
	Description string `yaml:"description"`
}

// SensitiveFilesConfig holds sensitive files configuration.
type SensitiveFilesConfig struct {
	ForbiddenRead  []string      `yaml:"forbidden_read"`
	CodePatterns   []CodePattern `yaml:"code_patterns"`
	SecretEnvVars  []string      `yaml:"secret_env_vars"`
	CustomPatterns []CodePattern `yaml:"custom_patterns"`
}

// DangerousOperationsConfig holds dangerous operations patterns.
type DangerousOperationsConfig struct {
	Network          []string `yaml:"network"`
	SensitiveAccess  []string `yaml:"sensitive_access"`
	SecretScanning   []string `yaml:"secret_scanning"`
	SystemRecon      []string `yaml:"system_recon"`
	DynamicExecution []string `yaml:"dynamic_execution"`
	ShellExecution   []string `yaml:"shell_execution"`
}

// LoggingConfig holds logging configuration.
type LoggingConfig struct {
	Enabled      bool   `yaml:"enabled"`
	LogBlocked   bool   `yaml:"log_blocked"`
	LogAllCalls  bool   `yaml:"log_all_calls"`
	LogDirectory string `yaml:"log_directory"`
	LogContent   bool   `yaml:"log_content"`
	MaxLogSizeMB int    `yaml:"max_log_size_mb"`
	MaxLogFiles  int    `yaml:"max_log_files"`
}

// SecurityConfig is the main security configuration model.
type SecurityConfig struct {
	Directories         DirectoriesConfig         `yaml:"directories"`
	Git                 GitConfig                 `yaml:"git"`
	BypassPrevention    BypassPreventionConfig    `yaml:"bypass_prevention"`
	DownloadProtection  DownloadProtectionConfig  `yaml:"download_protection"`
	UnpackProtection    UnpackProtectionConfig    `yaml:"unpack_protection"`
	ProtectedPaths      ProtectedPathsConfig      `yaml:"protected_paths"`
	SensitiveFiles      SensitiveFilesConfig      `yaml:"sensitive_files"`
	DangerousOperations DangerousOperationsConfig `yaml:"dangerous_operations"`
	Logging             LoggingConfig             `yaml:"logging"`
}

// DefaultConfig returns a configuration with sensible defaults.
func DefaultConfig() *SecurityConfig {
	return &SecurityConfig{
		Directories: DirectoriesConfig{
			AllowedPaths: []string{},
		},
		Git: GitConfig{
			HardBlocked:     []string{"push --force"},
			ConfirmRequired: []string{"push -f", "reset --hard", "branch -D", "clean -fd", "reflog expire"},
			Allowed:         []string{"push --force-with-lease", "clean -fd --dry-run", "clean -fdn"},
			CIAutoAllow:     []string{"clean -fd", "reset --hard"},
		},
		BypassPrevention: BypassPreventionConfig{
			BlockedOutsideProject:             []string{"base64 -d", "xxd -r"},
			HardBlocked:                       []string{"eval"},
			BlockVariableAsCommand:            true,
			BlockShellPipeTargets:             []string{"sh", "bash", "zsh", "fish"},
			BlockShellExecPatterns:            []string{"sh -c", "bash -c", "zsh -c", "dash -c", "ksh -c", "ash -c", "busybox sh", "env -i bash", "env -i sh"},
			ConfirmInterpreterInlineWithNetwork: []string{"python -c", "python3 -c", "perl -e", "node -e", "ruby -e"},
			NetworkPatterns:                   []string{"import requests", "import urllib", "import http.client", "import socket", "import httpx", "import aiohttp", "require('http')", "fetch("},
			ObfuscationPatterns:               []string{"importlib.import_module", "__import__"},
			RCEPatternsRequireNetwork:         []string{"exec(base64", "exec(bytes.fromhex", "eval(base64"},
		},
		DownloadProtection: DownloadProtectionConfig{
			RequireUserDownload:       []string{".py", ".sh", ".bash", ".rb", ".pl", ".js", ".exe", ".app", ".dmg", ".pkg", ".deb", ".bin", ".msi"},
			AutoDownloadButCheckUnpack: []string{".tar.gz", ".tgz", ".zip", ".rar", ".7z", ".tar.bz2", ".tar.xz"},
			AutoDownload:              []string{".json", ".yaml", ".yml", ".txt", ".csv", ".md", ".xml", ".html"},
			BlockPipeToShell:          true,
			TrackDownloadedExecutables: true,
			DownloadedFilesMetadata:   ".claude/hooks/security-guardian/.downloaded.json",
			DetectBinaryByMagic:       true,
			GitTrackedAllow:           true,
			FileCommandFallback:       true,
		},
		UnpackProtection: UnpackProtectionConfig{
			CheckExtractedFiles:       true,
			CheckArchivePathTraversal: true,
			BlockedPatterns:           []string{"tar -C ../", "tar --directory=../", "tar --one-top-level=../", "unzip -d ../", "bsdtar -C ../", "bsdtar -s", "python -m zipfile -e", "python3 -m zipfile -e"},
		},
		ProtectedPaths: ProtectedPathsConfig{
			NoModify: []string{
				".git/**",
				".claude/settings.json",
				".claude/settings.local.json",
				".claude/hooks/security-guardian/main.py",
				".claude/hooks/security-guardian/pyproject.toml",
				".claude/hooks/security-guardian/config/**",
				".claude/hooks/security-guardian/checks/**",
				".claude/hooks/security-guardian/handlers/**",
				".claude/hooks/security-guardian/parsers/**",
				".claude/hooks/security-guardian/messages/**",
				// Go version self-protection
				".claude/hooks/security-guardian-go/cmd/**",
				".claude/hooks/security-guardian-go/internal/**",
				".claude/hooks/security-guardian-go/go.mod",
				".claude/hooks/security-guardian-go/go.sum",
				".claude/hooks/security-guardian-go/Makefile",
				".claude/hooks/security-guardian-go/scripts/**",
			},
			NoReadContent: []string{"**/.env", "**/.env.*", "!**/.env.example", "!**/.env.template"},
		},
		SensitiveFiles: SensitiveFilesConfig{
			ForbiddenRead: []string{
				"**/.env", "**/.env.*", "!**/.env.example", "!**/.env.template",
				"**/secrets.yaml", "**/credentials.json",
				"**/*.pem", "**/*.key",
				"**/id_rsa*", "**/id_ed25519*",
			},
			CodePatterns: []CodePattern{
				{Pattern: `open\(['""].*\.env`, Description: "Reading .env file"},
				{Pattern: `open\(['""].*\.pem`, Description: "Reading private key"},
				{Pattern: `load_dotenv\(`, Description: "Loading .env via dotenv"},
				{Pattern: `\.aws/credentials`, Description: "AWS credentials access"},
				{Pattern: `\.netrc`, Description: "Netrc file access"},
				{Pattern: `\.npmrc`, Description: "NPM config access"},
				{Pattern: `\.pypirc`, Description: "PyPI config access"},
			},
			SecretEnvVars: []string{
				"API_KEY", "SECRET_KEY", "DATABASE_URL",
				"AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY",
				"GITHUB_TOKEN", "OPENAI_API_KEY", "ANTHROPIC_API_KEY",
				"STRIPE_SECRET_KEY", "PRIVATE_KEY", "PASSWORD", "DB_PASSWORD",
			},
			CustomPatterns: []CodePattern{},
		},
		DangerousOperations: DangerousOperationsConfig{
			Network:          []string{`import\s+(requests|urllib|httpx|aiohttp)`, `from\s+(requests|urllib|httpx)\s`, `socket\.`, `urlopen\(`, `curl\s`, `wget\s`},
			SensitiveAccess:  []string{`\.env`, `/etc/passwd`, `~/.ssh`, `\.aws/credentials`, `\.netrc`, `\.npmrc`, `\.pypirc`},
			SecretScanning:   []string{`grep.*password`, `grep.*secret`, `grep.*token`, `grep.*api.key`, `find.*\.env`, `find.*\.ssh`, `find.*\.aws`, `glob\(.*\.env`, `os\.walk.*password`, `re\.search.*password`, `re\.findall.*secret`},
			SystemRecon:      []string{`os\.environ`, `getpass\.getuser`, `socket\.gethostname`, `platform\.`, `subprocess.*whoami`, `subprocess.*id\s`, `subprocess.*uname`},
			DynamicExecution: []string{`exec\(`, `eval\(`, `compile\(`, `__import__\(`, `importlib\.import_module`, `subprocess\..*shell=True`},
			ShellExecution:   []string{`subprocess\.`, `os\.system\(`, `os\.popen\(`},
		},
		Logging: LoggingConfig{
			Enabled:      true,
			LogBlocked:   true,
			LogAllCalls:  true,
			LogDirectory: "${HOME}/.claude/logs/security-guardian",
			LogContent:   false,
			MaxLogSizeMB: 10,
			MaxLogFiles:  5,
		},
	}
}
