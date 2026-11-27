#!/usr/bin/env bash
# fetch-exports.sh: overwrite committed translation files with translate's exports.
#
# EXPORTS holds one request per line:
#   <query> -> <path>      e.g. project=product-server-php-backend&format=properties&lang=da&platform=all -> i18n/messages_da.properties
#   <project>=<path>       shorthand for project=<project>&format=raw -> <path>
# format=laravel answers several files, so its <path> is a directory; every other format
# writes one file. lang={lang} in a query repeats the line for every language the project
# has in translate, with {lang} in the path replaced too; a line naming one language
# explicitly (lang=en -> messages.properties) takes that language out of the repeat. format=raw is pretty-printed with jq --indent 2, the rest is written as
# served, since those are the consumers' own file formats.
#
# Builds must not fail because translate is down, so a failed request, a bad answer or a
# file that would shrink too much leaves every committed file as it is and prints a
# ::warning. Nothing is written unless every request succeeded. A malformed line or an
# unsafe path is the caller's mistake and fails the step.
set -uo pipefail

TRANSLATE_API="${TRANSLATE_API:?TRANSLATE_API is required}"
MAX_SHRINK_PERCENT="${MAX_SHRINK_PERCENT:-5}"
EXPORTS="${EXPORTS:-}"

error() { echo "::error title=translate-exports::$*"; exit 1; }
keep() { echo "::warning title=Translation fallback::$* The committed files stay as they are."; exit 0; }

if ! [[ "$MAX_SHRINK_PERCENT" =~ ^[0-9]+$ ]] || [ "$MAX_SHRINK_PERCENT" -gt 100 ]; then
  error "max-shrink-percent must be 0-100, got '$MAX_SHRINK_PERCENT'."
fi

