# Changelog

## [Unreleased]

### Changed
* Relocate boot scaffold to `/etc/nullstone/` (manifests, `load-app-secrets.sh`, `mount-disks.sh`) so cloud-init write_files work on Container-Optimized OS read-only root.

