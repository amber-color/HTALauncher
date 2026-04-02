param(
    [string]$title = "HTALauncher"
)

# --- Win32 API 定義 ---
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class Win32 {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int X,
        int Y,
        int cx,
        int cy,
        uint uFlags
    );
}
"@

# 最前面フラグ
$HWND_TOPMOST = [IntPtr](-1)
$SWP_NOMOVE = 0x0002
$SWP_NOSIZE = 0x0001

# --- ウィンドウ取得リトライ ---
$hwnd = [IntPtr]::Zero

for ($i = 0; $i -lt 50; $i++) {
    $hwnd = [Win32]::FindWindow("HTML Application Host Window Class", $title)
    if ($hwnd -ne [IntPtr]::Zero) {
        break
    }
    Start-Sleep -Milliseconds 100
}

# --- 最前面化 ---
if ($hwnd -ne [IntPtr]::Zero) {
    [Win32]::SetWindowPos($hwnd, $HWND_TOPMOST, 0, 0, 0, 0, $SWP_NOMOVE -bor $SWP_NOSIZE) | Out-Null
}
