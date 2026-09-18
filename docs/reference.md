# Repository Reference

This document is a code-driven overview of the repository contents. It is meant to answer:

- which files are intended for import versus direct execution,
- which external neuroimaging tools each workflow depends on,
- which parts of the codebase are reusable versus more workflow-specific.

## High-Level Structure

The repository has one main code area:

- `library/`: shell scripts and Python modules for preprocessing, registration, surface/layer analysis, plotting, and small workflow helpers.

At the repository root:

- `README.md`: onboarding and usage overview.
- `__init__.py`: package entry point that exposes selected modules from `library/`.

## Dependency Matrix

The repository is a wrapper-heavy toolbox. Most functions rely on external neuroimaging software in addition to Python packages.

| Area | Python packages | External tools commonly required |
| --- | --- | --- |
| Anatomy / MP2RAGE | `nibabel`, `numpy`, `nipype`, `scikit-image` | FreeSurfer, SPM12, CAT12, ANTs, FSL, `gradient_unwarp.py` |
| Functional / VASO preprocessing | minimal Python for shell wrappers | AFNI, FSL, LAYNII, `jq`, GNU `parallel` |
| Surface / fsLR / ROI analysis | `numpy`, `scipy`, `nibabel`, `nilearn`, `nipype`, `niworkflows` | FreeSurfer, ANTs, Connectome Workbench, ciftify, AFNI, FSL, LAYNII |
| Plotting and geometry | `matplotlib`, `numpy`, `nibabel`, `nilearn`, `numba`, `joblib` | none for plotting; Workbench/FreeSurfer for data generation |
| Orchestration | none or minimal Python | GNU `parallel`, SLURM, Apptainer, Conda |

## Conventions Used Across The Repository

Several recurring assumptions show up throughout the code:

- VASO data are often represented as pairs of files named `*_nulled.nii` and `*_notnulled.nii`.
- Many scripts write output files into the current working directory rather than to an explicit output directory.
- Some modules assume an `analysis_dir` that already contains registration products such as `fs_to_func_0GenericAffine.mat`.
- Surface workflows assume existing FreeSurfer surfaces, ciftify outputs, or fsLR resources.
- Several functions ignore or reset image affines intentionally when sampling voxelwise data and ROIs.
- Some older modules contain hard-coded example paths or TODO notes and should be treated as building blocks rather than polished general-purpose CLIs.

## Python Module Reference

### Public-facing modules

| File | Role | Notes |
| --- | --- | --- |
| `library/layer_analysis.py` | Main analysis module for registration helpers, surface sampling, fsLR transforms, ROI generation, trial averaging, layer profiles, and utility helpers. | Best starting point for reusable analysis code. Calls many external tools through `subprocess` and Nipype. |
| `library/anatomy.py` | Anatomy and MP2RAGE processing utilities, including CAT12 segmentation and `recon-all` orchestration. | Uses SPM/CAT12 via Nipype and expects a working SPM setup. |
| `library/surface_plotting.py` | Surface plotting helpers for metrics, atlas boundaries, and cluster visualization. | Pure Python plotting utilities once data already exist. |
| `library/voxel_space_plotting.py` | Nilearn plotting helpers that first reset images into voxel space. | Useful when affines are inconsistent or deliberately ignored. |
| `library/cluster_surface.py` | Surface-clustering implementation and CLI for connected high-valued metric clusters. | One of the cleaner standalone Python CLIs in the repo. |
| `library/voxeldepths_from_surfaces.py` | Compute voxelwise depths from white/pial surfaces and transform FreeSurfer surfaces into grid space. | Geometry-heavy; uses `numba` and `joblib`. |
| `library/plot_surf_slice.py` | Plot a 2D slice through a surface mesh. | Small helper, useful for inspection/debugging. |
| `library/group_fslr_analysis.py` | Group analysis after sampling subject data to fsLR space. | Importable logic is useful; direct execution is a hard-coded example. |

### Supporting or specialized modules

