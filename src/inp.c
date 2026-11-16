/* inputting files to be patched */

/* $Id: inp.c,v 1.9 1997/04/17 16:15:48 eggert Exp $ */

/*
Copyright 1986, 1988 Larry Wall
Copyright 1991, 1992, 1993, 1997 Free Software Foundation, Inc.
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
If not, write to the Free Software Foundation,
59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/

#define XTERN extern
#include <common.h>
#include <backupfile.h>
#include <pch.h>
#include <util.h>
#undef XTERN
#define XTERN
#include <inp.h>

/* Input-file-with-indexable-lines abstract type */

/* patch16: plans A and B are replaced by a line index of bounded size
   (docs/PORT-FEASIBILITY.md, section 4).  Plan A kept the whole file in
   one allocation, which a 16-bit size_t limits to under 64 KB; plan B
   kept fixed-width records as wide as the longest line, so one long line
   made the temporary file huge.  Here the index holds the file offset of
   each line's start, INDEX_BLOCK to a block; blocks beyond the first go
   to the temporary file TMPINNAME, and two are cached.  Line text is read
   from the input file itself into one of two windows, one for each
   WHICHBUF of ifetch.  Memory use is fixed, apart from windows grown for
   lines longer than WINDOW_SIZE, up to INPUT_LINE_MAX.  */

#define INDEX_BLOCK 1024		/* line offsets in an index block */
#define WINDOW_SIZE 8192		/* bytes of input read at once */
#define INPUT_LINE_MAX 32000		/* longest input line, in bytes */
#define LINENUM_MAX_INPUT 500000000L	/* so 4-byte index offsets fit a long */

static int ifd = -1;			/* the input file */
static int xfd = -1;			/* blocks of the index, or -1 */
static long *xblock[2];			/* two cached index blocks */
static LINENUM xbase[2] = {-1, -1};	/* first entry of each, or -1 */
static int xnext;			/* the cached block to replace next */
static LINENUM crlf_lines;		/* input lines ending CR LF */
static LINENUM lf_lines;		/* and LF alone */

struct window
{
  char *text;
  long start;				/* file offset of text[0] */
  size_t len;				/* bytes of the file in text */
  size_t size;				/* bytes allocated */
};
static struct window win[2];

static long line_start PARAMS ((LINENUM));
static void index_input PARAMS ((char const *));
static void report_revision PARAMS ((int));

/* New patch--prepare to edit another file. */

void
re_input()
{
    /* patch16: also called before the output replaces the input file,
       which DOS cannot rename while it is open.  */
    if (0 <= ifd)
      close (ifd);
    ifd = -1;
    if (0 <= xfd)
      close (xfd);
    xfd = -1;
    xbase[0] = xbase[1] = -1;
    win[0].len = win[1].len = 0;
}

/* Constuct the line index, somehow or other. */

void
scan_input(filename)
char *filename;
{
    using_plan_a = FALSE;		/* patch16: running out is fatal */
    index_input (filename);
    switch (verbosity)
      {
      case SILENT:
	break;

      case VERBOSE:
	say ("Patching file %s (%ld lines)...\n", filename, input_lines);
	break;

      case DEFAULT_VERBOSITY:
	say ("patching file %s\n", filename);
	break;
      }
}

/* Report whether a desired revision was found.  */

static void
report_revision (found_revision)
     int found_revision;
{
  if (found_revision)
    {
      if (verbosity == VERBOSE)
	say ("Good.  This file appears to be the %s version.\n", revision);
    }
  else if (force)
    {
      if (verbosity != SILENT)
	say ("Warning: this file doesn't appear to be the %s version--patching anyway.\n",
	     revision);
    }
  else if (batch)
    {
      fatal ("this file doesn't appear to be the %s version--aborting.",
	     revision);
    }
  else
    {
      ask ("This file doesn't appear to be the %s version--patch anyway? [n] ",
	   revision);
      if (*buf != 'y')
	fatal ("aborted");
    }
}


