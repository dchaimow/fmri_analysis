"""
Voxel depths from surfaces.

The code lives in the vdfs package (https://github.com/dchaimow/vdfs), this module only re-exports it, so
that `from fmri_analysis import voxeldepths_from_surfaces` keeps working. vdfs needs to be installed in the
environment:

    pip install "git+https://github.com/dchaimow/vdfs@v1.1.0"

If vdfs is not installed, fmri_analysis can still be imported (and names from this module can be imported),
but calling any function from this module raises an ImportError.
"""
try:
    from vdfs.voxeldepths_from_surfaces import *  # noqa: F401,F403
except ModuleNotFoundError as e:
    if e.name != "vdfs":
        raise
    _VDFS_MISSING = ("fmri_analysis.voxeldepths_from_surfaces requires the vdfs package, install it with: "
                     'pip install "git+https://github.com/dchaimow/vdfs@v1.1.0"')

    def __getattr__(name):
        # module attributes that the import system looks up must not be replaced
        if name.startswith("__"):
            raise AttributeError(name)

        def vdfs_missing(*args, **kwargs):
            raise ImportError(_VDFS_MISSING)
        return vdfs_missing
