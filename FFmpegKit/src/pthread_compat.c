/*
 * Copyright (c) 2025 Akash Patel
 *
 * This file is part of FFmpegKit.
 *
 * FFmpegKit is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * FFmpegKit is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with FFmpegKit.  If not, see <http://www.gnu.org/licenses/>.
 */

#if defined(_WIN32) && !defined(__MINGW32__)
#include <windows.h>
#include <pthread.h>
#include <time.h>

/**
 * Neutralize the system definitions to avoid redefinition errors.
 * We rely on the types provided by <sys/timeb.h> and <time.h>.
 */

#ifndef WINPTHREAD_NANOSLEEP_DECL
int __cdecl nanosleep(const struct timespec *req, struct timespec *rem) {
    Sleep((unsigned long)(req->tv_sec * 1000 + req->tv_nsec / 1000000));
    if (rem) { rem->tv_sec = 0; rem->tv_nsec = 0; }
    return 0;
}
#endif

#ifndef WINPTHREAD_CLOCK_DECL
int __cdecl clock_gettime(clockid_t clk_id, struct timespec *tp) {
    FILETIME ft;
    unsigned __int64 val;
    GetSystemTimeAsFileTime(&ft);
    val = ((unsigned __int64)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    val -= 116444736000000000ULL;
    tp->tv_sec = (long long)(val / 10000000ULL);
    tp->tv_nsec = (long long)((val % 10000000ULL) * 100);
    return 0;
}
#endif

/**
 * 64-bit redirection for MinGW 15+ 
 * We use the system's struct _timespec64 and __cdecl to match the header declarations.
 */

int __cdecl nanosleep64(const struct _timespec64 *req, struct _timespec64 *rem) {
    Sleep((unsigned long)(req->tv_sec * 1000 + req->tv_nsec / 1000000));
    if (rem) { rem->tv_sec = 0; rem->tv_nsec = 0; }
    return 0;
}

int __cdecl clock_gettime64(clockid_t clk_id, struct _timespec64 *tp) {
    FILETIME ft;
    unsigned __int64 val;
    GetSystemTimeAsFileTime(&ft);
    val = ((unsigned __int64)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    val -= 116444736000000000ULL;
    tp->tv_sec = (long long)(val / 10000000ULL);
    tp->tv_nsec = (long long)((val % 10000000ULL) * 100);
    return 0;
}

int __cdecl pthread_cond_timedwait64(pthread_cond_t *cond, pthread_mutex_t *mutex, const struct _timespec64 *abstime) {
    struct timespec ts;
    ts.tv_sec = (long)abstime->tv_sec;
    ts.tv_nsec = (long)abstime->tv_nsec;
    return pthread_cond_timedwait(cond, mutex, &ts);
}

int __cdecl pthread_cond_timedwait64_relative_np(pthread_cond_t *cond, pthread_mutex_t *mutex, const struct _timespec64 *reltime) {
    struct _timespec64 now;
    struct timespec ts;
    
    // 1. Get current time
    clock_gettime64(0, &now); // 0 = CLOCK_REALTIME
    
    // 2. Add relative offset
    ts.tv_sec = (long)(now.tv_sec + reltime->tv_sec);
    ts.tv_nsec = (long)(now.tv_nsec + reltime->tv_nsec);
    
    // 3. Handle nanosecond overflow
    if (ts.tv_nsec >= 1000000000L) {
        ts.tv_sec++;
        ts.tv_nsec -= 1000000000L;
    }

    return pthread_cond_timedwait(cond, mutex, &ts);
}
#endif