void
get_input_file (filename, outname)
     char const *filename;
     char const *outname;
{

    if (inerrno == -1)
      inerrno = stat (inname, &instat) == 0 ? 0 : errno;
    if (inerrno && ok_to_create_file) {
      int fd;
      if (verbosity == VERBOSE)
	say ("(Creating file %s...)\n", inname);
      if (dry_run) {
	inerrno = 0;
	instat.st_mode = 0;
	instat.st_size = 0;
	return;
      }
      makedirs (inname);
      fd = creat (inname, S_IRUSR|S_IWUSR|S_IRGRP|S_IWGRP|S_IROTH|S_IWOTH);
      if (fd < 0)
	inerrno = errno;
      else {
	inerrno = fstat (fd, &instat) == 0 ? 0 : errno;
	if (close (fd) != 0)
	  inerrno = errno;
      }
    }

    /* patch16: no RCS or SCCS checkout (decision 5).  */
    if (inerrno)
      fatal ("can't find %s", filename);
    if (!S_ISREG (instat.st_mode))
	fatal ("%s is not a regular file--can't patch", filename);
}


/* patch16: index FILENAME's lines, and check for the Prereq: revision
   as plan B did.  */

static void
index_input (filename)
     char const *filename;
{
  LINENUM line = 0;			/* lines started */
  long here = 0;			/* file offset of buf[0] */
  long begin = 0;			/* where the current line began */
  int n, k;
  int found_revision = !revision;
  char const *rev = revision;
  size_t revlen = rev ? strlen (rev) : 0;
  size_t i = 0;
  int prev = 0;				/* the byte before c */

  re_input ();
  crlf_lines = lf_lines = 0;
  for (k = 0;  k < 2;  k++)
    {
      if (!xblock[k])
	xblock[k] = (long *) xmalloc (INDEX_BLOCK * sizeof (long));
      if (!win[k].text)
	{
	  win[k].text = xmalloc (WINDOW_SIZE);
	  win[k].size = WINDOW_SIZE;
	}
    }

  /* An empty file need not exist, as in a dry run that creates it.  */
  if (instat.st_size != 0)
    {
      ifd = open (filename, O_RDONLY | O_BINARY);
      if (ifd < 0)
	pfatal ("can't open file %s", filename);
    }

  /* xblock[0] collects the index; a full block is written out.  */
  while (0 <= ifd && (n = read (ifd, win[0].text, WINDOW_SIZE)) != 0)
    {
      if (n < 0)
	read_fatal ();
      for (k = 0;  k < n;  k++)
	{
	  int c = (unsigned char) win[0].text[k];
	  long at = here + k;

	  if (at == begin)
	    {
	      if (line % INDEX_BLOCK == 0 && line)
		{
		  if (xfd < 0
		      && (xfd = creat (TMPINNAME, S_IRUSR|S_IWUSR)) < 0)
		    pfatal ("can't create %s", TMPINNAME);
		  if (write (xfd, (char *) xblock[0],
			     INDEX_BLOCK * sizeof (long))
		      != INDEX_BLOCK * sizeof (long))
		    write_fatal ();
		}
	      xblock[0][line++ % INDEX_BLOCK] = at;
	      if (LINENUM_MAX_INPUT < line)
		fatal ("%s has more than %ld lines, patch16's limit",
		       filename, LINENUM_MAX_INPUT);
	    }
	  if (c == '\n')
	    {
	      begin = at + 1;
	      if (prev == '\r')
		crlf_lines++;
	      else
		lf_lines++;
	    }
	  else if (INPUT_LINE_MAX <= at - begin)
	    fatal ("line %ld of %s is longer than %d bytes, patch16's limit",
		   line, filename, INPUT_LINE_MAX);

	  /* Plan B's search for the revision, a word of its own.  */
	  if (!found_revision)
	    {
	      if (i == revlen)
		{
		  found_revision = ISSPACE ((unsigned char) c);
		  i = (size_t) -1;
		}
	      else if (i != (size_t) -1)
		i = rev[i]==c ? i + 1 : (size_t) -1;

	      if (i == (size_t) -1  &&  ISSPACE ((unsigned char) c))
		i = 0;
	    }
	  prev = c;
	}
      here += n;
    }
  if (!found_revision && i == revlen)
    found_revision = TRUE;		/* the revision ends the file */
  if (revision)
    report_revision (found_revision);

  /* One entry more: the end of the last line.  */
  input_lines = line;
  if (line % INDEX_BLOCK == 0 && line)
    {
      if (xfd < 0 && (xfd = creat (TMPINNAME, S_IRUSR|S_IWUSR)) < 0)
	pfatal ("can't create %s", TMPINNAME);
      if (write (xfd, (char *) xblock[0], INDEX_BLOCK * sizeof (long))
	  != INDEX_BLOCK * sizeof (long))
	write_fatal ();
    }
  xblock[0][line % INDEX_BLOCK] = here;
  if (xfd < 0)
    xbase[0] = 0;			/* the whole index is in memory */
  else
    {
      if (write (xfd, (char *) xblock[0],
		 (line % INDEX_BLOCK + 1) * sizeof (long))
	  != (line % INDEX_BLOCK + 1) * sizeof (long)
	  || close (xfd) != 0)
	write_fatal ();
      if ((xfd = open (TMPINNAME, O_RDONLY | O_BINARY)) < 0)
	pfatal ("can't reopen file %s", TMPINNAME);
    }
}

