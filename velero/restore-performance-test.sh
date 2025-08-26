#!/bin/bash

# Script to test Velero restore performance
# Measures restore speed and validates data integrity

set -e

echo "🔄 Velero Restore Performance Test"
echo "=================================="
echo ""

# Check if backup name provided
if [ $# -eq 0 ]; then
    echo "📋 Available backups:"
    velero backup get
    echo ""
    read -p "Enter backup name to restore: " BACKUP_NAME
else
    BACKUP_NAME=$1
fi

# Validate backup exists and is completed
echo "🔍 Validating backup: $BACKUP_NAME"
BACKUP_STATUS=$(velero backup describe $BACKUP_NAME --details=false 2>/dev/null | grep "Phase:" | awk '{print $2}' || echo "NotFound")

if [ "$BACKUP_STATUS" = "NotFound" ]; then
    echo "❌ Backup '$BACKUP_NAME' not found"
    echo "Available backups:"
    velero backup get
    exit 1
elif [ "$BACKUP_STATUS" != "Completed" ]; then
    echo "❌ Backup '$BACKUP_NAME' is not completed (Status: $BACKUP_STATUS)"
    exit 1
fi

echo "✅ Backup '$BACKUP_NAME' is valid and completed"
echo ""

# Get backup details
ITEMS_IN_BACKUP=$(velero backup describe $BACKUP_NAME --details=false | grep "Items backed up:" | awk '{print $3}')
BACKUP_SIZE=$(velero backup describe $BACKUP_NAME --details=false | grep "Backup Size:" | awk '{print $3}')

echo "📊 Backup details:"
echo "  Items in backup: $ITEMS_IN_BACKUP"
echo "  Backup size: $BACKUP_SIZE"
echo ""

# Restore options
echo "📋 Select restore option:"
echo "1) Full restore (all namespaces and resources)"
echo "2) Namespace restore (restore to different namespace)"
echo "3) Selective restore (with resource filters)"
echo ""
read -p "Enter choice (1-3): " -n 1 -r RESTORE_CHOICE
echo ""

# Generate restore name with timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESTORE_NAME="restore-$BACKUP_NAME-$TIMESTAMP"

# Build restore command based on choice
case $RESTORE_CHOICE in
    1)
        echo "🔄 Full restore selected"
        RESTORE_CMD="velero restore create $RESTORE_NAME --from-backup $BACKUP_NAME --wait"
        RESTORE_TYPE="Full Restore"
        ;;
    2)
        read -p "Enter target namespace: " TARGET_NS
        echo "Creating target namespace if it doesn't exist..."
        kubectl create namespace "$TARGET_NS" --dry-run=client -o yaml | kubectl apply -f -
        
        RESTORE_CMD="velero restore create $RESTORE_NAME --from-backup $BACKUP_NAME --namespace-mappings velero-perf-test:$TARGET_NS --wait"
        RESTORE_TYPE="Namespace Restore (to $TARGET_NS)"
        ;;
    3)
        echo "Available resource filters:"
        echo "  --include-resources configmaps,secrets"
        echo "  --exclude-resources services"
        echo "  --include-namespaces ns1,ns2"
        echo "  --exclude-namespaces system-ns"
        echo ""
        read -p "Enter additional restore flags: " RESTORE_FLAGS
        RESTORE_CMD="velero restore create $RESTORE_NAME --from-backup $BACKUP_NAME $RESTORE_FLAGS --wait"
        RESTORE_TYPE="Selective Restore"
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "🚀 Starting $RESTORE_TYPE..."
echo "  Restore name: $RESTORE_NAME"
echo "  Command: $RESTORE_CMD"
echo ""

# Confirm before proceeding
read -p "⚠️  This will create/modify resources in your cluster. Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Restore cancelled"
    exit 0
fi

# Record start time
START_TIME=$(date +%s)
START_TIME_HUMAN=$(date)

echo "⏱️  Restore started at: $START_TIME_HUMAN"
echo ""

# Create log file
LOG_FILE="velero-restore-$RESTORE_NAME.log"
echo "📝 Logging to: $LOG_FILE"

# Start restore and monitor progress
echo "Starting restore..." | tee "$LOG_FILE"
echo "Command: $RESTORE_CMD" | tee -a "$LOG_FILE"
echo "Start time: $START_TIME_HUMAN" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Run restore command in background
$RESTORE_CMD 2>&1 | tee -a "$LOG_FILE" &
RESTORE_PID=$!

# Monitor progress
echo "📊 Monitoring restore progress..."
echo "   (Press Ctrl+C to stop monitoring, restore will continue)"
echo ""

# Wait for restore to appear
sleep 5

