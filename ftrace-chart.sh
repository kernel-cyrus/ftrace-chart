#!/bin/bash
set -e

# Help
if [ -z "$1" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then

    echo ""
    echo "ftrace-chart"
    echo "=========================="
    echo "Generate plantuml chart for function-graph trace"
    echo ""
    echo "Format:"
    echo "  ./ftrace-chart.sh [record|report] [options]"
    echo ""
    echo "Options"
    echo "  -h, --help                  Help"
    echo "  -m, --mode=[trace|stack]    \"trace\" is function-graph chart (excution flow of the function)"
    echo "                              \"stack\" is stacktrace chart (where has the function been called)"
    echo "  -f, --function              Function to track"
    echo "  -t, --timeout               Seconds to trace, you can stop mannully without passing this param."
    echo "  -o, --outdir                Directory to save trace data and chart files."
    echo ""
    echo "Examples:"
    echo "  1. Record function-graph trace of schedule()"
    echo "  $ ./ftrace-chart.sh record --mode=trace --function=schedule --timeout=10"
    echo ""
    echo "  2. Generate plantuml(.puml) files of the trace"
    echo "  $ ./ftrace-chart.sh report ./ftrace-chart.data/trace.txt"
    echo ""
    echo "  3. Generate svg image for plantuml"
    echo "  $ java -jar plantuml-mit.jar -tsvg ./ftrace-chart.data/schedule~1.puml"
    echo ""

# Record Mode
elif [ "$1" == "record" ]; then

    # Aarsing arguments
    shift
    for i in "$@"; do
        case $i in
            -m=*|--mode=*)
                MODE="${i#*=}"
                shift # past argument=value
                ;;
            -f=*|--function=*)
                FUNC="${i#*=}"
                shift # past argument=value
                ;;
            -t=*|--timeout=*)
                TIME="${i#*=}"
                shift # past argument=value
                ;;
            -o=*|--outdir=*)
                OUT_DIR="${i#*=}"
                shift # past argument=value
                ;;
            *)
                echo "Invalid argument: ${i#*=}, please check your input."
                exit 0
                ;;
        esac
    done

    # Check arguments
    if [ -z "$MODE" ]; then
        echo "Please pass the record mode: --mode=[trace|stack]"
        exit 0
    fi
    
    if [ -z "$FUNC" ]; then
        echo "Please pass the record function: --function=<function_name>"
        exit 0
    fi

    if [ -z "$OUT_DIR" ]; then
        OUT_DIR="./ftrace-chart.data"
    fi

    OUT_FILE="$OUT_DIR/trace.txt"

    mkdir -p $OUT_DIR

    # Record Trace Mode
    if [ "$MODE" == "trace" ]; then
        
        echo "Setting up ftrace..."
        echo 0 > /sys/kernel/debug/tracing/tracing_on
        echo function_graph > /sys/kernel/debug/tracing/current_tracer
        echo > /sys/kernel/debug/tracing/trace
        echo > /sys/kernel/debug/tracing/set_graph_function
        echo "$FUNC" > /sys/kernel/debug/tracing/set_graph_function
        echo "Start tracing..."
        echo 1 > /sys/kernel/debug/tracing/tracing_on
        set +e
        if [ -z "$TIME" ]; then
            trap 'echo ""' SIGINT
            echo "Press CTRL+C to stop..."
            cat /sys/kernel/debug/tracing/trace_pipe > $OUT_FILE
        else
            echo "Wait $TIME seconds..."
            timeout $TIME cat /sys/kernel/debug/tracing/trace_pipe > $OUT_FILE
        fi
        set -e
        echo "Stop tracing..."
        echo 0 > /sys/kernel/debug/tracing/tracing_on
        echo "Done. ($OUT_FILE)"

    # Record Stack Mode
    elif [ "$MODE" == "stack" ]; then
        echo "FIXME: not implement yet."
    # Invalid
    else
        echo "ERROR: Invalid record mode. --mode=[trace|stack]"
    fi

# Other Modes
else

    python3 main.py "$@"

fi

set +e