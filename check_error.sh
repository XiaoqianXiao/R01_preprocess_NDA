for file in *.out; do
    if [[ -f "$file" ]]; then
        last_line=$(tail -n 3 "$file" 2>/dev/null)
        if [[ "$last_line" != *"finished without error"* ]]; then
            echo "$file"
        fi
    fi
done


for file in *.err; do
    if [[ -f "$file" ]]; then
        last_line=$(tail -n 1 "$file" 2>/dev/null)
        if [[ "$last_line" != *"PROCESSING DONE"* ]]; then
            echo "$file"
        fi
    fi
done


for file in *.out; do
    if [[ -f "$file" ]]; then
        last_line=$(tail -n 1 "$file" 2>/dev/null)
        if [[ "$last_line" != *"DONE"* ]]; then
            echo "$file"
        fi
    fi
done

file_pattern="*.out"
search_term="completed"
lines_to_check=5

for file in $file_pattern; do
    if [[ -f "$file" ]]; then
        # Grab the last few lines to safely clear the trailing dashed lines
        tail_chunk=$(tail -n "$lines_to_check" "$file" 2>/dev/null)
        
        # Check if the search term exists anywhere in that chunk
        if [[ "$tail_chunk" != *"$search_term"* ]]; then
            echo "$file"
        fi
    fi
done

SUBJECTS=($(find /gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/sourcedata/nii -maxdepth 1 -type d -name "sub-*" -exec basename {} \; | sed 's/sub-//g' | sort)); for file in ${file_pattern:-mriqc_36869418_*.out}; do if [[ -f "$file" ]]; then tail_chunk=$(tail -n "${lines_to_check:-10}" "$file" 2>/dev/null); if [[ "$tail_chunk" != *"${search_term:-completed}"* ]]; then task_id=$(echo "$file" | grep -oE '[0-9]+\.out$' | grep -oE '[0-9]+'); echo "sub-${SUBJECTS[$task_id]}"; fi; fi; done




for file in *.out; do
    if [[ -f "$file" ]]; then
        last_line=$(tail -n 3 "$file" 2>/dev/null)
        if [[ "$last_line" != *"fMRIPrep finished successfully!"* ]]; then
            echo "$file"
        fi
    fi
done