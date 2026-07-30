/**
 * @process acceptance-gated-implementation
 * @description Acceptance-gated implementation: approved criteria -> worktree -> acceptance tests RED -> implement -> GREEN -> tamper check -> approve
 * @inputs { feature: string, specPath: string, planPath: string, validationPlanPath: string, branchName: string, repoRoot: string, worktreeDir?: string, criteria: array, commands: object, acceptancePaths: array, maxRepairAttempts?: number }
 * @outputs { approved: boolean, verdicts: array, baseline: object, redEvidence: object, greenEvidence: object, tamperClean: boolean, worktreePath: string }
 * @graph
 *   domains: [domain:software-engineering]
 *   skillAreas: [skill-area:e2e-testing, skill-area:orchestration-loop]
 *   workflows: [workflow:feature-development]
 *   topics: [topic:test-driven-development, topic:acceptance-testing]
 *   roles: [role:tech-lead, role:qa-engineer, role:backend-engineer]
 *
 * ADAPTED for claude-dispatch. Concrete criteria, paths, and commands are baked
 * into DEFAULTS at the bottom of this file; `inputs` may override any of them.
 *
 * Approved criteria source: ~/docs/validation/2026-07-27-task-dispatch-tool-validation.md
 *
 * Two conventions this file relies on, both load-bearing:
 *
 * 1. Every pass/fail decision is a shell exit code. `nonInteractive` runs
 *    (babysitter:yolo, -p mode) auto-approve breakpoints, so the shell gates are
 *    the only enforcement that survives. Never convert a shell gate into an agent
 *    judgement call. See library/reference/SHELL_VS_AGENT_VERIFICATION.md.
 * 2. Shell tasks emit their result as a single JSON object on the LAST LINE of
 *    stdout; human-readable output goes to stderr or a log file. `outputSchema`
 *    validates the posted value before it is committed.
 */

