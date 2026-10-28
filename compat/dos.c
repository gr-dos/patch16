/* DOS adapters for patch16: the POSIX functions GNU patch calls that
   libc16 does not have (compat/include/p16.h, unistd.h, signal.h).

   Copyright 2026 patch16 contributors

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2, or (at your option)
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; see the file COPYING.
*/

#include <config.h>
#include <dos.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

/* FP_SEG and FP_OFF below need far data pointers. */
#if !defined __COMPACT__ && !defined __LARGE__
#error patch16 is built in the compact model
#endif

void fatal (char const *, ...);

/* INT 21h function 4400h: 1 if handle FD is a character device. */
static int
is_device (int fd, int *failed)
{
  union REGS r;
  r.x.ax = 0x4400;
  r.x.bx = fd;
  intdos (&r, &r);
  *failed = r.x.cflag != 0;
  return (r.x.dx & 0x80) != 0;
}

int
isatty (int fd)
{
  int failed;
  int dev = is_device (fd, &failed);
  return !failed && dev;
}

/* A regular file's size; DOS keeps no owner or permissions on a handle,
   so the mode is that of a writable file. */
int
fstat (int fd, struct stat *st)
{
  int failed;
  int dev = is_device (fd, &failed);
  if (failed)
    {
      errno = EBADF;
      return -1;
    }
  memset (st, 0, sizeof *st);
  st->st_nlink = 1;
  if (dev)
    st->st_mode = 0x2000 | 0666;	/* a character device */
  else
    {
      long size = filelength (fd);
      if (size < 0)
	return -1;
      st->st_mode = S_IFREG | 0666;
      st->st_size = size;
    }
  return 0;
}

int
chdir (char const *path)
{
  union REGS r;
  struct SREGS s;
  segread (&s);
  r.h.ah = 0x3b;
  r.x.dx = FP_OFF (path);
  s.ds = FP_SEG (path);
  intdosx (&r, &r, &s);
  if (r.x.cflag)
    {
      errno = ENOENT;
      return -1;
    }
  return 0;
}

int
creat (char const *path, int mode)
{
  return open (path, O_WRONLY | O_CREAT | O_TRUNC | O_BINARY,
	       (mode & 0200) ? S_IREAD | S_IWRITE : S_IREAD);
}

/* A new, empty file with a name DOS makes unique (INT 21h function 5Ah,
   DOS 3.0), in the current directory. NAME gets its path. Creating the
   file is what makes the name safe to use: no other program can take it
   between this call and patch16 opening it. */
char *
tmpnam (char *name)
{
  union REGS r;
  struct SREGS s;
  strcpy (name, ".\\");
  memset (name + 2, 0, 14);
  segread (&s);
  r.h.ah = 0x5a;
  r.x.cx = 0;
  r.x.dx = FP_OFF (name);
  s.ds = FP_SEG (name);
  intdosx (&r, &r, &s);
  if (r.x.cflag)
    {
      errno = EACCES;
      return 0;
    }
  close (r.x.ax);
  return name;
}

/* atol for hunk line numbers: a value too large for a long is LONG_MAX,
   which the callers' range checks then reject. */
long
atol (char const *s)
{
  unsigned long v = 0;
  int neg = 0;
  while (*s == ' ' || *s == '\t')
    s++;
  if (*s == '-' || *s == '+')
    neg = *s++ == '-';
  for (;  '0' <= *s && *s <= '9';  s++)
    {
      unsigned d = *s - '0';
      if (v > (LONG_MAX - d) / 10)
	return neg ? -LONG_MAX : LONG_MAX;
      v = v * 10 + d;
    }
  return neg ? -(long) v : (long) v;
}

/* No RCS or SCCS checkout and no ed on DOS. */
int
system (char const *command)
{
  (void) command;
  errno = ENOENT;
  return -1;
}

FILE *
popen (char const *command, char const *mode)
{
  (void) command;
  (void) mode;
  errno = ENOENT;
  return 0;
}

int
pclose (FILE *fp)
{
  (void) fp;
  return -1;
}

int
link (char const *from, char const *to)
{
  (void) from;
  (void) to;
  errno = EACCES;
  return -1;
}

int
getpid (void)
{
  return 1;
}

int
getuid (void)
{
  return 0;
}

/* Signals are not delivered yet: Ctrl-C ends the program as DOS does. */
static p16_sighandler handlers[SIGPIPE + 1];

p16_sighandler
signal (int sig, p16_sighandler handler)
{
  p16_sighandler old;
  if (sig < 0 || sig > SIGPIPE)
    return SIG_DFL;
  old = handlers[sig];
  handlers[sig] = handler;
  return old;
}

int
kill (int pid, int sig)
{
  (void) pid;
  (void) sig;
  return 0;
}

void
abort (void)
{
  fatal ("internal error: abort");
}

void
p16_assert_failed (char const *file, unsigned line)
{
  fatal ("internal error: assertion failed at %s line %d", file, (int) line);
}
