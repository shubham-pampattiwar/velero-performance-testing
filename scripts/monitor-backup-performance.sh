#!/bin/bash

# Monitor Velero backup performance for issue debugging
# Tracks backup progress, timing, resource usage, and identifies performance degradation

set -e

BACKUP_NAME=""
VELERO_NAMESPACE="openshift-adp"
MONITOR_INTERVAL=10
OUTPUT_DIR="./backup-performance-logs"
DETAILED_LOGGING=false

usage() {
    echo "Usage: $0 -n BACKUP_NAME [-i INTERVAL] [-d OUTPUT_DIR] [-v] [-h]"
    echo ""
    echo "Options:"
    echo "  -n BACKUP_NAME    Name of the Velero backup to monitor (required)"
    echo "  -i INTERVAL       Monitoring interval in seconds (default: 10)"
    echo "  -d OUTPUT_DIR     Directory for output logs (default: ./backup-performance-logs)"
    echo "  -v                Enable detailed/verbose logging"
    echo "  -h                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -n perf-test-150k"
    echo "  $0 -n perf-test-v1-11-1 -i 5 -v"
    exit 1
}

while getopts "n:i:d:vh" opt; do
    case ${opt} in
        n)
            BACKUP_NAME="$OPTARG"
            ;;
        i)
            MONITOR_INTERVAL="$OPTARG"
            ;;
        d)
            OUTPUT_DIR="$OPTARG"
            ;;
        v)
            DETAILED_LOGGING=true
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
    esac
done

if [ -z "$BACKUP_NAME" ]; then
    echo "Error: Backup name is required"
    usage
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Log files
PERFORMANCE_LOG="$OUTPUT_DIR/${BACKUP_NAME}-performance.log"
RESOURCE_LOG="$OUTPUT_DIR/${BACKUP_NAME}-resources.log"
DETAILED_LOG="$OUTPUT_DIR/${BACKUP_NAME}-detailed.log"
SUMMARY_LOG="$OUTPUT_DIR/${BACKUP_NAME}-summary.log"

# Initialize logs
echo "# Velero Backup Performance Monitoring - $(date)" > "$PERFORMANCE_LOG"
echo "# Backup: $BACKUP_NAME" >> "$PERFORMANCE_LOG"
echo "# Monitoring interval: ${MONITOR_INTERVAL}s" >> "$PERFORMANCE_LOG"
echo "timestamp,status,progress,items_backed_up,total_items,objects_per_second,phase,elapsed_time" >> "$PERFORMANCE_LOG"

echo "# Resource Usage Monitoring - $(date)" > "$RESOURCE_LOG"
echo "timestamp,cpu_usage,memory_usage,velero_pod_status" >> "$RESOURCE_LOG"

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$DETAILED_LOG"
    
    if [ "$DETAILED_LOGGING" = true ] || [ "$level" != "DEBUG" ]; then
        echo "[$timestamp] [$level] $message"
    fi
}

get_backup_status() {
    kubectl get backup "$BACKUP_NAME" -n "$VELERO_NAMESPACE" -o json 2>/dev/null || echo "{}"
}

get_velero_pod_resources() {
    kubectl top pod -n "$VELERO_NAMESPACE" -l app.kubernetes.io/name=velero --no-headers 2>/dev/null | awk '{print $2","$3}' || echo "N/A,N/A"
}

