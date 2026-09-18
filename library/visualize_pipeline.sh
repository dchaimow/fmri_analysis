#!/bin/bash
# Create DAG from pipeline.sh using only bash and command-line tools
# Always shows text output, creates SVG if Graphviz is available
#
# Usage: ./visualize_pipeline.sh [pipeline_file]

PIPELINE_FILE="${1:-pipeline.sh}"

if [ ! -f "$PIPELINE_FILE" ]; then
    echo "Error: Pipeline file $PIPELINE_FILE not found"
    exit 1
fi

# Function to clean job names
clean_job_name() {
    local script_name="$1"
    # Remove quotes and file extension
    script_name=$(echo "$script_name" | sed 's/"//g' | sed 's/\.[^.]*$//')
    
    # Remove sl_ or gl_ prefix and step numbers
    script_name=$(echo "$script_name" | sed -E 's/^[0-9]*_?[sg]l_//')
    
    # Replace underscores/hyphens with spaces and capitalize
    script_name=$(echo "$script_name" | sed 's/[_-]/ /g' | sed 's/\b\w/\U&/g')
    
    echo "$script_name"
}



# Extract job lines (ignore comments and empty lines)
job_lines=$(grep -E '^[A-Z][A-Z0-9]*=' "$PIPELINE_FILE" | grep -v '^#')

# Arrays to store job info
declare -A jobs
declare -A dependencies
declare -A script_names
declare -A job_order

job_counter=0

# Parse each job line
while IFS= read -r line; do
    if [ -z "$line" ]; then continue; fi
    
    # Extract job variable name
    job_var=$(echo "$line" | cut -d'=' -f1)
    
    # Extract script name (with or without quotes)
    script_name=$(echo "$line" | grep -oE '"[^"]*\.(sh|py)"' | head -1)
    if [ -z "$script_name" ]; then
        # Try without quotes - extract script name from run command
        script_name=$(echo "$line" | grep -oE '(run\.sh|run_[^ ]*) [^ ]*\.(sh|py)' | sed 's/^[^ ]* //')
    fi
    
    # Extract dependency string (with or without quotes)
    dep_string=$(echo "$line" | grep -oE '\"\$[^"]*\"' | tail -1 | sed 's/"//g')
    if [ -z "$dep_string" ]; then
        # Try without quotes - look for $VAR patterns after the last time specification
        dep_string=$(echo "$line" | grep -oE '[0-9:]+00 .*$' | sed 's/^[0-9:]*00 //' | sed 's/)$//' | grep '\$' || echo "")
    fi
    
    # Clean job name
    clean_name=$(clean_job_name "$script_name")
    
    # Store job info
    jobs["$job_var"]="$clean_name"
    script_names["$job_var"]="$script_name"
    job_order["$job_var"]=$job_counter
    
    # Parse dependencies
    if [ -n "$dep_string" ]; then
        # Extract dependency variables like JOB1:JOB2
        deps=$(echo "$dep_string" | grep -oE 'JOB[0-9]+' | tr '\n' ':' | sed 's/:$//')
        dependencies["$job_var"]="$deps"
    else
        dependencies["$job_var"]=""
    fi
    
    job_counter=$((job_counter + 1))
done <<< "$job_lines"

# Function to output text format
output_text() {
    echo "Pipeline Jobs:"
    echo "=============================================="
    
    for job_var in $(printf '%s\n' "${!jobs[@]}" | sort); do
        job_name="${jobs[$job_var]}"
        deps="${dependencies[$job_var]}"
        
        if [ -n "$deps" ]; then
            # Convert dependency variables to names
            dep_names=""
            IFS=':' read -ra dep_array <<< "$deps"
            for dep in "${dep_array[@]}"; do
                if [ -n "${jobs[$dep]}" ]; then
                    if [ -n "$dep_names" ]; then
                        dep_names="$dep_names, ${jobs[$dep]}"
                    else
                        dep_names="${jobs[$dep]}"
                    fi
                else
                    # Show raw dependency if job name not found
                    if [ -n "$dep_names" ]; then
                        dep_names="$dep_names, $dep (not found)"
                    else
                        dep_names="$dep (not found)"
                    fi
                fi
            done
            echo "$job_name ($job_var) <- depends on: $dep_names"
        else
            echo "$job_name ($job_var) <- no dependencies"
        fi
    done
    
    echo
    echo "Total jobs: ${#jobs[@]}"
    total_deps=0
    for deps in "${dependencies[@]}"; do
        if [ -n "$deps" ]; then
            dep_count=$(echo "$deps" | tr ':' '\n' | wc -l)
            total_deps=$((total_deps + dep_count))
        fi
    done
    echo "Total dependencies: $total_deps"
}

