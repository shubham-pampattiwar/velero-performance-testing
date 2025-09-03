#!/bin/bash

# Analyze Velero backup performance logs for issue #9169
# Generates charts, identifies performance degradation patterns, and summarizes findings

set -e

LOG_DIR=""
BACKUP_NAME=""
OUTPUT_DIR="./performance-analysis"

usage() {
    echo "Usage: $0 -d LOG_DIR [-n BACKUP_NAME] [-o OUTPUT_DIR] [-h]"
    echo ""
    echo "Options:"
    echo "  -d LOG_DIR       Directory containing backup performance logs (required)"
    echo "  -n BACKUP_NAME   Specific backup to analyze (optional, analyzes all if not specified)"
    echo "  -o OUTPUT_DIR    Output directory for analysis results (default: ./performance-analysis)"
    echo "  -h               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -d ./backup-performance-logs"
    echo "  $0 -d ./backup-performance-logs -n performance-test-113k-objects"
    exit 1
}

while getopts "d:n:o:h" opt; do
    case ${opt} in
        d)
            LOG_DIR="$OPTARG"
            ;;
        n)
            BACKUP_NAME="$OPTARG"
            ;;
        o)
            OUTPUT_DIR="$OPTARG"
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

if [ -z "$LOG_DIR" ]; then
    echo "Error: Log directory is required"
    usage
fi

if [ ! -d "$LOG_DIR" ]; then
    echo "Error: Log directory '$LOG_DIR' does not exist"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

