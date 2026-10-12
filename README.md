# Locize translate action

AI-translate your [i18next](https://www.i18next.com) files in CI with [Locize](https://www.locize.com?from=github_action__readme). On every push it extracts your changed reference keys, syncs them to Locize, triggers AI auto-translation, and pulls the results back — delivered over the Locize CDN so translation fixes go live without redeploying your app.

It is a thin wrapper around [`i18next-cli localize --ci`](https://github.com/i18next/i18next-cli#localize). The CI flow is **detect → extract → sync `--auto-translate` → download**. Instrumentation (rewriting your source to add `t()` calls) is skipped in CI — this action never touches your source files.

## What it does (and doesn't)

- ✅ Extracts new/changed keys from your code and syncs them to Locize.
- ✅ Triggers AI/MT auto-translation of the new keys (auto-translation is on by default for new Locize projects).
- ✅ Downloads the translations into your locale files.
- ❌ Does **not** rewrite your source code (no instrumentation in CI).
- ❌ Does **not** commit or open a PR — pair it with a commit/PR step (see [Committing the results](#committing-the-results)). Keeping this action single-purpose lets you compose it with whatever git workflow you already use.

> **Starting from hardcoded strings?** The one-time instrumentation (wrapping strings in `t()` calls) happens locally, not in CI: run `npx i18next-cli localize` interactively, or, if you work with an AI coding agent (Claude Code, Cursor, ...), have it follow the runbook printed by `npx i18next-cli localize --print-agent-prompt` and review the diff like any PR. From then on, this action keeps every push translated, and the results land in Locize's [trust layer](#the-upgrade-the-trust-layer) (Quality Estimation, review workflow, provenance) instead of going into your repo unreviewed.

## Honest about "free"

A brand-new **free** Locize project can auto-translate a **limited starter amount** out of the box — enough to see it work end to end on a small app. For **continuous** translation you either:

- **subscribe** to a paid plan (which also unlocks the trust layer below), or
- **bring your own AI/MT key** (OpenAI, Gemini, Mistral, DeepL, Lara) on a plan that supports it.

This action does not give you unlimited free translation, and it doesn't pretend to. What it gives you for free is a working CI pipeline + the managed delivery layer, with a clear upgrade path when translation volume and review actually matter.

## Prerequisites (one-time, manual)

1. **Create a Locize project** — sign up at [locize.app/register](https://www.locize.app/register?from=github_action__readme). Project creation is a manual step; there is no headless "create project" in CI.
2. **Have an `i18next.config.{ts,js}`** in your repo. If you don't yet, run `npx i18next-cli init` (or the full local `npx i18next-cli localize`) once and commit the config. Your target languages from that config are created automatically on the first sync.
3. **Add two repository secrets:**
   - `LOCIZE_PROJECTID` — your Locize project id
   - `LOCIZE_API_KEY` — any write-capable Locize API key

## Quick start

```yaml
name: Translate
on:
  push:
    branches: [main]

jobs:
  translate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: locize/translate@v2
        with:
          project-id: ${{ secrets.LOCIZE_PROJECTID }}
          api-key: ${{ secrets.LOCIZE_API_KEY }}
```

### Committing the results

This action writes translated files but leaves git to you. Pair it with a commit (or PR) step:

```yaml
      - uses: locize/translate@v2
        with:
          project-id: ${{ secrets.LOCIZE_PROJECTID }}
          api-key: ${{ secrets.LOCIZE_API_KEY }}

      # Option A — commit the updated translations back to the branch
      # (the workflow needs `permissions: contents: write`)
      - uses: stefanzweifel/git-auto-commit-action@v7
        with:
          commit_message: 'chore(i18n): update translations'

      # Option B — open a pull request instead
      # - uses: peter-evans/create-pull-request@v7
      #   with:
      #     commit-message: 'chore(i18n): update translations'
      #     title: 'Update translations'
      #     branch: i18n/update-translations
```

> **Heads-up — AI translation is asynchronous.** Auto-translation runs on the locize side after the sync. With `--ci` the action does a single download and does not wait, so a freshly added key may still be empty in the same run; the next push (or run) picks it up. If you serve translations through [i18next-locize-backend](https://github.com/locize/i18next-locize-backend), the CDN delivers them live regardless of when you commit the files.

### Translating just a pull request's diff

On `pull_request` events, `command: sync` defaults to **changed-only mode**: your source-language files are diffed against the merge-base with the PR's base branch, and only the keys the PR added or modified are synced and AI-translated — not the whole project. Keys are scoped per namespace file, plural families travel together, and nothing is deleted.

The only requirement: the base branch must be available in the checkout, so set `fetch-depth: 0` (the `actions/checkout` default of `1` contains only the checked-out commit, and the action fails with a clear message telling you so).

```yaml
name: Translate PR
on:
  pull_request:

permissions:
  contents: write

jobs:
  translate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          ref: ${{ github.head_ref }}
          fetch-depth: 0
      - uses: locize/translate@v2
        with:
          command: sync
          project-id: ${{ secrets.LOCIZE_PROJECTID }}
          api-key: ${{ secrets.LOCIZE_API_KEY }}
      - uses: stefanzweifel/git-auto-commit-action@v7
        with:
          commit_message: 'chore(i18n): translate PR changes'
```

On `pull_request` events the checkout needs `ref: ${{ github.head_ref }}` so the commit lands on the PR branch, and the workflow needs `contents: write`. Pull requests from forks do not receive repository secrets, so this only works for branches in the same repository. A commit pushed with the default `GITHUB_TOKEN` does not start new workflow runs, so CI does not run again on the translation commit.

Set `changed-only: false` to keep full-project syncs on pull requests, or `changed-only: true` to use it outside PR events too (the base branch is then auto-detected: `origin/HEAD`, `main`, `master`). With `command: localize` the option is not yet supported and the full flow runs.

## Choosing what runs (`command`)

The action runs the full flow by default, but you can scope it to match how much of the pipeline your repo already owns:

| `command` | What runs | Use when |
|---|---|---|
| `localize` (default) | detect → extract → sync → auto-translate → download | Your code calls `t()` and you want the action to (re)extract keys, push them, translate, and pull results. Instrumentation is **always skipped in CI**, so already-instrumented code is fully supported — your source is never modified. |
| `sync` | sync → auto-translate → download | Your locale files are **already extracted** (committed in the repo, or produced by an earlier step). The action skips extraction entirely — no source parsing — and just reconciles the existing files with Locize. |

**Already instrumented, only need extract + sync?** That's the default — use the [Quick start](#quick-start) workflow as-is. In CI the instrument step is skipped, your keys are extracted, and they're synced to Locize.

**Already instrumented and extracted, only need the sync?** Set `command: sync` so extraction is skipped too:

```yaml
      - uses: locize/translate@v2
        with:
          command: sync
          project-id: ${{ secrets.LOCIZE_PROJECTID }}
          api-key: ${{ secrets.LOCIZE_API_KEY }}
```

## How it compares

Free CI translators like lingo.dev's Action and ai-i18n are a good fit when you want translation to run entirely in your pipeline on your own LLM key. They are free at volume because *you* pay the LLM bill. Here's the honest difference:

| | This action (locize) | lingo.dev Action / ai-i18n |
|---|---|---|
| Free at volume | Free **starter amount**; then subscribe or bring your own key | Free at volume on **your own LLM key** |
| Who pays the translation bill | locize (starter) → you (subscription or your key) | You (your LLM key) |
| Managed CDN delivery | ✅ Update translations without redeploying | ❌ Commit-and-redeploy |
| i18next-native depth | ✅ Plurals/context/namespaces, 16+ formats | Varies |
| Trust layer | ✅ See below | ❌ Raw MT output |

If raw MT in your repo is all you need, those tools are fine — use them. The reason to come (or stay) here is the layer **on top** of the translation.

## The upgrade: the trust layer

When translations stop being throwaway and start needing to be *trusted*, the paid layer is the product:

- **[Quality Estimation](https://www.locize.com/docs/quality-estimation?from=github_action__readme)** — confidence scores on AI translations, shown in the editor, so you know which strings to look at.
- **[Review workflow](https://www.locize.com/docs/review-workflow?from=github_action__readme)** — route low-confidence AI translations to a human instead of accepting them blind.
- **[EU AI Act / review-provenance export](https://www.locize.com/docs/eu-ai-act-article-50?from=github_action__readme)** — an auditor-shaped record of who reviewed what, when, and at what confidence.

"Free CI translation in → governed trust layer up" — that's the path this action puts you on.

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `project-id` | ✅ | — | locize project id (use `${{ secrets.LOCIZE_PROJECTID }}`). |
| `api-key` | ✅ | — | Write-capable locize API key (use `${{ secrets.LOCIZE_API_KEY }}`). |
| `command` | | `localize` | Flow to run: `localize` (full: extract → sync → translate → download) or `sync` (sync → translate → download, for already-extracted repos). See [Choosing what runs](#choosing-what-runs-command). |
| `working-directory` | | `.` | Directory containing your `i18next.config.{ts,js}`. |
| `config` | | — | Explicit config file path, overriding auto-detection. |
| `cdn-type` | | `standard` | locize CDN endpoint: `standard` or `pro`. |
| `update-values` | | `false` | Also update existing translation values on locize, not only add new keys. |
| `changed-only` | | auto | Only sync and AI-translate the keys changed on this branch vs. the base branch (`command: sync` only). Auto: `true` on `pull_request` events, `false` otherwise. Needs `actions/checkout` with `fetch-depth: 0`. See [Translating just a pull request's diff](#translating-just-a-pull-requests-diff). |
| `skip-translate` | | `false` | Sync keys but do not request AI auto-translation. |
| `dry-run` | | `false` | Preview every step without writing or pushing anything. |
| `cli-version` | | `1` | `i18next-cli` major version/dist-tag to install. Defaults to `1` (all v1.x fixes, no breaking-major surprise); set to `latest` for the newest release. |
| `node-version` | | `24` | Node.js version (`i18next-cli` requires >=22). |

## Notes

- **Idempotent and safe to re-run.** Already-synced keys are not re-created; syncing never overwrites translations edited remotely unless you pass `update-values: true`.
- **Reference-language driven.** Auto-translation fires when the reference language gains keys; target languages are filled from it.
- **Credentials.** Provide `project-id` / `api-key` via `with:` (as above) or via environment variables — both `LOCIZE_PROJECTID` and `LOCIZE_PROJECT_ID` (and `LOCIZE_API_KEY` / `LOCIZE_APIKEY`) are accepted. The api-key is masked in logs by GitHub Actions; never expose it in client-side code — the CDN only needs the project id.

## Upgrading from v1

`v2` has one behavioral change: on `pull_request` events, `command: sync` now defaults to [changed-only mode](#translating-just-a-pull-requests-diff), so only the PR's diff is synced and AI-translated. If your PR workflow uses `command: sync`, either add `fetch-depth: 0` to your checkout step (recommended) or set `changed-only: false` to keep the previous full-project behavior. Everything else is unchanged, and `v1` keeps working as-is.

## License

[MIT](./LICENSE)
