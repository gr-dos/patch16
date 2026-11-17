/* p16_test_point for tests/run.sh's test build, build/patcht.exe.

   P16BREAK raises Ctrl-Break (INT 23h) at a point, as DOS would on
   seeing the key; P16LOSE deletes the file named there, to make the next
   step fail:
     1  after each hunk is applied; the file is the input
        (Ctrl-Break: the handler cleans up and exits 2)
     2  between moving the original aside and moving the new file in;
        the file is the new one
        (Ctrl-Break is ignored there, and the install completes;
        deleting it makes the install fail and put the original back)

   Copyright 2026 patch16 contributors
   GPL version 2 or any later version; see compat/include/config.h.  */

#include <config.h>
#include <dos.h>

static int
at (char const *var, int point)
{
  char const *s = getenv (var);
  return s && *s - '0' == point;
}

void
p16_test_point (int point, char const *name)
{
  union REGS r;

  if (at ("P16LOSE", point))
    unlink (name);
  if (at ("P16BREAK", point))
    int86 (0x23, &r, &r);
}
