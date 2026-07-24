# 既に CursorTrigger.hta が起動していれば exit 1、なければ exit 0
# ("HTML Application Host Window Class" かつ タイトルが一致するウィンドウを EnumWindows で数える。
#  FindWindow は先頭1件しか取れないため、多重起動の検知には使えない)

param(
    [string]$title = "HTALauncherCursorTrigger"
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class Win32Guard {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
}
"@

$script:count = 0

$callback = {
    param($hWnd, $lParam)
    $cls = New-Object System.Text.StringBuilder 256
    [Win32Guard]::GetClassName($hWnd, $cls, 256) | Out-Null
    if ($cls.ToString() -eq "HTML Application Host Window Class") {
        $txt = New-Object System.Text.StringBuilder 256
        [Win32Guard]::GetWindowText($hWnd, $txt, 256) | Out-Null
        if ($txt.ToString() -eq $title) {
            $script:count++
        }
    }
    return $true
}

[Win32Guard]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null

if ($script:count -gt 1) { exit 1 } else { exit 0 }
