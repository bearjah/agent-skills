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
