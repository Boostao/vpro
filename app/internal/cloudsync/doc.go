// Package cloudsync (Layer 2) implements TLS-enforced PostgreSQL BECMaster
// synchronization across the isolated becmaster, staging, and standards schemas,
// including pre-upload compliance gating, rare-plant coordinate redaction,
// SERIALIZABLE Custodian 3-way merge, dated snapshots, and SHA-256 hash-chained audit.
package cloudsync
