/* assert.h for patch16: a failed assertion is an internal error, reported
   through fatal () so that temporary files are removed (exit status 2).

   Copyright 2026 patch16 contributors
   GPL version 2 or any later version; see compat/include/config.h.  */

#ifndef PATCH16_ASSERT_H
#define PATCH16_ASSERT_H

void p16_assert_failed (char const *, unsigned);

#define assert(e) ((e) ? (void) 0 : p16_assert_failed (__FILE__, __LINE__))

#endif
