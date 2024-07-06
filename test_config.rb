#!ruby

MRuby::Lockfile.disable rescue nil

require "yaml"

config = {
  common: {
    gems: [
      { core: "mruby-sprintf" },
      { core: "mruby-print" },
      { core: "mruby-fiber" },
      { core: "mruby-bin-mrbc" },
      { core: "mruby-bin-mirb" },
      { core: "mruby-bin-mruby" }
    ]
  },
  builds: {
    host: {
      defines: ["MRB_WORD_BOXING"],
      gems: [
        core: "mruby-io"
      ]
    },
    host1: {
      defines: nil,
      uses: "libbacktrace",
    },
    host2: {
      defines: nil,
      uses: "execinfo",
    },
    "host32-nan": {
      defines: %w(MRB_INT32 MRB_NAN_BOXING),
      uses: "libunwind"
    },
    "host64++": {
      defines: %w(MRB_INT64 MRB_NO_BOXING),
      "c++abi": true,
      uses: "boost"
    }
  }
}

config[:"builds"].each_pair do |n, c|
  MRuby::Build.new(n) do |conf|
    toolchain :clang

    conf.build_dir = File.join(__dir__, "build", c[:"build_dir"] || name.to_s)

    enable_debug
    enable_test
    enable_cxx_abi if c[:"c++abi"]

    compilers.each do |cc|
      cc.defines << [*c[:"defines"]]
      cc.flags << [*c[:"cflags"]]
      cc.include_paths << [*c[:"incdirs"]]
    end

    linker.library_paths << [*c[:"libdirs"]]
    linker.libraries << [*c[:"libs"]]
    linker.flags << %w(-rdynamic)

    Array(config.dig(:common, :gems)).each { |*g| gem *g }
    Array(c[:gems]).each { |*g| gem *g }

    gem __dir__ do |g|
      [*c[:uses]].flatten.each do |m|
        g.enable_stacktrace(m)
      end

      if g.cc.command =~ /\b(?:g?cc|clang)\d*\b/
        g.cc.flags << (c[:"c++abi"] ? "-std=c++11" : "-std=c99")
        g.cxx.flags << "-std=c++11"
        g.cc.flags << "-pedantic"
        g.cc.flags << "-Wall"
      end
    end
  end
end