| File | Role | Notes |
| --- | --- | --- |
| `library/generate_roi.py` | ROI generation from surface or atlas information, with a Nipype-style interface. | Importable, but `__main__` is currently a placeholder. |
| `library/generate_layer_contrast_roi.py` | ROI generation using layer-contrast criteria. | Importable, but direct execution currently runs a test helper. |
| `library/ribbon_segmentation_from_surf.py` | Create ribbon-style segmentations from surfaces. | Specialized geometry utility. |
| `library/cat12_seg_interface.py` | Custom Nipype interface for CAT12 segmentation. | Mostly an interface definition. |
| `library/fs_to_epiT1_reg.py` | Nipype workflow stub for FS-to-EPI-T1 registration. | Marked by TODO comments; not a complete CLI. |
| `library/interfaces.py` | Miscellaneous Nipype interface experiments. | Better treated as internal scratch/work-in-progress code. |
| `library/anat_brain-extract_using-fs-refine.py` | Python refinement of a FreeSurfer-derived brain mask. | Command-line capable, but primarily a utility script. |
| `library/spm_bias-correct.py` | Simple SPM bias-correction entry point. | Small, direct CLI. |
| `library/mp2rage_recon-all.py` | Thin CLI around `anatomy.mp2rage_recon_all`. | Good entry point for MP2RAGE anatomy workflow. |
| `library/voxel-to-world.py` | Convert voxel indices to world coordinates for a NIfTI image. | Small standalone CLI. |

### What `layer_analysis.py` contains

`layer_analysis.py` is the largest and most central module. Its functions fall into a few major groups:

- Registration and coordinate transforms:
  `surftransform_gii`, `surftransform_fs`, `fs_surface_to_func`, `register_fs_to_vasot1`, `apply_ants_transforms`.
- Surface and fsLR operations:
  `sample_surf_hcp`, `transform_data_native_surf_to_fs_LR`, `sample_layer_to_fs_LR`, `smooth_surfmetric_hcp`, `find_clusters_hcp`.
- ROI generation:
  `get_fs_roi`, `get_fs_LR_atlas_roi`, `get_stat_cluster_roi`, `get_funcloc_roi`, `get_md_roi`, `get_glasser_roi`, `get_funcact_roi_laynii`, `get_funcact_roi_vfs`.
- Trial averaging and timecourses:
  `calc_stim_times`, `average_trials_3ddeconvolve`, `average_trials_vaso_3ddeconvolve`, `calc_percent_change_trialavg`.
- Laminar and voxel-sampling helpers:
  `calc_layers_laynii`, `generate_two_layers`, `sample_roi`, `average_roi`, `sample_depths`, `sample_layer_profile`.
- Data-wrangling helpers:
  `sample_temporal_layer_data_to_df`, `calculate_df_condition_contrasts`, `calculate_df_period_averages`.

The older file `docs/layer_analysis.md` outlines the intended architecture and is useful when navigating that module.

## Command-Line Script Reference

### Anatomy, MP2RAGE, and registration

