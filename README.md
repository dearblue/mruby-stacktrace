mruby-stacktrace - C と mruby VM を組み合わせたスタックトレース情報の取得
========================================================================

Ruby のメソッドと C の関数のコールフレームを統合して取得するライブラリです。
デバッグ時に C のスタック一覧と mruby VM のスタック一覧を別の紙に印刷して隣に並べる必要はありません。


ちゅういとせいげん
------------------------------------------------------------------------

  - 現時点での目的は技術実証です。
  - バイナリファイルにデバッグ情報やダイナミックシンボルテーブルが必要です。
  - デバッガ (`GDB` や `LLDB`) のプロンプトから呼び出しても、正しい結果は取得できません。
  - 😿 デバッグ情報やダイナミックシンボルテーブルがあっても、C と Ruby のスタックの同期がずれる可能性があります。


できること
------------------------------------------------------------------------

  - C API
      - `#include <mruby-stacktrace.h>`
          - `mrb_value mruby_stacktrace(mrb_state *mrb)`
  - Ruby API
      - `Kernel#stacktrace`


くみこみかた
------------------------------------------------------------------------

あなたのビルド設定ファイルに追加し、libmruby をビルドして下さい。
ライブラリの自動検出に頼ることができます。
ただしデバッグセクションあるいはダイナミックシンボルテーブルの出力を行う必要があります。

GCC/Clang 互換コンパイラの場合の例を次に示します。

```ruby
MRuby::Build.new do |conf|
  ...
  compilers.each { |cc| cc.flags << "-g" }  # デバッグ情報を出力する
  linker.flags << "-rdynamic"               # ダイナミックシンボルテーブルを出力する
  #linker.flags << "-Wl,--export-dynamic"   # -rdynamic と同等
  conf.gem "mruby-stacktrace", github: "dearblue/mruby-stacktrace"
end
```

自動検出に失敗したり、特定のライブラリを使いたい場合は `#gem` メソッドにブロックを与えて指定します。

```ruby
  conf.gem "mruby-stacktrace", github: "dearblue/mruby-stacktrace" do |g|
    g.with_libunwind
  end
```

現在のところ、指定可能なメソッドと既定値は以下のとおりです:

```ruby
  def gem.with_libbacktrace(libraries: %w(backtrace),
                            defines: nil,
                            include_paths: "/usr/local/include",
                            library_paths: "/usr/local/lib")
  def gem.with_boost(libraries: %w(boost_stacktrace_addr2line dl backtrace),
                     defines: %w(BOOST_STACKTRACE_USE_ADDR2LINE _GNU_SOURCE),
                     include_paths: "/usr/local/include",
                     library_paths: "/usr/local/lib")
  def gem.with_execinfo(libraries: %w(execinfo),
                        defines: nil,
                        include_paths: "/usr/local/include",
                        library_paths: "/usr/local/lib")
  def gem.with_libunwind(libraries: %w(unwind unwind-x86_64),
                         defines: nil,
                         include_paths: "/usr/local/include",
                         library_paths: "/usr/local/lib")
```

自動検出によるライブラリの優先度や設定値については [preset-libs.yaml](preset-libs.yaml) をご確認ください。


つかいかた
------------------------------------------------------------------------

`Kernel#stacktrace` を呼び出すと、スタックトレース情報を文字列の配列として取得できます。

読み方は、C 関数の場合は「リターンアドレス」、「関数シンボル名 + 相対位置」、「モジュール名、またはソースコードファイル名」です。
Ruby のメソッドの場合は、「ファイバーのニックネーム + コールスタック位置」、「メソッド名」、「ソースコードファイル名」です。

情報が取得できない場合は項目が省略されます。