monitor_backup() {
    local start_time=$(date +%s)
    local last_items_count=0
    local last_check_time=$start_time
    local performance_degradation_detected=false
    
    log_message "INFO" "Starting backup monitoring for: $BACKUP_NAME"
    log_message "INFO" "Output directory: $OUTPUT_DIR"
    
    while true; do
        local current_time=$(date +%s)
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local elapsed_time=$((current_time - start_time))
        
        # Get backup status
        local backup_json=$(get_backup_status)
        
        if [ "$backup_json" = "{}" ]; then
            log_message "ERROR" "Backup $BACKUP_NAME not found"
            exit 1
        fi
        
        local status=$(echo "$backup_json" | jq -r '.status.phase // "Unknown"')
        local progress=$(echo "$backup_json" | jq -r '.status.progress // {}')
        local items_backed_up=$(echo "$progress" | jq -r '.itemsBackedUp // 0')
        local total_items=$(echo "$progress" | jq -r '.totalItems // 0')
        
        # Calculate objects per second
        local time_diff=$((current_time - last_check_time))
        local items_diff=$((items_backed_up - last_items_count))
        local objects_per_second=0
        
        if [ "$time_diff" -gt 0 ] && [ "$items_diff" -gt 0 ]; then
            objects_per_second=$(echo "scale=2; $items_diff / $time_diff" | bc -l 2>/dev/null || echo "0")
        fi
        
        # Get resource usage
        local resources=$(get_velero_pod_resources)
        local velero_pod_status=$(kubectl get pods -n "$VELERO_NAMESPACE" -l app.kubernetes.io/name=velero --no-headers -o custom-columns=":status.phase" 2>/dev/null | head -1)
        
        # Log performance data
        echo "$timestamp,$status,$progress,$items_backed_up,$total_items,$objects_per_second,$status,$elapsed_time" >> "$PERFORMANCE_LOG"
        echo "$timestamp,$resources,$velero_pod_status" >> "$RESOURCE_LOG"
        
        # Performance analysis
        if [ "$items_backed_up" -gt 5000 ] && [ -n "$objects_per_second" ] && [ "$(echo "$objects_per_second < 5" | bc -l 2>/dev/null)" = "1" ] && [ "$performance_degradation_detected" = false ]; then
            performance_degradation_detected=true
            log_message "WARNING" "Performance degradation detected! Objects/sec: $objects_per_second (threshold: <5 ops/s after 5k objects)"
            echo "PERFORMANCE_DEGRADATION_DETECTED: $(date) - Objects/sec: $objects_per_second at $items_backed_up objects" >> "$SUMMARY_LOG"
        fi
        
        log_message "INFO" "Status: $status | Progress: $items_backed_up/$total_items | Rate: ${objects_per_second} obj/s | Elapsed: ${elapsed_time}s"
        
        # Check if backup is complete
        if [ "$status" = "Completed" ] || [ "$status" = "Failed" ] || [ "$status" = "PartiallyFailed" ]; then
            log_message "INFO" "Backup finished with status: $status"
            
            # Generate summary
            echo "=== BACKUP PERFORMANCE SUMMARY ===" > "$SUMMARY_LOG"
            echo "Backup Name: $BACKUP_NAME" >> "$SUMMARY_LOG"
            echo "Final Status: $status" >> "$SUMMARY_LOG"
            echo "Total Objects: $total_items" >> "$SUMMARY_LOG"
            echo "Objects Backed Up: $items_backed_up" >> "$SUMMARY_LOG"
            echo "Total Duration: ${elapsed_time}s" >> "$SUMMARY_LOG"
            echo "Average Rate: $(echo "scale=2; $items_backed_up / $elapsed_time" | bc -l 2>/dev/null || echo "0") obj/s" >> "$SUMMARY_LOG"
            echo "Performance Degradation: $performance_degradation_detected" >> "$SUMMARY_LOG"
            echo "Generated: $(date)" >> "$SUMMARY_LOG"
            
            log_message "INFO" "Performance summary saved to: $SUMMARY_LOG"
            break
        fi
        
        # Update for next iteration
        last_items_count=$items_backed_up
        last_check_time=$current_time
        
        sleep "$MONITOR_INTERVAL"
    done
}

# Check dependencies
if ! command -v jq &> /dev/null; then
    log_message "ERROR" "jq is required but not installed"
    exit 1
fi

if ! command -v bc &> /dev/null; then
    log_message "ERROR" "bc is required but not installed"
    exit 1
fi

if ! kubectl get backup "$BACKUP_NAME" -n "$VELERO_NAMESPACE" &> /dev/null; then
    log_message "ERROR" "Backup '$BACKUP_NAME' not found in namespace '$VELERO_NAMESPACE'"
    exit 1
fi

# Start monitoring
monitor_backup