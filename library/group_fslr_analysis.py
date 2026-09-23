#!/usr/bin/env python3
"""
Group analysis on fs_LR surface afer sampling volume data from individual subjects.

Steps are:
1. Sample and process individual subject data:
    1a) sample individual subject data to surfaces in native functional space, 
    1b) transform to fsLR, 
    1c) optionally smooth 
    1d) calculate layer contrasts. 
    By default sample from entire cortical depth, optionally sample from one more depth range (layers).
    -> the result are numpy arrays for each hemisphere, containing for each layer contrast and each subject all 164k vertex values.
2. Calculate group analysis contrasts:
    2a) Calculate across-subjects converage for each vertex.
    2b) calculate group contrast estimate as linear combination of the individual subject layer contrasts,
    2c) calculate standard deviation across subjects, and the standard error of the group contrast
    2d) calculate t-statistics for the group contrast and transform to z-statistics
 Write the results as metric files.

Needed data:
- single subject volume files to sample (1st level estimates, fstats ...)
- single subject surfaces in functional space (pial and white)
- single subject transform to fs_LR space (ciftify)

Needed specifications:
- list of subjects to process
- single subjects laminar contrasts to compute
- group analysis contrasts to compute

If we want to calculated a depth contrast we need to specify the depth ranges of one or more layers to sample,
as well as the contrast(s) to compute from these layers.
    }
"""


import os
from . import layer_analysis as analysis
import numpy as np
from tempfile import TemporaryDirectory
import nibabel as nib
from joblib import Parallel, delayed

# set MAX_CPUS based on OMP_NUM_THREADS, set to 1 if not set
try:
    MAX_CPUS = int(os.environ['OMP_NUM_THREADS'])
except KeyError:
    MAX_CPUS = 1


def sample_firstlevel_layer_contrast_to_fsLR(subject,firstlevel_analysis_dir,ciftify_dir,surf_dir,
                                             firstlevel_subpath,
                                             depth_ranges=None,
                                             layer_contrasts=None,
                                             smooth_sigma=3):
    
    # check whether firstlevel_subpath ends in .gii -> if yes we start from single subject native space surface data
    # in that case we don't assum multiple depth ranges and layer contrasts and just process the single surface file
    # and we don't call sample_layer_to_fs_LR but directly transform to fsLR using analysis.transform_data_native_surf_to_fs_LR
    if firstlevel_subpath.endswith('.gii'):
        firstlevel_subpath = os.path.basename(firstlevel_subpath)  # only the file name
        starting_from_surface = True

    else:
        starting_from_surface = False

    with TemporaryDirectory() as tmpdirname:
        ciftify_dir = os.path.join(ciftify_dir, subject)
        surf_dir = os.path.join(surf_dir, subject)
        firstlevel_path = os.path.join(firstlevel_analysis_dir, subject, firstlevel_subpath)

        firstlevel_fsLR_layer_contrast_data = dict()
        firstlevel_fsLR_layer_contrast_coverage = dict()

        for hemi in ('L','R'):
            # set surface file names
            white_surf = os.path.join(surf_dir,f"{hemi}.white.func.surf.gii")
            pial_surf = os.path.join(surf_dir,f"{hemi}.pial.func.surf.gii")

            firstlevel_fsLR_layer_data = np.zeros((len(depth_ranges), 163842))  # assuming 164k fs_LR vertices
            firstlevel_fsLR_layer_coverage_nans = np.zeros((len(depth_ranges), 163842))  # assuming 164k fs_LR vertices
            for layer_idx, depth_range in enumerate(depth_ranges):
    
                # set output file names
                firstlevel_fsLR_path = os.path.join(tmpdirname,f'{hemi}.{layer_idx}.164k_fs_LR.func.gii')    
                coverage_fsLR_path = os.path.join(tmpdirname,f'{hemi}.{layer_idx}.164k_fs_LR.coverage.shape.gii')
                # calculate coverage for each vertex            
                analysis.sample_layer_to_fs_LR(firstlevel_path, 
                                            firstlevel_fsLR_path,
                                            white_surf, pial_surf,
                                            ciftify_dir, 
                                            hemi,
                                            depth_range,
                                            coverage_out=coverage_fsLR_path, 
                                            smooth_sigma=smooth_sigma)            
         
                # load sampled fsLR surface data
                firstlevel_fsLR_layer_data[layer_idx,:] =  nib.load(firstlevel_fsLR_path).darrays[0].data
                # load coverage and set non-covered vertices to nan
                coverage = nib.load(coverage_fsLR_path).darrays[0].data  # load
                firstlevel_fsLR_layer_coverage_nans[layer_idx,:] = np.where(coverage == 1, 1.0, np.nan)

            # calculate layer contrasts
            firstlevel_fsLR_layer_contrast_data[hemi] = layer_contrasts @ firstlevel_fsLR_layer_data
            # set coverage to 0 wherever contrast calculation resulted in nans, otherwise set to 1
            firstlevel_fsLR_layer_contrast_coverage_nans = layer_contrasts @ firstlevel_fsLR_layer_coverage_nans
            firstlevel_fsLR_layer_contrast_coverage[hemi] = np.where(np.isnan(firstlevel_fsLR_layer_contrast_coverage_nans), 0, 1)

    return firstlevel_fsLR_layer_contrast_data, firstlevel_fsLR_layer_contrast_coverage

