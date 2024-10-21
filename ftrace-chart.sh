#!/bin/bash
set -e

start_trace() {
    TRACE_FILE=$1
    echo "$TRACE_FILE"
    echo "Start tracing..."
    echo 1 > /sys/kernel/debug/tracing/tracing_on
    set +e
    if [ -z "$TIME" ]; then
        trap 'echo ""' SIGINT
        echo "Press CTRL+C to stop..."
        cat /sys/kernel/debug/tracing/trace_pipe > $TRACE_FILE
    else
        echo "Wait $TIME seconds..."
        timeout $TIME cat /sys/kernel/debug/tracing/trace_pipe > $TRACE_FILE
    fi
    set -e
    echo "Stop tracing..."
    echo 0 > /sys/kernel/debug/tracing/tracing_on
}

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
    echo "Trace Mode Example"
    echo "---------------------"
    echo "  Generate chart of schedule() excution flow:"
    echo ""
    echo "  1. Record function-graph trace of schedule()"
    echo "  $ ./ftrace-chart.sh record --mode=trace --function=schedule --timeout=10"
    echo ""
    echo "  2. Generate plantuml(.puml) files of the trace"
    echo "  $ ./ftrace-chart.sh report --mode=trace ./ftrace-chart.data/trace.txt"
    echo ""
    echo "  3. Generate plantuml svg image"
    echo "  $ java -jar plantuml-mit.jar -tsvg ./ftrace-chart.data/schedule.puml"
    echo ""
    echo "Stack Mode Example"
    echo "---------------------"
    echo "  Generate chart of schedule() called positions:"
    echo ""
    echo "  1. Record stacktrace of schedule()"
    echo "  $ ./ftrace-chart.sh record --mode=stack --function=schedule --timeout=10"
    echo ""
    echo "  2. Generate plantuml(.puml) files of the trace"
    echo "  $ ./ftrace-chart.sh report --mode=stack ./ftrace-chart.data/trace.txt"
    echo ""
    echo "  3. Generate plantuml svg image"
    echo "  $ java -jar plantuml-mit.jar -tsvg ./ftrace-chart.data/schedule.puml"
    echo ""
    echo "Visit https://github.com/kernel-cyrus/ftrace-chart for more help."
    echo ""

# Record Mode
elif [ "$1" == "record" ]; then

    ARGS=("$@")

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

    # FIXME: add overwrite alert
    OUT_FILE="$OUT_DIR/trace.txt"

    mkdir -p $OUT_DIR

    if [ "$EUID" -ne 0 ]; then
        echo "Running as root."
        exec sudo "$0" "${ARGS[@]}"
    fi

    # Record Trace Mode
    if [ "$MODE" == "trace" ]; then
        
        echo "Setting up ftrace..."
        echo 0 > /sys/kernel/debug/tracing/tracing_on
        echo function_graph > /sys/kernel/debug/tracing/current_tracer
        echo > /sys/kernel/debug/tracing/trace
        echo > /sys/kernel/debug/tracing/set_graph_function
        echo "$FUNC" > /sys/kernel/debug/tracing/set_graph_function
        start_trace $OUT_FILE
        echo 0 > /sys/kernel/debug/tracing/tracing_on
        echo > /sys/kernel/debug/tracing/set_graph_function
        echo "Done. ($OUT_FILE)"

    # Record Stack Mode
    elif [ "$MODE" == "stack" ]; then

        echo "Setting up ftrace..."
        echo 0 > /sys/kernel/debug/tracing/tracing_on
        echo nop > /sys/kernel/debug/tracing/current_tracer
        echo > /sys/kernel/debug/tracing/trace
        if [ -d "/sys/kernel/debug/tracing/events/kprobes" ]; then
            echo 0 > /sys/kernel/debug/tracing/events/kprobes/enable
        fi
        echo > /sys/kernel/debug/tracing/kprobe_events
        echo "p:$FUNC $FUNC" > /sys/kernel/debug/tracing/kprobe_events
        echo 1 > /sys/kernel/debug/tracing/events/kprobes/enable
        echo 1 > /sys/kernel/debug/tracing/options/stacktrace
        start_trace $OUT_FILE
        echo 0 > /sys/kernel/debug/tracing/events/kprobes/enable
        echo 0 > /sys/kernel/debug/tracing/options/stacktrace
        echo > /sys/kernel/debug/tracing/kprobe_events
        echo "Done. ($OUT_FILE)"

    # Invalid
    else
        echo "ERROR: Invalid record mode: --mode=[trace|stack]"
    fi

# Other Modes
else

    python3 main.py "$@"

fi

set +e