analyze_backup_performance() {
    local perf_log="$1"
    local backup_name="$2"
    local analysis_file="$OUTPUT_DIR/${backup_name}-analysis.txt"
    
    echo "=== PERFORMANCE ANALYSIS: $backup_name ===" > "$analysis_file"
    echo "Generated: $(date)" >> "$analysis_file"
    echo "" >> "$analysis_file"
    
    if [ ! -f "$perf_log" ]; then
        echo "Performance log not found: $perf_log" >> "$analysis_file"
        return
    fi
    
    # Extract key metrics
    local total_lines=$(wc -l < "$perf_log")
    local data_lines=$((total_lines - 3))  # Skip header lines
    
    if [ "$data_lines" -le 0 ]; then
        echo "No performance data found in log" >> "$analysis_file"
        return
    fi
    
    echo "BASIC METRICS:" >> "$analysis_file"
    echo "- Total monitoring intervals: $data_lines" >> "$analysis_file"
    
    # Get final stats
    local last_line=$(tail -1 "$perf_log")
    IFS=',' read -r timestamp status progress items_backed_up total_items objects_per_second phase elapsed_time <<< "$last_line"
    
    echo "- Final status: $status" >> "$analysis_file"
    echo "- Objects processed: $items_backed_up" >> "$analysis_file"
    echo "- Total objects: $total_items" >> "$analysis_file"
    echo "- Total duration: ${elapsed_time}s" >> "$analysis_file"
    
    if [ "$items_backed_up" -gt 0 ] && [ "$elapsed_time" -gt 0 ]; then
        local avg_rate=$(echo "scale=2; $items_backed_up / $elapsed_time" | bc -l 2>/dev/null || echo "0")
        echo "- Average processing rate: $avg_rate objects/second" >> "$analysis_file"
    fi
    
    echo "" >> "$analysis_file"
    
    # Analyze performance degradation
    echo "PERFORMANCE DEGRADATION ANALYSIS:" >> "$analysis_file"
    
    # Check for rates below 5 obj/s after 5k objects
    local degradation_count=0
    local slow_periods=""
    
    while IFS=',' read -r ts st prog items total rate ph elapsed; do
        if [[ "$items" =~ ^[0-9]+$ ]] && [ "$items" -gt 5000 ]; then
            if [[ "$rate" =~ ^[0-9]+\.?[0-9]*$ ]] && [ "$(echo "$rate < 3" | bc -l 2>/dev/null)" = "1" ]; then
                degradation_count=$((degradation_count + 1))
                if [ -z "$slow_periods" ]; then
                    slow_periods="$items objects (${rate} obj/s)"
                else
                    slow_periods="$slow_periods, $items objects (${rate} obj/s)"
                fi
            fi
        fi
    done < <(tail -n +4 "$perf_log")  # Skip header
    
    if [ "$degradation_count" -gt 0 ]; then
        echo "- Performance degradation detected: YES" >> "$analysis_file"
        echo "- Slow periods count: $degradation_count intervals" >> "$analysis_file"
        echo "- Slow periods: $slow_periods" >> "$analysis_file"
    else
        echo "- Performance degradation detected: NO" >> "$analysis_file"
    fi
    
    echo "" >> "$analysis_file"
    
    # Performance phases analysis
    echo "PERFORMANCE PHASES:" >> "$analysis_file"
    
    # First 5k objects
    local first_5k_rate=$(awk -F',' 'NR>3 && $4<=5000 && $4>0 {sum+=$6; count++} END {if(count>0) print sum/count; else print "N/A"}' "$perf_log")
    echo "- First 5k objects average rate: $first_5k_rate obj/s" >> "$analysis_file"
    
    # After 5k objects
    local after_5k_rate=$(awk -F',' 'NR>3 && $4>5000 {sum+=$6; count++} END {if(count>0) print sum/count; else print "N/A"}' "$perf_log")
    echo "- After 5k objects average rate: $after_5k_rate obj/s" >> "$analysis_file"
    
    # Performance drop calculation
    if [[ "$first_5k_rate" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$after_5k_rate" =~ ^[0-9]+\.?[0-9]*$ ]] && [ "$(echo "$first_5k_rate > 0" | bc -l)" = "1" ]; then
        local performance_drop=$(echo "scale=2; (($first_5k_rate - $after_5k_rate) / $first_5k_rate) * 100" | bc -l 2>/dev/null || echo "0")
        echo "- Performance drop after 5k objects: ${performance_drop}%" >> "$analysis_file"
    fi
    
    echo "" >> "$analysis_file"
    
    # Generate CSV for visualization
    local csv_file="$OUTPUT_DIR/${backup_name}-data.csv"
    echo "timestamp,elapsed_seconds,objects_processed,rate_obj_per_sec,cumulative_rate" > "$csv_file"
    
    while IFS=',' read -r timestamp status progress items_backed_up total_items objects_per_second phase elapsed_time; do
        if [[ "$elapsed_time" =~ ^[0-9]+$ ]] && [[ "$items_backed_up" =~ ^[0-9]+$ ]]; then
            local cumulative_rate=0
            if [ "$elapsed_time" -gt 0 ]; then
                cumulative_rate=$(echo "scale=2; $items_backed_up / $elapsed_time" | bc -l 2>/dev/null || echo "0")
            fi
            echo "$timestamp,$elapsed_time,$items_backed_up,$objects_per_second,$cumulative_rate" >> "$csv_file"
        fi
    done < <(tail -n +4 "$perf_log")
    
    echo "DATA FILES:" >> "$analysis_file"
    echo "- Analysis report: $analysis_file" >> "$analysis_file"
    echo "- CSV data: $csv_file" >> "$analysis_file"
    
    echo "Analysis completed for $backup_name"
    echo "Report: $analysis_file"
}

# Find and analyze backup logs
if [ -n "$BACKUP_NAME" ]; then
    # Analyze specific backup
    perf_log="$LOG_DIR/${BACKUP_NAME}-performance.log"
    if [ -f "$perf_log" ]; then
        analyze_backup_performance "$perf_log" "$BACKUP_NAME"
    else
        echo "Performance log not found for backup: $BACKUP_NAME"
        exit 1
    fi
else
    # Analyze all backups in directory
    found_logs=false
    for perf_log in "$LOG_DIR"/*-performance.log; do
        if [ -f "$perf_log" ]; then
            backup_name=$(basename "$perf_log" -performance.log)
            analyze_backup_performance "$perf_log" "$backup_name"
            found_logs=true
        fi
    done
    
    if [ "$found_logs" = false ]; then
        echo "No performance logs found in directory: $LOG_DIR"
        exit 1
    fi
fi

# Generate summary report
summary_file="$OUTPUT_DIR/performance-summary.txt"
echo "=== VELERO PERFORMANCE ANALYSIS SUMMARY ===" > "$summary_file"
echo "Generated: $(date)" >> "$summary_file"
echo "Log directory: $LOG_DIR" >> "$summary_file"
echo "" >> "$summary_file"

echo "ANALYZED BACKUPS:" >> "$summary_file"
for analysis in "$OUTPUT_DIR"/*-analysis.txt; do
    if [ -f "$analysis" ]; then
        backup=$(basename "$analysis" -analysis.txt)
        echo "- $backup" >> "$summary_file"
        
        # Extract key metrics
        status=$(grep "Final status:" "$analysis" | cut -d: -f2 | xargs)
        objects=$(grep "Objects processed:" "$analysis" | cut -d: -f2 | xargs)
        duration=$(grep "Total duration:" "$analysis" | cut -d: -f2 | xargs)
        degradation=$(grep "Performance degradation detected:" "$analysis" | cut -d: -f2 | xargs)
        
        echo "  Status: $status, Objects: $objects, Duration: $duration, Degradation: $degradation" >> "$summary_file"
    fi
done

echo "" >> "$summary_file"
echo "ANALYSIS COMPLETE" >> "$summary_file"
echo "Individual reports available in: $OUTPUT_DIR" >> "$summary_file"

echo ""
echo "Performance analysis completed!"
echo "Summary report: $summary_file"
echo "Individual analysis files in: $OUTPUT_DIR"