def group_fslr_analysis(firstlevel_analysis_dir,ciftify_dir,surf_dir,firstlevel_subpath,subjects,
                        depth_ranges=None,layer_contrasts=None,group_contrasts='mean',group_analysis_dir=None,
                        smooth_sigma=3, nan_as_zero=False):
    """
    Perform group analysis on fs_LR surface afer sampling volume data from individual subjects.

    Parameters
    ----------
    first_level_analysis_dir: str
        Path to the directory containing individual subjects' first level analysis subdirectories with first level analysis results.
        (i.e. first_level_analysis_dir/sub-01, first_level_analysis_dir/sub-02, etc.).
    ciftify_dir: str
        Path to the directory containing individual subjects' ciftify subdirectories (i.e ciftify_dir/sub-01, ciftify_dir/sub-02, etc.).
    surf_dir: str
        Path to the directory containing individual subjects' surface files in functional space (named [L.R].[white|pial].func.surf.gii)
        (i.e. surf_dir/sub-01/L.white.func.surf.gii, etc.)
    firstlevel_subpath: 
        Relative path from each subjects first level analysis directory to the file to sample from.
    subjects: list of str
        List of subject identifiers to process, e.g. ['sub-01', 'sub-02'].
    depth_ranges: list of tuples (default=None)
        List of depth ranges to sample from, e.g. [(0, 0.2), (0.2, 0.4)].
        If None, the entire cortical depth is sampled.
    layer_contrasts: ndarray
        List of contrasts to compute from the sampled layers, e.g. [[1, -1], [0, 1]].
        If None, each layer is processed separately.
    group_contrasts: str of ndarray
        Either 'mean' of list of group contrasts to compute.
        Currently only 'mean' is supported, which computes the for eacg vertex the mean across subjects for which thar vertex is covered.
    group_analysis_dir: str
        Directory to store group analysis results.
        If None, the results are stored in a subdirectory 'group_analysis' of the first level analysis directory.
    smooth_sigma: float
        sigma value (mm) for smoothing the data. Default is 3 mm.
        If 0, no smoothing is applied.
    nan_as_zero: bool
        If True, NaN values in the data are treated as zeros. Default is False.
        This is mainly for debugging purposes, as it can lead to misleading results if not used carefully.
    """
    if depth_ranges is None and layer_contrasts is None:
        layer_analysis = False
    else:
        layer_analysis = True

    if depth_ranges is None:
        # Default to entire cortical depth
        depth_ranges = [(0, 1)]  

    if layer_contrasts is None:
        # each layer is processed separately
        layer_contrasts = np.eye(len(depth_ranges))

    n_subjects = len(subjects)

    # step 1 - sample individual subject data to surfaces in native functional and transform to fsLR space (parallelized)
    group_layer_contrast_data = {hemi : np.zeros((len(layer_contrasts), 163842, n_subjects)) for hemi in ('L', 'R')}
    group_layer_contrast_coverage = {hemi : np.zeros((len(layer_contrasts), 163842, n_subjects)) for hemi in ('L', 'R')}
    
    results = Parallel(n_jobs=min(n_subjects, MAX_CPUS))(
        delayed(sample_firstlevel_layer_contrast_to_fsLR)(
            subject, firstlevel_analysis_dir, ciftify_dir, surf_dir,
            firstlevel_subpath, depth_ranges, layer_contrasts, smooth_sigma
        ) for subject in subjects
    )
    
    # Assign results to group arrays
    for subject_index, (layer_contrast_data, layer_contrast_coverage) in enumerate(results):
        for hemi in ('L', 'R'):
            group_layer_contrast_data[hemi][:, :, subject_index] = layer_contrast_data[hemi]
            group_layer_contrast_coverage[hemi][:, :, subject_index] = layer_contrast_coverage[hemi]
    
    # step 2 - calculate group analysis contrasts
    # calculate mean of one array along one axis, but only use values that are covered in all subjects
    if group_contrasts != 'mean':
        raise NotImplementedError("Currently only 'mean' group contrast is supported.")
    
    m = dict()
    s = dict()
    n = dict()
    for hemi in ('L', 'R'):
        # set non-covered vertices to nan
        group_layer_contrast_data_nan = np.where(group_layer_contrast_coverage[hemi] > 0, 
                                                group_layer_contrast_data[hemi], np.nan)
        if nan_as_zero:
            # Treat NaNs as zero
            data_for_stats = np.nan_to_num(group_layer_contrast_data_nan, nan=0.0)
            m[hemi] = np.mean(data_for_stats, axis=2)
            s[hemi] = np.std(data_for_stats, axis=2)
        else:
            group_layer_contrast_data_masked = np.ma.masked_invalid(group_layer_contrast_data_nan)
        
            m[hemi] = np.ma.mean(group_layer_contrast_data_masked, axis=2).filled(np.nan)
            s[hemi] = np.ma.std(group_layer_contrast_data_masked, axis=2).filled(np.nan)
        n[hemi] = np.sum(group_layer_contrast_coverage[hemi] > 0, axis=2)
        
        # write the results to metric files
        if group_analysis_dir is None:
            group_analysis_dir = os.path.join(firstlevel_analysis_dir, 'group_analysis')
        os.makedirs(group_analysis_dir, exist_ok=True)

        for layer_contrast_idx in range(len(layer_contrasts)):
            if layer_analysis:
                stat_basename = f'group_lc{layer_contrast_idx}'
            else:
                stat_basename = f'group'

            data_mean_fname = os.path.join(group_analysis_dir, f'{hemi}.164k_fs_LR.{stat_basename}.mean.func.gii')
            data_std_fname = os.path.join(group_analysis_dir, f'{hemi}.164k_fs_LR.{stat_basename}.std.func.gii')
            data_n_fname = os.path.join(group_analysis_dir, f'{hemi}.164k_fs_LR.{stat_basename}.n.func.gii')

            # write metric files for mean, std and n using nibabel
            analysis.write_metric_gifti(data_mean_fname, m[hemi][layer_contrast_idx, :], hemi)
            analysis.write_metric_gifti(data_std_fname, s[hemi][layer_contrast_idx, :], hemi)
            analysis.write_metric_gifti(data_n_fname, n[hemi][layer_contrast_idx, :], hemi)