# Monitor loop
while kill -0 $RESTORE_PID 2>/dev/null; do
    # Get restore status
    STATUS=$(velero restore describe $RESTORE_NAME --details=false 2>/dev/null | grep "Phase:" | awk '{print $2}' || echo "Unknown")
    WARNINGS=$(velero restore describe $RESTORE_NAME --details=false 2>/dev/null | grep "Warnings:" | awk '{print $2}' || echo "0")
    ERRORS=$(velero restore describe $RESTORE_NAME --details=false 2>/dev/null | grep "Errors:" | awk '{print $2}' || echo "0")
    
    # Calculate elapsed time
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    ELAPSED_MIN=$((ELAPSED / 60))
    ELAPSED_SEC=$((ELAPSED % 60))
    
    # Show progress
    printf "\r⏳ Status: %-12s | Warnings: %-3s | Errors: %-3s | Elapsed: %02d:%02d" "$STATUS" "$WARNINGS" "$ERRORS" "$ELAPSED_MIN" "$ELAPSED_SEC"
    
    sleep 10
done

# Wait for background process to complete
wait $RESTORE_PID
RESTORE_EXIT_CODE=$?

echo ""
echo ""

# Record end time
END_TIME=$(date +%s)
END_TIME_HUMAN=$(date)
TOTAL_DURATION=$((END_TIME - START_TIME))
DURATION_MIN=$((TOTAL_DURATION / 60))
DURATION_SEC=$((TOTAL_DURATION % 60))

echo "⏱️  Restore completed at: $END_TIME_HUMAN" | tee -a "$LOG_FILE"
echo "⏰ Total duration: ${DURATION_MIN}m ${DURATION_SEC}s" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Get final restore details
echo "📊 Final Restore Results:" | tee -a "$LOG_FILE"
echo "=========================" | tee -a "$LOG_FILE"
velero restore describe $RESTORE_NAME | tee -a "$LOG_FILE"

# Calculate performance metrics and validate
if [ "$RESTORE_EXIT_CODE" -eq 0 ]; then
    echo ""
    echo "✅ Restore completed!" | tee -a "$LOG_FILE"
    
    # Extract metrics
    RESTORE_WARNINGS=$(velero restore describe $RESTORE_NAME --details=false | grep "Warnings:" | awk '{print $2}')
    RESTORE_ERRORS=$(velero restore describe $RESTORE_NAME --details=false | grep "Errors:" | awk '{print $2}')
    
    echo ""
    echo "📈 Performance Metrics:" | tee -a "$LOG_FILE"
    echo "  Items in backup: $ITEMS_IN_BACKUP" | tee -a "$LOG_FILE"
    echo "  Total time: ${DURATION_MIN}m ${DURATION_SEC}s" | tee -a "$LOG_FILE"
    echo "  Warnings: $RESTORE_WARNINGS" | tee -a "$LOG_FILE"
    echo "  Errors: $RESTORE_ERRORS" | tee -a "$LOG_FILE"
    
    if [ -n "$ITEMS_IN_BACKUP" ] && [ "$ITEMS_IN_BACKUP" -gt 0 ] && [ "$TOTAL_DURATION" -gt 0 ]; then
        RATE=$(( ITEMS_IN_BACKUP / TOTAL_DURATION ))
        echo "  Average rate: $RATE objects/second" | tee -a "$LOG_FILE"
        
        # Performance assessment
        if [ "$RATE" -lt 20 ]; then
            echo "  ⚠️  Performance: SLOW (< 20 objects/sec)" | tee -a "$LOG_FILE"
        elif [ "$RATE" -lt 100 ]; then
            echo "  ⚡ Performance: MODERATE (20-100 objects/sec)" | tee -a "$LOG_FILE"
        else
            echo "  🚀 Performance: FAST (> 100 objects/sec)" | tee -a "$LOG_FILE"
        fi
    fi
    
    # Success assessment
    if [ "$RESTORE_ERRORS" = "0" ]; then
        if [ "$RESTORE_WARNINGS" = "0" ]; then
            echo "  🎉 Status: PERFECT (no errors or warnings)" | tee -a "$LOG_FILE"
        else
            echo "  ✅ Status: SUCCESS (with $RESTORE_WARNINGS warnings)" | tee -a "$LOG_FILE"
        fi
    else
        echo "  ⚠️  Status: PARTIAL SUCCESS ($RESTORE_ERRORS errors, $RESTORE_WARNINGS warnings)" | tee -a "$LOG_FILE"
    fi
    
    echo ""
    echo "🔍 Validation suggestions:"
    echo "  1. Check restored resources:"
    case $RESTORE_CHOICE in
        1)
            echo "     kubectl get all,configmaps,secrets -l velero-test=performance --all-namespaces"
            ;;
        2)
            echo "     kubectl get all,configmaps,secrets -n $TARGET_NS"
            ;;
        3)
            echo "     kubectl get all,configmaps,secrets --all-namespaces"
            ;;
    esac
    echo "  2. Compare object counts with original"
    echo "  3. Validate application functionality"
    
else
    echo "❌ Restore failed!" | tee -a "$LOG_FILE"
    echo "Check the logs above for error details." | tee -a "$LOG_FILE"
fi

echo ""
echo "📄 Full restore details saved to: $LOG_FILE"
echo ""
echo "🔍 Additional commands:"
echo "  velero restore logs $RESTORE_NAME         # View detailed logs"
echo "  velero restore describe $RESTORE_NAME     # View restore details"
echo "  kubectl get all --all-namespaces          # Check restored resources"