/* Which file names from a patch patch16 will write to (DESIGN.md, section
   7): a relative DOS name, each part of it 8.3, that stays in the current
   directory (or -d's) and names no DOS device.

   A patch's names are not trusted: one made by anyone could name
   ..\AUTOEXEC.BAT, C:\CONFIG.SYS or PRN. Names given on the command line
   or at the "File to patch:" prompt are the user's own, and are not
   checked. fetchname (src/util.c) has already stripped -p's parts and
   made each \ a /.

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
#include <string.h>

/* DOS's own devices. A device's name is a device in every directory and
   with any extension (NUL.TXT is NUL). Drivers loaded in CONFIG.SYS can
   add more names; those are not known here.  */
static char const *const devices[] = {
  "AUX", "CLOCK$", "CON", "NUL", "PRN",
  "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
  "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
  0
};

static int
upper (int c)
{
  return 'a' <= c && c <= 'z' ? c - 'a' + 'A' : c;
}

/* Whether the N bytes at S are DOS device NAME, ignoring case.  */
static int
is_named (char const *s, unsigned n, char const *name)
{
  unsigned i;
  if (strlen (name) != n)
    return 0;
  for (i = 0;  i < n;  i++)
    if (upper ((unsigned char) s[i]) != name[i])
      return 0;
  return 1;
}

/* A byte DOS takes in a name: not a control character, a blank, or one
   of its separators and wildcards. Code page bytes (128 and up) are
   taken, as DOS takes them.  */
static int
name_byte (int c)
{
  return 0x20 < c && c != 0x7f && !strchr ("\"*+,./:;<=>?[\\]|", c);
}

/* Why NAME is not one patch16 writes to, as the end of "patch16 does not
   patch ...", or 0 if it is one.  */
char const *
p16_unsafe_name (char const *name)
{
  char const *s = name;

  if (*s == '/')
    return "a file named from the root";
  if (s[0] && s[1] == ':')
    return "a file on a named drive";
  for (;;)
    {
      char const *part = s;
      unsigned base, ext = 0;
      int dot = 0;
      char const *const *d;

      while (*s && *s != '/' && *s != '.')
	s++;
      base = (unsigned) (s - part);
      if (*s == '.')
	{
	  char const *e = ++s;
	  dot = 1;
	  while (*s && *s != '/')
	    s++;
	  ext = (unsigned) (s - e);
	}
      if (base == 0 && dot && ext == 0 && (!*s || *s == '/'))
	;			/* "." */
      else if (base == 0 && dot && ext == 1 && part[1] == '.'
	       && (!*s || *s == '/'))
	return "a file outside the current directory";	/* ".." */
      else
	{
	  char const *p;
	  if (base == 0 || 8 < base || 3 < ext || (dot && ext == 0))
	    return "a file whose name is not a DOS 8.3 name";
	  for (p = part;  p < s;  p++)
	    if (!name_byte ((unsigned char) *p) && !(*p == '.' && p == part + base))
	      return "a file whose name is not a DOS 8.3 name";
	  for (d = devices;  *d;  d++)
	    if (is_named (part, base, *d))
	      return "a DOS device";
	}
      if (!*s)
	return 0;
      s++;			/* the / */
      if (!*s)
	return "a file whose name is not a DOS 8.3 name";	/* "DIR/" */
    }
}
