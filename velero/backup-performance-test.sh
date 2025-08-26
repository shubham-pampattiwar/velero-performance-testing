#!/bin/bash

# Script to run Velero backup performance tests
# Tests backup speed and monitors performance characteristics

set -e

echo "🎯 Velero Backup Performance Test"
echo "================================="
echo ""

# Check if Velero is installed
if ! command -v velero &> /dev/null; then
    echo "❌ Velero CLI not found. Please install Velero first:"
    echo "  ./velero/install-velero.sh"
    exit 1
fi

# Check Velero server status
echo "🔍 Checking Velero server status..."
if ! velero version --timeout=10s >/dev/null 2>&1; then
    echo "❌ Velero server not accessible. Please check installation:"
    echo "  kubectl get pods -n velero"
    echo "  velero backup-location get"
    exit 1
fi

echo "✅ Velero server is accessible"
echo ""

# Detect available test resources
echo "📊 Detecting available test resources..."
SIMPLE_OBJECTS=$(kubectl get all,configmaps,secrets -n velero-perf-test -l velero-test=performance --no-headers 2>/dev/null | wc -l || echo "0")
LARGE_SCALE_OBJECTS=$(kubectl get all,configmaps,secrets --all-namespaces -l velero-test=performance --no-headers 2>/dev/null | wc -l || echo "0")

echo "  Simple test objects (velero-perf-test): $SIMPLE_OBJECTS"
echo "  Large-scale test objects (all namespaces): $LARGE_SCALE_OBJECTS"
echo ""

if [ "$SIMPLE_OBJECTS" -eq 0 ] && [ "$LARGE_SCALE_OBJECTS" -eq 0 ]; then
    echo "❌ No test resources found. Please create test objects first:"
    echo "  ./scripts/run-simple-test.sh      # 30k objects"
    echo "  ./scripts/run-large-scale-test.sh # 300k objects"
    exit 1
fi

# Select backup scope
echo "📋 Select backup scope:"
if [ "$SIMPLE_OBJECTS" -gt 0 ]; then
    echo "1) Simple test backup ($SIMPLE_OBJECTS objects in velero-perf-test namespace)"
fi
if [ "$LARGE_SCALE_OBJECTS" -gt 0 ]; then
    echo "2) Large-scale test backup ($LARGE_SCALE_OBJECTS objects across all performance namespaces)"
fi
echo "3) Custom selector backup"
echo ""
read -p "Enter choice (1-3): " -n 1 -r BACKUP_CHOICE
echo ""

# Generate backup name with timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

case $BACKUP_CHOICE in
    1)
        if [ "$SIMPLE_OBJECTS" -eq 0 ]; then
            echo "❌ No simple test objects found"
            exit 1
        fi
        BACKUP_NAME="simple-test-$TIMESTAMP"
        BACKUP_CMD="velero backup create $BACKUP_NAME --include-namespaces velero-perf-test --wait"
        EXPECTED_OBJECTS=$SIMPLE_OBJECTS
        TEST_TYPE="Simple Test (30k objects)"
        ;;
    2)
        if [ "$LARGE_SCALE_OBJECTS" -eq 0 ]; then
            echo "❌ No large-scale test objects found"
            exit 1
        fi
        BACKUP_NAME="large-scale-test-$TIMESTAMP"
        BACKUP_CMD="velero backup create $BACKUP_NAME --selector velero-test=performance --wait"
        EXPECTED_OBJECTS=$LARGE_SCALE_OBJECTS
        TEST_TYPE="Large-Scale Test (300k objects)"
        ;;
    3)
        read -p "Enter custom label selector (e.g., app=myapp): " CUSTOM_SELECTOR
        BACKUP_NAME="custom-test-$TIMESTAMP"
        BACKUP_CMD="velero backup create $BACKUP_NAME --selector $CUSTOM_SELECTOR --wait"
        EXPECTED_OBJECTS="Unknown"
        TEST_TYPE="Custom Selector"
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "🚀 Starting $TEST_TYPE backup..."
echo "  Backup name: $BACKUP_NAME"
echo "  Expected objects: $EXPECTED_OBJECTS"
echo "  Command: $BACKUP_CMD"
echo ""

# Record start time
START_TIME=$(date +%s)
START_TIME_HUMAN=$(date)

echo "⏱️  Backup started at: $START_TIME_HUMAN"
echo ""

# Create log file
LOG_FILE="velero-backup-$BACKUP_NAME.log"
echo "📝 Logging to: $LOG_FILE"

