@echo off
setlocal
set "ROOT=%~dp0"
set "SOURCE=%ROOT%driver-probe.c"
set "EXE=%ROOT%driverProbe.exe"
set "REPORT=%ROOT%driver-probe-report.txt"
set "CC="
set "CC_DIR="
for %%C in (clang.exe gcc.exe) do if not defined CC (where %%C >nul 2>&1 && set "CC=%%C")
if not defined CC if exist "C:\msys64\mingw64\bin\gcc.exe" set "CC=C:\msys64\mingw64\bin\gcc.exe"
if not defined CC if exist "C:\msys64\ucrt64\bin\gcc.exe" set "CC=C:\msys64\ucrt64\bin\gcc.exe"
if not defined CC if exist "C:\mingw64\bin\gcc.exe" set "CC=C:\mingw64\bin\gcc.exe"
if not defined CC if exist "C:\Program Files\LLVM\bin\clang.exe" set "CC=C:\Program Files\LLVM\bin\clang.exe"
if not defined CC (
    echo No open-source C compiler found.
    echo Install MSYS2 MinGW-w64, then run this file again.
    pause
    exit /b 3
)
for %%F in ("%CC%") do set "CC_DIR=%%~dpF"
set "PATH=%CC_DIR%;%PATH%"
set "SELF=%~f0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$self=$env:SELF; $out=$env:SOURCE; $begin='### BEGIN DRIVER '+'SOURCE ###'; $finish='### END DRIVER '+'SOURCE ###'; $lines=[System.IO.File]::ReadAllLines($self); $start=[Array]::IndexOf($lines,$begin); $end=[Array]::IndexOf($lines,$finish); if($start -lt 0 -or $end -le $start){throw 'Embedded C source markers were not found.'}; $source=$lines[($start+1)..($end-1)] -join [Environment]::NewLine; [System.IO.File]::WriteAllText($out,$source,(New-Object System.Text.UTF8Encoding($false)))"
if errorlevel 1 (echo Could not extract embedded C source.&pause&exit /b 2)
echo Building Driver API probe with "%CC%"...
"%CC%" -O2 -static-libgcc -static-libstdc++ -o "%EXE%" "%SOURCE%" > "%REPORT%" 2>&1
if errorlevel 1 (type "%REPORT%"&pause&exit /b 4)
echo Running Driver API probe...
"%EXE%" >> "%REPORT%" 2>&1
set "RC=%ERRORLEVEL%"
type "%REPORT%"
echo Report: "%REPORT%"
pause
exit /b %RC%

### BEGIN DRIVER SOURCE ###
#include <windows.h>
#include <stdio.h>
#include <stddef.h>
typedef int CUresult; typedef int CUdevice;
typedef CUresult (__cdecl *cuInit_t)(unsigned int); typedef CUresult (__cdecl *cuDeviceGetCount_t)(int*); typedef CUresult (__cdecl *cuDeviceGet_t)(CUdevice*,int); typedef CUresult (__cdecl *cuDeviceGetName_t)(char*,int,CUdevice); typedef CUresult (__cdecl *cuDeviceComputeCapability_t)(int*,int*,CUdevice); typedef CUresult (__cdecl *cuDeviceTotalMem_t)(size_t*,CUdevice); typedef CUresult (__cdecl *cuMemGetInfo_t)(size_t*,size_t*); typedef const char* (__cdecl *cuGetErrorString_t)(CUresult);
static int fail(const char* op, CUresult r, cuGetErrorString_t text) { fprintf(stderr,"%s failed: %s (%d)\n",op,text?text(r):"unknown",r); return 2; }
int main(void) {
 HMODULE dll=LoadLibraryA("nvcuda.dll"); if(!dll){fprintf(stderr,"nvcuda.dll load failed: %lu\n",(unsigned long)GetLastError());return 2;}
 cuInit_t init=(cuInit_t)GetProcAddress(dll,"cuInit"); cuDeviceGetCount_t countfn=(cuDeviceGetCount_t)GetProcAddress(dll,"cuDeviceGetCount"); cuDeviceGet_t get=(cuDeviceGet_t)GetProcAddress(dll,"cuDeviceGet"); cuDeviceGetName_t namefn=(cuDeviceGetName_t)GetProcAddress(dll,"cuDeviceGetName"); cuDeviceComputeCapability_t cap=(cuDeviceComputeCapability_t)GetProcAddress(dll,"cuDeviceComputeCapability"); cuDeviceTotalMem_t totalfn=(cuDeviceTotalMem_t)GetProcAddress(dll,"cuDeviceTotalMem_v2"); if(!totalfn) totalfn=(cuDeviceTotalMem_t)GetProcAddress(dll,"cuDeviceTotalMem"); cuMemGetInfo_t memfn=(cuMemGetInfo_t)GetProcAddress(dll,"cuMemGetInfo_v2"); if(!memfn) memfn=(cuMemGetInfo_t)GetProcAddress(dll,"cuMemGetInfo"); cuGetErrorString_t err=(cuGetErrorString_t)GetProcAddress(dll,"cuGetErrorString");
 if(!init||!countfn||!get||!namefn||!cap||!totalfn||!memfn){fprintf(stderr,"Required CUDA Driver API export missing.\n");return 3;} CUresult r=init(0);if(r)return fail("cuInit",r,err);int count=0;r=countfn(&count);if(r)return fail("cuDeviceGetCount",r,err);printf("CUDA device count: %d\n",count);
 for(int i=0;i<count;++i){CUdevice d;char name[256]={0};int major=0,minor=0;size_t total=0,freeb=0,infototal=0;r=get(&d,i);if(r)return fail("cuDeviceGet",r,err);r=namefn(name,256,d);if(r)return fail("cuDeviceGetName",r,err);r=cap(&major,&minor,d);if(r)return fail("cuDeviceComputeCapability",r,err);r=totalfn(&total,d);if(r)return fail("cuDeviceTotalMem",r,err);r=memfn(&freeb,&infototal);if(r)return fail("cuMemGetInfo",r,err);printf("Device %d name: %s\nDevice %d compute capability: %d.%d\nDevice %d totalGlobalMemBytes: %llu\nDevice %d freeMemBytes: %llu\nDevice %d memInfoTotalBytes: %llu\n",i,name,i,major,minor,i,(unsigned long long)total,i,(unsigned long long)freeb,i,(unsigned long long)infototal);}
 printf("Driver API probe completed. No deliberate device allocation was performed.\n");FreeLibrary(dll);return 0;
}
### END DRIVER SOURCE ###
