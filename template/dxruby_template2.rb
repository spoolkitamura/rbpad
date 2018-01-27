require 'dxruby'

# シーン(場面)クラス
class Scene

  # 初期化
  def initialize
    Window.caption = 'DXRuby Application'
    Window.width   = 640
    Window.height  = 480
  end

  # 描画ループ
  def draw
    Window.loop do
      break if Input.key_release?(K_ESCAPE)
    end
  end

end


# シーンを作成して描画
scene = Scene.new
scene.draw

