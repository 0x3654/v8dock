@echo off
chcp 65001 >nul
rem Administration console for the 8.5 cluster (32-bit snap-in, ARM Windows).
rem Mirror of console83. Administers ONLY the 8.5 cluster (server1c:2540):
rem the console and server versions must match. rac analogue: rac85 in PATH.
setlocal
set "BIN=C:\Program Files (x86)\1cv8\8.5.1.1522\bin"
set "MSC=C:\Program Files (x86)\1cv8\common\1CV8 Servers 8.5.msc"
set "KEY=HKLM\SOFTWARE\Classes\Wow6432Node\CLSID\{C08A0F38-EFA5-4F60-8D4B-5D7709056530}\InprocServer32"
reg query "%KEY%" /ve | find "%BIN%" >nul && goto run
C:\Windows\SysWOW64\regsvr32.exe /s "%BIN%\radmin.dll"
reg query "%KEY%" /ve | find "%BIN%" >nul && goto run
echo [ОШИБКА] Не удалось переключить оснастку на 8.5 (нужны права администратора).
echo Запусти ярлык правой кнопкой - "Запуск от имени администратора".
pause
exit /b 1
:run
start "" C:\Windows\SysWOW64\mmc.exe "%MSC%"
