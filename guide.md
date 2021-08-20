# Guide to using the Declarative Autograder Framework (DAF)

This document explains the concepts and techniques needed to use the
[Declarative Autograder Framework](https://github.com/daveho/declarative-autograder).

From a practical standpoint, looking at the examples (TODO: link to
examples) is probably the best place to start for learning how to
use DAF to implement autograders.  However, the content in
this document is important if you want to really understand how
DAF autograders are put together.

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

If you've ever written an autograder, then you're probably aware that
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
    run_program.sh
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
    run_program.sh
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
        run_program.sh
        ...etc...
submission/
    program.c
    Makefile
    ...etc...
```

DAF is designed to allow either of these runtime configurations to work.

## Concepts

This section explains the fundamental concepts involved in using DAF to implement an
autograder.

### Rubric

A *rubric* is a list of *rubric items*.  Each rubric item specifies a *testname*,
*description*, and *points*.  Both the rubric and its rubric items are represented
as Ruby arrays.

Specifying a rubric is probably the first thing you will do when writing an
autograder script.  Example:

```ruby
rubric = [
  [:make_succeeds, "Make successfully compiles the program", 5.0],
  [:test1, "First program test", 10.0],
  [:test2, "Second program test", 10.0],
  [:test3, "Third program tes", 5.0],
]
```

The rubric above specifies four rubric items, worth a total of 30 points.
The `:make_succeeds` rubric item represents the requirement that the student
program compile successfully using make.  The `:test1`, `:test2`, and `:test3`
rubric items represent functional tests which will evaluate the extent to
which the student's submission meets the functional specifications
in the assignment description.

### Tasks and task results

A *task* is a behavior to be executed as part of the autograder.  DAF
can create a variety of different kinds of tasks to carry out behaviors useful
for autograding.  For example, the [X.run](https://daveho.github.io/declarative-autograder/X.html#run-class_method)
task runs a program.  All tasks will produce at least one boolean value
to indicate success or failure.

A task's *call* method executes the task.  To report the result of the task,
one or more boolean values are pushed onto an outcomes array.
Nearly all tasks push a single boolean value. The only exception are tasks created by
[X.inorder](https://daveho.github.io/declarative-autograder/X.html#inorder-class_method)),
which can push multiple values.

Tasks created by [X.test](https://daveho.github.io/declarative-autograder/X.html#test-class_method)
represent the execution of a test associated with a rubric item.  Let's say that the program
being tested is a calculator program.  A test execution might look like this:

```ruby
X.test(:test_add, X.run('./test_calculator.sh', '5', './calc', '2 + 3'))
```

The code above indicates that to run the `:test_add` test, the `./test_caculator.sh`
script should be run with the arguments `5`, `./calc`, and `2 + 3`.
If the script succeeds (exits normally with a 0 exit code), then the `X.run` task
pushes a true outcome value, and `X.test` records the `:test_add` test as passing.
If the script fails (exits abnormally and/or exits with a non-zero exit code),
then `X.test` records `:test_add` as failing.  (In general, `X.test` tasks will
consider the subordinate task to have succeeded if the most recent boolean
value it pushed is true.  Since all tasks other than `X.inorder` tasks push only
a single boolean value, in practice you can think of every task yielding a
single true or false value indicating whether it succeeded or failed.)

Other kinds of tasks are useful for other important autograder behaviors.
For example, [X.make](https://daveho.github.io/declarative-autograder/X.html#make-class_method)
runs the `make` utility to compile a program, and
[X.copy](https://daveho.github.io/declarative-autograder/X.html#copy-class_method)
copies files that will be needed to compile the student's program and/or run tests.

Internally, a task is implemented by a Ruby object supporting a `call` method taking four arguments:

* `outcomes`: list of booleans containing previous test results
* `results`: map of testnames to scores (for reporting)
* `logger`: for logging diagnostics
* `rubric`: the rubric describing the tests

You won't need to know how tasks work internally unless you want to create your
own custom task objects.  If you look at the source code for
[autograder2.rb](https://github.com/daveho/declarative-autograder/blob/master/autograder2.rb), you'll notice that 
tasks are implemented as Ruby lambdas.

### `X.all` and `X.inorder`

Tasks such as `X.run`, `X.make`, `X.copy`, and `X.test` are the fundamental
building blocks of an autograder.  However, the autograder will need to run
many tasks in order to fully test and evaluate the student program.
*Sequencing* of tasks is an important concern.  Sometimes we will want to
make the execution of later tasks dependent on the success of earlier tasks,
and sometimes we will want to execute a number of tests independently.

[X.all](https://daveho.github.io/declarative-autograder/X.html#all-class_method)
and [X.inorder](https://daveho.github.io/declarative-autograder/X.html#inorder-class_method) 
provide mechanisms to create [composite](https://en.wikipedia.org/wiki/Composite_pattern)
tasks comprised of a sequence of lower-level tasks.

The `X.all` task executes a series of consitutent tasks in order. Later tasks
are only executed if all previous tasks completed successfully.  So, `X.all` is
very useful for specifying prerequisites which must complete successfully before
later tasks can be attempted.  For example, before running tests on a student
program, test files must be copied, and the program must be compiled:

```ruby
X.all(
  # copy required test files
  X.copy('input_1.txt',
         'input_2.txt',
         'expected_output_1.txt'
         'expected_output_2.txt',
         'run_program.sh'),
  # compile the student program
  X.test(:make_succeeds, X.make('program')),
  # ...now the tests can be executed...
)
```

In the above example, we don't want to attempt running tests unless all files
needed for testing (inputs, expected outputs, and test scripts) have been
copied successfully, and the student program has been compiled successfully.

The `X.inorder` task executes a series of tasks, but later tasks are attempted
regardless of whether or not previous tasks succeeded.  The core of an autograder
is typically an `X.inorder` task which executes all of the functional tests associated
with rubric items.  To elaborate the example above:

```ruby
X.all(
  # copy required test files
  X.copy('input_1.txt',
         'input_2.txt',
         'expected_output_1.txt'
         'expected_output_2.txt',
         'run_program.sh'),
  # compile the student program
  X.test(:make_succeeds, X.make('program')),
  # execute the tests against the student program
  X.inorder(
    X.test(:test_case_1, X.run('./run_program.sh', './program',
                               'input_1.txt', 'expected_output_1.txt')),
    X.test(:test_case_2, X.run('./run_program.sh', './program',
                               'input_2.txt', 'expected_output_2.txt')),
  ),
)
```

As you can see, the `X.all` and `X.inorder` tasks provide complete flexibility in
determining which tasks are executed.  The `X.all` task shown above could form the
*test plan* for an autograder.

### Tests, test outcomes, and the test plan

TODO

### Results

TODO

## Writing test scripts

TODO


TODO
