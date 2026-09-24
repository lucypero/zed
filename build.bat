@echo off
setlocal

rem Release build of Zed for Windows, laid out the way the official installer
rem lays it out.
rem
rem Usage:
rem   build.bat [--ultra] [cargo arguments...]
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
rem --ultra: ultra optimized build
rem   Slower to build, faster to run, and only runs on this machine's CPU (or
rem   one with the same instruction set extensions). It builds into its own
rem   profile, target\release-ultra, so it never invalidates the normal release
rem   build's cache and the two can sit side by side. On top of `release` it:
rem     - uses fat LTO instead of thin LTO, so the whole program is optimized
rem       as one unit (inlining across crates, dead code removal);
rem     - builds the zed crate with codegen-units=1 instead of 16;
rem     - compiles with -C target-cpu=native, so the compiler can use every
rem       instruction set extension this CPU has (AVX2 and so on);
rem     - swaps the global allocator for mimalloc (the zed/mimalloc feature),
rem       which is faster than the Windows heap for Zed's many small allocations.
rem   Expect the final link to take much longer than a normal release build and
rem   to need a lot of RAM (budget 16 GB or more). Nothing here changes Zed's
rem   behavior, so if something breaks only in this build, suspect mimalloc or
rem   target-cpu first.
rem
rem Any other arguments are forwarded to cargo, e.g. `build.bat --locked` or
rem `build.bat --ultra --locked`.

pushd "%~dp0" || exit /b 1

set "ULTRA="
set "CARGO_ARGS="
:parseargs
if "%~1"=="" goto :argsparsed
if /i "%~1"=="--ultra" (
    set "ULTRA=1"
) else (
    set CARGO_ARGS=%CARGO_ARGS% %1
)
shift
goto :parseargs
:argsparsed

if "%CARGO_TARGET_DIR%"=="" (
    set "TARGET_DIR=%CD%\target"
) else (
    set "TARGET_DIR=%CARGO_TARGET_DIR%"
)

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

rem The channel is baked in at compile time. crates/zed/RELEASE_CHANNEL says
rem `dev`, and a dev build skips the single-instance mutex and named pipe, so
rem the launcher can never hand files to a running Zed and every `zed <path>`
rem opens a fresh process and window. Nightly keeps that handoff working while
rem using its own mutex/pipe names, so it can't collide with an installed stable
rem Zed. Set ZED_RELEASE_CHANNEL yourself to override.
if "%ZED_RELEASE_CHANNEL%"=="" set "ZED_RELEASE_CHANNEL=nightly"

if defined ULTRA goto :ultrabuild

set "OUT=%TARGET_DIR%\release"
echo Building zed and cli in release (%ZED_RELEASE_CHANNEL% channel)...
cargo build --release --package zed --package cli %CARGO_ARGS%
goto :built

:ultrabuild
rem The release-ultra profile is defined here with --config rather than in
rem Cargo.toml, so this script is the only thing that knows about it. The
rem rustflags entry is joined with the ones .cargo/config.toml already sets for
rem Windows (crt-static and friends) rather than replacing them, which setting
rem RUSTFLAGS would do.
set "OUT=%TARGET_DIR%\release-ultra"
echo Building zed and cli ultra optimized (%ZED_RELEASE_CHANNEL% channel)...
echo This takes much longer than a normal release build, mostly in the final link.
cargo build --profile release-ultra --package zed --package cli ^
    --features zed/mimalloc ^
    --config "profile.release-ultra.inherits='release'" ^
    --config "profile.release-ultra.lto='fat'" ^
    --config "profile.release-ultra.codegen-units=1" ^
    --config "profile.release-ultra.package.zed.codegen-units=1" ^
    --config "target.'cfg(windows)'.rustflags=['-Ctarget-cpu=native']" ^
    %CARGO_ARGS%

:built
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
