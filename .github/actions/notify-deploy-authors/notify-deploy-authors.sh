#!/usr/bin/env bash
#
# DM the authors of everything in a deploy, telling them their change is live and pointing them at
# the dashboard to watch. Run this as a step after the rollout has finished.
#
# Never fails the caller: a monitoring nudge is not worth breaking a deploy over, so every runtime
# problem is a ::warning:: and a zero exit. Set STRICT=true to exit non-zero instead, which is what
# you want while testing the wiring.
#
# Needs: bash, curl, jq. No associative arrays, so this also runs on the bash 3.2 that ships with
# macOS - handy for testing by hand before wiring it up.
#
set -uo pipefail

STRICT="${STRICT:-false}"
DRY_RUN="${DRY_RUN:-false}"
STAGE="${STAGE:-}"
IDENTITY_API_URL="${IDENTITY_API_URL:-}"
DASHBOARD_LABEL="${DASHBOARD_LABEL:-Error Dashboard}"
MONITORING_WINDOW="${MONITORING_WINDOW:-the next 30 minutes}"
MAX_AUTHORS="${MAX_AUTHORS:-15}"

# Anything we can't do is a warning, not a failed deploy. Note there is deliberately no `set -e`
# or ERR trap: an ERR trap fires on every non-zero command, including the many ordinary
# "grep matched nothing" cases below, which would abort the run halfway through.
give_up() {
  echo "::warning::notify-deploy-authors: $1"
  [ "$STRICT" = "true" ] && exit 1
  exit 0
}

for required in GITHUB_REPOSITORY GITHUB_TOKEN CURRENT_REF DASHBOARD_URL SERVICE_NAME; do
  eval "value=\${$required:-}"
  [ -n "$value" ] || give_up "missing required input: $required"
done
if [ "$DRY_RUN" != "true" ] && [ -z "${SLACK_TOKEN:-}" ]; then
  give_up "missing required input: SLACK_TOKEN"
fi

# A first deploy has nothing to compare against, which is not an error.
[ -n "${PREVIOUS_REF:-}" ] || give_up "no previous ref given - nothing to compare, skipping"
[ "$PREVIOUS_REF" != "$CURRENT_REF" ] || give_up "previous and current ref are identical - skipping"

US=$(printf '\037')

gh_api() { curl -sSf -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$@"; }

slack_api() {
  method="$1"; shift
  curl -sS -H "Authorization: Bearer $SLACK_TOKEN" -H "Content-type: application/json; charset=utf-8" \
    "https://slack.com/api/$method" "$@"
}

# --- who is in this deploy --------------------------------------------------------------------
# The compare API gives every commit between the two refs, which is all we need: commit authors are
# logins, and Co-authored-by trailers give us the people GitHub doesn't attribute.
compare_json="$(gh_api "https://api.github.com/repos/$GITHUB_REPOSITORY/compare/$PREVIOUS_REF...$CURRENT_REF?per_page=250")" ||
  give_up "could not compare $PREVIOUS_REF...$CURRENT_REF (do both refs exist?)"

# Bots never need to monitor anything. `[bot]` catches the GitHub App suffix; the identity
# resolver's isBot flag catches the rest further down.
logins="$(jq -r '[.commits[].author.login | select(. != null)] | unique | .[]' <<<"$compare_json" |
  grep -v '\[bot\]$' || true)"

coauthor_emails="$(jq -r '.commits[].commit.message' <<<"$compare_json" |
  grep -iEo 'co-authored-by:[[:space:]]*[^<]*<[^>]+>' |
  sed -E 's/.*<([^>]+)>.*/\1/' |
  grep -viE 'users\.noreply\.github\.com|noreply@' | sort -u || true)"

if [ -z "$logins" ] && [ -z "$coauthor_emails" ]; then
  echo "No human authors between $PREVIOUS_REF and $CURRENT_REF - nothing to do."
  exit 0
fi

author_count=$(printf '%s\n%s\n' "$logins" "$coauthor_emails" | grep -cve '^$' || true)
echo "Authors in this deploy ($author_count): $(tr '\n' ' ' <<<"$logins") $(tr '\n' ' ' <<<"$coauthor_emails")"

# A range far bigger than a normal deploy usually means the refs are wrong. Better to say so than
# to DM half the company.
if [ "$author_count" -gt "$MAX_AUTHORS" ]; then
  give_up "$author_count authors exceeds MAX_AUTHORS=$MAX_AUTHORS - refusing to DM. Check PREVIOUS_REF/CURRENT_REF."
fi

# --- resolve them to Slack --------------------------------------------------------------------
# A GitHub login alone does not reach anyone in Slack: public profile emails are set on a small
# minority of the org, and commit emails are often noreply or personal addresses. The identity
# resolver knows each person's work email, which is the address Slack has.
#
# Records are: key, email, slackUserId, displayName - delimited by a unit separator rather than a
# tab, because tab counts as IFS whitespace and `read` would collapse runs of empty fields,
# shifting everything after a blank one into the wrong slot.
people=""
resolved=""

