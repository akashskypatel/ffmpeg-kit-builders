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

#ifndef PTHREAD_COMPAT_H
#define PTHREAD_COMPAT_H

#if defined(_WIN32) && !defined(__MINGW32__)
#if defined(HAVE_STDINT_H)
#undef HAVE_STDINT_H
#endif
#define HAVE_STDINT_H 1

#if defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wundef"
#pragma GCC diagnostic ignored "-Wold-style-cast"
#endif

#include <pthread.h>
#include <time.h>

#if defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic pop
#endif

#ifdef __cplusplus
extern "C" {
#endif

int __cdecl pthread_cond_timedwait64_relative_np(pthread_cond_t *cond, pthread_mutex_t *mutex, const struct _timespec64 *reltime);
int __cdecl pthread_cond_timedwait64(pthread_cond_t *cond, pthread_mutex_t *mutex, const struct _timespec64 *abstime);
int __cdecl clock_gettime64(clockid_t clk_id, struct _timespec64 *tp);
int __cdecl nanosleep64(const struct _timespec64 *req, struct _timespec64 *rem);
int __cdecl clock_gettime(clockid_t clk_id, struct timespec *tp);
int __cdecl nanosleep(const struct timespec *req, struct timespec *rem);

#ifdef __cplusplus
}
#endif

#ifdef __cplusplus
#include <stdbool.h>
#include <cstdint>
#if __cplusplus >= 202002L
#include <compare>
#endif

extern "C++" {
    /**
     * Compatibility wrapper for pthreads-win32 where pthread_t is a struct.
     */
    struct pthread_t_compat : public pthread_t {
        // Default constructor
        pthread_t_compat() { p = nullptr; x = 0; }
        
        // Copy constructor from base pthreads-win32 struct
        pthread_t_compat(const pthread_t& t) { p = t.p; x = t.x; }
        
        // Fix for OpenCV: allows initialization from 0/NULL (posix_thread(0))
        pthread_t_compat(std::uintptr_t i) { p = reinterpret_cast<void*>(i); x = 0; }

        // Casting operators for pointer-based logic (OpenCV parallel.cpp)
        operator void*() const { return this->p; }
        operator size_t() const { return reinterpret_cast<size_t>(this->p); }
    };

    // GCC 15+ Comparisons
    inline bool operator==(const pthread_t& lhs, const pthread_t& rhs) {
        return lhs.p == rhs.p && lhs.x == rhs.x;
    }
    
    inline bool operator!=(const pthread_t& lhs, const pthread_t& rhs) {
        return !(lhs == rhs);
    }

    #if __cplusplus >= 202002L
        inline std::strong_ordering operator<=>(const pthread_t& lhs, const pthread_t& rhs) {
            if (lhs.p < rhs.p) return std::strong_ordering::less;
            if (lhs.p > rhs.p) return std::strong_ordering::greater;
            if (lhs.x < rhs.x) return std::strong_ordering::less;
            if (lhs.x > rhs.x) return std::strong_ordering::greater;
            return std::strong_ordering::equal;
        }
    #else
        inline bool operator<(const pthread_t& lhs, const pthread_t& rhs) {
            if (lhs.p < rhs.p) return true;
            if (lhs.p > rhs.p) return false;
            return lhs.x < rhs.x;
        }
    #endif
}

// Map the standard type and function to our compat wrapper
#define pthread_t pthread_t_compat

#undef pthread_self
#define pthread_self() pthread_t_compat((pthread_self)())

#endif

#endif // defined(_WIN32) && !defined(__MINGW32__)
#endif // PTHREAD_COMPAT_H
