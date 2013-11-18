#!/bin/bash
# File: options_parser.sh
# Author: Changsheng Jiang
#
# Copy free, using at your own risk.
#
# options_parser.sh contains some routines for options declaring and
# parsing.
#
# Examples:
#
#   source options_parser.sh
#   OP_add_option "tf|train-file" "train_file" "FILE\nset variable train_file"
#   OP_add_option "input-file" "input_file" "FILE\nset variable input_file"
#   value=0
#   function summation {
#     local op_value op_value_error op_values
#     OP_value_many regex [0-9]+ -- "$@"
#     for l_v in "${op_values[@]}"; do
#       let value+=l_v
#     done
#     return 0
#   }
#   OP_add_option "sum" "OP_func summation" "INT+\ncall sum as take function"
#   OP_add_option "config-file" "OP_func OP_take_config_file" "FILE\nconfig from file"
#   OP_parse --sum 1 2 3 4 --train-file train.log --input-file in.log
#   # now $value=10, $train_file=train.log $input_file=in.log
#   echo "# --config-file FILE will parse every line in FILE as command line, " >>options.conf
#   echo "# and ignore empty lines and lines prefixed by '#'." >>options.conf
#   echo --sum 10 20 30 40 >>options.conf
#   echo --train-file other_train.log >>options.conf
#   OP_parse --config-file options.conf
#   # now $value=110, $train_file=other_train.log
#
#
# There is also a layer to mimic google-gflags's behavior.
#
#   DEFINE_string NAME DEFALT-VALUE DOCUMENT
#   DEFINE_integer NAME DEFALT-VALUE DOCUMENT
#   DEFINE_boolean NAME DEFALT-VALUE DOCUMENT
#   DEFINE_float NAME DEFALT-VALUE DOCUMENT
#
# Coding style:
#
# Names start with OP_ are public. Names start with op_ are private,
# dynamic scope. Names start with l_ are local only.  To embed options
# parser in sub commands, just declare local bash variables
# op_options, op_parse_index and op_parse_error.
#
# Implementation:
#
# Following designs in other languages version, options_parser.sh
# traits every option as three parts, MATCH, TAKE, and DOCUMENT.
#
# MATCH is any function to set op_match_priority in current position
# op_index. op_index is also changed as start position for TAKE
# function. MATCH should return fail if op_match_priority is zero.
#
# TAKE is any function to advance op_index. If failed, set
# op_take_error. op_item_start is also set to the start position,
# i.e. position before call the item's MATCH.
#
# DOCUMENT is a string only, currently.
#
# We can add options by 'OP_add_option MATCH TAKE DOCUMENT'. If
# there're no spaces in MATCH, I'll add a prefix 'OP_match_string ',
# treat MATCH a '|' joined options. To add a MATCH function, we'd
# better add prefix 'OP_func ' to avoid the default prefix. If
# there're no spaces in TAKE, I'll add a prefix 'OP_take_set ', treat
# TAKE as variable name. As MATCH case, to add a function as TAKE,
# prefix it 'OP_func '.

declare -a op_options

OP_MATCH_NONE=0
OP_MATCH_SINGLE=100
OP_MATCH_POSITION=1000
OP_MATCH_PREFIX=10000
OP_MATCH_EXACT=100000

function OP_func {
  "$@"
}