if [ -n "$IDENTITY_API_URL" ]; then
  query=""
  [ -n "$logins" ] && query="github=$(paste -sd, - <<<"$logins")"
  [ -n "$coauthor_emails" ] && query="${query:+$query&}email=$(paste -sd, - <<<"$coauthor_emails")"

  # Optional and best-effort: off the tailnet this fails and we fall back to GitHub data.
  if identity_json="$(curl -sSf --max-time 15 "$IDENTITY_API_URL/api/identity/resolve?$query" 2>/dev/null)"; then
    # personId as the key means one person reached once, even when they turn up both as a commit
    # author and as a co-author email. The resolver flags bots and leavers rather than filtering
    # them; we want neither.
    people="$(jq -r '
      [.github // {}, .email // {}] | add | to_entries[]
      | select(.value != null)
      | select(.value.isBot != true and .value.isActive != false)
      | [(.value.personId // .key), (.value.email // ""), (.value.slackUserId // ""), (.value.displayName // .key)]
      | join("\u001f")' <<<"$identity_json" | sort -u)"

    resolved="$(jq -r '[.github // {}, .email // {}] | add | to_entries[]
      | select(.value != null) | .key' <<<"$identity_json" | tr '[:upper:]' '[:lower:]' | sort -u)"
  else
    echo "::warning::Identity resolver unreachable at $IDENTITY_API_URL - falling back to GitHub emails, which reach far fewer people"
  fi
fi

is_resolved() { [ -n "$resolved" ] && grep -qxF "$(tr '[:upper:]' '[:lower:]' <<<"$1")" <<<"$resolved"; }

# Fall back to the public GitHub profile email for anyone the resolver didn't cover.
while read -r login; do
  [ -z "$login" ] && continue
  is_resolved "$login" && continue
  profile_email="$(gh_api "https://api.github.com/users/$login" | jq -r '.email // empty' || true)"
  people="$people
$(printf '%s%s%s%s%s%s' "$login" "$US" "$profile_email" "$US" "$US" "$login")"
done <<<"$logins"

# A co-author trailer email the resolver didn't know is still worth a direct Slack lookup.
if [ -n "$coauthor_emails" ]; then
  while read -r email; do
    [ -z "$email" ] && continue
    is_resolved "$email" && continue
    people="$people
$(printf '%s%s%s%s%s%s' "$email" "$US" "$email" "$US" "$US" "$email")"
  done <<<"$coauthor_emails"
fi

# Drop blanks, then drop repeats of an address we have already queued under another key.
people="$(grep -v '^[[:space:]]*$' <<<"$people" | sort -u |
  awk -F"$US" '{ if ($2 == "" || !seen[$2]++) print }')"

# --- the message ------------------------------------------------------------------------------
stage_text=""
[ -n "$STAGE" ] && stage_text=" to $(tr '[:lower:]' '[:upper:]' <<<"${STAGE:0:1}")${STAGE:1}"

ref_link="$CURRENT_REF"
[ -n "${REF_URL:-}" ] && ref_link="<$REF_URL|$CURRENT_REF>"

headline=":rocket: *Your changes are live* - $SERVICE_NAME $ref_link is now deployed${stage_text}."
ask="Please keep an eye out for errors over $MONITORING_WINDOW:
• <$DASHBOARD_URL|$DASHBOARD_LABEL>"
fallback="Your changes are live in $SERVICE_NAME $CURRENT_REF - please monitor for errors"

sent=0
unreachable=""
while IFS="$US" read -r key email slack_id name; do
  [ -z "${key:-}" ] && continue

  if [ -z "$slack_id" ]; then
    if [ -z "$email" ]; then
      unreachable="$unreachable $name"
      continue
    fi
    if [ "$DRY_RUN" = "true" ]; then
      slack_id="(would look up $email)"
    else
      lookup="$(slack_api "users.lookupByEmail?email=$email")"
      slack_id="$(jq -r '.user.id // empty' <<<"$lookup")"
      if [ -z "$slack_id" ]; then
        echo "::warning::No Slack account for $name <$email>: $(jq -r '.error // "unknown"' <<<"$lookup")"
        unreachable="$unreachable $name"
        continue
      fi
    fi
  fi

  payload="$(jq -nc --arg ch "$slack_id" --arg text "$fallback" --arg h "$headline" --arg a "$ask" '{
    channel: $ch, text: $text,
    blocks: [
      {type:"section", text:{type:"mrkdwn", text:$h}},
      {type:"section", text:{type:"mrkdwn", text:$a}}
    ]}')"

  if [ "$DRY_RUN" = "true" ]; then
    echo "--- would DM $name [$slack_id] ---"
    jq . <<<"$payload"
  else
    # Posting to a user id opens (or reuses) the DM with them.
    result="$(slack_api chat.postMessage -d "$payload")"
    if [ "$(jq -r '.ok' <<<"$result")" = "true" ]; then
      echo "DM sent to $name"
      sent=$((sent + 1))
    else
      echo "::warning::DM to $name failed: $(jq -r '.error' <<<"$result")"
    fi
  fi
done <<<"$people"

echo "Done. DMs sent: $sent. Unreachable:${unreachable:- none}"
if [ -n "$unreachable" ]; then
  echo "::warning::Could not reach in Slack:$unreachable. Set identity-api-url (and give the runner tailnet access) so authors resolve without a public GitHub email."
fi
