#!/bin/bash

# Function to show help message
show_help() {
  echo "Usage: $0 [-t duration_in_seconds] [-i ip_address] [-f file_to_ping_results.txt] [-p ping_interval] [-r] [-c] [-P] [-R]"
  echo
  echo "Options:"
  echo "  -t duration_in_seconds  The amount of time to collect data for, in seconds. Default: 10800 seconds (3 hours)"
  echo "  -i ip_address           The IP address to ping. Default: 8.8.8.8"
  echo "  -f file_to_ping_results.txt  Path to an existing text file with ping results"
  echo "  -p ping_interval        The interval between each ping in seconds. Default: 1 second"
  echo "  -r                      Reset the configuration file to default values"
  echo "  -c                      Clear all results and plots (with confirmation)"
  echo "  -P                      Clear all plots (with confirmation)"
  echo "  -R                      Clear all results (with confirmation)"
  echo "  -h                      Show this help message and exit"
}

# Configuration file
config_file="config.yaml"

# Default configuration values
default_config=$(cat <<EOL
# Default configuration values
duration: 10800
ip_address: "8.8.8.8"
interval: 1

# Plotting settings
plot:
  figure_size: [20, 15]
  dpi: 100
  theme: "darkgrid"
  font:
    title_size: 24
    label_size: 22
    tick_size: 20
    legend_size: 20

# Data aggregation settings
aggregation:
  method: "mean"  # Options: mean, median, min, max
  interval: 60    # Aggregation interval in seconds

# Data segmentation settings
segmentation:
  hourly: true

# Folder paths
results_folder: "results"
plots_folder: "plots"
log_folder: "logs"
EOL
)

# Function to create a default configuration file
create_default_config() {
  echo "$default_config" > $config_file
  echo "Default configuration file created: $config_file"
}

# Check if configuration file exists
if [ ! -f $config_file ]; then
  create_default_config
fi

# Function to read values from the YAML configuration file using Python
read_config() {
  python3 -c "
import yaml
import sys

config_file = '$config_file'
with open(config_file, 'r') as f:
    config = yaml.safe_load(f)

print(config.get('$1', ''))
"
}

# Load configuration values
duration=$(read_config 'duration')
ip_address=$(read_config 'ip_address')
interval=$(read_config 'interval')
results_folder=$(read_config 'results_folder')
plots_folder=$(read_config 'plots_folder')
log_folder=$(read_config 'log_folder')

# Use default values if variables are empty
results_folder=${results_folder:-"results"}
plots_folder=${plots_folder:-"plots"}
log_folder=${log_folder:-"logs"}

# Parse arguments
while getopts "t:i:f:p:hrcPR" opt; do
  case $opt in
    t) duration=$OPTARG ;;
    i) ip_address=$OPTARG ;;
    f) text_file=$OPTARG ;;
    p) interval=$OPTARG ;;
    r) reset_config=true ;;
    c) clear_all=true ;;
    P) clear_plots=true ;;
    R) clear_results=true ;;
    h) show_help; exit 0 ;;
    \?) show_help; exit 1 ;;
  esac
done

# Handle reset configuration file option
if [ "$reset_config" = true ]; then
  create_default_config
  echo "Configuration file has been reset to default values."
  exit 0
fi

# Function to confirm action
confirm() {
  read -p "Are you sure you want to $1? (y/n): " choice
  case "$choice" in
    y|Y ) return 0 ;;
    * ) return 1 ;;
  esac
}

# Function to clear results
clear_results() {
  rm -rf "$results_folder"/*
  echo "All results have been cleared."
}

# Function to clear plots
clear_plots() {
  rm -rf "$plots_folder"/*
  echo "All plots have been cleared."
}

# Handle clear options with confirmation
if [ "$clear_all" = true ]; then
  if confirm "clear all results and plots"; then
    clear_results
    clear_plots
  else
    echo "Operation cancelled."
  fi
  exit 0
fi

if [ "$clear_results" = true ]; then
  if confirm "clear all results"; then
    clear_results
  else
    echo "Operation cancelled."
  fi
  exit 0
fi

if [ "$clear_plots" = true ]; then
  if confirm "clear all plots"; then
    clear_plots
  else
    echo "Operation cancelled."
  fi
  exit 0
fi

# Create necessary directories
mkdir -p $results_folder
mkdir -p $plots_folder
mkdir -p $log_folder

# Get the current date and time in a more user-friendly format
current_date=$(date +%Y-%m-%d_%H-%M-%S)
log_file="$log_folder/monitor_ping_$current_date.log"

# Log function
log() {
  echo "$(date +%Y-%m-%d_%H-%M-%S) - $1" | tee -a $log_file
}

log "Script started"

# Check for conflicting options
if [ -n "$text_file" ]; then
  if [ -n "$duration" ] || [ -n "$ip_address" ]; then
    log "Warning: Ignoring -t and -i options because a file was provided with -f"
  fi
fi

log "Parsed arguments: duration=$duration, ip_address=$ip_address, text_file=$text_file, interval=$interval"

# Define the filename for the ping results
results_file="$results_folder/ping_results_$current_date.txt"

# Function to draw progress bar
draw_progress_bar() {
  local progress=$1
  local total_width=50
  local complete_width=$((progress * total_width / 100))
  local incomplete_width=$((total_width - complete_width))

  # Colors (using ANSI escape codes)
  local green="\033[42m"
  local red="\033[41m"
  local reset="\033[0m"

  # Create progress bar with color
  local bar=""
  for ((i=0; i<complete_width; i++)); do
    bar="${bar}${green} ${reset}"
  done
  for ((i=0; i<incomplete_width; i++)); do
    bar="${bar}${red} ${reset}"
  done

  printf "\rProgress: [${bar}] %d%%" "$progress"
}

# If a text file is provided, use it, otherwise run the ping command
if [ -n "$text_file" ]; then
  cp "$text_file" "$results_file"
  log "Copied text file $text_file to $results_file"
else
  log "Running ping command: ping -i $interval -w $duration $ip_address"
  ping -i $interval -w $duration $ip_address > $results_file &
  ping_pid=$!

  # Track progress
  start_time=$(date +%s)
  while kill -0 $ping_pid 2> /dev/null; do
    current_time=$(date +%s)
    elapsed_time=$((current_time - start_time))
    progress=$((elapsed_time * 100 / duration))

    draw_progress_bar $progress
    sleep 1
  done

  # Final progress update to 100%
  draw_progress_bar 100
  echo

  # Wait for ping to complete
  wait $ping_pid
  echo -e "\nPing command completed."

  # Extract packet loss information and append to results file
  packet_loss=$(grep -oP '\d+(?=% packet loss)' $results_file | tail -1)
  echo "Packet Loss: $packet_loss%" >> $results_file
  log "Packet loss information appended to results file"
fi

# Run the Python script to generate the plots
log "Running Python script to generate plots"
python3 generate_plots.py $results_file $plots_folder $duration $ip_address $interval 2>&1 | tee -a $log_file
log "Python script completed"
