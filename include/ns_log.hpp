#pragma once

#include <cstdio>
#include <cstdarg>

// Global logging function: writes to console + SD card (Switch) or console (Desktop)
inline void NS_LOG(const char* format, ...) {
    char buffer[512];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);

    // 1. Console
    printf("%s\n", buffer);
    fflush(stdout);

#ifdef __SWITCH__
    // 2. SD Card
    FILE* f = fopen("sdmc:/brls.log", "a");
    if (f) {
        fprintf(f, "%s\n", buffer);
        fclose(f);
    }
#endif
}
