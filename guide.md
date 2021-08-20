# Guide to using the declarative autograder framework (DAF)

This document explains the concepts and techniques needed to use the
[Declarative Autograder Framework](https://github.com/daveho/declarative-autograder).

## Background, philosophy

An *autograder* is a program that tests student code and generates a
grade.  Usually, the testing is for functional correctness, meaning some
combination of unit tests and system tests where the program is fed
test inputs and the program output is compared to expected output.
However, it is possible to incorporate non-functional tests such as style
checking into an autograder.

Autograders are a common feature of contemporary CS education. They can
provide immediate feedback to students on their progress in completing programming
assignments, and they can relieve instructors and teaching assistants of the
burden of testing student code by hand.

[Gradescope](https://www.gradescope.com) is one platform providing autograding
support for CS classes.  The declarative autograder framework (DAF) is designed to
integrate with Gradescope, although there is nothing to prevent its use as
a standalone tool, or to prevent it from being integrated with other autograder platforms.

If you've ever tried to write an autograder, then you're probably aware that
autograder programs and scripts can easily become complex and hard to work with.
This is where DAF comes in: it is intended to make autograder scripts easy
to write.

The philosophy of DAF is that an autograder script should directly specify *what* is
being done to test student code, but avoid specifying *how* the code will be
tested.  In other words, an autograder script should mainly consist of two things:

1. a *rubric* describing the properties of a correct student submission and how much each is worth
2. a *test plan* describing, at a high level, what *tests* should be executed to evaluate the
   student submission against each rubric item

What an autograder script should *not* directly specify is the low-level mechanics of
how student code will be tested. That functionality can (and should) be offloaded
to scripts and programs invoked by the autograder script.

In [the author](https://www.cs.jhu.edu/~daveho)'s opinion, autograders implemented
according to these principles can be concise, beautiful, and a pleasure to use and
modify.  (You will no doubt form your own opinion.)

DAF has been used extensively by the author in several courses, and (indirectly)
by hundreds of students, so an argument can be made that it is reasonably
production-ready.

## Test environment

DAF makes the following assumptions about the environment in which the autograder will run:

1. There is a directory hierarchy containing the autograder files and the student submission files
2. The `run_autograder` script, which is the autograder, is in the top level of the hierarchy
3. The file `autograder2.rb`, which is the Ruby module implementing DAF, is either in the same
   directory as `run_autograder`, or is in a subdirectory called `source`
4. Data files needed by the autograder, such as test inputs and expected outputs, are
   in a subdirectory named either `files` or `source/files`
5. The files comprising the student code submission are in a subdirectory called `submission`

A typical autograder will have the following directory structure:

```
run_autograder
autograder2.rb
files/
    input_1.txt
    expected_output_1.txt
    ...etc...
```

When developing and testing an autograder, or running it as a standalone program,
this directory structure will also have a `submission` subdirectory with the student
program:

```
run_autograder
autograder2.rb
files/
    input_1.txt
    expected_output_1.txt
    ...etc...
submission/
    program.c
    Makefile
    ...etc...
```

Because [Gradescope's autograder feature](https://gradescope-autograders.readthedocs.io/en/latest/specs/)
moves files around, when a student code submission
is tested on Gradescope, the environment will look something like this:

```
run_autograder
source/
    autograder2.rb
    files/
        input_1.txt
        expected_output_1.txt
        ...etc...
submission/
    program.c
    Makefile
    ...etc...
```

DAF is designed to allow either of these runtime configurations to work.

## Concepts

TODO

### Rubric

TODO

### Tasks

TODO

### `X.all` and `X.inorder`

TODO

### Tests and test outcomes

TODO

### Results

TODO

## Writing test scripts

TODO


TODO
