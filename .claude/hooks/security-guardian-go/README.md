# Security Guardian Go

High-performance security hooks for Claude Code, written in Go for maximum speed and minimal footprint.

## Features

- **Fast Cold Start**: ~10-20ms startup time (vs ~300-500ms for Python)
- **Single Binary**: No runtime dependencies, no virtual environments
- **Native Bash Parsing**: Uses mvdan/sh for accurate command analysis
- **Full Feature Parity**: All security checks from Python version

## Performance Comparison

| Metric | Python | Go |
|--------|--------|-----|
| Cold start | ~300-500ms | **~10-20ms** |
| Dependencies | venv + packages | **Single binary** |
| Size | ~50MB (venv) | **~10-15MB** |

## Installation

### Option 1: Download from Releases (Recommended)

```bash
# One-liner install
curl -fsSL https://raw.githubusercontent.com/artwist-polyakov/polyakov-claude-skills/main/.claude/hooks/security-guardian-go/scripts/install.sh | bash
```

Or manually download from [GitHub Releases](https://github.com/artwist-polyakov/polyakov-claude-skills/releases).

### Option 2: Build from Source

```bash
# Clone the repository
git clone https://github.com/artwist-polyakov/polyakov-claude-skills.git
cd polyakov-claude-skills/.claude/hooks/security-guardian-go

# Build for your platform
go build -o bin/guardian ./cmd/guardian

# Or build for all platforms
make build-all
```

## Supported Platforms

- **macOS ARM** (M1/M2/M3): `guardian-darwin-arm64`
- **macOS Intel**: `guardian-darwin-amd64`
- **Linux x64**: `guardian-linux-amd64`

## Integration with Claude Code

Add to your `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash|Read|Write|Edit|Glob|Grep|NotebookEdit",
      "hooks": [{
        "type": "command",
        "command": "\"$CLAUDE_PROJECT_DIR/.claude/hooks/security-guardian-go/bin/guardian\"",
        "timeout": 5000
      }]
    }]
  }
}
```

**Note**: Timeout reduced from 10000ms to 5000ms because Go is much faster.

## Configuration

Configuration is loaded from `internal/config/security_config.yaml` or the path specified in `SECURITY_GUARDIAN_CONFIG` environment variable.

The configuration file is identical to the Python version - see [security_config.yaml](internal/config/security_config.yaml) for all options.

## Security Checks

| Check | Description |
|-------|-------------|
| **Directory** | Primary protection - keeps operations within project boundaries |
| **Bypass** | Detects attempts to circumvent security (eval, pipe to shell) |
| **Git** | Blocks destructive git operations (force push, hard reset) |
| **Deletion** | Protects against dangerous file deletion |
| **Download** | Controls file downloads, blocks pipe to shell |
| **Unpack** | Prevents archive path traversal attacks |
| **Execution** | Monitors chmod +x on downloaded files |
| **Secrets** | Blocks access to sensitive files (.env, keys) |
| **CodeContent** | Detects dangerous patterns in scripts |

## How It Works

1. Claude Code calls the hook before tool execution
2. Guardian receives JSON on stdin with tool name and input
3. Security checks are run based on tool type
4. Guardian outputs JSON decision: `allow`, `ask`, or `deny`

### Example Input/Output

**Input** (stdin):
```json
{"tool_name": "Bash", "tool_input": {"command": "rm -rf /"}}
```

**Output** (stdout):
```json
{"permissionDecision": "deny", "message": "BLOCKED: Cannot recursively delete project root\nGuidance: Deleting entire project is blocked. Be more specific about what to delete."}
```

## Development

### Project Structure

```
security-guardian-go/
├── cmd/guardian/          # CLI entry point
├── internal/
│   ├── checks/            # Security check implementations
│   ├── config/            # Configuration schema and loader
│   ├── handlers/          # Tool handlers (Bash, Read, Write, etc.)
│   ├── messages/          # Guidance messages
│   └── parsers/           # Bash and path parsing
├── scripts/               # Build and install scripts
├── Makefile               # Build automation
└── go.mod                 # Go module definition
```

### Building

```bash
# Build for current platform
make build

# Build for all platforms
make build-all

# Run tests
make test

# Run benchmark
make benchmark
```

### Testing

```bash
# Run all tests
go test ./...

# Run with verbose output
go test -v ./...

# Run with coverage
go test -cover ./...
```

## License

MIT License - see repository root for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `make test`
5. Submit a pull request
