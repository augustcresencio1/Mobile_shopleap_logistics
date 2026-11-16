$php = "C:\Users\PC\AppData\Local\Microsoft\WinGet\Packages\PHP.PHP.8.4_Microsoft.Winget.Source_8wekyb3d8bbwe"
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools"
$env:Path = "$php;$adb;" + $env:Path

adb reverse tcp:8000 tcp:8000
php artisan serve
