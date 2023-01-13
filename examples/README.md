# DAF examples

This directory has example autograders.

Each example autograder has an `example_solution` directory
containing an example solution that can be tested using the autograder.
Since the autograders will expect the student solution to be in
a directory called `submission`, the procedure for trying out one
of the example autograders is

```bash
rm -rf submission
cp -r example_solution submission
./run_autograder
```

Note that the example solutions have deliberate mistakes so that not
all autograder tests pass.

The [example01](example01) autograder tests a simple C program
that reads input from standard input and writes output to standard output.

The [example02](example02) autograder tests C functions
using a [unit test framework](https://github.com/daveho/tctest).

The [example03](example03) autograder unit tests a Java class using
[JUnit](https://junit.org).
