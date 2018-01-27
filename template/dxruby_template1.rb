require 'dxruby'

# 初期化
Window.caption = 'DXRuby Application'
Window.width   = 640
Window.height  = 480

# 描画ループ
Window.loop do
  break if Input.key_release?(K_ESCAPE)
end

