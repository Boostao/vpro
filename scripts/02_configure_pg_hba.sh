#!/bin/bash
# Copy custom pg_hba.conf and reload configuration
set -e

echo "Configuring pg_hba.conf for vpro_default trust authentication..."
cp /docker-entrypoint-initdb.d/pg_hba_custom.conf /var/lib/postgresql/data/pg_hba.conf
chown postgres:postgres /var/lib/postgresql/data/pg_hba.conf
chmod 600 /var/lib/postgresql/data/pg_hba.conf

# PostgreSQL will automatically load the new pg_hba.conf on startup
echo "pg_hba.conf configured successfully"
