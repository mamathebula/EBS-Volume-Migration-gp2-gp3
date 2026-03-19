# EBS Volume Migration: gp2 → gp3

Bash script that finds all gp2 EBS volumes in your AWS account and migrates them to gp3 in batches.

## Why Migrate?

| | gp2 | gp3 |
|---|---|---|
| Price | $0.10/GB/month | $0.08/GB/month |
| Baseline IOPS | 100 IOPS per GB (up to 16,000) | 3,000 IOPS (free, regardless of size) |
| Baseline Throughput | 128–250 MB/s (depends on size) | 125 MB/s (free) |
| Max IOPS | 16,000 | 16,000 |
| Max Throughput | 250 MB/s | 1,000 MB/s |

gp3 is 20% cheaper and gives you 3,000 IOPS baseline on every volume — even a 1 GB volume. With gp2, a 1 GB volume only gets 100 IOPS.

### Example Savings

| Volume Size | gp2 Cost | gp3 Cost | Monthly Savings |
|-------------|----------|----------|-----------------|
| 100 GB | $10.00 | $8.00 | $2.00 |
| 500 GB | $50.00 | $40.00 | $10.00 |
| 1 TB | $100.00 | $80.00 | $20.00 |
| 10 x 100 GB | $100.00 | $80.00 | $20.00 |

## Usage

| Command | What It Does |
|---------|-------------|
| `./migrate-gp2-to-gp3.sh` | Migrates gp2 volumes in your current configured region only |
| `./migrate-gp2-to-gp3.sh --all-regions` | Loops through every AWS region and migrates gp2 volumes in each |
| `export AWS_REGION=us-west-1 && ./migrate-gp2-to-gp3.sh` | Migrates gp2 volumes in a specific region |

## Prerequisites

- AWS CLI installed and configured (`aws configure`)
- Permissions: `ec2:DescribeVolumes` and `ec2:ModifyVolume`

## Run

### Option 1: Local Terminal

**Step 1: Set up AWS credentials** (skip if already configured)

```bash
aws configure
```

**Step 2: Verify credentials**

```bash
aws sts get-caller-identity
```

**Step 3: Run the script**

Single region (current region):

```bash
chmod +x migrate-gp2-to-gp3.sh
./migrate-gp2-to-gp3.sh
```

All regions:

```bash
chmod +x migrate-gp2-to-gp3.sh
./migrate-gp2-to-gp3.sh --all-regions
```

### Option 2: AWS CloudShell

1. Log into the AWS Console
2. Open CloudShell (terminal icon, top right)
3. Make sure you're in the correct region
4. Click Actions → Upload file → select `migrate-gp2-to-gp3.sh`
5. If re-uploading, delete the old file first:

```bash
rm migrate-gp2-to-gp3.sh
```

6. Run:

Single region:

```bash
chmod +x migrate-gp2-to-gp3.sh
./migrate-gp2-to-gp3.sh
```

All regions:

```bash
chmod +x migrate-gp2-to-gp3.sh
./migrate-gp2-to-gp3.sh --all-regions
```

## What Happens

1. Script finds all gp2 volumes in the current region (or all regions with `--all-regions`)
2. Shows you a list with volume ID, size, state, and what instance it's attached to
3. Asks for confirmation before proceeding (per region)
   - `y` = migrate this region
   - `n` = skip this region
   - `a` = migrate this region and auto-approve all remaining regions
4. Migrates in batches of 10 (5-second pause between batches to avoid throttling)
5. Migrations happen in the background — the volume stays online during migration

## Check Migration Status

After running the script, check progress with:

```bash
aws ec2 describe-volumes-modifications \
  --filters Name=modification-state,Values=modifying \
  --query "VolumesModifications[*].[VolumeId,OriginalVolumeType,TargetVolumeType,Progress]" \
  --output table
```

Check completed migrations:

```bash
aws ec2 describe-volumes-modifications \
  --filters Name=modification-state,Values=completed \
  --query "VolumesModifications[*].[VolumeId,OriginalVolumeType,TargetVolumeType]" \
  --output table
```

