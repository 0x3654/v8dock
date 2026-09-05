@echo off
rem Shared between the mac and Windows: base list (ibases.v8i), conf.cfg, templates.
rem The common store lives on the mac: ~/.1c-storage/. In Windows it is visible
rem as the SHARE \\Mac\1C (drive X:, the share is set up on the mac with the
rem prlctl --shf-host-add 1C rule).
rem ATTENTION: only \\Mac\1C! The target \\Mac\Home\1C is BROKEN: \\Mac\Home via
rem Parallels shares only the profile folders (Desktop/Documents/...),
rem everything else does not exist there. A symlink to a dead target = the
rem client launcher silently dies ~5 sec after start.
rem The STORE = master copy: the script never writes into it, only links.
rem Run: right-click "Run as administrator" (mklink needed; or enable developer
rem mode - then no admin required).
rem Before running: close the 1C client, the VM must see \\Mac\1C (Parallels Sharing).
rem The script is idempotent - safe to re-run.

setlocal
set STORE=\\Mac\1C
set CE=%APPDATA%\1C\1CEStart
set CV=%APPDATA%\1C\1cv8

if not exist "%STORE%\ibases.v8i" (
  echo [ERR] %STORE% недоступен - проверь Parallels Sharing (шара "1C" = ~/.1c-storage мака)
  exit /b 1
)

rem --- base list, point 1: the "1C:Enterprise" launcher (active on this machine) ---
rem IMPORTANT: a client started via the launcher reads the list from 1CEStart, NOT from 1cv8!
if not exist "%CE%" mkdir "%CE%"
if exist "%CE%\ibases.v8i.bak" del "%CE%\ibases.v8i.bak"
if exist "%CE%\ibases.v8i" ren "%CE%\ibases.v8i" ibases.v8i.bak
mklink "%CE%\ibases.v8i" "%STORE%\ibases.v8i" || goto :err

rem --- base list, point 2: the classic 1cv8.exe client (point it there too) ---
if exist "%CV%\ibases.v8i.bak" del "%CV%\ibases.v8i.bak"
if exist "%CV%\ibases.v8i" ren "%CV%\ibases.v8i" ibases.v8i.bak
mklink "%CV%\ibases.v8i" "%STORE%\ibases.v8i" || goto :err

rem --- conf.cfg (SystemLanguage etc.); the platform profile always lives in 1cv8 ---
if not exist "%CV%\conf" mkdir "%CV%\conf"
if exist "%CV%\conf\conf.cfg.bak" del "%CV%\conf\conf.cfg.bak"
if exist "%CV%\conf\conf.cfg" ren "%CV%\conf\conf.cfg" conf.cfg.bak
mklink "%CV%\conf\conf.cfg" "%STORE%\conf.cfg" || goto :err

rem --- templates: the store already exists, the local tmplts goes to archive ---
if exist "%CV%\tmplts.bak" rmdir /s /q "%CV%\tmplts.bak"
if exist "%CV%\tmplts" ren "%CV%\tmplts" tmplts.bak
mklink /D "%CV%\tmplts" "%STORE%\tmplts" || goto :err

echo OK: ibases.v8i (1CEStart + 1cv8), conf.cfg, tmplts теперь общие с маком.
echo Старые копии лежат рядом как *.bak
pause
exit /b 0

:err
echo [ERR] mklink не удался - скрипт нужно запускать от администратора
pause
exit /b 1
