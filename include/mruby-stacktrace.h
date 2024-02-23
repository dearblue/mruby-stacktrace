#ifndef MRUBY_STACKTRACE_H
#define MRUBY_STACKTRACE_H 1

#include <mruby.h>

MRB_BEGIN_DECL

/**
 *  スタックトレースを文字列の配列オブジェクトとして返します。
 */
MRB_API mrb_value mruby_stacktrace(mrb_state *mrb);

/**
 *  内容を標準出力へ書き出します。
 *
 *  ただし `MRB_NO_STDIO` が定義してある場合は何もせずに制御を戻します。
 */
MRB_API void mruby_stacktrace_print(mrb_state *mrb);

/**
 *  呼び出しフレーム情報を受け取る利用者定義関数。
 *
 *  @return 情報の受け取りを続行する場合は「TRUE」を返してください。
 *          中止する場合は「FALSE」を返してください。
 *
 *  @param cxt          mruby VM 上の実行コンテキストへのポインタ
 *  @param ci           mruby VM 上の呼び出しフレーム情報へのポインタ
 *  @param pc           実マシン上のプログラムカウンタ (Ruby メソッドの場合は 0)
 *  @param function     関数名、あるいはメソッド名 (取得できない場合は NULL)
 *  @param funcdiff     関数の開始番地からの相対番地 (取得できない場合は -1)
 *  @param filename     実行点に対するファイル名か実行モジュール名 (取得できない場合は NULL)
 *  @param fineno       実行点に対する行番号 (取得できない場合は -1)
 *  @param opaque       利用者データ
 */
typedef mrb_bool mruby_stacktrace_report_func(
    mrb_state *mrb, const struct mrb_context *cxt, const mrb_callinfo *ci,
    uintptr_t pc, const char *function, intptr_t funcdiff,
    const char *filename, int lineno, void *opaque);

/**
 *  スタックトレースごとの情報を、与えられた関数へ渡します。
 */
MRB_API void mruby_stacktrace_foreach(mrb_state *mrb, mruby_stacktrace_report_func *report, void *opaque);

MRB_END_DECL

#endif // MRUBY_STACKTRACE_H
