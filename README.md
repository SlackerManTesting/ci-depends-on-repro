# ci-depends-on-repro

Security-research testbed, operator-owned. Reproduces the CI behavior of a `Depends-On:` pull-request-body
dependency directive on the operator's OWN GitHub account.

What is modeled (commit-for-commit with a third-party project's configuration at commit `227561fe`, Apache-2.0):

- `script/git-tool` — verbatim copy of the upstream `script/git-tool` (its original Apache-2.0 header is
  retained). Its `apply_dependencies` function honors any `Depends-On: <org>/<repo>#<N>` line in the `PR_BODY`
  environment variable by fetching `refs/pull/N/merge` from the target repository into the freshly cloned
  dependency tree.
- `.github/workflows/ci.yml` — `pull_request`/`push` consumer that exports `PR_BODY`, runs the consumer script,
  and uploads the generated `report_pr` artifact.
- `script/run-consumer` — mirrors the report-generation ordering of the modeled project's size-check script:
  report header FIRST, then the dependency fetch via `script/git-tool`, then EXECUTION of whatever the pulled
  dependency tree ships (`script/execute.sh` when present), then the report tail.
- `.github/workflows/report.yml` — a `workflow_run` sink with `pull-requests: write` that downloads the
  `report_pr` artifact from the consumer run and posts its bytes verbatim as a `github-actions[bot]` comment on
  the pull request (creating, or silently replacing when the comment starts with the magic header).

All content uses a fictional **ACME-CI** brand. This testbed never contacts any third-party repository; its base
and sibling repositories belong to the operator's own account.

## Try the attack

**One comment.** Open the issue **"Try the attack"** in this repository and comment:

```
/attack
```

The `Attack Trigger` workflow (`.github/workflows/attack.yml`) then does the whole chain and posts the evidence
back into that issue thread:

1. it opens a pull request in this repository whose **description** (not its code) carries
   `Depends-On: SlackerManTesting/ci-depends-on-sib#1`;
2. the `CI Consumer` workflow pulls `refs/pull/1/merge` from the *sibling* repository and executes what that
   pull request contains;
3. the pulled code writes into the build's `report_pr` artifact, between the legitimate header and tail;
4. the `Size Report` sink posts those bytes verbatim as `github-actions[bot]` on the pull request thread;
5. a second run shows the same comment id being rewritten in place (`created_at` unchanged, `updated_at` moved);
6. the trigger closes the pull request and deletes the branch.

The trigger only ever touches this repository and reads the public sibling repository. It requires the
`ATTACK_TOKEN` repository secret (a fine-grained PAT scoped to this repository only) because a pull request
opened with the repository's own `GITHUB_TOKEN` does not trigger `pull_request` workflows.

**Without a GitHub account** — replay the same chain locally, offline, in a few seconds:

```bash
bash repro.sh
```

It builds a scratch sibling repository with a `refs/pull/42/merge` ref, exports a `PR_BODY` containing the
directive, runs this repository's `script/git-tool` against it, and prints the `git pull` line, the content that
landed in the workspace, the execution of the pulled script, and the negative control (no directive → no pull).

## Same effect as the real project's CI

The two parts that decide the outcome are upstream files, not re-implementations:

| Part | This testbed | Upstream `openthread/openthread` @ `227561fe` |
|---|---|---|
| directive → pull | `script/git-tool` | `script/git-tool` — **byte-identical** (sha256 `BF5EA41A8960EB637863394A18C61574530F093F101E4B992A7C8D5040AA81A0`) |
| publish as the CI bot | `.github/workflows/report.yml` | `.github/workflows/size-report.yml` — same file with three cosmetic deltas: job name, `workflows: ["CI Consumer"]` instead of `["Size Check"]`, and the report title `**ACME-CI**` instead of `**OpenThread**`; the logic (`download-artifact` by run id → post the raw bytes → magic-header match → `updateComment`, else `createComment`) is upstream's, line for line |
| consumer job | `ci.yml` + `script/run-consumer` | `size-check.yml` + `script/check-size` — the upstream script builds `nrf52840` with the Arm GCC 7 toolchain, which is too heavy for a public demo, so the testbed reproduces its **ordering** exactly (report header → dependency fetch → execution of the pulled tree → report tail) with a three-line stand-in for the build step |
