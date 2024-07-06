#ifndef MRUBY_STACKTRACE_INTERNALS_H
#define MRUBY_STACKTRACE_INTERNALS_H 1

#include <mruby.h>
#include <mruby/irep.h>         // NOTE: Positions are locked for versions older than mruby-3.2.0
#include <mruby/array.h>
#include <mruby/class.h>
#include <mruby/data.h>
#include <mruby/debug.h>
#include <mruby/error.h>
#include <mruby/hash.h>
#include <mruby/numeric.h>
#include <mruby/string.h>
#include <mruby/value.h>
#include <mruby/variable.h>
#include <stdlib.h>
#include <string.h>

#ifndef MRB_PROC_IREP
# define MRB_PROC_IREP(PROC) ((PROC)->body.irep)
#endif

#if MRUBY_RELEASE_NO >= 30100
# define CI_CINFO_NONE_P(CI) ((CI)->cci == 0)
# define CI_CINFO_DIRECT_P(CI) ((CI)->cci == 2)
#else
# define CI_CINFO_NONE_P(CI) ((CI)->acc >= 0)
# define CI_CINFO_DIRECT_P(CI) ((CI)->acc == -2)
#endif

#if MRUBY_RELEASE_NO <= 30200
# if MRUBY_RELEASE_NO <= 20000
#  define mrb_debug_get_filename(M, I, P) mrb_debug_get_filename(I, P)
#  define mrb_debug_get_line(M, I, P) mrb_debug_get_line(I, P)
# endif
# if MRUBY_RELEASE_NO <= 20001
#  define mrb_sym_name(M, S) mrb_sym2name(M, S)
# endif

static mrb_bool
mrb_debug_get_position(mrb_state *mrb, const mrb_irep *irep, uint32_t pc, int32_t *lineno, const char **filename)
{
  *filename = mrb_debug_get_filename(mrb, (mrb_irep *)irep, pc);
  if (*filename) {
    int32_t n = mrb_debug_get_line(mrb, (mrb_irep *)irep, pc);
    if (n >= 0) {
      *lineno = n;
      return TRUE;
    }
  }

  return FALSE;
}
#endif

#endif /* MRUBY_STACKTRACE_INTERNALS_H */
