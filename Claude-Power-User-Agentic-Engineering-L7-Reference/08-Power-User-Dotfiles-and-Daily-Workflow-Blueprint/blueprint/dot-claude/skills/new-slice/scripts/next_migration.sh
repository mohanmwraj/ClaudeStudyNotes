#!/usr/bin/env bash
ls "$1/src/main/resources/db/migration" | sed -E 's/^V([0-9]+)__.*/\1/' | sort -n | tail -1
