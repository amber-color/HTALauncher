param(
    [string]$title = "HTALauncher",
    [string]$htaPath = ""
)

# --- Win32 API 定義 ---
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class Win32Activate {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
}
"@

$SW_RESTORE = 9

$hwnd = [Win32Activate]::FindWindow("HTML Application Host Window Class", $title)

if ($hwnd -ne [IntPtr]::Zero) {
    # Windows のフォアグラウンドロックにより、直近で(クリック等の)入力を受けて
    # いない別プロセスからの SetForegroundWindow/ShowWindow は無視されることが
    # あるため、現在のフォアグラウンドスレッドの入力キューに一時的に自スレッド
    # を接続してから操作する（AttachThreadInput は本来この制限を回避するための
    # 正規の手段）
    $fgWnd = [Win32Activate]::GetForegroundWindow()
    $fgProcId = 0
    $fgThreadId = [Win32Activate]::GetWindowThreadProcessId($fgWnd, [ref]$fgProcId)
    $curThreadId = [Win32Activate]::GetCurrentThreadId()

    $attached = $false
    if ($fgThreadId -ne 0 -and $fgThreadId -ne $curThreadId) {
        $attached = [Win32Activate]::AttachThreadInput($curThreadId, $fgThreadId, $true)
    }

    try {
        [Win32Activate]::ShowWindow($hwnd, $SW_RESTORE) | Out-Null
        [Win32Activate]::SetForegroundWindow($hwnd) | Out-Null
    } finally {
        if ($attached) {
            [Win32Activate]::AttachThreadInput($curThreadId, $fgThreadId, $false) | Out-Null
        }
    }
} elseif ($htaPath -ne "") {
    # 未起動：新規起動
    Start-Process "mshta.exe" -ArgumentList ('"' + $htaPath + '"')
}
