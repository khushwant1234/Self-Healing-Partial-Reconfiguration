@echo off
rem One-command unattended build on the Windows Vivado machine.
rem   scripts\run.bat m0
rem Clone the repo to a SHORT root (e.g. C:\dfx\sh) -- see docs\BUILD_PLAN.md.
setlocal
set TARGET=%1
if "%TARGET%"=="" set TARGET=m0
pushd "%~dp0.."

set TCL=vivado\%TARGET%\build_%TARGET%.tcl
if not exist "%TCL%" (
  echo No build script %TCL%
  popd & exit /b 2
)

where vivado >nul 2>nul
if errorlevel 1 (
  if exist C:\Xilinx\Vivado\2020.2\settings64.bat (
    call C:\Xilinx\Vivado\2020.2\settings64.bat
  ) else (
    echo ERROR: vivado not on PATH and C:\Xilinx\Vivado\2020.2\settings64.bat not found.
    popd & exit /b 2
  )
)

if not exist build\logs mkdir build\logs
if not exist reports\%TARGET% mkdir reports\%TARGET%

call vivado -mode batch -notrace -source %TCL% -log build\logs\%TARGET%_vivado.log -journal build\logs\%TARGET%_vivado.jou
set RC=%ERRORLEVEL%
copy /Y build\logs\%TARGET%_vivado.log reports\%TARGET%\vivado.log >nul 2>nul

echo.
echo ================ %TARGET%: vivado exit code %RC% ================
if exist reports\%TARGET%\SUMMARY.txt (
  type reports\%TARGET%\SUMMARY.txt
) else (
  echo ^(no SUMMARY.txt -- Vivado died before writing it; see reports\%TARGET%\vivado.log^)
)
echo.
echo Now push the results:
echo   git add bitstreams/%TARGET% reports/%TARGET%
echo   git commit -m "%TARGET% build results (rc=%RC%)"
echo   git push
popd
exit /b %RC%
