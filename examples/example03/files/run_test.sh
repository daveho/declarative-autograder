#! /usr/bin/env bash

# Script to execute one unit test

if [ $# -ne 1 ]; then
  >&2 echo "Usage: ./run_test.sh <test name>"
  exit 1
fi

test_name="$1"

CLASSPATH="bin:junit-4.13.2.jar:hamcrest-core-1.3.jar"

java -cp ${CLASSPATH} edu.jhu.cs.example.CalculatorTest ${test_name}
exit $?
