#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s /path/to/Rolls\n' "$(basename "$0")" >&2
  exit 64
fi

rolls_dir="$1"
if [[ ! -d "$rolls_dir" ]]; then
  printf 'Rolls directory not found: %s\n' "$rolls_dir" >&2
  exit 66
fi

bytes_for() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf '0'
    return
  fi
  find "$path" -type f -print0 | xargs -0 stat -f '%z' 2>/dev/null | awk '{ total += $1 } END { print total + 0 }'
}

mb() {
  awk -v bytes="$1" 'BEGIN { printf "%.2f", bytes / 1024 / 1024 }'
}

roll_count=0
total_first=0
total_second=0
total_blended=0
total_grid=0
total_roll=0

printf 'Roll storage in %s\n\n' "$rolls_dir"
printf '%-38s %10s %10s %10s %10s %10s\n' "Roll" "First MB" "Second MB" "Blend MB" "Grid MB" "Total MB"

for roll_dir in "$rolls_dir"/*; do
  [[ -d "$roll_dir" && -f "$roll_dir/roll.json" ]] || continue
  first=$(bytes_for "$roll_dir/first")
  second=$(bytes_for "$roll_dir/second")
  blended=$(bytes_for "$roll_dir/blended")
  grid=$(bytes_for "$roll_dir/grid.jpg")
  roll_total=$(bytes_for "$roll_dir")

  total_first=$((total_first + first))
  total_second=$((total_second + second))
  total_blended=$((total_blended + blended))
  total_grid=$((total_grid + grid))
  total_roll=$((total_roll + roll_total))
  roll_count=$((roll_count + 1))

  printf '%-38s %10s %10s %10s %10s %10s\n' \
    "$(basename "$roll_dir")" \
    "$(mb "$first")" \
    "$(mb "$second")" \
    "$(mb "$blended")" \
    "$(mb "$grid")" \
    "$(mb "$roll_total")"
done

printf '\n'
printf '%-38s %10s %10s %10s %10s %10s\n' \
  "TOTAL" \
  "$(mb "$total_first")" \
  "$(mb "$total_second")" \
  "$(mb "$total_blended")" \
  "$(mb "$total_grid")" \
  "$(mb "$total_roll")"

if [[ "$roll_count" -eq 0 ]]; then
  printf '\nNo roll directories with roll.json were found.\n'
  exit 0
fi

average=$((total_roll / roll_count))
completed_average=$(( (total_blended + total_grid) / roll_count ))

printf '\nAverage total per measured roll: %s MB\n' "$(mb "$average")"
printf 'Average completed-output footprint: %s MB\n' "$(mb "$completed_average")"
printf '\nProjected total storage from measured average:\n'
for count in 10 50 100 500; do
  projected=$((average * count))
  printf '  %3d rolls: %s MB\n' "$count" "$(mb "$projected")"
done
