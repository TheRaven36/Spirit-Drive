@echo off
setlocal
cd /d "%~dp0"

echo [Spirit Drive] Hole aktuellen Stand von Robin-Branch ...
git pull --ff-only
if errorlevel 1 call "%~dp0tools\fix_uid_conflicts.bat"
if errorlevel 1 (
    echo.
    echo [Spirit Drive] git pull fehlgeschlagen. Lokale Aenderungen im Klon? Bitte nichts von Hand aendern.
    pause
    exit /b 1
)

set "GODOT_EXE="
if exist "godot_path.local" set /p GODOT_EXE=<"godot_path.local"
if not defined GODOT_EXE (
    echo.
    echo Pfad zur Godot-EXE eingeben, z.B. C:\Tools\Godot\Godot_v4.7-stable_win64.exe
    set /p GODOT_EXE=Pfad: 
)
set "GODOT_EXE=%GODOT_EXE:"=%"
if not exist "%GODOT_EXE%" (
    echo [Spirit Drive] Godot nicht gefunden: "%GODOT_EXE%"
    if exist "godot_path.local" del "godot_path.local"
    pause
    exit /b 1
)
> "godot_path.local" echo %GODOT_EXE%

if /i "%~1"=="play" (
    start "" "%GODOT_EXE%" --path "%~dp0."
) else (
    start "" "%GODOT_EXE%" --editor --path "%~dp0."
)
endlocal
