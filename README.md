# gcp-gce-server

Creates a Google Cloud Compute Engine VM.

## Disk Attachment

If you attach a disk to the instance (usually through a capability), this module will mount it to the instance.
It is mounted at `/mnt/<device-name>` where the `device_name` is configured by the capability.
