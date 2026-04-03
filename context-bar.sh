#!/bin/bash

input=$(cat)

# Extract model, directory, and cwd
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "?"')
[[ "$model" == "null" ]] && model="?"
cwd=$(echo "$input" | jq -r '.cwd // empty')
[[ "$cwd" == "null" ]] && cwd=""
dir=$(basename "$cwd" 2>/dev/null || echo "?")
[[ -z "$dir" ]] && dir="?"

# Get git branch, uncommitted file count, and sync status
branch=""
git_status=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    if [[ -n "$branch" ]]; then
        # Count uncommitted files
        file_count=$(git -C "$cwd" --no-optional-locks status --porcelain -uall 2>/dev/null | wc -l | tr -d ' ')

        # Check sync status with upstream
        sync_status=""
        upstream=$(git -C "$cwd" rev-parse --abbrev-ref @{upstream} 2>/dev/null)
        if [[ -n "$upstream" ]]; then
            # Get last fetch time
            fetch_head="$cwd/.git/FETCH_HEAD"
            fetch_ago=""
            if [[ -f "$fetch_head" ]]; then
                fetch_time=$(stat -f %m "$fetch_head" 2>/dev/null || stat -c %Y "$fetch_head" 2>/dev/null)
                if [[ -n "$fetch_time" ]]; then
                    now=$(date +%s)
                    diff=$((now - fetch_time))
                    if [[ $diff -lt 60 ]]; then
                        fetch_ago="<1m ago"
                    elif [[ $diff -lt 3600 ]]; then
                        fetch_ago="$((diff / 60))m ago"
                    elif [[ $diff -lt 86400 ]]; then
                        fetch_ago="$((diff / 3600))h ago"
                    else
                        fetch_ago="$((diff / 86400))d ago"
                    fi
                fi
            fi

            counts=$(git -C "$cwd" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
            ahead=$(echo "$counts" | cut -f1)
            behind=$(echo "$counts" | cut -f2)
            if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
                if [[ -n "$fetch_ago" ]]; then
                    sync_status="synced ${fetch_ago}"
                else
                    sync_status="synced"
                fi
            elif [[ "$ahead" -gt 0 && "$behind" -eq 0 ]]; then
                sync_status="${ahead} ahead"
            elif [[ "$ahead" -eq 0 && "$behind" -gt 0 ]]; then
                sync_status="${behind} behind"
            else
                sync_status="${ahead} ahead, ${behind} behind"
            fi
        else
            sync_status="no upstream"
        fi

        # Build git status string
        if [[ "$file_count" -eq 0 ]]; then
            git_status="(0 files uncommitted, ${sync_status})"
        elif [[ "$file_count" -eq 1 ]]; then
            # Show the actual filename when only one file is uncommitted
            single_file=$(git -C "$cwd" --no-optional-locks status --porcelain -uall 2>/dev/null | head -1 | sed 's/^...//')
            git_status="(${single_file} uncommitted, ${sync_status})"
        else
            git_status="(${file_count} files uncommitted, ${sync_status})"
        fi
    fi
fi

# Get transcript path for last message feature
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

# --- Plan usage: read directly from status line input JSON (no API calls needed) ---

# Helper: epoch -> local 12-hour time, strip leading zero from hour
epoch_to_time() {
    local ep="$1"
    local raw
    raw=$(date -r "$ep" "+%I:%M %p" 2>/dev/null \
       || date -d "@$ep" "+%I:%M %p" 2>/dev/null)
    echo "${raw#0}"
}

# Helper: epoch -> local day abbreviation + 12-hour time
epoch_to_day_time() {
    local ep="$1"
    local day raw_time
    day=$(date -r "$ep" "+%a" 2>/dev/null || date -d "@$ep" "+%a" 2>/dev/null)
    raw_time=$(date -r "$ep" "+%I:%M %p" 2>/dev/null \
            || date -d "@$ep" "+%I:%M %p" 2>/dev/null)
    echo "$day ${raw_time#0}"
}

# Read rate limits from the input JSON that Claude Code provides
five_util=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
week_util=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
week_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)

parts=()
plan_str=""

if [[ -n "$five_util" ]]; then
    five_pct="${five_util%.*}%"
    five_part="Session ${five_pct}"
    if [[ -n "$five_resets" ]]; then
        five_time=$(epoch_to_time "$five_resets")
        [[ -n "$five_time" ]] && five_part+=" resets at ${five_time}"
    fi
    parts+=("$five_part")
fi

if [[ -n "$week_util" ]]; then
    week_pct="${week_util%.*}%"
    week_part="Week ${week_pct}"
    if [[ -n "$week_resets" ]]; then
        week_time=$(epoch_to_day_time "$week_resets")
        [[ -n "$week_time" ]] && week_part+=" resets ${week_time}"
    fi
    parts+=("$week_part")
fi

if [[ ${#parts[@]} -gt 0 ]]; then
    for part in "${parts[@]}"; do
        if [[ -z "$plan_str" ]]; then
            plan_str="$part"
        else
            plan_str+=" | $part"
        fi
    done
fi

# Build output: Model | Dir | Branch (uncommitted) | Plan usage
output="${model} | 📁${dir}"
[[ -n "$branch" ]] && output+=" | 🔀${branch} ${git_status}"
[[ -n "$plan_str" ]] && output+=" | ${plan_str}"

# Get user's last message (text only, not tool results, skip unhelpful messages)
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    max_len=${#output}
    last_user_msg=$(jq -rs '
        # Messages to skip (not useful as context)
        def is_unhelpful:
            startswith("[Request interrupted") or
            startswith("[Request cancelled") or
            . == "";

        [.[] | select(.type == "user") |
         select(.message.content | type == "string" or
                (type == "array" and any(.[]; .type == "text")))] |
        reverse |
        map(.message.content |
            if type == "string" then .
            else [.[] | select(.type == "text") | .text] | join(" ") end |
            gsub("\n"; " ") | gsub("  +"; " ")) |
        map(select(is_unhelpful | not)) |
        first // ""
    ' < "$transcript_path" 2>/dev/null)

    if [[ -n "$last_user_msg" ]]; then
        if [[ ${#last_user_msg} -gt $max_len ]]; then
            printf '%s\n💬 %s\n' "$output" "${last_user_msg:0:$((max_len - 3))}..."
        else
            printf '%s\n💬 %s\n' "$output" "$last_user_msg"
        fi
    else
        printf '%s\n' "$output"
    fi
else
    printf '%s\n' "$output"
fi
