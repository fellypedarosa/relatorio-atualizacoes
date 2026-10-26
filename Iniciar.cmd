@echo off
setlocal
set "REPORT_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "REPORT_POWERSHELL=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%REPORT_POWERSHELL%" -NoLogo -NoProfile -File "%~dp0Principal.ps1" %*
set "REPORT_EXIT=%ERRORLEVEL%"
echo.
echo Codigo de saida: %REPORT_EXIT% ^(0=completo, 2=parcial, 1=falha^).
exit /b %REPORT_EXIT%
