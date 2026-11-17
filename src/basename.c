/* basename.c -- return the last element in a path */
/* Copyright 2026 patch16 contributors (the DOS separators below);
   GPL version 2 or any later version, as GNU patch.  */

#if HAVE_CONFIG_H
# include <config.h>
#endif

#include <backupfile.h>

/* In general, we can't use the builtin `basename' function if available,
   since it has different meanings in different environments.
   In some environments the builtin `basename' modifies its argument.  */

char *
base_name (name)
     char const *name;
{
  char const *base = name;

  /* patch16: DOS paths also use \ and a drive's colon.  */
  for (;  *name;  name++)
    if (*name == '/' || *name == '\\' || *name == ':')
      base = name + 1;

  return (char *) base;
}
