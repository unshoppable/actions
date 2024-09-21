#!/bin/sh -l

TEMPLATE=$1
OUTPUT=$2
VALUES=$3

if [ -n "$VALUES" ]; then
  echo "$VALUES" > /tmp/values.yml
  gomplate -f "$TEMPLATE" -o "$OUTPUT" --datasource values=/tmp/values.yml
else
  gomplate -f "$TEMPLATE" -o "$OUTPUT"
fi
