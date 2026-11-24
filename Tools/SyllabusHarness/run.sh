#!/bin/bash
# Builds the real SyllabusReader into a Mac command-line tool and runs it.
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
SRC=../../SchedAI/Semester
mkdir -p .build
swiftc -O -o .build/harness main.swift $SRC/SyllabusReader.swift $SRC/SemesterModels.swift 2>&1 | grep -E "error" || true
.build/harness "${1:-syllabi}"
