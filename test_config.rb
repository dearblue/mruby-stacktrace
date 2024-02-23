#!ruby

MRuby::Lockfile.disable rescue nil

require "yaml"

config = YAML.load <<~'YAML'
  common:
    gems:
    - :core: "mruby-sprintf"
    - :core: "mruby-print"
    - :core: "mruby-bin-mrbc"
    - :core: "mruby-bin-mirb"
    - :core: "mruby-bin-mruby"
  builds:
    host:
      defines: [MRB_WORD_BOXING]
      gems:
      - :core: "mruby-io"
    host1:
      defines:
      uses: use_libbacktrace
    host2:
      defines:
      uses: use_execinfo
    host32-nan:
      defines: [MRB_INT32, MRB_NAN_BOXING]
      uses: use_libunwind
    host64++:
      defines: [MRB_INT64, MRB_NO_BOXING]
      c++abi: true
      uses: use_boost
YAML

config["builds"].each_pair do |n, c|
  MRuby::Build.new(n) do |conf|
    toolchain :clang

    conf.build_dir = File.join("build", c["build_dir"] || name)

    enable_debug
    enable_test
    enable_cxx_abi if c["c++abi"]

    compilers.each do |cc|
      cc.defines << [*c["defines"]]
      cc.flags << [*c["cflags"]]
      cc.include_paths << [*c["incdirs"]]
    end

    linker.library_paths << [*c["libdirs"]]
    linker.libraries << [*c["libs"]]
    linker.flags << %w(-rdynamic)

    Array(config.dig("common", "gems")).each { |*g| gem *g }
    Array(c["gems"]).each { |*g| gem *g }

    gem __dir__ do |g|
      [*c["uses"]].flatten.each do |m|
        g.send(m)
      end

      if g.cc.command =~ /\b(?:g?cc|clang)\d*\b/
        g.cc.flags << "-std=c99" unless c["c++abi"]
        g.cc.flags << "-pedantic"
        g.cc.flags << "-Wall"
      end
    end
  end
end
