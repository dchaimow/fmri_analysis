#! /usr/bin/env python3
import anatomy
import argparse

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="mp2rage_recon-all: runs a modified FreeSurfer recon-all pipeline (brain mask from CAT12) "
                    "on MP2RAGE data (mprageized) or, with --mprage, on MPRAGE data (SPM bias corrected) "
                    "(requires freesurfer, SPM/CAT12 and optionally gradient_unwarp.py and FSL)"
    )
    parser.add_argument(
        "inputs", nargs="+", metavar="input",
        help="paths to nifti files containing MP2RAGE INV2 and UNI data (in this order), "
             "or, with --mprage, MPRAGE data"
    )
    parser.add_argument(
        "--mprage", action="store_true", help="input is a single MPRAGE instead of MP2RAGE INV2 and UNI")
    parser.add_argument("--fs_dir", type=str, help="path to output fs dir")
    parser.add_argument("--spm_dir", type=str, help="path to spm installation")
    parser.add_argument(
        "--gdc_coeff_file",
        help="run gradient disortion correction using specified coefficient file",)
    parser.add_argument(
        "--brainmask",
        help="use this brain mask (voxel grid of the input data) instead of the one from the CAT12 segmentation; "
             "with --gdc_coeff_file it must be in gdc corrected space (e.g. from an earlier run with gdc)",)
    parser.add_argument(
        "--intermediate_dir",
        help="write intermediate files (e.g. mprageized/bias corrected T1w, brain mask) to this directory",)
    parser.add_argument(
        "--ncpu",
        type=int,
        default=1,
        help="number of CPUs to use for parallel processing (default: 1)",
    )

    args = parser.parse_args()

    if args.mprage and len(args.inputs) != 1:
        parser.error("with --mprage exactly one input (MPRAGE) is required")
    if not args.mprage and len(args.inputs) != 2:
        parser.error("exactly two inputs (INV2 and UNI) are required (or use --mprage for MPRAGE data)")

    if args.spm_dir is not None:
        anatomy.set_spm_path(args.spm_dir)

    if args.mprage:
        anatomy.mprage_recon_all(
            args.inputs[0],
            output_fs_dir=args.fs_dir,
            gdc_coeff_file=args.gdc_coeff_file,
            n_cpu=args.ncpu,
            input_brainmask_file=args.brainmask,
            intermediate_dir=args.intermediate_dir
        )
    else:
        anatomy.mp2rage_recon_all(
            args.inputs[0],
            args.inputs[1],
            output_fs_dir=args.fs_dir,
            gdc_coeff_file=args.gdc_coeff_file,
            n_cpu=args.ncpu,
            input_brainmask_file=args.brainmask,
            intermediate_dir=args.intermediate_dir
        )
