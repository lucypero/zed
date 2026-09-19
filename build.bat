@echo off
setlocal

rem Release build of Zed for Windows, laid out the way the official installer
rem lays it out.
rem
rem Produces:
rem   target\release\zed.exe      the editor itself; built without debug_assertions
rem                               it links as a GUI-subsystem binary (see the
rem                               windows_subsystem attribute in crates/zed/src/main.rs)
rem   target\release\bin\zed.exe  the launcher, a copy of crates/cli's cli.exe; it
rem                               spawns the editor detached and exits immediately,
rem                               so invoking it never blocks your terminal
rem
rem This mirrors script/bundle-windows.ps1, which builds the same two crates and
rem installs cli.exe as bin\zed.exe with bin\ on PATH.
rem
rem Any extra arguments are forwarded to cargo, e.g. `build.bat --locked`.

pushd "%~dp0" || exit /b 1

if "%CARGO_TARGET_DIR%"=="" (
    set "TARGET_DIR=%CD%\target"
) else (
    set "TARGET_DIR=%CARGO_TARGET_DIR%"
)
set "OUT=%TARGET_DIR%\release"

rem Git for Windows ships a coreutils `link` in usr\bin. If it shadows MSVC's
rem link.exe the build dies on every build script with "extra operand ... .rcgu.o".
for /f "delims=" %%L in ('where link.exe 2^>nul') do (
    echo %%L| find /i "\usr\bin\" >nul
    if not errorlevel 1 (
        echo [warn] link.exe resolves to %%L
        echo [warn] That is Git's coreutils link, not the MSVC linker, and the
        echo [warn] build will fail. Drop Git's usr\bin from PATH in this shell.
        echo.
    )
    goto :linkchecked
)
:linkchecked

echo Building zed and cli in release...
cargo build --release --package zed --package cli %*
if errorlevel 1 (
    echo.
    echo Build failed.
    popd
    exit /b 1
)

if not exist "%OUT%\bin" mkdir "%OUT%\bin"
copy /y "%OUT%\cli.exe" "%OUT%\bin\zed.exe" >nul
if errorlevel 1 (
    echo Could not stage the launcher into %OUT%\bin.
    popd
    exit /b 1
)

echo.
echo Done.
echo   editor:   %OUT%\zed.exe
echo   launcher: %OUT%\bin\zed.exe
echo.
echo Put this directory on PATH, ahead of any installed Zed, and `zed .` will
echo behave exactly like the downloaded build:
echo   %OUT%\bin

popd
endlocal
