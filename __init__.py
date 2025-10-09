"""
fMRI Analysis Library
A collection of tools for fMRI data analysis and visualization.
"""

import os
import importlib
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

def __getattr__(name):
    """Dynamically import modules from library directory when accessed."""
    import importlib.util  # Move import here to avoid top-level import
    
    library_path = Path(__file__).parent / "library"
    module_file = library_path / f"{name}.py"
    
    if module_file.exists():
        # Import the module dynamically
        spec = importlib.util.spec_from_file_location(
            f"fmri_analysis.library.{name}", 
            module_file
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        
        # Cache it in globals for future access
        globals()[name] = module
        return module
    
    raise AttributeError(f"module 'fmri_analysis' has no attribute '{name}'")

def __dir__():
    """List all available modules for tab completion."""
    library_path = Path(__file__).parent / "library"
    modules = [f.stem for f in library_path.glob("*.py") if f.name != "__init__.py"]
    return modules + ["__version__"]