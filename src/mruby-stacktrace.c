#include <mruby-stacktrace.h>
#include "internals.h"
#include <mruby/debug.h>
#include <mruby/proc.h>

//#include <dlfcn.h> // for dladdr

#ifdef MRB_USE_CXX_ABI
//# include <cxxabi.h> // see also: https://stackoverflow.com/q/19615905
# include <boost/core/demangle.hpp>
#endif

#if SIZE_MAX > UINT32_MAX
# define COND64(CODE64, CODE32) CODE64
#else
# define COND64(CODE64, CODE32) CODE32
#endif

#define BITROTATE(N, SH) (((N) << (SH)) | ((N) >> (sizeof(uintptr_t) * CHAR_BIT - (SH))))

static const char digest_table[] = {
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
  'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
};

static char *
addr_to_hex(size_t addr, size_t bufsize, char buf[])
{
  char *p = buf + bufsize;
  *--p = '\0';

  for (; addr > 0; addr >>= 4) {
    *--p = digest_table[addr & 0x0f];
  }

  while (p > buf + bufsize - 1 - (sizeof(void *) * 2)) {
    *--p = '0';
  }

  *--p = 'x';
  *--p = '0';

  return p;
}

static char *
int_to_str(size_t num, size_t bufsize, char buf[], int base)
{
  char *p = buf + bufsize;
  *--p = '\0';

  if (num == 0) {
    *--p = '0';
  } else {
    for (; num > 0; num /= base) {
      *--p = digest_table[num % base];
    }
  }

  return p;
}

static char *
fiber_tac_name(char buf[6], const struct mrb_context *cxt)
{
  uintptr_t code = (uintptr_t)cxt;
  code ^= BITROTATE(code, 13);
  code ^= BITROTATE(code, 29);
  code %= 26 * 26 * 26 * 26 * 26 - 1; // 奇数による剰余を求める
  for (int i = 0; i < 5; i++) {
    buf[i] = 'A' + (char)(code % 26);
    code /= 26;
  }
  buf[5] = '\0';

  return buf;
}

static int
need_unwind_mruby_frames(const mrb_callinfo *ci, const char function[])
{
#if MRUBY_RELEASE_NO >= 10300
# define MRB_VM_EXEC_FUNCNAME "mrb_vm_exec"
#else
# define MRB_VM_EXEC_FUNCNAME "mrb_context_run"
#endif
  if (strcmp(function, MRB_VM_EXEC_FUNCNAME) == 0) {
    return 1;
  }

  if (CI_CINFO_DIRECT_P(ci) &&
      (strcmp(function, "exec_irep") == 0 ||
       strcmp(function, "eval_under") == 0 ||
       strcmp(function, "mrb_f_send") == 0 ||
       strcmp(function, "mrb_exec_irep") == 0 ||
       strcmp(function, "mrb_yield_with_class") == 0 ||
       //mrb_yield_cont
       //mrb_mod_module_eval
       //mrb_obj_instance_eval
       strcmp(function, "mrb_funcall_with_block") == 0)) {
    return 2;
  }

  return 0;
}

static void
entry_mruby_frames(mrb_state *mrb, int ai, struct mrb_context **c, mrb_callinfo **ci,
                   mruby_stacktrace_report_func *report, void *opaque)
{
  for (;;) {
    const char *method = (**ci).mid ? mrb_sym_name(mrb, (**ci).mid) : "<n/a>";

    const char *filename;
    int32_t lineno;
    const mrb_irep *irep = ((**ci).proc && !MRB_PROC_CFUNC_P((**ci).proc)) ? MRB_PROC_IREP((**ci).proc) : NULL;
    if (!irep || !mrb_debug_get_position(mrb, irep, (**ci).pc - irep->iseq, &lineno, &filename)) {
      filename = NULL;
      lineno = -1;
    }

    report(mrb, *c, *ci, 0, method, -1, filename, lineno, opaque);
    mrb_gc_arena_restore(mrb, ai);

    if (*ci > (**c).cibase) {
      (*ci)--;
      if (!CI_CINFO_NONE_P(*ci + 1)) {
        return;
      }
    } else {
      const struct mrb_context *c1 = *c;
      *c = c1->prev ? c1->prev : c1 != mrb->root_c ? mrb->root_c : NULL;
      *ci = *c ? (**c).ci : NULL;
#if MRUBY_RELEASE_NO >= 10300
# define EC_VMEXEC(C) ((C)->vmexec)
#else
# define EC_VMEXEC(C) FALSE
#endif
      if (!*ci || EC_VMEXEC(c1)) {
        return;
      }
    }
  }
}

