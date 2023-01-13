# Flexible Gradescope autograder framework
# Copyright (c) 2019-2021 David H. Hovemeyer <david.hovemeyer@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION

# Goal is to allow "declarative" autograders, where the run_autograder
# script specifies a WHAT is tested, not HOW the testing is done

require 'open3'
require 'json'

# Figure out where files are. For local testing, we assume 'files'
# is in the same directory as 'run_autograder', but on the actual
# Gradescope VM, it will be a subdirectory of 'source'.
$files = 'files'
if !File.directory?('files') and File.directory?('source/files')
  $files = 'source/files'
end

# Default timeout for executed commands, in seconds.
DEFAULT_TIMEOUT = 20

# Default subprocess success predicate.
# The default implementation returns +true+ if +status.success?+ evaluates
# to a true value.
DEFAULT_SUCCESS_PRED = ->(status, stdout_str, stderr_str) do
  return status.success?
end

# Default test judge.
# It considers a test to have passed if the last boolean value
# in the outcomes array is true.  This obviously works for
# "normal" tests executed with {#X.run}, which only produce a
# single boolean. It will also work well with tests which
# execute {#X.all}. It is probably not a good choice for tests
# executed with {#X.inorder}, since that produces multiple test
# results in the outcomes array, which may vary in value.
DEFAULT_JUDGE = ->(outcomes) do
  return outcomes[-1] ? 1.0 : 0.0
end

# Wrapper class for rubric.
# It simplifies the lookup of rubric items by testname.
# This class is used internally for test execution and test outcome
# reporting, so autograders won't generally need to use it directly.
# An instance of Rubric is pass to task's +call+ method as the
# +rubric+ parameter.
#
# A rubric specification is an array of _rubric items_.
# Each rubric item is an array with three members:
# - _testname_, a Symbol uniquely identifying a test
# - _description_, a String providing a short description of the test
# - _points_, a number indicating how many points the test is worth
class Rubric
  attr_reader :spec

  # @param [Array] spec Initialize a Rubric object from an array of rubric items
  def initialize(spec)
    @spec = spec
  end

  # Get the description string corresponding to the given test name.
  # @param [Symbol] testname the test name
  # @return [String] the description for the test
  def get_desc(testname)
    @spec.each do |tuple|
      return tuple[1] if tuple[0] == testname
    end
    raise "Internal error: unknown testname #{testname}"
  end

  # @return the total number of points for all rubric items
  def get_total_points
    total = 0.0
    @spec.each do |item|
      total += item[2]
    end
    return total
  end
end

# A Logger object is used by tasks to generate private output
# (visible only to instructors) and public output (visible to students).
#
# An instance of this class is passed to each task's +call+ method
# as the +logger+ parameter.
#
# Private messages are written immediately to standard output, and
# (at least on Gradescope) are visible only to instructors.
#
# Public messages (visible to students) are queued, and are made
# visible by becoming part of the next test outcome.  In general,
# public messages should only be generated as part of test execution.
#
# Student-visible test output is generated with {#log},
# while {#logprivate} generates output that is only visible to instructors.
# {#log_cmd_output} generates either public or private output,
# depending on the value of its visibility parameter.
class Logger
  def initialize
    @msgs = []
  end

  # Send a message to the private log visible only to instructors.
  # Private log messages are immediately written to standard output.
  #
  # @param msg the message to output to the private (instructor-visible) log
  def logprivate(msg)
    # Print to stdout so the message is reported to instructors by Gradescope
    puts "#{Time.now.utc}: #{msg}"
  end

  # Log command output (stdout or stderr) to the reported diagnostics.
  # This method is used for logging the output of programs or scripts.
  # The actual logging is delegated to the {#logprivate} or {#log}
  # methods, depending on the value of the +visibility+ parameter.
  #
  # @param kind what kind of output: each emitted line is prefixed with this string, i.e., +'stdout'+ or +'stderr'+
  # @param output output to log
  # @param visibility either +:public+ or +:private+
  def log_cmd_output(kind, output, visibility)
    logfn = ->(msg) { visibility == :public ? log(msg) : logprivate(msg) }
    logfn.call("#{kind}:")
    output.split("\n").each do |line|
      logfn.call(line)
    end
  end

  # Log a message.
  # The message will be sent to the private (instructor-visible) log,
  # and if the +student_visible+ option is +true+ (default is +true+),
  # then the message will be reported to the student as part of the next
  # test outcome.
  #
  # @param [String] msg the message to log
  # @param [Boolean] student_visible if +true+, message will be visible to student
  def log(msg, student_visible: true)
    # Send to private log
    logprivate(msg)

    if student_visible
      # Save message: will be made part of reported test result
      encoded_msg = nil
      # We want strings to be UTF-8
      encoded_msg = msg.encode('UTF-8', :invalid => :replace, :undef => :replace)
      @msgs.push(encoded_msg)
    end
  end

  # Get all logged public messages (returning a copy to avoid mutation issues)
  # @return [Array<String>] array of logged public messages
  def get_msgs
    return @msgs.clone
  end

  # Clear out accumulated log messages
  # (this should be done once a test result is reported)
  def clear
    @msgs.clear
  end