if __name__ == "__main__":
    # test the group_fslr_analysis function with example parameters
    study_data_dir = '/ptmp/dchaimow/data/finn-et-al-2019_replication/'
    firstlevel_analysis_dir = os.path.join(study_data_dir,'derivatives','analysis')
    ciftify_dir = os.path.join(study_data_dir,'derivatives','ciftify')
    surf_dir = os.path.join(study_data_dir,'derivatives','ref_anat')
    firstlevel_data_subpath = 'trialavg5/trialavg5_notnulled_alpharem_fstat.nii'
    subjects = ['sub-01', 'sub-02', 'sub-03']
    #depth_ranges = [(0,0.5),(0.5,1)]
    #layer_contrasts = np.array([[0.5, 0.5],[-1, 1]])
    depth_ranges = None
    layer_contrasts = None
    group_contrasts = 'mean'  # currently only 'mean' is supported
    group_analysis_dir = '/ptmp/dchaimow/data/test_group_fslr_analysis'
    smooth_sigma = 3  # in mm

    group_fslr_analysis(
        firstlevel_analysis_dir,
        ciftify_dir,
        surf_dir,
        firstlevel_data_subpath,
        subjects,
        depth_ranges,
        layer_contrasts,
        group_contrasts,
        group_analysis_dir=group_analysis_dir,
        smooth_sigma=smooth_sigma)
    

    