safe_path() { # a relative path inside the workspace
  [ -n "$1" ] && [[ "$1" != /* ]] && [[ "/$1/" != */../* ]] && [[ "$1" =~ ^[A-Za-z0-9._/@+-]+$ ]]
}

# Strings in a file, for the shrink guard.
count() {
  case "$1" in
    *.properties) { grep -cE '^[^#![:space:]]' "$1" || true; } ;;
    *.php) { grep -c "' => " "$1" || true; } ;;
    *.json | *.arb) jq 'if type == "object" and has("keys") and (.keys | type == "array") then .keys | length else [paths(scalars)] | length end' "$1" 2>/dev/null || echo 0 ;;
    *) wc -l < "$1" | tr -d ' ' ;;
  esac
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/stage"
: > "$work/plan"

# Parse and check every line before the first request.
n=0
while IFS= read -r line || [ -n "$line" ]; do
  line="$(echo "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  [ -n "$line" ] || continue
  n=$((n + 1))
  if [[ "$line" == *" -> "* ]]; then
    query="${line%% -> *}"; path="${line#* -> }"
  elif [[ "$line" =~ ^([a-z0-9-]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
    query="project=${BASH_REMATCH[1]}&format=raw"; path="${BASH_REMATCH[2]}"
  else
    error "Line $n '$line' is neither '<query> -> <path>' nor '<project>=<path>'."
  fi
  [[ "$query" =~ ^[A-Za-z0-9_.,%=\&{}-]+$ ]] || error "Line $n: '$query' is not a plain query string."
  template=0
  if [[ "$query" == *"{"* || "$path" == *"{"* ]]; then
    [[ "&$query&" == *"&lang={lang}&"* ]] || error "Line $n: '{' is only allowed as lang={lang}."
    [[ "${query//lang=\{lang\}/}" != *"{"* ]] || error "Line $n: '{' is only allowed as lang={lang}."
    template=1
  fi
  project="$(tr '&' '\n' <<< "$query" | sed -n 's/^project=//p' | head -1)"
  format="$(tr '&' '\n' <<< "$query" | sed -n 's/^format=//p' | head -1)"
  [[ "$project" =~ ^[a-z0-9-]+$ ]] || error "Line $n: the query needs project=<slug>."
  [[ "$format" =~ ^(raw|properties|arb|lokalise-json|laravel)$ ]] || error "Line $n: format must be raw, properties, arb, lokalise-json or laravel, got '$format'."
  safe_path "${path//\{lang\}/x}" || error "Line $n: '$path' must be a relative path inside the repository."
  if [ "$format" = laravel ]; then
    [[ "$path" != *"{"* ]] || error "Line $n: format=laravel writes a directory; leave {lang} out of its path."
    [ -d "$path" ] || error "Line $n: format=laravel writes a directory, and '$path' is not one."
  elif [ "$template" = 1 ]; then
    [[ "$path" == *"{lang}"* ]] || error "Line $n: lang={lang} needs {lang} in the path, or every language writes one file."
    [ -d "$(dirname "$path")" ] || error "Line $n: '$(dirname "$path")' must be a committed directory."
  else
    [ -f "$path" ] || error "Line $n: '$path' must be a committed file; the image falls back to it."
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$query" "$format" "$path" "$template" "$project" >> "$work/lines"
done <<< "$EXPORTS"
[ -s "$work/lines" ] || error "translate-exports is set but lists nothing."

# Repeat each lang={lang} line over the project's languages in translate, in the line's
# place. A language another line names explicitly for the same project and format stays
# with that line. A language without a committed file yet is written as a new file.
if cut -f5 "$work/lines" | grep -qx 1; then
  code="$(curl -sS --max-time 60 --retry 2 --retry-delay 3 -o "$work/projects.json" -w '%{http_code}' "$TRANSLATE_API/projects" 2>/dev/null)" || code=000
  [ "$code" = 200 ] || keep "translate answered HTTP $code for its project list."
fi
cp "$work/lines" "$work/explicit"
while IFS=$'\t' read -r n query format path template project; do
  if [ "$template" = 0 ]; then printf '%s\t%s\t%s\t%s\n' "$n" "$query" "$format" "$path" >> "$work/plan"; continue; fi
  langs="$(jq -er --arg s "$project" '(.projects // .)[] | select(.slug == $s) | .languages | select(length > 0) | .[]' "$work/projects.json" 2>/dev/null)" \
    || keep "translate lists no languages for '$project'."
  for lang in $langs; do
    [[ "$lang" =~ ^[A-Za-z0-9_]+$ ]] || keep "translate lists an unexpected language '$lang' for '$project'."
    if awk -F'\t' -v p="$project" -v f="$format" -v l="lang=$lang" '$5 == 0 && $6 == p && $3 == f && index("&" $2 "&", "&" l "&") > 0 { found = 1 } END { exit !found }' "$work/explicit"; then
      continue
    fi
    printf '%s\t%s\t%s\t%s\n' "$n-$lang" "${query//\{lang\}/$lang}" "$format" "${path//\{lang\}/$lang}" >> "$work/plan"
  done
done < "$work/lines"

# Fetch everything into the stage. One failure keeps every committed file.
stale=""
while IFS=$'\t' read -r n query format path; do
  body="$work/body-$n"
  code="$(curl -sS --max-time 60 --retry 2 --retry-delay 3 -D "$work/headers-$n" -o "$body" -w '%{http_code}' "$TRANSLATE_API/export?$query" 2>/dev/null)" || code=000
  [ "$code" = 200 ] || keep "translate answered HTTP $code for '$query'."
  grep -qi '^x-mirror-stale: *true' "$work/headers-$n" && stale=1
  case "$format" in
    raw)
      project="$(tr '&' '\n' <<< "$query" | sed -n 's/^project=//p' | head -1)"
      jq -e --arg p "$project" '.project == $p and (.keys | type == "array" and length > 0)' "$body" > /dev/null 2>&1 \
        || keep "translate's raw export of '$project' is not the expected JSON."
      mkdir -p "$work/stage/$(dirname "$path")"; jq --indent 2 . "$body" > "$work/stage/$path" ;;
    laravel)
      jq -e '.files | type == "object" and length > 0' "$body" > /dev/null 2>&1 || keep "translate's laravel export for '$query' has no files."
      while IFS= read -r rel; do
        if ! safe_path "$rel" || [[ "$rel" != *.php ]]; then keep "translate's laravel export for '$query' names an unexpected file '$rel'."; fi
        mkdir -p "$work/stage/$path/$(dirname "$rel")"
        jq -j --arg f "$rel" '.files[$f]' "$body" > "$work/stage/$path/$rel"
      done < <(jq -r '.files | keys[]' "$body")
      ;;
    *)
      [ -s "$body" ] || keep "translate's export for '$query' is empty."
      if [ "$format" != properties ]; then jq -e . "$body" > /dev/null 2>&1 || keep "translate's export for '$query' is not JSON."; fi
      mkdir -p "$work/stage/$(dirname "$path")"; cp "$body" "$work/stage/$path" ;;
  esac
done < "$work/plan"

# Shrink guard against the committed files.
total=0
while IFS= read -r -d '' staged; do
  rel="${staged#"$work/stage/"}"
  total=$((total + 1))
  new="$(count "$staged")"
  [ "$new" -gt 0 ] || keep "'$rel' would have no strings."
  if [ -f "$rel" ]; then
    old="$(count "$rel")"
    if [ $((new * 100)) -lt $((old * (100 - MAX_SHRINK_PERCENT))) ]; then
      keep "'$rel' would shrink from $old to $new strings (more than $MAX_SHRINK_PERCENT%)."
    fi
  fi
done < <(find "$work/stage" -type f -print0)

cp -R "$work/stage/." .
[ -n "$stale" ] && echo "::warning title=Stale export::translate's copy is older than usual, so the baked-in files may miss the latest edits."
echo "Baked $total file(s) from translate into the image."
