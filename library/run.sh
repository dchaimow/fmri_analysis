#!/bin/bash
# Universal script that automatically chooses the best run mode available:
# 1. Use RUN_MODE if specified in environment
# 2. SLURM (if available and we're on a compute node)
# 3. GNU parallel (if available)
# 4. Sequential (fallback, always available)
#
# It reads configuration from environment variables exported by pipeline.sh.
# The script and processing step may be either a subject-level or group-level processing task.
# It automatically determines processing type from script name:
#   *_sl_*.[sh|py] = subject-level processing
#   *_gl_*.[sh|py] = group-level processing
# Usage: ./run.sh <script_to_run> <cpus_per_task> <time> [dependency_job_id]

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <script_to_run> <cpus_per_task> <time> [dependency_job_id]"
    echo "Script naming convention:"
    echo "  *_sl_*.[sh|py] = subject-level processing"
    echo "  *_gl_*.[sh|py] = group-level processing"
    echo "Note: Configuration is read from environment variables exported by pipeline.sh"
    echo "Note: Automatically detects and uses SLURM, GNU parallel, or sequential run modes"
    echo "Note: Set RUN_MODE environment variable to force specific run mode"
    exit 1
fi

# Parse command line arguments
SCRIPT_TO_RUN=$1
CPUS_PER_TASK=$2
TIME=$3
DEPENDENCY_JOB_ID=$4

# Convert SUBJECTS_LIST to array
if [ -n "$SUBJECTS_LIST" ]; then
    read -ra SUBJECTS <<< "$SUBJECTS_LIST"
else
    echo "Error: SUBJECTS_LIST environment variable is not set"
    echo "This script should be called from pipeline.sh which exports the required configuration"
    exit 1
fi

