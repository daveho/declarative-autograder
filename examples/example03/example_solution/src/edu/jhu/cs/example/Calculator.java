package edu.jhu.cs.example;

public class Calculator {
  private int mem;

  public Calculator() {
    this.mem = 0;
  }

  public int get() {
    return this.mem;
  }

  public void set(int val) {
    this.mem = val;
  }

  public void add(int x) {
    this.mem += x;
  }

  public void sub(int x) {
    this.mem -= x;
  }

  public void mul(int x) {
    this.mem *= x;
  }

  public void div(int x) {
    this.mem /= x;
  }
}
