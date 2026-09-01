#!/usr/bin/env bash
set -euo pipefail

# Resolve credentials: the 'with:' input first, then environment variables,
# accepting both the canonical (LOCIZE_PROJECTID / LOCIZE_API_KEY) and the
# underscore/concatenated variants so any existing secret naming just works.
PROJECT_ID="${INPUT_PROJECT_ID:-${LOCIZE_PROJECTID:-${LOCIZE_PROJECT_ID:-}}}"
API_KEY="${INPUT_API_KEY:-${LOCIZE_API_KEY:-${LOCIZE_APIKEY:-}}}"

if [ -z "$PROJECT_ID" ] || [ -z "$API_KEY" ]; then
  echo "::error::Missing locize credentials. Pass project-id/api-key via 'with:' or set LOCIZE_PROJECTID + LOCIZE_API_KEY (LOCIZE_PROJECT_ID / LOCIZE_APIKEY also accepted) in the environment." >&2
  exit 1
fi

# i18next-cli reads these environment variables. Passing them via the env
# (not as CLI args) keeps them out of the printed command.
export LOCIZE_PROJECTID="$PROJECT_ID"
export LOCIZE_API_KEY="$API_KEY"

if [ -n "${INPUT_WORKING_DIRECTORY:-}" ]; then
  cd "$INPUT_WORKING_DIRECTORY"
fi

COMMAND_INPUT="${INPUT_COMMAND:-localize}"

# changed-only: unset means "auto" — on on pull_request events, off otherwise.
# Only the sync flow supports it (localize keeps full-project semantics).
CHANGED_ONLY="${INPUT_CHANGED_ONLY:-}"
if [ -z "$CHANGED_ONLY" ]; then
  if [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ]; then CHANGED_ONLY="true"; else CHANGED_ONLY="false"; fi
fi

run () {
  echo "Running: $*"
  "$@"
}

case "$COMMAND_INPUT" in
  localize)
    # Full flow: detect -> extract -> locize-sync --auto-translate -> download.
    # --ci is non-interactive and skips instrumentation (source rewriting needs
    # human review), so this never modifies your source files. This also covers the
    # "already instrumented, just extract + sync" case: instrument is a no-op/skip.
    # changed-only is a sync-only feature; only warn when it was asked for
    # explicitly (the pull_request auto-default is silently not applied here).
    if [ "${INPUT_CHANGED_ONLY:-}" = "true" ]; then
      echo "::warning::changed-only is not yet supported with command: localize; running the full flow. Use command: sync for changed-only translation."
    fi
    ARGS=(i18next-cli localize --ci)
    [ -n "${INPUT_CONFIG:-}" ] && ARGS+=(--config "$INPUT_CONFIG")
    [ -n "${INPUT_CDN_TYPE:-}" ] && ARGS+=(--cdn-type "$INPUT_CDN_TYPE")
    [ "${INPUT_UPDATE_VALUES:-}" = "true" ] && ARGS+=(--update-values)
    [ "${INPUT_SKIP_TRANSLATE:-}" = "true" ] && ARGS+=(--skip-translate)
    [ "${INPUT_DRY_RUN:-}" = "true" ] && ARGS+=(--dry-run)
    run "${ARGS[@]}"
    ;;

  sync)
    # Already-extracted repos: sync local locale files -> auto-translate -> download.
    # No extraction and no source parsing happen in this mode.
    AUTO_TRANSLATE="true"
    [ "${INPUT_SKIP_TRANSLATE:-}" = "true" ] && AUTO_TRANSLATE="false"

    SYNC_ARGS=(i18next-cli locize-sync --auto-translate "$AUTO_TRANSLATE")
    [ -n "${INPUT_CONFIG:-}" ] && SYNC_ARGS+=(--config "$INPUT_CONFIG")
    [ -n "${INPUT_CDN_TYPE:-}" ] && SYNC_ARGS+=(--cdn-type "$INPUT_CDN_TYPE")
    [ "${INPUT_UPDATE_VALUES:-}" = "true" ] && SYNC_ARGS+=(--update-values)
    if [ "$CHANGED_ONLY" = "true" ]; then
      # Scope syncing + AI translation to the keys this branch changed.
      # GITHUB_BASE_REF is only set on pull_request events; without it the CLI
      # auto-detects the base (origin/HEAD -> main -> master).
      SYNC_ARGS+=(--changed-only)
      [ -n "${GITHUB_BASE_REF:-}" ] && SYNC_ARGS+=(--base "$GITHUB_BASE_REF")
    fi
    [ "${INPUT_DRY_RUN:-}" = "true" ] && SYNC_ARGS+=(--dry-run)
    run "${SYNC_ARGS[@]}"

    # locize-download writes files, so honor dry-run by skipping it.
    if [ "${INPUT_DRY_RUN:-}" = "true" ]; then
      echo "dry-run: skipping locize-download"
    else
      DL_ARGS=(i18next-cli locize-download)
      [ -n "${INPUT_CONFIG:-}" ] && DL_ARGS+=(--config "$INPUT_CONFIG")
      [ -n "${INPUT_CDN_TYPE:-}" ] && DL_ARGS+=(--cdn-type "$INPUT_CDN_TYPE")
      run "${DL_ARGS[@]}"
    fi
    ;;

  *)
    echo "Unsupported command: '$COMMAND_INPUT' (expected 'localize' or 'sync')" >&2
    exit 1
    ;;
esac
