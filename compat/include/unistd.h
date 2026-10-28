/* unistd.h for patch16: the POSIX names GNU patch uses, from libc16's
   Microsoft-style headers and patch16's DOS adapters (compat/dos.c).

   Copyright 2026 patch16 contributors
   GPL version 2 or any later version; see compat/include/config.h.  */

#ifndef PATCH16_UNISTD_H
#define PATCH16_UNISTD_H

#include <direct.h>
#include <io.h>
#include <stdlib.h>

/* common.h declares lseek K&R-style unless it is a macro.  */
#define lseek lseek

/* DOS directories have no permissions: libc16's mkdir takes no mode.  */
#define mkdir(path, mode) mkdir (path)

int isatty (int);
int chdir (char const *);
int creat (char const *, int);
int getpid (void);
int getuid (void);
int link (char const *, char const *);
int system (char const *);

#endif