# Start backup and monitor progress
echo "Starting backup..." | tee "$LOG_FILE"
echo "Command: $BACKUP_CMD" | tee -a "$LOG_FILE"
echo "Start time: $START_TIME_HUMAN" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Run backup command in background and capture output
$BACKUP_CMD 2>&1 | tee -a "$LOG_FILE" &
BACKUP_PID=$!

# Monitor progress while backup is running
echo "📊 Monitoring backup progress..."
echo "   (Press Ctrl+C to stop monitoring, backup will continue)"
echo ""

# Wait for backup to appear in the system
sleep 5

# Monitor loop
while kill -0 $BACKUP_PID 2>/dev/null; do
    # Get backup status
    STATUS=$(velero backup describe $BACKUP_NAME --details=false 2>/dev/null | grep "Phase:" | awk '{print $2}' || echo "Unknown")
    PROGRESS=$(velero backup describe $BACKUP_NAME --details=false 2>/dev/null | grep "Items backed up:" | awk '{print $3}' || echo "0")
    
    # Calculate elapsed time
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    ELAPSED_MIN=$((ELAPSED / 60))
    ELAPSED_SEC=$((ELAPSED % 60))
    
    # Show progress
    printf "\r⏳ Status: %-12s | Items: %-8s | Elapsed: %02d:%02d" "$STATUS" "$PROGRESS" "$ELAPSED_MIN" "$ELAPSED_SEC"
    
    sleep 10
done

# Wait for background process to complete
wait $BACKUP_PID
BACKUP_EXIT_CODE=$?

echo ""
echo ""

# Record end time
END_TIME=$(date +%s)
END_TIME_HUMAN=$(date)
TOTAL_DURATION=$((END_TIME - START_TIME))
DURATION_MIN=$((TOTAL_DURATION / 60))
DURATION_SEC=$((TOTAL_DURATION % 60))

echo "⏱️  Backup completed at: $END_TIME_HUMAN" | tee -a "$LOG_FILE"
echo "⏰ Total duration: ${DURATION_MIN}m ${DURATION_SEC}s" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Get final backup details
echo "📊 Final Backup Results:" | tee -a "$LOG_FILE"
echo "========================" | tee -a "$LOG_FILE"
velero backup describe $BACKUP_NAME | tee -a "$LOG_FILE"

# Calculate performance metrics
if [ "$BACKUP_EXIT_CODE" -eq 0 ]; then
    echo ""
    echo "✅ Backup completed successfully!" | tee -a "$LOG_FILE"
    
    # Extract metrics from backup description
    ITEMS_BACKED_UP=$(velero backup describe $BACKUP_NAME --details=false | grep "Items backed up:" | awk '{print $3}')
    BACKUP_SIZE=$(velero backup describe $BACKUP_NAME --details=false | grep "Backup Size:" | awk '{print $3}')
    
    if [ -n "$ITEMS_BACKED_UP" ] && [ "$ITEMS_BACKED_UP" -gt 0 ] && [ "$TOTAL_DURATION" -gt 0 ]; then
        RATE=$(( ITEMS_BACKED_UP / TOTAL_DURATION ))
        echo ""
        echo "📈 Performance Metrics:" | tee -a "$LOG_FILE"
        echo "  Items backed up: $ITEMS_BACKED_UP" | tee -a "$LOG_FILE"
        echo "  Backup size: $BACKUP_SIZE" | tee -a "$LOG_FILE"
        echo "  Total time: ${DURATION_MIN}m ${DURATION_SEC}s" | tee -a "$LOG_FILE"
        echo "  Average rate: $RATE objects/second" | tee -a "$LOG_FILE"
        
        # Compare with expected performance
        if [ "$RATE" -lt 10 ]; then
            echo "  ⚠️  Performance: SLOW (< 10 objects/sec)" | tee -a "$LOG_FILE"
            echo "  🔍 This matches the reported issue behavior!" | tee -a "$LOG_FILE"
        elif [ "$RATE" -lt 50 ]; then
            echo "  ⚡ Performance: MODERATE (10-50 objects/sec)" | tee -a "$LOG_FILE"
        else
            echo "  🚀 Performance: FAST (> 50 objects/sec)" | tee -a "$LOG_FILE"
        fi
    fi
else
    echo "❌ Backup failed!" | tee -a "$LOG_FILE"
    echo "Check the logs above for error details." | tee -a "$LOG_FILE"
fi

echo ""
echo "📄 Full backup details saved to: $LOG_FILE"
echo ""
echo "🔍 Next steps:"
echo "  1. Analyze performance: ./velero/analyze-performance.sh $BACKUP_NAME"
echo "  2. Test restore: ./velero/restore-performance-test.sh $BACKUP_NAME"
echo "  3. View logs: velero backup logs $BACKUP_NAME"