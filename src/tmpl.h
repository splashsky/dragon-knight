/* tmpl.h :: template compiler. Turns a template source into Lua source code.
 * The C side only compiles; rendering happens in Lua (see PLAN.md "Template language").
 *
 * The generated Lua chunk, when executed, returns a render function:
 *     local render = chunk()
 *     local html   = render(ctx, h)     -- ctx: data table, h: helpers table
 * Generated code must preserve line numbers (template line N == Lua line N) so
 * runtime errors point at the right template line. */
#ifndef DK_TMPL_H
#define DK_TMPL_H

#include <stddef.h>
#include "util.h"

/* Returns 0 on success (Lua source appended to out), -1 on syntax error with
 * err = "<name>:<line>: <message>". */
int tmpl_compile(const char *src, size_t len, const char *name,
                 sbuf *out, char *err, size_t errlen);

#endif
