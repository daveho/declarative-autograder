# DAF — a Declarative Autograder Framework

This is an experiment to create a general-purpose framework for implementing
[Gradescope](https://www.gradescope.com/) autograders.  (You should read
the [Gradescope autograder specification](https://gradescope-autograders.readthedocs.io/en/latest/specs/)
for more information about how they work.

[autograder2.rb](autograder2.rb) is a result of this experiment.

Note that the framework could be adapted fairly easily to run in contexts
other than Gradescope.  The result of autograding is a data structure
representing tests and test outcomes, which could be translated into formats
other than a Gradescope `results.json` file.

The code is distributed under the MIT license.  Comments to <mailto:david.hovemeyer@gmail.com>

## Documentation

The [Guide](guide.md) documents how to use DAF.

The [API documentation](https://daveho.github.io/declarative-autograder) explains
how the various API functions work.

## Examples

The [examples](examples) directory has several complete example autograders.
