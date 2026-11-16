/* p16_test_point for tests/run.sh's test build, patch16t.exe: raise
   Ctrl-Break (INT 23h) at the point named by the environment variable
   P16BREAK, as DOS would on seeing the key:
     1  after each hunk is applied (the handler cleans up and exits 2)
     2  between moving the original aside and moving the new file in
        (Ctrl-Break is ignored there, and the install completes)

   Copyright 2026 patch16 contributors
   GPL version 2 or any later version; see compat/include/config.h.  */

#include <config.h>
#include <dos.h>

void
p16_test_point (int point)
{
  char const *s = getenv ("P16BREAK");
  union REGS r;

  if (s && *s - '0' == point)
    int86 (0x23, &r, &r);
}
