#!/bin/bash
set -e

start_trace() {
    _OUT_FILE=$1
    echo "Tracing start..."
    echo 1 > /sys/kernel/debug/tracing/tracing_on
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
    echo 0 > /sys/kernel/debug/tracing/tracing_on
    echo "Trace stop."
}

start_perf() {
    _EVENT=$1
    _OUT_FILE=$2
    echo "Tracing start..."
    if [ -z "$PID" ]; then
        PID_STR=""
    else
	PID_STR="-t $PID"
    fi
    set +e
    if [ -z "$TIME" ]; then
        trap 'echo -n ""' SIGINT
        echo "Press CTRL+C to stop..."
        perf record -e $_EVENT $PID_STR -F 99 -a -g -o $_OUT_FILE
    else
        echo "Tracing for $TIME seconds..."
        perf record -e $_EVENT $PID_STR -F 99 -a -g -o $_OUT_FILE -- sleep $TIME
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
    echo "                              \"uftrace\" is uftrace to perfetto view (program excution flow)"
    echo "  -f, --function              Function to track"
    echo "  -p, --pid                   Process to track"
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
    echo "  2. Generate plantuml files"
    echo "  $ ./ftrace-chart.sh report --mode=trace"
    echo ""
    echo "  3. Generate svg image"
    echo "  $ java -jar thirdparty/plantuml/plantuml-mit.jar -tsvg ./result/schedule*.puml"
    echo ""
    echo "Stack Mode Example"
    echo "---------------------"
    echo "  Generate chart of schedule() called positions:"
    echo ""
    echo "  1. Record stacktrace of schedule()"
    echo "  $ ./ftrace-chart.sh record --mode=stack --function=schedule --timeout=10"
    echo ""
    echo "  2. Generate plantuml files and svg image"
    echo "  $ ./ftrace-chart.sh report --mode=stack"
    echo ""
    echo "Flame Mode Example"
    echo "---------------------"
    echo "  Generate flame graph of an event or function:"
    echo ""
    echo "  1. Record perf data of an event or function"
    echo "  $ ./ftrace-chart.sh record --mode=flame --timeout=10"
    echo "  $ ./ftrace-chart.sh record --mode=flame --event=cache-misses --timeout=10"
    echo "  $ ./ftrace-chart.sh record --mode=flame --function=schedule --timeout=10"
    echo ""
    echo "  2. Generate flamechart svg image"
    echo "  $ ./ftrace-chart.sh report --mode=flame"
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
            -p=*|--pid=*)
                PID="${i#*=}"
                shift # past argument=value
                ;;
            -e=*|--event=*)
                EVENT="${i#*=}"
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
            -c=*|--cmd=*)
                CMD="${i#*=}"
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
        echo "Please pass the record mode: --mode=[trace|stack|flame|uftrace]"
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

        if [ -z "$FUNC" ]; then
            echo "Please pass the record function: --function=<function_name>"
            exit 0
        fi

        echo "Setup ftrace..."
        echo 0 > /sys/kernel/debug/tracing/tracing_on
        echo function_graph > /sys/kernel/debug/tracing/current_tracer
        echo > /sys/kernel/debug/tracing/trace
        echo > /sys/kernel/debug/tracing/set_graph_function
        echo "$FUNC" > /sys/kernel/debug/tracing/set_graph_function
        echo '8192' > /sys/kernel/debug/tracing/buffer_size_kb
	echo $PID > /sys/kernel/debug/tracing/set_ftrace_pid
	echo $PID > /sys/kernel/debug/tracing/set_event_pid
        start_trace $OUT_FILE
        echo "Reset ftrace..."
        echo 0 > /sys/kernel/debug/tracing/tracing_on
        echo > /sys/kernel/debug/tracing/set_graph_function
	echo > /sys/kernel/debug/tracing/set_ftrace_pid
	echo > /sys/kernel/debug/tracing/set_event_pid
        echo "Trace file saved: $OUT_FILE"
        echo "Done."

    # Record Stack Mode
    elif [ "$MODE" == "stack" ]; then

        if [ -z "$FUNC" ]; then
            echo "Please pass the record function: --function=<function_name>"
            exit 0
        fi

        echo "Setup ftrace..."
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
        echo '8192' > /sys/kernel/debug/tracing/buffer_size_kb
	echo $PID > /sys/kernel/debug/tracing/set_ftrace_pid
	echo $PID > /sys/kernel/debug/tracing/set_event_pid
        start_trace $OUT_FILE
        echo "Reset ftrace..."
        echo 0 > /sys/kernel/debug/tracing/events/kprobes/enable
        echo 0 > /sys/kernel/debug/tracing/options/stacktrace
        echo > /sys/kernel/debug/tracing/kprobe_events
	echo > /sys/kernel/debug/tracing/set_ftrace_pid
	echo > /sys/kernel/debug/tracing/set_event_pid
        echo "Trace file saved: $OUT_FILE"
        echo "Done."

    # Record Flame Mode
    elif [ "$MODE" == "flame" ]; then

        if [ -z "$EVENT" ]; then
            EVENT="cycles"
        fi

        if [ "$FUNC" ]; then
            echo "Setup ftrace..."
            echo "p:$FUNC $FUNC" >> /sys/kernel/debug/tracing/kprobe_events
            start_perf kprobes:$FUNC $OUT_FILE
            echo "Reset ftrace..."
            echo "-:$FUNC" >> /sys/kernel/debug/tracing/kprobe_events
            echo "Trace file saved: $OUT_FILE"
            echo "Done."
        elif [ "$EVENT" ]; then
            start_perf $EVENT $OUT_FILE
            echo "Trace file saved: $OUT_FILE"
            echo "Done."
        fi

    elif [ "$MODE" == "uftrace" ]; then

	if ! type uftrace >/dev/null 2>&1; then
            echo "Please install uftrace first."
            exit 0
	fi

        if [ -z "$CMD" ]; then
            echo "Please specify a program to run: --cmd=<program>"
            exit 0
        fi

	PARAMS=""
        if [ "$FUNC" ]; then
            PARAMS+=" -F $FUNC"
	fi

	if [ "$EVENT" ]; then
            PARAMS+=" -E $EVENT"
	fi

	uftrace record $PARAMS -k -K 50 -d $OUT_FILE $CMD
        echo "Trace file saved: $OUT_FILE"
        echo "Done."

    # Invalid
    else
        echo "ERROR: Invalid record mode: --mode=[trace|stack|flame|uftrace]"
    fi

# Other Modes
else

    python3 main.py "$@"

fi

set +e
