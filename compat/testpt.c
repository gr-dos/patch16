/* p16_test_point for patch.exe: nothing (compat/include/p16.h).

   Copyright 2026 patch16 contributors
   GPL version 2 or any later version; see compat/include/config.h.  */

#include <config.h>

/* tests/breakpt.c takes its place in build/patcht.exe.  */
void
p16_test_point (int point, char const *name)
{
  (void) point;
  (void) name;
}
