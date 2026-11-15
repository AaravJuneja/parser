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

    if [[ "$line" =~ $ignored_pattern ]]; then
        return
    fi

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

validate_document() {
    local i byte
    local pending=0
    local codepoint=0
    local minimum=0

    line_number=1

    for ((i = 0; i < ${#document}; i++)); do
        printf -v byte '%d' "'${document:i:1}"

        if ((pending > 0)); then
            if ((byte < 0x80 || byte > 0xbf)); then
                report_error "invalid UTF-8 continuation byte"
                return 1
            fi

            codepoint=$(((codepoint << 6) | (byte & 0x3f)))
            pending=$((pending - 1))

            if ((pending == 0)); then
                if ((codepoint < minimum ||
                     codepoint > 0x10ffff ||
                     (codepoint >= 0xd800 && codepoint <= 0xdfff))); then
                    report_error "invalid UTF-8 code point"
                    return 1
                fi
            fi
        elif ((byte < 0x80)); then
            case "$byte" in
                9)
                    ;;
                10)
                    ((line_number += 1))
                    ;;
                13)
                    if [[ "${document:i:2}" != $'\r\n' ]]; then
                        report_error "carriage return must be followed by line feed"
                        return 1
                    fi
                    ;;
                *)
                    if ((byte < 0x20 || byte == 0x7f)); then
                        report_error "forbidden raw control character"
                        return 1
                    fi
                    ;;
            esac
        elif ((byte >= 0xc2 && byte <= 0xdf)); then
            pending=1
            codepoint=$((byte & 0x1f))
            minimum=0x80
        elif ((byte >= 0xe0 && byte <= 0xef)); then
            pending=2
            codepoint=$((byte & 0x0f))
            minimum=0x800
        elif ((byte >= 0xf0 && byte <= 0xf4)); then
            pending=3
            codepoint=$((byte & 0x07))
            minimum=0x10000
        else
            report_error "invalid UTF-8 leading byte"
            return 1
        fi
    done

    if ((pending != 0)); then
        report_error "incomplete UTF-8 sequence"
        return 1
    fi

    return 0
}

read_document() {
    local read_status

    if IFS= read -r -d '' document; then
        read_status=0
    else
        read_status=$?
    fi

    if ((read_status > 1)); then
        report_error "could not read document"
        return 1
    fi

    validate_document || return 1

    if ((read_status == 0)); then
        report_error "raw NUL byte is not permitted"
        return 1
    fi

    return 0
}

parse_file() {
    local LC_ALL=C
    local filename=$1
    local line_number=1
    local had_error=0
    local document=""
    local remaining=""
    local line=""

    local -a node_type=(table)
    local -a node_parent=(-1)
    local -a node_key=("")
    local -a node_value=("")

    local current_table=0
    local node_result=0
    local encoded_bytes=""

    local ignored_pattern=$'^[ \t]*(#.*)?$'
    local key_pattern=$'^[ \t]*([A-Za-z0-9_-]+)[ \t]*=(.*)$'
    local table_pattern=$'^[ \t]*\\[[ \t]*([A-Za-z0-9_-]+)[ \t]*\\][ \t]*$'

    if ! read_document < "$filename"; then
        return 1
    fi

    remaining=$document
    line_number=0

    while [[ -n "$remaining" ]]; do
        ((line_number += 1))

        if [[ "$remaining" == *$'\n'* ]]; then
            line=${remaining%%$'\n'*}
            remaining=${remaining#*$'\n'}

            line=${line%$'\r'}
        else
            line=$remaining
            remaining=""
        fi

        parse_line "$line"
    done

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