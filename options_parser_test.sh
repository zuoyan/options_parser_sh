source options_parser.sh

die() {
  local frame=0

  while caller $frame; do
    ((frame++));
  done
  echo "$*"
  exit 126
}

function assert_equal {
  if test "$1" != "$2"; then
    echo "'$1' != '$2' $3"
    die
  fi
}

function assert_failed {
  "$@"
  if test $? -eq 0; then
    echo "'$@' not failed"
    die
  fi
}

function assert_success {
  "$@"
  if ! test $? -eq 0; then
    echo "'$@' failed"
    die
  fi
}

function basic_test {
  local op_value op_value_error op_index=0
  local -a op_values
  op_index=0
  assert_failed OP_value opt -- d0c820728b04b407627109ce50ebae95

  assert_success OP_value -- d0c820728b04b407627109ce50ebae95
  assert_equal "$op_value" d0c820728b04b407627109ce50ebae95

  op_index=0
  assert_success OP_value match -- --d0c820728b04b407627109ce50ebae95
  assert_equal "$op_value" d0c820728b04b407627109ce50ebae95

  op_index=0
  assert_success OP_value_many regex '[0-9]+' -- 12 34 ab cd
  op_value="${op_values[@]}"
  assert_equal "$op_value" "12 34"
  op_values=()
  assert_failed OP_value regex '[0-9]+' -- -10
}

basic_test

function set_test {
  local op_parser_index op_parser_error
  assert_success OP_parse

  local -a op_options
  local opta optb
  OP_add_option "a|opta" "opta"
  OP_add_option "b|optb" "optb"
  assert_success OP_parse -a a0 -b b0 --opta a1 --optb b1
  assert_equal $op_parse_index 8
  assert_equal $opta a1
  assert_equal $optb b1
  assert_failed OP_parse -a a2 -unknown
  assert_equal $op_parse_index 2
  assert_equal $opta a2
}

set_test

function doc_test {
  local -a op_options
  local op_parse_index op_parse_error
  local train_file input_file
  OP_add_option "tf|train-file" "train_file" "FILE\nset variable train_file"
  OP_add_option "input-file" "input_file" "FILE\nset variable input_file"
  local value=0
  function summation {
    local op_value op_value_error op_values
    OP_value_many regex [0-9]+ -- "$@"
    for l_v in "${op_values[@]}"; do
      let value+=l_v
    done
    return 0
  }
  OP_add_option "sum" "OP_func summation" "INT+\ncall sum as take function"
  assert_success OP_parse --sum 1 2 3 4 --train train.log --input in.log
  assert_equal $value 10
  assert_equal $train_file train.log
  assert_equal $input_file in.log
}

doc_test


function file_test {
  local -a op_options
  local op_parse_index op_parse_error
  local train_file input_file
  OP_add_option "tf|train-file" "train_file" "FILE\nset variable train_file"
  OP_add_option "input-file" "input_file" "FILE\nset variable input_file"
  local value=0
  function summation {
    local op_value op_value_error op_values
    OP_value_many regex [0-9]+ -- "$@"
    for l_v in "${op_values[@]}"; do
      let value+=l_v
    done
    return 0
  }
  OP_add_option "sum" "OP_func summation" "INT+\ncall sum as take function"
  OP_add_option "config-file" "OP_func OP_take_config_file" "FILE\nconfig from file"
  fn=$(mktemp)
  echo "#options_parser, try load config from file">>$fn
  echo --sum 1 2 3 4 \$UID >>$fn
  echo --train train.log >>$fn
  echo --input in.log >>$fn
  assert_success OP_parse --config-file $fn
  unlink $fn
  local value_check=10
  let value_check+=UID
  assert_equal $value $value_check
  assert_equal $train_file train.log
  assert_equal $input_file in.log
}

file_test

function flags_test {
  local op_options
  DEFINE_string vs "value-str" "string value"
  DEFINE_integer vi "13" "integer value"
  DEFINE_float vf "3.14" "float value"
  DEFINE_boolean vb "0" "bool value"
  assert_success OP_parse --vs "set-vs"
  assert_equal $FLAGS_vs "set-vs"
  assert_failed OP_parse --vi "129set-vi"
  assert_equal $FLAGS_vi "13" "don't reset vi"
  assert_success OP_parse --vi "139"
  assert_equal $FLAGS_vi "139"
  assert_failed OP_parse --vf "139a"
  assert_equal $FLAGS_vf "3.14"
  assert_success OP_parse --vf "3.1415"
  assert_equal $FLAGS_vf "3.1415"
  assert_success OP_parse --vb
  assert_equal $FLAGS_vb "1" "boolean should be set"
  assert_success OP_parse --no-vb
  assert_equal $FLAGS_vb "0" "boolean should be reset"
}

flags_test

function flags_scope_test {
  function flags_scope_test_in {
    local op_options
    local FLAGS_vi=0
    DEFINE_integer vi "13" "integer value"
    assert_success OP_parse --vi 123
    assert_equal $FLAGS_vi 123
  }
  local o_flags_vi="$FLAGS_vi"
  assert_success flags_scope_test_in
  assert_equal "$FLAGS_vi" "$o_flags_vi"
}

flags_scope_test
