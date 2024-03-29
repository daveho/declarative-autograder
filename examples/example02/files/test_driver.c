#include <stdlib.h>
#include "tctest.h"
#include "stack.h"

/*
 * An instance of the TestObjs data type contains the
 * test fixture available to each test function.
 */
typedef struct {
	Stack *s;
} TestObjs;

/* The setup function creates the test fixture. */
TestObjs *setup();

/* The cleanup function cleans up the test fixture. */
void cleanup(TestObjs *objs);

/* Each test function gets a pointer to the test fixture object. */
void testPush(TestObjs *objs);
void testPushMany(TestObjs *objs);
void testSwapTopElts(TestObjs *objs);
void testSizeIsEven(TestObjs *objs);
void testSegfaultBeforeAssert(TestObjs *objs);

int main(int argc, char **argv) {
	if (argc > 2) {
		printf("Usage: %s [<test name>]\n", argv[0]);
		return 1;
	}

	/*
	 * If a command line argument is passed, it's the name
	 * of the test to be executed.
	 */
	if (argc == 2) {
		tctest_testname_to_execute = argv[1];
	}

	/* Prepare to run tests */
	TEST_INIT();

	/* Execute test functions */
	TEST(testPush);
	TEST(testPushMany);
	TEST(testSwapTopElts);
	TEST(testSizeIsEven);
	TEST(testSegfaultBeforeAssert);

	/*
	 * Report results: exits with nonzero exit code if
	 * any test failed
	 */
	TEST_FINI();
}

TestObjs *setup() {
	TestObjs *objs = malloc(sizeof(TestObjs));
	objs->s = stackCreate();
	return objs;
}

void cleanup(TestObjs *objs) {
	stackDestroy(objs->s);
	free(objs);
}

void testPush(TestObjs *objs) {
	int x;

	ASSERT(stackIsEmpty(objs->s));
	ASSERT(stackPush(objs->s, 1));
	ASSERT(stackPush(objs->s, 2));
	ASSERT(stackPush(objs->s, 3));

	ASSERT(stackPop(objs->s, &x));
	ASSERT(3 == x);
	ASSERT(stackPop(objs->s, &x));
	ASSERT(2 == x);
	ASSERT(stackPop(objs->s, &x));
	ASSERT(1 == x);
}

void testPushMany(TestObjs *objs) {
	for (int i = 1; i < STACK_MAX; i++) {
		ASSERT(stackPush(objs->s, i));
	}

	/* stack should be full at this point */
	ASSERT(!stackPush(objs->s, 11));
}

void testSwapTopElts(TestObjs *objs) {
	int x;

	ASSERT(stackPush(objs->s, 1));
	ASSERT(stackPush(objs->s, 2));
	ASSERT(stackPush(objs->s, 3));

	ASSERT(stackSwapTopElts(objs->s));

	ASSERT(stackPop(objs->s, &x));
	ASSERT(2 == x);
	ASSERT(stackPop(objs->s, &x));
	ASSERT(3 == x);
}

void testSizeIsEven(TestObjs *objs) {
	ASSERT(stackPush(objs->s, 1));
	ASSERT(stackPush(objs->s, 2));
	ASSERT(stackPush(objs->s, 3));
	ASSERT(!stackSizeIsEven(objs->s));

	int x;
	ASSERT(stackPop(objs->s, &x));
	ASSERT(stackSizeIsEven(objs->s));
}

void testSegfaultBeforeAssert(TestObjs *objs) {
	/* This test causes a segfault before any ASSERT is executed */
	int x;
	stackPush(objs->s, 1);
	stackPush(objs->s, 2);
	stackPush(objs->s, 3);
	stackSwapTopElts(objs->s);
	ASSERT(stackPop(objs->s, &x));
	ASSERT(2 == x);
	ASSERT(stackPop(objs->s, &x));
	ASSERT(3 == x);
}
