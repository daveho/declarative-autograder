#! /usr/bin/env bash

if [ $# -ne 2 ]; then
  >&2 echo "Usage: ./run_test <exe name> <test name>"
  exit 1
fi

exe_name="$1"
test_name="$2"

# Run the program, providing the example input and capturing the
# actual output
$exe_name < ${test_name}.in > ${test_name}_actual.out
if [ $? -ne 0 ]; then
  >&2 echo "Student program did not exit successfully"
  exit 1
fi

# Diff the expected output against the actual output
diff ${test_name}.out ${test_name}_actual.out > ${test_name}_diff.out

# Test succeeds if the diff command was successful (actual output
# matched the expected output)
exit $?
