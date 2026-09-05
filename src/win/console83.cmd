@echo off
chcp 65001 >nul
rem Administration console for the 8.3 cluster (32-bit snap-in, ARM Windows).
rem Registration is shared between 8.3/8.5: before launch we check that it
rem points to our version; if not - switch it (admin required). Both consoles
rem can be kept open at the same time - the version is fixed in memory when
rem mmc starts.
rem rac analogue: rac83 in PATH.
setlocal
set "BIN=C:\Program Files (x86)\1cv8\8.3.27.2325\bin"
set "MSC=C:\Program Files (x86)\1cv8\common\1CV8 Servers 8.3.msc"
set "KEY=HKLM\SOFTWARE\Classes\Wow6432Node\CLSID\{C08A0F38-EFA5-4F60-8D4B-5D7709056530}\InprocServer32"
reg query "%KEY%" /ve | find "%BIN%" >nul && goto run
C:\Windows\SysWOW64\regsvr32.exe /s "%BIN%\radmin.dll"
reg query "%KEY%" /ve | find "%BIN%" >nul && goto run
echo [ОШИБКА] Не удалось переключить оснастку на 8.3 (нужны права администратора).
echo Запусти ярлык правой кнопкой - "Запуск от имени администратора".
pause
exit /b 1
:run
start "" C:\Windows\SysWOW64\mmc.exe "%MSC%"
