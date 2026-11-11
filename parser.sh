#!/usr/bin/env bash

filename="$1"

if [[ -z "$filename" ]]; then
    printf "Usage: %s FILE\n" "$0"
    exit 1
fi    

if [[ ! -f "$filename" ]]; then
    printf "Error: file not found: %s\n" "$filename"
    exit 1
fi

section="default"
while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
        ""|\#*|\;*) continue ;;
    esac

    if [[ "$line" =~ ^\[([a-zA-Z0-9_.-]+)\]$ ]]; then
        section="${BASH_REMATCH[1]}"
        printf "Section: %s\n" "$section"
        continue
    fi
    
    if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_.-]*)[[:space:]]*=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        printf '%s.%s = %s\n' "$section" "$key" "$value"
    else
        printf 'Error: unrecognized line: %s\n' "$line" >&2
    fi
    
done < "$filename"