'
' 起動スクリプト
'
cmd = "%COMSPEC% /C ruby rbpad.rb"
Set sh = WScript.CreateObject("WScript.Shell")
sh.Run cmd, 0