## Important Notes

- Migration is online — no downtime, no detach required. Volumes stay attached and usable
- Migration typically takes a few minutes to a few hours depending on volume size
- You can only modify a volume once every 6 hours. If a volume was recently modified, it will fail and the script will show an error for that volume
- If a volume is managed by CloudFormation, this will cause stack drift (same as the Lambda runtime updater). Update the template afterwards to match
- The script only targets the current region. Run it again with a different `AWS_REGION` for multi-region accounts
- There is no cost for the migration itself — you only pay the new gp3 price going forward

## Advantages of gp3 over gp2

- 20% cheaper — $0.08/GB vs $0.10/GB, same storage, lower price
- 3,000 IOPS baseline on every volume regardless of size (gp2 needs 1 TB to reach 3,000 IOPS)
- Performance is independent from capacity — you can provision IOPS and throughput separately without increasing volume size
- Higher max IOPS — gp3 supports up to 80,000 IOPS per volume vs 16,000 on gp2
- Higher max throughput — gp3 supports up to 2,000 MB/s vs 250 MB/s on gp2
- Larger max volume size — gp3 supports up to 64 TiB vs 16 TiB on gp2
- Online migration — no downtime, no detach, volume stays usable during conversion
- No migration cost — you only pay the new gp3 price going forward

## Disadvantages / Things to Watch

- If you have gp2 volumes larger than 5.3 TB, they get more than 16,000 IOPS from the 3 IOPS/GB formula. On gp3, you'd need to provision additional IOPS ($0.005/IOPS-month) to match — this could cost more
- Extra IOPS above 3,000 costs $0.005 per provisioned IOPS-month
- Extra throughput above 125 MB/s costs $0.04 per provisioned MB/s-month
- If your workload relies on gp2 burst credits (small volumes bursting to 3,000 IOPS), gp3 gives you 3,000 IOPS baseline instead — same performance, but no burst above that without provisioning
- Volumes can only be modified once every 6 hours — if a migration fails, you have to wait before retrying
- If volumes are managed by CloudFormation, this causes stack drift (update the template afterwards)
- The script migrates with default gp3 settings (3,000 IOPS, 125 MB/s throughput). If you need higher performance, adjust IOPS/throughput after migration
- Migrations run in batches of 10 with a 5-second pause between batches to avoid AWS API throttling. If you have hundreds or thousands of volumes, the script handles it automatically — it just takes longer (e.g., 1,000 volumes = 100 batches ≈ 8–10 minutes of API calls, plus background migration time)

For full details, see the [AWS Prescriptive Guidance: Migrate EBS volumes from gp2 to gp3](https://docs.aws.amazon.com/prescriptive-guidance/latest/optimize-costs-microsoft-workloads/ebs-migrate-gp2-gp3.html).

## Risks

Low risk. This is a safe migration:

- No downtime — volume stays online
- No data loss — it's a type change, not a copy
- Performance is equal or better (3,000 IOPS baseline vs potentially less on small gp2 volumes)
- If you need more than 3,000 IOPS or 125 MB/s throughput on gp3, you can provision extra (at additional cost)

The only edge case: if you have a gp2 volume larger than 5.3 TB, it gets more than 16,000 IOPS on gp2 (3 IOPS/GB). On gp3, you'd need to provision additional IOPS to match. This is rare.

## What Gets Deployed

Nothing. This is a standalone bash script. It does not create any AWS resources — it only calls the EC2 API to modify existing volumes.

## Multi-Region

Run with `--all-regions` to scan and migrate across every AWS region:

```bash
./migrate-gp2-to-gp3.sh --all-regions
```

The script will loop through all regions, show you gp2 volumes in each, and ask for confirmation per region. Press `a` at any prompt to auto-approve all remaining regions.

To run for a specific region without `--all-regions`:

```bash
export AWS_REGION=eu-west-1
./migrate-gp2-to-gp3.sh
```
