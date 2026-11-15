@echo off
rem Loest den haeufigsten Pull-Konflikt automatisch: Godot hat lokal eine
rem .uid-Datei erzeugt, die inzwischen auch im Repo liegt. Nur solche
rem Dateien werden entfernt - alles andere bleibt unangetastet.
setlocal EnableDelayedExpansion
cd /d "%~dp0.."
set "FIXED=0"
for /f "delims=" %%F in ('git ls-files --others --exclude-standard -- "*.uid"') do (
    git cat-file -e "@{u}:%%F" 2>nul
    if not errorlevel 1 (
        set "P=%%F"
        del /q "!P:/=\!"
        echo   Godot-Cache ersetzt: %%F
        set "FIXED=1"
    )
)
if "!FIXED!"=="0" exit /b 1
git merge --ff-only @{u}
exit /b !errorlevel!