function OP_add_option {
  if [[ $# -eq 3 ]]; then
    op_options+=("$1" "$2" "--$1" "$3")
  else
    op_options+=("$1" "$2" "$3" "$4")
  fi
}

function OP_check_regex {
  local l_regex=$1
  shift
  if [[ "$1" =~ $l_regex ]]; then
    echo "$1"
    return 0
  fi
  return 1
}

function OP_check_regex_sub {
  local l_regex=$1
  local l_sub=$2
  shift 2
  if [[ "$1" =~ $l_regex ]]; then
    echo "${BASH_REMATCH[l_sub]}"
    return 0
  fi
  return 1
}

function OP_check_match {
  OP_check_regex_sub '^-+(.*)' 1 "$@"
}

function OP_check_match_index {
  local l_match_index=$1
  shift
  if test "$op_index" -eq "$l_match_index"; then
    OP_check_match "$1"
  else
    echo "$1"
    return 0
  fi
}

# using variables op_index, op_value and op_value_error
function OP_value {
  local -a l_checks
  while true; do
    case $1 in
      opt):
        l_checks+=("OP_check_regex ^-+")
        shift;;
      noopt):
        l_checks+=("OP_check_regex ^[^-]")
        shift;;
      match):
        l_checks+=(OP_check_match)
        shift;;
      match_index):
        l_checks+=("OP_check_match_index $2")
        shift 2;;
      regex):
        l_checks+=("OP_check_regex $2")
        shift 2;;
      regex-sub):
        l_checks+=("OP_check_regex_sub $2 $3")
        shift 3;;
      --):
        shift
        break;;
      *):
        echo "internal error: OP_value with unkown \$1=$1, do you forget --" >&2
        exit 126
        break;;
    esac
  done
  if test "$op_index" -ge $#; then
    op_value_error="run out of argv"
    return 1
  fi
  local l_argv=("$@")
  local l_value="${l_argv[op_index]}"
  for l_check in "${l_checks[@]}"; do
    local l_check_result
    if ! l_check_result=$($l_check "$l_value"); then
      op_value_error="check failed $l_check $l_value"
      return 1
    fi
    l_value="$l_check_result"
  done
  let op_index++
  op_value="$l_value"
  return 0
}

# using op_index and op_values
function OP_value_many {
  local op_value op_value_error
  while OP_value "$@"; do
    op_values+=("$op_value")
  done
}

