"""
fMRI Analysis Library
A collection of tools for fMRI data analysis and visualization.
"""


from pathlib import Path

def _get_git_hash():
    """Get git commit hash without running git command."""
    try:
        repo_root = Path(__file__).parent
        git_dir = repo_root / ".git"
        
        if not git_dir.exists():
            return "unknown"
        
        # Read HEAD to find current branch/commit
        head_file = git_dir / "HEAD"
        if not head_file.exists():
            return "unknown"
            
        head_content = head_file.read_text().strip()
        
        if head_content.startswith("ref: "):
            # HEAD points to a branch reference
            ref_path = head_content[5:]  # Remove "ref: " prefix
            ref_file = git_dir / ref_path
            if ref_file.exists():
                commit_hash = ref_file.read_text().strip()
            else:
                return "unknown"
        else:
            # HEAD contains the commit hash directly (detached HEAD)
            commit_hash = head_content
        
        # Return short hash (first 7 characters)
        return commit_hash[:7]
        
    except Exception:
        return "unknown"

# Version info
__version__ = f"0.1.0-dev+{_get_git_hash()}"

# Import the library subpackage
from . import library

# Expose commonly used functions at the top level
from .library import (
    group_fslr_analysis,
    layer_analysis,
    anatomy,
    cluster_surface,
    generate_roi,
    plot_surf_slice,
    surface_plotting,
    voxel_space_plotting,
    voxeldepths_from_surfaces)

__all__ = ['library', 'group_fslr_analysis', 'layer_analysis', 'anatomy', 'cluster_surface', 
           'generate_roi', 'plot_surf_slice', 'surface_plotting', 'voxel_space_plotting', 
           'voxeldepths_from_surfaces']

