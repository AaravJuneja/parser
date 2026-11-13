#!/usr/bin/env bash

trim() {
    local value=$1
    local whitespace=$' \t'

    value="${value#"${value%%[!$whitespace]*}"}"
    value="${value%"${value##*[!$whitespace]}"}"

    printf '%s' "$value"
}

encode_bytes() {
    local LC_ALL=C
    local input=$1
    local i byte hex

    encoded_bytes=""

    for ((i = 0; i < ${#input}; i++)); do
        printf -v byte '%d' "'${input:i:1}"
        printf -v hex '%02x' "$byte"
        encoded_bytes+="$hex"
    done
}

print_bytes() {
    local hex=$1
    local i

    for ((i = 0; i < ${#hex}; i += 2)); do
        printf '%b' "\\x${hex:i:2}"
    done
}

add_node() {
    local type=$1
    local parent=$2
    local key=$3
    local value=$4

    node_result=${#node_type[@]}

    node_type[node_result]=$type
    node_parent[node_result]=$parent
    node_key[node_result]=$key
    node_value[node_result]=$value
}

select_table() {
    local key=$1
    local node

    for ((node = 1; node < ${#node_type[@]}; node++)); do
        if [[ "${node_type[node]}" == table &&
              "${node_parent[node]}" == 0 &&
              "${node_key[node]}" == "$key" ]]; then
            current_table=$node
            return
        fi
    done

    add_node table 0 "$key" ""
    current_table=$node_result
}

report_error() {
    printf '%s:%d: error: %s\n' \
        "$filename" "$line_number" "$1" >&2

    had_error=1
}

print_pair() {
    local node=$1
    local parent=${node_parent[node]}

    if ((parent != 0)); then
        print_bytes "${node_key[parent]}"
        printf '.'
    fi

    print_bytes "${node_key[node]}"
    printf ' = '
    print_bytes "${node_value[node]}"
    printf '\n'
}

parse_line() {
    local line=$1
    local key value key_hex

    line="$(trim "$line")"

    case "$line" in
        ""|\#*) return ;;
    esac

    if [[ "$line" =~ $table_pattern ]]; then
        encode_bytes "${BASH_REMATCH[1]}"
        select_table "$encoded_bytes"

        printf 'Section: '
        print_bytes "${node_key[current_table]}"
        printf '\n'
        return
    fi

    if [[ "$line" =~ $key_pattern ]]; then
        key="${BASH_REMATCH[1]}"
        value="$(trim "${BASH_REMATCH[2]}")"

        if [[ -z "$value" ]]; then
            report_error "missing value"
            return
        fi

        encode_bytes "$key"
        key_hex=$encoded_bytes

        encode_bytes "$value"
        add_node raw "$current_table" "$key_hex" "$encoded_bytes"

        print_pair "$node_result"
    else
        report_error "unrecognized line: $line"
    fi
}

parse_file() {
    local filename=$1
    local line_number=0
    local had_error=0
    local line=""

    local -a node_type=(table)
    local -a node_parent=(-1)
    local -a node_key=("")
    local -a node_value=("")

    local current_table=0
    local node_result=0
    local encoded_bytes=""

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