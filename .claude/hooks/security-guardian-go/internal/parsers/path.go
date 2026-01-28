package parsers

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// GetProjectRoot detects and returns the project root directory.
// It uses CLAUDE_PROJECT_DIR env var if set, otherwise searches for .git directory.
// The returned path has symlinks resolved (e.g. /tmp → /private/tmp on macOS)
// to ensure consistent path comparisons across the codebase.
func GetProjectRoot() string {
	// Check environment variable first
	if envRoot := os.Getenv("CLAUDE_PROJECT_DIR"); envRoot != "" {
		if absPath, err := filepath.Abs(envRoot); err == nil {
			return evalSymlinksOrClean(absPath)
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
			return evalSymlinksOrClean(current)
		}

		parent := filepath.Dir(current)
		if parent == current {
			break
		}
		current = parent
	}

	// Fall back to current working directory
	return evalSymlinksOrClean(cwd)
}

// evalSymlinksOrClean resolves symlinks on a path, falling back to Clean if resolution fails.
func evalSymlinksOrClean(path string) string {
	if resolved, err := filepath.EvalSymlinks(path); err == nil {
		return resolved
	}
	return filepath.Clean(path)
}

// ResolvePath resolves a path string to an absolute path, following symlinks.
// If baseDir is empty, uses current working directory.
func ResolvePath(pathStr string, baseDir string) string {
	if baseDir == "" {
		baseDir, _ = os.Getwd()
	}

	// Expand environment variables and user home
	expanded := os.ExpandEnv(pathStr)
	if strings.HasPrefix(expanded, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			expanded = filepath.Join(home, expanded[2:])
		}
	} else if expanded == "~" {
		if home, err := os.UserHomeDir(); err == nil {
			expanded = home
		}
	}

	// Resolve symlinks on baseDir before joining
	// This prevents mismatches like /tmp/proj vs /private/tmp/proj on macOS
	if resolvedBase, err := filepath.EvalSymlinks(baseDir); err == nil {
		baseDir = resolvedBase
	}

	// Make absolute if relative
	var path string
	if filepath.IsAbs(expanded) {
		path = expanded
	} else {
		path = filepath.Join(baseDir, expanded)
	}

	// Try to resolve symlinks (realpath equivalent)
	if resolved, err := filepath.EvalSymlinks(path); err == nil {
		return resolved
	}

	// If resolve fails, just clean the path
	return filepath.Clean(path)
}

// IsPathWithinAllowed checks if a path is within allowed directories.
func IsPathWithinAllowed(path string, projectRoot string, allowedPaths []string) bool {
	// Resolve project root
	resolvedRoot, err := filepath.EvalSymlinks(projectRoot)
	if err != nil {
		resolvedRoot = filepath.Clean(projectRoot)
	}

	// Check if within project
	rel, err := filepath.Rel(resolvedRoot, path)
	if err == nil && !strings.HasPrefix(rel, "..") {
		return true
	}

	// Check allowed paths
	for _, allowed := range allowedPaths {
		allowedPath := ResolvePath(allowed, "")
		rel, err := filepath.Rel(allowedPath, path)
		if err == nil && !strings.HasPrefix(rel, "..") {
			return true
		}
	}

	return false
}

// IsSymlinkEscape checks if a path uses symlinks to escape project boundaries.
// This detects when a symlink within the project points to a location outside the project.
func IsSymlinkEscape(pathStr string, projectRoot string, baseDir string) bool {
	if baseDir == "" {
		baseDir = projectRoot
	}

	// Resolve both paths fully
	resolved := ResolvePath(pathStr, baseDir)
	projectResolved, err := filepath.EvalSymlinks(projectRoot)
	if err != nil {
		projectResolved = filepath.Clean(projectRoot)
	}

	// Check if resolved path is within project
	rel, err := filepath.Rel(projectResolved, resolved)
	if err == nil && !strings.HasPrefix(rel, "..") {
		return false // Path is within project after resolution - no escape
	}

	// Path is outside project after resolution
	// Check if this is due to a symlink WITHIN the project pointing outside

	// Expand the original path
	expanded := os.ExpandEnv(pathStr)
	if strings.HasPrefix(expanded, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			expanded = filepath.Join(home, expanded[2:])
		}
	}

	var original string
	if filepath.IsAbs(expanded) {
		original = expanded
	} else {
		original = filepath.Join(baseDir, expanded)
	}
	original = filepath.Clean(original)

	// Build path component by component to find symlinks
	insideProject := false
	parts := strings.Split(original, string(filepath.Separator))

	checkPath := "/"
	if parts[0] == "" {
		parts = parts[1:]
	}

	for _, part := range parts {
		checkPath = filepath.Join(checkPath, part)

		// Check if we've entered the project directory
		if resolved, err := filepath.EvalSymlinks(checkPath); err == nil {
			rel, err := filepath.Rel(projectResolved, resolved)
			if err == nil && !strings.HasPrefix(rel, "..") {
				insideProject = true
			}
		}

		// If we're inside the project and hit a symlink that goes outside
		info, err := os.Lstat(checkPath)
		if err == nil && info.Mode()&os.ModeSymlink != 0 && insideProject {
			target, err := filepath.EvalSymlinks(checkPath)
			if err == nil {
				rel, err := filepath.Rel(projectResolved, target)
				if err != nil || strings.HasPrefix(rel, "..") {
					// Symlink inside project points outside - this is an escape
					return true
				}
			}
		}
	}

	// Not a symlink escape - just a path that was outside to begin with
	return false
}

// IsGitTracked checks if a file is tracked by git.
func IsGitTracked(filePath string, projectRoot string) bool {
	cmd := exec.Command("git", "ls-files", "--error-unmatch", filePath)
	cmd.Dir = projectRoot

	// Set a timeout using a goroutine
	done := make(chan error, 1)
	go func() {
		done <- cmd.Run()
	}()

	select {
	case err := <-done:
		return err == nil
	case <-time.After(5 * time.Second):
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
		return false
	}
}

// CheckArchivePathTraversal checks if an archive extraction path contains traversal attacks.
func CheckArchivePathTraversal(archivePath string) bool {
	normalized := filepath.Clean(archivePath)
	return strings.HasPrefix(normalized, "..")
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
