=begin

  Ruby/GTK2による Ruby初心者向けプログラミング環境

    Copyright (c) 2018 Koki Kitamura
    This program is licensed under the same license as Ruby-GNOME2.

    Version :
      0.6.0 (2018/03/10)

=end

require 'gtk2'
require 'rexml/document'


# メニュー項目モデル
class MenuitemStore < Gtk::TreeStore

  COLUMN_DESC        = 0    # メニュー表示文言                           menubar_actions.xml
  COLUMN_FG_COLOR    = 1    # 文字色
  COLUMN_FONT_WEIGHT = 2    # フォントウェイト(太さ)
  COLUMN_KIND        = 3    # メニュー種別(menu/menuitem/separator)      menubar.xml
  COLUMN_TYPE        = 4    # アクション種別(branch/item/template)       menubar_actions.xml
  COLUMN_ACCKEY      = 5    # アクセスキー(<shift><ctrl><alt>A)          menubar_actions.xml
  COLUMN_CONTENT     = 6    # 挿入テキスト                               menubar_actions.xml
  COLUMN_ICON_ID     = 7    # アイコン識別子
  COLUMN_STATUS      = 8    # 編集ステータス

  def initialize
    super(String,
          String,
          Float,
          String,
          String,
          String,
          String,
          String,
          String)
    _read_xml   # 設定用 XMLファイルの読み込み
  end

  # 設定用 XMLファイルの読み込み
  private def _read_xml
    hash = {}
    content = IO.read("#{File.expand_path(File.dirname(__FILE__))}/config/menubar_actions.xml")   # メニューバーアクション情報
    xmldoc = REXML::Document.new(content)
    _to_hash(hash, xmldoc)

    content = IO.read("#{File.expand_path(File.dirname(__FILE__))}/config/menubar.xml")           # メニューバー構成情報
    xmldoc = REXML::Document.new(content)
    _add(hash, xmldoc)
  end

  # メニューバーアクション情報をハッシュ化
  private def _to_hash(hash, parent, level = 0)
    parent.elements.each do |child|
      id     = child.attributes['id'].to_s
      desc   = child.attributes['desc'].to_s
      acckey = child.attributes['acckey'].to_s
      text   = child.text.sub(/^\n/, '') if child.text   # 冒頭に挿入される改行のみを除去
      hash[id] = {
        id: id,
        type: child.name,
        desc: desc,
        acckey: acckey,
        content: text
      } unless level == 0
      _to_hash(hash, child, level + 1)
    end
  end

  # ハッシュ化された情報とメニューバー構成情報とから iterの各要素にデータをセット
  private def _add(hash, parent, level = 0, current = nil)
    parent.elements.each do |child|
      action = child.attributes['action'].to_s       # menubar.xlmlと menubar_actions.xlmlとの間のキー情報(TreePath.to_sベース)
      unless level == 0                              # トップレベル(root)はツリー表示しない
        iter = self.append(current)                  # TreeStoreにデータを追加
#        p @hash[action]
         case child.name
         when "menu"                                 # メニュー
           _add_menu(iter, hash[action][:desc])
         when "menuitem"                             # メニュー項目
           _add_menuitem(iter, hash[action][:desc],
                               hash[action][:type],
                               hash[action][:acckey],
                               hash[action][:content])
         when "separator"                            # セパレーター
           _add_separator(iter)
         end
