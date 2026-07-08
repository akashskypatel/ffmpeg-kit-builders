#!/usr/bin/env bash

if (( BASH_VERSINFO[0] < 5 )); then
    for bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$bash" ]]; then
            exec "$bash" "$0" "$@"
        fi
    done

    echo "GNU Bash 5+ is required." >&2
    exit 1
fi

# Run this on the clean, unpatched src/ directory
# Command to find functional calls that are dangerous in global scope
(grep -Enw 'getenv|setenv|putenv|chdir|setlocale|signal|sigaction|av_log_set_callback' src/*.c src/*.h) > audit_func.log 2>&1
# Command to find global variables that are not const
(clang-query -p build/ src/*.c -c "set output dump" -c "m varDecl(allOf(hasGlobalStorage(), isDefinition(), unless(isStaticStorageClass()), unless(hasType(isConstQualified()))))" 2>/dev/null | grep "^VarDecl" | grep "src/") > audit_vars.log 2>&1
# Command to find extern variables that are not const
(clang-query -p build/ src/*.c -c "set output dump" -c "m varDecl(allOf(hasGlobalStorage(), unless(isStaticStorageClass()), unless(hasType(isConstQualified()))))" 2>/dev/null | grep "^VarDecl" | grep "src/") > audit_extern.log 2>&1
# Command to find static variables that are not const
(clang-query -p build/ src/*.c -c "set output dump" -c "m varDecl(allOf(isStaticStorageClass(), unless(hasType(isConstQualified()))))" 2>/dev/null | grep -E "VarDecl|src/") > audit_static.log 2>&1
# Command to find global variables that are not const
(clang-tidy -p build/ src/*.[ch] -checks='-*,cppcoreguidelines-avoid-non-const-global-variables,bugprone-thread-safe-functions' -extra-arg="-Wno-unused-command-line-argument" 2>/dev/null | grep -E "warning:|src/") > audit_globals.log 2>&1
# Command to find global variables that have addresses taken
(clang-query -p build/ src/*.c --extra-arg="-Wno-everything" -c 'm declRefExpr(to(varDecl(hasGlobalStorage()).bind("problem_var")), hasAncestor(varDecl(hasGlobalStorage(), isDefinition())))') > audit_address.log 2>&1