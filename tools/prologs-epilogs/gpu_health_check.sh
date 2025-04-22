#!/bin/bash

# Script to perform GPU health checks for Slurm nodes.
# Arguments:
#   prolog: Run checks during Slurm prolog.
#   epilog: Run checks during Slurm epilog.
#   healthcheck: Run checks independently.

LOG_PREFIX="GPU_HEALTH_CHECK:"

log_error() {
  echo "$LOG_PREFIX ERROR: $@" >&2
}

log_info() {
  echo "$LOG_PREFIX INFO: $@" >&2
}

# Check for required argument
if [ "$#" -ne 1 ]; then
  log_error "Usage: $0 {prolog|epilog|healthcheck}"
  exit 1
fi

MODE=$1
log_info "Running in mode: $MODE"

# Source Slurm environment if available and get node name
# SLURMD_NODENAME is typically set for prolog/epilog scripts
if [ -z "$SLURMD_NODENAME" ]; then
    # If not set (e.g., running manually via healthcheck), try getting hostname
    SLURMD_NODENAME=$(hostname)
    log_info "SLURMD_NODENAME not set, using hostname: $SLURMD_NODENAME"
    if [ -z "$SLURMD_NODENAME" ]; then
        log_error "Could not determine hostname."
        exit 1
    fi
fi

log_info "Starting GPU health checks for node: $SLURMD_NODENAME"

# --- nvidia-smi check ---
log_info "Running nvidia-smi check..."
if ! nvidia-smi; then
  log_error "nvidia-smi command failed."
  log_error "Draining node $SLURMD_NODENAME due to nvidia-smi failure."
  # Drain the node
  if command -v scontrol &> /dev/null; then
    scontrol update NodeName=$SLURMD_NODENAME State=DRAIN Reason='GPU health check failed: nvidia-smi error'
    if [ $? -ne 0 ]; then
        log_error "scontrol command failed to drain node $SLURMD_NODENAME."
        exit 1 # Exit with error if scontrol fails
    fi
  else
      log_error "scontrol command not found. Cannot drain node $SLURMD_NODENAME."
      exit 1 # Exit with error if scontrol is missing
  fi
  exit 1 # Exit with error after attempting drain
fi
log_info "nvidia-smi check passed."

# --- dcgm-diag check ---
log_info "Running dcgm-diag check..."
# Use 'dcgm-diag -r 1' for a quick diagnostic check (level 1)
if ! dcgm-diag -r 1; then
  log_error "dcgm-diag -r 1 command failed."
  log_error "Draining node $SLURMD_NODENAME due to dcgm-diag failure."
  # Drain the node
  if command -v scontrol &> /dev/null; then
    scontrol update NodeName=$SLURMD_NODENAME State=DRAIN Reason='GPU health check failed: dcgm-diag error'
     if [ $? -ne 0 ]; then
        log_error "scontrol command failed to drain node $SLURMD_NODENAME."
        exit 1 # Exit with error if scontrol fails
    fi
  else
      log_error "scontrol command not found. Cannot drain node $SLURMD_NODENAME."
      exit 1 # Exit with error if scontrol is missing
  fi
  exit 1 # Exit with error after attempting drain
fi
log_info "dcgm-diag check passed."

log_info "GPU health checks completed successfully for node $SLURMD_NODENAME."
exit 0
