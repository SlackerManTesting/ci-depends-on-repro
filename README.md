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