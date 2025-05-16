#!/bin/bash

DATA_FILE=""
SCRIPT_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            echo "Generate flamegraph from perf.data or perf.script"
	    echo "./gen-flamegraph.sh perf.data"
	    echo "./gen-flamegraph.sh perf.data --vmlinux vmlinux"
	    echo "./gen-flamegraph.sh perf.data --kallsyms kallsyms"
	    echo "./gen-flamegraph.sh --script perf.script"
            exit 0
            ;;
        --script)
            SCRIPT_FILE="$2"
            shift 2
            ;;
        *)
            DATA_FILE="${@:1}"
            break
            ;;
    esac
done

echo $DATA_FILE
echo $SCRIPT_FILE

set -x
if [[ -z "$SCRIPT_FILE" ]]; then
    perf script -i $DATA_FILE -f > out/perf.script
    SCRIPT_FILE="perf.script"
fi
../thirdparty/flamegraph/stackcollapse-perf.pl out/$SCRIPT_FILE > out/perf.script.folded
../thirdparty/flamegraph/flamegraph.pl out/perf.script.folded > out/flamegraph.svg
../thirdparty/flamegraph/flamegraph.pl out/perf.script.folded --reverse > out/flamegraph-reverse.svg
