/* signal.h for patch16: DOS has only Ctrl-C/Ctrl-Break (INT 23h), which
   is SIGINT here; the other signals GNU patch names are never raised.

   Copyright 2026 patch16 contributors
   GPL version 2 or any later version; see compat/include/config.h.  */

#ifndef PATCH16_SIGNAL_H
#define PATCH16_SIGNAL_H

#define SIGINT  2
#define SIGPIPE 13

typedef void (*p16_sighandler) (int);

#define SIG_DFL ((p16_sighandler) 0)
#define SIG_IGN ((p16_sighandler) 1)

p16_sighandler signal (int, p16_sighandler);
int kill (int, int);

#endif
