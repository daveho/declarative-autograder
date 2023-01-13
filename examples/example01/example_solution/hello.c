#include <stdio.h>

int main(void) {
  char name[11];

  printf("What is your name? ");
  scanf("%10s", name);
  name[10] = '\0';
  printf("Hello, %s\n", name);
  return 0;
}
