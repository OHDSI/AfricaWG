#!/bin/bash
# Ensure the directory exists in the mounted volume
mkdir -p /postprocessing/dqd/data/public

# Create the placeholder only if it doesn't exist
if [ ! -f /postprocessing/dqd/data/public/dq-result.json ]; then
    echo '{}' > /postprocessing/dqd/data/public/dq-result.json
fi

# Execute the original command
exec "$@"