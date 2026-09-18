#!/usr/bin/env python3
"""
Runs fsleyes render with a hook to zoom the view to the ROI mask.
The ROI mask must be the second overlay in the overlay list, and the first overlay must be 
the background image. The ROI mask must be 3D, and the background image must be 3D or 4D. 
The ROI mask must be non-empty. The zoomed view is centered on the ROI mask, and the visible 
rectangle is expanded to match the output aspect ratio. 
Usage: fsleyes_render_zoom_roi.py <fsleyes render args>
"""
import sys
from itertools import product

import numpy as np
from fsleyes import render


def fit_roi(overlayList, displayCtx, sceneOpts, canvases):
    if len(overlayList) < 2:
        raise ValueError("Load the background first and ROI mask second.")

    roi = overlayList[1]
    data = np.asarray(roi.data)

    if data.ndim != 3:
        raise ValueError("The ROI mask must be 3D.")

    voxels = np.argwhere(np.isfinite(data) & (data != 0))
    if len(voxels) == 0:
        raise ValueError("The ROI mask is empty.")

    # Full voxel edges, plus four mask voxels on each side.
    lower = voxels.min(axis=0) - 4.5
    upper = voxels.max(axis=0) + 4.5

    corners = np.array(list(product(*zip(lower, upper))))
    opts = displayCtx.getOpts(roi)
    corners = opts.transformCoords(corners, "voxel", "display")

    lo = corners.min(axis=0)
    hi = corners.max(axis=0)
    centre = (lo + hi) / 2
    displayCtx.location = centre

    axial = next(
        (c for c in canvases if c.opts.zax == 2), None
    )
    if axial is None:
        raise ValueError("An axial orthographic canvas must be enabled.")

    # Expand the rectangle to match the output aspect ratio.
    width, height = axial.GetSize()
    units_per_pixel = max(
        (hi[0] - lo[0]) / width,
        (hi[1] - lo[1]) / height,
    )
    half_width = units_per_pixel * width / 2
    half_height = units_per_pixel * height / 2

    # Set the visible rectangle directly for off-screen rendering.
    axial.opts.displayBounds[:] = (
        centre[0] - half_width, centre[0] + half_width,
        centre[1] - half_height, centre[1] + half_height,
    )


if __name__ == "__main__":
    render.main(sys.argv[1:], hook=fit_roi)