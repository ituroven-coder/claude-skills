#!/bin/sh
# Tests for auto-approve-plan.sh hook script.
# Run from any directory inside a git repo.
# Creates a temporary .codex-review/ structure, runs the hook, checks output.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/auto-approve-plan.sh"

# --- Setup temp repo ---
TMPDIR_BASE="${TMPDIR:-/tmp}"
TEST_DIR="$TMPDIR_BASE/test-auto-approve-$$"
mkdir -p "$TEST_DIR"
trap 'rm -rf "$TEST_DIR"' EXIT

cd "$TEST_DIR"
git init -q -b main

# No commits — symbolic-ref must still resolve branch name
BRANCH_SLUG="main"

PASS=0
FAIL=0

assert_output() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"

    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$test_name"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s\n" "$test_name"
        printf "    expected: %s\n" "$expected"
        printf "    actual:   %s\n" "$actual"
    fi
}

# ============================
# Test 1: AUTO_REVIEW not set (no config.env) — silent passthrough
# ============================
printf "Test 1: AUTO_REVIEW not set\n"
output="$(echo '{}' | sh "$HOOK" 2>/dev/null)" || true
assert_output "empty output (passthrough)" "" "$output"

# ============================
# Test 2: AUTO_REVIEW=false — silent passthrough
# ============================
printf "Test 2: AUTO_REVIEW=false\n"
mkdir -p .codex-review
printf 'AUTO_REVIEW=false\n' > .codex-review/config.env
output="$(echo '{}' | sh "$HOOK" 2>/dev/null)" || true
assert_output "empty output (passthrough)" "" "$output"

# ============================
# Test 3: AUTO_REVIEW=true, no verdict.txt — deny
# ============================
printf "Test 3: AUTO_REVIEW=true, no verdict\n"
printf 'AUTO_REVIEW=true\n' > .codex-review/config.env
mkdir -p ".codex-review/$BRANCH_SLUG"
rm -f ".codex-review/$BRANCH_SLUG/verdict.txt"
output="$(echo '{}' | sh "$HOOK" 2>/dev/null)" || true
case "$output" in
    *'"behavior":"deny"'*) assert_output "deny decision" "yes" "yes" ;;
    *) assert_output "deny decision" "contains behavior:deny" "$output" ;;
esac
case "$output" in
    *"codex-review"*) assert_output "message mentions skill" "yes" "yes" ;;
    *) assert_output "message mentions skill" "contains codex-review" "$output" ;;
esac

# ============================
# Test 4: AUTO_REVIEW=true, verdict=CHANGES_REQUESTED — deny
# ============================
printf "Test 4: AUTO_REVIEW=true, verdict=CHANGES_REQUESTED\n"
printf 'CHANGES_REQUESTED' > ".codex-review/$BRANCH_SLUG/verdict.txt"
output="$(echo '{}' | sh "$HOOK" 2>/dev/null)" || true
case "$output" in
    *'"behavior":"deny"'*) assert_output "deny decision" "yes" "yes" ;;
    *) assert_output "deny decision" "contains behavior:deny" "$output" ;;
esac

# ============================
# Test 5: AUTO_REVIEW=true, verdict=APPROVED — allow
# ============================
printf "Test 5: AUTO_REVIEW=true, verdict=APPROVED\n"
printf 'APPROVED' > ".codex-review/$BRANCH_SLUG/verdict.txt"
output="$(echo '{}' | sh "$HOOK" 2>/dev/null)" || true
case "$output" in
    *'"behavior":"allow"'*) assert_output "allow decision" "yes" "yes" ;;
    *) assert_output "allow decision" "contains behavior:allow" "$output" ;;
esac

# ============================
# Test 6: AUTO_REVIEW=true, verdict=APPROVED with whitespace — allow
# ============================
printf "Test 6: verdict with trailing whitespace\n"
printf '  APPROVED \n' > ".codex-review/$BRANCH_SLUG/verdict.txt"
output="$(echo '{}' | sh "$HOOK" 2>/dev/null)" || true
case "$output" in
    *'"behavior":"allow"'*) assert_output "allow despite whitespace" "yes" "yes" ;;
    *) assert_output "allow despite whitespace" "contains behavior:allow" "$output" ;;
esac

# ============================
# Test 7: AUTO_REVIEW with quotes in config — parsed correctly
# ============================
printf "Test 7: AUTO_REVIEW with quotes\n"
printf 'AUTO_REVIEW="true"\n' > .codex-review/config.env
printf 'APPROVED' > ".codex-review/$BRANCH_SLUG/verdict.txt"
output="$(echo '{}' | sh "$HOOK" 2>/dev/null)" || true
case "$output" in
    *'"behavior":"allow"'*) assert_output "quoted value parsed" "yes" "yes" ;;
    *) assert_output "quoted value parsed" "contains behavior:allow" "$output" ;;
esac

# ============================
# Test 8: repo with commits — branch resolved correctly
# ============================
printf "Test 8: repo with commits\n"
TEST_DIR2="$TMPDIR_BASE/test-auto-approve-commits-$$"
mkdir -p "$TEST_DIR2"
cd "$TEST_DIR2"
git init -q -b feat/my-feature
git config user.email "test@test.com"
git config user.name "Test"
git commit -q --allow-empty -m "init"

BRANCH_SLUG2="feat-my-feature"
mkdir -p ".codex-review"
printf 'AUTO_REVIEW=true\n' > .codex-review/config.env
mkdir -p ".codex-review/$BRANCH_SLUG2"
printf 'APPROVED' > ".codex-review/$BRANCH_SLUG2/verdict.txt"
output="$(echo '{}' | sh "$HOOK" 2>/dev/null)" || true
case "$output" in
    *'"behavior":"allow"'*) assert_output "allow with commits + slash branch" "yes" "yes" ;;
    *) assert_output "allow with commits + slash branch" "contains behavior:allow" "$output" ;;
esac
cd "$TEST_DIR"
rm -rf "$TEST_DIR2"

# ============================
# Test 9: plugin.json hook commands use ${CLAUDE_PLUGIN_ROOT}, not relative paths
# ============================
printf "Test 9: plugin.json hook paths use CLAUDE_PLUGIN_ROOT\n"
PLUGIN_JSON="$SCRIPT_DIR/../../../.claude-plugin/plugin.json"
if [ -f "$PLUGIN_JSON" ]; then
    # Extract all "command" values from hooks and check for relative paths
    bad_paths="$(grep '"command"' "$PLUGIN_JSON" | grep -v 'CLAUDE_PLUGIN_ROOT' | grep -E '\./|[^/]scripts/' || true)"
    if [ -z "$bad_paths" ]; then
        assert_output "no relative paths in hook commands" "yes" "yes"
    else
        assert_output "no relative paths in hook commands" "" "$bad_paths"
    fi
else
    assert_output "plugin.json exists" "yes" "no"
fi

# ============================
# Summary
# ============================
printf "\n=== Results: %d passed, %d failed ===\n" "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