end

# Tasks
# must support a call method with the following parameters
#   outcomes: list of booleans containing previous test results
#   results: map of testnames to scores (for reporting)
#   logger: for logging diagnostics
#   rubric: the rubric describing the tests
# in general, tasks can (and should) be lambdas

# Public front-end namespace for the autograder framework.
#
# The name "X" has no significance. It was chosen to be as concise as
# possible, in order to make +run_autograder+ scripts as noise-free as possible.
class X
  # Build an array consisting of all arguments as elements, with the
  # exception that arguments that are arrays will have their elements
  # added.  This is useful for building a large argument array
  # out of an arbitrary combination of arrays and individual values.
  #
  # @param args the sequence of values to build
  # @return [Array] array containing the discovered non-array values in +args+
  def self.combine(*args)
    result = []
    args.each do |arg|
      if arg.kind_of?(Array)
        result.concat(arg)
      else
        result.push(arg)
      end
    end
    return result
  end

  # Return list of files matching specified "file glob" pattern in +files+ directory.
  # "File glob" means "shell wildcard", and the pattern is expanded by the Unix shell.
  # This is not a task, it returns an array of the filenamess matching the pattern.
  #
  # @param [String] pattern a file glob pattern, e.g., +*.c+ for all filenames ending in +.c+
  # @return [Array<String>] array of filenames matching the file glob pattern
  def self.glob(pattern)
    result = []
    IO.popen("cd #{$files} && sh -c 'ls -d #{pattern}'") do |f|
      f.each_line do |line|
        line.rstrip!
        result.push(line)
      end
    end
    return result
  end

  # Copy one or more files from the +files+ directory into the +submission+ directory.
  # This is useful for copying test scripts, secret inputs and expected outputs,
  # and other data needed for test execution prior to executing tests.
  #
  # @param files filenames to copy from +files+ to +submission+
  # @param subdir if specified (non-nil), files are copied into this subdirectory of +submission+
  # @param report_command if +true+, command is reported to student (defaults to +true+)
  def self.copy(*files, subdir: nil, report_command: true)
    raise "Internal error: no file specified to copy" if files.empty?
    if files.size == 1
      # base case: copy a single file
      filename = files[0]
      destdir = subdir.nil? ? 'submission' : "submission/#{subdir}"
      return ->(outcomes, results, logger, rubric) do
        logger.log("Copying #{filename} from files...", student_visible: report_command)
        rc = system('cp', "#{$files}/#{filename}", destdir)
        #logger.log("cp result is #{rc}")
        outcomes.push(rc)
      end
    else
      # recursive case: copy multiple files
      tasks = files.map { |filename| X.copy(filename, subdir: subdir, report_command: report_command) }
      return X.all(*tasks)
    end
  end

  # Recursively copy one or more entire directories from the +files+ directory into the +submission+ directory
  #
  # @param dirnames directory names to recursively copy from +files+ into +submission+
  # @param report_command if +true+, command(s) are reported to student (defaults to +true+)
  def self.copydir(*dirnames, report_command: true)
    raise "Internal error: no directory specified to copy" if dirnames.empty?
    if dirnames.size == 1
      # base case: copy a single directory
      dirname = dirnames[0]
      return ->(outcomes, results, logger, rubric) do
        logger.log("Copying directory #{dirname} from files...", student_visible: report_command)
        rc = system('cp', '-r', "#{$files}/#{dirname}", "submission")
        outcomes.push(rc)
      end
    else
      # recursive case: copy multiple directories
      tasks = dirnames.map { |dirname| X.copydir(dirname, report_command: report_command) }
      return X.all(*tasks)
    end
  end

  # Returns a task which will check to see if files in the +submission+ directory exist.
  # The returned task will push a true outcome if and only if all of the files exist.
  #
  # @param filenames filenames of which to check existence
  # @param check_exe if true, the returned task will also check that file(s) are executable (default false)
  # @param [String] subdir if set, file(s) are checked in specified subdirectory of +submission+
  # @return the task object
  def self.check(*filenames, check_exe: false, subdir: nil)
    return ->(outcomes, results, logger, rubric) do
      checkdir = subdir.nil? ? 'submission' : "submission/#{subdir}"
      checks = []
      filenames.each do |filename|
        full_filename = "#{checkdir}/#{filename}"
        logger.log("Checking that #{filename} exists#{check_exe ? ' and is executable' : ''}")
        if File.exists?(full_filename) and (!check_exe || File.executable?(full_filename))
          checks.push(true)
        else
          logger.log("#{filename} doesn't exist#{check_exe ? ', or is not executable' : ''}")
          checks.push(false)
        end
      end
      outcomes.push(checks.all?)
    end
  end

  # Check to see if files in the submission directory exist and are executable.
  # Task will produce a true outcome IFF all of the files exist and are executable.
  #
  # @param filenames filenames of which to check existence/executability
  # @param [String] subdir if set (non-nil), file(s) are checked in specified subdirectory of +submission+
  # @return the task object
  def self.check_exe(*filenames, subdir: nil)
    return check(*filenames, check_exe: true, subdir: subdir)
  end

  # @deprecated Please use {check_exe} instead
  def self.checkExe(*filenames, subdir: nil)
    return check_exe(*filenames, subdir: subdir)
  end

  # Create and return a task to run +make+ in the +submission+ directory
  # (or a specified subdirectory).  Parameters passed to this function are passed
  # as command-line arguments to +make+ (when the task is executed).  With no
  # arguments, the default target will be built.
  #
  # @param makeargs argument strings to pass to +make+
  # @param [String] subdir if specified, make is run in this subdirectory of +submission+
  # @return the task object
  def self.make(*makeargs, subdir: nil)
    return ->(outcomes, results, logger, rubric) do
      # Determine where to run make
      cmddir = subdir.nil? ? 'submission' : "submission/#{subdir}"

      # Make sure the directory actually exists
      raise "Internal error: #{cmddir} directory is missing?" if !File.directory?(cmddir)

      cmd = ['make'] + makeargs
      logger.log("Running command #{cmd.join(' ')}")
      Dir.chdir(cmddir) do
        stdout_str, stderr_str, status = Open3.capture3(*cmd, stdin_data: '')
        if status.success?
          logger.log("Successful make")
          logger.log_cmd_output('Make standard output', stdout_str, :private)
          logger.log_cmd_output('Make standard error', stderr_str, :private)
          outcomes.push(true)
        else
          logger.log("Make failed!")
          logger.log_cmd_output('Make standard output', stdout_str, :public)
          logger.log_cmd_output('Make standard error', stderr_str, :public)
          outcomes.push(false)
        end
      end
    end
  end

  # Create and return a task to run a command (program or script)
  # in the +submission+ directory (or a specified subdirectory).
  #
  # Note that if +stdin_filename+ is specified, its entire contents are read into memory,
  # so you should avoid sending very large files that way.
  #
  # @param  cmd the comand to run (first value is program, subsequent values are program arguments)
  # @param  timeout timeout in seconds
  # @param  timeout_signal signal to send to the process if a timeout occurs, e.g., 'INT' for SIGINT
  # @param  report_command report the executed command to student
  # @param  report_stdout report command stdout to student
  # @param  report_stderr report command stderr to student
  # @param  report_outcome report "Command failed!" if command fails (and report_command is true)
  # @param  stdin_filename name of file to send to command's stdin (if not specified, empty stdin is sent)
  # @param  stdout_filename name of file to write command's stdout to (in the submission directory,
  #                    if not specified, no output file is written)
  # @param  subdir if specified, the command is run in this subdirectory of +submission+
  # @param  env if specified, hash with additional environment variables to set for subprocess
  # @param  success_pred predicate to check subprocess success: must have a +call+ method that
  #                 takes process status object, standard output string, and
  #                 standard error string as parameters, defaults to just checking
  #                 status.success?
  # @param  rlimit_hash if specified, a hash of resource limit keys (e.g., +:rlimit_stack+)
  #                 to their corresponding values, specifying resource limits for the
  #                 subprocess
  # @return the task object
  def self.run(*cmd,
               timeout: DEFAULT_TIMEOUT,
               timeout_signal: nil,
               report_command: true,
               report_stdout: false,
               report_stderr: false,
               report_outcome: true,
               stdin_filename: nil,
               stdout_filename: nil,
               subdir: nil,
               env: {},
               success_pred: DEFAULT_SUCCESS_PRED,
               rlimit_hash: {})
    return ->(outcomes, results, logger, rubric) do
      # Determine where to run the command
      cmddir = subdir.nil? ? 'submission' : "submission/#{subdir}"

      # Make sure the directory actually exists
      raise "Internal error: #{cmddir} directory is missing?" if !File.directory?(cmddir)

      Dir.chdir(cmddir) do
        stdin_data = stdin_filename.nil? ? '' : File.read(stdin_filename, binmode: true)

        # Prepare the command to run (wrapping the requested command using timeout)
        #cmd = ['timeout', timeout.to_s ] + cmd
        cmd_to_run = []
        cmd_to_run.push('timeout')
        cmd_to_run.push("--signal=#{timeout_signal}") if !timeout_signal.nil?
        cmd_to_run.push(timeout.to_s)
        cmd_to_run += cmd

        keyword_args = { stdin_data: stdin_data, binmode: true }
        rlimit_hash.each_pair do |key, value|
          raise "Invalid rlimit key #{key}" if !key.to_s.start_with?('rlimit_')
          keyword_args[key] = value
        end

        #puts "report_command=#{report_command}"
        logger.log("Running command: #{cmd_to_run.join(' ')}", student_visible: report_command)
        stdout_str, stderr_str, status = Open3.capture3(env, *cmd_to_run, **keyword_args)
        logger.log_cmd_output('Standard output', stdout_str, report_stdout ? :public : :private)
        logger.log_cmd_output('Standard error', stderr_str, report_stderr ? :public : :private)
        if !stdout_filename.nil?
          File.open(stdout_filename, 'wb') do |outfh|
            outfh.write(stdout_str)
          end
        end
        if success_pred.call(status, stdout_str, stderr_str)
          outcomes.push(true)
        else
          logger.log("Command failed!", student_visible: report_command && report_outcome)
          outcomes.push(false)
        end
      end
    end
  end

  # Wrapper class to give a predicate function object (i.e., lambda) a +desc+
  # method which returns a human-readable description string.
  # This is useful for autograders which use {eval_pred}, so that the
  # application and result of the predicate can be logged in a meaningful way.
  class Pred
    attr_accessor :pred_func, :desc

    # @param pred_func a predicate function (e..g, a lambda returning a boolean value)
    # @param [String] desc a description of the predicate, e.g. "determine if all unit tests passed"
    def initialize(pred_func, desc)
      @pred_func = pred_func
      @desc = desc
    end

    def call(*args)
      return @pred_func.call(*args)
    end
  end

  # Create a predicate from a lambda and a string with a textual
  # description of the predicate being evaluated.
  # The lambda should take one parameter, the results map.
  # When creating an eval_pred task, using this function to create
  # a predicate is preferred to just using a lambda because it allows
  # the task to generate a meaningful student-visible log message
  # describing what the predicate is evaluating.
  #
  # @param pred_func a predicate function (e..g, a lambda returning a boolean value)
  # @param [String] desc a description of the predicate, e.g. "determine if all unit tests passed"
  def self.pred(pred_func, desc)
    return Pred.new(pred_func, desc)
  end

  # A task that evaluates a predicate and produces an outcome
  # based on the result (true or false) of that predicate.
  # This is useful for "synthetic" tests, i.e., ones whose outcomes
  # aren't based by executing student code, but instead are evaluated
  # by other criteria.  The "pred" parameter must have a "call"
  # function which takes one parameter --- the results map, which
  # allows the predicate to know whether previous tests have passed
  # or failed --- and returns true or false.
  # Suggestion: use the "pred" function to create the predicate,
  # which will allow it to have a meaningful description that can be
  # logged.
  #
  # @param pred a predicate function (ideally, an instance of {Pred})
  # @param report_desc if true, evaluation and result of preddicate are publicly logged
  def self.eval_pred(pred, report_desc: true, report_outcome: true)
    return ->(outcomes, results, logger, rubric) do
      if pred.respond_to?(:desc) && report_desc
        logger.log("Checking predicate: #{pred.desc}")
      end
      outcome = pred.call(results)
      if report_outcome
        logger.log("Predicate evaluated as #{outcome}")
      end
      outcomes.push(outcome)
    end
  end

  # Check whether a test passed.
  # Requires that the results map is available, and contains a
  # recorded result (0 for failure, 1 for success) for the named test.
  # This can be called from within a predicate function,
  # since the results map will be (at least partially) available by
  # that time.
  #
  # @param [Symbol] testname the testname to inquire about
  # @param [Hash] results the results map (map of testnames to evaluated numeric scores)
  # @return [Boolean] true if the test passed, false if the test failed
  def self.test_passed(testname, results)
    if !results.has_key?(testname)
      return false
    end
    result_pair = results[testname]
    return result_pair[0] >= 1.0
  end

  # Return a task which executes a test by invoking the specified task and determining whether
  # its outcome was successful, unsuccessful, or partially successful.
  # The correctness of the test will be reported by being entered in the results map.
  #
  # @param [Symbol] testname the testname of the test to execute (which should have
  #                          a corresponding rubric item!)
  # @param task the task to execute: its success or failure determines whether the
  #             test passes or fails
  # @param judge the judge function used to produce a "correctness score"
  #              in the range 0.0 (completely incorrect) to 1.0 (completely correct)
  #              from the outcomes array; the default judge assigns 0.0 or 1.0
  #              based on the last boolean value in the outcomes array
  # @return the task object
  def self.test(testname, task, judge: DEFAULT_JUDGE)
    return ->(outcomes, results, logger, rubric) do
      logger.log("Executing test: #{rubric.get_desc(testname)}")
      task.call(outcomes, results, logger, rubric)

      # Use judge to determine correctness
      correctness = judge.call(outcomes)
      if correctness < 0.0 || correctness > 1.0
        raise "Judge produced incorrect correctness value #{correctness}"
      end

      # Report on success or failure
      if correctness == 1.0
        logger.log("Test PASSED")
      elsif correctness == 0.0
        logger.log("Test FAILED")
      else
        logger.log("Test resulted in partial credit")
      end

      # Add to results and clear log messages
      results[testname] = [ correctness, logger.get_msgs ]
      logger.clear
    end
  end

  # Return a task which executes all tasks in sequence, auto-failing any tasks that follow
  # a failed task. This is useful for ensuring that prerequisite tasks execute successfully
  # before dependent tasks run.
  #
  # Example:
  #
  #     # make the_program, and if successful, base the outcome of the
  #     # :program_runs test on whether or not it runs successfully
  #     X.all(X.make('the_program'),
  #           X.test(:program_runs, X.run('./the_program')))
  #
  # In the example above, if the +X.make+ task fails (e.g., because of
  # a compilation error), then the +X.test+ task is automatically considered to
  # have failed.
  #
  # When the failure of a task causes subsequent tasks to fail, a message
  # of the form "Task failed, not executing subsequent tasks" will be logged,
  # unless the +report_failure+ parameter is specified as false.
  #
  # A single outcome is pushed: true if all tasks succeeded,
  # false if any tasks failed.
  #
  # @param tasks the sequence of tasks
  # @param [Boolean] report_failure if true, report if a task failure will suppress further tasks (defaults to true)
  # @return the task object
  def self.all(*tasks, report_failure: true)
    return ->(outcomes, results, logger, rubric) do
      task_outcomes = []
      any_failed = false

      # Execute the individual tasks
      count = 0
      tasks.each do |task|
        is_last = (count == tasks.length - 1)

        if any_failed
          # This task gets auto-failed
          task_outcomes.push(false)
          #logger.log("Auto-failing task, yo")
        else
          num_outcomes = task_outcomes.size
          task.call(task_outcomes, results, logger, rubric)
          raise "Internal error: task failed to generate an outcome" if task_outcomes.size < num_outcomes + 1
          any_failed = !task_outcomes[-1]
          raise "Internal error: task generated a non-boolean outcome" if not ([true,false].include?(any_failed))
          logger.log("Task failed, not executing subsequent tasks") if any_failed && report_failure && !is_last
        end
        count += 1
      end

      # If all of the individual tasks succeeded, then the overall 'all' task has succeeded
      outcomes.push(task_outcomes.all?)
      #logger.log("all task outcome: #{outcomes[-1]}")
    end
  end

  # Return a task which executes a sequence of tasks and records their outcomes.
  # Tasks can pass or fail completely independently: i.e., if an earlier task
  # fails, the execution of subsequent tasks will still be attempted.
  #
  # This is very useful for executing tests, where the failure of an earlier
  # test should not prevent a later test from being attempted.
  #
  # Pushes all of the outcomes generated by all of the executed tasks.
  #
  # @param tasks the sequence of tasks
  # @return the task object
  def self.inorder(*tasks)
    return ->(outcomes, results, logger, rubric) do
      tasks.each do |task|
        task.call(outcomes, results, logger, rubric)
      end
    end
  end

  # Return a task which executes all tasks in sequence and pushes their outcomes, but
  # changes all of the outcomes to true, creating the illusion that
  # all tests succeed even if they didn't.  So, the returned task works very much
  # like one created by {inorder}, but where all of the generated outcomes are
  # guaranteed to be true.
  #
  # @param tasks the sequence of tasks
  # @return the task object
  def self.nofail(*tasks)
    return ->(outcomes, results, logger, rubric) do
      task_outcomes = []
      tasks.each do |task|
        task.call(task_outcomes, results, logger, rubric)
      end
      task_outcomes.map! { true }
      outcomes.concat(task_outcomes)
    end
  end

  # Return a task which execute one specified task and expects it to fail.
  # The "inverted" task succeeds if the original task fails,
  # and vice versa.  This can be useful for testing error handling: i.e.,
  # a test sends an erroneous input to a program, and expects the program
  # to report the error by exiting with a non-zero exit code, which
  # is considered a "failed" execution by {run}.
  #
  # @param task the task to invert
  # @return the task object
  def self.expectfail(task)
    return ->(outcomes, results, logger, rubric) do
      task.call(outcomes, results, logger, rubric)
      outcomes.map! { |b| !b }
    end
  end

  # Private method to check a testname to determine whether it specifies
  # a hidden or visible test.  Hidden tests are specified by testnames
  # ending with +_hidden+.
  #
  # @param [Symbol] testname the testname to check
  # @return true if the testname indicates a hidden test, false if it indicates a visible test
  def self._visibility_of(testname)
    return testname.to_s.end_with?('_hidden') ? 'hidden' : 'visible'
  end

  # Internal method to return a result object for a testname that is missing from the results map.
  # Typically, a test with no result was not executed because a prerequisite step
  # (in a task created by {all}) failed, preventing the execution of a subsquent test.
  # The result object will specify a score of 0.0 for the affected test.
  #
  # Autograders should not need to call this method directly.
  #
  # @param [Symbol] testname the testname missing from the results map
  # @param [String] desc the test description from the rubric
  # @param [Number] maxscore the maximum score possible for the rubric item
  def self.result_obj_for_missing_test(testname, desc, maxscore)
    return {
      'name' => desc,
      'score' => 0.0,
      'max_score' => maxscore,
      'output' => 'Test was not executed due to a failed prerequisite step',
      'visibility' => _visibility_of(testname)
    }
  end

  # Internal method to create a result object for an executed test.
  #
  # @param [Symbol] testname the testname missing from the results map
  # @param [String] desc the test description from the rubric
  # @param [Number] maxscore the maximum score possible for the rubric item
  # @param [Array] outcome_pair a two element array: the first element is a 1 or 0
  #                indicating whether the test passed or failed, and the second
  #                element is an array of public log messages to be reported to
  #                the student
  def self.result_obj(testname, desc, maxscore, outcome_pair)
    return {
      'name' => desc,
      'score' => outcome_pair[0] * maxscore,
      'max_score' => maxscore,
      'output' => outcome_pair[1].join("\n"),
      'visibility' => _visibility_of(testname)
    }
  end

  # Execute the tests and return a hash that can be converted into a
  # results JSON file, using the correct schema for a Gradescope +results.json+.
  # This the method which actually executes the test plan and produces the
  # autograder results.
  #
  # @param [Array] rubric the rubric, which is an array of rubric items (see
  #                the documentation for the {Rubric} class)
  # @param plan a task to execute as the overall test plan: this will usually be
  #             created using the {all} method, since prerequisite tasks will
  #             generally need to complete successfully before any actual testing
  #             of the student program can proceed
  # @return [Hash] a hash in Gradescope +results.json+ format with the results
  #                of executing the autograder
  def self.execute_tests(rubric, plan)
    rubric = Rubric.new(rubric)
    logger = Logger.new

    logger.logprivate("Starting autograder (total points is #{rubric.get_total_points()})")

    # results is a map of testnames to earned scores
    results = {}

    # execute the plan
    outcomes = []
    plan.call(outcomes, results, logger, rubric)

    # prepare the report
    results_json = { 'tests' => [] }

    rubric.spec.each do |tuple|
      testname, desc, maxscore = tuple
      if !results.has_key?(testname)
        # no result was reported for this testname
        # this is *probably* because the associated test depended on a prerequisite task that failed
        results_json['tests'].push(result_obj_for_missing_test(testname, desc, maxscore))
      else
        outcome_pair = results[testname]
        results_json['tests'].push(result_obj(testname, desc, maxscore, outcome_pair))
      end
    end

    return results_json
  end

  # Write generated JSON results object to correct location to report
  # autograder results to Gradescope
  def self.post_results(results_json)
    system('mkdir -p results')
    File.open("results/results.json", 'w') do |outf|
      outf.puts JSON.pretty_generate(results_json)
    end
  end
end

# vim:ft=ruby:
