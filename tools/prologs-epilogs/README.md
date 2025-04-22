# Prologs and Epilogs

The following scripts function simultaneously as both prolog and epilog scripts
when used with the [external epilog and prolog][epe] feature of the
slurm_controller_instance module.

A typical approach is to stage these files to `/opt/apps/adm/slurm/scripts/` on
the controller and then use symbolic links pointing from the directories that
are iterated over by the `slurm_mux` external epilog and prolog feature.

## Included scripts

- [receive-data-path-manager](receive-data-path-manager): implements the Receive
  Data Path Manager solution for Google Cloud VM type a3-highgpu-8g
- [receive-data-path-manager-mega](receive-data-path-manager-mega): implements
  the Receive Data Path Manager solution for Google Cloud VM type a3-megagpu-8g
  - _WARNING_: This solution is in Public Preview and may be modified
    significantly or renamed as a3-megagpu-8g becomes Generally Available.
    Please review the [CHANGELOG](../../CHANGELOG.md) for announcements.
- [sudo-oslogin](sudo-oslogin): ensures that users who are configured with the
  [OS Admin Login role][os-admin-login] can run sudo during Slurm jobs
- [sudo-all-jobs-users](sudo-all-jobs-users): ensures that every job can run
  sudo; _this configuration is recommended only for debugging purposes_.

## GPU Health Checks

These scripts help monitor the health of GPU nodes within the Slurm cluster.

### `gpu_health_check.sh`

*   **Purpose**: Performs basic GPU diagnostics using `nvidia-smi` and `dcgm-diag -r 1` (level 1 tests).
*   **Usage**: Designed to be run by Slurm's `Prolog` and `Epilog` mechanisms.
    *   `Prolog={{ slurm_scripts_path }}/gpu_health_check.sh prolog`
    *   `Epilog={{ slurm_scripts_path }}/gpu_health_check.sh epilog`
    (Replace `{{ slurm_scripts_path }}` with the actual path, e.g., `/opt/slurm/scripts`).
    It can also be run manually with the `healthcheck` argument for testing.
*   **Failure Behavior**: If either `nvidia-smi` or `dcgm-diag` fails (returns a non-zero exit code), the script will log an error and attempt to drain the node using `scontrol update NodeName=$SLURMD_NODENAME State=DRAIN Reason='...'`.
*   **Dependencies**: `nvidia-smi`, `dcgm-diag`, `scontrol`.

### `nccl_health_check.sh`

*   **Purpose**: Performs a basic network communication health check between GPU nodes using NCCL. It verifies that two nodes can successfully run a small `nccl-tests` job (`all_reduce_perf`).
*   **Usage**: Designed to be run by Slurm's `HealthCheckProgram` mechanism.
    *   `HealthCheckProgram={{ slurm_scripts_path }}/nccl_health_check.sh`
    *   `HealthCheckInterval=<seconds>` (e.g., 600)
    *   `HealthCheckNodeState=IDLE` (Recommended to avoid interfering with running jobs)
    (Replace `{{ slurm_scripts_path }}` with the actual path).
*   **Operation**:
    1.  Identifies the current node (`$SLURMD_NODENAME`) and its partition (`$SLURM_JOB_PARTITION`).
    2.  Searches for another `IDLE` or `MIXED` node in the same partition using `sinfo`.
    3.  If a partner node is found, it launches a 2-node job (`srun --nodes=2 --ntasks=2 --ntasks-per-node=1 --gpus-per-task=<N> ...`) running `all_reduce_perf -g <N> ...`. The number of GPUs `<N>` is determined by checking `$CUDA_VISIBLE_DEVICES` (defaulting to 1).
    4.  If no partner node is available, the script exits successfully without running the test.
*   **Failure Behavior**: If the `srun` command executing `all_reduce_perf` fails, the script logs an error and attempts to drain the *current* node (the one where the health check is running) using `scontrol update NodeName=$SLURMD_NODENAME State=DRAIN Reason='NCCL health check failed...'`.
*   **Dependencies**: `sinfo`, `srun`, `scontrol`, `nccl-tests` (specifically `all_reduce_perf` must be in the PATH on compute nodes), `awk` (for GPU parsing).

## Directory pattern

For example, if the following symbolic links are created:

```
/opt/apps/adm/slurm/prolog_slurmd.d/start-rxdm.prolog_slurmd -> ../scripts/receive-data-path-manager
/opt/apps/adm/slurm/epilog_slurmd.d/stop-rxdm.epilog_slurmd -> ../scripts/receive-data-path-manager
```

Then the Receive Data Path Manager (RxDM) will be started before every user's
job and stopped upon job exit, whether successful or failed. They can otherwise
be run on a partition by partition basis, if they are placed in
partition-specific directories. In the example below, the partition is named
"a3":

```
/opt/apps/adm/slurm/partition-a3-prolog_slurmd.d/start-rxdm.prolog_slurmd -> ../scripts/receive-data-path-manager
/opt/apps/adm/slurm/partition-a3-epilog_slurmd.d/stop-rxdm.epilog_slurmd -> ../scripts/receive-data-path-manager
```

## Example implementation

The following sequence of commands will install the global prolog and epilog
shown above. It will download the script from the latest Slurm-GCP release.
`master` can be replaced with a specific tagged version if preferred.

```shell
#!/bin/bash
mkdir -p /opt/apps/adm/slurm/prolog_slurmd.d
mkdir -p /opt/apps/adm/slurm/epilog_slurmd.d
curl -s --create-dirs -o /opt/apps/adm/slurm/scripts/receive-data-path-manager \
    https://raw.githubusercontent.com/GoogleCloudPlatform/slurm-gcp/master/tools/prologs-epilogs/receive-data-path-manager
chmod 0755 /opt/apps/adm/slurm/scripts/
chmod 0755 /opt/apps/adm/slurm/scripts/receive-data-path-manager
ln -s /opt/apps/adm/slurm/scripts/receive-data-path-manager /opt/apps/adm/slurm/prolog_slurmd.d/start-rxdm.prolog_slurmd
ln -s /opt/apps/adm/slurm/scripts/receive-data-path-manager /opt/apps/adm/slurm/epilog_slurmd.d/stop-rxdm.epilog_slurmd
```

[epe]: ../../terraform/slurm_cluster/modules/slurm_files/README_TF.md#input_enable_external_prolog_epilog
[os-admin-login]: https://cloud.google.com/compute/docs/oslogin/set-up-oslogin#configure_users
