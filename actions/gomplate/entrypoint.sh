#!/bin/sh -l

TEMPLATE=$1
OUTPUT=$2
VALUES=$3

export $(printenv | sed 's/^\(.*\)$/\1/g')

if [ -n "$VALUES" ]; then
  echo "$VALUES" > /tmp/values.yml
  gomplate -f "$TEMPLATE" -o "$OUTPUT" --datasource values=/tmp/values.yml
else
  gomplate -f "$TEMPLATE" -o "$OUTPUT"
fi