static void
entry_frame(mrb_state *mrb, struct mrb_context **c, mrb_callinfo **ci,
            uintptr_t pc, const char *function0, intptr_t funcdiff, const char *filename, int lineno,
            mruby_stacktrace_report_func *report, void *opaque)
{
  int ai = mrb_gc_arena_save(mrb);

#ifdef MRB_USE_CXX_ABI
  char function[256];
  function[0] = '\0';
  function[sizeof(function) - 1] = '\0';

  {
# ifdef MRUBY_STACKTRACE_USE_BOOST
    const char *o = function0;
# else
    boost::core::scoped_demangled_name demangled(function0);
    const char *o = demangled.get();
# endif
    if (!o) {
      strncat(function, (function0 ? function0 : "(\?\?\?)"), sizeof(function) - 1);
    } else {
      const char *p = strchr(o, '(');
      if (!p) {
        strncat(function, (function0 ? function0 : "(\?\?\?)"), sizeof(function) - 1);
      } else {
        strncat(function, o, p - o);
      }
    }
  }
#else
# define function function0
#endif

  if (*c && function && need_unwind_mruby_frames(*ci, function)) {
    entry_mruby_frames(mrb, ai, c, ci, report, opaque);
  }

  report(mrb, *c, *ci, (uintptr_t)pc, function, funcdiff, filename, lineno, opaque);
  mrb_gc_arena_restore(mrb, ai);
}

#ifdef MRUBY_STACKTRACE_USE_BOOST
#include <boost/stacktrace.hpp>

MRB_API void
mruby_stacktrace_foreach(mrb_state *mrb, mruby_stacktrace_report_func *report, void *opaque)
{
  struct mrb_context *c = mrb->c;
  mrb_callinfo *ci = c->ci;

  for (boost::stacktrace::frame frame: boost::stacktrace::stacktrace()) {
    entry_frame(mrb, &c, &ci,
                (intptr_t)frame.address(), frame.name().c_str(), -1,
                frame.source_file().c_str(), frame.source_line(), report, opaque);
  }
}
#endif // MRUBY_STACKTRACE_USE_BOOST

#ifdef MRUBY_STACKTRACE_USE_EXECINFO
#include <execinfo.h>

#pragma message("TODO: 段階的な拡張を行う")
#define MAXFRAMES 1048576

MRB_API void
mruby_stacktrace_foreach(mrb_state *mrb, mruby_stacktrace_report_func *report, void *opaque)
{
  struct mrb_context *c = mrb->c;
  mrb_callinfo *ci = c->ci;
  int ai = mrb_gc_arena_save(mrb);

  mrb_value buf_val = mrb_str_buf_new(mrb, MAXFRAMES * sizeof(void *));
  void **addrp = (void **)RSTRING_PTR(buf_val);
  size_t len = backtrace(addrp, MAXFRAMES);
  char **out = backtrace_symbols_fmt(addrp, len, "%n\t%d\t%f");

  for (size_t i = 0; i < len; i++) {
    char *function = out[i];
    char *diffp = strchr(function, '\t');
    *diffp++ = '\0';
    char *modname = strchr(diffp, '\t');
    *modname++ = '\0';
    long diff = strtol(diffp, NULL, 0);

    entry_frame(mrb, &c, &ci, (intptr_t)addrp[i], function, diff, modname, 0, report, opaque);
  }

  free(out);
  mrb_gc_arena_restore(mrb, ai);
}
#endif // MRUBY_STACKTRACE_USE_EXECINFO

#ifdef MRUBY_STACKTRACE_USE_LIBBACKTRACE
#include <backtrace.h>

struct mruby_stacktrace_receptor
{
  mrb_state *mrb;
  struct mrb_context *c;
  mrb_callinfo *ci;
  int ai;
  mruby_stacktrace_report_func *report;
  void *opaque;
};

static int
mruby_stacktrace_receptor(void *data, uintptr_t pc, const char *filename, int lineno, const char *function)
{
  struct mruby_stacktrace_receptor *a = (struct mruby_stacktrace_receptor *)data;

  entry_frame(a->mrb, &a->c, &a->ci,
              (intptr_t)pc, (function && function[0] != '\0' ? function : "(\?\?\?)"), 0,
              (filename && filename[0] != '\0' ? filename : NULL), lineno,
              a->report, a->opaque);

  return 0;
}

MRB_API void
mruby_stacktrace_foreach(mrb_state *mrb, mruby_stacktrace_report_func *report, void *opaque)
{
  static struct backtrace_state *backtrace_state0;

  if (!backtrace_state0) {
    backtrace_state0 = backtrace_create_state(NULL, 1, NULL, NULL);
  }

  struct mruby_stacktrace_receptor a = { mrb, mrb->c, mrb->c->ci, mrb_gc_arena_save(mrb), report, opaque };

  backtrace_full(backtrace_state0, 0, mruby_stacktrace_receptor, NULL, &a);
}
#endif // MRUBY_STACKTRACE_USE_LIBBACKTRACE

#ifdef MRUBY_STACKTRACE_USE_LIBUNWIND
#include <libunwind.h>

