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
