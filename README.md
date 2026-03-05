# Lorealis 

# 1. Clear cache
Remove-Item -Recurse -Force build
# 2. Configure
cmake -B build -G "Visual Studio 16 2019" -DPLATFORM_DESKTOP=ON
# 3. Build
cmake --build build --config Release


cmake -B build -DMPV_DIR="e:/Works/Projects/ns-chat/extern/mpv-dev" . 
cmake --build build --config Release

"C:\Program Files\CMake\bin\cmake.exe" -B build -G "Visual Studio 16 2019" -DPLATFORM_DESKTOP=ON
"C:\Program Files\CMake\bin\cmake.exe" --build build --config Release

## Docker Build (Nintendo Switch)

### PowerShell
```powershell
docker run --rm -v "${PWD}:/data" devkitpro/devkita64:20260219 bash -c "/data/build_switch.sh"
```

### CMD
```cmd
docker run --rm -v "%cd%:/data" devkitpro/devkita64:20251117 bash -c "/data/build_switch.sh"


# copy to ns
docker run --rm -it -v E:\Works\Projects\ns-chat\build_switch:/work devkitpro/devkita64:20260219 bash
/opt/devkitpro/tools/bin/nxlink -a 192.168.31.91 /work/NS_Finder.nro

/brls.log
01	BRLS: Application main() entered
02  BRLS: CRASH - std::exception: filesystem error:status:No such device [romfs:/i18n/en-US]
03  BRLS: Application main()  exiting normally 
```