import { defineTask } from '@a5c-ai/babysitter-sdk';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Escapes a string for safe inclusion inside a single-quoted shell argument. */
const sq = (s) => String(s).replace(/'/g, "'\\''");

/** Renders paths as a space-separated list of single-quoted shell arguments. */
const sqList = (paths) => paths.map((p) => `'${sq(p)}'`).join(' ');

/** Signatures meaning an acceptance test is broken rather than legitimately RED. */
const HARNESS_ERROR_SIGNATURES = [
  'ModuleNotFoundError',
  'ImportError',
  'SyntaxError',
  'Cannot find module',
  'error collecting',
  'errors during collection',
  'fixture .* not found',
  'no tests ran',
  'No test files found',
].join('|');

const DEFAULT_TIMEOUT_MS = 900000;

// ---------------------------------------------------------------------------
// Phase 0 — baseline capture (never fails the run; a red baseline is data)
// ---------------------------------------------------------------------------

const captureBaselineTask = defineTask(
  'acceptance-gate/capture-baseline',
  (args) => ({
    kind: 'shell',
    title: 'Capture baseline test results on the base commit',
    shell: {
      command: [
        `cd '${sq(args.cwd)}'`,
        `mkdir -p '${sq(args.artifactsDir)}'`,
        `log='${sq(args.artifactsDir)}/baseline-full-suite.log'`,
        `baseSha=$(git rev-parse HEAD)`,
        `( ${args.fullSuiteCommand} ) > "$log" 2>&1; code=$?`,
        // Always exit 0: a red baseline must be recorded, not fatal.
        `jq -nc --arg sha "$baseSha" --arg log "$log" --argjson code "$code" \\`,
        `  '{baseSha:$sha, logPath:$log, exitCode:$code, green:($code==0)}'`,
        `exit 0`,
      ].join('\n'),
      expectedExitCode: 0,
      timeout: args.timeout ?? DEFAULT_TIMEOUT_MS,
    },
    outputSchema: {
      type: 'object',
      required: ['baseSha', 'logPath', 'exitCode', 'green'],
      properties: {
        baseSha: { type: 'string' },
        logPath: { type: 'string' },
        exitCode: { type: 'number' },
        green: { type: 'boolean' },
      },
    },
    labels: ['acceptance-gate', 'baseline'],
  })
);

// ---------------------------------------------------------------------------
// Phase 2 — isolated worktree
// ---------------------------------------------------------------------------

const setupWorktreeTask = defineTask(
  'acceptance-gate/setup-worktree',
  (args) => ({
    kind: 'shell',
    title: `Create worktree on branch ${args.branchName}`,
    shell: {
      command: [
        `set -e`,
        `cd '${sq(args.repoRoot)}'`,
        // Fail closed rather than silently committing a .gitignore change.
        `git check-ignore -q '${sq(args.worktreeDir)}' || {`,
        `  echo "ABORT: '${sq(args.worktreeDir)}' is not gitignored - add it and commit first" >&2`,
        `  exit 1`,
        `}`,
        `git worktree add '${sq(args.worktreePath)}' -b '${sq(args.branchName)}' >&2`,
        `cd '${sq(args.worktreePath)}'`,
        args.installCommand ? `( ${args.installCommand} ) >&2` : `true`,
        `head=$(git rev-parse HEAD)`,
        `jq -nc --arg path '${sq(args.worktreePath)}' --arg branch '${sq(args.branchName)}' --arg head "$head" \\`,
        `  '{worktreePath:$path, branch:$branch, headSha:$head}'`,
      ].join('\n'),
      expectedExitCode: 0,
      timeout: args.timeout ?? DEFAULT_TIMEOUT_MS,
    },
    outputSchema: {
      type: 'object',
      required: ['worktreePath', 'branch', 'headSha'],
      properties: {
        worktreePath: { type: 'string' },
        branch: { type: 'string' },
        headSha: { type: 'string' },
      },
    },
    labels: ['acceptance-gate', 'worktree', 'isolation'],
  })
);

// ---------------------------------------------------------------------------
// Phase 3 — author the acceptance tests (agent), then freeze their SHA (shell)
// ---------------------------------------------------------------------------

const authorAcceptanceTestsTask = defineTask(
  'acceptance-gate/author-acceptance-tests',
  (args) => ({
    kind: 'agent',
    title: 'Author end-to-end acceptance tests from the approved validation plan',
    agent: {
      prompt: [
        `Write executable end-to-end acceptance tests in the worktree at ${args.worktreePath}.`,
        ``,
        `Source of truth: ${args.validationPlanPath} (approved). Spec: ${args.specPath}.`,
        `Write the test files at: ${args.acceptancePaths.join(', ')}`,
        ``,
        `One test per acceptance criterion, named so the criterion ID is visible:`,
        args.criteria.map((c) => `  ${c.id}: ${c.outcome}  (observe via: ${c.command})`).join('\n'),
        ``,
        `Rules:`,
        `- Drive the system only through public interfaces (HTTP, CLI, exported API, UI).`,
        `- Never mock anything under test. Third-party calls may be stubbed at the`,
        `  process boundary only; list every stub in your report.`,
        `- Start real processes. No sleep-based synchronization - poll for the condition.`,
        `- Each test sets up and tears down its own fixtures and can run alone.`,
        `- Assert the exact observable outcome from the criterion, not an internal call.`,
        `- Do NOT write or modify any implementation code. Tests only.`,
        ``,
        `SELF-CONTAINMENT IS MANDATORY. At the moment these tests first run, NOTHING`,
        `from the implementation plan exists - including test/helpers.sh. Sourcing it`,
        `would fail with "No such file", which is a broken harness, not a RED test.`,
        `test/acceptance/ must carry its own runner, assertions, and fixtures and`,
        `share nothing with the unit suite. Invoke bin/dispatch-task.sh only as a`,
        `subprocess; never source lib/*.sh.`,
        ``,
        `TMUX ISOLATION: create a private tmux server per run on socket`,
        `"dispatch-acc-$$" via 'tmux -L "$SOCK" new-session -d', synthesize TMUX from`,
        `'tmux -L "$SOCK" display-message -p "#{socket_path},#{pid},0"', and export it`,
        `to the entrypoint. Never touch the caller's live tmux session. Kill the`,
        `server in teardown. Override HOME to a temp dir for the install cases.`,
        `Poll for .dispatch-argv on a bounded loop; never sleep-synchronize.`,
        ``,
        `These tests MUST fail right now, because the feature does not exist yet. They`,
        `must fail on their assertion, not on an import error or collection error - run`,
        `them and confirm the failure reason before you finish.`,
        ``,
        `Commit the test files with message: "test: acceptance criteria for ${args.feature}"`,
        `Report: files written, criterion->test mapping, every stub, and the observed`,
        `failure reason per test.`,
      ].join('\n'),
    },
    io: {
      inputs: { validationPlanPath: 'string', criteria: 'array', worktreePath: 'string' },
      outputs: {
        filesWritten: 'array',
        criterionToTest: 'object',
        stubs: 'array',
        failureReasons: 'object',
      },
    },
    labels: ['acceptance-gate', 'atdd', 'test-authoring'],
  })
);

const freezeAcceptanceShaTask = defineTask(
  'acceptance-gate/freeze-acceptance-sha',
  (args) => ({
    kind: 'shell',
    title: 'Record the commit SHA that freezes the acceptance tests',
    shell: {
      command: [
        `set -e`,
        `cd '${sq(args.worktreePath)}'`,
        // An uncommitted test is not a frozen gate.
        `if [ -n "$(git status --porcelain -- ${sqList(args.acceptancePaths)})" ]; then`,
        `  echo "ABORT: acceptance tests are not committed" >&2`,
        `  exit 1`,
        `fi`,
        `for p in ${sqList(args.acceptancePaths)}; do`,
        `  git ls-files --error-unmatch "$p" >/dev/null 2>&1 || {`,
        `    echo "ABORT: $p is not tracked - no acceptance tests were written there" >&2`,
        `    exit 1`,
        `  }`,
        `done`,
        `sha=$(git rev-parse HEAD)`,
        `jq -nc --arg sha "$sha" '{acceptanceSha:$sha}'`,
      ].join('\n'),
      expectedExitCode: 0,
    },
    outputSchema: {
      type: 'object',
      required: ['acceptanceSha'],
      properties: { acceptanceSha: { type: 'string' } },
    },
    labels: ['acceptance-gate', 'freeze'],
  })
);

// ---------------------------------------------------------------------------
// Phase 4 — RED verification (hard gate)
// ---------------------------------------------------------------------------

const verifyRedTask = defineTask(
  'acceptance-gate/verify-red',
  (args) => ({
    kind: 'shell',
    title: 'Verify acceptance tests fail, and fail for the right reason',
    shell: {
      command: [
        `cd '${sq(args.worktreePath)}'`,
        `mkdir -p '${sq(args.artifactsDir)}'`,
        `log='${sq(args.artifactsDir)}/red.log'`,
        `( ${args.acceptanceCommand} ) > "$log" 2>&1; code=$?`,
        `if [ "$code" -eq 0 ]; then`,
        `  echo "NOT RED: acceptance suite passed before any implementation exists." >&2`,
        `  echo "Either the criterion is already satisfied (drop it and disclose at GATE 2)" >&2`,
        `  echo "or the assertion is vacuous (fix the test). See $log" >&2`,
        `  exit 1`,
        `fi`,
        `if grep -qiE '${sq(HARNESS_ERROR_SIGNATURES)}' "$log"; then`,
        `  echo "NOT RED: harness error, not a missing-capability failure. See $log" >&2`,
        `  grep -iE '${sq(HARNESS_ERROR_SIGNATURES)}' "$log" >&2`,
        `  exit 1`,
        `fi`,
        `jq -nc --arg log "$log" --argjson code "$code" '{red:true, exitCode:$code, logPath:$log}'`,
      ].join('\n'),
      expectedExitCode: 0,
      timeout: args.timeout ?? DEFAULT_TIMEOUT_MS,
    },
    outputSchema: {
      type: 'object',
      required: ['red', 'exitCode', 'logPath'],
      properties: {
        red: { type: 'boolean' },
        exitCode: { type: 'number' },
        logPath: { type: 'string' },
      },
    },
    labels: ['acceptance-gate', 'red', 'hard-gate'],
  })
);

// ---------------------------------------------------------------------------
// Phase 5 — implementation, in the worktree, gate frozen
// ---------------------------------------------------------------------------

const implementPlanTask = defineTask(
  'acceptance-gate/implement-plan',
  (args) => ({
    kind: 'agent',
    title:
      args.attempt > 1
        ? `Repair implementation (attempt ${args.attempt})`
        : 'Implement the approved plan in the worktree',
    agent: {
      prompt: [
        args.attempt > 1
          ? `The acceptance suite is still failing. Fix the implementation.\n\nFailures:\n${args.failureSummary}`
          : `Implement the approved plan at ${args.planPath}, in the worktree at ${args.worktreePath}.`,
        ``,
        `Use superpowers:subagent-driven-development: one fresh subagent per plan task,`,
        `inner TDD loop per task, commit per task.`,
        ``,
        `START AT TASK 1 STEP 2. Task 1 Step 1 (git init, create .gitignore) is already`,
        `done at the base commit - the gate needed a base to branch from. Do not re-run`,
        `git init and do not rewrite .gitignore; it is already correct, including the`,
        `".worktrees" entry deliberately written WITHOUT a trailing slash.`,
        ``,
        `Plan Task 8 Step 3 contains a conditional fix for $HERE resolving through the`,
        `install symlink. Actually test it through the symlink and pick the branch that`,
        `works; do not assume.`,
        ``,
        `THE GATE IS FROZEN. The files under ${args.acceptancePaths.join(', ')} define the`,
        `gate you are being measured against. Do not edit, skip, xfail, delete, or`,
        `otherwise weaken them, and do not add configuration that excludes them from a`,
        `run. If you believe a criterion is wrong or unimplementable, STOP and report it`,
        `- it will be escalated to your human partner. Do not adjust it yourself.`,
        ``,
        `A later check diffs those files against ${args.acceptanceSha}. Any change halts`,
        `the run.`,
        ``,
        `Report: tasks completed, files changed, per-task test results, and anything you`,
        `could not implement, with the reason.`,
      ].join('\n'),
    },
    io: {
      inputs: { planPath: 'string', worktreePath: 'string', attempt: 'number' },
      outputs: {
        tasksCompleted: 'array',
        filesChanged: 'array',
        blocked: 'array',
        committed: 'boolean',
      },
    },
    labels: ['acceptance-gate', 'implementation'],
  })
);

// ---------------------------------------------------------------------------
// Phase 6 — GREEN validation
// ---------------------------------------------------------------------------

const verifyGreenTask = defineTask(
  'acceptance-gate/verify-green',
  (args) => ({
    kind: 'shell',
    title: 'Run acceptance suite and full suite in the worktree',
    shell: {
      command: [
        `cd '${sq(args.worktreePath)}'`,
        `mkdir -p '${sq(args.artifactsDir)}'`,
        `acc='${sq(args.artifactsDir)}/green-acceptance.log'`,
        `full='${sq(args.artifactsDir)}/green-full-suite.log'`,
        `( ${args.acceptanceCommand} ) > "$acc" 2>&1; accCode=$?`,
        `( ${args.fullSuiteCommand} ) > "$full" 2>&1; fullCode=$?`,
        `jq -nc --arg acc "$acc" --arg full "$full" --argjson a "$accCode" --argjson f "$fullCode" \\`,
        `  '{acceptanceExitCode:$a, fullSuiteExitCode:$f, acceptanceLog:$acc, fullSuiteLog:$full,`,
        `    passed:(($a==0) and ($f==0))}'`,
        // Exit 0 regardless: the process decides whether to repair or escalate.
        `exit 0`,
      ].join('\n'),
      expectedExitCode: 0,
      timeout: args.timeout ?? DEFAULT_TIMEOUT_MS,
    },
    outputSchema: {
      type: 'object',
      required: ['acceptanceExitCode', 'fullSuiteExitCode', 'passed'],
      properties: {
        acceptanceExitCode: { type: 'number' },
        fullSuiteExitCode: { type: 'number' },
        acceptanceLog: { type: 'string' },
        fullSuiteLog: { type: 'string' },
        passed: { type: 'boolean' },
      },
    },
    labels: ['acceptance-gate', 'green'],
  })
);

// ---------------------------------------------------------------------------
// Phase 7 — tamper check (hard gate) + evidence report
// ---------------------------------------------------------------------------

const tamperCheckTask = defineTask(
  'acceptance-gate/tamper-check',
  (args) => ({
    kind: 'shell',
    title: 'Verify the acceptance tests were not modified during implementation',
    shell: {
      command: [
        `cd '${sq(args.worktreePath)}'`,
        `mkdir -p '${sq(args.artifactsDir)}'`,
        `if git diff --quiet '${sq(args.acceptanceSha)}'..HEAD -- ${sqList(args.acceptancePaths)}; then`,
        `  jq -nc '{tamperClean:true}'`,
        `  exit 0`,
        `fi`,
        `diff='${sq(args.artifactsDir)}/acceptance-test-tamper.diff'`,
        `git diff '${sq(args.acceptanceSha)}'..HEAD -- ${sqList(args.acceptancePaths)} > "$diff"`,
        `echo "TAMPER: acceptance tests changed after being frozen. See $diff" >&2`,
        `exit 1`,
      ].join('\n'),
      expectedExitCode: 0,
    },
    outputSchema: {
      type: 'object',
      required: ['tamperClean'],
      properties: { tamperClean: { type: 'boolean' } },
    },
    labels: ['acceptance-gate', 'tamper-check', 'hard-gate'],
  })
);

const buildEvidenceReportTask = defineTask(
  'acceptance-gate/build-evidence-report',
  (args) => ({
    kind: 'agent',
    title: 'Build the validation evidence report',
    agent: {
      prompt: [
        `Write the validation evidence report to ${args.reportPath}.`,
        ``,
        `Inputs:`,
        `- Approved validation plan: ${args.validationPlanPath}`,
        `- Baseline (pre-implementation): ${args.baselineLogPath}`,
        `- RED evidence: ${args.redLogPath}`,
        `- GREEN acceptance: ${args.greenAcceptanceLogPath}`,
        `- GREEN full suite: ${args.greenFullSuiteLogPath}`,
        ``,
        `One row per acceptance criterion: ID, observing command, VERBATIM output`,
        `excerpt, verdict (PASS/FAIL). Quote the output - do not paraphrase it.`,
        ``,
        `Then:`,
        `- Baseline-vs-final comparison. A failure present in the baseline is NOT`,
        `  attributed to this implementation; list those separately as pre-existing.`,
        `- Tamper check result: ${args.tamperClean ? 'CLEAN' : 'TAMPERED'}`,
        `- Every criterion dropped or changed after GATE 1, and where it was approved.`,
        `- Every stub used, as a stated limitation of the validation.`,
        ``,
        `State the verdict plainly. If any criterion failed, say so first - do not bury`,
        `it under what passed.`,
      ].join('\n'),
    },
    io: {
      inputs: { criteria: 'array', reportPath: 'string' },
      outputs: {
        reportPath: 'string',
        verdicts: 'array',
        allPassed: 'boolean',
        preExisting: 'array',
      },
    },
    labels: ['acceptance-gate', 'evidence', 'reporting'],
  })
);

// ---------------------------------------------------------------------------
// MAIN PROCESS
// ---------------------------------------------------------------------------

const DOCS = '/home/berjah/docs';

/**
 * One row per acceptance criterion in the approved validation plan §1.
 * `command` is the observing command; the acceptance runner takes a case name.
 */
const CRITERIA = [
  { id: 'AC-1',  requirement: 'Errors: $TMUX unset is a hard fail',                      outcome: 'Exit non-zero, stderr contains "not inside a tmux session", no worktree created',                        command: './test/acceptance/run-acceptance.sh ac_01_requires_tmux' },
  { id: 'AC-2',  requirement: 'Errors: missing brief is a hard fail',                    outcome: 'Exit non-zero, stderr contains "brief not found", no worktree created',                                  command: './test/acceptance/run-acceptance.sh ac_02_requires_brief' },
  { id: 'AC-3',  requirement: 'Repo names resolve; unknown/ambiguous errors with candidates', outcome: 'Unknown -> "no repo named"; two matches -> "ambiguous" plus both paths; neither creates a worktree', command: './test/acceptance/run-acceptance.sh ac_03_repo_resolution' },
  { id: 'AC-4',  requirement: 'Errors: existing worktree path or branch is a hard fail', outcome: 'Exit non-zero, stderr "already exists", pre-existing directory untouched',                               command: './test/acceptance/run-acceptance.sh ac_04_rejects_existing_worktree_or_branch' },
  { id: 'AC-5',  requirement: 'cwd is the primary repo worktree',                        outcome: 'Stub writes .dispatch-argv into <parent>/<primary>-wt-<slug> and nowhere else',                          command: './test/acceptance/run-acceptance.sh ac_05_primary_is_cwd' },
  { id: 'AC-6',  requirement: 'Targets get sibling worktrees on shared dispatch/<slug>', outcome: 'Both <repo>-wt-<slug> exist; branch --show-current is dispatch/<slug> in each',                           command: './test/acceptance/run-acceptance.sh ac_06_targets_get_sibling_worktrees' },
  { id: 'AC-7',  requirement: 'Reference repos are read-only, get no worktree',          outcome: 'No <ref>-wt-<slug> exists; ref repo branch and working tree unchanged',                                  command: './test/acceptance/run-acceptance.sh ac_07_refs_get_no_worktree' },
  { id: 'AC-8',  requirement: 'Siblings reached via --add-dir',                          outcome: 'Recorded argv contains secondary worktree path and ref checkout path, both after --add-dir',           command: './test/acceptance/run-acceptance.sh ac_08_add_dir_contents' },
  { id: 'AC-9',  requirement: 'Argv order: prompt first, variadic --add-dir last',       outcome: 'Prompt is argv[0]; --session-id + 36-char uuid follow; --add-dir appears after both',                   command: './test/acceptance/run-acceptance.sh ac_09_argv_order' },
  { id: 'AC-10', requirement: 'Entry skill by task kind, default brainstorming',         outcome: 'Prompt starts "/superpowers:brainstorming " and names the brief; --skill overrides the prefix',      command: './test/acceptance/run-acceptance.sh ac_10_prompt_skill_and_brief' },
  { id: 'AC-11', requirement: 'One dispatch produces exactly one session',               outcome: 'Window count increases by exactly 1; new window named <primary>-<slug>',                                 command: './test/acceptance/run-acceptance.sh ac_11_single_window_named' },
  { id: 'AC-12', requirement: 'Report names window, worktrees, session id, transcript, cleanup', outcome: 'stdout contains window name, every worktree path, the same uuid, a .jsonl transcript path, and --cleanup <slug>', command: './test/acceptance/run-acceptance.sh ac_12_report_fields' },
  { id: 'AC-13', requirement: 'Base ref auto-detected per repo; --base overrides',       outcome: 'origin/HEAD -> origin/main; only origin/master -> master; --base honoured; no remote + no --base -> error naming --base', command: './test/acceptance/run-acceptance.sh ac_13_base_ref_resolution' },
  { id: 'AC-14', requirement: 'Cleanup removes worktrees and the dispatch branch',       outcome: 'Exit 0, directory gone, dispatch/<slug> absent from git branch',                                        command: './test/acceptance/run-acceptance.sh ac_14_cleanup_removes' },
  { id: 'AC-15', requirement: 'Cleanup refuses a dirty worktree unless forced',          outcome: 'Non-zero + "uncommitted changes" + directory present; --force -> exit 0 and gone',                       command: './test/acceptance/run-acceptance.sh ac_15_cleanup_refuses_dirty' },
  { id: 'AC-16', requirement: 'Cleanup refuses unmerged commits unless forced',          outcome: 'Non-zero, stderr contains "not in origin/main", directory still present',                                command: './test/acceptance/run-acceptance.sh ac_16_cleanup_refuses_unmerged' },
  { id: 'AC-17', requirement: 'Installer exposes the tool at documented paths',          outcome: 'Both symlinks created under a temp HOME; --help through the symlink exits 0; dispatch.md declares allowed-tools', command: './test/acceptance/run-acceptance.sh ac_17_install_symlinks_work' },
  { id: 'AC-18', requirement: 'REGRESSION GUARD: install must not disturb ralph tooling', outcome: 'ralph-new-terminal.sh and ralph-terminal.md byte-identical after install; ralph still prints usage and exits non-zero with no args', command: './test/acceptance/run-acceptance.sh ac_18_install_preserves_ralph' },
];

const DEFAULTS = {
  feature: 'task-dispatch-tool',
  specPath: `${DOCS}/designs/2026-07-27-task-dispatch-tool-design.md`,
  planPath: `${DOCS}/designs/2026-07-27-task-dispatch-tool-implementation-plan.md`,
  validationPlanPath: `${DOCS}/validation/2026-07-27-task-dispatch-tool-validation.md`,
  branchName: 'feat/task-dispatch',
  repoRoot: '/home/berjah/code/personal-stuff/claude-dispatch',
  worktreeDir: '.worktrees',
  acceptancePaths: ['test/acceptance'],
  criteria: CRITERIA,
  commands: {
    fullSuite: './test/run-tests.sh',
    acceptanceSuite: './test/acceptance/run-acceptance.sh',
    // No dependency install step: this is bash with no package manifest.
    install: '',
  },
  maxRepairAttempts: 3,
};

export async function process(inputs, ctx) {
  const merged = { ...DEFAULTS, ...(inputs ?? {}) };
  merged.commands = { ...DEFAULTS.commands, ...((inputs ?? {}).commands ?? {}) };

  const {
    feature,
    specPath,
    planPath,
    validationPlanPath,
    branchName,
    repoRoot,
    worktreeDir = '.worktrees',
    criteria = [],
    commands = {},
    acceptancePaths = [],
    maxRepairAttempts = 3,
  } = merged;

  if (!criteria.length) {
    throw new Error('acceptance-gate: criteria is empty - GATE 1 would have nothing to approve');
  }
  if (!acceptancePaths.length) {
    throw new Error('acceptance-gate: acceptancePaths is empty - nothing to freeze or tamper-check');
  }
  if (!commands.fullSuite || !commands.acceptanceSuite) {
    throw new Error('acceptance-gate: commands.fullSuite and commands.acceptanceSuite are required');
  }

  const worktreePath = `${repoRoot}/${worktreeDir}/${branchName}`;
  const artifactsDir = ctx.artifactsDir;
  const results = { feature, approved: false, worktreePath };

  // -- Phase 0 ---------------------------------------------------------------
  ctx.log?.('Phase 0: baseline capture', { feature, branchName });
  const baseline = await ctx.task(captureBaselineTask, {
    cwd: repoRoot,
    fullSuiteCommand: commands.fullSuite,
    artifactsDir,
  });
  results.baseline = baseline;
  ctx.log?.('Baseline captured', { green: baseline.green, baseSha: baseline.baseSha });

  // -- Phase 1: GATE 1 -------------------------------------------------------
  const gate1 = await ctx.breakpoint(
    {
      title: 'GATE 1 - Acceptance criteria approval',
      question:
        `These ${criteria.length} criteria are what I will accept as proof that "${feature}" ` +
        `does what it was designed to do, and the non-goals list is what I will NOT check. ` +
        `Implementation will be dispatched into a fresh worktree at ${worktreePath} on ` +
        `branch ${branchName}. Approve these criteria, or tell me what to change?`,
      criteria: criteria.map((c) => ({
        id: c.id,
        requirement: c.requirement,
        outcome: c.outcome,
      })),
      baseline: { green: baseline.green, baseSha: baseline.baseSha, logPath: baseline.logPath },
      context: {
        runId: ctx.runId,
        files: [
          {
            path: validationPlanPath,
            format: 'markdown',
            label: 'Validation plan (criteria + non-goals)',
          },
          { path: specPath, format: 'markdown', label: 'Spec' },
          { path: planPath, format: 'markdown', label: 'Implementation plan' },
        ],
      },
    },
    { label: 'gate-1-criteria-approval' }
  );

  if (gate1.approved === false) {
    ctx.halt('GATE 1 rejected - criteria not approved, nothing was dispatched', {
      feedback: gate1.feedback ?? gate1.response,
    });
  }

  // -- Phase 2 ---------------------------------------------------------------
  ctx.log?.('Phase 2: worktree setup');
  results.worktree = await ctx.task(setupWorktreeTask, {
    repoRoot,
    worktreeDir,
    worktreePath,
    branchName,
    installCommand: commands.install,
  });

  // -- Phase 3 ---------------------------------------------------------------
  ctx.log?.('Phase 3: authoring acceptance tests (no implementation yet)');
  results.acceptanceTests = await ctx.task(authorAcceptanceTestsTask, {
    feature,
    specPath,
    validationPlanPath,
    worktreePath,
    acceptancePaths,
    criteria,
  });

  const frozen = await ctx.task(freezeAcceptanceShaTask, { worktreePath, acceptancePaths });
  const acceptanceSha = frozen.acceptanceSha;
  results.acceptanceSha = acceptanceSha;
  ctx.log?.('Acceptance tests frozen', { acceptanceSha });

  // -- Phase 4: RED gate -----------------------------------------------------
  ctx.log?.('Phase 4: RED verification');
  const red = await ctx.task(verifyRedTask, {
    worktreePath,
    acceptanceCommand: commands.acceptanceSuite,
    artifactsDir,
  });
  results.redEvidence = red;
  ctx.log?.('RED verified - tests fail for the right reason. Implementation may now be dispatched.');

  // -- Phases 5 + 6: implement, validate, bounded repair ---------------------
  let green = null;
  let attempt = 0;

  while (attempt < maxRepairAttempts) {
    attempt += 1;
    ctx.log?.(`Phase 5: implementation (attempt ${attempt}/${maxRepairAttempts})`);

    await ctx.task(implementPlanTask, {
      feature,
      planPath,
      worktreePath,
      acceptancePaths,
      acceptanceSha,
      attempt,
      failureSummary: green
        ? `acceptance exit=${green.acceptanceExitCode}, full suite exit=${green.fullSuiteExitCode}. ` +
          `Logs: ${green.acceptanceLog}, ${green.fullSuiteLog}`
        : '',
    });

    ctx.log?.('Phase 6: GREEN validation');
    green = await ctx.task(verifyGreenTask, {
      worktreePath,
      acceptanceCommand: commands.acceptanceSuite,
      fullSuiteCommand: commands.fullSuite,
      artifactsDir,
    });

    if (green.passed) break;

    ctx.log?.('Acceptance suite not green', {
      attempt,
      acceptanceExitCode: green.acceptanceExitCode,
      fullSuiteExitCode: green.fullSuiteExitCode,
    });

    if (attempt >= maxRepairAttempts) {
      // Escalate rather than loop forever or quietly declare success.
      const escalation = await ctx.breakpoint(
        {
          title: 'Acceptance criteria still failing',
          question:
            `After ${attempt} attempts the acceptance suite still fails. The gate has not ` +
            `been touched. Options: keep repairing, revise a criterion (say which and why), ` +
            `or stop and hand back the worktree as-is. How should I proceed?`,
          acceptanceLog: green.acceptanceLog,
          fullSuiteLog: green.fullSuiteLog,
          context: {
            runId: ctx.runId,
            files: [{ path: validationPlanPath, format: 'markdown', label: 'Approved criteria' }],
          },
        },
        { label: 'repair-budget-exhausted' }
      );
      if (escalation.approved === false) {
        ctx.halt('Stopped at partner request with acceptance criteria unmet', {
          worktreePath,
          feedback: escalation.feedback ?? escalation.response,
        });
      }
      attempt = 0; // partner authorized more attempts
    }
  }
  results.greenEvidence = green;

  // -- Phase 7 ---------------------------------------------------------------
  ctx.log?.('Phase 7: tamper check');
  let tamperClean = false;
  try {
    const tamper = await ctx.task(tamperCheckTask, {
      worktreePath,
      acceptanceSha,
      acceptancePaths,
      artifactsDir,
    });
    tamperClean = tamper.tamperClean === true;
  } catch (err) {
    // Fail closed. A gate that moved during implementation carries false authority.
    ctx.halt('TAMPER: acceptance tests were modified after being frozen - result is not trustworthy', {
      acceptanceSha,
      diffPath: `${artifactsDir}/acceptance-test-tamper.diff`,
      error: err?.message,
    });
  }
  results.tamperClean = tamperClean;

  const reportPath = `${artifactsDir}/validation-evidence.md`;
  const report = await ctx.task(buildEvidenceReportTask, {
    criteria,
    reportPath,
    validationPlanPath,
    baselineLogPath: baseline.logPath,
    redLogPath: red.logPath,
    greenAcceptanceLogPath: green.acceptanceLog,
    greenFullSuiteLogPath: green.fullSuiteLog,
    tamperClean,
  });
  results.verdicts = report.verdicts ?? [];
  results.reportPath = report.reportPath ?? reportPath;

  // -- Phase 8: GATE 2 -------------------------------------------------------
  const gate2 = await ctx.breakpoint(
    {
      title: 'GATE 2 - Validation evidence approval',
      question:
        `All ${criteria.length} acceptance criteria were proven RED before implementation and ` +
        `are now GREEN, the full suite shows no failure absent from the baseline, and the ` +
        `acceptance tests are byte-identical to the frozen versions. Approve this as proof ` +
        `that "${feature}" does what it was designed to do?`,
      verdicts: results.verdicts,
      tamperClean,
      worktreePath,
      branchName,
      context: {
        runId: ctx.runId,
        files: [
          { path: results.reportPath, format: 'markdown', label: 'Validation evidence' },
          { path: validationPlanPath, format: 'markdown', label: 'Approved criteria' },
        ],
      },
    },
    { label: 'gate-2-evidence-approval' }
  );

  results.approved = gate2.approved !== false;

  if (!results.approved) {
    ctx.halt('GATE 2 rejected - evidence not accepted', {
      worktreePath,
      feedback: gate2.feedback ?? gate2.response,
    });
  }

  ctx.log?.('Approved. Hand off to superpowers:finishing-a-development-branch.', {
    worktreePath,
    branchName,
  });

  // Branch finishing is deliberately NOT automated: merge/PR/keep is the partner's
  // call, and no PR is opened without an explicit request.
  results.nextStep = 'superpowers:finishing-a-development-branch';
  return results;
}
