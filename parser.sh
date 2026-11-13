#!/usr/bin/env bash

trim() {
    local value=$1
    local whitespace=$' \t'

    value="${value#"${value%%[!$whitespace]*}"}"
    value="${value%"${value##*[!$whitespace]}"}"

    printf '%s' "$value"
}

report_error() {
    printf '%s:%d: error: %s\n' \
        "$filename" "$line_number" "$1" >&2

    had_error=1
}

print_pair() {
    local key=$1
    local value=$2

    if [[ -n "$section" ]]; then
        printf '%s.%s = %s\n' "$section" "$key" "$value"
    else
        printf '%s = %s\n' "$key" "$value"
    fi
}

parse_line() {
    local line=$1
    local key value

    line="$(trim "$line")"

    case "$line" in
        ""|\#*) return ;;
    esac

    if [[ "$line" =~ $table_pattern ]]; then
        section="${BASH_REMATCH[1]}"
        printf 'Section: %s\n' "$section"
        return
    fi

    if [[ "$line" =~ $key_pattern ]]; then
        key="${BASH_REMATCH[1]}"
        value="$(trim "${BASH_REMATCH[2]}")"

        if [[ -z "$value" ]]; then
            report_error "missing value"
            return
        fi

        print_pair "$key" "$value"
    else
        report_error "unrecognized line: $line"
    fi
}

parse_file() {
    local filename=$1
    local section=""
    local line_number=0
    local had_error=0
    local line=""

    local key_pattern=$'^([A-Za-z0-9_-]+)[ \t]*=(.*)$'
    local table_pattern=$'^\\[[ \t]*([A-Za-z0-9_-]+)[ \t]*\\]$'

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number += 1))
        parse_line "$line"
    done < "$filename"

    return "$had_error"
}

main() {
    local filename="${1:-}"

    if [[ -z "$filename" ]]; then
        printf 'Usage: %s FILE\n' "$0"
        return 1
    fi

    if [[ ! -f "$filename" ]]; then
        printf 'Error: file not found: %s\n' "$filename"
        return 1
    fi

    parse_file "$filename"
}

main "$@"