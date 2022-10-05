@echo off

echo Start build...
if EXIST build del /Q build\*.*
if NOT EXIST build mkdir build

echo Assembling code...
bin\vasmarm_std_win32.exe -L build\compile.txt -m250 -Fbin -opt-adr -o build\shrinkler.bin main.asm

if %ERRORLEVEL% neq 0 (
	echo Failed to assemble code.
	exit /b 1
)

echo Copying files...
set HOSTFS=..\..\Arculator_V2.1_Windows\hostfs
copy build\shrinkler.bin "%HOSTFS%\shrinkler,ff8"
