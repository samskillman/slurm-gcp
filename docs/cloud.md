# Cloud Cluster Guide

[FAQ](./faq.md) | [Troubleshooting](./troubleshooting.md) |
[Glossary](./glossary.md)

<!-- mdformat-toc start --slug=github --no-anchors --maxlevel=6 --minlevel=1 -->

- [Cloud Cluster Guide](#cloud-cluster-guide)
  - [Overview](#overview)
  - [GCP Marketplace](#gcp-marketplace)
  - [Terraform](#terraform)
    - [Quickstart Examples](#quickstart-examples)

<!-- mdformat-toc end -->

## Overview

This guide focuses on setting up a cloud [Slurm cluster](./glossary.md#slurm).
With cloud, there are decisions that need to be made and certain considerations
taken into account. This guide will cover them and their recommended solutions.

There are two deployment methods for cloud cluster management:

- [GCP Marketplace](#gcp-marketplace)
- [Terraform](#terraform)

## GCP Marketplace

This deployment method leverages
[GCP Marketplace](./glossary.md#gcp-marketplace) to make setting up clusters a
breeze without leaving your browser. While this method is simpler and less
flexible, it is great for exploring what `slurm-gcp` is!

See the [Marketplace Guide](./marketplace.md) for setup instructions and more
information.

## Terraform

This deployment method leverages [Terraform](./glossary.md#terraform) to deploy
and manage cluster infrastructure. While this method can be more complex, it is
a robust option. `slurm-gcp` provides terraform modules that enables you to
create a Slurm cluster with ease.

See the [slurm_cluster module](../terraform/slurm_cluster/README.md) for
details.

If you are unfamiliar with [terraform](./glossary.md#terraform), then please
checkout out the [documentation](https://www.terraform.io/docs) and
[starter guide](https://learn.hashicorp.com/collections/terraform/gcp-get-started)
to get you familiar.

### Quickstart Examples

See the [test cluster][test-cluster] example for an extensible and robust
example. It can be configured to handle creation of all supporting resources
(e.g. network, service accounts) or leave that to you. Slurm can be configured
with partitions and nodesets as desired.

> **NOTE:** It is recommended to use the
> [slurm_cluster module](../terraform/slurm_cluster/README.md) in your own
> [terraform project](./glossary.md#terraform-project). It may be useful to copy
> and modify one of the provided examples.

Alternatively, see
[HPC Blueprints](https://cloud.google.com/hpc-toolkit/docs/setup/hpc-blueprint)
for
[HPC Toolkit](https://cloud.google.com/blog/products/compute/new-google-cloud-hpc-toolkit)
examples.

### GPU Health Checking

To improve the reliability of clusters utilizing GPUs, `slurm-gcp` includes optional health checking scripts that can automatically detect certain GPU issues and drain the affected node to prevent jobs from running on faulty hardware.

Two scripts are involved:

*   **`gpu_health_check.sh`**: Performs node-local checks using `nvidia-smi` and `dcgm-diag`. It is typically run before and after each job using Slurm's `Prolog` and `Epilog` mechanisms.
*   **`nccl_health_check.sh`**: Performs a basic network communication check between two GPU nodes using `nccl-tests` (`all_reduce_perf`) launched via `srun`. It is designed to run periodically on idle nodes using Slurm's `HealthCheckProgram`.

These health checks are configured and deployed via the `slurm` Ansible role included in the Terraform setup. The role copies the scripts to the compute nodes and configures the following parameters in `slurm.conf`:

*   `Prolog={{ slurm_paths.scripts }}/gpu_health_check.sh prolog`
*   `Epilog={{ slurm_paths.scripts }}/gpu_health_check.sh epilog`
*   `HealthCheckProgram={{ slurm_paths.scripts }}/nccl_health_check.sh`
*   `HealthCheckInterval=600` (or as configured)
*   `HealthCheckNodeState=IDLE` (or as configured)

**Dependencies:**

For these health checks to function correctly, the following dependencies must be available on the compute node images:
*   `nvidia-smi` (typically part of the NVIDIA driver installation)
*   `dcgm-diag` (part of the NVIDIA Data Center GPU Manager)
*   `nccl-tests` (specifically the `all_reduce_perf` binary must be in the default PATH)
*   Standard Slurm commands (`sinfo`, `srun`, `scontrol`) and Linux utilities (`awk`).

For more detailed information on the scripts themselves, see the `tools/prologs-epilogs/README.md` file.

<!-- Links -->

[test-cluster]: ../terraform/slurm_cluster/examples/slurm_cluster/test_cluster/README.md