MRB_API void
mruby_stacktrace_foreach(mrb_state *mrb, mruby_stacktrace_report_func *report, void *opaque)
{
  struct mrb_context *c = mrb->c;
  mrb_callinfo *ci = c->ci;

  unw_cursor_t cursor;
  unw_context_t context;

  unw_getcontext(&context);
  unw_init_local(&cursor, &context);

  do {
    int ret;

    unw_word_t pc;
    ret = unw_get_reg(&cursor, UNW_REG_IP, &pc);
    if (pc == 0) {
      break;
    }

    char funcname[1024] = { '\0' };
    unw_word_t offset;
    ret = unw_get_proc_name(&cursor, funcname, sizeof(funcname), &offset);

    entry_frame(mrb, &c, &ci, (intptr_t)pc, funcname, offset, NULL, 0, report, opaque);
  } while (unw_step(&cursor) > 0);
}
#endif // MRUBY_STACKTRACE_USE_LIBUNWIND

static void
output_frame(mrb_state *mrb, const struct mrb_context *c, const mrb_callinfo *ci,
             uintptr_t pc, const char *function, intptr_t funcdiff,
             const char *filename, int lineno,
             void (*output)(mrb_state *mrb, size_t buflen, const char *buf, void *opaque), void *opaque)
{
  char buf[32];
  const char *p;

#define OUTPUT_LIT(MRB, LIT, OPAQUE) output(MRB, sizeof(LIT) - 1, ("" LIT), OPAQUE)

  if (pc > 0) {
    p = addr_to_hex((size_t)pc, sizeof(buf), buf);
    output(mrb, buf + sizeof(buf) - 1 - p, p, opaque);
  } else {
    OUTPUT_LIT(mrb, COND64("             ", "     "), opaque);
    p = fiber_tac_name(buf, c);
    output(mrb, 5, p, opaque);
    OUTPUT_LIT(mrb, "+", opaque);
    p = int_to_str((ci - c->cibase), sizeof(buf), buf, 10);
    output(mrb, buf + sizeof(buf) - 1 - p, p, opaque);
  }

  OUTPUT_LIT(mrb, " ", opaque);
  output(mrb, strlen(function), function, opaque);

  if (funcdiff > 0) {
    OUTPUT_LIT(mrb, "+0x", opaque);
    p = int_to_str((size_t)funcdiff, sizeof(buf), buf, 16);
    output(mrb, buf + sizeof(buf) - 1 - p, p, opaque);
  }

  if (filename) {
    OUTPUT_LIT(mrb, " ", opaque);
    output(mrb, strlen(filename), filename, opaque);

    if (lineno > 0) {
      OUTPUT_LIT(mrb, ":", opaque);
      p = int_to_str((size_t)lineno, sizeof(buf), buf, 10);
      output(mrb, buf + sizeof(buf) - 1 - p, p, opaque);
    }
  }

  output(mrb, 0, 0, opaque); // end of frame
}

static void
str_concat(mrb_state *mrb, size_t buflen, const char *buf, void *opaque)
{
  mrb_str_cat(mrb, *(mrb_value *)opaque, buf, buflen);
}

static mrb_bool
report_frame(mrb_state *mrb, const struct mrb_context *c, const mrb_callinfo *ci,
             uintptr_t pc, const char *function, intptr_t funcdiff,
             const char *filename, int lineno, void *opaque)
{
  mrb_value entry = mrb_str_new(mrb, NULL, 0);
  output_frame(mrb, c, ci, pc, function, funcdiff, filename, lineno, str_concat, &entry);
  mrb_ary_push(mrb, *(mrb_value *)opaque, entry);

  return TRUE;
}

MRB_API mrb_value
mruby_stacktrace(mrb_state *mrb)
{
  mrb_value bt = mrb_ary_new_capa(mrb, 10);
  mruby_stacktrace_foreach(mrb, report_frame, &bt);
  return bt;
}

static mrb_value
obj_stacktrace(mrb_state *mrb, mrb_value self)
{
  return mruby_stacktrace(mrb);
}

#ifndef MRB_NO_STDIO
static void
stdout_output(mrb_state *mrb, size_t buflen, const char *buf, void *opaque)
{
  (void)mrb;
  (void)opaque;

  if (buf) {
    fwrite(buf, buflen, 1, stdout);
  } else {
    fwrite("\n", 1, 1, stdout);
  }
}

static mrb_bool
stdout_report_frame(mrb_state *mrb, const struct mrb_context *c, const mrb_callinfo *ci,
                    uintptr_t pc, const char *function, intptr_t funcdiff,
                    const char *filename, int lineno, void *opaque)
{
  output_frame(mrb, c, ci, pc, function, funcdiff, filename, lineno, stdout_output, NULL);

  return TRUE;
}
#endif

MRB_API void
mruby_stacktrace_print(mrb_state *mrb)
{
#ifndef MRB_NO_STDIO
  mruby_stacktrace_foreach(mrb, stdout_report_frame, NULL);
#endif
}

void
mrb_mruby_stacktrace_gem_init(mrb_state *mrb)
{
  struct RClass *kern = mrb->kernel_module;

  mrb_define_method(mrb, kern, "stacktrace", obj_stacktrace, MRB_ARGS_NONE());
}

void
mrb_mruby_stacktrace_gem_final(mrb_state *mrb)
{
}
