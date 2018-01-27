=begin

  Ruby/GTK2による Ruby初心者向けプログラミング環境

    Copyright (c) 2018 Koki Kitamura
    This program is licensed under the same license as Ruby-GNOME2.

    Version :
      0.5.0 (2018/01/28)

=end


require 'gtk2'
require 'drb/drb'
require "tempfile"
require 'rexml/document'


# スクロールバー付きテキストバッファ
class Widget_ScrolledText < Gtk::ScrolledWindow
  def initialize
    super
    @view   = Gtk::TextView.new
    @view.modify_font(Pango::FontDescription.new("MS Gothic 12"))
    @view.left_margin        = 4
    @view.pixels_above_lines = 2
    @view.pixels_below_lines = 1
    @view.accepts_tab        = false    # TABキーはフォーカス移動
    self.add(@view)
  end
end


# エディタ用ページ
class Widget_Page < Widget_ScrolledText

  attr_reader :status, :dirname, :basename

  def initialize(status_area)
    super()

    @status   = :EMPTY
    @dirname  = nil
    @basename = nil
    @status_area = status_area

    @view.buffer.create_tag('user',     {foreground: 'limegreen',
                                        })
    @view.buffer.create_tag('comment',  {foreground: 'green',
                                        })
    @view.buffer.create_tag('const',    {foreground: 'mediumvioletred',
                                        })
    @view.buffer.create_tag('string',   {foreground: 'chocolate',
                                         weight:      600           # SEMIBOLD
                                        })
    @view.buffer.create_tag('reserved', {foreground: 'indigo',
                                         weight:      600           # SEMIBOLD
                                        })

    _display_status

    @view.signal_connect("button_release_event") do
      _display_status
      false                # trueだとマウスボタンによる範囲選択動作が連動してしまう
    end

    @view.signal_connect_after("move_cursor") do |widget, step, count, extend_selection|
      # マウス移動後に発行されるシグナル
      _display_status
    end


    @view.buffer.signal_connect("insert_text") do |widget, iter, text, len|
      # テキスト挿入前に発行されるシグナル
      @indent_swt = (/\n/.match(text) ? :ON : :OFF)  # 改行コードを含む場合のみインデント処理を有効化([DEL]キー対象外)
      _display_status
    end

    @view.buffer.signal_connect("changed") do |widget|
      # バッファ変更後に発行されるシグナル
      # puts "changed"
      @status = :UNSAVED                                # 編集ステータスを変更

      # 改行時のインデント処理
      if @indent_swt == :ON
        mark = @view.buffer.selection_bound             # カーソル位置のマークを取得
        iter = @view.buffer.get_iter_at_mark(mark)
        if iter.starts_line?                            # 行頭の場合
          iter_end = iter.clone                         # 改行後の現在位置を示すiter
          iter.backward_line                            # 前行の先頭位置を示すiter
          line_str = iter.get_text(iter_end).chomp      # 前行の文字列
          match = /^ */.match(line_str)                 # 前行の文字列に含まれる先頭からの空白文字列
          @view.buffer.insert_at_cursor(match[0])       # カーソル位置に空白文字列を挿入(インデント揃え)
          #puts "[#{line_str}]"
          #puts "[#{match[0]}]"
        end
        @indent_swt = :OFF
      end
      _tokenize                                         # タグ設定用の字句解析
      _display_status
    end
  end

  # カーソル位置にインデント付きでテキストを挿入
  def insert_block(text)
    mark = @view.buffer.selection_bound                 # カーソル位置のマークを取得
    iter = @view.buffer.get_iter_at_mark(mark)          # マークからイテレータを取得
    text.gsub!("\n", "\n#{" " * iter.line_offset}")     # テキストのインデントを調整(改行後にスペース付加)
    @view.buffer.insert_at_cursor(text)                 # テキストを挿入
    @view.scroll_to_mark(mark, 0, false, 0, 1)          # マークまで移動
  end

  # ファイル保存
  def save(filename, temporary = false)
    content  = @view.buffer.text
    File.open(filename, "wb:utf-8") do |fp|
      fp.puts content
    end

    unless temporary
      @status   = :SAVED
      @dirname  = File.dirname(filename)
      @basename = File.basename(filename)
    end
    _display_status
  end

  # ファイル読み込み
  def load(filename, template = false)
    File.open(filename, "rb:utf-8") do |file|
      content = file.read
      @view.buffer.insert(@view.buffer.end_iter, content)
    end

    if template
      @status = :UNSAVED
    else
      @status = :SAVED
      @dirname  = File.dirname(filename)
      @basename = File.basename(filename)
    end

    @view.buffer.place_cursor(@view.buffer.start_iter)
    _display_status
  end

  # フォーカスをセット
  def set_focus
    @view.set_focus(true)
  end

  # ステータス表示
  def display_status
    _display_status
  end

  # ステータスエリアに情報表示(行位置、桁位置、ファイル保存状態)
  private def _display_status(movement_step = nil, count = 0)
    mark = @view.buffer.selection_bound                             # カーソル位置のマークを取得
    iter = @view.buffer.get_iter_at_mark(mark)
    @status_area.text = "%4d行%4d桁  %s" % [iter.line + 1, iter.line_offset + 1, (@status == :UNSAVED ? "(未保存)" : " " * 8)]
  end

  # キーワード解析
  private def _tokenize
    # 既存のタグをすべて削除
    @view.buffer.remove_all_tags(@view.buffer.start_iter, @view.buffer.end_iter)

    # タグの適用
    str = @view.buffer.get_text(@view.buffer.start_iter, @view.buffer.end_iter, true)
    wordlist = _parse(str)
    wordlist.each do |x|
      @view.buffer.apply_tag(x[:tag].to_s,
                             @view.buffer.get_iter_at_offset(x[:pos]),
                             @view.buffer.get_iter_at_offset(x[:pos] + x[:len]))
      # puts "#{x[:tag]} (#{x[:word]}) #{x[:pos]} #{x[:len]} (#{str[x[:pos], x[:len]]})"
    end
  end

  # 字句解析
  # (再帰的に呼び出し、対象字句の情報を配列で返す)
  private def _parse(str, index = 0, list = [])
    until str.empty?
      tag = nil
      case str
      when /()(\!.*\!)()/
        tag = :user                          # ユーザ可変箇所(ツール独自書式)
      when /()(#.*$)()/
        tag = :comment                       # コメント
      when /()(".+?")()/, /()('.+?')()/
        tag = :string                        # 文字列
      when /()([A-Z][A-Za-z0-9_]+)()/
        tag = :const                         # 定数
      when /(^|\s)(begin|end|if|else|elsif|then|unless|case|when|while|until|for|break|next|return|do|require|require_relative|def|module|class)(\s|$)/
        tag = :reserved                      # 予約語
      end

      if tag
        _parse($~.pre_match, index, list)    # マッチした部分より前の文字列を再帰処理
        # マッチした部分の情報のハッシュを配列にセット
        # [タグ名, 字句, 開始位置, 長さ]
        # ($2がターゲットの文字列、$1,$3は前後の空白・行頭行末または :reservedのパターンに合わせるためのダミー(""))
        list << {:tag  => tag,
                 :word => $2,
                 :pos  => index + $~.pre_match.length + $1.length,
                 :len  => $2.length}
        index += (str.length - ($3 + $~.post_match).length)   # 相対位置情報をインクリメント
        str = $3 + $~.post_match             # マッチした部分より後の文字列を新たな処理対象文字列に設定
      else
        index += str.length
        str = ''
      end
    end
    return list
  end

end


# エディタ
class Widget_Editor < Gtk::Notebook

  # コンストラクタ
  def initialize(status_area)
    super()
    @status_area = status_area
    @next_pageno = 0
    _append_page
    __debug_status

    self.signal_connect("switch-page") do |widget, page, num_page|
      puts "swithch page #{widget.page} --> #{num_page}  (n_pages = #{widget.n_pages})"
      self.get_nth_page(num_page).display_status
    end
  end

  # ページにフォーカスをセット
  def page_focus
    self.get_nth_page(self.page).set_focus
  end

  # 構文挿入
  def insert_block(statement)
    editor_page   = self.get_nth_page(self.page)              # 当該ページの child widget
    editor_page.insert_block(statement)
  end

  # 指定ディレクトリに一時ファイル保存
  def save_tmp(dirname)
    editor_page = self.get_nth_page(self.page)                # 当該ページの child widget
    basename = "rs_#{Utility.get_uniqname}.rb"                # ファイル名(ランダム)
    filename = "#{dirname}/#{basename}"                       # フルパス
    editor_page.save(filename, true)                          # ファイル保存
    return basename
  end

  # ファイル保存
  def save(filename)
    editor_page   = self.get_nth_page(self.page)              # 当該ページの child widget
    p editor_page
    self.get_tab_label(editor_page).text = File.basename(filename, ".*")
    editor_page.save(filename)                                # ファイル保存
    __debug_status
  end

  # ファイル読込み
  def load(filename)
    tabname = File.basename(filename, ".*")
    dirname = File.dirname(filename)
    editor_page = _append_page(dirname, filename, tabname)
    editor_page.load(filename)
    __debug_status
  end

  # テンプレート読込み
  def load_template(filename)
    editor_page = _append_page
    editor_page.load(filename, true)
    __debug_status
  end

  # ページを閉じる
  def close
    self.remove_page(self.page)
    __debug_status
  end

  # 新規ページ追加
  def append
    _append_page
    __debug_status
  end

  # ページ追加
  private def _append_page(dirname = nil, filename = nil, tabname = nil)
    editor_page = Widget_Page.new(@status_area)
    tabname ||= "program#{@next_pageno}"
    @next_pageno += 1
    self.insert_page(self.n_pages, editor_page, Gtk::Label.new(tabname))
    self.show_all
    self.page = self.n_pages - 1   # 挿入ページを表示(show_allの後の指定必須)

    return editor_page
  end

  # カレントページの情報を取得
  def get_page_properties
    editor_page   = self.get_nth_page(self.page)              # 当該ページの child widget
    return editor_page.dirname, editor_page.basename, self.get_tab_label(editor_page).text, editor_page.status
  end

  private def __debug_status
    puts "next_pageno : #{@next_pageno}"

    if self.n_pages == 0
      puts "[EMPTY]"
    else
      self.n_pages.times do |i|
        editor_page = self.get_nth_page(i)
        puts "#{i} : #{editor_page.dirname}  #{editor_page.basename}  #{self.get_tab_label(editor_page).text}  #{editor_page.status}"
      end
    end
  end

end


# 実行結果出力画面
class Widget_OutputScreen < Widget_ScrolledText

  def initialize
    super
    @view.buffer.create_tag('info',   {foreground: 'gray'})
    @view.buffer.create_tag('result', {weight: 600})          # SEMIBOLD
    @view.set_editable(false)
  end

  # 最下行にテキストを挿入
  def add_tail(text, tag = nil)
    @view.buffer.insert(@view.buffer.end_iter, text)
    unless tag == nil                                         # 指定されたタグの書式で表示
      iter_s = @view.buffer.get_iter_at_offset(@view.buffer.end_iter.offset - text.size)
      iter_e = @view.buffer.end_iter
      @view.buffer.apply_tag(tag, iter_s, iter_e)
    end
  end

  # 最下行までスクロール
  def scroll_tail
    mark = @view.buffer.create_mark(nil, @view.buffer.end_iter, true)
    @view.scroll_to_mark(mark, 0, false, 0, 1)   # (scroll_to_iterだと最下行まで移動せず)
  end
end


# キーボード入力画面
class Widget_InputScreen < Gtk::Entry
  def initialize(drb_portno)
    super()                             # 引数なしで呼び出し
    self.signal_connect("activate") do
      text = self.text
      self.text = ""                    # 入力内容クリア
      puts "Entry contents: #{text}"
      begin
        cl = DRbObject.new_with_uri("druby://localhost:#{drb_portno}")
        cl.puts(text)                   # DRbサーバに送信(STDINをエミュレート)
      rescue => e
        p e
      end
    end
  end
end


# プログラミング用パッド
class Pad < Gtk::Window

  def initialize
    super("rbpad")
    self.set_size_request(800, 600)

    # DRb用ポート番号
    @drb_portno = 49322

    # UIマネージャ用メニュー
    menu = _define_menu
    actions_menubar = _define_actions_menubar      # アクション定義(メニューバー)
    actions_toolbar = _define_actions_toolbar      # アクション定義(ツールバー)

    # UIマネージャ
    uimanager = Gtk::UIManager.new

    toolbar_group = Gtk::ActionGroup.new("toolbar_group")
    toolbar_group.add_actions(actions_toolbar)
    uimanager.insert_action_group(toolbar_group, 0)

    menubar_group = Gtk::ActionGroup.new("menubar_group")
    menubar_group.add_actions(actions_menubar)
    uimanager.insert_action_group(menubar_group, 0)

    self.add_accel_group(uimanager.accel_group)   # ショートカットキー有効化
    uimanager.add_ui(menu)

    # コンソール(出力用)
    @console_output = Widget_OutputScreen.new

    # コンソール(出力用)フレーム
    frame_output = Gtk::Frame.new(" 実行結果 ")
    frame_output.add(@console_output)

    # コンソール(入力用)
    @console_input = Widget_InputScreen.new(@drb_portno)

    # コンソール(入力用)フレーム
    frame_input = Gtk::Frame.new(" キーボード入力 ")
    frame_input.add(@console_input)

    # ステータス表示用ラベル
    status_area = Gtk::Label.new
    style = Gtk::Style.new
    style.font_desc = Pango::FontDescription.new("MS Gothic 9")
    status_area.style = style

    frame_status = Gtk::Frame.new
    frame_status.add(status_area)

    # エディタ
    @editor = Widget_Editor.new(status_area)

    # 縦可変仕切り(エディタ＋出力)
    vpaned = Gtk::VPaned.new
    vpaned.pack1(@editor, true, false)
    vpaned.pack2(frame_output.set_shadow_type(Gtk::SHADOW_ETCHED_IN), true, false)
    vpaned.position = 300

    # 横固定仕切り(入力＋ステータス)
    hbox = Gtk::HBox.new
    hbox.pack_start(frame_input.set_shadow_type(Gtk::SHADOW_ETCHED_IN), true, true)
    hbox.pack_start(frame_status.set_shadow_type(Gtk::SHADOW_ETCHED_IN), false, false)
    frame_status.set_size_request(150, -1)

    # コンテナ
    vbox_all = Gtk::VBox.new(false, 0)
    vbox_all.pack_start(uimanager.get_widget("/MenuBar"), false, true, 0)
    vbox_all.pack_start(uimanager.get_widget("/ToolBar"), false, true, 0)
    vbox_all.pack_start(vpaned, true, true, 0)
    vbox_all.pack_start(hbox, false, false, 0)

    # ウィンドウ設定
    @editor.page_focus   # エディタのページにフォーカスをセット
    self.add(vbox_all)
    self.show_all

    self.signal_connect("delete_event") do
      puts "clicked [x]"
      _close_page_all     # trueが返ってきた場合は "destroy"シグナルは発生されない
    end

    self.signal_connect("destroy") do
      _quit
    end
  end

  # メニュー定義
  private def _define_menu
    content = IO.read("#{File.expand_path(File.dirname(__FILE__))}/config/menubar.xml")
    "<ui>
      <menubar name='MenuBar'>
        <menu action='file'>
          <menuitem action='run' />
          <separator />
          <menuitem action='new' />
          <menuitem action='open' />
          <menuitem action='save' />
          <menuitem action='saveas' />
          <separator />
          <menuitem action='close' />
          <separator />
          <menuitem action='exit' />
        </menu>
        #{content}
        <menu action='help'>
          <menuitem action='ref_ruby' />
          <menuitem action='ref_dxruby' />
          <separator />
          <menuitem action='ruby_ver' />
          <separator />
          <menuitem action='about' />
        </menu>
      </menubar>
      <toolbar name='ToolBar'>
        <toolitem action='Exec' />
        <separator />
      </toolbar>
    </ui>"
  end

  # メニューバー用アクション定義
  private def _define_actions_menubar

    uri_ref_ruby   = nil
    uri_ref_dxruby = nil
    File.open("#{File.expand_path(File.dirname(__FILE__))}/config/reference_uri.xml") do |fp|
      content = REXML::Document.new(fp)
      uri_ref_ruby   = content.elements["references/ref_ruby"].attributes["uri"]
      uri_ref_dxruby = content.elements["references/ref_dxruby"].attributes["uri"]
    end

    actions = [
      ["file",       nil,                 "ファイル(_F)"],
      ["run",        Gtk::Stock::EXECUTE, "プログラムを実行する",          "<control>R",        nil, Proc.new{ _exec }],
      ["new",        Gtk::Stock::NEW,     "プログラムを新しく作る",        nil,                 nil, Proc.new{ _new }],
      ["open",       Gtk::Stock::OPEN,    "プログラムを読みこむ...",       nil,                 nil, Proc.new{ _open }],
      ["save",       Gtk::Stock::SAVE,    "プログラムを保存する",          nil,                 nil, Proc.new{ _save }],
      ["saveas",     Gtk::Stock::SAVE_AS, "プログラムを別名で保存する...", "<shift><control>S", nil, Proc.new{ _save_as }],
      ["close",      Gtk::Stock::CLOSE,   "プログラムを閉じる",            nil,                 nil, Proc.new{ _close }],
      ["exit",       Gtk::Stock::QUIT,    "rbpadを終了する",               nil,                 nil, Proc.new{ _close_page_all }],

      ["help",       nil,                 "ヘルプ(_H)"],
      ["ref_ruby",   nil,                 "Rubyリファレンス",              nil,                 nil, Proc.new{ _startcmd(uri_ref_ruby) }],
      ["ref_dxruby", nil,                 "DXRubyリファレンス",            nil,                 nil, Proc.new{ _startcmd(uri_ref_dxruby) }],
      ["ruby_ver",   nil,                 "Rubyバージョン",                nil,                 nil, Proc.new{ _ruby_ver }],
      ["about",      nil,                 "rbpadについて",                 nil,                 nil, Proc.new{ _about }],
    ]

    # XMLファイルからの設定情報を反映(ユーザカスタマイズ用)
    File.open("#{File.expand_path(File.dirname(__FILE__))}/config/menubar_actions.xml") do |fp|
      content = REXML::Document.new(fp)

      content.elements.each('menubar_action/branch') do |e|        # 親または中間枝
        actions << [e.attributes['id'],
                    nil, 
                    e.attributes['desc']]
      end

      content.elements.each('menubar_action/item') do |e|          # メニュー項目
        actions << [e.attributes['id'],
                    nil,
                    e.attributes['desc'],
                    e.attributes['acckey'],
                    nil,
                    Proc.new{ _insert_statement(e.text.gsub(/^\n/, ''))}]
      end

      content.elements.each('menubar_action/template') do |e|      # テンプレート読み込み対象ファイル
        actions << [e.attributes['id'],
                    nil,
                    e.attributes['desc'],
                    e.attributes['acckey'],
                    nil,
                    Proc.new{ _load_template(e.text.gsub(/^\n/, '').chomp)}]
      end
    end

    return actions
  end

  # ツールバー用アクション定義
  private def _define_actions_toolbar
    [
      ["Exec", Gtk::Stock::EXECUTE, "プログラム実行", nil, "プログラムを実行する", Proc.new{ _exec }]
    ]
  end


  # コードの実行
  private def _exec
    thread = Thread.start do
      dirname, basename, tabname, status = @editor.get_page_properties
      if dirname and Dir.exist?(dirname)
        # すでに既存ディレクトリ上にファイルが存在している場合
        run_dirname  = dirname                           # 当該ディレクトリ上で実行
        run_filename = @editor.save_tmp(dirname)
      else
        tmp_dirname  = Dir.mktmpdir(["ruby_", "_tmp"])
        run_dirname  = tmp_dirname                       # 一時ディレクトリ上で実行
        run_filename = @editor.save_tmp(tmp_dirname)
      end

      # DRb用の一時ファイルを実行ディレクトリに保存
      required_filename = _save_required_file(run_dirname)

      #puts "tmp_dirname       : #{tmp_dirname}"
      #puts "run_dirname       : #{run_dirname}"
      #puts "run_filename      : #{run_filename}"
      #puts "required_filename : #{required_filename}"

      # 実行コマンド生成
      # cmd = %Q{ruby -E UTF-8 -r #{required_filename} -C #{run_dirname} #{run_filename}}               # -C (Ruby 2.2以降では日本語ディレクトリの際に動作しない)
      cmd = %Q{cd /d "#{run_dirname}" & ruby -E UTF-8 -r "#{required_filename}" #{run_filename}}
      puts cmd

      # 実行
      @console_output.add_tail("> start: #{tabname} (#{Time.now.strftime('%H:%M:%S')})\n", "info")      # 最下行に挿入
      @console_output.scroll_tail                                                                       # 最下行までスクロール
      IO.popen(cmd, err: [:child, :out]) do |pipe|                                                      # 標準エラー出力を標準出力にマージ
        pipe.each do |line|
          line.gsub!(run_filename, tabname)                                                             # 出力用に一時ファイル名をタブ名に置換
          @console_output.add_tail(line, "result")                                                      # 最下行に挿入
          @console_output.scroll_tail                                                                   # 最下行までスクロール
        end
      end
      @console_output.add_tail("> end  : #{tabname} (#{Time.now.strftime('%H:%M:%S')})\n\n", "info")    # 最下行に挿入
      @console_output.scroll_tail                                                                       # 最下行までスクロール

      # 一時ディレクトリ削除(再帰的に一時ディレクトリ内のファイルも削除)
      FileUtils.remove_entry_secure "#{run_dirname}/#{run_filename}"
      FileUtils.remove_entry_secure required_filename
      FileUtils.remove_entry_secure tmp_dirname if tmp_dirname
    end
  end

  # DRbサーバ用コード(起動時にrequireして STDINをエミュレート)
  private def _save_required_file(tmp_dirname)
    # $stdin <-- (druby) -- $in
    script = <<-"EOS".gsub(/^\s+/, '')     # インデント除去(Ruby 2.3以降なら <<~"EOS")
      require 'drb/drb'
      $stdout.sync = true
      $stderr.sync = true
      $stdin, $in = IO.pipe
      DRb.start_service("druby://localhost:#{@drb_portno}", $in)
    EOS
    basename = "rq_#{Utility.get_uniqname}.rb"
    tmpfilepath = "#{tmp_dirname}/#{basename}"
    File.open(tmpfilepath, "w") do |fp|
      fp.puts script
    end
    return tmpfilepath                     # 一時ファイルのフルパス
  end

  # Rubyバージョン表示
  private def _ruby_ver
    thread = Thread.start do
      IO.popen("ruby -v & gem list --quiet --local gtk2 dxruby", err: [:child, :out]) do |pipe|
        pipe.each do |line|
          @console_output.add_tail(line)             # 最下行に挿入
        end
      end
      @console_output.add_tail("\n")                 # 最下行に挿入(空行)
      @console_output.scroll_tail                    # 最下行までスクロール
    end
  end

  # rbpadについて
  private def _about
    msg = <<-"EOS".gsub(/^\s+/, '')
      rbpad.rb (ver. 0.5.0)
      Copyright (c) 2018 Koki Kitamura
      This program is licenced under the same licence as Ruby-GNOME2.
    EOS
    @console_output.add_tail(msg + "\n")   # 最下行に挿入
    @console_output.scroll_tail            # 最下行までスクロール
  end

  # ファイル読み込み
  private def _open
    dialog = Gtk::FileChooserDialog.new(
      "ファイルを開く",
      self,
      Gtk::FileChooser::ACTION_OPEN,
      nil,
      [Gtk::Stock::OK, Gtk::Dialog::RESPONSE_ACCEPT],
      [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL]
    )

    # ファイルフィルターの設定
    filter1 = Gtk::FileFilter.new
    filter2 = Gtk::FileFilter.new
    filter1.name = "Ruby Program Files (*.rb)"
    filter2.name = "All Files (*.*)"
    filter1.add_pattern('*.rb')
    filter2.add_pattern('*')
    dialog.add_filter(filter1)                      # 最初に追加されたフィルターがデフォルト
    dialog.add_filter(filter2)

    dialog.run do |res|
      if res == Gtk::Dialog::RESPONSE_ACCEPT
        filename = dialog.filename.gsub('\\', '/')  # /foo/bar/zzz
        @editor.load(filename)                      # 指定パスからファイルを読み込み
      end
    end
    dialog.destroy
  end

  # ファイル保存
  private def _save
    # ステータスが「:EMPTY」または「:SAVED」なら何もしない
    # dirnameが存在するディレクトリなら黙って上書き保存
    # 上記以外の場合、save_asをコール
    dirname, basename, tabname, status = @editor.get_page_properties
    puts "status #{status}  basename #{basename}  dirname #{dirname}"
    return if status == :EMPTY
    return if status == :SAVED
    if dirname and Dir.exist?(dirname) and basename
      @editor.save("#{dirname}/#{basename}")        # 指定パスにファイルを保存
    else
      _save_as                                      # ダイアログ表示
    end
  end

  # 名前を付けてファイルを保存
  private def _save_as
    dialog = Gtk::FileChooserDialog.new(
      "名前を付けて保存",
      self,
      Gtk::FileChooser::ACTION_SAVE,
      nil,
      [Gtk::Stock::OK,     Gtk::Dialog::RESPONSE_ACCEPT],
      [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL]
    )
    # すでに同名のファイルが存在する場合、上書きするかどうかを確認
    dialog.do_overwrite_confirmation = true
    dialog.signal_connect("confirm_overwrite") do |fc|
      puts "confirm #{dialog.uri}"
      Gtk::FileChooser::CONFIRMATION_CONFIRM
    end

    # ファイルフィルターの設定
    filter1 = Gtk::FileFilter.new
    filter2 = Gtk::FileFilter.new
    filter1.name = "Ruby Program Files (*.rb)"
    filter2.name = "All Files (*.*)"
    filter1.add_pattern('*.rb')
    filter2.add_pattern('*')
    dialog.add_filter(filter1)                      # 最初に追加されたフィルターがデフォルト
    dialog.add_filter(filter2)

    dialog.run do |res|
      if res == Gtk::Dialog::RESPONSE_ACCEPT
        puts dialog.filename
        filename = dialog.filename.gsub('\\', '/')  # /foo/bar/zzz
        @editor.save(filename)                      # 指定パスにファイルを保存
      end
    end
    dialog.destroy
  end

  # 確認ダイアログ(Yes/No/Cancel)
  private def _draw_confirm_dialog(title, labeltext, parent)
    dialog = Gtk::Dialog.new(title, parent, Gtk::Dialog::MODAL)

    dialog.vbox.pack_start(Gtk::Label.new(labeltext), true, true, 30)

    dialog.add_button(Gtk::Stock::YES,    Gtk::Dialog::RESPONSE_YES)
    dialog.add_button(Gtk::Stock::NO,     Gtk::Dialog::RESPONSE_NO)
    dialog.add_button(Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL)
    dialog.default_response = Gtk::Dialog::RESPONSE_CANCEL         # デフォルト設定(キャンセルボタン)
    dialog.show_all

    res = nil
    dialog.run do |response|
      #p "YES"    if response == Gtk::Dialog::RESPONSE_YES
      #p "NO"     if response == Gtk::Dialog::RESPONSE_NO
      #p "CANCEL" if response == Gtk::Dialog::RESPONSE_CANCEL
      res = response
    end
    dialog.destroy
    return res
  end

  # テンプレート読み込み
  private def _load_template(basename)
    @editor.load_template("#{File.expand_path(File.dirname(__FILE__))}/template/#{basename}")
  end

  # 外部リファレンス表示
  private def _startcmd(uri)
    if uri =~ /^http/
      cmd = "start #{uri}"
    else
      # ローカルファイルの場合はスクリプトの位置を起点にした相対パス指定を前提
      cmd = "start #{File.expand_path(File.dirname(__FILE__))}/#{uri}"
    end

    Thread.start do
#      cmd = "start #{File.dirname(__FILE__)}/help/#{refname}"   
      p cmd
      system(cmd)        # 既定のアプリケーションで開く
    end
  end

  # 新規追加
  private def _new
    @editor.append
    @editor.page_focus   # エディタのページにフォーカスをセット
  end

  # 閉じる
  private def _close
    _close_page
    _quit if @editor.n_pages <= 0    # ページがなくなったら終了
  end

  # すべて閉じる
  private def _close_page_all
    until @editor.n_pages <= 0
      return true if _close_page == :CANCEL    # trueなら "delete_event"([x])からのコール時に "destroy"されない
    end
    _quit
  end

  # 終了
  private def _quit
    Gtk.main_quit
  end

  # ページを閉じる
  private def _close_page
    dirname, basename, tabname, status = @editor.get_page_properties
    if status == :UNSAVED
       # 未保存時はダイアログ表示
       res = _draw_confirm_dialog("rbpad", " #{tabname} はまだ保存されていません。閉じる前に保存しますか？", self)
       if    res == Gtk::Dialog::RESPONSE_YES
         _save_as
       elsif res == Gtk::Dialog::RESPONSE_NO
         @editor.close
       else
         return :CANCEL
       end
    else
      # 保存済みまたは空の場合はそのまま閉じる
      @editor.close
    end
  end

  # 構文挿入
  private def _insert_statement(statement)
    @editor.insert_block(statement)
  end

end


# ユーティリティモジュール
module Utility
  module_function def get_uniqname
    # ８文字のランダムな文字列を生成
    (1..8).map {
      (('A'..'Z').to_a + ('a'..'z').to_a + ('0'..'9').to_a).sample
    }.join
  end
end


# エンコーディング設定
Encoding.default_external = 'UTF-8'

# アプリケーション起動
pad = Pad.new
Gtk.main

