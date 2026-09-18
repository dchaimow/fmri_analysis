# fmri_analysis

`fmri_analysis` is a personal toolbox for high-resolution, layer-fMRI, and surface-based fMRI analysis. It combines:

- Python modules for ROI generation, laminar sampling, plotting, geometry, and group analysis.
- Bash wrappers around AFNI, FSL, FreeSurfer, ANTs, Connectome Workbench, ciftify, LAYNII, and related tools.

This repository is not a single end-to-end application. It is a reusable collection of scripts and analysis helpers that can be called directly from the command line or imported into other projects.

## What Is In The Repository

The codebase mainly covers:

- MP2RAGE and anatomy preprocessing, specifically an implementation of a FreeSurfer based pipeline, incorporating and CAT12/SPM-based steps.
- VASO/BOLD run import, splitting, motion correction, BOLD correction, and T1w contrast estimation.
- FreeSurfer-to-functional registration and ribbon import.
- Surface sampling, fsLR transformation, layer-profile extraction, and ROI generation.
- Surface and voxel-space plotting.
- Convenience scripts for multi-subject execution and simple pipeline orchestration.

## Repository Layout

- `library/`: the actual toolbox. Most shell scripts and Python analysis modules live here.
- `__init__.py`: package entry point that exposes the most commonly used Python modules.
- `docs/layer_analysis.md`: older developer notes for the large `layer_analysis.py` module.
- `docs/reference.md`: script/module reference for this repository.

## Installation

There is currently no packaging metadata such as `pyproject.toml` or `setup.py`, so the repository is usually used in one of two ways.

### 1. Use the command-line tools

Add `library/` to your `PATH`:

```bash
export FMRI_ANALYSIS_DIR=/path/to/fmri_analysis
export PATH="$FMRI_ANALYSIS_DIR/library:$PATH"
```

This makes shell scripts such as `motioncorrect.sh` and Python entry points such as `cluster_surface.py` directly callable.

### 2. Import the Python modules

Add the parent directory of the repository to `PYTHONPATH`:

```bash
export PYTHONPATH="$(dirname "$FMRI_ANALYSIS_DIR"):$PYTHONPATH"
```

Then import from Python:

```python
from fmri_analysis.library import layer_analysis
from fmri_analysis.library import surface_plotting
```

The package root also re-exports several frequently used modules:

```python
import fmri_analysis

fmri_analysis.layer_analysis
fmri_analysis.surface_plotting
fmri_analysis.cluster_surface
```

## Python Dependencies

The Python code depends on a scientific Python stack plus neuroimaging interfaces. The imports in this repository require some combination of:

- `numpy`
- `scipy`
- `pandas`
- `matplotlib`
- `nibabel`
- `nilearn`
- `nipype`
- `niworkflows`
- `numba`
- `joblib`
- `scikit-image`

Not every script needs every package, but `layer_analysis.py`, `anatomy.py`, and the surface/depth tools assume most of the stack is available.

## External Software Dependencies

Most command-line tools here are wrappers around other neuroimaging software. Depending on which part of the repository you use, you may need:

- AFNI
- FSL
- FreeSurfer
- ANTs
- Connectome Workbench (`wb_command`)
- ciftify
- LAYNII
- SPM12 and CAT12
- MATLAB Runtime or MATLAB, depending on your SPM setup
- GNU `parallel`
- `jq`
- `itksnap`
- `gradient_unwarp.py`
- TemplateFlow access for `ciftify_recon_all_highres.sh`
- SLURM and Apptainer for `run.sh`

There is no single dependency profile that covers every script cleanly. In practice, you install the subset required by your workflow.

## Usage Model And Conventions

Most scripts assume a Unix shell workflow and make strong assumptions about filenames, working directories, and external software availability.

Common conventions in this repository:

- VASO pairs are usually named `*_nulled.nii` and `*_notnulled.nii`.
- Many scripts write outputs into the current working directory.
- Some workflows assume a FreeSurfer subject directory and ciftify outputs already exist.
- Several Python functions call external binaries with `subprocess.run(...)` rather than re-implementing the underlying operation in Python.
- Some entry points are polished CLIs, while others are better treated as importable modules or workflow building blocks.

## Main Workflows

### Anatomical Processing

Use the anatomy helpers and shell wrappers when preparing MP2RAGE or other high-resolution anatomical data:

- `library/mp2rage_recon-all.py`: CLI around `anatomy.mp2rage_recon_all(...)`.
- `library/anatomy.py`: anatomy utilities including normalization, CAT12 segmentation, and MP2RAGE-to-FreeSurfer processing.
- `library/spm_bias-correct.py`: simple SPM bias-correction entry point.
- `library/fs_recon-all_on-brain-extracted.sh`: run `recon-all` on already skull-stripped input.
- `library/anat_brain-extract_using-*.sh` and `library/anat_brain-extract_using-fs-refine.py`: brain extraction helpers.

