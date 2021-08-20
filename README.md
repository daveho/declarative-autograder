# Declarative autograder framework

This is an experiment to create a general-purpose framework for implementing
[Gradescope](https://www.gradescope.com/) autograders.  (You should read
the [Gradescope autograder specification](https://gradescope-autograders.readthedocs.io/en/latest/specs/)
for more information about how they work.

[autograder2.rb](autograder2.rb) is a result of this experiment.  There is
no documentation or example code yet (TODO, coming soon), but it works pretty
well and supports *very* clean `run_autograder` scripts.

Note that the framework could be adapted fairly easily to run in contexts
other than Gradescope.  The result of autograding is a data structure
representing tests and test outcomes, which could be translated into formats
other than a Gradescope `results.json` file.

The code is distributed under the MIT license.  Comments to <mailto:david.hovemeyer@gmail.com>

## Documentation

See the [Guide](guide.md) and the [API documentation](https://daveho.github.io/declarative-autograder).

## Examples

One way to see how the framework is to look at examples. (TODO: link to examples)
