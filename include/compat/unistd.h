#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#ifdef _WIN32
#include <io.h>
#include <process.h>

// POSIX access constants
#define F_OK 0
#define W_OK 2
#define R_OK 4
#define X_OK 0 // Not supported on Windows, mapping to 0

// Some common POSIX types and functions if needed
#define srandom srand
#define random rand

#endif
