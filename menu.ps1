# menu.ps1
# このファイルを環境にあわせて編集してください
#
# $Tool     : ツール実行ファイルのパス設定
# $List     : コマンド定義
# $Image    : アイコン画像定義
# $Fallback : 未定義コマンドのフォールバック処理


# =========================
# ツールパス設定
# =========================
$Script:Tool[[Cmd]::TERM] = "wt.exe"
$Script:Tool[[Cmd]::EDIT] = "notepad.exe"


# =========================
# コマンド定義
# =========================
# 書式:
#   単純起動      $List['キー'] = 'ファイルパスまたはURL'
#   引数付き起動  $List['キー'] = @([Cmd]::OPEN, 'パス', '引数1', ...)
#   プロセス起動  $List['キー'] = @([Cmd]::START, 'パス')
#   エディタ      $List['キー'] = @([Cmd]::EDIT, 'ファイルパス')
#   最新ファイル  $List['キー'] = @([Cmd]::LATEST, 'フォルダパス')
#   サブメニュー  $List['キー'] = @{'サブキー' = @([Cmd]::OPEN, 'パス'); ... }
$Script:List = @{
    # ブラウザでURLを開く
    "g" = "https://www.google.com/"
    "yt" = "https://www.youtube.com/results?search_query="

    # エクスプローラでフォルダを開く
    "dl" = @([Cmd]::OPEN, "$Env:USERPROFILE\Downloads")
    "desk" = @([Cmd]::OPEN, "$Env:USERPROFILE\Desktop")

    # ターミナルを開いてコマンドを実行
    "ps"   = @([Cmd]::TERM, "powershell")
    "ver"  = @([Cmd]::TERM, "ssh","192.168.1.1")
    "gemini"   = @([Cmd]::TERM, "-d","C:\Users\kiw\home\novel","gemini")
    "p"   = @([Cmd]::TERM, "-p","powershell")
    "c"   = @([Cmd]::TERM, "-p","powershell", "-d","C:\Users\kiw\home\novel")
    "q"   = @([Cmd]::TERM, "powershell", "pwd")

    # 指定ディレクトリ配下の最新ファイルを開く
    "log" = @([Cmd]::LATEST, 'C:\logs')

    # サブメニュー
    'prj' = @{
       'src' = 'C:\prj\src'
       'log' = 'C:\prj\log'
    }

    # ネスト（サブコマンド）
    "git" = @{
        "clone" = @([Cmd]::TERM, "git", "clone")
        "pull"  = @([Cmd]::TERM, "git", "pull")
        "push"  = @([Cmd]::TERM, "git", "push")
    }
}


# =========================
# 画像定義
# =========================
# 書式:
#   name = [offsetX, offsetY, path/base64, option]
$Script:Images = [ordered]@{

    "チラ" = @(
        0,
        8,
        "./chilla.png",
        "Size=60"
    )
}


# =========================
# fallback（未定義コマンド）
# =========================
$Script:Fallback = {
    param($txt)

    # URLならそのまま開く
    if ($txt -match '^https?://') {
        Start-Process $txt
    }
    else {
        # Google検索
        Start-Process "https://www.google.com/search?q=$txt"
    }
}

