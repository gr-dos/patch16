/* Message formatting for patch16 (compat/include/p16.h).

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

/* Only these conversions are formatted, as GNU patch uses them:
   %s, %c, %d, %ld, %o and %%, each with an optional decimal field width
   (right-justified, padded with spaces). Anything else is an internal
   error. */

#include <config.h>
#include <libc16.h>
#include <string.h>

void fatal_exit (int);

/* Where formatted text goes: a stream, through a small buffer so that a
   message takes a few DOS calls rather than one per byte, or a string. */
struct sink
{
  FILE *fp;
  char *str;
  char buf[128];
  unsigned used;
  int count;
  int failed;
};

static void
flush_sink (struct sink *k)
{
  if (k->fp && k->used)
    {
      if (fwrite (k->buf, 1, k->used, k->fp) != k->used)
        k->failed = 1;
      k->used = 0;
    }
}

static void
put (struct sink *k, char const *s, unsigned n)
{
  k->count += n;
  if (k->str)
    {
      memcpy (k->str, s, n);
      k->str += n;
      return;
    }
  while (n)
    {
      unsigned room = sizeof k->buf - k->used;
      unsigned m = n < room ? n : room;
      memcpy (k->buf + k->used, s, m);
      k->used += m;
      s += m;
      n -= m;
      if (k->used == sizeof k->buf)
        flush_sink (k);
    }
}

static void
put_field (struct sink *k, char const *s, unsigned n, unsigned width)
{
  static char const spaces[] = "        ";
  while (n < width)
    {
      unsigned pad = width - n;
      if (pad > sizeof spaces - 1)
        pad = sizeof spaces - 1;
      put (k, spaces, pad);
      width -= pad;
    }
  put (k, s, n);
}

static void
bad_format (char const *format)
{
  static char const msg[] = "patch16: **** internal error: unsupported format `";
  fwrite (msg, 1, sizeof msg - 1, stderr);
  fputs (format, stderr);
  fputs ("'\n", stderr);
  fatal_exit (0);
}

static int
format (struct sink *k, char const *format, va_list args)
{
  char const *f = format;
  char num[34];

  while (*f)
    {
      char const *start = f;
      unsigned width = 0;
      int is_long = 0;
      char const *s;

      while (*f && *f != '%')
        f++;
      if (f != start)
        put (k, start, f - start);
      if (!*f)
        break;
      f++;
      while ('0' <= *f && *f <= '9')
        {
          width = width * 10 + (*f++ - '0');
          if (width > 80)
            bad_format (format);
        }
      if (*f == 'l')
        {
          is_long = 1;
          f++;
        }
      switch (*f)
        {
        case '%':
          if (width || is_long)
            bad_format (format);
          put (k, "%", 1);
          break;
        case 's':
          if (is_long)
            bad_format (format);
          s = va_arg (args, char const *);
          put_field (k, s, strlen (s), width);
          break;
        case 'c':
          if (is_long)
            bad_format (format);
          num[0] = (char) va_arg (args, int);
          put_field (k, num, 1, width);
          break;
        case 'd':
          s = libc16_ltoa (is_long ? va_arg (args, long)
                           : (long) va_arg (args, int), num, 10);
          put_field (k, s, strlen (s), width);
          break;
        case 'o':
          s = libc16_ultoa (is_long ? va_arg (args, unsigned long)
                            : (unsigned long) va_arg (args, unsigned), num, 8);
          put_field (k, s, strlen (s), width);
          break;
        default:
          bad_format (format);
        }
      f++;
    }
  flush_sink (k);
  if (k->str)
    *k->str = '\0';
  return k->failed ? -1 : k->count;
}

int
p16_vfprintf (FILE *fp, char const *fmt, va_list args)
{
  struct sink k;
  k.fp = fp;
  k.str = 0;
  k.used = 0;
  k.count = 0;
  k.failed = 0;
  return format (&k, fmt, args);
}

int
p16_fprintf (FILE *fp, char const *fmt, ...)
{
  va_list args;
  int r;
  va_start (args, fmt);
  r = p16_vfprintf (fp, fmt, args);
  va_end (args);
  return r;
}

int
p16_printf (char const *fmt, ...)
{
  va_list args;
  int r;
  va_start (args, fmt);
  r = p16_vfprintf (stdout, fmt, args);
  va_end (args);
  return r;
}

int
p16_sprintf (char *str, char const *fmt, ...)
{
  struct sink k;
  va_list args;
  int r;
  k.fp = 0;
  k.str = str;
  k.used = 0;
  k.count = 0;
  k.failed = 0;
  va_start (args, fmt);
  r = format (&k, fmt, args);
  va_end (args);
  return r;
}

void
p16_perror (char const *s)
{
  int errnum = errno;
  if (s && *s)
    {
      fputs (s, stderr);
      fputs (": ", stderr);
    }
  fputs (strerror (errnum), stderr);
  fputs ("\n", stderr);
}
