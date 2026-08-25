#!/usr/bin/env bash
set -uo pipefail

# Local test for the notify-deploy-authors action.
#
# Defaults to a dry run: it resolves real authors against the real identity resolver and prints the
# exact Slack payloads, without messaging anyone. Pass --send to actually deliver the DMs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/.env" ]; then
  echo "Loading $SCRIPT_DIR/.env"
  set -a
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/.env"
  set +a
fi

: "${GITHUB_TOKEN:=$(gh auth token 2>/dev/null)}"
export GITHUB_TOKEN

DRY_RUN=true
for arg in "$@"; do
  case "$arg" in
    --send) DRY_RUN=false ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done
export DRY_RUN

# A local run is for finding wiring mistakes, so surface them instead of warning and moving on.
export STRICT="${STRICT:-true}"

if [ "$DRY_RUN" = "false" ]; then
  echo "About to send REAL DMs to the authors of ${PREVIOUS_REF:-?}...${CURRENT_REF:-?}."
  printf 'Type "yes" to continue: '
  read -r confirm
  [ "$confirm" = "yes" ] || { echo "Aborted."; exit 1; }
fi

exec "$SCRIPT_DIR/notify-deploy-authors.sh"