# Common validation function
validate_config() {
    # Verify required environment variables are set
    if [ -z "$STUDY_DATA_DIR" ] || [ -z "$APPTAINER_IMAGE" ] || [ -z "$CONDA_ENV" ] || [ -z "$LIBRARY_DIR" ]; then
        echo "Error: Missing required environment variables"
        echo "Required variables: STUDY_DATA_DIR, APPTAINER_IMAGE, CONDA_ENV, LIBRARY_DIR"
        echo "This script should be called from pipeline.sh which exports the required configuration"
        exit 1
    fi

    # Verify SUBJECTS array is defined and not empty
    if [ ${#SUBJECTS[@]} -eq 0 ]; then
        echo "Error: SUBJECTS array is not defined or empty"
        echo "Check SUBJECTS_LIST environment variable in pipeline.sh"
        exit 1
    fi

    # Verify required files and directories exist
    if [ ! -f "$APPTAINER_IMAGE" ]; then
        echo "Error: Apptainer image $APPTAINER_IMAGE does not exist."
        exit 1
    fi

    if [ ! -d "$LIBRARY_DIR" ]; then
        echo "Error: Library directory $LIBRARY_DIR does not exist."
        exit 1
    fi
}

# Determine processing type function
determine_processing_type() {
    # Remove both .sh and .py extensions
    JOB_NAME=$(basename "$SCRIPT_TO_RUN")
    JOB_NAME=${JOB_NAME%.sh}
    JOB_NAME=${JOB_NAME%.py}
    
    if [[ "$JOB_NAME" == *"_sl_"* ]]; then
        JOB_NAME=${JOB_NAME#*_sl_}  # Remove prefix up to and including "_sl_"
        PROCESSING_TYPE="subject"
    elif [[ "$JOB_NAME" == *"_gl_"* ]]; then
        JOB_NAME=${JOB_NAME#*_gl_}  # Remove prefix up to and including "_gl_"
        PROCESSING_TYPE="group"
    else
        echo "Error: Cannot determine processing type from script name: $SCRIPT_TO_RUN"
        echo "Script name must contain either '_sl_' (subject-level) or '_gl_' (group-level)"
        exit 1
    fi
}

# Set run mode (keep existing RUN_MODE or auto-detect)
set_run_mode() {
    # If RUN_MODE is already set, validate it
    if [ -n "$RUN_MODE" ]; then
        case "$RUN_MODE" in
            "slurm"|"parallel"|"sequential")
                return
                ;;
            *)
                echo "Error: Invalid RUN_MODE '$RUN_MODE'. Valid options: slurm, parallel, sequential" >&2
                exit 1
                ;;
        esac
    fi
    
    # Auto-detect and set run mode
    # Check for SLURM
    if command -v sbatch &> /dev/null && command -v squeue &> /dev/null; then
        # Additional check: are we in a SLURM environment (not just tools installed)?
        if [ -n "$SLURM_JOB_ID" ] || sinfo &> /dev/null; then
            RUN_MODE="slurm"
            echo "Auto-detected run mode: $RUN_MODE" >&2
            return
        fi
    fi
    
    # Check for GNU parallel
    if command -v parallel &> /dev/null; then
        # Make sure it's GNU parallel (not another parallel command)
        if parallel --version 2>/dev/null | grep -q "GNU parallel"; then
            RUN_MODE="parallel"
            echo "Auto-detected run mode: $RUN_MODE" >&2
            return
        fi
    fi
    
    # Fallback to sequential
    RUN_MODE="sequential"
    echo "Auto-detected run mode: $RUN_MODE" >&2
}

# Common function to build container command
build_container_command() {
    local subject=$1
    local omp_threads_var=${2:-"CPUS_PER_TASK"}
    
    # Use explicit PATH setting - this approach was confirmed working with debugging
    echo "apptainer exec --bind ${LIBRARY_DIR}:${LIBRARY_DIR} --env OMP_NUM_THREADS=\${${omp_threads_var}},MCR_CACHE_ROOT=\$MCR_CACHE_ROOT,MATLAB_PREFDIR=\$MATLAB_PREFDIR ${APPTAINER_IMAGE} bash -c \"source /opt/conda/etc/profile.d/conda.sh && conda activate ${CONDA_ENV} && export PATH=${LIBRARY_DIR}:\\\$PATH && export MCR_CACHE_ROOT=\\\$MCR_CACHE_ROOT MATLAB_PREFDIR=\\\$MATLAB_PREFDIR && ./${SCRIPT_TO_RUN} ${STUDY_DATA_DIR} ${subject}\""
}

# Common function to run container command
run_container_command() {
    local subject=$1
    # Ensure unique MCR/MATLAB cache/prefs per job if not preset
    if [ -z "$MCR_CACHE_ROOT" ]; then
        local tag="${subject:-local}_${BASHPID}"
        export MCR_CACHE_ROOT="${TMPDIR:-/tmp}/mcr_${tag}"
    fi
    if [ -z "$MATLAB_PREFDIR" ]; then
        local tag="${subject:-local}_${BASHPID}"
        export MATLAB_PREFDIR="${TMPDIR:-/tmp}/matlab_${tag}"
    fi
    mkdir -p "$MCR_CACHE_ROOT" "$MATLAB_PREFDIR"

    eval "$(build_container_command "$subject")"
}

# SLURM run mode
run_slurm() {    
    # Build SLURM options
    SLURM_OPTS="--job-name=${JOB_NAME}"
    SLURM_OPTS="${SLURM_OPTS} --nodes=1"
    SLURM_OPTS="${SLURM_OPTS} --ntasks-per-node=1"
    SLURM_OPTS="${SLURM_OPTS} --cpus-per-task=${CPUS_PER_TASK}"
    SLURM_OPTS="${SLURM_OPTS} --time=${TIME}"

    # Add job array for subject-level processing
    if [ "$PROCESSING_TYPE" = "subject" ]; then
        SLURM_OPTS="${SLURM_OPTS} --array=1-${NUM_SUBJECTS}"
        SLURM_OPTS="${SLURM_OPTS} --output=logs/${JOB_NAME}_%A_%a.out"
        SLURM_OPTS="${SLURM_OPTS} --error=logs/${JOB_NAME}_%A_%a.err"
    else
        SLURM_OPTS="${SLURM_OPTS} --output=logs/${JOB_NAME}_%j.out"
        SLURM_OPTS="${SLURM_OPTS} --error=logs/${JOB_NAME}_%j.err"
    fi

    # Add dependency if specified
    if [ -n "$DEPENDENCY_JOB_ID" ]; then
        # Clean up dependency string more thoroughly:
        # 1. Replace multiple colons with single colon
        # 2. Remove leading/trailing colons
        # 3. Repeat until no more changes (handles cases like ::::: -> : -> empty)
        CLEAN_DEPS="$DEPENDENCY_JOB_ID"
        while true; do
            NEW_DEPS=$(echo "$CLEAN_DEPS" | sed 's/::*/:/g; s/^://; s/:$//')
            if [ "$NEW_DEPS" = "$CLEAN_DEPS" ]; then
                break
            fi
            CLEAN_DEPS="$NEW_DEPS"
        done
        
        # Only add dependency if we have valid job IDs
        if [ -n "$CLEAN_DEPS" ] && [ "$CLEAN_DEPS" != ":" ]; then
            # Choose dependency strategy based on processing type
            if [ "$PROCESSING_TYPE" = "subject" ]; then
                # Subject-level: use aftercorr for corresponding task dependencies
                SLURM_OPTS="${SLURM_OPTS} --dependency=aftercorr:${CLEAN_DEPS}"
            else
                # Group-level: wait for entire previous job to complete (afterok)
                SLURM_OPTS="${SLURM_OPTS} --dependency=afterok:${CLEAN_DEPS}"
            fi
        fi
    fi

    # Create temporary script
    TEMP_SCRIPT=$(mktemp)


    cat > "$TEMP_SCRIPT" <<-EOF
	#!/bin/bash
	#SBATCH ${SLURM_OPTS}

	EOF

    # Add subject-specific logic for job arrays
    if [ "$PROCESSING_TYPE" = "subject" ]; then
        # Convert SUBJECTS array to a format that can be embedded in the script
        SUBJECTS_STRING=$(printf '"%s" ' "${SUBJECTS[@]}")
        cat >> "$TEMP_SCRIPT" <<-EOF
		# Define subjects array from config
		SUBJECTS=(${SUBJECTS_STRING})

		# Get subject for this array task
		SUBJECT=\${SUBJECTS[\$((SLURM_ARRAY_TASK_ID - 1))]}
		echo "Processing subject: \$SUBJECT (Array task ID: \$SLURM_ARRAY_TASK_ID)"

		EOF
    fi

    # Add the execution command directly
    cat >> "$TEMP_SCRIPT" <<-EOF
	# Run the analysis
	EOF

    # Set per-job MCR/MATLAB cache to avoid collisions
    cat >> "$TEMP_SCRIPT" <<-EOF
	CACHE_TAG="\${SLURM_JOB_ID}_\${SLURM_ARRAY_TASK_ID:-0}"
	export MCR_CACHE_ROOT="\${TMPDIR:-/tmp}/mcr_\${CACHE_TAG}"
	export MATLAB_PREFDIR="\${TMPDIR:-/tmp}/matlab_\${CACHE_TAG}"
	mkdir -p "\$MCR_CACHE_ROOT" "\$MATLAB_PREFDIR"
	EOF

    if [ "$PROCESSING_TYPE" = "subject" ]; then
        # Build the command for subject-level processing
        CONTAINER_CMD=$(build_container_command "\$SUBJECT" "SLURM_CPUS_PER_TASK")
        echo "$CONTAINER_CMD" >> "$TEMP_SCRIPT"
    else
        # Build the command for group-level processing  
        CONTAINER_CMD=$(build_container_command "" "SLURM_CPUS_PER_TASK")
        echo "$CONTAINER_CMD" >> "$TEMP_SCRIPT"
    fi

    # Submit the job and capture job ID
    JOB_ID=$(sbatch --parsable "$TEMP_SCRIPT")

    # Clean up temporary script
    if [ -f "$TEMP_SCRIPT" ]; then
        rm "$TEMP_SCRIPT"
    fi

    echo "Processing ${JOB_NAME} using SLURM run mode (JOB ID: $JOB_ID)" >&2

    # Return job ID for potential chaining
    echo "$JOB_ID"
}

# Parallel run mode
run_parallel() {
    echo "Processing ${JOB_NAME} using GNU parallel run mode" >&2
    
    # Export function and variables for parallel
    export -f run_container_command
    export SCRIPT_TO_RUN STUDY_DATA_DIR APPTAINER_IMAGE CONDA_ENV LIBRARY_DIR CPUS_PER_TASK JOB_NAME
    
    echo "Starting ${PROCESSING_TYPE}-level processing: ${JOB_NAME}" >&2
    
    if [ "$PROCESSING_TYPE" = "subject" ]; then
        echo "Processing ${NUM_SUBJECTS} subjects in parallel with ${CPUS_PER_TASK} CPUs per subject" >&2
        
        # Calculate optimal parallel jobs
        TOTAL_CORES=$(nproc)
        MAX_PARALLEL_JOBS=$((TOTAL_CORES / CPUS_PER_TASK))
        if [ $MAX_PARALLEL_JOBS -lt 1 ]; then
            MAX_PARALLEL_JOBS=1
        fi
        
        # Create subject and task ID pairs
        SUBJECT_TASKS=()
        for i in "${!SUBJECTS[@]}"; do
            TASK_ID=$((i + 1))
            SUBJECT_TASKS+=("${SUBJECTS[$i]} $TASK_ID")
        done
        
        # Run subjects in parallel with logging
        printf '%s\n' "${SUBJECT_TASKS[@]}" | \
        parallel --jobs ${MAX_PARALLEL_JOBS} --colsep ' ' \
            'echo "Processing subject: {1} (Task ID: {2})" | tee -a logs/'${JOB_NAME}'_{2}.out; \
             run_container_command {1} >> logs/'${JOB_NAME}'_{2}.out 2>> logs/'${JOB_NAME}'_{2}.err'
        
        EXIT_CODE=$?
    else
        echo "Running single group-level job" >&2
        {
            echo "Running group-level analysis"
            run_container_command ""
        } > logs/${JOB_NAME}.out 2> logs/${JOB_NAME}.err
        
        EXIT_CODE=$?
    fi
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo "✓ Completed ${PROCESSING_TYPE}-level processing: ${JOB_NAME}" >&2
        echo "parallel_$$_$(date +%s)"
    else
        echo "✗ Failed ${PROCESSING_TYPE}-level processing: ${JOB_NAME}" >&2
        exit $EXIT_CODE
    fi
}

# Sequential run mode
run_sequential() {
    echo "Processing ${JOB_NAME} using sequential run mode" >&2
    
    if [ "$PROCESSING_TYPE" = "subject" ]; then
        echo "Processing ${NUM_SUBJECTS} subjects sequentially with ${CPUS_PER_TASK} CPUs per subject" >&2
        
        FAILED_SUBJECTS=()
        TOTAL_EXIT_CODE=0
        
        for i in "${!SUBJECTS[@]}"; do
            TASK_ID=$((i + 1))
            SUBJECT="${SUBJECTS[$i]}"
            
            echo "[$TASK_ID/${NUM_SUBJECTS}] Starting subject: $SUBJECT" >&2
            
            # Create log files
            LOG_OUT="logs/${JOB_NAME}_${TASK_ID}.out"
            LOG_ERR="logs/${JOB_NAME}_${TASK_ID}.err"
            
            echo "Processing subject: $SUBJECT (Task ID: $TASK_ID)" | tee -a "$LOG_OUT"
            
            # Run the analysis
            run_container_command "$SUBJECT" >> "$LOG_OUT" 2>> "$LOG_ERR"
            SUBJECT_EXIT_CODE=$?
            
            if [ $SUBJECT_EXIT_CODE -eq 0 ]; then
                echo "✓ Completed subject: $SUBJECT (Task ID: $TASK_ID)" | tee -a "$LOG_OUT"
            else
                echo "✗ Failed subject: $SUBJECT (Task ID: $TASK_ID, exit code: $SUBJECT_EXIT_CODE)" | tee -a "$LOG_ERR"
                FAILED_SUBJECTS+=("$SUBJECT")
                TOTAL_EXIT_CODE=1
            fi
        done
        
        # Report results
        if [ $TOTAL_EXIT_CODE -eq 0 ]; then
            echo "✓ All ${NUM_SUBJECTS} subjects completed successfully" >&2
        else
            echo "✗ ${#FAILED_SUBJECTS[@]} subject(s) failed: ${FAILED_SUBJECTS[*]}" >&2
        fi
        
        EXIT_CODE=$TOTAL_EXIT_CODE
    else
        
        LOG_OUT="logs/${JOB_NAME}.out"
        LOG_ERR="logs/${JOB_NAME}.err"
        
        echo "Running group-level analysis" >> "$LOG_OUT"
        run_container_command "" >> "$LOG_OUT" 2>> "$LOG_ERR"
        EXIT_CODE=$?
    fi
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo "✓ Completed ${PROCESSING_TYPE}-level processing: ${JOB_NAME}" >&2
        echo "sequential_$$_$(date +%s)"
    else
        echo "✗ Failed ${PROCESSING_TYPE}-level processing: ${JOB_NAME}" >&2
        exit $EXIT_CODE
    fi
}

# Main execution
validate_config
determine_processing_type
set_run_mode

NUM_SUBJECTS=${#SUBJECTS[@]}
mkdir -p logs
case $RUN_MODE in
    "slurm")
        run_slurm "$@"
        ;;
    "parallel")
        run_parallel
        ;;
    "sequential")
        run_sequential
        ;;
    *)
        echo "Error: Unknown run mode: $RUN_MODE"
        exit 1
        ;;
esac
