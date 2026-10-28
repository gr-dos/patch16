/* config.h for patch16: GNU patch 2.2 built for 16-bit DOS with libc16.
   Takes the place of the config.h that configure makes from config.hin.

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

#ifndef PATCH16_CONFIG_H
#define PATCH16_CONFIG_H

/* What libc16 has (its docs/spec/).  */
#define STDC_HEADERS 1
#define HAVE_STRING_H 1
#define HAVE_FCNTL_H 1
#define HAVE_LIMITS_H 1
#define HAVE_UNISTD_H 1
#define HAVE_MKDIR 1
#define HAVE_MEMCMP 1
#define HAVE_RENAME 1
#define HAVE_VPRINTF 1
#define RETSIGTYPE void

/* DOS file names are 8.3; addext.c then uses the short forms.  */
#undef HAVE_LONG_FILE_NAMES

#define ED_PROGRAM "ed"

/* Prototypes for every file, including getopt.c, which includes these
   itself only with the GNU C library.  */
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <p16.h>

#endif