# using op_index, op_values
function OP_value_times {
  local l_times=$1
  shift 1
  local op_value op_value_times
  local -a l_values
  local l_start_index=$op_index
  while test ${#l_values[@]} -lt "$l_times"; do
    if ! OP_value "$@"; then
      op_index=$l_start_index
      return 1
    fi
    l_values+=("$op_value")
  done
  op_values+=("${l_values[@]}")
  return 0
}

function OP_value_append {
  local l_dest="$1"
  shift
  if OP_value "$@"; then
    eval "$l_dest+=(\"\${op_value}\")"
    return 0
  fi
  return 1
}

function OP_value_extend {
  local l_dest="$1"
  shift
  local op_values
  if OP_value_many "$@"; then
    eval "$l_dest+=(\"\${op_values[@]}\")"
    return 0
  fi
  return 1
}

function OP_match_string {
  op_match_priority=$OP_MATCH_NONE
  local l_opts=$1
  shift 1
  local -a l_aopts
  IFS="|" read -ra l_aopts <<<"$l_opts"
  local l_start_index=$op_index
  local op_value op_value_error
  if ! OP_value match -- "$@"; then
    return
  fi
  local l_match_arg="$op_value"
  for l_o in "${l_aopts[@]}"; do
    if test x"$l_o" = x"$l_match_arg"; then
      op_match_priority=$OP_MATCH_EXACT
      return
    fi
  done
  for l_o in "${l_aopts[@]}"; do
    if test x"${l_o:0:${#l_match_arg}}" = x"$l_match_arg"; then
      op_match_priority=$OP_MATCH_PREFIX
      return
    fi
  done
}

function OP_match_position {
  local op_value op_value_error l_start=$op_index
  if OP_value noopt -- "$@"; then
    op_match_priority=OP_MATCH_POSITION
    op_index=$l_start
    return 0
  fi
  op_match_priority=$OP_MATCH_NONE
  return 1
}

function OP_take_set_check {
  local l_dest=$1
  shift
  local op_value op_value_error
  if OP_value "$@"; then
    eval $l_dest="\$op_value"
    return 0
  fi
  op_take_error="$op_value_error"
  return 1
}

function OP_take_set {
  local l_dest=$1
  shift
  OP_take_set_check "$l_dest" -- "$@"
}

function OP_take_extend {
  local op_value op_values op_value_error
  if OP_value_extend "$@"; then
    return 0
  fi
  op_take_error="$op_value_error"
  return 1
}

function OP_take_append {
  local op_value op_value_error
  if OP_value_append "$@"; then
    return 0
  else
    op_take_error="$op_value_error"
    return 1
  fi
}

function OP_match_at {
  local l_item_index=$1
  shift
  local l_match="${op_options[l_item_index*4]}"
  if ! [[ "$l_match" =~ " " ]]; then
    l_match="OP_match_string $l_match"
  fi
  local op_match_priority
  $l_match "$@"
  if test x$op_match_priority != x0; then
    op_item_matches+=("$l_item_index $op_index $op_match_priority")
  fi
}

function OP_take_at {
  local l_item_index=$1
  shift
  local l_take="${op_options[l_item_index*4+1]}"
  if ! [[ "$l_take" =~ " " ]]; then
    l_take="OP_take_set $l_take"
  fi
  $l_take "$@"
}

function OP_matches_loop {
  local l_item_index=0
  local op_index="$op_index"
  local l_start_index="$op_index"
  while true; do
    local l_item_off
    (( l_item_off = l_item_index '*' 4 ))
    if test $l_item_off -ge ${#op_options[@]}; then
      break
    fi
    OP_match_at $l_item_index "$@"
    op_index=$l_start_index
    let l_item_index++
  done
}

function OP_matches {
  local -a op_item_matches
  OP_matches_loop "$@"
  local -a l_item_matches
  mapfile -t l_item_matches < <(
    for l_im in "${op_item_matches[@]}"; do
      echo "$l_im"
    done | sort "-t " -k3 -nr
  )
  if test ${#l_item_matches[@]} -eq 0; then
    op_match_error="none"
    return 1
  fi
  local -a first_match
  read -ra first_match <<< ${l_item_matches[0]}
  if test ${#l_item_matches[@]} -ge 2; then
    local -a second_match
    read -ra second_match <<< ${l_item_matches[1]}
    if test ${second_match[2]} -eq ${first_match[2]}; then
      op_match_error="multiple"
      return 1
    fi
  fi
  op_match_item=${first_match[0]}
  op_match_stop=${first_match[1]}
  return 0
}

function OP_help_at {
  local l_item_index=$1
  local l_match="${op_options[$l_item_index*4]}"
  local l_prefix="${op_options[$l_item_index*4+2]}"
  local l_desc="${op_options[$l_item_index*4+3]}"
  [[ -z "$l_prefix" && -z "$l_desc" ]] && return 0
  l_desc=$(
    echo "$l_desc" \
      | sed ': s;/[^\n]$/{s/\n/ /g;N;b s;};s/\\n/\n/g' )
  local l_line
  local -a l_lines
  mapfile -t l_lines < <( echo -e "$l_desc" )
  mapfile -t l_lines < <(
    for l_line in "${l_lines[@]}"; do
      echo $l_line | fmt -s -w60
    done
  )
  echo -n "$l_prefix"
  local l_spaces=20 l_i
  local l_prefix_len=${#l_prefix}
  if test $l_prefix_len -le 18; then
    let l_spaces=20-l_prefix_len
  else
    echo ""
    l_spaces=20
  fi
  for l_line in "${l_lines[@]}"; do
    for (( l_i = 0; l_i < l_spaces; l_i++ )); do
      echo -n " "
    done
    echo "$l_line"
    l_spaces=20
  done
}

function OP_help {
  if [[ -n "$op_description" ]]; then
    echo "$op_description" | fmt -s -w80
    echo
  fi
  local l_item_index=0
  while true; do
    local l_item_off
    (( l_item_off = l_item_index '*' 4 ))
    if test $l_item_off -ge ${#op_options[@]}; then
      break
    fi
    OP_help_at $l_item_index
    let l_item_index++
  done
  exit 1
}

function OP_add_help {
  local l_match="${1:-h|help}"
  local l_help="${2:-show help message}"
  OP_add_option $l_match "OP_func OP_help" "$l_help"
}

function OP_parse {
  op_parse_error=""
  local op_index=0
  op_parse_index=$op_index
  while test "$op_index" -lt "$#"; do
    local op_match_item="" op_match_stop=-1 op_match_error=""
    local op_item_start=$op_index
    if ! OP_matches "$@"; then
      op_parse_error="match-error $op_match_error"
      op_parse_index=$op_index
      return 1
    fi
    let op_index=op_match_stop
    local op_take_error=""
    if ! OP_take_at $op_match_item "$@"; then
      op_parse_error="take-error $op_take_error"
      op_parse_index="$op_index"
      return 1
    fi
  done
  op_parse_index=$op_index
  return 0
}

function OP_parse_all {
  local op_parse_index op_parse_error
  if ! OP_parse "$@"; then
    echo "parse stop @$op_parse_index with error $op_parse_error ..." >&2
    exit 126
  fi
}

function OP_parse_line {
  local op_parse_index
  local -a l_argv
  function op_collect_argv_ {
    l_argv+=("$@")
  }
  eval "op_collect_argv_ $1"
  OP_parse "${l_argv[@]}"
}

function OP_parse_file {
  local -a l_lines
  mapfile -t l_lines < "$1"
  for l_line in "${l_lines[@]}"; do
    if test x"$l_line" = x""; then
      continue
    fi
    if [[ "$l_line" =~ ^# ]]; then
      continue
    fi
    if ! OP_parse_line "$l_line"; then
      op_parse_error="can't parse line($l_line) from file($1), $op_parse_error"
      return 1
    fi
  done
}

function OP_take_config_file {
  local op_value op_value_error
  local op_parse_error
  if OP_value -- "$@"; then
    if ! OP_parse_file "$op_value"; then
      op_take_error="$op_parse_error"
      return 1
    fi
  else
    op_take_error="expect a config file"
    return 1
  fi
}

function op_flags_declare_name {
  local l_fname="FLAGS_$1"
  eval l_is_set="\${$l_fname+xxx}"
  if [ -z "$l_is_set" ]; then
    declare -g $l_fname="$2"
  else
    eval $l_fname="\$2"
  fi
}

function DEFINE_string {
  local l_name="$1"
  op_flags_declare_name "$l_name" "$2"
  local l_doc="$3"
  shift 3
  OP_add_option "$l_name" "FLAGS_$l_name" "STRING\n$l_doc"
}

function DEFINE_integer {
  local l_name="$1"
  op_flags_declare_name "$l_name" "$2"
  local l_doc="$3"
  shift 3
  OP_add_option "$l_name" \
    "OP_take_set_check FLAGS_$l_name regex ^[-+]?[0-9]+$ --" \
    "INTEGER\n$l_doc"
}

function DEFINE_float {
  local l_name="$1"
  op_flags_declare_name "$l_name" "$2"
  local l_doc="$3"
  shift 3
  OP_add_option "$l_name" \
    "OP_take_set_check FLAGS_$l_name regex ^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$ --" \
    "FLOAT\n$l_doc"
}

function OP_take_set_boolean_from_match {
  local l_name="$1"
  shift
  local op_value op_value_error
  local op_index=$op_item_start
  if OP_value match -- "$@"; then
    if [[ "$op_value" =~ ^no- ]]; then
      eval $l_name=0
    else
      eval $l_name=1
    fi
    return 0
  else
    echo "get match failed:$op_value_error ..." >&2
    exit 126
  fi
}

function DEFINE_boolean {
  local l_name="$1"
  op_flags_declare_name "$l_name" "$2"
  local l_doc="$3"
  shift 3
  OP_add_option "$l_name|no-$l_name" \
    "OP_take_set_boolean_from_match FLAGS_$l_name" "$l_doc"
}
