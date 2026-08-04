@echo off
REM Build instantmeshes-cli for Windows x64 and package a platform-specific Blender addon.
REM Requires: Visual Studio 2022 + CMake

set "PROJECT_ROOT=%~dp0..\.."
set "BUILD_DIR=%PROJECT_ROOT%\build_windows"
set "ADDON_SRC=%PROJECT_ROOT%\instant_meshes"
set "RELEASE_DIR=%PROJECT_ROOT%\release"

echo === Building instantmeshes-cli for Windows x64 ===

if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%"
if exist "%RELEASE_DIR%" rmdir /s /q "%RELEASE_DIR%"
mkdir "%RELEASE_DIR%" 2>nul

cmake -S "%PROJECT_ROOT%" -B "%BUILD_DIR%" ^
  -DCMAKE_BUILD_TYPE=Release ^
  -G "Visual Studio 17 2022" ^
  -A x64 ^
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5

cmake --build "%BUILD_DIR%" --target instantmeshes-cli --config Release -j

:: Strip and copy CLI
copy /Y "%BUILD_DIR%\Release\instantmeshes-cli.exe" "%RELEASE_DIR%\instantmeshes-cli-windows-x86_64.exe"

echo --- Packaging Blender addon ---
set "ADDON_TMP=%TEMP%\im_addon_win"
if exist "%ADDON_TMP%" rmdir /s /q "%ADDON_TMP%"
mkdir "%ADDON_TMP%\instant_meshes\bin"
copy "%ADDON_SRC%\__init__.py" "%ADDON_TMP%\instant_meshes\"
copy "%ADDON_SRC%\operators.py" "%ADDON_TMP%\instant_meshes\"
copy "%ADDON_SRC%\panel.py" "%ADDON_TMP%\instant_meshes\"
copy "%ADDON_SRC%\preferences.py" "%ADDON_TMP%\instant_meshes\"
copy "%BUILD_DIR%\Release\instantmeshes-cli.exe" "%ADDON_TMP%\instant_meshes\bin\instantmeshes-cli.exe"

pushd "%ADDON_TMP%"
powershell Compress-Archive -Path instant_meshes -DestinationPath "%RELEASE_DIR%\instant-meshes-blender-windows.zip" -Force
popd

echo === Done ===
echo Standalone CLI: %RELEASE_DIR%\instantmeshes-cli-windows-x86_64.exe
echo Blender addon:   %RELEASE_DIR%\instant-meshes-blender-windows.zip
dir "%RELEASE_DIR%"
