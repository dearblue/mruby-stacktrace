require "tmpdir"

MRuby::Gem::Specification.new("mruby-stacktrace") do |s|
  s.summary = "unified stacktrace collector for C and mruby VM"
  version = File.read(File.join(__dir__, "README.md")).scan(/^\s*[\-\*] version:\s*(\d+(?:\.\w+)+)/i).flatten[-1]
  s.version = version if version
  s.license = "CC0"
  s.author  = "dearblue"
  s.homepage = "https://github.com/dearblue/mruby-stacktrace"

  def self.with_libbacktrace(libraries: %w(backtrace),
                             defines: nil,
                             include_paths: "/usr/local/include",
                             library_paths: "/usr/local/lib")
    update_configuration("LIBBACKTRACE",
                         defines,
                         %w(backtrace.h),
                         %w(backtrace_full),
                         libraries, include_paths, library_paths)
  end

  def self.with_boost(libraries: %w(boost_stacktrace_addr2line dl backtrace),
                      defines: %w(BOOST_STACKTRACE_USE_ADDR2LINE _GNU_SOURCE),
                      include_paths: "/usr/local/include",
                      library_paths: "/usr/local/lib")
    update_configuration("BOOST",
                         defines,
                         %w(boost/stacktrace.hpp),
                         %w(boost::stacktrace::stacktrace),
                         libraries, include_paths, library_paths)
  end

  def self.with_execinfo(libraries: %w(execinfo),
                         defines: nil,
                         include_paths: "/usr/local/include",
                         library_paths: "/usr/local/lib")
    update_configuration("EXECINFO",
                         defines,
                         %w(execinfo.h),
                         %w(backtrace backtrace_symbols_fmt),
                         libraries, include_paths, library_paths)
  end

  def self.with_libunwind(libraries: %w(unwind unwind-x86_64),
                          defines: nil,
                          include_paths: "/usr/local/include",
                          library_paths: "/usr/local/lib")
    update_configuration("LIBUNWIND",
                         defines,
                         %w(libunwind.h),
                         %w(unw_getcontext unw_init_local unw_get_reg unw_get_proc_name),
                         libraries, include_paths, library_paths)
  end

  ### PUBLIC INTERFACE ENDS HERE



  def self.update_configuration(name, defines, header_files, functions, libraries, include_paths, library_paths)
    raise "can't select multiple libraries" if @done_stacktrace_configuration
    @done_stacktrace_configuration = true

    # ???: 事前のリンク確認まで行う？？？

    update_configuration!(name, defines, libraries, include_paths, library_paths)
  end

  def self.update_configuration!(name, defines, libraries, include_paths, library_paths)
    compilers.each do |cc|
      cc.defines << ["MRUBY_STACKTRACE_USE_#{name}", *defines]
      cc.include_paths << [*include_paths]
    end
    linker.libraries << [*libraries]
    linker.library_paths << [*library_paths]
  end

  @done_stacktrace_configuration = false
  build_config_initializer_origin = @build_config_initializer
  @build_config_initializer = ->(*) do
    instance_eval(&build_config_initializer_origin) if build_config_initializer_origin

    conffile = File.join(self.build_dir, "config.cache")

    case
    when @done_stacktrace_configuration
      ;
    when File.file?(conffile) && File.mtime(conffile).to_i > [MRUBY_CONFIG, __FILE__].map { |e| File.mtime(e).to_i }.max
      y = YAML.load_file(conffile)
      update_configuration!(*y.values_at(*%w(name defines libraries include_paths library_paths)))
    else
      Dir.glob(File.join(dir, "src").gsub(/[\[\]\{\}]/) { |e| "\\#{e}" } + "/**/*.c") { |c|
        file c => conffile
      }
      file File.join(build_dir, "gem_init.c") => conffile
      file conffile => [MRUBY_CONFIG, __FILE__] do
        detect_libraries(YAML.load_file(File.join(__dir__, "preset-libs.yaml")))
      end
    end
  end

  def self.detect_libraries(libs)
    tool_cc = {
      bin: build.cc.dup,
      src: ->(e) { "#{e}.c" }
    }
    tool_cxx = {
      bin: build.cxx.dup,
      src: ->(e) { "#{e}.cxx" }
    }
    tool_ld = {
      bin: build.linker.dup,
      obj: ->(e) { build.objfile(e) },
      exe: ->(e) { build.exefile(e) }
    }

    [tool_cc, tool_cxx, tool_ld].each do |e|
      class << e[:bin]
        def sh(*command)
          system *command, out: File::NULL, err: File::NULL or fail
        end

        def _pp(*)
        end
      end
    end

    Dir.mktmpdir do |dir|
      libs.each do |spec|
        cc = (spec["abi"] == "c++" && build.cxx_abi_enabled?) ? tool_cxx : tool_cc
        ld = tool_ld

        src = cc[:src].call(File.join(dir, "1"))
        File.write src, <<~CODE
          #{[*spec["header_files"]].flatten.map { |h| %(#include <#{h}>\n) }.join}
          int
          main(int argc, char *argv[])
          {
          #{[*spec["functions"]].flatten.map { |f| %(\t(void)#{f};\n) }.join}
          \treturn 0;
          }
        CODE

        obj = ld[:obj].call(File.join(dir, "1"))
        exe = ld[:exe].call(File.join(dir, "1"))
        if (cc[:bin].run(obj, src, [*spec["defines"]], [*spec["include_paths"]]) rescue nil) &&
           (ld[:bin].run(exe, [obj], [*spec["libraries"]], [*spec["library_paths"]]) rescue nil)
          update_configuration!(*spec.values_at(*%w(name defines libraries include_paths library_paths)))

          FileUtils.mkpath build_dir
          File.binwrite File.join(build_dir, "config.cache"), <<~CONFIG_YAML
            %YAML 1.1
            ---
            name: #{spec["name"].inspect}
            defines: #{[*spec["defines"]].inspect}
            libraries: #{[*spec["libraries"]].inspect}
            include_paths: #{[*spec["include_paths"]].inspect}
            library_paths: #{[*spec["library_paths"]].inspect}
          CONFIG_YAML

          return true
        end
      end
    end

    fail <<~FAIL
      \e[7mfailed auto detection for stacktrace libraries (build: #{build.name})\e[m
      | Please specify which libraries to use in your build configuration file.
      | Or help me to improve auto-detection.
      | See: #{File.join(self.dir, "README.md")}
    FAIL
  end
end
