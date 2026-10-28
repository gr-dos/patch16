/* p16.h: patch16's replacements for what libc16 leaves out.

   libc16 has no printf family (its decision 3). GNU patch's messages use
   only %s, %c, %d, %ld, %o and a field width, so compat/fmt.c formats
   exactly those and nothing else: any other conversion is an internal
   error. The standard names are macros for these, so GNU patch's call
   sites stay as they are.

   Copyright 2026 patch16 contributors
   GPL version 2 or any later version; see compat/include/config.h.  */

#ifndef PATCH16_P16_H
#define PATCH16_P16_H

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>

int p16_vfprintf (FILE *, char const *, va_list);
int p16_fprintf (FILE *, char const *, ...);
int p16_printf (char const *, ...);
int p16_sprintf (char *, char const *, ...);
void p16_perror (char const *);

#define vfprintf p16_vfprintf
#define fprintf p16_fprintf
#define printf p16_printf
#define sprintf p16_sprintf
#define perror p16_perror

/* Output to stdout and stderr is unbuffered in libc16.  */
#define setbuf(fp, b) ((void) 0)

/* DOS adapters (compat/dos.c).  */
int fstat (int, struct stat *);
char *tmpnam (char *);
#define L_tmpnam 80
FILE *popen (char const *, char const *);
int pclose (FILE *);
long atol (char const *);
void abort (void);

/* Installing patched files and rejects (compat/install.c).  */
void p16_move_file (char const *, char const *, char *);
void p16_move_new (char const *, char *);
void p16_restore (void);

/* libc16 has no memchr; GNU patch's memchr.c provides it.  */
void *memchr (void const *, int, size_t);

#ifndef ENOTDIR
#define ENOTDIR ENOENT
#endif

#endif
