#!/bin/bash
#
# Parse command options in bash.
#
# Every options are treated as matcher, taker and document.
#
# * Matcher
#
# A matcher is a function which sets OP_MATCH_PRIORITY with OP_POSITION and
# returns success or failed code. The largest priority matcher wins. We build
# matcher from match description, or user provided function. The match
# description is the same string we saw in help message, any non options parts
# are ignored.
#
# A matcher starting with '-' is treated as the help description of the matcher,
# for example, '-i, --input-file FILE' will create a matcher which accepts '-i
# file' or '--input-file file'.
#
# * Taker
#
# A taker is a function which sets OP_POSITION. If the given taker looks like a
# variable name, we will assign the next argument to that variable.
#
# * Document
#
# Document is text lines.
#
# * OP::add_option
#
#  OP:add_option "-i, --input-file FILE" input_file "the input file"
#
# Then it accepts '-i file', or '--input-file file', and assigns the variable
# input_file.
#
# This is implemented as
#
# OP::add_option "-i, -input-file FILE" \
#  'OP::set_value input_file OP::value --' \
#  "The input file"
#
# In some case, user could define a new value function, like we do in
# OP::set_value, for example:
#
#   declare -a files
#   function append_existing_file() {
#     local OP_VALUE
#     # Consumes the next argument and assigns it to OP_VALUE.
#     OP::value -- "$@" || return 1
#     # Check the file exists.
#     [[ -f "$OP_VALUE" ]] || {
#       OP::error "The file '$OP_VALUE' does not exist ..."
#       return 1
#     }
#     files+=( $OP_VALUE )
#   }
#
# And it could be used as
#
#   OP::add_option "-i, --input-file FILE" "OP::func append_existing_file" "doc ..."
#
#
# * Flags
#
#  DEFINE_string input_file "" "the input file"
#
# This will accept '--input_file file' and assign FLAGS_input_file.
#
#  DEFINE_string "-i, --input-file FILE" "" "the input file"
#
# This will accept '--input-file file' and assign FLAGS_input_file.
#
# * Test
#
# This file contains test code, and has been tested with bash version 4.3. The
# test code could be run as:
#
#   bash options_parser.sh OP::Test
#
# Or
#
#   bash options_parser.sh OP::Test <test cases>...
#
#
# * Copyleft
#
# Wrote by Changsheng Jiang(jiangzuoyan@gmail.com), use it at your own risk.
#

if declare -F OP::parse_all >/dev/null; then
  return
fi

declare -a OP_OPTIONS

OP_MATCH_NONE=0
OP_MATCH_SINGLE=100
OP_MATCH_POSITION=1000
OP_MATCH_PREFIX=10000
OP_MATCH_EXACT=100000

OP_COLOR_RED="$(echo -e '\e[0;31m')"
OP_COLOR_RESET="$(echo -e '\e[0m')"

function OP::quote_arg() {
  if [[ "$1" =~ \  || -z "$1" ]] ; then
    echo -n "'$1'"
  else
    printf '%s' "$1"
  fi
}

function OP::print_args() {
  local l_x=0
  for arg in "$@"; do
    if test $l_x -gt 0; then
      echo -n " "
    fi
    let ++l_x
    OP::quote_arg "$arg"
  done
}

function OP::print_log() {
  local l_location=$1
  local l_severity=$2
  shift 2
  {
    if [[ $l_severity =~ W|E|F ]]; then
      echo -n "$OP_COLOR_RED"
    fi
    echo -n "$l_severity"
    printf "%(%s)T %s]" -1 "$l_location"
    OP::print_args "$@"
    if [[ $l_severity =~ W|E|F ]]; then
      echo -n "$OP_COLOR_RESET"
    fi
    echo
  } >&2
}

function OP::print_log_lines() {
  local l_location=$1
  local l_severity=$2
  shift 2
  for arg in "$@"; do
    OP::print_log "$l_location" "$l_severity" "$arg"
  done
}

function OP::log() {
  local l_location="$1"
  shift
  if [[ $l_location =~ ^[0-9]+$ ]]; then
    let ++l_location
    l_location="$(OP::get_frame $l_location)"
  fi
  OP::print_log "$l_location" "$@"
}

function OP::info() {
  local l_location=1
  if [[ $1 =~ "--log-location" ]]; then
    l_location="$2"
    shift 2
  fi
  OP::log "$l_location" I "$@"
}

function OP::error() {
  local l_location=1
  if [[ $1 =~ "--log-location" ]]; then
    l_location="$2"
    shift 2
  fi
  OP::log "$l_location" E "$@"
}

function OP::fatal() {
  local l_location=1
  if [[ $1 =~ "--log-location" ]]; then
    l_location="$2"
    shift 2
  fi
  if [[ $l_location =~ ^[0-9]+$ ]]; then
    l_location="$(OP::get_frame $l_location)"
  fi
  OP::print_log "$l_location" F "$@"
  OP::print_log "$l_location" F "Traceback"
  OP::traceback "$l_location" 1
  exit 1
}

function OP::traceback() {
  local l_location="$1"
  local l_n="$2"
  shift 2
  let ++l_n
  local l_f
  while l_f="$(OP::get_frame $l_n)"; do
    let ++l_n
    OP::print_log "$l_location" E "$l_f"
  done
}

