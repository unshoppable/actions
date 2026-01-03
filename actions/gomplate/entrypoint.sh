#!/bin/sh -l
#
# Gomplate Template Rendering Entrypoint
# =======================================
#
# This script renders Go templates using gomplate with merged JSON configuration.
#
# PURPOSE:
# Generate deployment YAML files (e.g., GCP Cloud Run service/job definitions)
# by combining base configuration, stage-specific overrides, and runtime variables.
#
# FEATURES:
# 1. JSON Config Merging - Merges multiple JSON config files with deep object merge:
#    - Base config (e.g., variables.json) - common settings across all stages
#    - Stage config (e.g., prod/variables.json) - stage-specific overrides
#    - Extra vars (JSON string) - runtime values like IMAGE tag
#
# 2. Variable Interpolation - Resolves ${VAR} references within JSON values:
#    - Example: "bucket-${STAGE}" becomes "bucket-prod" when STAGE=prod
#    - Supports multiple passes for chained references
#
# 3. Template Preprocessing - Simplifies template syntax:
#    - Converts {{ KEY }} to {{ .KEY }} (auto-adds dot prefix)
#    - Removes legacy .Env. prefix if present
#    - Expands # {{ CONTAINER_ENV }} placeholder to full env var YAML block
#
# 4. CONTAINER_ENV Expansion - Generates Cloud Run environment variable YAML:
#    - Reads CONTAINER_ENV object from merged config
#    - Outputs properly formatted YAML for GCP Cloud Run spec
#
# ARGUMENTS:
#   $1 - TEMPLATE: Path to the gomplate template file
#   $2 - OUTPUT: Path to save the rendered output
#   $3 - CONFIG_BASE: Path to base JSON config file (optional)
#   $4 - CONFIG_STAGE: Path to stage-specific JSON config file (optional)
#   $5 - EXTRA_VARS: Additional variables as JSON string (optional)
#   $6 - VALUES: Legacy YAML values for backwards compatibility (optional)
#
# USAGE (via GitHub Action):
#   uses: unshoppable/actions/actions/gomplate@main
#   with:
#     template: .github/config/my-app/gcp.yaml
#     output: deployment.yaml
#     config_base: .github/config/my-app/variables.json
#     config_stage: .github/config/my-app/prod/variables.json
#     extra_vars: '{"STAGE": "prod", "IMAGE": "eu.gcr.io/project/app:tag"}'
#

TEMPLATE=$1
OUTPUT=$2
CONFIG_BASE=$3
CONFIG_STAGE=$4
EXTRA_VARS=$5
VALUES=$6

# GitHub Actions mounts workspace at /github/workspace
# Adjust paths if they're relative and we're in GitHub Actions
adjust_path() {
  local path="$1"
  if [ -z "$path" ]; then
    echo ""
  elif [ -f "$path" ]; then
    # Path exists as-is
    echo "$path"
  elif [ -n "$GITHUB_WORKSPACE" ] && [ -f "$GITHUB_WORKSPACE/$path" ]; then
    # Try with GitHub workspace prefix
    echo "$GITHUB_WORKSPACE/$path"
  else
    # Return original path (will fail later with clear error)
    echo "$path"
  fi
}

# Debug: show current directory and workspace info
echo "Current directory: $(pwd)"
echo "GITHUB_WORKSPACE: $GITHUB_WORKSPACE"
echo "ls of current directory:"
ls -la | head -10

TEMPLATE=$(adjust_path "$TEMPLATE")
CONFIG_BASE=$(adjust_path "$CONFIG_BASE")
CONFIG_STAGE=$(adjust_path "$CONFIG_STAGE")

echo "Adjusted paths:"
echo "  TEMPLATE: $TEMPLATE (exists: $([ -f "$TEMPLATE" ] && echo "yes" || echo "no"))"
echo "  CONFIG_BASE: $CONFIG_BASE (exists: $([ -f "$CONFIG_BASE" ] && echo "yes" || echo "no"))"
echo "  CONFIG_STAGE: $CONFIG_STAGE (exists: $([ -f "$CONFIG_STAGE" ] && echo "yes" || echo "no"))"

# Adjust OUTPUT path for GitHub workspace
if [ -n "$GITHUB_WORKSPACE" ] && [ ! -d "$(dirname "$OUTPUT")" ]; then
  OUTPUT="$GITHUB_WORKSPACE/$OUTPUT"
fi
echo "  OUTPUT: $OUTPUT"

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
        echo "Merging file: $file_or_json"
        content=$(cat "$file_or_json")
      else
        # It's a JSON string
        echo "Merging JSON string: $file_or_json"
        content="$file_or_json"
      fi

      # Validate JSON before merging
      if ! echo "$content" | jq empty 2>/dev/null; then
        echo "ERROR: Invalid JSON content: $content"
        echo "Skipping this input"
        continue
      fi

      # Deep merge using jq's * operator (which recursively merges objects)
      result=$(echo "$result" "$content" | jq -s '.[0] * .[1]')

      if [ $? -ne 0 ]; then
        echo "ERROR: jq merge failed"
        echo "Current result: $result"
        echo "Content being merged: $content"
      fi
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

    # Extract all top-level keys with scalar values for substitution
    # Skip objects and arrays as they can't be interpolated into strings
    json=$(echo "$json" | jq '
      # Build a lookup of only scalar (string/number/boolean) values
      . as $root |
      ($root | to_entries | map(select(.value | type == "string" or type == "number" or type == "boolean")) | from_entries) as $scalars |
      def resolve_refs:
        if type == "string" then
          . as $str |
          reduce ($scalars | to_entries[]) as $entry (
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
  echo "CONFIG_BASE: $CONFIG_BASE"
  echo "CONFIG_STAGE: $CONFIG_STAGE"
  echo "EXTRA_VARS: $EXTRA_VARS"

  # Check if config files exist
  if [ -n "$CONFIG_BASE" ]; then
    if [ -f "$CONFIG_BASE" ]; then
      echo "CONFIG_BASE file exists, contents:"
      cat "$CONFIG_BASE"
    else
      echo "WARNING: CONFIG_BASE file does not exist: $CONFIG_BASE"
    fi
  fi

  if [ -n "$CONFIG_STAGE" ]; then
    if [ -f "$CONFIG_STAGE" ]; then
      echo "CONFIG_STAGE file exists, contents:"
      cat "$CONFIG_STAGE"
    else
      echo "WARNING: CONFIG_STAGE file does not exist: $CONFIG_STAGE"
    fi
  fi

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
