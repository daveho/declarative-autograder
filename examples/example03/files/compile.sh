#! /usr/bin/env bash

# Script to compile the student's Java source code
# and the unit test code

SRCS="edu/jhu/cs/example/Calculator.java edu/jhu/cs/example/CalculatorTest.java"
CLASSPATH=".:../junit-4.13.2.jar:../hamcrest-core-1.3.jar"

mkdir -p bin
cd src && javac -d ../bin -cp ${CLASSPATH} ${SRCS}
exit $?