```console
% bin/mruby -e 'Class.new { Class.new { Fiber.new { -> { puts stacktrace }.call }.resume } }'
0x00000000004d701f mruby_stacktrace build/repos/host/mruby-stacktrace/src/mruby-stacktrace.c:343
0x00000000004d71e8 obj_stacktrace build/repos/host/mruby-stacktrace/src/mruby-stacktrace.c:352
             NFRQE+2 stacktrace
             NFRQE+1 <n/a> -e:1
             NFRQE+0 <n/a> -e:1
             JVSYD+5 resume
             JVSYD+4 <n/a> -e:1
0x0000000000442bb5 mrb_vm_exec src/vm.c:1909
0x000000000043f5be mrb_vm_run src/vm.c:1331
0x000000000043ddbc mrb_run src/vm.c:3112
0x000000000043f063 mrb_yield_with_class src/vm.c:1034
0x00000000004137d5 mrb_class_initialize src/class.c:2016
0x00000000004135f8 mrb_class_new_class src/class.c:2036
             JVSYD+3 new
             JVSYD+2 <n/a> -e:1
0x0000000000442bb5 mrb_vm_exec src/vm.c:1909
0x000000000043f5be mrb_vm_run src/vm.c:1331
0x000000000043ddbc mrb_run src/vm.c:3112
0x000000000043f063 mrb_yield_with_class src/vm.c:1034
0x00000000004137d5 mrb_class_initialize src/class.c:2016
0x00000000004135f8 mrb_class_new_class src/class.c:2036
             JVSYD+1 new
             JVSYD+0 <n/a> -e:1
0x0000000000442bb5 mrb_vm_exec src/vm.c:1909
0x000000000043f5be mrb_vm_run src/vm.c:1331
0x000000000043e41f mrb_top_run src/vm.c:3121
0x0000000000463fce mrb_load_exec mrbgems/mruby-compiler/core/parse.y:6919
0x0000000000464504 mrb_load_nstring_cxt mrbgems/mruby-compiler/core/parse.y:6991
0x00000000004645a0 mrb_load_string_cxt mrbgems/mruby-compiler/core/parse.y:7003
0x00000000004045ec main mrbgems/mruby-bin-mruby/tools/mruby/mruby.c:358
0x000000082473daf9 (???)
0x000000000040406f (???) /usr/src/lib/csu/amd64/crt1_s.S:83
```


さんこうしりょう
------------------------------------------------------------------------

  - C++でスタックトレース(関数コール履歴)の取得 - An Embedded Engineer’s Blog <br>
    <https://an-embedded-engineer.hateblo.jp/entry/2020/08/24/212511>
  - c++ - How to print a stack trace whenever a certain function is called - Stack Overflow <br>
    <https://stackoverflow.com/a/54365144>
  - [Linux\]\[C/C++] backtrace取得方法まとめ #Linux - Qiita <br>
    <https://qiita.com/koara-local/items/012b917111a96f76d27c>


しょげん
------------------------------------------------------------------------

  - Package name: mruby-stacktrace
  - Version: 0.1
  - Project status: CONCEPT
  - Author: [dearblue](https://github.com/dearblue)
  - Project page: <https://github.com/dearblue/mruby-stacktrace>
  - Licensing: [Creative Commons Zero License (CC0 / Public Domain)](LICENSE)
  - Dependency external mrbgems: (NONE)
  - Bundled C libraries (git-submodules): (NONE)
  - Dependency external libraries:
      - [boost](https://www.boost.org/) (with C++ or `gem.with_boost`)
        under [Boost Software License](https://www.boost.org/LICENSE_1_0.txt)
      - [libbacktrace](https://github.com/ianlancetaylor/libbacktrace) (with `gem.with_libbacktrace`)
        under [3 clause BSD License](https://github.com/ianlancetaylor/libbacktrace/blob/master/LICENSE)
      - [libexecinfo](https://github.com/NetBSD/src/tree/trunk/lib/libexecinfo) (with `gem.with_execinfo`)
        under [2 clause BSD License](https://github.com/NetBSD/src/blob/trunk/lib/libexecinfo/execinfo.h)
      - [libunwind](https://github.com/libunwind/libunwind) (with `gem.with_libunwind`)
        under [MIT License](https://github.com/libunwind/libunwind/blob/master/COPYING)
