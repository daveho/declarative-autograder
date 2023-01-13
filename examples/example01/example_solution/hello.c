#include <stdio.h>

int main(void) {
  char name[7];

  printf("What is your name? ");
  scanf("%6s", name);
  name[6] = '\0';
  printf("Hello, %s\n", name);
  return 0;
}
