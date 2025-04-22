#!/bin/bash

# Script to perform NCCL health checks between Slurm nodes using nccl-tests.
# This script is intended to be run as a Slurm health check step or job.

LOG_PREFIX="NCCL_HEALTH_CHECK:"
NCCL_TEST_BINARY="all_reduce_perf" # Assumed to be in PATH or standard location
SRUN_TIMEOUT="0:05:00" # 5 minutes timeout for the srun command

log_error() {
  echo "$LOG_PREFIX ERROR: $@" >&2
}

log_warning() {
  echo "$LOG_PREFIX WARNING: $@" >&2
}

log_info() {
  echo "$LOG_PREFIX INFO: $@" >&2
}

# --- Check for necessary commands ---
for cmd in sinfo srun scontrol $NCCL_TEST_BINARY; do
  if ! command -v $cmd &> /dev/null; then
    log_error "Required command '$cmd' not found in PATH."
    exit 1
  fi
done
log_info "All required commands (sinfo, srun, scontrol, $NCCL_TEST_BINARY) found."

# --- Get current node name ---
# SLURMD_NODENAME is typically set for healthcheck scripts run by Slurm
CURRENT_NODE=$SLURMD_NODENAME
if [ -z "$CURRENT_NODE" ]; then
    # If not set, try getting hostname
    log_warning "SLURMD_NODENAME not set, attempting to use hostname."
    CURRENT_NODE=$(hostname -s) # Use short hostname
    if [ -z "$CURRENT_NODE" ]; then
        log_error "Could not determine current node name."
        exit 1
    fi
fi
log_info "Running NCCL health check on node: $CURRENT_NODE"

# --- Get partition ---
CURRENT_PARTITION=$SLURM_JOB_PARTITION
if [ -z "$CURRENT_PARTITION" ]; then
    log_error "SLURM_JOB_PARTITION environment variable is not set. Cannot determine partition."
    exit 1 # Cannot find partners without partition info
fi
log_info "Current node $CURRENT_NODE is in partition: $CURRENT_PARTITION"

# --- Identify allocated GPUs ---
# Try to count GPUs from CUDA_VISIBLE_DEVICES, default to 1 otherwise.
# This assumes the health check job/step itself has GPUs allocated and visible.
GPUS_PER_TASK=1 # Default
if [ -n "$CUDA_VISIBLE_DEVICES" ]; then
    # Count comma-separated devices
    NUM_GPUS=$(echo "$CUDA_VISIBLE_DEVICES" | awk -F ',' '{print NF}')
    if [[ "$NUM_GPUS" -gt 0 ]]; then
        GPUS_PER_TASK=$NUM_GPUS
        log_info "Detected $GPUS_PER_TASK GPUs from CUDA_VISIBLE_DEVICES ($CUDA_VISIBLE_DEVICES)."
    else
        log_warning "CUDA_VISIBLE_DEVICES is set ('$CUDA_VISIBLE_DEVICES') but couldn't parse GPU count, defaulting to $GPUS_PER_TASK GPU per task."
    fi
else
    log_warning "CUDA_VISIBLE_DEVICES not set, defaulting to $GPUS_PER_TASK GPU per task."
fi
# Ensure we request at least 1 GPU per task
if [[ "$GPUS_PER_TASK" -lt 1 ]]; then
    log_warning "Calculated GPUs per task is less than 1, setting to 1."
    GPUS_PER_TASK=1
fi
log_info "Will request $GPUS_PER_TASK GPU(s) per task for the NCCL test."


# --- Find a partner node ---
log_info "Searching for an IDLE or MIXED partner node in partition '$CURRENT_PARTITION' (excluding $CURRENT_NODE)..."
# Use sinfo to find nodes, exclude the current node, take the first one
PARTNER_NODE=$(sinfo -N -h -p "$CURRENT_PARTITION" -t IDLE,MIXED --format="%N" | grep -v "^${CURRENT_NODE}$" | head -n 1)

if [ -z "$PARTNER_NODE" ]; then
  log_warning "No suitable IDLE or MIXED partner node found in partition '$CURRENT_PARTITION' (excluding $CURRENT_NODE)."
  log_warning "Skipping NCCL check for $CURRENT_NODE as no partner is available."
  exit 0 # Not a failure of the current node
fi
log_info "Found partner node: $PARTNER_NODE"

# --- Construct and run srun NCCL test ---
NODELIST="$CURRENT_NODE,$PARTNER_NODE"
log_info "Launching NCCL test ($NCCL_TEST_BINARY) between $CURRENT_NODE and $PARTNER_NODE..."

# Basic nccl-test parameters: -b 8 (start size), -e 128M (end size), -f 2 (factor), -g N (gpus), -c 1 (check correctness)
# The -g parameter for all_reduce_perf should match the number of GPUs requested per task.
SRUN_CMD="srun --nodelist=$NODELIST --ntasks=2 --ntasks-per-node=1 --gpus-per-task=$GPUS_PER_TASK --time=$SRUN_TIMEOUT $NCCL_TEST_BINARY -b 8 -e 128M -f 2 -g $GPUS_PER_TASK -c 1"

log_info "Executing: $SRUN_CMD"

# Execute the command and capture output/error for logging if needed
if $SRUN_CMD; then
  log_info "NCCL test ($NCCL_TEST_BINARY) completed successfully between $CURRENT_NODE and $PARTNER_NODE."
else
  SRUN_EXIT_CODE=$?
  log_error "NCCL test ($NCCL_TEST_BINARY) failed between $CURRENT_NODE and $PARTNER_NODE (srun exit code: $SRUN_EXIT_CODE)."
  log_error "Draining node $CURRENT_NODE due to NCCL health check failure."

  # Drain the current node
  scontrol update NodeName=$CURRENT_NODE State=DRAIN Reason="NCCL health check failed with $PARTNER_NODE"
  if [ $? -ne 0 ]; then
      log_error "scontrol command failed to drain node $CURRENT_NODE."
      # Still exit non-zero because the NCCL test failed
  else
      log_info "Successfully drained node $CURRENT_NODE."
  fi
  exit 1 # Exit with error because NCCL test failed
fi

exit 0
