@echo off
setlocal enabledelayedexpansion
title Roblox Protocol Handler Fix - version-f5a60436d48947d3

echo ===================================================
echo       Roblox URL Protocol Handler Fix
echo ===================================================
echo.

:: Target version set here:
set "TARGET_VER=version-ff002f610f964ac7"

echo Searching for Roblox version: %TARGET_VER% ...

set "EXE_PATH="

:: 1. Search in LocalAppData (Default installation path)
if exist "%LOCALAPPDATA%\Roblox\Versions\%TARGET_VER%\RobloxPlayerBeta.exe" (
    set "EXE_PATH=%LOCALAPPDATA%\Roblox\Versions\%TARGET_VER%\RobloxPlayerBeta.exe"
)

:: 2. Search in Program Files (x86)
if not defined EXE_PATH (
    if exist "%ProgramFiles(x86)%\Roblox\Versions\%TARGET_VER%\RobloxPlayerBeta.exe" (
        set "EXE_PATH=%ProgramFiles(x86)%\Roblox\Versions\%TARGET_VER%\RobloxPlayerBeta.exe"
    )
)

:: 3. Search in Program Files (64-bit)
if not defined EXE_PATH (
    if exist "%ProgramFiles%\Roblox\Versions\%TARGET_VER%\RobloxPlayerBeta.exe" (
        set "EXE_PATH=%ProgramFiles%\Roblox\Versions\%TARGET_VER%\RobloxPlayerBeta.exe"
    )
)

:: 4. Search in ProgramData
if not defined EXE_PATH (
    if exist "%ProgramData%\Roblox\Versions\%TARGET_VER%\RobloxPlayerBeta.exe" (
        set "EXE_PATH=%ProgramData%\Roblox\Versions\%TARGET_VER%\RobloxPlayerBeta.exe"
    )
)

:: Verify executable was found
if not defined EXE_PATH (
    echo.
    echo [ERROR] Could not find RobloxPlayerBeta.exe in version folder:
    echo "%TARGET_VER%"
    echo.
    echo Please verify that this version folder exists in your Roblox directory.
    echo.
    pause
    exit /b 1
)

echo [FOUND] Roblox executable:
echo "%EXE_PATH%"
echo.

echo Updating Windows Registry protocol handlers...

:: Register roblox-player protocol (Legacy web launch)
reg add "HKCU\Software\Classes\roblox-player" /ve /t REG_SZ /d "URL:Roblox Protocol" /f >nul
reg add "HKCU\Software\Classes\roblox-player" /v "URL Protocol" /t REG_SZ /d "" /f >nul
reg add "HKCU\Software\Classes\roblox-player\DefaultIcon" /ve /t REG_SZ /d "\"%EXE_PATH%\",0" /f >nul
reg add "HKCU\Software\Classes\roblox-player\shell\open\command" /ve /t REG_SZ /d "\"%EXE_PATH%\" \"%%1\"" /f >nul

:: Register roblox protocol (Universal deeplinks)
reg add "HKCU\Software\Classes\roblox" /ve /t REG_SZ /d "URL:Roblox Protocol" /f >nul
reg add "HKCU\Software\Classes\roblox" /v "URL Protocol" /t REG_SZ /d "" /f >nul
reg add "HKCU\Software\Classes\roblox\DefaultIcon" /ve /t REG_SZ /d "\"%EXE_PATH%\",0" /f >nul
reg add "HKCU\Software\Classes\roblox\shell\open\command" /ve /t REG_SZ /d "\"%EXE_PATH%\" \"%%1\"" /f >nul

if %errorlevel% equ 0 (
    echo.
    echo ===================================================
    echo [SUCCESS] Protocol handlers registered successfully!
    echo Roblox is now linked to: %TARGET_VER%
    echo ===================================================
) else (
    echo.
    echo [ERROR] Failed to write registry keys. Try running this script as Administrator.
)

echo.
pause
endlocal
