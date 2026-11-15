#!/usr/bin/env bash

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

advance_cursor() {
    case "${document:position:1}" in
        $'\r')
            ((position += 2))
            ((line_number += 1))
            ;;
        $'\n')
            ((position += 1))
            ((line_number += 1))
            ;;
        *)
            ((position += 1))
            ;;
    esac

    return 0
}

skip_whitespace() {
    while ((position < document_length)); do
        case "${document:position:1}" in
            ' ' | $'\t')
                advance_cursor
                ;;
            *)
                break
                ;;
        esac
    done

    return 0
}

skip_to_newline() {
    while ((position < document_length)); do
        case "${document:position:1}" in
            $'\r' | $'\n')
                break
                ;;
        esac

        advance_cursor
    done

    return 0
}

parse_bare_key() {
    local start=$position

    while ((position < document_length)); do
        case "${document:position:1}" in
            [A-Za-z0-9_-])
                advance_cursor
                ;;
            *)
                break
                ;;
        esac
    done

    if ((position == start)); then
        return 1
    fi

    parsed_key="${document:start:position-start}"
    return 0
}

parse_raw_value() {
    local start=$position
    local end=$position

    while ((position < document_length)); do
        case "${document:position:1}" in
            $'\r' | $'\n')
                break
                ;;
            ' ' | $'\t')
                ;;
            *)
                end=$((position + 1))
                ;;
        esac

        advance_cursor
    done

    if ((end == start)); then
        report_error "missing value"
        return 1
    fi

    parsed_value="${document:start:end-start}"
    return 0
}

parse_table_header() {
    local parsed_key=""

    advance_cursor
    skip_whitespace

    parse_bare_key || return 1

    skip_whitespace

    [[ "${document:position:1}" == ']' ]] || return 1

    advance_cursor
    skip_whitespace

    case "${document:position:1}" in
        "" | $'\r' | $'\n')
            ;;
        *)
            return 1
            ;;
    esac

    encode_bytes "$parsed_key"
    select_table "$encoded_bytes"

    printf 'Section: '
    print_bytes "${node_key[current_table]}"
    printf '\n'
    return 0
}

parse_key_value() {
    local parsed_key=""
    local parsed_value=""
    local key_hex

    parse_bare_key || return 1

    skip_whitespace

    [[ "${document:position:1}" == '=' ]] || return 1

    advance_cursor
    skip_whitespace
    parse_raw_value || return 1

    encode_bytes "$parsed_key"
    key_hex=$encoded_bytes

    encode_bytes "$parsed_value"
    add_node raw "$current_table" "$key_hex" "$encoded_bytes"
    print_pair "$node_result"
    return 0
}

parse_document() {
    local start parser

    while ((position < document_length)); do
        start=$position
        skip_whitespace

        case "${document:position:1}" in
            "")
                break
                ;;
            $'\r' | $'\n')
                advance_cursor
                continue
                ;;
            '#')
                skip_to_newline
                continue
                ;;
            '[')
                parser=parse_table_header
                ;;
            *)
                parser=parse_key_value
                ;;
        esac

        if ! "$parser"; then
            if ((had_error == 0)); then
                skip_to_newline
                report_error "unrecognized line: ${document:start:position-start}"
            fi
            return 1
        fi
    done

    return 0
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
                return 1
            fi

            codepoint=$(((codepoint << 6) | (byte & 0x3f)))
            pending=$((pending - 1))

            if ((pending == 0)); then
                if ((codepoint < minimum ||
                     codepoint > 0x10ffff ||
                     (codepoint >= 0xd800 && codepoint <= 0xdfff))); then
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
                        return 1
                    fi
                    ;;
                *)
                    if ((byte < 0x20 || byte == 0x7f)); then
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
            return 1
        fi
    done

    if ((pending != 0)); then
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

    if ! validate_document || ((read_status == 0)); then
        report_error "invalid UTF-8 or raw control character"
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
    local document_length=0
    local position=0

    local -a node_type=(table)
    local -a node_parent=(-1)
    local -a node_key=("")
    local -a node_value=("")

    local current_table=0
    local node_result=0
    local encoded_bytes=""

    if ! read_document < "$filename"; then
        return 1
    fi

    document_length=${#document}
    line_number=1
    parse_document
}

main() {
    local filename="${1:-}"

    if [[ -z "$filename" ]]; then
        printf 'Usage: %s FILE\n' "$0"
        return 1
    fi

    if [[ ! -f "$filename" ]]; then
        printf 'why no file: %s\n' "$filename"
        return 1
    fi

    parse_file "$filename"
}

main "$@"