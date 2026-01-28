// Package parsers provides command and path parsing utilities.
package parsers

import (
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

// ParsedCommand represents a parsed bash command.
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

// ParseBashCommand parses a bash command string into structured ParsedCommand objects.
func ParseBashCommand(command string) []*ParsedCommand {
	if command == "" || strings.TrimSpace(command) == "" {
		return nil
	}

	command = strings.TrimSpace(command)

	// Try to parse with mvdan/sh
	reader := strings.NewReader(command)
	parser := syntax.NewParser()

	file, err := parser.Parse(reader, "")
	if err != nil {
		// Fall back to simple parsing on error
		return simpleParse(command)
	}

	var commands []*ParsedCommand

	for _, stmt := range file.Stmts {
		cmds := parseNode(stmt, command)
		commands = append(commands, cmds...)
	}

	if len(commands) == 0 {
		return simpleParse(command)
	}

	// Also extract commands from command/process substitutions.
	// e.g. `echo $(rm -rf ../outside)` or `cat <(cat /etc/passwd)`
	subCmds := extractSubstitutionCommands(file, command)
	commands = append(commands, subCmds...)

	return commands
}

// extractSubstitutionCommands walks the AST to find command/process substitutions
// and returns their inner commands as ParsedCommand objects.
func extractSubstitutionCommands(node syntax.Node, rawCommand string) []*ParsedCommand {
	var commands []*ParsedCommand

	syntax.Walk(node, func(n syntax.Node) bool {
		switch sub := n.(type) {
		case *syntax.CmdSubst:
			// $(cmd) or `cmd`
			for _, stmt := range sub.Stmts {
				cmds := parseNode(stmt, rawCommand)
				commands = append(commands, cmds...)
			}
		case *syntax.ProcSubst:
			// <(cmd) or >(cmd)
			for _, stmt := range sub.Stmts {
				cmds := parseNode(stmt, rawCommand)
				commands = append(commands, cmds...)
			}
		}
		return true
	})

	return commands
}

// parseNode parses a syntax node recursively.
func parseNode(node syntax.Node, rawCommand string) []*ParsedCommand {
	var commands []*ParsedCommand

	switch n := node.(type) {
	case *syntax.Stmt:
		if n.Cmd != nil {
			cmds := parseNode(n.Cmd, rawCommand)
			// Extract redirect targets from Stmt.Redirs and attach to commands
			if len(n.Redirs) > 0 && len(cmds) > 0 {
				var redirectPaths []string
				for _, redir := range n.Redirs {
					if redir.Word != nil {
						target := extractWordValue(redir.Word)
						if target != "" {
							redirectPaths = append(redirectPaths, target)
						}
					}
				}
				if len(redirectPaths) > 0 {
					// Attach redirects to the first (primary) command
					cmds[0].Redirects = append(cmds[0].Redirects, redirectPaths...)
				}
			}
			commands = append(commands, cmds...)
		}

	case *syntax.CallExpr:
		cmd := parseCallExpr(n, rawCommand)
		if cmd != nil {
			commands = append(commands, cmd)
		}

	case *syntax.BinaryCmd:
		// Handle pipelines and && / || / ;
		leftCmds := parseNode(n.X, rawCommand)
		rightCmds := parseNode(n.Y, rawCommand)

		if n.Op == syntax.Pipe {
			// Link pipeline commands via PipesTo chain
			if len(leftCmds) > 0 && len(rightCmds) > 0 {
				last := leftCmds[len(leftCmds)-1]
				for last.PipesTo != nil {
					last = last.PipesTo
				}
				last.PipesTo = rightCmds[0]
			}
			// Return ALL commands so checks that iterate the slice
			// (without traversing PipesTo) still see every command.
			commands = append(commands, leftCmds...)
			commands = append(commands, rightCmds...)
		} else {
			// For && and || and ;, just collect all commands
			commands = append(commands, leftCmds...)
			commands = append(commands, rightCmds...)
		}

	case *syntax.Subshell:
		for _, stmt := range n.Stmts {
			cmds := parseNode(stmt, rawCommand)
			commands = append(commands, cmds...)
		}

	case *syntax.Block:
		for _, stmt := range n.Stmts {
			cmds := parseNode(stmt, rawCommand)
			commands = append(commands, cmds...)
		}
	}

	return commands
}

// parseCallExpr parses a call expression into a ParsedCommand.
func parseCallExpr(call *syntax.CallExpr, rawCommand string) *ParsedCommand {
	if len(call.Args) == 0 {
		return nil
	}

	// Extract command name
	cmdName := extractWordValue(call.Args[0])
	if cmdName == "" {
		return nil
	}

	// Check if command is a variable expansion
	variableAsCommand := strings.HasPrefix(cmdName, "$") || strings.HasPrefix(cmdName, "${")

	var args []string
	var flags []string

	// Process arguments
	for i, arg := range call.Args[1:] {
		_ = i
		word := extractWordValue(arg)
		if word == "" {
			continue
		}
		if strings.HasPrefix(word, "-") {
			flags = append(flags, word)
		} else {
			args = append(args, word)
		}
	}

	return &ParsedCommand{
		Command:           cmdName,
		Args:              args,
		Flags:             flags,
		Redirects:         nil, // Redirects are parsed at Stmt level, not needed for security checks
		VariableAsCommand: variableAsCommand,
		Raw:               rawCommand,
	}
}

// extractWordValue extracts the string value from a syntax.Word.
func extractWordValue(word *syntax.Word) string {
	if word == nil {
		return ""
	}

	var parts []string
	for _, part := range word.Parts {
		switch p := part.(type) {
		case *syntax.Lit:
			parts = append(parts, p.Value)
		case *syntax.SglQuoted:
			parts = append(parts, p.Value)
		case *syntax.DblQuoted:
			// Recursively extract double-quoted content
			for _, qp := range p.Parts {
				if lit, ok := qp.(*syntax.Lit); ok {
					parts = append(parts, lit.Value)
				} else if pe, ok := qp.(*syntax.ParamExp); ok {
					// Keep variable references
					if pe.Short {
						parts = append(parts, "$"+pe.Param.Value)
					} else {
						parts = append(parts, "${"+pe.Param.Value+"}")
					}
				}
			}
		case *syntax.ParamExp:
			if p.Short {
				parts = append(parts, "$"+p.Param.Value)
			} else {
				parts = append(parts, "${"+p.Param.Value+"}")
			}
		case *syntax.CmdSubst:
			parts = append(parts, "$(...)") // Placeholder for command substitution
		}
	}

	return strings.Join(parts, "")
}

// simpleParse provides fallback parsing when mvdan/sh fails.
func simpleParse(command string) []*ParsedCommand {
	var commands []*ParsedCommand

	// Split by pipes first
	pipeParts := strings.Split(command, "|")

	for _, part := range pipeParts {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}

		// Split by && and ; for command lists
		for _, subpart := range splitCommandList(part) {
			subpart = strings.TrimSpace(subpart)
			if subpart == "" {
				continue
			}

			tokens := tokenize(subpart)
			if len(tokens) == 0 {
				continue
			}

			cmdName := tokens[0]
			var args []string
			var flags []string

			for _, token := range tokens[1:] {
				if strings.HasPrefix(token, "-") {
					flags = append(flags, token)
				} else {
					args = append(args, token)
				}
			}

			variableAsCommand := strings.HasPrefix(cmdName, "$")

			cmd := &ParsedCommand{
				Command:           cmdName,
				Args:              args,
				Flags:             flags,
				VariableAsCommand: variableAsCommand,
				Raw:               command,
			}
			commands = append(commands, cmd)
		}
	}

	// Link pipeline commands
	for i := 0; i < len(commands)-1; i++ {
		if i < len(pipeParts)-1 {
			commands[i].PipesTo = commands[i+1]
		}
	}

	return commands
}

