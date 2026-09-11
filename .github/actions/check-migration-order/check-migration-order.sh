#!/usr/bin/env bash
#
# Fails when this branch adds a Flyway migration that does not sort after every
# migration already on the base branch, or when it touches a committed one.
#
# Env:
#   BASE_REF         branch to compare against, e.g. "main" (not a full ref)
#   MIGRATION_PATHS  newline-separated migration roots; each is an INDEPENDENT
#                    Flyway version namespace
#   NAMING_PATTERN   ERE every newly added migration filename must match
set -euo pipefail

: "${BASE_REF:?BASE_REF is required}"
: "${MIGRATION_PATHS:?MIGRATION_PATHS is required}"
: "${NAMING_PATTERN:?NAMING_PATTERN is required}"

# merge-base needs real history; a shallow clone silently yields the wrong
# answer rather than failing, so deepen instead of trusting the caller.
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
    echo "Repository is shallow, unshallowing to get a usable merge base..."
    git fetch --unshallow --quiet
fi

git fetch origin "$BASE_REF" --quiet
base="origin/$BASE_REF"
merge_base=$(git merge-base HEAD "$base")

# Strip directory, the B/V prefix and the __description suffix.
versions() { sed -E 's|.*/||; s|^[BV]||; s|__.*$||'; }

errors=0
checked=0

check_root() {
    local migrations="$1"

    # The base branch is the authority on whether a root exists: a PR that adds
    # the very first migration to a new root must still be checked.
    if [ -z "$(git ls-tree -r --name-only "$base" -- "$migrations")" ] &&
        [ ! -d "$migrations" ]; then
        echo "  no such path on $base or in the working tree — skipping"
        return 0
    fi
    checked=$((checked + 1))

    # Flyway pools every location under a root into one version namespace, so the
    # ceiling is the highest version anywhere under it on the base branch TIP --
    # not on the merge base, which is what lets a stale branch merge out of order.
    local base_max
    base_max=$(
        git ls-tree -r --name-only "$base" -- "$migrations" |
            grep -E '\.sql$' | versions | sort -V | tail -1
    )
    echo "  newest migration on $base: ${base_max:-<none>}"

    # A committed migration's checksum is recorded in flyway_schema_history, so
    # editing, renaming or deleting one breaks validation on every environment
    # that already applied it.
    local file name version newest
    while read -r file; do
        [ -n "$file" ] || continue
        echo "::error file=$file::$file is an existing migration -- editing, renaming or deleting it breaks Flyway checksum validation everywhere it already ran. Add a new migration instead."
        errors=$((errors + 1))
    done < <(git diff --name-only --diff-filter=MRD "$merge_base" HEAD -- "$migrations" | grep -E '\.sql$' || true)

    while read -r file; do
        [ -n "$file" ] || continue
        name=$(basename "$file")

        if ! printf '%s' "$name" | grep -qE "$NAMING_PATTERN"; then
            echo "::error file=$file::Bad migration name '$name' -- must match $NAMING_PATTERN"
            errors=$((errors + 1))
            continue
        fi

        version=$(printf '%s' "$name" | versions)
        newest=$(printf '%s\n%s\n' "$version" "$base_max" | sort -V | tail -1)

        if [ -n "$base_max" ] && { [ "$version" = "$base_max" ] || [ "$newest" != "$version" ]; }; then
            echo "::error file=$file::Migration $version does not sort after $base_max, the newest migration already on $BASE_REF. Rebase and rename it to a timestamp after that one."
            errors=$((errors + 1))
        else
            echo "  OK: $name sorts after ${base_max:-<none>}"
        fi
    done < <(git diff --name-only --diff-filter=A "$merge_base" HEAD -- "$migrations" | grep -E '\.sql$' || true)
}

while IFS= read -r root; do
    root="${root#"${root%%[![:space:]]*}"}"
    root="${root%"${root##*[![:space:]]}"}"
    [ -n "$root" ] || continue
    echo "::group::$root"
    check_root "$root"
    echo "::endgroup::"
done <<<"$MIGRATION_PATHS"

if [ "$errors" -gt 0 ]; then
    echo "FAILED: $errors migration problem(s)."
    exit 1
fi
if [ "$checked" -eq 0 ]; then
    echo "No migration roots found — nothing to check."
    exit 0
fi
echo "OK: migrations in $checked root(s) are ordered after $BASE_REF."