### Functional And VASO Preprocessing

The shell scripts in `library/` contain a compact toolbox for common preprocessing steps:

- `importruns.sh`: copy and rename runs.
- `importruns_vaso*.sh`: import VASO runs and split/interleave nulled and not-nulled volumes.
- `motioncorrect.sh`: AFNI-based motion correction for regular or VASO data.
- `boldcorrect.sh`, `boldcorrect_lin.sh`, `boldcorrect_renzo.sh`: VASO BOLD correction variants.
- `calct1.sh`: derive a T1-like image from VASO nulled/not-nulled data.
- `prepare_fieldmap.sh`: prepare fieldmap inputs for FSL `fugue`.
- `hpfilter.sh`, `smooth_susan.sh`, `avgtrials.sh`, `avgruns.sh`: small preprocessing/statistical helpers.

### Surface, Layer, And ROI Analysis

The main reusable Python analysis code lives here:

- `library/layer_analysis.py`: the largest module, covering registration helpers, surface sampling, fsLR transforms, ROI creation, trial averaging, layer-profile extraction, and related utilities.
- `library/group_fslr_analysis.py`: group-level analysis after sampling subject data to fsLR space.
- `library/generate_roi.py`: ROI generation utilities and Nipype-style interface.
- `library/generate_layer_contrast_roi.py`: ROI generation from laminar contrasts.
- `library/cluster_surface.py`: cluster connected high-valued regions on a surface metric.
- `library/voxeldepths_from_surfaces.py`: derive voxel-wise cortical depths from white/pial surfaces.
- `library/ribbon_segmentation_from_surf.py`: ribbon segmentation utilities from surface geometry.

### Plotting And Visualization

- `library/surface_plotting.py`: plotting utilities for flat or surface-based data.
- `library/voxel_space_plotting.py`: nilearn-based plotting after resetting images to voxel space.
- `library/plot_surf_slice.py`: 2D slice visualization of surface intersections.
- `library/visualize_pipeline.sh`: generate a DAG-style visualization from a `pipeline.sh` file.

## Small CLI Examples

Examples below are illustrative. Many scripts assume you are already in an analysis directory with the expected inputs nearby.

```bash
# Add tools to PATH
export PATH="/path/to/fmri_analysis/library:$PATH"

# Split interleaved VASO runs into nulled / not-nulled volumes
importruns_vaso-split.sh run 4.0 sub-01_run-1.nii.gz sub-01_run-2.nii.gz

# Motion-correct VASO runs
motioncorrect.sh -vaso run1 run2 run3

# Perform linear-interpolation-based VASO BOLD correction
boldcorrect_lin.sh run1 0.5

# Cluster a surface metric
cluster_surface.py zstat.func.gii white.surf.gii zstat_clusters.func.gii \
  --min_cluster_size 100

# Build a FreeSurfer average subject from multiple subjects
create_fs_average_subject.sh -d "$SUBJECTS_DIR" -n myaverage -s talairach
```

## Recommended Python Entry Points

If you want to use the repository as a library, start with:

- `fmri_analysis.library.layer_analysis`
- `fmri_analysis.library.anatomy`
- `fmri_analysis.library.surface_plotting`
- `fmri_analysis.library.voxel_space_plotting`
- `fmri_analysis.library.cluster_surface`
- `fmri_analysis.library.voxeldepths_from_surfaces`

These contain most of the reusable functionality. Other files are often thin wrappers, experiment-specific helpers, or command-line scripts.

## Files That Are Better Treated As Internal Or Experimental

Some files exist but are not full polished public CLIs:

- `library/generate_roi.py`: importable functionality is present, but the `__main__` block is a placeholder.
- `library/generate_layer_contrast_roi.py`: currently runs a hard-coded test function when executed directly.
- `library/group_fslr_analysis.py`: direct execution path is an embedded example, not a general CLI.
- `library/fs_to_epiT1_reg.py`: workflow code exists, but command-line handling is marked as TODO.
- `library/interfaces.py`: appears to be partial Nipype interface work rather than a finished user-facing module.
- `library/upsample_for-layer-sampling.sh`: appears incomplete.

## Documentation

Additional repository documentation lives in:

- [`docs/reference.md`](docs/reference.md): module, script, dependency, and workflow reference.

## Caveats

- No formal test suite is included in this repository.
- The codebase mixes stable utilities with workflow-specific scripts and older experiments.
- Some paths inside the code are environment-specific and may need adaptation on a new system.
- Many functions assume neuroimaging file conventions rather than validating inputs exhaustively.

## License

No license file is currently present in this repository. If you plan to distribute or publish derived work, add an explicit license first.