| File | Purpose | Main external dependencies |
| --- | --- | --- |
| `library/mp2rage_recon-all.py` | Run MP2RAGE preprocessing and then FreeSurfer reconstruction through `anatomy.py`. | FreeSurfer, SPM/CAT12, optional `gradient_unwarp.py` |
| `library/spm_bias-correct.py` | Run SPM bias correction on a single file. | SPM12, MATLAB Runtime/MATLAB |
| `library/fs_recon-all_on-brain-extracted.sh` | Run high-resolution `recon-all` when skull stripping has already been done. | FreeSurfer |
| `library/anat_brain-extract_using-inv2.sh` | Brain-extract anatomical data by creating a mask from MP2RAGE INV2. | FSL |
| `library/anat_brain-extract_using-fs-reimport.sh` | Reimport FreeSurfer `brainmask.mgz` into anatomical space and apply it. | FreeSurfer, FSL |
| `library/anat_brain-extract_using-fs-refine.py` | Refine a FreeSurfer-derived brain mask with morphology operations. | Nipype, FreeSurfer, FSL, `scikit-image` |
| `library/prepare_fieldmap.sh` | Prepare a fieldmap for FSL `fugue` from two echoes and phase data. | FSL, `jq` |
| `library/run_gdc.sh` | Apply gradient distortion correction and save corrected image, warpfield, and Jacobian. | FSL, `gradient_unwarp.py` |
| `library/register_fs-to-vasoT1_prepare.sh` | Prepare manual initialization for FreeSurfer-to-VASO-T1 registration using ITK-SNAP. | FreeSurfer, ITK-SNAP |
| `library/register_fs-to-vasoT1.sh` | Manual-initialized nonlinear FreeSurfer-to-VASO-T1 registration. | FreeSurfer, ANTs, ITK-SNAP |
| `library/register_fs-to-vasoT1_no-manual.sh` | Fully scripted nonlinear FreeSurfer-to-VASO-T1 registration. | FreeSurfer, ANTs |
| `library/register_fs-to-bold.sh` | Register FreeSurfer anatomy to BOLD space. | FreeSurfer, ANTs, AFNI |
| `library/register_fs-to-bold_no-manual.sh` | Non-manual BOLD-space registration variant. | FreeSurfer, ANTs, AFNI |
| `library/import-fs-ribbon.sh` | Bring the FreeSurfer ribbon into functional space and convert values for LAYNII-style use. | FreeSurfer, ANTs, FSL |
| `library/ciftify_recon_all_highres.sh` | Run a high-resolution `ciftify_recon-all` workflow and prepare high-res MNI templates if needed. | ciftify, FSL, TemplateFlow |
| `library/create_fs_average_subject.sh` | Build a FreeSurfer average subject from a set of subjects, without relying on `fsaverage`. | FreeSurfer, optional GNU `parallel` |

### Functional, VASO, and preprocessing helpers

| File | Purpose | Main external dependencies |
| --- | --- | --- |
| `library/importruns.sh` | Copy and rename input runs, writing a run list file. | FSL |
| `library/importruns_vaso-split.sh` | Import interleaved VASO runs, split nulled/not-nulled volumes, set TR, trim startup volumes. | AFNI, FSL |
| `library/importruns_vaso-split_reverse.sh` | Same as above, but assumes not-nulled volumes come first. | AFNI, FSL |
| `library/importruns_vaso.sh` | Import already-split VASO nulled/not-nulled pairs and standardize TR/startup handling. | AFNI, FSL |
| `library/motioncorrect.sh` | AFNI-based motion correction for regular or VASO data, with GNU `parallel` support. | AFNI, GNU `parallel` |
| `library/motioncorrect_old.sh` | Older version of the motion-correction wrapper. | AFNI, GNU `parallel` |
| `library/motioncorrect_vaso.sh` | VASO-specific motion-correction wrapper using outlier counts to pick a reference. | AFNI |
| `library/run_afni_mc.sh` | Low-level wrapper around `3dvolreg`, including motion plots in FSL format. | AFNI, FSL |
| `library/boldcorrect.sh` | Basic VASO BOLD correction by dividing nulled by time-shifted not-nulled data. | FSL |
| `library/boldcorrect_lin.sh` | VASO BOLD correction with asymmetric readout timing handled by linear interpolation. | AFNI, `bc` |
| `library/boldcorrect_renzo.sh` | Alternative VASO BOLD correction adapted from Renzo Huber's method. | AFNI |
| `library/calct1.sh` | Compute a T1-like contrast from VASO nulled/not-nulled data and make a brain mask. | AFNI, LAYNII, FSL |
| `library/hpfilter.sh` | Temporal high-pass filtering. | FSL |
| `library/smooth_susan.sh` | Edge-preserving SUSAN spatial smoothing. | FSL |
| `library/avgruns.sh` | Mean-average multiple runs. | AFNI |
| `library/avgtrials.sh` | Event-related trial averaging using `3dDeconvolve` and a TENT basis. | AFNI |
| `library/glm_rA.sh` | Simple rest-vs-activation GLM helper. | AFNI |
| `library/select_runs.sh` | Select lines from a run list file. | shell |
| `library/select_runs_add-ext.sh` | Select run list entries and append a suffix such as `_nulled`. | shell |
| `library/find_task-runs.sh` | Group run indices by BIDS `TaskName` from sidecar JSON files. | `jq` |
| `library/find_max-roi_slice.sh` | Find the slice with maximum ROI coverage along a dimension. | FSL |
| `library/upsample.sh` | Resample a volume to a finer grid in all dimensions. | AFNI |
| `library/upsample_for-layer-sampling.sh` | Intended helper for upsampling layer-sampling inputs. | Appears incomplete |
| `library/voxel-to-world.py` | Convert voxel coordinates to scanner/world coordinates. | `nibabel` |

