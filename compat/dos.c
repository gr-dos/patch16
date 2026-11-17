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

/* DOS has one current directory per drive, shared with the shell that
   ran patch16, so -d's change is undone at exit (p16_exit): the drive
   that was current, and the directory that was current on the drive -d
   named. */
static int dir_saved;
static unsigned char home_drive;	/* 0 for A: */
static char home_dir[3 + 64 + 1];	/* "X:\" and DOS's 64 bytes */

static unsigned char
current_drive (void)
{
  union REGS r;
  r.h.ah = 0x19;
  intdos (&r, &r);
  return r.h.al;
}

static void
select_drive (unsigned char drive)
{
  union REGS r;
  r.h.ah = 0x0e;
  r.h.dl = drive;
  intdos (&r, &r);
}

/* INT 21h function 3Bh. */
static int
set_dir (char const *path)
{
  union REGS r;
  struct SREGS s;
  segread (&s);
  r.h.ah = 0x3b;
  r.x.dx = FP_OFF (path);
  s.ds = FP_SEG (path);
  intdosx (&r, &r, &s);
  return r.x.cflag ? -1 : 0;
}

int
chdir (char const *path)
{
  union REGS r;
  struct SREGS s;
  char *dir = home_dir + 3;
  unsigned char drive = current_drive ();
  unsigned char target = drive;

  if (path[0] && path[1] == ':')
    target = (unsigned char) ((path[0] | 0x20) - 'a');
  if (!dir_saved)
    {
      /* INT 21h function 47h: the directory, without "X:\". */
      home_drive = drive;
      home_dir[0] = (char) ('A' + target);
      home_dir[1] = ':';
      home_dir[2] = '\\';
      segread (&s);
      r.h.ah = 0x47;
      r.h.dl = (unsigned char) (target + 1);
      r.x.si = FP_OFF (dir);
      s.ds = FP_SEG (dir);
      intdosx (&r, &r, &s);
      if (r.x.cflag)
	{
	  errno = ENOENT;
	  return -1;
	}
      dir_saved = 1;
    }
  if (set_dir (path) != 0)
    {
      errno = ENOENT;
      return -1;
    }
  if (target != drive)
    select_drive (target);
  return 0;
}

#undef exit
void
p16_exit (int status)
{
  if (dir_saved)
    {
      dir_saved = 0;
      set_dir (home_dir);
      select_drive (home_drive);
    }
  exit (status);
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

int
getpid (void)
{
  return 1;
}

/* Ctrl-C and Ctrl-Break (INT 23h) are SIGINT. DOS calls INT 23h with
   the program's own stack and registers as at the INT 21h call that saw
   the key, and any DOS function may be called from it. GNU patch's
   handler cleans up and exits (2); while it ignores SIGINT, around the
   renames that install a file, this returns and DOS carries on. Before
   GNU patch sets a handler, Ctrl-C exits (2) with the directory -d
   changed put back. */
static p16_sighandler handlers[SIGPIPE + 1];

static void __interrupt __far
on_break (void)
{
  p16_sighandler h = handlers[SIGINT];
  if (h == SIG_IGN)
    return;
  if (h == SIG_DFL)
    p16_exit (2);
  h (SIGINT);
}

/* A critical error (INT 24h: a drive not ready, a write-protected disk)
   fails the DOS call, which patch16 then reports and cleans up after,
   rather than asking "Abort, Retry, Fail?", where Abort would end it
   with no cleanup. FAIL needs DOS 3.0, as tmpnam does. */
static int __cdecl __far
on_critical (unsigned deverror, unsigned errcode, unsigned __far *devhdr)
{
  (void) deverror;
  (void) errcode;
  (void) devhdr;
  return _HARDERR_FAIL;
}

void
p16_init (void)
{
  _dos_setvect (0x23, on_break);
  _harderr (on_critical);
}

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
