require "tmpdir"
require File.join(MRUBY_ROOT, "lib/mruby/source")

MRuby::Gem::Specification.new("mruby-stacktrace") do |s|
  s.summary = "unified stacktrace collector for C and mruby VM"
  version = File.read(File.join(__dir__, "README.md")).scan(/^\s*[\-\*] version:\s*(\d+(?:\.\w+)+)/i).flatten[-1]
  s.version = version if version
  s.license = "CC0"
  s.author  = "dearblue"
  s.homepage = "https://github.com/dearblue/mruby-stacktrace"

  def self.use_libbacktrace(libraries: %w(backtrace),
                            defines: nil,
                            include_paths: "/usr/local/include",
                            library_paths: "/usr/local/lib")
    clear_feature_detectors
    add_feature_detector defines: ["MRUBY_STACKTRACE_USE_LIBBACKTRACE", *defines],
                         headers: %w(backtrace.h),
                         libraries: libraries,
                         symbols: %w(backtrace_full),
                         include_paths: include_paths,
                         library_paths: library_paths
  end

  def self.use_boost(libraries: %w(boost_stacktrace_addr2line dl backtrace),
                     defines: %w(BOOST_STACKTRACE_USE_ADDR2LINE _GNU_SOURCE),
                     include_paths: "/usr/local/include",
                     library_paths: "/usr/local/lib")
    clear_feature_detectors
    add_feature_detector defines: ["MRUBY_STACKTRACE_USE_BOOST", *defines],
                         headers: %w(boost/stacktrace.hpp),
                         libraries: libraries,
                         symbols: %w(),
                         include_paths: include_paths,
                         library_paths: library_paths,
                         cxx: true
  end

  def self.use_execinfo(libraries: %w(execinfo),
                        defines: nil,
                        include_paths: "/usr/local/include",
                        library_paths: "/usr/local/lib")
    clear_feature_detectors
    add_feature_detector defines: ["MRUBY_STACKTRACE_USE_EXECINFO", *defines],
                         headers: %w(execinfo.h),
                         libraries: libraries,
                         symbols: %w(backtrace backtrace_symbols_fmt),
                         include_paths: include_paths,
                         library_paths: library_paths
  end

  def self.use_libunwind(libraries: %w(unwind unwind-x86_64),
                         defines: nil,
                         include_paths: "/usr/local/include",
                         library_paths: "/usr/local/lib")
    clear_feature_detectors
    add_feature_detector defines: ["MRUBY_STACKTRACE_USE_LIBUNWIND", *defines],
                         headers: %w(libunwind.h),
                         libraries: libraries,
                         symbols: %w(unw_init_local unw_get_reg unw_get_proc_name),
                         include_paths: include_paths,
                         library_paths: library_paths
  end

  ### PUBLIC INTERFACE ENDS HERE



  def self.update_configuration!(name, defines, libraries, include_paths, library_paths)
    compilers.each do |cc|
      cc.defines << ["MRUBY_STACKTRACE_USE_#{name}", *defines]
      cc.include_paths << [*include_paths]
    end
    linker.libraries << [*libraries]
    linker.library_paths << [*library_paths]
  end

  def self.add_feature_detector(code: nil, headers: [], libraries: [], symbols: [], include_paths: [], library_paths: [], defines: [], cxx: false)
    unless code
      code = <<~DETECT_CODE
        #{[*headers].flatten.map { |h| %(#include <#{h}>\n) }.join}
        int
        main(int argc, char *argv[])
        {
        #{[*symbols].flatten.map { |f| %(\t(void)#{f};\n) }.join}
        \treturn 0;
        }
      DETECT_CODE
    end

    @library_detectors ||= []
    @library_detectors << {
      "code" => code,
      "header_files" => [*headers].flatten,
      "libraries" => [*libraries].flatten,
      "include_paths" => [*include_paths].flatten,
      "library_paths" => [*library_paths].flatten,
      "defines" => [*defines].flatten,
      "abi" => (cxx ? "c++" : "c")
    }

    self
  end

  def self.clear_feature_detectors
    @library_detectors ||= []
    @library_detectors.clear
    self
  end

  unless respond_to?(:last_initializer)
    def self.last_initializer(&block)
      @last_initializer = block
    end

    build_config_initializer_origin = @build_config_initializer
    @build_config_initializer = ->(*) do
      instance_eval(&build_config_initializer_origin) if build_config_initializer_origin
      instance_eval(&@last_initializer)
    end
  end

  last_initializer do
    conffile = File.join(self.build_dir, "config.cache")

    Dir.glob(File.join(dir.gsub(/[\[\]\{\}]/) { |e| "\\#{e}" }, "{core,src}/**/*")) { |src|
      file src => conffile if File.file?(src)
    }

    file File.join(build_dir, "gem_init.c") => conffile

    task conffile do |t|
      if File.file?(conffile) && File.mtime(conffile) > [MRUBY_CONFIG, __FILE__].map { |e| File.mtime(e) }.max
        y = YAML.load_file(conffile)
        update_configuration!(*y.values_at(*%w(name defines libraries include_paths library_paths)))
        timestamp = Time.at(1)
      else
        _pp "CHECK", conffile
        detect_libraries
        timestamp = Time.now
      end
      t.define_singleton_method(:timestamp, &-> { timestamp })
    end
  end

  @library_detectors = YAML.load_file(File.join(__dir__, "preset-libs.yaml"))

  def self.detect_libraries(libs = @library_detectors)
    tool_cc = {
      bin: self.cc.dup,
      src: ->(e) { "#{e}.c" }
    }
    tool_cxx = {
      bin: self.cxx.dup,
      src: ->(e) { "#{e}.cxx" }
    }
    tool_ld = {
      bin: self.linker.dup,
      obj: ->(e) { self.objfile(e) },
      exe: ->(e) { self.exefile(e) }
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
        File.write src, spec["code"] || <<~CODE
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
      \e[7mError\e[m: failed library detection (build: #{build.name})
        | Please specify or revise the libraries to be used in your build configuration file.
        | Or help me to improve auto-detection.
        | See: #{File.join(self.dir, "README.md")}
    FAIL
  end
end
