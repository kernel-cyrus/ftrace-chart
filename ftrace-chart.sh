#!/bin/bash
set -e

start_trace() {
    _OUT_FILE=$1
    echo "Tracing start..."
    echo -n 1 > /sys/kernel/debug/tracing/tracing_on
    set +e
    if [ -z "$TIME" ]; then
        trap 'echo -n ""' SIGINT
        echo "Press CTRL+C to stop..."
        cat /sys/kernel/debug/tracing/trace_pipe > $_OUT_FILE
    else
        echo "Tracing for $TIME seconds..."
        timeout $TIME cat /sys/kernel/debug/tracing/trace_pipe > $_OUT_FILE
    fi
    set -e
    echo -n 0 > /sys/kernel/debug/tracing/tracing_on
    echo "Trace stop."
}

start_perf() {
    _FUNC=$1
    _OUT_FILE=$2
    echo "Tracing start..."
    set +e
    if [ -z "$TIME" ]; then
        trap 'echo -n ""' SIGINT
        echo "Press CTRL+C to stop..."
        perf record -e kprobes:$_FUNC -F 99 -a -g -o $_OUT_FILE
    else
        echo "Tracing for $TIME seconds..."
        perf record -e kprobes:$_FUNC -F 99 -a -g -o $_OUT_FILE -- sleep $TIME
    fi
    set -e
    echo "Trace stop."
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
    echo "  -m, --mode=[trace|stack|flame]"
    echo "                              \"trace\" is function-graph chart (excution flow of the function)"
    echo "                              \"stack\" is stacktrace chart (where has the function been called)"
    echo "                              \"flame\" is flamegraph chart (where and times the function has been called)"
    echo "  -f, --function              Function to track"
    echo "  -t, --timeout               Seconds to trace, you can stop mannully without passing this param."
    echo "  -o, --output                Output trace file (default: result/*.data)."
    echo ""
    echo "Trace Mode Example"
    echo "---------------------"
    echo "  Generate chart of schedule() excution flow:"
    echo ""
    echo "  1. Record function-graph trace of schedule()"
    echo "  $ ./ftrace-chart.sh record --mode=trace --function=schedule --timeout=10"
    echo ""
    echo "  2. Generate plantuml(.puml) files of the trace"
    echo "  $ ./ftrace-chart.sh report --mode=trace"
    echo ""
    echo "  3. Generate plantuml svg image"
    echo "  $ java -jar thirdparty/plantuml/plantuml-mit.jar -tsvg ./result/schedule*.puml"
    echo ""
    echo "Stack Mode Example"
    echo "---------------------"
    echo "  Generate chart of schedule() called positions:"
    echo ""
    echo "  1. Record stacktrace of schedule()"
    echo "  $ ./ftrace-chart.sh record --mode=stack --function=schedule --timeout=10"
    echo ""
    echo "  2. Generate plantuml(.puml) and svg files of the trace"
    echo "  $ ./ftrace-chart.sh report --mode=stack"
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
            -o=*|--output=*)
                OUT_FILE="${i#*=}"
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
        echo "Please pass the record mode: --mode=[trace|stack|flame]"
        exit 0
    fi
    
    if [ -z "$FUNC" ]; then
        echo "Please pass the record function: --function=<function_name>"
        exit 0
    fi

    if [ -z "$OUT_FILE" ]; then
        OUT_FILE="./result/$MODE.data"
    fi

    mkdir -p "$(dirname "$OUT_FILE")"

    if [ "$EUID" -ne 0 ]; then
        echo "Running as root."
        exec sudo "$0" "${ARGS[@]}"
    fi

    # Record Trace Mode
    if [ "$MODE" == "trace" ]; then
        
        echo "Setup ftrace..."
        echo -n 0 > /sys/kernel/debug/tracing/tracing_on
        echo -n function_graph > /sys/kernel/debug/tracing/current_tracer
        echo -n > /sys/kernel/debug/tracing/trace
        echo -n > /sys/kernel/debug/tracing/set_graph_function
        echo -n "$FUNC" > /sys/kernel/debug/tracing/set_graph_function
        start_trace $OUT_FILE
        echo "Reset ftrace..."
        echo -n 0 > /sys/kernel/debug/tracing/tracing_on
        echo -n > /sys/kernel/debug/tracing/set_graph_function
        echo "Trace file saved: $OUT_FILE"
        echo "Done."

    # Record Stack Mode
    elif [ "$MODE" == "stack" ]; then

        echo "Setup ftrace..."
        echo -n 0 > /sys/kernel/debug/tracing/tracing_on
        echo -n nop > /sys/kernel/debug/tracing/current_tracer
        echo -n > /sys/kernel/debug/tracing/trace
        if [ -d "/sys/kernel/debug/tracing/events/kprobes" ]; then
            echo -n 0 > /sys/kernel/debug/tracing/events/kprobes/enable
        fi
        echo > /sys/kernel/debug/tracing/kprobe_events
        echo -n "p:$FUNC $FUNC" > /sys/kernel/debug/tracing/kprobe_events
        echo -n 1 > /sys/kernel/debug/tracing/events/kprobes/enable
        echo -n 1 > /sys/kernel/debug/tracing/options/stacktrace
        start_trace $OUT_FILE
        echo "Reset ftrace..."
        echo -n 0 > /sys/kernel/debug/tracing/events/kprobes/enable
        echo -n 0 > /sys/kernel/debug/tracing/options/stacktrace
        echo -n > /sys/kernel/debug/tracing/kprobe_events
        echo "Trace file saved: $OUT_FILE"
        echo "Done."

    # Record Flame Mode
    elif [ "$MODE" == "flame" ]; then

        echo "Setup ftrace..."
        echo -n "p:$FUNC $FUNC" >> /sys/kernel/debug/tracing/kprobe_events
        start_perf $FUNC $OUT_FILE
        echo "Reset ftrace..."
        echo -n "-:$FUNC" >> /sys/kernel/debug/tracing/kprobe_events
        echo "Trace file saved: $OUT_FILE"
        echo "Done."

    # Invalid
    else
        echo "ERROR: Invalid record mode: --mode=[trace|stack|flame]"
    fi

# Other Modes
else

    python3 main.py "$@"

fi

set +e