// tokenize splits a command string into tokens, respecting quotes.
func tokenize(command string) []string {
	var tokens []string
	var current strings.Builder
	inQuotes := false
	quoteChar := byte(0)

	for i := 0; i < len(command); i++ {
		char := command[i]

		if (char == '"' || char == '\'') && (i == 0 || command[i-1] != '\\') {
			if !inQuotes {
				inQuotes = true
				quoteChar = char
			} else if char == quoteChar {
				inQuotes = false
				quoteChar = 0
			} else {
				current.WriteByte(char)
			}
		} else if char == ' ' && !inQuotes {
			if current.Len() > 0 {
				tokens = append(tokens, current.String())
				current.Reset()
			}
		} else {
			current.WriteByte(char)
		}
	}

	if current.Len() > 0 {
		tokens = append(tokens, current.String())
	}

	return tokens
}

// splitCommandList splits command by && and ; while respecting quotes.
func splitCommandList(command string) []string {
	var parts []string
	var current strings.Builder
	inQuotes := false
	quoteChar := byte(0)

	for i := 0; i < len(command); i++ {
		char := command[i]

		if (char == '"' || char == '\'') && (i == 0 || command[i-1] != '\\') {
			if !inQuotes {
				inQuotes = true
				quoteChar = char
			} else if char == quoteChar {
				inQuotes = false
				quoteChar = 0
			}
			current.WriteByte(char)
		} else if !inQuotes {
			if char == ';' || (char == '&' && i+1 < len(command) && command[i+1] == '&') {
				if current.Len() > 0 {
					parts = append(parts, current.String())
					current.Reset()
				}
				if char == '&' {
					i++ // Skip second &
				}
			} else {
				current.WriteByte(char)
			}
		} else {
			current.WriteByte(char)
		}
	}

	if current.Len() > 0 {
		parts = append(parts, current.String())
	}

	return parts
}