#        puts "#{level} #{child.name} #{current} (#{iter}) #{action}"
      end
      _add(hash, child, level + 1, iter)
    end
  end

  # メニューに関する情報を iterにセット
  private def _add_menu(iter, desc)
    iter[COLUMN_DESC]        = desc
    iter[COLUMN_FG_COLOR]    = "black"
    iter[COLUMN_FONT_WEIGHT] = 400
    iter[COLUMN_KIND]        = "menu"
    iter[COLUMN_TYPE]        = "branch"
    iter[COLUMN_ACCKEY]      = ""
    iter[COLUMN_CONTENT]     = ""
    iter[COLUMN_ICON_ID]     = Gtk::Stock::OPEN
    iter[COLUMN_STATUS]      = "INIT"
  end

  # メニュー項目に関する情報を iterにセット
  private def _add_menuitem(iter, desc, type, acckey, content)
    iter[COLUMN_DESC]        = desc
    iter[COLUMN_FG_COLOR]    = "darkblue"
    iter[COLUMN_FONT_WEIGHT] = 400
    iter[COLUMN_KIND]        = "menuitem"
    iter[COLUMN_TYPE]        = type
    iter[COLUMN_ACCKEY]      = acckey
    iter[COLUMN_CONTENT]     = content
    iter[COLUMN_ICON_ID]     = Gtk::Stock::JUSTIFY_LEFT
    iter[COLUMN_STATUS]      = "INIT"
  end

  # セパレーターに関する情報を iterにセット
  private def _add_separator(iter)
    iter[COLUMN_DESC]        = "--- <separator> ---"
    iter[COLUMN_FG_COLOR]    = "black"
    iter[COLUMN_FONT_WEIGHT] = 400
    iter[COLUMN_KIND]        = "separator"
    iter[COLUMN_TYPE]        = "separator"
    iter[COLUMN_ACCKEY]      = ""
    iter[COLUMN_CONTENT]     = ""
    iter[COLUMN_ICON_ID]     = Gtk::Stock::MEDIA_PAUSE
    iter[COLUMN_STATUS]      = "INIT"
  end

  # 設定内容を'編集'状態に変更(太字表示＋内部ステータス変更)
  private def _mod_status(iter)
    iter[COLUMN_FONT_WEIGHT] = 600
    iter[COLUMN_STATUS]      = "EDITED"
  end

  # メニューを追加
  def add_menu(iter, desc)
    _add_menu(iter, desc)
    _mod_status(iter)         # 編集状態に変更
  end

  # メニュー項目を追加
  def add_menuitem(iter, desc, type, acckey, content)
    _add_menuitem(iter, desc, type, acckey, content)
    _mod_status(iter)         # 編集状態に変更
  end

  # セパレーターを追加
  def add_separator(iter)
    _add_separator(iter)
    _mod_status(iter)         # 編集状態に変更
  end

end


