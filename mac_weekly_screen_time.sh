#!/bin/bash

#===============================================================================
#
#          FILE:  mac_weekly_screen_time.sh
#
#         USAGE:  ./mac_weekly_screen_time.sh
#
#   DESCRIPTION:  Calculates the user's total "screen time" for each of the
#                 last 7 days. Screen time is defined as any period when the
#                 display is ON, regardless of lock screen status.
#
#       OPTIONS:  ---
#  REQUIREMENTS:  macOS, bash
#          BUGS:  ---
#         NOTES:  This version uses a more robust state-tracking logic and
#                 locale-independent date parsing to ensure accuracy on
#                 different system configurations.
#        AUTHOR:  Gemini
#       CREATED:  2024-06-28
#      REVISION:  7.0
#
#===============================================================================

# --- Configuration ---
# Set to 'true' to see a detailed step-by-step log of how the script is processing events.
ENABLE_DEBUG=false

# --- Function for logging debug messages ---
debug_log() {
    if [ "$ENABLE_DEBUG" = true ]; then
        echo "DEBUG: $1"
    fi
}

echo "Analyzing power logs for screen time (Display ON)..."

# --- Step 1: Parse all relevant display power events ---

# We only need to track when the display turns on and off.
event_log=$(pmset -g log | grep 'Display is turned')

# Process the raw log into a chronological list of events.
events=()
while IFS= read -r line; do
    timestamp_str=$(echo "$line" | awk -F ' ' '{print $1" "$2}')
    # Use LC_TIME=C to force standard C locale for date parsing.
    epoch_time=$(LC_TIME=C date -j -f "%Y-%m-%d %H:%M:%S" "$timestamp_str" "+%s" 2>/dev/null)
    
    if [ -z "$epoch_time" ]; then
        debug_log "Failed to parse date: $timestamp_str"
        continue
    fi

    event_type=""
    if [[ "$line" == *"Display is turned on"* ]]; then
        event_type="DISPLAY_ON"
    elif [[ "$line" == *"Display is turned off"* ]]; then
        event_type="DISPLAY_OFF"
    fi

    if [[ -n "$event_type" ]]; then
        events+=("$epoch_time $event_type")
    fi
done <<< "$event_log"

if [ ${#events[@]} -eq 0 ]; then
    echo "Error: Could not find any display power events in the system log."
    exit 1
fi

# --- Step 2: Process the event list to build "screen time sessions" ---

sessions=()
session_start_time=0

for event in "${events[@]}"; do
    event_time=$(echo "$event" | cut -d' ' -f1)
    event_type=$(echo "$event" | cut -d' ' -f2)

    if [[ "$event_type" == "DISPLAY_ON" ]]; then
        # A display on event starts a new session if one isn't already running.
        if [[ $session_start_time -eq 0 ]]; then
            debug_log "SCREEN TIME SESSION STARTED at $event_time"
            session_start_time=$event_time
        fi
    elif [[ "$event_type" == "DISPLAY_OFF" ]]; then
        # A display off event ends the current session.
        if [[ $session_start_time -gt 0 ]]; then
            debug_log "SCREEN TIME SESSION ENDED at $event_time. Duration: $((event_time - session_start_time))s"
            sessions+=("$session_start_time $event_time")
            session_start_time=0
        fi
    fi
done

# Handle the edge case where a session is still active when the script is run.
if [[ $session_start_time -gt 0 ]]; then
    current_time=$(date "+%s")
    debug_log "Ongoing session detected. Closing at current time: $current_time"
    sessions+=("$session_start_time $current_time")
fi

if [ ${#sessions[@]} -eq 0 ]; then
    echo "Warning: No complete screen time sessions were found in the log period."
fi

# --- Step 3: Calculate and display the daily screen time ---

# Print report header.
echo "-------------------------------------------------"
echo "        macOS Weekly Screen Time Report"
echo "-------------------------------------------------"
echo "Date         | Day       | Screen Time (HH:MM:SS)"
echo "-------------------------------------------------"

# Loop from 6 days ago to today (a total of 7 days).
for i in {6..0}; do
    target_date_str=$(date -v-${i}d "+%Y-%m-%d")
    day_name=$(date -v-${i}d "+%A")
    day_start_epoch=$(LC_TIME=C date -j -f "%Y-%m-%d %H:%M:%S" "$target_date_str 00:00:00" "+%s")
    day_end_epoch=$(LC_TIME=C date -j -f "%Y-%m-%d %H:%M:%S" "$target_date_str 23:59:59" "+%s")

    daily_total_seconds=0

    for session in "${sessions[@]}"; do
        session_start=$(echo "$session" | cut -d' ' -f1)
        session_end=$(echo "$session" | cut -d' ' -f2)

        overlap_start=$(( session_start > day_start_epoch ? session_start : day_start_epoch ))
        overlap_end=$(( session_end < day_end_epoch ? session_end : day_end_epoch ))

        duration=$((overlap_end - overlap_start))
        if (( duration > 0 )); then
            daily_total_seconds=$((daily_total_seconds + duration))
        fi
    done

    hours=$((daily_total_seconds / 3600))
    minutes=$(((daily_total_seconds % 3600) / 60))
    seconds=$((daily_total_seconds % 60))

    printf "%s | %-9s | %02d:%02d:%02d\n" "$target_date_str" "$day_name" $hours $minutes $seconds
done

echo "-------------------------------------------------"

