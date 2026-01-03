#!/bin/sh -l

TEMPLATE=$1
OUTPUT=$2
CONFIG_BASE=$3
CONFIG_STAGE=$4
EXTRA_VARS=$5
VALUES=$6

# Function to deep merge JSON objects
# Later arguments override earlier ones
merge_json() {
  if [ $# -eq 0 ]; then
    echo "{}"
    return
  fi

  result="{}"
  for file_or_json in "$@"; do
    if [ -n "$file_or_json" ]; then
      if [ -f "$file_or_json" ]; then
        # It's a file path
        content=$(cat "$file_or_json")
      else
        # It's a JSON string
        content="$file_or_json"
      fi
      # Deep merge using jq's * operator with recursive merge for objects
      result=$(echo "$result" "$content" | jq -s '
        def deepmerge(a; b):
          if (a | type) == "object" and (b | type) == "object" then
            a * b | to_entries | map(
              if .value | type == "object" then
                {key: .key, value: deepmerge(a[.key] // {}; b[.key] // {})}
              else
                .
              end
            ) | from_entries
          else
            b
          end;
        deepmerge(.[0]; .[1])
      ')
    fi
  done
  echo "$result"
}

# Function to resolve ${VAR} references in JSON values
resolve_interpolations() {
  local json="$1"
  local max_iterations=10
  local iteration=0

  while [ $iteration -lt $max_iterations ]; do
    iteration=$((iteration + 1))

    # Check if there are any ${...} patterns left
    if ! echo "$json" | grep -q '\${[^}]*}'; then
      break
    fi

    # Extract all top-level keys and their values, then use them for substitution
    json=$(echo "$json" | jq -r '
      . as $root |
      def resolve_refs:
        if type == "string" then
          . as $str |
          reduce ($root | to_entries[]) as $entry (
            $str;
            gsub("\\$\\{" + $entry.key + "\\}"; ($entry.value | tostring))
          )
        elif type == "object" then
          to_entries | map({key: .key, value: (.value | resolve_refs)}) | from_entries
        elif type == "array" then
          map(resolve_refs)
        else
          .
        end;
      resolve_refs
    ')
  done

  echo "$json"
}

# Build merged config
if [ -n "$CONFIG_BASE" ] || [ -n "$CONFIG_STAGE" ] || [ -n "$EXTRA_VARS" ]; then
  echo "Building merged config..."

  # Merge configs: base < stage < extra_vars
  MERGED=$(merge_json "$CONFIG_BASE" "$CONFIG_STAGE" "$EXTRA_VARS")

  echo "Merged config (before interpolation):"
  echo "$MERGED" | jq .

  # Resolve ${VAR} interpolations
  MERGED=$(resolve_interpolations "$MERGED")

  echo "Merged config (after interpolation):"
  echo "$MERGED" | jq .

  # Write merged config
  echo "$MERGED" > /tmp/config.json

  # Generate CONTAINER_ENV YAML block from JSON
  CONTAINER_ENV_BLOCK=$(echo "$MERGED" | jq -r '
    if .CONTAINER_ENV then
      .CONTAINER_ENV | to_entries | map("- name: " + .key + "\n              value: '\''" + (.value | tostring) + "'\''") | join("\n            ")
    else
      ""
    end
  ')

  # Preprocess template:
  # 1. Replace {{ CONTAINER_ENV }} with the generated YAML block
  # 2. Remove legacy .Env. prefix if present
  # 3. Convert {{ KEY }} to {{ .KEY }} and {{- KEY }} to {{- .KEY }}
  sed -E \
    -e 's/\.Env\.//g' \
    -e 's/\{\{- ([A-Z])/\{\{- .\1/g' \
    -e 's/\{\{ ([A-Z])/\{\{ .\1/g' \
    "$TEMPLATE" > /tmp/template.processed

  # Replace CONTAINER_ENV placeholder (needs separate step due to multiline)
  if [ -n "$CONTAINER_ENV_BLOCK" ]; then
    # Create a temp file with the YAML content
    echo "$CONTAINER_ENV_BLOCK" > /tmp/container_env.yaml
    # Use awk to replace the placeholder with file contents
    awk '
      /# \{\{ \.CONTAINER_ENV \}\}/ {
        while ((getline line < "/tmp/container_env.yaml") > 0) print line
        next
      }
      { print }
    ' /tmp/template.processed > /tmp/template.final
    mv /tmp/template.final /tmp/template.processed
  fi

  # Build gomplate command with context
  GOMPLATE_CMD="gomplate -f /tmp/template.processed -o \"$OUTPUT\" --context .=file:///tmp/config.json?type=application/json"

  # Add legacy values if provided
  if [ -n "$VALUES" ]; then
    echo "$VALUES" > /tmp/values.yml
    GOMPLATE_CMD="$GOMPLATE_CMD --datasource values=/tmp/values.yml"
  fi

  eval $GOMPLATE_CMD
else
  # Legacy mode: use values only
  if [ -n "$VALUES" ]; then
    echo "$VALUES" > /tmp/values.yml
    gomplate -f "$TEMPLATE" -o "$OUTPUT" --datasource values=/tmp/values.yml
  else
    gomplate -f "$TEMPLATE" -o "$OUTPUT"
  fi
fi
