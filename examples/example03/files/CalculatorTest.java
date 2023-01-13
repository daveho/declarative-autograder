package edu.jhu.cs.example;

import static org.junit.Assert.assertEquals;

import org.junit.Before;
import org.junit.Test;
import org.junit.runner.JUnitCore;
import org.junit.runner.Request;
import org.junit.runner.Result;

public class CalculatorTest {
  private Calculator calculator;

  @Before
  public void setUp() throws Exception {
    calculator = new Calculator();
  }

  @Test
  public void testIsZeroInitially() {
    assertEquals(0, calculator.get());
  }

  @Test
  public void testSet() {
    calculator.set(11);
    assertEquals(11, calculator.get());
  }

  @Test
  public void testAdd() {
    calculator.add(2);
    calculator.add(3);
    calculator.add(4);
    assertEquals(9, calculator.get());
  }

  @Test
  public void testSub() {
    calculator.set(100);
    calculator.sub(36);
    assertEquals(64, calculator.get());
  }

  // We define a main method in order to support running a single
  // unit test named as a command line parameter
  public static void main(String[] args) {
    String testName = args[0];
    Request request = Request.method(CalculatorTest.class, testName);
    System.out.print("Running test " + testName + "...");
    System.out.flush();
    Result result = new JUnitCore().run(request);
    boolean success = result.wasSuccessful();
    System.out.println(success ? "PASS" : "FAIL");
    System.exit(success ? 0 : 1);
  }

}
