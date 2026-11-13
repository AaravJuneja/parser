#!/usr/bin/env bash

trim() {
    local value=$1
    local whitespace=$' \t'

    value="${value#"${value%%[!$whitespace]*}"}"
    value="${value%"${value##*[!$whitespace]}"}"

    printf '%s' "$value"
}

filename="$1"

if [[ -z "$filename" ]]; then
    printf "Usage: %s FILE\n" "$0"
    exit 1
fi    

if [[ ! -f "$filename" ]]; then
    printf "Error: file not found: %s\n" "$filename"
    exit 1
fi

section=""
line_number=0
had_error=0

key_pattern=$'^([A-Za-z0-9_-]+)[ \t]*=(.*)$'
table_pattern=$'^\\[[ \t]*([A-Za-z0-9_-]+)[ \t]*\\]$'

while IFS= read -r line || [[ -n "$line" ]]; do
    ((line_number += 1))
    line="$(trim "$line")"

    case "$line" in
        ""|\#*) continue ;;
    esac

    if [[ "$line" =~ $table_pattern ]]; then
        section="${BASH_REMATCH[1]}"
        printf "Section: %s\n" "$section"
        continue
    fi
    
    if [[ "$line" =~ $key_pattern ]]; then
        key="${BASH_REMATCH[1]}"
        value="$(trim "${BASH_REMATCH[2]}")"

        if [[ -z "$value" ]]; then
            printf '%s:%d: error: missing value\n' \
                "$filename" "$line_number" >&2
            had_error=1
            continue
        fi

        if [[ -n "$section" ]]; then
            printf '%s.%s = %s\n' "$section" "$key" "$value"
        else
            printf '%s = %s\n' "$key" "$value"
        fi

    else
        printf '%s:%d: error: unrecognized line: %s\n' "$filename" "$line_number" "$line" >&2
        had_error=1
    fi
done < "$filename"

exit "$had_error"