### Surface, ROI, and group-analysis utilities

| File | Purpose | Main external dependencies |
| --- | --- | --- |
| `library/cluster_surface.py` | Cluster connected regions in a surface metric and write cluster indices as GIFTI. | `numpy`, `nibabel`, `matplotlib` |
| `library/generate_roi.py` | Programmatic ROI generation with a Nipype-style interface. | Workbench, `nilearn`, `nibabel`, `numpy` |
| `library/generate_layer_contrast_roi.py` | Programmatic ROI generation driven by layer contrast targets. | Workbench, `nilearn`, `nibabel`, `numpy` |
| `library/group_fslr_analysis.py` | Group analysis after subject-level sampling to fsLR space. | Workbench, `layer_analysis.py` dependencies |
| `library/surface_plotting.py` | Plot fsLR/GIFTI/CIFTI data and atlas boundaries. | `matplotlib`, `nibabel` |
| `library/plot_surf_slice.py` | Slice and visualize a mesh intersection. | `matplotlib`, `numpy` |
| `library/voxel_space_plotting.py` | Plot voxel-space anatomy, EPI, stats, ROIs, and labels. | `nilearn`, `nibabel` |
| `library/voxeldepths_from_surfaces.py` | Derive cortical depths from white and pial surfaces on a voxel grid. | `numpy`, `numba`, `joblib`, FreeSurfer surface files |
| `library/ribbon_segmentation_from_surf.py` | Surface-based ribbon segmentation support code. | `numpy`, `numba`, `joblib`, `scikit-image` |

### Orchestration and workflow support

| File | Purpose | Main external dependencies |
| --- | --- | --- |
| `library/run.sh` | Choose SLURM, GNU `parallel`, or sequential execution mode for a pipeline step. | SLURM, GNU `parallel`, Apptainer, Conda |
| `library/run_multi-subject.sh` | Run a command over multiple subjects, using GNU `parallel` when available. | GNU `parallel` |
| `library/visualize_pipeline.sh` | Parse a `pipeline.sh` file and generate a DAG-style text/SVG visualization. | shell, optional Graphviz |

## Entry Points That Are Most Ready To Use

If you need the parts of the repository that appear the most directly reusable:

- `library/cluster_surface.py`
- `library/mp2rage_recon-all.py`
- `library/spm_bias-correct.py`
- `library/motioncorrect.sh`
- `library/boldcorrect_lin.sh`
- `library/create_fs_average_subject.sh`
- `library/run.sh`

These have either argument parsing, clear usage headers, or self-contained shell interfaces.

## Files To Treat With More Caution

The following files are useful, but they are not polished general-purpose CLIs:

- `library/generate_roi.py`: importable functionality is the main value.
- `library/generate_layer_contrast_roi.py`: direct execution currently runs a built-in test.
- `library/group_fslr_analysis.py`: direct execution path is a hard-coded example.
- `library/fs_to_epiT1_reg.py`: workflow implementation is incomplete from a CLI perspective.
- `library/interfaces.py`: interface experiments and partial code.
- `library/upsample_for-layer-sampling.sh`: appears unfinished.

## Suggested Reading Order For New Users

If you want to become productive with the repository quickly:

1. Read `README.md`.
2. Skim `library/layer_analysis.py` and `library/anatomy.py` to see the main reusable APIs.
3. Inspect the shell scripts relevant to your workflow category:
   anatomy, VASO preprocessing, registration, or fsLR/surface work.
4. Use `docs/reference.md` as the map back to the rest of the repository.

## Gaps In Current Documentation

This documentation reflects the current codebase, but a few structural gaps remain in the repository itself:

- no packaged install path,
- no environment file or lockfile,
- no tests,
- no explicit license,
- some scripts mix stable utilities with experiment-specific assumptions.

If you want to harden the repository further, the next documentation-adjacent improvement would be to add a reproducible environment definition and one or two end-to-end workflow examples.