// ExtractPathsFromCommand extracts all file/directory paths from a parsed command.
func ExtractPathsFromCommand(cmd *ParsedCommand) []string {
	var paths []string

	// Add all args as potential paths
	paths = append(paths, cmd.Args...)

	// Add redirect targets
	paths = append(paths, cmd.Redirects...)

	// Extract path-like values embedded in flags (e.g. --target-directory=/tmp, -C/path)
	for _, flag := range cmd.Flags {
		if idx := strings.Index(flag, "="); idx > 0 {
			val := flag[idx+1:]
			if val != "" {
				paths = append(paths, val)
			}
		} else if strings.HasPrefix(flag, "-") && !strings.HasPrefix(flag, "--") && len(flag) > 2 {
			// Combined short flag with value: -C/tmp, -o/path
			// Check if there's a path-like suffix after the flag letter(s)
			for i := 1; i < len(flag); i++ {
				rest := flag[i:]
				if strings.HasPrefix(rest, "/") || strings.HasPrefix(rest, "~") || strings.HasPrefix(rest, ".") {
					paths = append(paths, rest)
					break
				}
			}
		}
	}

	// Filter to only path-like strings
	var pathLike []string
	for _, p := range paths {
		if strings.Contains(p, "/") || strings.HasPrefix(p, ".") || strings.HasPrefix(p, "~") {
			pathLike = append(pathLike, p)
		} else if strings.Contains(p, ".") && !strings.HasPrefix(p, "-") {
			// Also include if it looks like a filename with extension
			pathLike = append(pathLike, p)
		}
	}

	return pathLike
}

// gitGlobalFlagsWithValue lists git global options that consume a following argument.
// These must be skipped when searching for the subcommand in Args.
var gitGlobalFlagsWithValue = map[string]bool{
	"-C":          true,
	"-c":          true,
	"--git-dir":   true,
	"--work-tree": true,
	"--namespace":  true,
}

// GetGitSubcommandAndFlags extracts git subcommand and its flags from parsed commands.
// It skips git global flags (like -C <path>) that appear before the subcommand.
func GetGitSubcommandAndFlags(parsedCmds []*ParsedCommand) (string, []string) {
	for _, cmd := range parsedCmds {
		if cmd.Command == "git" && len(cmd.Args) > 0 {
			flags := make([]string, len(cmd.Flags))
			copy(flags, cmd.Flags)

			// Count how many global flags with values are in Flags.
			// Each one consumes one arg from Args (its value), which appears
			// before the real subcommand.
			// e.g., "git -C . push --force":
			//   Flags = ["-C", "--force"], Args = [".", "push"]
			//   "-C" consumes "." → skip 1 arg → subcommand = "push"
			skipArgs := 0
			for _, f := range cmd.Flags {
				if gitGlobalFlagsWithValue[f] {
					skipArgs++
				}
			}

			if skipArgs >= len(cmd.Args) {
				continue // No subcommand found after skipping global flag values
			}

			subcommand := cmd.Args[skipArgs]

			// Remaining args after subcommand might be flags (like push --force)
			for _, arg := range cmd.Args[skipArgs+1:] {
				if strings.HasPrefix(arg, "-") {
					flags = append(flags, arg)
				}
			}
			return subcommand, flags
		}
	}
	return "", nil
}

// IsPipeToShell checks if any command pipes to a shell.
func IsPipeToShell(parsedCmds []*ParsedCommand, shellTargets []string) bool {
	for _, cmd := range parsedCmds {
		if cmd.PipesTo != nil {
			targetCmd := cmd.PipesTo.Command
			for _, shell := range shellTargets {
				if targetCmd == shell || strings.HasSuffix(targetCmd, "/"+shell) {
					return true
				}
			}
		}
	}
	return false
}
