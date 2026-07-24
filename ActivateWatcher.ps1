param(
    [string]$triggerFlagPath,
    [string]$htaPath = "",
    [string]$title = "HTALauncher",
    [string]$selfTitle = "HTALauncherCursorTrigger"
)

# 復帰のたびに powershell.exe を新規起動すると、コンパイル抜きでも
# プロセス起動だけで約 0.9 秒かかり体感速度が悪い。そのため CursorTrigger.hta
# 起動時にこのスクリプトを一つだけ常駐させておき、ホバーのたびに軽量な
# シグナルファイルを書き込むだけにして、常駐プロセス側がそれを検知して
# 即座に復帰処理を行う。
$dllPath = Join-Path $PSScriptRoot "Win32Helpers.dll"

$csharpSource = @"
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

if (-not (Test-Path $dllPath)) {
    Add-Type -OutputAssembly $dllPath -TypeDefinition $csharpSource
}
Add-Type -Path $dllPath

# CursorTrigger.hta が再起動されるたびにこのスクリプトも起動されるため、
# 既に別の ActivateWatcher.ps1 が動いていればすぐ終了する（PIDロックファイルで判定）
$lockPath = Join-Path $PSScriptRoot ".activate_watcher.lock"
if (Test-Path $lockPath) {
    $existingPid = Get-Content $lockPath -ErrorAction SilentlyContinue
    $existingProc = $null
    if ($existingPid) { $existingProc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue }
    if ($existingProc -and $existingProc.ProcessName -eq "powershell") {
        exit 0
    }
}
$PID | Out-File $lockPath -Encoding ascii -Force

$SW_RESTORE = 9

function Invoke-Activate {
    $hwnd = [Win32Activate]::FindWindow("HTML Application Host Window Class", $title)
    if ($hwnd -ne [IntPtr]::Zero) {
        # Windows のフォアグラウンドロックにより、直近で(クリック等の)入力を
        # 受けていない別プロセスからの SetForegroundWindow/ShowWindow は無視
        # されることがあるため、現在のフォアグラウンドスレッドの入力キューに
        # 一時的に自スレッドを接続してから操作する
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
        Start-Process "mshta.exe" -ArgumentList ('"' + $htaPath + '"')
    }
}

Remove-Item $triggerFlagPath -ErrorAction SilentlyContinue

try {
    $lastSelfCheck = Get-Date
    while ($true) {
        Start-Sleep -Milliseconds 50
        if (Test-Path $triggerFlagPath) {
            Remove-Item $triggerFlagPath -ErrorAction SilentlyContinue
            Invoke-Activate
        }
        # 2秒ごとに CursorTrigger.hta 自身の生存確認をし、終了していたら道連れに終了する
        if (((Get-Date) - $lastSelfCheck).TotalMilliseconds -ge 2000) {
            $lastSelfCheck = Get-Date
            $selfHwnd = [Win32Activate]::FindWindow("HTML Application Host Window Class", $selfTitle)
            if ($selfHwnd -eq [IntPtr]::Zero) { break }
        }
    }
} finally {
    Remove-Item $lockPath -ErrorAction SilentlyContinue
}