# メニュー項目ツリー
class MenuitemTree < Gtk::ScrolledWindow
  def initialize
    super

    @tree = Gtk::TreeView.new(MenuitemStore.new)
    self.add(@tree)

    # UIマネージャ用メニュー
    menu = _define_menu
    actions_popup   = _define_actions_popup       # アクション定義(ポップアップ)

    # UIマネージャ
    @uimanager = Gtk::UIManager.new
    popup_group = Gtk::ActionGroup.new("popup_group")
    popup_group.add_actions(actions_popup)
    @uimanager.insert_action_group(popup_group, 0)
    @uimanager.add_ui(menu)

    # カラム
    column = Gtk::TreeViewColumn.new
    column.title = '  メニュー構成'

    render_pixbuf = Gtk::CellRendererPixbuf.new   # アイコン用レンダラー
    column.pack_start(render_pixbuf, false)
    column.add_attribute(render_pixbuf, 'stock_id',   MenuitemStore::COLUMN_ICON_ID)

    render_text = Gtk::CellRendererText.new       # テキスト用レンダラー
    column.pack_start(render_text, true)
    column.add_attribute(render_text,   'text',       MenuitemStore::COLUMN_DESC)
    column.add_attribute(render_text,   'foreground', MenuitemStore::COLUMN_FG_COLOR)
    column.add_attribute(render_text,   'weight',     MenuitemStore::COLUMN_FONT_WEIGHT)

    @tree.append_column(column)
    @tree.reorderable = false                     # ドラッグ＆ドロップ設定(無効)

    iter = @tree.model.iter_first
    if iter
      while true
        @tree.expand_row(iter.path, false)        # ツリーが空でなければ第１階層のみツリーを開いて表示
        break unless iter.next!
      end
    end

    # ツリー項目選択時のイベント
    @tree.selection.signal_connect('changed') do |selection|
      @current_iter = @tree.selection.selected
      if @current_iter
        hash = {
          :description => @current_iter[MenuitemStore::COLUMN_DESC],
          :content     => @current_iter[MenuitemStore::COLUMN_CONTENT],
          :acckey      => @current_iter[MenuitemStore::COLUMN_ACCKEY],
          :type        => @current_iter[MenuitemStore::COLUMN_TYPE],
          :kind        => @current_iter[MenuitemStore::COLUMN_KIND]
        }
        @current_iter[MenuitemStore::COLUMN_STATUS] = 'LOADING'
        @proc.call(hash) if @proc                         # MenuitemEditor側へのデータ渡し
        @current_iter[MenuitemStore::COLUMN_STATUS] = 'INIT'
      end
    end

    # マウス右クリックのイベント
    @tree.signal_connect("button_release_event") do |w, e|
      if e.kind_of?(Gdk::EventButton) and e.button == 3   # マウス右クリック
        iter = @tree.selection.selected
        _show_popup(iter, e)                              # ポップアップメニューの表示
      end
    end
  end

  # ポップアップメニューの表示
  private def _show_popup(iter, e)
    # 第１階層は「menu」のみ
    # 階層化できるのは「menu」のみ
    # (「menuitem」および「separator」は必ず末端要素)
    if iter
      kind  = iter[MenuitemStore::COLUMN_KIND]
      depth = iter.path.depth
      if kind == "menu"
        # メニュー
        if depth == 1
          # 第１階層
          @uimanager.get_action("/Popup/add_menuitem").sensitive     = false   # メニュー項目は不可
          @uimanager.get_action("/Popup/add_separator").sensitive    = false   # セパレーターは不可
        else
          # 第１階層以外
          @uimanager.get_action("/Popup/add_menuitem").sensitive     = true
          @uimanager.get_action("/Popup/add_separator").sensitive    = true
        end
        @uimanager.get_action("/Popup/add_menu").sensitive           = true
        @uimanager.get_action("/Popup/add_menu_child").sensitive     = true
        @uimanager.get_action("/Popup/add_menuitem_child").sensitive = true
      else
        # メニュー以外(メニュー項目、セパレーター)
        @uimanager.get_action("/Popup/add_menuitem").sensitive       = true
        @uimanager.get_action("/Popup/add_separator").sensitive      = true
        @uimanager.get_action("/Popup/add_menu").sensitive           = false   # メニューは不可
        @uimanager.get_action("/Popup/add_menu_child").sensitive     = false   # メニュー(下位階層)は不可
        @uimanager.get_action("/Popup/add_menuitem_child").sensitive = false   # メニュー項目(下位階層)は不可
      end
      @uimanager.get_action("/Popup/remove").sensitive               = true
    else
      # メニューがすべて削除されている状態(iter == nil)
      @uimanager.get_action("/Popup/add_menuitem").sensitive         = false
      @uimanager.get_action("/Popup/add_separator").sensitive        = false
      @uimanager.get_action("/Popup/add_menu").sensitive             = false
      @uimanager.get_action("/Popup/add_menu_child").sensitive       = true    # メニュー(下位階層)のみ可(root下に作成)
      @uimanager.get_action("/Popup/add_menuitem_child").sensitive   = false
      @uimanager.get_action("/Popup/remove").sensitive               = false
    end
    # ポップアップメニュー表示
    @uimanager.get_widget("/Popup").popup(nil, nil, e.button, e.time)
  end

  # ポップアップメニュー定義
  private def _define_menu
    "<ui>
      <popup name='Popup'>
        <menuitem action='add_menu' />
        <menuitem action='add_menu_child' />
        <separator />
        <menuitem action='add_menuitem' />
        <menuitem action='add_menuitem_child' />
        <separator />
        <menuitem action='add_separator' />
        <separator />
        <menuitem action='remove' />
      </popup>
    </ui>"
  end

  # ポップアップメニュー用アクション定義
  private def _define_actions_popup
    [
      ["add_menu",           Gtk::Stock::ADD,     "メニューの追加"          ,     nil, nil, Proc.new{ _append(:menu) }],
      ["add_menu_child",     Gtk::Stock::CONVERT, "メニューの追加(下位階層)",     nil, nil, Proc.new{ _append_child(:menu) }],
      ["add_menuitem",       Gtk::Stock::ADD,     "メニュー項目の追加",           nil, nil, Proc.new{ _append(:menuitem) }],
      ["add_menuitem_child", Gtk::Stock::CONVERT, "メニュー項目の追加(下位階層)", nil, nil, Proc.new{ _append_child(:menuitem) }],
      ["add_separator",      Gtk::Stock::ADD,     "セパレーターの追加",           nil, nil, Proc.new{ _append(:separator) }],
      ["remove",             Gtk::Stock::DELETE,  "削除",                         nil, nil, Proc.new{ _remove }],
    ]
  end

  # ツリー項目の追加
  private def _append(kind)
    # 選択項目と同一階層に追加
    iter = @tree.selection.selected
    iter_new = @tree.model.insert_after(iter.parent, iter)   # nilならトップレベル
    case kind
    when :menu
      @tree.model.add_menu(iter_new, "[新メニュー]")
    when :menuitem
      @tree.model.add_menuitem(iter_new, "[新メニュー項目]", "item", "", "#")
    when :separator
      @tree.model.add_separator(iter_new)
    end
    @tree.set_cursor(iter_new.path, nil, false)   # 追加ノードを選択状態
  end

  # ツリー項目(子)の追加
  private def _append_child(kind)
    # 選択項目の下位階層に追加
    iter = @tree.selection.selected
    iter_new = @tree.model.append(iter)
    case kind
    when :menu
      @tree.model.add_menu(iter_new, "[新メニュー]")
    when :menuitem
      @tree.model.add_menuitem(iter_new, "[新メニュー項目]", "item", "", "#")
    end
    @tree.expand_row(iter.path, false) if iter    # ツリー展開
    @tree.set_cursor(iter_new.path, nil, false)   # 追加ノードを選択状態
  end

  # ツリー項目の削除
  private def _remove
    iter = @tree.selection.selected
    path = iter.path
    @tree.model.remove(iter)                      # 削除
    unless @tree.model.iter_is_valid?(@tree.model.get_iter(path))
      unless path.prev!                           # 前
        path.up!                                  # 上
      end
    end
    # カーソルをセット(削除位置の'後'→'前'→'上'の順に対象を選定)
    @tree.set_cursor(path, @tree.get_column(0), false) if path.depth > 0

    unless @tree.model.iter_first
      # TreeStoreが空になったら MenuitemEditor側も空白表示にする
      hash = {
        :description => "",
        :content     => "",
        :acckey      => "",
        :type        => "",
        :kind        => ""
      }
      @proc.call(hash) if @proc                   # MenuitemEditor側へのデータ渡し
    end
  end

  # 再帰的に各ツリー項目の編集ステータスをチェック
  private def _get_status(iter)
    if iter[MenuitemStore::COLUMN_STATUS] == "EDITED"
      @status = :EDITED
      return
    end
    (0...iter.n_children).each do |i|
      child = iter.nth_child(i)         # 子ノード
      _get_status(child)                # 再帰
    end
  end

  # メニュー情報の編集ステータスを取得(:INIT or :EDITED)
  def get_status
    @status = :INIT
    iter =  @tree.model.iter_first
    while iter
      _get_status(iter)
      break unless (iter.next! and @status == :INIT)
    end
    return @status
  end

  # メニュー情報をメニューバー構成情報ファイルに保存
  private def _write_menubar(iter, f = $stdout)
    # nameは省略(actionと同一内容がデフォルトでセットされる)
    # actionは menuと menuitemとで異なる接頭辞を付与
    # (■iter.pathだけだとメニュー組み換えの際に UIManagerの処理で node type doesn't matchとなる可能性あり)
    indent = "  " * (iter.path.depth)
    case iter[MenuitemStore::COLUMN_KIND]
    when "menu"
      f.puts %Q(#{indent}<menu action="m_#{iter.path.to_str}" valid="t">)
    when "menuitem"
      f.puts %Q(#{indent}<menuitem action="mi_#{iter.path.to_str}" valid="t" />)
    when "separator"
      f.puts %Q(#{indent}<separator valid="t" />)
    end
    (0...iter.n_children).each do |i|
      child = iter.nth_child(i)         # 子ノード
      _write_menubar(child, f)          # 再帰
    end
    if iter[MenuitemStore::COLUMN_KIND] == "menu"
      f.puts %Q(#{indent}</menu>)
    end
  end

  # メニュー情報をメニューバーアクション情報ファイルに保存
  private def _write_menubar_actions(iter, f = $stdout)
    # idは _write_menubarの menuと menuitemとに連動させる
# puts "#{iter.path.to_str} #{iter[MenuitemStore::COLUMN_STATUS]}"
    iter[MenuitemStore::COLUMN_STATUS] = "INIT"                   # 初期状態に復帰
    iter[MenuitemStore::COLUMN_FONT_WEIGHT]  = 400                # 初期状態に復帰
    if iter[MenuitemStore::COLUMN_TYPE] == "branch"
      f.puts %Q(<#{iter[MenuitemStore::COLUMN_TYPE]} id="m_#{iter.path.to_str}"  desc=#{iter[MenuitemStore::COLUMN_DESC].encode(xml: :attr)} valid="t" />)
      f.puts %Q()
    elsif iter[MenuitemStore::COLUMN_TYPE] != "separator"
      f.puts %Q(<#{iter[MenuitemStore::COLUMN_TYPE]} id="mi_#{iter.path.to_str}" desc=#{iter[MenuitemStore::COLUMN_DESC].encode(xml: :attr)} acckey=#{iter[MenuitemStore::COLUMN_ACCKEY].encode(xml: :attr)}  valid="t">)
      f.puts %Q(#{iter[MenuitemStore::COLUMN_CONTENT].encode(xml: :text)})
      f.puts %Q(</#{iter[MenuitemStore::COLUMN_TYPE]}>)
      f.puts %Q()
    end
    (0...iter.n_children).each do |i|
      child = iter.nth_child(i)         # 子ノード
      _write_menubar_actions(child, f)  # 再帰
    end
  end

  # メニュー情報を XMLファイルに保存
  def save
    iter = @tree.model.iter_first
    begin
      File.open("#{File.expand_path(File.dirname(__FILE__))}/config/menubar.xml", "wb") do |f|
        f.puts %Q(<menubar>)
        while iter
          _write_menubar(iter, f)
          break unless iter.next!
        end
        f.puts %Q(</menubar>)
      end
    rescue => e
      puts %Q(class=[#{e.class}] message=[#{e.message}])
    end

    iter = @tree.model.iter_first    # .path.to_str
    begin
      File.open("#{File.expand_path(File.dirname(__FILE__))}/config/menubar_actions.xml", "wb") do |f|
        f.puts "<menubar_action>\n\n"
        while iter
          _write_menubar_actions(iter, f)
          break unless iter.next!
        end
        f.puts "</menubar_action>"
      end
    rescue => e
      puts %Q(class=[#{e.class}] message=[#{e.message}])
    end
  end

  # 指定ツリー項目間でツリー構造ごとデータをコピー
  private def _tree_copy(iter_src, iter_dst)
    (0...@tree.model.n_columns).each do |i|
      iter_dst[i] = iter_src[i]                      # 自身のノードの情報を転記([0]～[n])
    end
    (0...iter_src.n_children).each do |i|
      iter_new = @tree.model.append(iter_dst)        # 転記先の子ノードを作成
      _tree_copy(iter_src.nth_child(i), iter_new)
    end
  end

  # ツリー項目の移動
  def move_path(direction)
    iter_src = @tree.selection.selected
    return unless iter_src

    path = iter_src.path
    case direction
    when :up     # 上位階層に移動
      # (1)選択ノードの parentの parentに対して parentのあとに新ノードを追加
      # (2)上記の新ノードに自身のデータおよび配下のノードを再帰的にコピー
      if (iter_src.path.depth >= 2 and iter_src[MenuitemStore::COLUMN_KIND] == "menu") or
         (iter_src.path.depth >= 3 and iter_src[MenuitemStore::COLUMN_KIND] == "menuitem")
        iter_target = iter_src.parent.parent                        # rootを指す場合は nil
        iter_new = @tree.model.insert_after(iter_target, iter_src.parent)
        _tree_copy(iter_src, iter_new)                              # iter_new配下に iter_src配下を再帰的にコピー
        @tree.model.remove(iter_src)                                # 自身を削除
        @tree.set_cursor(iter_new.path, @tree.get_column(0), false) # カーソルをセット
        iter_new[MenuitemStore::COLUMN_STATUS]      = "EDITED"
        iter_new[MenuitemStore::COLUMN_FONT_WEIGHT] = 600
      end
    when :down   # 下位階層に移動
      # (1)選択ノードと同一階層の兄ノード(ただしメニューのみ)に対して新ノードを追加
      # (2)上記の新ノードに自身のデータおよび配下のノードを再帰的にコピー
      while path.prev!
        iter_tmp = @tree.model.get_iter(path)
        if iter_tmp[MenuitemStore::COLUMN_KIND] == "menu"           # 同一階層の兄ノード(menu)を探す
          iter_target = iter_tmp
          break
        end
      end
      if iter_target
        iter_new = @tree.model.append(iter_target)
        _tree_copy(iter_src, iter_new)                              # iter_new配下に iter_src配下を再帰的にコピー
        @tree.model.remove(iter_src)                                # 自身を削除
        @tree.expand_row(iter_target.path, true)                    # ツリー展開(配下すべて対象)
        @tree.set_cursor(iter_new.path, @tree.get_column(0), false) # カーソルをセット
        iter_new[MenuitemStore::COLUMN_STATUS]      = "EDITED"
        iter_new[MenuitemStore::COLUMN_FONT_WEIGHT] = 600
      end
    when :prev   # 同一階層内の上位置に移動
      path.prev!
      iter_dst = @tree.model.get_iter(path)
      if @tree.model.iter_is_valid?(iter_dst)                       # 移動先が有効かつパスの値が異なっていれば入替え
        if iter_src.path != iter_dst.path
          @tree.model.swap(iter_src, iter_dst)
          iter_src[MenuitemStore::COLUMN_STATUS]      = "EDITED"
          iter_src[MenuitemStore::COLUMN_FONT_WEIGHT] = 600
        end
      end
    when :next   # 同一階層内の下位置に移動
      path.next!
      iter_dst = @tree.model.get_iter(path)
      if @tree.model.iter_is_valid?(iter_dst)                       # 移動先が有効かつパスの値が異なっていれば入替え
        if iter_src.path != iter_dst.path
          @tree.model.swap(iter_src, iter_dst)
          iter_src[MenuitemStore::COLUMN_STATUS]      = "EDITED"
          iter_src[MenuitemStore::COLUMN_FONT_WEIGHT] = 600
        end
      end
    end

  end

  # 選択中のメニュー情報を iterにセット(MenuitemEditorからのコールバック用)
  def set_info(hash)
    return if @current_iter == nil                                  # カレントノードがない(未設定など)場合

    unless @current_iter[MenuitemStore::COLUMN_STATUS] == "LOADING"
      @current_iter[MenuitemStore::COLUMN_ACCKEY] = ""
      if hash[:acc_key] != " "   # 先頭要素(＝空白)以外
        @current_iter[MenuitemStore::COLUMN_ACCKEY] += "<shift>"   if hash[:acc_shift]
        @current_iter[MenuitemStore::COLUMN_ACCKEY] += "<control>" if hash[:acc_ctrl]
        @current_iter[MenuitemStore::COLUMN_ACCKEY] += "<alt>"     if hash[:acc_alt]
        @current_iter[MenuitemStore::COLUMN_ACCKEY] += hash[:acc_key] if @current_iter[MenuitemStore::COLUMN_ACCKEY] != ""   # <shift><control><alt>いずれかとの組み合わせ必須
      end

      if    @current_iter[MenuitemStore::COLUMN_KIND] == "menu"
        @current_iter[MenuitemStore::COLUMN_TYPE] = "branch"
      elsif @current_iter[MenuitemStore::COLUMN_KIND] == "menuitem"
        @current_iter[MenuitemStore::COLUMN_TYPE] = (hash[:type] ? "item" : "template")
      end
      @current_iter[MenuitemStore::COLUMN_DESC] = hash[:description]
      @current_iter[MenuitemStore::COLUMN_CONTENT] = hash[:content]

      @current_iter[MenuitemStore::COLUMN_STATUS]      = "EDITED"   # 編集ステータスを変更
      @current_iter[MenuitemStore::COLUMN_FONT_WEIGHT] = 600
    end
  end

  # コールバック用 Procオブジェクト(MenuitemEditor側へのデータ渡し)の登録
  def set_proc(proc)
    @proc = proc
  end

  # フォーカスをセット
  def set_focus
    @tree.set_focus(true)
  end

end


# メニュー項目エディタ
class MenuitemEditor < Gtk::VBox

  def initialize
    super

    @description = Gtk::Entry.new

    @kind_statement = Gtk::RadioButton.new("部分挿入用    ")
    @kind_template  = Gtk::RadioButton.new(@kind_statement, "新規雛形用")
    @kind_statement.active = true
    kind = Gtk::HBox.new
    #kind.pack_start(Gtk::Label.new("  タイプ       "), false, true)
    kind.pack_start(@kind_statement, false, true)
    kind.pack_start(@kind_template,  false, true)

    @acckey1     = Gtk::CheckButton.new("<Shift>  ")
    @acckey2     = Gtk::CheckButton.new("<Ctrl>  ")
    @acckey3     = Gtk::CheckButton.new("<Alt>  ")
    @acckey4     = Gtk::ComboBox.new

    @acckey1.active = false
    @acckey2.active = false
    @acckey3.active = false
    [' ', *'A'..'Z', *'0'..'9'].each do |val|
      @acckey4.append_text(val)
    end
    @acckey4.active = 0

    acckey = Gtk::HBox.new
    acckey.pack_start(Gtk::Label.new("  ショートカットキー    "), false, true)
    acckey.pack_start(@acckey1, false, true)
    acckey.pack_start(@acckey2, false, true)
    acckey.pack_start(@acckey3, false, true)
    acckey.pack_start(@acckey4, false, true)

    scrolled_window = Gtk::ScrolledWindow.new
    scrolled_window.set_policy(Gtk::POLICY_AUTOMATIC,
                               Gtk::POLICY_AUTOMATIC)
    scrolled_window.set_shadow_type(Gtk::SHADOW_IN)

    @view = Gtk::TextView.new
    @view.set_editable(true)
    @view.set_cursor_visible(true)
    scrolled_window.add(@view)

    font = Pango::FontDescription.new('MS Gothic 12')
    @description.modify_font(font)
    @view.modify_font(font)
    @view.set_wrap_mode(Gtk::TextTag::WRAP_NONE)
    @view.pixels_above_lines = 4
    @view.left_margin = 4

    self.pack_start(kind,            false, true)
    self.pack_start(@description,    false, true)
    self.pack_start(scrolled_window, true,  true)
    self.pack_start(acckey,          false, true)

    @acckey1.signal_connect("toggled")         { _callback }
    @acckey2.signal_connect("toggled")         { _callback }
    @acckey3.signal_connect("toggled")         { _callback }
    @acckey4.signal_connect("changed")         { _callback }
    @kind_statement.signal_connect("toggled")  { _callback }
    @kind_template.signal_connect("toggled")   { _callback }
    @description.signal_connect("changed")     { _callback }
    @view.buffer.signal_connect("changed")     { _callback }
  end

  # コールバック処理(MenuitemTree側へのデータ渡し)
  private def _callback
      hash = {
        :acc_shift   => @acckey1.active?,
        :acc_ctrl    => @acckey2.active?,
        :acc_alt     => @acckey3.active?,
        :acc_key     => @acckey4.active_text,
        :type        => @kind_statement.active?,
        :description => @description.text,
        :content     => @view.buffer.text
      }
      @proc.call(hash) if @proc   # コールバック用 Procオブジェクトのコール
  end

  # 各コンポーネントについて活性/非活性の制御
  private def _set_edit_status(kind)
    case kind
    when "menu"
      @kind_statement.sensitive = false
      @kind_template.sensitive  = false
      @acckey1.sensitive        = false
      @acckey2.sensitive        = false
      @acckey3.sensitive        = false
      @acckey4.sensitive        = false
      @description.editable     = true
      @description.sensitive    = true
      @view.editable            = false
      @view.cursor_visible      = false
      @view.sensitive           = true
    when "menuitem"
      @kind_statement.sensitive = true
      @kind_template.sensitive  = true
      @acckey1.sensitive        = true
      @acckey2.sensitive        = true
      @acckey3.sensitive        = true
      @acckey4.sensitive        = true
      @description.editable     = true
      @description.sensitive    = true
      @view.editable            = true
      @view.cursor_visible      = true
      @view.sensitive           = true
    when "separator"
      @kind_statement.sensitive = false
      @kind_template.sensitive  = false
      @acckey1.sensitive        = false
      @acckey2.sensitive        = false
      @acckey3.sensitive        = false
      @acckey4.sensitive        = false
      @description.editable     = false
      @description.sensitive    = false
      @view.editable            = false
      @view.cursor_visible      = false
      @view.sensitive           = true
    end
  end

  # 各コンポーネントへの情報をセット(MenuitemTreeからのコールバック用)
  def get_info(hash)
    @description.text      = hash[:description] if hash[:description]           # if条件 nil要否?!
    @view.buffer.text      = hash[:content]     if hash[:content]               # if条件 nil要否?!
    @kind_statement.active = true if hash[:type] == "item"
    @kind_template.active  = true if hash[:type] == "template"
    @acckey1.active        = (hash[:acckey] =~ /\<shift\>/i   ? true : false)   # <shift>   記載があれば true
    @acckey2.active        = (hash[:acckey] =~ /\<control\>/i ? true : false)   # <control> 記載があれば true
    @acckey3.active        = (hash[:acckey] =~ /\<alt\>/i     ? true : false)   # <alt>     記載があれば true
    case hash[:acckey]
    when /\>([a-z])/i                                                           # >(閉じ括弧)のあとの文字
      @acckey4.active = ($1.upcase.ord - 'A'.ord) + 1                           # 'A'～'Z'のリスト上のインデックス
    when /\>([0-9])/i                                                           # >(閉じ括弧)のあとの文字
      @acckey4.active = ($1.ord - '0'.ord) + 27                                 # '0'～'9'のリスト上のインデックス
    else
      @acckey4.active = 0
    end

    # コンポーネントの編集可否設定
    _set_edit_status(hash[:kind])
  end

  # コールバック用 Procオブジェクト(MenuitemTree側へのデータ渡し)の登録
  def set_proc(proc)
    @proc = proc
  end

end


# マネージャ
class ConfigEditor < Gtk::Window
  @@run = false                                      # rbpadからの二重起動防止用

  def initialize
    return nil if @@run                              # 起動中ステータスなら nilを返す
    @@run = true                                     # 起動中ステータスを設定

    super("rbpad [configration editor]")

    # UIマネージャ用メニュー
    menu = _define_menu
    actions_menubar = _define_actions_menubar        # アクション定義(メニューバー)
    actions_toolbar = _define_actions_toolbar        # アクション定義(ツールバー)

    # UIマネージャ
    @uimanager = Gtk::UIManager.new

    toolbar_group = Gtk::ActionGroup.new("toolbar_group")
    toolbar_group.add_actions(actions_toolbar)
    @uimanager.insert_action_group(toolbar_group, 0)

    menubar_group = Gtk::ActionGroup.new("menubar_group")
    menubar_group.add_actions(actions_menubar)
    @uimanager.insert_action_group(menubar_group, 0)

    self.add_accel_group(@uimanager.accel_group)     # ショートカットキー有効化
    @uimanager.add_ui(menu)

    @tree   = MenuitemTree.new                       # ツリー
    @editor = MenuitemEditor.new                     # エディタ

    @tree.set_proc(Proc.new{|hash| @editor.get_info(hash)})
    @editor.set_proc(Proc.new{|hash| @tree.set_info(hash)})

    # 水平ペインによるレイアウト
    hpaned = Gtk::HPaned.new
    hpaned.pack1(@tree,   true, false)
    hpaned.pack2(@editor, true, false)
    hpaned.position = 270          # 初期の仕切り位置

    vbox_all = Gtk::VBox.new(false, 0)
    vbox_all.pack_start(@uimanager.get_widget("/MenuBar"), false, true, 0)
    vbox_all.pack_start(@uimanager.get_widget("/ToolBar"), false, true, 0)
    vbox_all.pack_start(hpaned, true, true, 0)

    self.add(vbox_all)

    self.set_default_size(800, 600)
    self.set_window_position(Gtk::Window::POS_CENTER)
    self.show_all

    @tree.set_focus

    self.signal_connect("delete_event") do
      puts "clicked [x]"
      _confirm     # trueが返ってきた場合は "destroy"シグナルは発生されない
    end

    self.signal_connect('destroy') do
      _quit
    end
  end

  # メニュー定義
  private def _define_menu
    "<ui>
      <menubar name='MenuBar'>
        <menu action='file'>
          <menuitem action='save' />
          <separator />
          <menuitem action='exit' />
        </menu>
      </menubar>
      <toolbar name='ToolBar'>
        <toolitem action='up' />
        <toolitem action='down' />
        <toolitem action='left' />
        <toolitem action='right' />
      </toolbar>
    </ui>"
  end

  # メニューバー用アクション定義
  private def _define_actions_menubar
    [
      ["file",          nil,                    "ファイル(_F)" ],
      ["save",          Gtk::Stock::SAVE,       "設定内容を保存する", nil, nil, Proc.new{ _save }],
      ["exit",          Gtk::Stock::QUIT,       "終了",               nil, nil, Proc.new{ _confirm }],
    ]
  end

  # ツールバー用アクション定義
  private def _define_actions_toolbar
    [
      ["up",            Gtk::Stock::GO_UP,      "前に移動",     nil, "選択項目を前に移動する",       Proc.new{ _path(:prev) }],
      ["down",          Gtk::Stock::GO_DOWN,    "後に移動",     nil, "選択項目を後に移動する",       Proc.new{ _path(:next) }],
      ["left",          Gtk::Stock::GO_BACK,    "上位階層",     nil, "選択項目を上位階層に移動する", Proc.new{ _path(:up)   }],
      ["right",         Gtk::Stock::GO_FORWARD, "下位階層",     nil, "選択項目を下位階層に移動する", Proc.new{ _path(:down) }],
    ]
  end

  private def _save
    @tree.save
  end

  private def _path(direction)
    @tree.move_path(direction)
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
      res = response
    end
    dialog.destroy
    return res
  end

  private def _confirm
    if @tree.get_status == :EDITED
      # 確認ダイアログ
      res = _draw_confirm_dialog("確認", "編集内容はまだ保存されていません。閉じる前に保存しますか？", self)
      if    res == Gtk::Dialog::RESPONSE_YES
        _save          # 保存
      elsif res == Gtk::Dialog::RESPONSE_CANCEL
        return true    # trueなら "delete_event"([x])からのコール時に "destroy"されない
      end
    end
    _quit
  end

  private def _quit
    @@run = false                     # 起動中ステータスを解除
    Gtk.main_quit if __FILE__ == $0   # rbpad本体から起動された場合は Gtkは終了しない
  end

end


if __FILE__ == $0
  # コンフィグレーションエディタの生成と起動
  config_editor = ConfigEditor.new
  Gtk.main
end

