#!/usr/bin/env bash

encode_bytes() {
    local input=$1
    local i byte hex

    encoded_bytes=""

    for ((i = 0; i < ${#input}; i++)); do
        printf -v byte '%d' "'${input:i:1}"
        printf -v hex '%02x' "$byte"
        encoded_bytes+="$hex"
    done
}

encode_codepoint() {
    local codepoint=$1

    if ((codepoint > 0x10ffff ||
         (codepoint >= 0xd800 && codepoint <= 0xdfff))); then
        return 1
    fi

    if ((codepoint <= 0x7f)); then
        printf -v encoded_bytes '%02x' "$codepoint"
    elif ((codepoint <= 0x7ff)); then
        printf -v encoded_bytes '%02x%02x' \
            "$((0xc0 | (codepoint >> 6)))" \
            "$((0x80 | (codepoint & 0x3f)))"
    elif ((codepoint <= 0xffff)); then
        printf -v encoded_bytes '%02x%02x%02x' \
            "$((0xe0 | (codepoint >> 12)))" \
            "$((0x80 | ((codepoint >> 6) & 0x3f)))" \
            "$((0x80 | (codepoint & 0x3f)))"
    else
        printf -v encoded_bytes '%02x%02x%02x%02x' \
            "$((0xf0 | (codepoint >> 18)))" \
            "$((0x80 | ((codepoint >> 12) & 0x3f)))" \
            "$((0x80 | ((codepoint >> 6) & 0x3f)))" \
            "$((0x80 | (codepoint & 0x3f)))"
    fi

    return 0
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
    printf '%s:%d: error: %s\n' "$filename" "$line_number" "$1"
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

    if [[ "${node_type[node]}" == string ]]; then
        printf '%s' "$2"
    else
        print_bytes "${node_value[node]}"
    fi

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

parse_statement_end() {
    skip_whitespace

    case "${document:position:1}" in
        '#')
            skip_to_newline
            ;;
        "" | $'\r' | $'\n')
            return 0
            ;;
        *)
            return 1
            ;;
    esac
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

parse_escape() {
    local digits=0
    local hex codepoint

    advance_cursor

    case "${document:position:1}" in
        '"') encoded_bytes=22 ;;
        \\) encoded_bytes=5c ;;
        b) encoded_bytes=08 ;;
        t) encoded_bytes=09 ;;
        n) encoded_bytes=0a ;;
        f) encoded_bytes=0c ;;
        r) encoded_bytes=0d ;;
        e) encoded_bytes=1b ;;
        x) digits=2 ;;
        u) digits=4 ;;
        U) digits=8 ;;
        *) return 1 ;;
    esac

    advance_cursor

    if ((digits > 0)); then
        hex="${document:position:digits}"

        [[ ${#hex} -eq digits && "$hex" != *[!0-9a-fA-F]* ]] || return 1

        codepoint=$((16#$hex))
        encode_codepoint "$codepoint" || return 1
        ((position += digits))
    fi

    return 0
}

parse_string() {
    local quote="${document:position:1}"
    local start

    parsed_value=""
    advance_cursor
    start=$position

    while ((position < document_length)); do
        case "${document:position:1}" in
            "$quote")
                encode_bytes "${document:start:position-start}"
                parsed_value+="$encoded_bytes"
                advance_cursor
                return 0
                ;;
            $'\r' | $'\n')
                return 1
                ;;
            \\)
                if [[ "$quote" == '"' ]]; then
                    encode_bytes "${document:start:position-start}"
                    parsed_value+="$encoded_bytes"
                    parse_escape || return 1
                    parsed_value+="$encoded_bytes"
                    start=$position
                    continue
                fi
                ;;
        esac

        advance_cursor
    done

    return 1
}

parse_multiline_escape() {
    case "${document:position+1:1}" in
        ' ' | $'\t' | $'\r' | $'\n')
            ;;
        *)
            parse_escape
            return
            ;;
    esac

    advance_cursor
    skip_whitespace

    case "${document:position:1}" in
        $'\r' | $'\n')
            ;;
        *)
            return 1
            ;;
    esac

    while ((position < document_length)); do
        case "${document:position:1}" in
            ' ' | $'\t' | $'\r' | $'\n')
                advance_cursor
                ;;
            *)
                break
                ;;
        esac
    done

    encoded_bytes=""
    return 0
}