function OP::get_frame() {
  local -ri l_i=${1:-0}
  local IFS=$' \t\n'
  local -a l_frames=( $(caller ${l_i}) )
  if [[ ${#l_frames[@]} == 0 ]]; then
    return 1
  fi
  local l_line="${l_frames[0]}"
  local l_func="${l_frames[1]}"
  local l_file="$(basename ${l_frames[2]})"
  echo -n "${l_file}:${l_line} ${l_func}"
}

# OP::print_args_position POSITION ARGS...
function OP::print_args_position() {
  local l_index l_offset
  OP::split_position l_index l_offset "$1"
  shift
  local l_x=0
  for arg in "$@"; do
    if test $l_x -gt 0; then
      echo -n " "
    fi
    if test $l_x -eq $l_index; then
      OP::quote_arg "${arg:0:l_offset}"
      echo -n "^^^^^"
      OP::quote_arg "${arg:l_offset}"
    else
      OP::quote_arg "$arg"
    fi
    let ++l_x
  done
}

function OP::assign() {
  local -n l_name_fe3f787b_ff87_4a00_8776_a5377f5bfe7f="$1"
  l_name_fe3f787b_ff87_4a00_8776_a5377f5bfe7f="$2"
}

function test::OP::assign() {
  local name
  expect OP::assign name value
  expect_equal "$name" "value"
}

function OP::append() {
  local -n l_name_221a90e4_26c5_4bf8_8a1d_d3f2d8994ae2="$1"
  shift
  l_name_221a90e4_26c5_4bf8_8a1d_d3f2d8994ae2+=( "$@" )
}

function test::OP::append() {
  local name=( pa pb )
  expect OP::append name a b c
  expect_equal "${name[*]}" "pa pb a b c"
}

function OP::assign_list() {
  local -n l_name_a5c1a89e_c0ec_4052_835c_b39ca197003d="$1"
  shift
  l_name_a5c1a89e_c0ec_4052_835c_b39ca197003d=( "$@" )
}

function test::OP::assign_list() {
  local name=( pa pb )
  expect OP::assign_list name a b c
  expect_equal "${name[*]}" "a b c"
}

# struct lenarr
#
#  <size> <length-0> x x x ...
#         <length-1> x x x ...
#         ...
#
# Every compound element inside the array is encoded as
#
#   <element-length> <attr-length-0> <attr-0> x x x ...
#                    <attr-length-1> <attr-1> x x x ...
#                    ...


# OP::lenarr_append array args...
#
# Append the element args into the array.
function OP::lenarr_append() {
  local -n l_array_684bcd7a_a7c2_46bc_b705_5a4eeed8526b=$1
  shift
  if test ${#l_array_684bcd7a_a7c2_46bc_b705_5a4eeed8526b[@]} -eq 0; then
    l_array_684bcd7a_a7c2_46bc_b705_5a4eeed8526b=( 0 )
  fi
  local l_n=$#
  let ++l_n
  l_array_684bcd7a_a7c2_46bc_b705_5a4eeed8526b+=( $l_n "$@" )
  let ++l_array_684bcd7a_a7c2_46bc_b705_5a4eeed8526b[0]
}

# OP::lenarr_at array pos dest
#
# Get sub array at position, and assign to the dest.
function OP::lenarr_at() {
  local -n l_array_ddb0a631_ed7f_4488_bb25_82416b09ecb1="$1"
  local l_pos="$2"
  local l_dest="$3"
  local l_len=${l_array_ddb0a631_ed7f_4488_bb25_82416b09ecb1[l_pos]}
  OP::assign_list "$l_dest" "${l_array_ddb0a631_ed7f_4488_bb25_82416b09ecb1[@]:l_pos+1:l_len-1}"
}

# OP::lenarr_getattr array pos attr dest
#
# Get attribute from an array, and assign the attribute into dest.
function OP::lenarr_getattr() {
  local -n l_array_cfbb8758_e637_4e0c_82c7_9df5956853be=$1
  local l_pos="$2"
  local l_attr="$3"
  local l_dest="$4"
  local l_len=${l_array_cfbb8758_e637_4e0c_82c7_9df5956853be[l_pos]}
  local l_off=1
  while [[ $l_off -lt $l_len ]] ; do
    local l_n=${l_array_cfbb8758_e637_4e0c_82c7_9df5956853be[l_pos+l_off]}
    local l_a=${l_array_cfbb8758_e637_4e0c_82c7_9df5956853be[l_pos+l_off+1]}
    if test "$l_a" = "$l_attr"; then
      let l_pos+=l_off+2
      let l_n-=2
      OP::assign_list "$l_dest" "${l_array_cfbb8758_e637_4e0c_82c7_9df5956853be[@]:l_pos:l_n}"
      return 0
    fi
    let l_off+=l_n
  done
  return 1
}

function OP::lenarr_next() {
  local -n l_array_10dd587d_204a_4537_941b_88fd9453ec60=$1
  local l_pos=$2
  if [[ $l_pos -ge ${#l_array_10dd587d_204a_4537_941b_88fd9453ec60[@]} ]] ; then
    return 1
  fi
  if [[ $l_pos -eq 0 ]]; then
    echo 1
    return 0
  fi
  local l_num=${l_array_10dd587d_204a_4537_941b_88fd9453ec60[l_pos]}
  let l_pos+=l_num
  if [[ $l_pos -ge ${#l_array_10dd587d_204a_4537_941b_88fd9453ec60[@]} ]] ; then
    return 1
  fi
  echo $l_pos
}

# OP::options_next pos
function OP::options_next() {
  OP::lenarr_next OP_OPTIONS $1
}

function OP::options_append() {
  OP::lenarr_append OP_OPTIONS "$@"
}

# OP::options_get pos :attr dest
#
# print position
function OP::options_get() {
  OP::lenarr_getattr OP_OPTIONS "$1" "$2" "$3" || {
    OP::fatal "Get options attribute $2 at position $1 failed"
  }
}

# Usage:
#  OP::add_option
#  OP::add_option matcher taker doc
#
# This also consumes the array variables OP_MATCHER, OP_TAKER and OP_DOC.
#
# Warning: The match and take func are called without quotes.
#
# Example:
#
#  OP::add_option "-h, --help" "OP::func OP::help" "Show help messages"
#  OP::add_option "-t, --train-file FILE" "FLAGS_train_file" "Set train file"
#  OP::add_option "-c, --check-file FILE" "FLAGS_check_file" "Set check file"
#
# Used variables: OP_OPTIONS OP_MATCHER OP_TAKER OP_DOC
function OP::add_option() {
  local -a l_matcher l_taker l_doc
  l_matcher=( "${OP_MATCHER[@]}" )
  l_taker=( "${OP_TAKER[@]}" )
  l_doc=( "${OP_DOC[@]}" )
  OP_MATCHER=()
  OP_TAKER=()
  OP_DOC=()
  local l_taker_set_name=""
  while [[ $# -gt 0 ]] ; do
    local l_arg=$1
    shift
    if [[ ${#l_matcher[@]} -eq 0 ]] ; then
      if [[ $l_arg =~ ^- ]] ; then
        l_matcher=( OP::match_description "$l_arg" )
        if [[ ${#l_doc[@]} -eq 0 ]] ; then
          l_doc+=( "$l_arg" )
        fi
      else
        l_matcher=( $l_arg )
      fi
      continue
    fi
    if [[ ${#l_taker[@]} -eq 0 ]] ; then
      if [[ $l_arg =~ \  ]] ; then
        l_taker=( $l_arg )
      else
        l_taker=( OP::set_value "$l_arg" OP::value -- )
        l_taker_set_name="$l_arg"
      fi
      continue
    fi
    l_doc+=( "$l_arg" )
  done
  if test -n "$l_taker_set_name"; then
    l_doc+=( "Default: ${!l_taker_set_name}" )
  fi
  local l_nm l_nt l_nd
  let l_nm=${#l_matcher[@]}+2
  let l_nt=${#l_taker[@]}+2
  let l_nd=${#l_doc[@]}+2
  OP::options_append $l_nm :matcher "${l_matcher[@]}" \
    $l_nt :taker "${l_taker[@]}" \
    $l_nd :doc "${l_doc[@]}"
}

# Define the matcher for next OP::add_option.
function OP::matcher() {
  OP_MATCHER=( "$@" )
}

# Define the doc for next OP::add_option.
function OP::doc() {
  OP_DOC=( "$@" )
}

# Define the taker for next OP::add_option.
function OP::taker() {
  OP_TAKER=( "$@" )
}

function test::OP::options() {
  OP_OPTIONS=( 2 11 3 :matcher m1 4 :taker t1a t1b 3 :doc d1 10 4 :matcher m2a m2b 5 :taker t2a t2b t2c )
  local l_pos=0
  l_pos=$( OP::options_next 0 )
  expect_equal "$l_pos" 1
  l_pos=$( OP::options_next 1 )
  expect_equal "$l_pos" 12
  expect_equal ${OP_OPTIONS[12]} 10
  expect_fail OP::options_next 12

  local -a tmp
  expect OP::options_get 1 :matcher tmp
  expect_equal "${tmp[*]}" "m1"

  expect OP::options_get 1 :taker tmp
  expect_equal "${tmp[*]}" "t1a t1b"

  expect OP::options_get 1 :doc tmp
  expect_equal "${tmp[*]}" "d1"

  expect OP::options_get 12 :matcher tmp
  expect_equal "${tmp[*]}" "m2a m2b"

  expect OP::options_get 12 :taker tmp
  expect_equal "${tmp[*]}" "t2a t2b t2c"

  local -a OP_OPTIONS_check=( ${OP_OPTIONS[@]} )
  OP_OPTIONS=( )

  OP::options_append 3 :matcher m1 4 :taker t1a t1b 3 :doc d1
  OP::options_append 4 :matcher m2a m2b 5 :taker t2a t2b t2c
  assert_equal ${#OP_OPTIONS[@]}  ${#OP_OPTIONS_check[@]}
  expect_equal "${OP_OPTIONS[*]}" "${OP_OPTIONS_check[*]}"
}

function OP::func() {
  "$@"
}

# OP::starts_with string prefix
#
# Return 0 iff the string starts with prefix.
function OP::starts_with() {
  local l_str="$1"
  local l_prefix="$2"
  if [ "${l_str:0:${#l_prefix}}" == "$l_prefix" ]; then
    return 0
  fi
  return 1
}

function test::OP::starts_with() {
  expect OP::starts_with "hello-world" "hello"
  expect_fail OP::starts_with "hello-world" "Hello"
}

# OP::split array-first array-second SEP arg... SEP more...
#
# Append the first and second parts into first, second respectively.
function OP::split() {
  local l_first_27e50b64_9b8d_441d_9040_b32f4b7d207a="$1"
  local l_second_27e50b64_9b8d_441d_9040_b32f4b7d207a="$2"
  local l_sep_27e50b64_9b8d_441d_9040_b32f4b7d207a="$3"
  shift 3
  while [[ $# -gt 0 ]] ; do
    local l_arg_27e50b64_9b8d_441d_9040_b32f4b7d207a="$1"
    shift
    if [[ "$l_arg_27e50b64_9b8d_441d_9040_b32f4b7d207a" == "$l_sep_27e50b64_9b8d_441d_9040_b32f4b7d207a" ]]; then
      break
    fi
    OP::append $l_first_27e50b64_9b8d_441d_9040_b32f4b7d207a "$l_arg_27e50b64_9b8d_441d_9040_b32f4b7d207a"
  done
  OP::append $l_second_27e50b64_9b8d_441d_9040_b32f4b7d207a "$@"
}

function test::OP::split() {
  local -a l_first
  local -a l_second
  expect OP::split l_first l_second --sep a b -- c --sep d e
  expect_equal "${#l_first[@]}" 4
  expect_equal "${#l_second[@]}" 2
  expect_equal "${l_first[*]}" "a b -- c"
  expect_equal "${l_second[*]}" "d e"
}

# OP::before --sep func ... --sep ARGS...
#
# Run func before ARGS....
#
# The used variables are depends on func and ARGS.
function OP::before() {
  local -a l_func_7012eab5_4ecb_4cdc_bfb3_1c655259e340
  local -a l_rest_7012eab5_4ecb_4cdc_bfb3_1c655259e340
  OP::split l_func_7012eab5_4ecb_4cdc_bfb3_1c655259e340 l_rest_7012eab5_4ecb_4cdc_bfb3_1c655259e340 "$@"
  if "${l_func_7012eab5_4ecb_4cdc_bfb3_1c655259e340[@]}"; then
    "${l_rest_7012eab5_4ecb_4cdc_bfb3_1c655259e340[@]}"
  else
    return 1
  fi
}

# OP::after --sep func ... --sep ARGS...
#
# Run func after ARGS... successes.
#
# The used variables are depends on func and ARGS.
function OP::after() {
  local -a l_func_bed5eeca_64a3_4b10_8ba6_90f1faf290e7
  local -a l_rest_bed5eeca_64a3_4b10_8ba6_90f1faf290e7
  OP::split l_func_bed5eeca_64a3_4b10_8ba6_90f1faf290e7 l_rest_bed5eeca_64a3_4b10_8ba6_90f1faf290e7 "$@"
  if "${l_rest_bed5eeca_64a3_4b10_8ba6_90f1faf290e7[@]}"; then
    "${l_func_bed5eeca_64a3_4b10_8ba6_90f1faf290e7[@]}"
  else
    return 1
  fi
}

# OP::split_position index-name offset-name position
function OP::split_position() {
  OP::assign $1 "$3"
  OP::assign $2 0
  if [[ $3 =~ ([0-9]+)-([0-9]+) ]] ; then
    OP::assign $1 "${BASH_REMATCH[1]}"
    OP::assign $2 "${BASH_REMATCH[2]}"
  fi
}

function test::OP::split_position() {
  local l_index l_offset

  expect OP::split_position l_index l_offset 13
  expect_equal "$l_index" 13
  expect_equal "$l_offset" 0

  expect OP::split_position l_index l_offset 14-17
  expect_equal "$l_index" 14
  expect_equal "$l_offset" 17
}

# Check the current position is an option.
#
# Used variables: OP_VALUE OP_VALUE_START_POSITION OP_POSITION
function OP::value_check_is_option() {
  local l_start_index l_start_offset
  OP::split_position l_start_index l_start_offset $OP_VALUE_START_POSITION
  if [[ $l_start_offset -gt 0 ]] ; then
    return 1
  fi
  if [[ "$OP_VALUE" =~ ^-+[^' '=]+ ]]; then
    return 0
  fi
  return 1
}

function OP::value_check_non_option() {
  if ! OP::value_check_is_option >/dev/null; then
    return 0
  fi
  return 1
}

function OP::value_check_regex() {
  if [[ "$OP_VALUE" =~ $1 ]]; then
    return 0
  fi
  return 1
}

function OP::value_check_bool() {
  if [[ "$OP_VALUE" =~ ^(t|true|True|TRUE|1)$ ]]; then
    OP_VALUE=1
    return 0
  elif [[ "$OP_VALUE" =~ ^(f|false|False|FALSE|0)$ ]]; then
    OP_VALUE=0
    return 0
  fi
  return 1
}

function OP::value_check_ne() {
  local l_value="$1"
  if [[ "$OP_VALUE" == "$l_value" ]]; then
    return 1
  fi
  return 0
}

function OP::value_check_eq() {
  local l_value="$1"
  if [[ "$OP_VALUE" == "$l_value" ]]; then
    return 0
  fi
  return 1
}

# OP::value checks... -- ARG...
#
# Run checks one by one over argument at position OP_POSITION, and set OP_VALUE,
# or OP_VALUE_ERROR respectively. The value is initialized original arguments,
# and folded by all checks in order. First error check will stop the folding.
#
# Used variables: OP_POSITION, OP_VALUE and OP_VALUE_ERROR.
#
# OP_POSITION is a integer, or integer '-' offset
function OP::value() {
  local -a l_checks
  local l_optional=0 l_optional_value
  while true; do
    case $1 in
      --):
        shift
        break;;
      "is-option"):
        OP::lenarr_append l_checks OP::value_check_is_option
        shift;;
      "non-option"):
        OP::lenarr_append l_checks OP::value_check_non_option
        shift;;
      optional):
        l_optional=1
        l_optional_value="$2"
        shift 2;;
      regex):
        OP::lenarr_append l_checks OP::value_check_regex "$2"
        shift 2;;
      bool):
        OP::lenarr_append l_checks OP::value_check_bool
        shift;;
      string):
        shift;;
      ne):
        OP::lenarr_append l_checks OP::value_check_ne "$2"
        shift 2;;
      eq):
        OP::lenarr_append l_checks OP::value_check_eq "$2"
        shift 2;;
      integer):
        OP::lenarr_append l_checks OP::value_check_regex '^[-+]?[0-9]+$'
        shift;;
      float):
        OP::lenarr_append l_checks OP::value_check_regex '^[-+]?[0-9]*\.?[0-9]*([eE][-+]?[0-9]+)?$'
        shift;;
      "OP::func .*"):
        OP::lenarr_append l_checks $1
        shift;;
      *):
        OP::fatal "OP::value got unkown check/modifier '$1', do you forget --"
        return 1
        break;;
    esac
  done
  local OP_VALUE_START_POSITION="$OP_POSITION"
  local l_index l_offset
  OP::split_position l_index l_offset $OP_POSITION
  if [[ $l_index -lt $# ]]; then
    if [[ $l_optional == 0 || $l_offset -gt 0 ]]; then
      let ++l_index
      OP_VALUE="${!l_index}"
      OP_VALUE=${OP_VALUE:${l_offset}}
      l_offset=0
      OP_POSITION=$l_index-0
    else
      OP_VALUE="${l_optional_value}"
    fi
  elif [[ $l_optional == 1 ]]; then
    OP_VALUE="$l_optional_value"
  else
    OP_VALUE_ERROR="run out of argv"
    return 1
  fi
  local l_check_pos=0
  local -a l_check_args
  while l_check_pos=$(OP::lenarr_next l_checks $l_check_pos); do
    OP::lenarr_at l_checks $l_check_pos l_check_args
    OP_VALUE_ERROR=""
    if ! "${l_check_args[@]}"; then
      OP_VALUE_ERROR="check failed check=${l_check_args[*]} value=$OP_VALUE with error $OP_VALUE_RROR"
      OP_POSITION=$OP_VALUE_START_POSITION
      return 1
    fi
  done
  return 0
}

function test::OP::value() {
  local OP_VALUE OP_VALUE_ERROR OP_POSITION

  OP_POSITION=0-0
  expect OP::value -- -a -b
  expect_equal "$OP_VALUE" "-a"
  expect_equal "$OP_POSITION" "1-0"

  expect OP::value -- -a -b
  expect_equal "$OP_VALUE" "-b"
  expect_equal "$OP_POSITION" "2-0"

  expect_fail OP::value -- -a -b
  expect_equal "$OP_POSITION" "2-0"

  OP_POSITION=0-0
  expect OP::value is-option -- -a b
  expect_equal "$OP_VALUE" "-a"
  expect_equal "$OP_POSITION" "1-0"

  OP_POSITION=0-0
  expect_fail OP::value is-option -- abc
  expect_equal "$OP_POSITION" "0-0"

  OP_POSITION=0-0
  expect OP::value -- abcd
  expect_equal "$OP_VALUE" abcd
  expect_equal "$OP_POSITION" "1-0"

  OP_POSITION=0-2
  expect_fail OP::value is-option -- -a=b
  expect_equal "$OP_POSITION" "0-2"

  OP_POSITION=0-3
  expect OP::value non-option -- -a=b
  expect_equal "$OP_VALUE" "b"
  expect_equal "$OP_POSITION" "1-0"

  OP_POSITION=0-0
  expect OP::value bool -- t
  expect_equal "$OP_VALUE" "1"
  expect_equal "$OP_POSITION" "1-0"

  OP_POSITION=0-0
  expect OP::value bool -- true
  expect_equal "$OP_VALUE" "1"
  expect_equal "$OP_POSITION" "1-0"

  OP_POSITION=0-0
  expect OP::value bool -- f
  expect_equal "$OP_VALUE" "0"
  expect_equal "$OP_POSITION" "1-0"

  OP_POSITION=0-0
  expect OP::value bool -- false
  expect_equal "$OP_VALUE" "0"
  expect_equal "$OP_POSITION" "1-0"

  OP_POSITION=0-0
  expect OP::value optional a -- b
  expect_equal "$OP_VALUE" a
  expect_equal "$OP_POSITION" "0-0"

  OP_POSITION=0-1
  expect OP::value optional a -- arg
  expect_equal "$OP_VALUE" rg
  expect_equal "$OP_POSITION" "1-0"
}

# This invokes it args again and again, until it failed, using OP_VALUE, and
# array OP_VALUES as results.
#
# OP::value_times min-times max-times args...
#
# Used variables: OP_POSITION OP_VALUE_ERROR OP_VALUE OP_VALUES(array).
#
# This assumes max-times is positive, and min-times is less than or equal to
# max-times.
function OP::value_times() {
  local l_times=0
  local l_min_times=$1
  local l_max_times=$2
  shift 2
  local l_start_index=$OP_POSITION
  local l_succ_index=$OP_POSITION
  while "$@"; do
    OP_VALUES+=("$OP_VALUE")
    let l_times++
    l_succ_index=$OP_POSITION
    if test $l_times -ge $l_max_times; then
      break
    fi
  done
  if test $l_times -lt $l_min_times; then
    OP_VALUE_ERROR="expect at least $l_min_times, only got $l_times"
    OP_POSITION=l_saved_index
    return 1
  fi
  OP_VALUE_ERROR=""
  OP_POSITION=$l_succ_index
  return 0
}

# Call OP::value_times 0 large-int ...
function OP::value_many() {
  OP::value_times 0 1073741824 "$@"
}

function test::OP::value_many() {
  OP_POSITION=0-0
  expect OP::value_many OP::value regex '^[0-9]+$' -- 12 34 ab 56
  OP_VALUE="${OP_VALUES[@]}"
  expect_equal "$OP_VALUE" "12 34"
  expect_equal "$OP_POSITION" "2-0"

  OP_POSITION=0-0
  OP_VALUES=()
  expect OP::value_many OP::value regex '^[0-9]+$' -- -10 11
  OP_VALUE="${OP_VALUES[@]}"
  expect_equal "$OP_VALUE" ""
  expect_equal "$OP_POSITION" "0-0"

  OP_POSITION=0-0
  OP_VALUES=()
  expect OP::value_many OP::value regex '^-?[0-9]+$' -- -10 12 1a 2b
  OP_VALUE="${OP_VALUES[@]}"
  expect_equal "$OP_VALUE" "-10 12"
  expect_equal "$OP_POSITION" "2-0"
}

# OP::set_value name
#
# Used variables: OP_VALUE
function OP::set_value() {
  local OP_VALUE
  local l_name_b10a728c_7a60_464f_8615_9c2649510db4="$1"
  shift
  if [[ $# -gt 0 ]]; then
    "$@" || return 1
  fi
  OP::assign "$l_name_b10a728c_7a60_464f_8615_9c2649510db4" "$OP_VALUE"
}

function test::OP::set_value() {
  OP_POSITION=0-0
  OP::set_value var_name OP::value -- a-value b c

  expect_equal "$var_name" a-value
  expect_equal "$OP_POSITION" 1-0

  OP::set_value var_name OP::value -- a-value b c

  expect_equal "$var_name" b
  expect_equal "$OP_POSITION" 2-0

  OP::set_value var_name OP::value -- a-value b c

  expect_equal "$var_name" c
  expect_equal "$OP_POSITION" 3-0

  expect_fail OP::after -- OP::set_value var_name -- OP::value -- a-value b c
}


# OP::value_append name
#
# Used variables: OP_VALUE
function OP::append_value() {
  local OP_VALUE
  local l_name_="$1"
  shift
  if [[ $# -gt 0 ]]; then
    "$@" || return 1
  fi
  OP::append "$l_name_" "$OP_VALUE"
}

function test::OP::append_value() {
  local l_name=(pa pb)
  OP_POSITION=0-0
  OP::append_value l_name OP::value -- a b c
  expect_equal "${l_name[*]}" "pa pb a"
}

# OP::append_values name
#
# Used variables: OP_VALUES
function OP::append_values() {
  local -a OP_VALUES
  local l_name="$1"
  shift
  if [[ $# -gt 0 ]]; then
    "$@" || return 1
  fi
  OP::append "$l_name" "${OP_VALUES[@]}"
}

# OP::split_match_description array description...
function OP::split_match_description() {
  local l_name="$1"
  shift
  OP::assign_list "$l_name" $(printf %s "$@" | sed 's/[^-a-zA-Z0-9._]/ /g;s/ [^- ][^ ]*//g' )
}

function test::OP::split_match_description() {
  for arg in "-f, --train-file FILE" "-f <input file> --train-file <input file>" "-f <input-file-name> --train-file[=FILE]"; do
    OP::split_match_description options "$arg"
    expect_equal "${#options[@]}" 2 splitting "$arg"
    expect_equal "${options[*]}" "-f --train-file" spliting "$arg"
  done

  for arg in "--train-file=FILE" "--train-file=<input file>" "--train-file[=FILE]"; do
    OP::split_match_description options "$arg"
    expect_equal "${#options[@]}" 1 splitting "$arg"
    expect_equal "${options[*]}" "--train-file" splitting "$arg"
  done
}

# OP::match_description match-description ARGV...
#
# Usage:
#  OP::match_description -h, --help --help
#  OP::match_description -f, --file FILE --file FILE
#  OP::match_description -f FILE --file FILE   --file FILE
#
# Returns match priority in variable OP_MATCH_PRIORITY, and step OP_POSITION
# accordingly.
#
# Used variables: OP_POSITION OP_MATCH_PRIORITY
function OP::match_description() {
  OP_MATCH_PRIORITY=$OP_MATCH_NONE
  local l_description="$1"
  shift
  local l_opt
  local -a l_opts
  OP::split_match_description l_opts "${l_description}"
  local l_index l_offset
  OP::split_position l_index l_offset $OP_POSITION
  if test $l_offset -gt 0; then
    return 1
  fi
  local l_start_position=$OP_POSITION
  local OP_VALUE OP_VALUE_ERROR
  if ! OP::value -- "$@"; then
    return 1
  fi
  if [[ $OP_VALUE =~ ^-*$ ]]; then
    return 1
  fi
  if [[ "$OP_VALUE" =~ ^(-+[^=]*)= ]] ; then
    OP_VALUE=${BASH_REMATCH[1]}
    l_offset=${#OP_VALUE}
    let ++l_offset
    OP_POSITION=$l_index-$l_offset
  fi
  for l_opt in "${l_opts[@]}"; do
    if test x"${OP_VALUE}" = x"$l_opt"; then
      OP_MATCH_PRIORITY=$OP_MATCH_EXACT
      return 0
    fi
  done
  for l_opt in "${l_opts[@]}"; do
    if OP::starts_with "$l_opt" "${OP_VALUE}"; then
      OP_MATCH_PRIORITY=$OP_MATCH_PREFIX
      return 0
    fi
  done
  for l_opt in "${l_opts[@]}"; do
    if [[ "$l_opt" =~ ^-[^-' ']$ ]] ; then
      if OP::starts_with "$OP_VALUE" "$l_opt"; then
        OP_VALUE="$l_opt"
        OP_POSITION=$l_index-2
        OP_MATCH_PRIORITY=$OP_MATCH_SINGLE
        return 0
      fi
    fi
  done
  return 1
}

function test::OP::match_description() {
  OP_POSITION=0
  expect OP::match_description "--tf, --train-file FILE" --train-file train.log
  expect_equal $OP_MATCH_PRIORITY $OP_MATCH_EXACT
  expect_equal $OP_POSITION 1-0

  OP_POSITION=0
  expect OP::match_description "--tf FILE --train-file FILE" --train train.log
  expect_equal $OP_MATCH_PRIORITY $OP_MATCH_PREFIX
  expect_equal $OP_POSITION 1-0

  OP_POSITION=0
  expect OP::match_description "-f FILE --train-file FILE" -f train.log
  expect_equal $OP_MATCH_PRIORITY $OP_MATCH_EXACT
  expect_equal $OP_POSITION 1-0

  OP_POSITION=0
  expect OP::match_description "-f FILE --train-file FILE" --train-file=train.log
  expect_equal $OP_MATCH_PRIORITY $OP_MATCH_EXACT
  expect_equal $OP_POSITION 0-13

  OP_POSITION=0
  expect OP::match_description "-f FILE --train-file=FILE" --train-file=train.log
  expect_equal $OP_MATCH_PRIORITY $OP_MATCH_EXACT
  expect_equal $OP_POSITION 0-13

  OP_POSITION=0
  expect_fail OP::match_description "-f FILE --train-file FILE" --train-files train.log

  OP_POSITION=0
  expect_fail OP::match_description "-f FILE --train-file FILE" --f train.log

  OP_POSITION=0
  expect_fail OP::match_description "-f FILE --train-file FILE" -train train.log

  OP_POSITION=0
  expect_fail OP::match_description "-f" -

  OP_POSITION=0
  expect_fail OP::match_description "-f" --

  OP_POSITION=0
  expect_fail OP::match_description "--f" --
}

# Private function.
#
# OP::call_matcher_at item-index "$@"
#
# Used variables: OP_POSITION OP_ITEM_MATCHES
#
# OP_ITEM_MATCHES is an array of (match_priority:the option pos in OP_OPTIONS:OP_POSITION)...
function OP::call_matcher_at() {
  local l_option_pos=$1
  shift
  local -a l_matcher
  OP::options_get $l_option_pos :matcher l_matcher
  local OP_MATCH_PRIORITY OP_VALUE OP_VALUES
  if "${l_matcher[@]}" "$@"; then
    OP_ITEM_MATCHES+=("$OP_MATCH_PRIORITY:$l_option_pos:$OP_POSITION")
  fi
}

# Private function.
#
# OP::call_taker_at item-index "$@"
#
# Used variables: OP_TAKE_ERROR OP_POSITION OP_VALUE OP_VALUES OP_VALUE_ERROR
function OP::call_taker_at() {
  local l_option_pos=$1
  shift
  local -a l_taker
  OP::options_get $l_option_pos :taker l_taker
  local OP_VALUE OP_VALUE_ERROR
  local -a OP_VALUES
  if "${l_taker[@]}" "$@"; then
    return 0
  fi
  if [[ -z "$OP_TAKE_ERROR" ]]; then
    OP_TAKE_ERROR="$OP_VALUE_ERROR"
  fi
  return 1
}

function OP::call_all_matchers() {
  local l_option_pos=0
  local OP_POSITION="$OP_POSITION"
  local l_start_arg="$OP_POSITION"
  local OP_VALUE OP_VALUES OP_VALUE_ERROR
  while l_option_pos=$(OP::options_next $l_option_pos); do
    OP::call_matcher_at $l_option_pos "$@"
    OP_POSITION=$l_start_arg
  done
}

# Used variables: OP_MATCH_ERROR OP_MATCH_ITEM OP_MATCH_STOP
function OP::find_best_match() {
  local -a OP_ITEM_MATCHES
  OP::call_all_matchers "$@"
  read -a OP_ITEM_MATCHES < <( echo ${OP_ITEM_MATCHES[@]} | sed 's/ /\n/g' | sort -rn )
  if test ${#OP_ITEM_MATCHES[@]} -eq 0; then
    OP_MATCH_ERROR="none"
    return 1
  fi
  # priority, item index, OP_POSITION
  local -a first_match
  IFS=: read -a first_match <<< "${OP_ITEM_MATCHES[0]}"
  if test ${#l_item_matches[@]} -ge 2; then
    local -a second_match
    IFS=: read -a second_match <<< "${OP_ITEM_MATCHES[1]}"
    if test ${second_match[0]} -eq ${first_match[0]}; then
      OP_MATCH_ERROR="multiple"
      return 1
    fi
  fi
  OP_MATCH_ITEM=${first_match[1]}
  OP_MATCH_STOP=${first_match[2]}
  return 0
}

function OP::help_at() {
  local l_option_pos=$1
  shift
  local -a l_doc
  OP::options_get $l_option_pos :doc l_doc
  if [[ ${#l_doc[@]} -eq 0 ]]; then
    return 0
  fi
  local l_match
  local l_desc_start=0
  if test ${#l_doc[@]} -ge 2; then
    l_match=${l_doc[0]}
    l_desc_start=1
  fi
  printf " $(tput bold)%-19s$(tput sgr0)" "$l_match"
  l_prefix=""
  if test ${#l_match} -ge 19; then
    echo
    l_prefix=$(printf '%20s' "")
  fi
  local l_num=0
  for l_desc in "${l_doc[@]:l_desc_start}"; do
    local l_line
    while read l_line; do
      echo "${l_prefix}${l_line}"
      let ++l_num
      [[ -z "${l_prefix}" ]] && l_prefix=$(printf '%20s' "")
    done < <(
      printf %s "$l_desc" | sed 's/\\n/\n/g' | fmt -s -w 60
    )
  done
  if test $l_num -eq 0; then
    echo
  fi
}

function OP::print_usage_header() {
  local l_file="$1"
  if ! [[ -r "$l_file" ]]; then
    echo "Usage: $1"
    return 0
  fi
  local l_index=0
  local l_line_printed=0
  while read -r line; do
    let ++l_index
    if [[ l_index -eq 1 && "$line" =~ ^#! ]]; then
      continue
    fi
    if [[ ! "$line" =~ ^# ]]; then
      break
    fi
    line="${line:1}"
    if [[ -z "$line" ]]; then
      if (( l_line_printed == 0 )); then
        continue
      fi
    fi
    let ++l_line_printed
    echo "${line# }"
  done < "$l_file"
}

# A taker.
function OP::help() {
  if declare -f OP::usage &>/dev/null; then
    OP::usage
  elif [[ -n "$OP_USAGE" ]]; then
    echo "$OP_USAGE" | fmt -s -w80
    echo
  else
    OP::print_usage_header "$0"
  fi
  local l_option_pos=0
  while l_option_pos=$(OP::options_next $l_option_pos); do
    OP::help_at $l_option_pos
  done
  exit 1
}

# Call as OP::add_help "-h, --help" "show help message"
function OP::add_help() {
  local l_match="$1"
  local l_help="$2"
  if test -z "$l_match"; then
    l_match="-h, --help"
  fi
  if test -z "$l_help"; then
    l_help="show help message"
  fi
  OP::add_option "$l_match" "OP::func OP::help" "$l_help"
}

# Used variables: OP_PARSE_ERROR OP_PARSE_POSITION
function OP::parse() {
  OP_PARSE_ERROR=""
  local OP_POSITION=0
  OP_PARSE_POSITION=$OP_POSITION
  while true; do
    local l_index l_offset
    OP::split_position l_index l_offset $OP_POSITION
    if test "$l_index" -ge "$#"; then
      break
    fi
    local OP_MATCH_ITEM="" OP_MATCH_STOP=-1 OP_MATCH_ERROR=""
    local OP_ITEM_START=$OP_POSITION
    if ! OP::find_best_match "$@"; then
      OP_PARSE_ERROR="match-error $OP_MATCH_ERROR"
      OP_PARSE_POSITION=$OP_POSITION
      return 1
    fi
    OP_POSITION=$OP_MATCH_STOP
    local OP_TAKE_ERROR=""
    if ! OP::call_taker_at $OP_MATCH_ITEM "$@"; then
      OP_PARSE_ERROR="got a take error $OP_TAKE_ERROR at $OP_POSITION"
      OP_PARSE_POSITION="$OP_POSITION"
      return 1
    fi
  done
  OP_PARSE_POSITION=$OP_POSITION
  return 0
}

function test::OP::parse_empty() {
  local -a OP_OPTIONS

  expect OP::parse
  expect_equal $OP_PARSE_POSITION "0"
}

function test::OP::parse_set() {
  OP::add_option "-a, --opta" "opta"
  OP::add_option "-b, --optb" "optb"

  OP::info "Test parse multiple ..."
  expect OP::parse -a a0 -b b0 --opta a1 --optb b1
  expect_equal $OP_PARSE_POSITION 8-0
  expect_equal $opta a1
  expect_equal $optb b1

  OP::info "Test with unknown ..."
  expect_fail OP::parse -a a2 -unknown
  expect_equal $OP_PARSE_POSITION 2-0
  expect_equal $opta a2
}

function test::OP::parse_func() {
  OP::add_option "--tf, --train-file FILE" "train_file" "set variable train_file"
  OP::add_option "--input-file FILE" "input_file" "set variable input_file"
  value=0
  function test_take_summation() {
    local OP_VALUE OP_VALUE_ERROR OP_VALUES
    OP::value_many OP::value regex [0-9]+ -- "$@"
    for l_v in "${OP_VALUES[@]}"; do
      let value+=l_v
    done
    return 0
  }
  OP::add_option "--sum INT..." "OP::func test_take_summation" "call sum as take function"
  expect OP::parse --sum 1 2 3 4 --train train.log --input in.log
  expect_equal $value 10
  expect_equal $train_file train.log
  expect_equal $input_file in.log
}

function OP::parse_all() {
  local OP_PARSE_POSITION OP_PARSE_ERROR
  if ! OP::parse "$@"; then
    echo -e "Parse stop with error $OP_PARSE_ERROR" >&2
    echo -n "Args:"
    OP::print_args_position "$OP_PARSE_POSITION" "$@" >&2
    echo
    exit 1
  fi
}

function OP::collect_argv_() {
  l_argv+=("$@")
}

function OP::parse_line() {
  local OP_PARSE_POSITION
  local -a l_argv
  OP::collect_argv_ $1
  OP::parse_all "${l_argv[@]}"
}

function OP::parse_file() {
  local l_line
  while read -r l_line; do
    if test -z "$l_line"; then
      continue
    fi
    if [[ "$l_line" =~ ^# ]]; then
      continue
    fi
    if ! OP::parse_line "$l_line"; then
      OP_PARSE_ERROR="can't parse line($l_line) from file($1), $OP_PARSE_ERROR"
      return 1
    fi
  done < $1
}

# A taker.
function OP::take_config_file() {
  local OP_VALUE OP_VALUE_ERROR
  local OP_PARSE_ERROR
  if OP::value -- "$@"; then
    if ! OP::parse_file "$OP_VALUE"; then
      OP_TAKE_ERROR="$OP_PARSE_ERROR"
      return 1
    fi
  else
    OP_TAKE_ERROR="expect a config file"
    return 1
  fi
}

function test::OP::take_config_file() {
  local -a OP_OPTIONS
  local OP_PARSE_POSITION OP_PARSE_ERROR
  local train_file input_file
  OP::add_option "--tf, --train-file FILE" "train_file" "set variable train_file"
  OP::add_option "--input-file FILE" "input_file" "set variable input_file"
  local value=0
  function test_take_summation() {
    local OP_VALUE OP_VALUE_ERROR
    local -a OP_VALUES
    OP::value_many OP::value regex [0-9]+ -- "$@"
    for l_v in "${OP_VALUES[@]}"; do
      let value+=l_v
    done
    return 0
  }
  OP::add_option "--sum INT..." "OP::func test_take_summation" "call sum as take function"
  OP::add_option "--config-file FILE" "OP::func OP::take_config_file" "config from file"
  fn=$(mktemp -t op.sh.test.XXXXXX)
  echo "#options_parser, try load config from file">>$fn
  echo "" --sum 1 2 3 4 >>$fn
  echo "" --train train.log >>$fn
  echo "" --input in.log >>$fn
  expect OP::parse --config-file $fn
  unlink $fn
  expect_equal $value 10
  expect_equal $train_file train.log
  expect_equal $input_file in.log
}

function OP::add_config_file() {
  local l_match="$1"
  local l_help="$2"
  if [[ -z "$l_match" ]]; then
    l_match="--config-file FILE"
  fi
  if test -z "$l_help"; then
    l_help="Parse configuration file, options line by line."
  fi
  OP::add_option "$l_match" "OP::func OP::take_config_file" "$l_help"
}

# DEFINE_flag value-arg match/name init-value doc...
function DEFINE_flag() {
  local l_value_arg="$1"
  local l_match="$2"
  local l_name="$2"
  if  [[ $l_name =~ ^- ]]; then
    local -a l_opts
    OP::split_match_description l_opts "$l_match"
    l_name="$(printf %s ${l_opts[-1]} | sed 's/^-\+//;s/-/_/g')"
  else
    l_match="--$l_name <$l_value_arg>"
  fi
  local -n l_flag_c5a29475_2570_4bcf_b00f_e116ce5ee6ab="FLAGS_$l_name"
  l_flag_c5a29475_2570_4bcf_b00f_e116ce5ee6ab="$3"
  shift 3
  OP::add_option "$l_match" \
    "OP::set_value FLAGS_$l_name OP::value $l_value_arg --" \
    "$@" \
    "Default: ${l_flag_c5a29475_2570_4bcf_b00f_e116ce5ee6ab}"
}

# DEFINE_string name/match init-value doc...
#
# Set FLAGS_##name.
function DEFINE_string() {
  DEFINE_flag string "$@"
}

function test::DEFINE_string() {
  expect DEFINE_string wrapper "" "wrapper"
  expect OP::parse --wrapper=env
  expect_equal "$FLAGS_wrapper" "env"

  expect DEFINE_string "-f, --train-file=[FILE]" init "..."
  expect_equal "$FLAGS_train_file" "init"

  expect OP::parse --train-file t.txt
  expect_equal "$FLAGS_train_file" t.txt
  expect_fail OP::parse --train_file t.txt
}

# DEFINE_integer name/match init-value doc
function DEFINE_integer() {
  DEFINE_flag integer "$@"
}

function test::DEFINE_integer() {
  local FLAGS_vi
  DEFINE_integer vi 3 "vi"
  expect_equal "$FLAGS_vi" 3
  expect OP::parse --vi=10
  expect_equal "$FLAGS_vi" "10"

  expect_fail OP::parse --vi=3.14
  expect_fail OP::parse --vi=10a
  expect_fail OP::parse --vi=a10

  expect DEFINE_integer "-n, --the-number NUM" 3
  expect_equal "$FLAGS_the_number" 3

  expect OP::parse --the-number 13
  expect_equal "$FLAGS_the_number" 13

  expect OP::parse -n18
  expect_equal "$FLAGS_the_number" 18

  expect_fail OP::parse -n18a
}

# DEFINE_float name/match init-value doc
function DEFINE_float() {
  DEFINE_flag float "$@"
}

function test::DEFINE_float() {
  local FLAGS_vf
  DEFINE_float vf 3.2 "vf"
  expect_equal "$FLAGS_vf" 3.2
  expect OP::parse --vf=10
  expect_equal "$FLAGS_vf" "10"
  expect OP::parse --vf=3.14
  expect_equal "$FLAGS_vf" "3.14"

  expect_fail OP::parse --vi=10a
  expect_fail OP::parse --vi=a10
}

function OP::from_match_start() {
  OP_POSITION=$OP_ITEM_START
}

function OP::bool_of() {
  if [[ "$1" =~ ^[fF0] || -z "$1" ]] ; then
    return 1
  fi
  return 0
}

function test::OP::bool_of() {
  expect_fail OP::bool_of
  expect_fail OP::bool_of ""
  expect_fail OP::bool_of 0
  expect_fail OP::bool_of false
  expect_fail OP::bool_of False
  expect_fail OP::bool_of FALSE
  expect OP::bool_of 1
  expect OP::bool_of true
  expect OP::bool_of True
  expect OP::bool_of TRUE
}

function OP::bool_value_of() {
  if OP::bool_of "$1"; then
    echo 1
  else
    echo 0
  fi
}

function test::OP::bool_value_of() {
  expect_equal "$(OP::bool_value_of 1)" 1
  expect_equal "$(OP::bool_value_of true)" 1
  expect_equal "$(OP::bool_value_of True)" 1
  expect_equal "$(OP::bool_value_of TRUE)" 1
  expect_equal "$(OP::bool_value_of t)" 1
  expect_equal "$(OP::bool_value_of T)" 1
  expect_equal "$(OP::bool_value_of 10)" 1
  expect_equal "$(OP::bool_value_of 100)" 1

  expect_equal "$(OP::bool_value_of 0)" 0
  expect_equal "$(OP::bool_value_of false)" 0
  expect_equal "$(OP::bool_value_of False)" 0
  expect_equal "$(OP::bool_value_of FALSE)" 0
  expect_equal "$(OP::bool_value_of f)" 0
  expect_equal "$(OP::bool_value_of F)" 0
}

# DEFINE_bool name/match init-value doc...
function DEFINE_bool() {
  local l_match="$1"
  local l_value="$(OP::bool_value_of $2)"
  shift 2
  DEFINE_flag 'optional 1 bool' "$l_match" "$l_value" "$@"
}

function test::DEFINE_bool() {
  local -a OP_OPTIONS
  local OP_PARSE_ERROR OP_PARSE_POSITION

  DEFINE_bool vb false "bool value"
  expect_equal "$FLAGS_vb" 0

  DEFINE_bool vc true "bool value"
  expect_equal "$FLAGS_vc" 1

  expect OP::parse --vb
  expect_equal $FLAGS_vb 1

  expect OP::parse --vb=0
  expect_equal $FLAGS_vb 0
  expect OP::parse --vb=f
  expect_equal $FLAGS_vb 0
  expect OP::parse --vb=false
  expect_equal $FLAGS_vb 0

  expect OP::parse --vb=1
  expect_equal $FLAGS_vb 1
  expect OP::parse --vb=t
  expect_equal $FLAGS_vb 1
  expect OP::parse --vb=true
  expect_equal $FLAGS_vb 1

  FLAGS_vb=0
  expect_fail OP::parse --vb --vi
  expect_equal $FLAGS_vb 1

  expect DEFINE_bool "-c, --check-args[=true/false]" true "verify ..."
  expect_equal "$FLAGS_check_args" 1

  FLAGS_check_args=0
  expect OP::parse -c
  expect_equal "$FLAGS_check_args" 1

  expect OP::parse -c0
  expect_equal "$FLAGS_check_args" 0

  expect OP::parse -c=1
  expect_equal "$FLAGS_check_args" 1

  expect_fail OP::parse -c 0
  expect_equal "$FLAGS_check_args" 1

  FLAGS_check_args=0
  expect_fail OP::parse --check 0
  expect_equal "$FLAGS_check_args" 1

  expect OP::parse --check=0
  expect_equal "$FLAGS_check_args" 0
}

function test::OP::flags() {
  local -a OP_OPTIONS
  DEFINE_string vs "value-str" "string value"
  DEFINE_integer vi "13" "integer value"
  DEFINE_float vf "3.14" "float value"
  DEFINE_bool vb "0" "bool value"

  expect OP::parse --vs "set-vs"
  expect_equal $FLAGS_vs "set-vs"
  expect_fail OP::parse --vi "129set-vi"
  expect_equal $FLAGS_vi "13" "don't reset vi"
  expect OP::parse --vi "139"
  expect_equal $FLAGS_vi "139"
  expect_fail OP::parse --vf "139a"
  expect_equal $FLAGS_vf "3.14"
  expect OP::parse --vf "3.1415"
  expect_equal $FLAGS_vf "3.1415"
  expect OP::parse --vb
  expect_equal $FLAGS_vb "1" "bool should be set"
  expect OP::parse --vb=0
  expect_equal $FLAGS_vb "0" "bool should be reset"
  expect OP::parse --vb=1 --vs "vs-value" --vi 17
  expect_equal $FLAGS_vb 1
  expect_equal $FLAGS_vs vs-value
  expect_equal $FLAGS_vi 17

  DEFINE_string a "" "I'm a"

  expect_fail OP::parse --vb=0 --vs "vs-value-" -- 18
  expect_equal "$OP_PARSE_POSITION" 3-0
  expect_equal $FLAGS_vb 0
  expect_equal $FLAGS_vs vs-value-
  expect_equal $FLAGS_vi 17
  expect_equal $FLAGS_a ""

  expect_fail OP::parse --vb=1 --vs="ya-value" --vi=20 -- 18
  expect_equal "$OP_PARSE_POSITION" 3-0
  expect_equal $FLAGS_vb 1
  expect_equal $FLAGS_vs ya-value
  expect_equal $FLAGS_vi 20

  expect_fail OP::parse --vb=0 --vs= --vi=21 -- 18
  expect_equal "$OP_PARSE_POSITION" 3-0
  expect_equal $FLAGS_vb 0
  expect_equal $FLAGS_vs ""
  expect_equal $FLAGS_vi 21
}

function test::OP::flags_scope() {
  function test::flags_scope_in() {
    local OP_OPTIONS
    local FLAGS_vi=0
    DEFINE_integer vi "13" "integer value"
    expect OP::parse --vi 123
    expect_equal $FLAGS_vi 123
  }
  local o_flags_vi="$FLAGS_vi"
  expect test::flags_scope_in
  expect_equal "$FLAGS_vi" "$o_flags_vi"
}

function OP::check_n() {
  local l_name="$1"
  shift
  if test -n "${!l_name}"; then
    true
  else
    OP::log 2 fatal "$l_name is empty $@"
  fi
}

# OP::add_position name doc description
function OP::add_position() {
  local l_dest="$1"
  local l_doc="$2"
  local l_description="$3"
  if [[ $l_dest =~ " " ]] ; then
    OP::add_option "OP::assign OP_MATCH_PRIORITY $OP_MATCH_POSITION" \
      "$l_dest" \
      "$l_doc" "$l_description"
  else
    OP::add_option "OP::assign OP_MATCH_PRIORITY $OP_MATCH_POSITION" \
      "OP::set_value $l_dest OP::value --" \
      "$l_doc" "$l_description"
  fi
}

function test::OP::add_position() {
  local file=""
  local OP_OPTIONS
  OP::add_option "--file FILE" file "..."
  OP::add_position file FILE "..."

  expect OP::parse_all --file a.log b.log
  expect_equal "$file" b.log

  expect OP::parse_all --file a.log b.log --file c.log
  expect_equal "$file" c.log
}

# The tests.

OP_UNIT_NUM_FAILED=0

function OP::unit::failed_traceback() {
  local l_location="$1"
  shift
  OP::print_log "$l_location" E
  OP::print_log "$l_location" E Traceback
  OP::traceback "$l_location" 2
  OP::print_log "$l_location" E
  OP::print_log "$l_location" E Variables
  local l_line
  while read -r l_line; do
    OP::print_log_lines "$l_location" E "$l_line"
  done < <( declare | egrep '^(l_|OP_)' )
}

function OP::unit::assert_failed() {
  exit 1
}

function OP::unit::expect_failed() {
  false
}

function OP::unit::check() {
  local l_location="$1"
  local l_fail="$2"
  shift 2
  OP::print_log "$l_location" I "Check" "$@"
  if "$@"; then
    true
  else
    let ++OP_UNIT_NUM_FAILED
    OP::print_log "$l_location" E "Failed" "$@"
    OP::unit::failed_traceback "$l_location" "$@"
    $l_fail "$l_location" "$@"
    return 1
  fi
}

function OP::unit::last() {
  return $?
}

function OP::unit::last_fail() {
  if test $? -eq  0; then
    return 1
  fi
  return 0
}

function OP::unit::equal() {
  test "$1" == "$2"
}

function OP::unit::fail() {
  ! "$@"
}

function OP::unit::assert() {
  local l_location=1
  if [[ $1 =~ ^[0-9]+ ]]; then
    l_location=$1
    shift
  fi
  l_location=$(OP::get_frame "$l_location")
  OP::unit::check "$l_location" OP::unit::assert_failed "$@"
}

function OP::unit::expect() {
  local l_location=1
  if [[ $1 =~ ^[0-9]+ ]]; then
    l_location=$1
    shift
  fi
  l_location=$(OP::get_frame "$l_location")
  OP::unit::check "$l_location" OP::unit::expect_failed "$@"
}

function OP::unit::run_test() {
  OP::info ===========Test $1 ...
  (
    function check() {
      OP::unit::check 2 "$@"
    }
    function expect() {
      OP::unit::expect 2 "$@"
    }
    function assert() {
      OP::unit::assert 2 "$@"
    }
    function expect_equal() {
      OP::unit::expect 2 OP::unit::equal "$@"
    }
    function expect_fail() {
      OP::unit::expect 2 OP::unit::fail "$@"
    }
    function expect_last() {
      OP::unit::expect 2 OP::unit::last "$@"
    }
    function assert_equal() {
      OP::unit::assert 2 OP::unit::equal "$@"
    }
    function assert_fail() {
      OP::unit::assert 2 OP::unit::fail "$@"
    }
    function assert_last() {
      OP::unit::assert 2 OP::unit::last "$@"
    }
    OP_UNIT_NUM_FAILED=0
    $1
    if [[ $OP_UNIT_NUM_FAILED -gt 0 ]] ; then
      OP::fatal $OP_UNIT_NUM_FAILED checks failed
    fi
  )
  if [[ $? -eq 0 ]] ; then
    OP::info ===========Done $1
    return 0
  else
    OP::error ==========Failed $1
    let ++OP_UNIT_NUM_FAILED
    return 1
  fi
}

function OP::unit::run_tests() {
  if [[ $# -gt 0 ]]; then
    for test in $@; do
      OP::unit::run_test $test
    done
  else
    for test in $(declare -F | grep 'f test::' | sed 's/.*-f//'); do
      OP::unit::run_test $test
    done
  fi

  if [[ $OP_UNIT_NUM_FAILED -gt 0 ]]; then
    echo "$OP_UNIT_NUM_FAILED tests failed"
    exit 1
  fi
}

if test "$1" == "OP::Test"; then
  shift
  OP::unit::run_tests "$@"
fi