/* patch16: the line ends most of the input's lines have: 1 for CR LF,
   0 for LF alone, or -1 if no line has one (a tie is LF).  */

int
input_eol ()
{
  if (!crlf_lines && !lf_lines)
    return -1;
  return lf_lines < crlf_lines;
}

/* patch16: the offset of line SLOT + 1's start; SLOT input_lines is the
   end of the file.  */

static long
line_start (slot)
     LINENUM slot;
{
  LINENUM base = slot - slot % INDEX_BLOCK;
  int b;

  if (xbase[0] == base)
    b = 0;
  else if (xbase[1] == base)
    b = 1;
  else
    {
      b = xnext;
      xnext = !xnext;
      xbase[b] = -1;
      if (lseek (xfd, base * (long) sizeof (long), SEEK_SET) == -1
	  || read (xfd, (char *) xblock[b], INDEX_BLOCK * sizeof (long)) < 0)
	read_fatal ();
      xbase[b] = base;
    }
  return xblock[b][slot - base];
}

/* Fetch a line from the input file.  patch16: the text stays valid until
   the next call with the same WHICHBUF.  */

char const *
ifetch (line, whichbuf, psize)
register LINENUM line;
int whichbuf;
size_t *psize;
{
    struct window *w = &win[whichbuf != 0];
    long start, end;
    size_t len;

    if (line < 1 || line > input_lines) {
	*psize = 0;
	return "";
    }
    start = line_start (line - 1);
    end = line_start (line);
    len = end - start;			/* at most INPUT_LINE_MAX + 1 */
    if (! (w->start <= start && end <= w->start + (long) w->len)) {
	size_t want = len < WINDOW_SIZE ? WINDOW_SIZE : len;
	int n;
	if (w->size < want) {
	    char *t = realloc (w->text, want);
	    if (!t)
		memory_fatal ();
	    w->text = t;
	    w->size = want;
	}
	w->len = 0;
	if (lseek (ifd, start, SEEK_SET) == -1
	    || (n = read (ifd, w->text, want)) < 0
	    || (size_t) n < len)
	    read_fatal ();
	w->start = start;
	w->len = n;
    }
    *psize = len;
    return w->text + (start - w->start);
}