parse_multiline_string() {
    local quote="${document:position:1}"
    local start quote_start

    parsed_value=""
    ((position += 3))

    case "${document:position:1}" in
        $'\r' | $'\n')
            advance_cursor
            ;;
    esac

    start=$position

    while ((position < document_length)); do
        case "${document:position:1}" in
            "$quote")
                quote_start=$position
                while [[ "${document:position:1}" == "$quote" ]]; do
                    ((position += 1))
                done

                case $((position - quote_start)) in
                    1 | 2)
                        continue
                        ;;
                    3 | 4 | 5)
                        encode_bytes "${document:start:position-start-3}"
                        parsed_value+="$encoded_bytes"
                        return 0
                        ;;
                    *)
                        return 1
                        ;;
                esac
                ;;
            \\)
                if [[ "$quote" == '"' ]]; then
                    encode_bytes "${document:start:position-start}"
                    parsed_value+="$encoded_bytes"
                    parse_multiline_escape || return 1
                    parsed_value+="$encoded_bytes"
                    start=$position
                    continue
                fi
                ;;
        esac

        advance_cursor
    done

    return 1
}

parse_integer() {
    local digits=$1
    local base=10
    local negative=0
    local limit=$(( (1 << 63) + 1 ))
    local value=0
    local i digit

    case "$digits" in
        -*)
            negative=1
            ((limit -= 1))
            digits=${digits:1}
            ;;
        +*)
            digits=${digits:1}
            ;;
        0x*)
            base=16
            digits=${digits:2}
            ;;
        0o*)
            base=8
            digits=${digits:2}
            ;;
        0b*)
            base=2
            digits=${digits:2}
            ;;
    esac

    digits=${digits//_/}

    for ((i = 0; i < ${#digits}; i++)); do
        digit=$((16#${digits:i:1}))

        if ((value < (limit + digit) / base)); then
            return 1
        fi

        ((value = value * base - digit))
    done

    if ((negative == 0)); then
        ((value = -value))
    fi

    parsed_type=integer
    encode_bytes "$value"
    parsed_value=$encoded_bytes
    return 0
}

parse_scalar() {
    local start=$position
    local token
    local decimal='[+-]?(0|[1-9](_?[0-9])*)'
    local digits='[0-9](_?[0-9])*'
    local exponent="[eE][+-]?${digits}"
    local float="^${decimal}([.]${digits}(${exponent})?|${exponent})$"

    while ((position < document_length)); do
        case "${document:position:1}" in
            ' ' | $'\t' | $'\r' | $'\n' | '#')
                break
                ;;
        esac

        advance_cursor
    done

    if ((position == start)); then
        parse_error="missing value"
        return 1
    fi

    token=${document:start:position-start}

    case "$token" in
        true | false)
            parsed_type=boolean
            ;;
        inf | +inf | -inf)
            parsed_type=float
            token=${token#+}
            ;;
        nan | +nan | -nan)
            parsed_type=float
            token=nan
            ;;
        *)
            if [[ "$token" =~ ^${decimal}$ ||
                  "$token" =~ ^0x[0-9a-fA-F](_?[0-9a-fA-F])*$ ||
                  "$token" =~ ^0o[0-7](_?[0-7])*$ ||
                  "$token" =~ ^0b[01](_?[01])*$ ]]; then
                parse_integer "$token"
                return
            fi

            [[ "$token" =~ $float ]] || return 1
            parsed_type=float
            token=${token//_/}
            token=${token#+}
            ;;
    esac

    encode_bytes "$token"
    parsed_value=$encoded_bytes
    return 0
}

valid_date() {
    local date=$1
    local year=$((10#${date:0:4}))
    local month=$((10#${date:5:2}))
    local day=$((10#${date:8:2}))
    local days=31

    ((month >= 1 && month <= 12)) || return 1

    case "$month" in
        2)
            days=28
            if ((year % 4 == 0 && (year % 100 != 0 || year % 400 == 0))); then
                days=29
            fi
            ;;
        4 | 6 | 9 | 11)
            days=30
            ;;
    esac

    ((day >= 1 && day <= days))
}

parse_date_time() {
    local date_pattern='[0-9]{4}-[0-9]{2}-[0-9]{2}'
    local time_pattern='[0-9]{2}:[0-9]{2}(:[0-9]{2}([.][0-9]+)?)?'
    local offset_pattern='[Zz]|[+-][0-9]{2}:[0-9]{2}'
    local date_time="^(${date_pattern})([Tt ](${time_pattern})(${offset_pattern})?)?"
    local text=${document:position}
    local token date time offset=""
    local hour minute second=0
    local offset_hour offset_minute

    if [[ "$text" =~ $date_time ]]; then
        token=${BASH_REMATCH[0]}
        date=${BASH_REMATCH[1]}
        time=${BASH_REMATCH[3]}
        offset=${BASH_REMATCH[6]}
        valid_date "$date" || return 1

        if [[ -n "$offset" ]]; then
            parsed_type="offset-date-time"
        elif [[ -n "$time" ]]; then
            parsed_type="local-date-time"
        else
            parsed_type="local-date"
        fi
    elif [[ "$text" =~ ^${time_pattern} ]]; then
        token=${BASH_REMATCH[0]}
        time=$token
        parsed_type="local-time"
    else
        return 1
    fi

    if [[ -n "$time" ]]; then
        hour=$((10#${time:0:2}))
        minute=$((10#${time:3:2}))
        if [[ "${time:5:1}" == : ]]; then
            second=$((10#${time:6:2}))
        fi
        ((hour <= 23 && minute <= 59 && second <= 60)) || return 1
    fi

    if [[ "$offset" == [+-]* ]]; then
        offset_hour=$((10#${offset:1:2}))
        offset_minute=$((10#${offset:4:2}))
        ((offset_hour <= 23 && offset_minute <= 59)) || return 1
    fi

    ((position += ${#token}))
    encode_bytes "$token"
    parsed_value=$encoded_bytes
    return 0
}

parse_value() {
    case "${document:position:5}" in
        '"""'* | "'''"*)
            parsed_type=string
            parse_multiline_string
            ;;
        '"'* | "'"*)
            parsed_type=string
            parse_string
            ;;
        [0-9][0-9][0-9][0-9]- | [0-9][0-9]:*)
            parse_date_time
            ;;
        *)
            parse_scalar
            ;;
    esac
}

parse_table_header() {
    local parsed_key=""

    advance_cursor
    skip_whitespace

    parse_bare_key || return 1

    skip_whitespace

    [[ "${document:position:1}" == ']' ]] || return 1

    advance_cursor
    parse_statement_end || return 1

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
    local parsed_type=""
    local value_start value_end

    parse_bare_key || return 1
    skip_whitespace

    [[ "${document:position:1}" == '=' ]] || return 1

    advance_cursor
    skip_whitespace
    value_start=$position
    parse_value || return 1
    value_end=$position
    parse_statement_end || return 1

    encode_bytes "$parsed_key"
    add_node "$parsed_type" "$current_table" "$encoded_bytes" "$parsed_value"
    print_pair "$node_result" "${document:value_start:value_end-value_start}"
    return 0
}

parse_document() {
    local parser
    local parse_error="invalid syntax"

    while ((position < document_length)); do
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
            report_error "$parse_error"
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