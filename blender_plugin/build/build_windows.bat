@echo off
REM Build instantmeshes-cli for Windows x86_64
REM Requires: Visual Studio 2019+ or MinGW-w64 with CMake

set PROJECT_ROOT=%~dp0..\..
set BUILD_DIR=%PROJECT_ROOT%\build_windows

echo === Building instantmeshes-cli for Windows x86_64 ===

if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%"

cmake -S "%PROJECT_ROOT%" -B "%BUILD_DIR%" ^
  -DCMAKE_BUILD_TYPE=Release ^
  -G "Visual Studio 17 2022" ^
  -A x64 ^
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5

cmake --build "%BUILD_DIR%" --target instantmeshes-cli --config Release -j

mkdir "%PROJECT_ROOT%\release" 2>nul
copy /Y "%BUILD_DIR%\Release\instantmeshes-cli.exe" "%PROJECT_ROOT%\release\instantmeshes-cli-windows-x86_64.exe"

echo Done: %PROJECT_ROOT%\release\instantmeshes-cli-windows-x86_64.exe
