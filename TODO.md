# TODO

Prioritized next steps for making this repository easier to use, maintain, and reuse.

## High Priority

- [ ] review automatically generated documentation and todos
- [ ] Add a reproducible Python environment file.
  Suggested output: `environment.yml` for Conda, with a short note on which dependencies are Python packages versus system tools.

- [ ] Add an external-tools setup checklist.
  Cover AFNI, FSL, FreeSurfer, ANTs, Connectome Workbench, ciftify, LAYNII, SPM/CAT12, GNU `parallel`, `jq`, and any expected environment variables.

- [ ] Write 1-2 end-to-end workflow guides in `docs/workflows/`.
  Best first candidates:
  - MP2RAGE / anatomy preprocessing
  - VASO preprocessing and trial averaging

- [ ] Document expected directory and filename conventions.
  Especially:
  - `*_nulled.nii` / `*_notnulled.nii`
  - FreeSurfer subject directories
  - ciftify outputs
  - files expected inside an `analysis_dir`

## Medium Priority

- [ ] Add minimal packaging with `pyproject.toml`.
  Goal: allow `pip install -e .` instead of relying on `PYTHONPATH`.

- [ ] Add a small smoke-test suite.
  Start with:
  - import tests for the main Python modules
  - tests for pure-Python utility functions
  - one or two CLI help / argument parsing checks where practical

- [ ] Mark stable versus experimental scripts more clearly.
  Options:
  - move unfinished code into `library/experimental/`
  - or label status in the docs and keep the layout unchanged

- [ ] Standardize command-line usage/help text across shell scripts.
  Some scripts already have clear usage headers; others rely on comments or implicit conventions.

- [ ] Remove or document environment-specific hard-coded paths.
  These appear in several places and make reuse on a different system harder.

## Code Cleanup

- [ ] Turn `library/group_fslr_analysis.py` into a real CLI or document it as import-only.

- [ ] Replace the direct test call in `library/generate_layer_contrast_roi.py` with proper argument parsing.

- [ ] Either finish the CLI for `library/generate_roi.py` or explicitly keep it as an importable interface only.

- [ ] Finish or retire `library/fs_to_epiT1_reg.py`.
  The file contains TODO notes and is not currently a complete command-line tool.

- [ ] Review `library/interfaces.py`.
  Decide whether to complete it, move it to an experimental area, or remove unused code.

- [ ] Review `library/upsample_for-layer-sampling.sh`.
  It appears incomplete and should be finished, removed, or marked as internal.

- [ ] Audit shell scripts for stricter error handling.
  Consider adding `set -Eeuo pipefail` where it is safe and appropriate.

## Documentation

- [ ] Add per-workflow examples with real command lines and expected outputs.

- [ ] Add a short "Which file should I use?" guide for common tasks.

- [ ] Expand the Python API docs for the most reusable modules:
  - `library/layer_analysis.py`
  - `library/anatomy.py`
  - `library/surface_plotting.py`
  - `library/voxeldepths_from_surfaces.py`

- [ ] Add notes on which scripts are wrappers around external tools versus which implement their own analysis logic.

## Maintenance

- [ ] Add a license file.

- [ ] Add a changelog or lightweight release/versioning policy.

- [ ] Decide whether to keep shell scripts and Python modules in the same `library/` directory long-term.

- [ ] Add a small set of example datasets or test fixtures if redistribution is possible.
