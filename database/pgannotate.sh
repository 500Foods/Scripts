#!/bin/bash

SCHEMA=$1
DEST_DIR=$2

if [[ -z "$SCHEMA" || -z "$DEST_DIR" ]]; then
    echo "Usage: $0 <schema> <destination_directory>"
    exit 1
fi

mkdir -p "$DEST_DIR"

# Get database connection info from .pgpass
PGPASS_LINE=$(head -n1 ~/.pgpass)
IFS=':' read -r HOST PORT DATABASE USER PASSWORD <<< "$PGPASS_LINE"

export PGPASSWORD="$PASSWORD"

# Get all tables in schema
TABLES=$(psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" -t -c "SELECT table_name FROM information_schema.tables WHERE table_schema='$SCHEMA' ORDER BY table_name;")

for TABLE in $TABLES; do
    TABLE=$(echo $TABLE | xargs) # trim whitespace
    FULL_TABLE="$SCHEMA.$TABLE"
    
    # Generate DDL
    DDL=$(psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" -t -c "SELECT pg_get_tabledef('$FULL_TABLE'::regclass);")
    
    # Get primary key
    PK=$(psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" -t -c "SELECT string_agg(column_name, ', ') FROM information_schema.key_column_usage WHERE table_schema='$SCHEMA' AND table_name='$TABLE' AND constraint_name IN (SELECT constraint_name FROM information_schema.table_constraints WHERE constraint_type='PRIMARY KEY' AND table_schema='$SCHEMA' AND table_name='$TABLE');")
    
    # Get indexes
    INDEXES=$(psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" -t -c "SELECT indexname, indexdef FROM pg_indexes WHERE schemaname='$SCHEMA' AND tablename='$TABLE';")
    
    # Create markdown file
    cat > "$DEST_DIR/${TABLE}.md" << EOF
# $FULL_TABLE

This table stores data related to ${TABLE,,} management and operations.

## DDL

\`\`\`sql
$DDL
\`\`\`

## Keys

**Primary Key:** ${PK:-None}

## Indexes

\`\`\`
$INDEXES
\`\`\`
EOF

    echo "Generated documentation for $FULL_TABLE"
done

echo "Documentation generation complete in $DEST_DIR"
