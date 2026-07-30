#!/usr/bin/env bash
# Structural checks on the prose deliverables.

test_skill_frontmatter() {
  assert_file_has "$ROOT/SKILL.md" "name: promptify"
  assert_file_has "$ROOT/SKILL.md" "trigger: /promptify"
  assert_file_has "$ROOT/SKILL.md" "description:"
  assert_eq "$(head -1 "$ROOT/SKILL.md")" "---" "first line of SKILL.md"
}

test_skill_has_required_sections() {
  local s
  for s in "## Pipeline" "## Universal core" "## Anti-patterns" \
           "## Guardrails" "## Output contract" "## Approval" "## Edge cases"; do
    assert_file_has "$ROOT/SKILL.md" "$s"
  done
}

test_skill_describes_all_five_stages() {
  local s
  for s in "1. Classify" "2. Recon" "3. Gap scan" "4. Rewrite" "5. Present"; do
    assert_file_has "$ROOT/SKILL.md" "$s"
  done
}

test_skill_points_at_lenses() {
  assert_file_has "$ROOT/SKILL.md" "references/lenses.md"
}

test_skill_within_line_budget() {
  assert_max_lines "$ROOT/SKILL.md" 200
}

test_lenses_has_a_section_per_kind() {
  local k
  for k in code research writing analysis creative meta; do
    assert_file_has "$ROOT/references/lenses.md" "## $k"
  done
}

test_lenses_meta_composes_writing_and_code() {
  local body
  body="$(awk '/^## meta$/{f=1;next} /^## /{f=0} f' "$ROOT/references/lenses.md")"
  assert_contains "$body" "writing" "meta section body"
  assert_contains "$body" "code" "meta section body"
}

test_lenses_within_line_budget() {
  assert_max_lines "$ROOT/references/lenses.md" 200
}

test_examples_has_four_cases() {
  local n
  n="$(grep -cE '^### Case [0-9]+:' "$ROOT/references/examples.md" 2>/dev/null || printf '0')"
  assert_eq "$n" "4" "case count in examples.md"
}

test_examples_cover_the_required_scenarios() {
  local s
  for s in "vague code" "already precise" "multi-domain" "non-code"; do
    assert_file_has "$ROOT/references/examples.md" "$s"
  done
}

test_examples_each_case_has_all_three_parts() {
  local raw expected optimized
  raw="$(grep -cF '**Raw:**' "$ROOT/references/examples.md" 2>/dev/null || printf '0')"
  expected="$(grep -cF '**Expected behavior:**' "$ROOT/references/examples.md" 2>/dev/null || printf '0')"
  optimized="$(grep -cF '**Optimized:**' "$ROOT/references/examples.md" 2>/dev/null || printf '0')"
  assert_eq "$raw" "4" "Raw sections"
  assert_eq "$expected" "4" "Expected behavior sections"
  assert_eq "$optimized" "4" "Optimized sections"
}

test_command_frontmatter() {
  assert_eq "$(head -1 "$ROOT/commands/p.md")" "---" "first line of p.md"
  assert_file_has "$ROOT/commands/p.md" "description:"
  assert_file_has "$ROOT/commands/p.md" "argument-hint:"
}

test_command_delegates_to_the_skill() {
  assert_file_has "$ROOT/commands/p.md" "promptify"
  assert_file_has "$ROOT/commands/p.md" '$ARGUMENTS'
}

test_command_stays_thin() {
  assert_max_lines "$ROOT/commands/p.md" 20
}
