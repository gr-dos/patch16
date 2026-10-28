/* Putting a patched file in place on DOS (docs/PORT-FEASIBILITY.md, 5).

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

/* DOS cannot rename a file over an existing one, so replacing FILE with
   a new version takes three renames: FILE aside (to its backup name, or
   to a hidden name in its directory), the new version to FILE, and, if
   that fails, FILE back. Until the new version is in place the original
   is remembered, so that a fatal error puts it back too.

   The same refusal makes rename a safe test for a free name: a backup or
   reject never replaces an existing file, it takes the next name
   (FOO.ORG, FOO.OR1, ... FOO.OR9) instead. */

#include <config.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <backupfile.h>

void copy_file (char const *, char const *);
void fatal (char const *, ...);
void pfatal (char const *, ...);
void say (char const *, ...);

/* The file moved aside and where it is, until the new version is in. */
static char const *pending_file;
static char *pending_aside;

static int
exists (char const *name)
{
  struct stat st;
  return stat (name, &st) == 0;
}

/* The digit for try N goes in the last character of the name. */
#define TRIES 10

static void
set_try (char *name, int n)
{
  if (n)
    name[strlen (name) - 1] = '0' + n;
}

/* Rename FROM to NAME, or to the first of NAME's variants that is free;
   NAME is left holding the name used. Never NAME if that is FROM itself. */
static int
rename_to_free (char const *from, char *name)
{
  int n;
  for (n = stricmp (from, name) == 0;  n < TRIES;  n++)
    {
      set_try (name, n);
      if (rename (from, name) == 0)
	return 0;
      if (errno != EACCES)
	return -1;
    }
  errno = EEXIST;
  return -1;
}

/* A hidden name in FILE's directory, for the original while it is
   replaced. */
static char *
aside_name (char const *file)
{
  static char const hidden[] = "PATCH16$.$$$";
  size_t dirlen = base_name (file) - file;
  char *name = malloc (dirlen + sizeof hidden);
  if (!name)
    fatal ("out of memory");
  memcpy (name, file, dirlen);
  strcpy (name + dirlen, hidden);
  return name;
}

/* Put the original back, if a new version was not put in its place. */
void
p16_restore (void)
{
  char const *file = pending_file;
  char *aside = pending_aside;
  if (!aside)
    return;
  pending_file = 0;
  pending_aside = 0;
  if (exists (file))
    unlink (file);
  if (rename (aside, file) != 0)
    fprintf (stderr, "patch16: the original %s is saved as %s\n",
	     file, aside);
}

/* Replace TO with FROM, keeping the original as BAKNAME (a name made
   with addext, which this may change to the next free one) if BAKNAME
   is not null. */
void
p16_move_file (char const *from, char const *to, char *bakname)
{
  char *aside = 0;
  int keep = bakname != 0;

  if (exists (to))
    {
      aside = keep ? bakname : aside_name (to);
      if (rename_to_free (to, aside) != 0)
	pfatal ("Can't rename `%s' to `%s'", to, aside);
      if (keep)
	say ("Saving the original %s as %s\n", to, aside);
      pending_file = to;
      pending_aside = aside;
    }

  if (rename (from, to) != 0)
    {
      if (errno != EXDEV)
	pfatal ("Can't rename `%s' to `%s'", from, to);
      /* Another drive: copy_file exits through fatal on an error, and
	 p16_restore takes back the partial copy. */
      copy_file (from, to);
      unlink (from);
    }

  pending_file = 0;
  pending_aside = 0;
  if (aside && !keep)
    {
      if (unlink (aside) != 0)
	say ("Can't remove `%s'; it holds the original %s\n", aside, to);
      free (aside);
    }
}

/* Move FROM to NAME, or to the first free variant of it, which NAME is
   left holding; never replace an existing file. */
void
p16_move_new (char const *from, char *name)
{
  int n;
  if (rename_to_free (from, name) == 0)
    return;
  if (errno != EXDEV)
    pfatal ("Can't rename `%s' to `%s'", from, name);
  for (n = 0;  n < TRIES;  n++)
    {
      set_try (name, n);
      if (!exists (name))
	{
	  copy_file (from, name);
	  unlink (from);
	  return;
	}
    }
  fatal ("%s and its variants all exist", name);
}
