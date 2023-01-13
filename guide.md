# Guide to using the Declarative Autograder Framework (DAF)

This document explains the concepts and techniques needed to use the
[Declarative Autograder Framework](https://github.com/daveho/declarative-autograder).

From a practical standpoint, looking at the [examples](examples)
is probably the best place to start for learning how to
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

Because this difference affects the location of `autograder2.rb` relative
to the `run_autograder` script, your `run_autograder` script should
begin with the following code:

```ruby
#! /usr/bin/env ruby

# autograder2.rb could be either in the same directory as run_autograder,
# or (on Gradescope) could be in "source"
$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.dirname(__FILE__) + "/source")

require 'autograder2'
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
  [ :make_succeeds, "Make successfully compiles the program", 5.0 ],
  [ :test1, "First program test", 10.0 ],
  [ :test2, "Second program test", 10.0 ],
  [ :test3, "Third program test", 5.0 ],
  [ :test4_hidden, "Fourth program test (result is hidden)", 5.0 ],
]
```

The rubric above specifies four rubric items, worth a total of 30 points.
The `:make_succeeds` rubric item represents the requirement that the student
program compile successfully using make.  The `:test1`, `:test2`, `:test3`,
and `:test4_hidden` rubric items represent functional tests which will
evaluate the extent to which the student's submission meets the functional
specifications in the assignment description. If a test name ends in
"`_hidden`", the result of running the test is not revealed to the
student.

### Tasks, task results, and tests

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
If the script succeeds (exits normally with a 0 exit code), then the
[X.run](https://daveho.github.io/declarative-autograder/X.html#run-class_method) task
pushes a true outcome value, and
[X.test](https://daveho.github.io/declarative-autograder/X.html#test-class_method)
records the `:test_add` test as passing.
If the script fails (exits abnormally and/or exits with a non-zero exit code), then
[X.test](https://daveho.github.io/declarative-autograder/X.html#test-class_method)
records `:test_add` as failing.  (In general,
[X.test](https://daveho.github.io/declarative-autograder/X.html#test-class_method)
tasks will consider the subordinate task to have succeeded if the most recent boolean
value it pushed is true.  Since all tasks other than
[X.inorder](https://daveho.github.io/declarative-autograder/X.html#inorder-class_method))
tasks push only a single boolean value, in practice you can think of every task yielding a
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

Tasks such as
[X.run](https://daveho.github.io/declarative-autograder/X.html#run-class_method),
[X.make](https://daveho.github.io/declarative-autograder/X.html#make-class_method),
[X.copy](https://daveho.github.io/declarative-autograder/X.html#copy-class_method), and
[X.test](https://daveho.github.io/declarative-autograder/X.html#test-class_method)
are the fundamental building blocks of an autograder.  However, the autograder will need to run
many tasks in order to fully test and evaluate the student program.
*Sequencing* of tasks is an important concern.  Sometimes we will want to
make the execution of later tasks dependent on the success of earlier tasks,
and sometimes we will want to execute a number of tests independently.

[X.all](https://daveho.github.io/declarative-autograder/X.html#all-class_method)
and [X.inorder](https://daveho.github.io/declarative-autograder/X.html#inorder-class_method) 
provide mechanisms to create [composite](https://en.wikipedia.org/wiki/Composite_pattern)
tasks comprised of a sequence of lower-level tasks.

The
[X.all](https://daveho.github.io/declarative-autograder/X.html#all-class_method)
task executes a series of consitutent tasks in order. Later tasks
are only executed if all previous tasks completed successfully.  So,
[X.all](https://daveho.github.io/declarative-autograder/X.html#all-class_method)
is very useful for specifying prerequisites which must complete successfully before
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

The
[X.inorder](https://daveho.github.io/declarative-autograder/X.html#inorder-class_method) 
task executes a series of tasks, but later tasks are attempted
regardless of whether or not previous tasks succeeded.  The core of an autograder
is typically an
[X.inorder](https://daveho.github.io/declarative-autograder/X.html#inorder-class_method) 
task which executes all of the functional tests associated
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

As you can see, the
[X.all](https://daveho.github.io/declarative-autograder/X.html#all-class_method)
and
[X.inorder](https://daveho.github.io/declarative-autograder/X.html#inorder-class_method) 
tasks provide complete flexibility in determining which tasks are executed.  The
[X.all](https://daveho.github.io/declarative-autograder/X.html#all-class_method)
task shown above could form the *test plan* for an autograder.

### Test plan, test outcomes, log messages

As hinted in the section above, a *test plan* is simply a task which, when
executed, will carry out all of the subordinate tasks needed to test and
evaluate the submitted student program.  The test plan is typically created using
[X.all](https://daveho.github.io/declarative-autograder/X.html#all-class_method)
so that the successful completion of mandatory prerequisite tasks
can be guaranteed before functional tests are executed.

As tests are executed by
[X.test](https://daveho.github.io/declarative-autograder/X.html#test-class_method)
tasks, DAF will update a *results map* recording the outcome of each test.
In the results map, each executed test (identified by the testname symbol,
e.g. `:test_case_1` in the previous example) is mapped to an *outcome pair*.
The outcome pair consists of two values:

* the first value is a number, either 0.0 (failure) or 1.0 (success)
* the second value is an array of log messages to be shown to the student

Log messages are a way that diagnostics produced during task execution can
captured. The *public* log messages are eventually revealed to the student
as part of the record of the outcome of a specific test.  Most task-creation
functions have optional parameters allowing control over which information
is made visible to students: see the
[API documentation](file:///home/daveho/git/declarative-autograder/doc/X.html)
for details.

### Executing the test plan, Results

The [X.execute\_tests]()
function takes the rubric and test plan, and executes the test plan.
As a result, it returns a Ruby Hash object following the schema of a
[Gradescope `results.json` file](https://gradescope-autograders.readthedocs.io/en/latest/specs/#output-format).
This hash has one member, accessed with the key `tests`, whose value is an
array of test result objects.  Each test result object represents the
result of executing the test associated with one rubric item.

The results hash can be written to a JSON file using the
[X.post\_results](https://daveho.github.io/declarative-autograder/X.html#post_results-class_method)
function, which will produce a file called `results/results.json`.
However, the autograder script could easily convert the data in the results
hash to whatever format is desired.

## Writing test scripts

TODO

## Putting it all together

TODO