# Function to output DOT format (for Graphviz)
output_dot() {
    # Find terminal nodes (jobs that no other job depends on)
    # and initial nodes (jobs that have no dependencies)
    declare -A is_terminal
    declare -A is_initial
    declare -A has_dependents
    
    # Mark all jobs as potentially terminal
    for job_var in "${!jobs[@]}"; do
        is_terminal["$job_var"]=1
    done
    
    # Mark jobs with no dependencies as initial
    for job_var in "${!jobs[@]}"; do
        deps="${dependencies[$job_var]}"
        if [ -z "$deps" ]; then
            is_initial["$job_var"]=1
        else
            is_initial["$job_var"]=0
        fi
    done
    
    # Mark jobs that have dependents as non-terminal
    for job_var in "${!dependencies[@]}"; do
        deps="${dependencies[$job_var]}"
        if [ -n "$deps" ]; then
            IFS=':' read -ra dep_array <<< "$deps"
            for dep in "${dep_array[@]}"; do
                if [ -n "${jobs[$dep]}" ]; then
                    is_terminal["$dep"]=0
                    has_dependents["$dep"]=1
                fi
            done
        fi
    done
    
    echo "digraph pipeline {"
    echo "  rankdir=TB;"
    echo "  node [shape=box, style=rounded];"
    echo
    
    # Group initial nodes at the top (same rank)
    echo "  // Initial nodes grouped at top"
    echo "  { rank=source;"
    for job_var in "${!jobs[@]}"; do
        if [ "${is_initial[$job_var]}" -eq 1 ]; then
            echo "    $job_var;"
        fi
    done
    echo "  }"
    echo
    
    # Group terminal nodes at the bottom (same rank)
    echo "  // Terminal nodes grouped at bottom"
    echo "  { rank=sink;"
    for job_var in "${!jobs[@]}"; do
        if [ "${is_terminal[$job_var]}" -eq 1 ]; then
            echo "    $job_var;"
        fi
    done
    echo "  }"
    echo
    
    # Add nodes with special marking for terminal nodes and subject-level jobs
    for job_var in "${!jobs[@]}"; do
        job_name="${jobs[$job_var]}"
        script_name="${script_names[$job_var]}"
        
        if [ "${is_terminal[$job_var]}" -eq 1 ]; then
            # Terminal nodes: bold text using HTML-like labels
            echo "  $job_var [label=<<B>$job_name</B>>];"
        elif [[ "$script_name" == *"_sl_"* ]]; then
            # Subject-level jobs: double border to indicate parallel processing
            echo "  $job_var [label=\"$job_name\", peripheries=2];"
        else
            # Regular nodes: default styling
            echo "  $job_var [label=\"$job_name\"];"
        fi
    done
    
    echo
    
    # Add edges
    for job_var in "${!dependencies[@]}"; do
        deps="${dependencies[$job_var]}"
        if [ -n "$deps" ]; then
            IFS=':' read -ra dep_array <<< "$deps"
            for dep in "${dep_array[@]}"; do
                if [ -n "${jobs[$dep]}" ]; then
                    echo "  $dep -> $job_var;"
                fi
            done
        fi
    done
    
    echo "}"
}

# Always output text format
output_text

# Check if dot (Graphviz) is available and create SVG
if command -v dot &> /dev/null; then
    echo
    echo "Creating DAG visualization..."
    
    # Create temporary dot file
    TEMP_DOT=$(mktemp --suffix=.dot)
    output_dot > "$TEMP_DOT"
    
    # Generate SVG with filename based on pipeline script
    PIPELINE_BASE=$(basename "$PIPELINE_FILE" .sh)
    SVG_FILE="${PIPELINE_BASE}.svg"
    
    if dot -Tsvg "$TEMP_DOT" -o "$SVG_FILE" 2>/dev/null; then
        echo "✓ DAG visualization saved to: $SVG_FILE"
        echo "  Terminal nodes (pipeline endpoints) have bold text and are grouped at the bottom"
        echo "  Subject-level jobs (parallel processing) have double borders"
    else
        echo "✗ Failed to generate SVG"
    fi
    
    # Clean up temporary file
    rm -f "$TEMP_DOT"
else
    echo
    echo "Note: Install Graphviz (dot command) to generate visual DAG"
    echo "  Ubuntu/Debian: sudo apt-get install graphviz"
    echo "  macOS: brew install graphviz"
    echo
    echo "Usage: $0 [pipeline_file]"
fi
