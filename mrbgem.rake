internals = File.join(__dir__, "contrib/mruby-buildconf/bootstrap.rb")
using Module.new { module_eval File.read(internals), internals, 1 }

MRuby::Gem::Specification.new("mruby-stacktrace") do |s|
  s.summary = "unified stacktrace collector for C and mruby VM"
  version = File.read(File.join(__dir__, "README.md")).scan(/^\s*[\-\*] version:\s*(\d+(?:\.\w+)+)/i).flatten[-1]
  s.version = version if version
  s.license = "CC0"
  s.author  = "dearblue"
  s.homepage = "https://github.com/dearblue/mruby-stacktrace"

  configuration_recipe(
    "stacktrace",
    {
      variation: "libbacktrace",
      defines: %w(MRUBY_STACKTRACE_USE_LIBBACKTRACE),
      libraries: "backtrace",
      code: {
        header_files: "backtrace.h",
        functions: "backtrace_full"
      }
    },
    { # for GNU libc
      variation: "execinfo",
      defines: %w(MRUBY_STACKTRACE_USE_EXECINFO),
      code: {
        header_files: "execinfo.h",
        "functions": %w(backtrace backtrace_symbols_fmt)
      }
    },
    { # for BSD libexecinfo
      variation: "execinfo",
      defines: %w(MRUBY_STACKTRACE_USE_EXECINFO),
      libraries: "execinfo",
      code: {
        header_files: "execinfo.h",
        functions: %w(backtrace backtrace_symbols_fmt),
      },
    },
    {
      variation: "libunwind",
      defines: %w(MRUBY_STACKTRACE_USE_LIBUNWIND),
      libraries: %w(unwind unwind-x86_64),
      code: {
        header_files: "libunwind.h",
        functions: %w(unw_init_local unw_get_reg unw_get_proc_name),
      }
    },
    {
      variation: "libunwind",
      defines: %w(MRUBY_STACKTRACE_USE_LIBUNWIND),
      libraries: %w(unwind unwind-x86),
      code: {
        header_files: "libunwind.h",
        functions: %w(unw_init_local unw_get_reg unw_get_proc_name),
      }
    },
    {
      variation: "libunwind",
      defines: %w(MRUBY_STACKTRACE_USE_LIBUNWIND),
      libraries: %w(unwind unwind-aarch64),
      code: {
        header_files: "libunwind.h",
        functions: %w(unw_init_local unw_get_reg unw_get_proc_name),
      }
    },
    {
      variation: "libunwind",
      defines: %w(MRUBY_STACKTRACE_USE_LIBUNWIND),
      libraries: %w(unwind unwind-arm),
      code: {
        header_files: "libunwind.h",
        functions: %w(unw_init_local unw_get_reg unw_get_proc_name),
      }
    },
    {
      variation: "libunwind",
      defines: %w(MRUBY_STACKTRACE_USE_LIBUNWIND),
      libraries: %w(unwind unwind-ppc32),
      code: {
        header_files: "libunwind.h",
        functions: %w(unw_init_local unw_get_reg unw_get_proc_name),
      }
    },
    {
      variation: "libunwind",
      defines: %w(MRUBY_STACKTRACE_USE_LIBUNWIND),
      libraries: %w(unwind unwind-ppc64),
      code: {
        header_files: "libunwind.h",
        functions: %w(unw_init_local unw_get_reg unw_get_proc_name),
      }
    },
    {
      variation: "boost",
      abi: "c++",
      defines: %w(MRUBY_STACKTRACE_USE_BOOST BOOST_STACKTRACE_USE_ADDR2LINE _GNU_SOURCE),
      libraries: %w(boost_stacktrace_addr2line dl backtrace),
      code: {
        type: ".cxx",
        header_files: "boost/stacktrace.hpp",
      }
    },
    {
      variation: "libunwind",
      defines: %w(MRUBY_STACKTRACE_USE_LIBUNWIND),
      libraries: "gcc_eh",
      code: {
        header_files: "libunwind.h",
        functions: %w(unw_init_local unw_get_reg unw_get_proc_name)
      },
    },
    abort: true)
end
