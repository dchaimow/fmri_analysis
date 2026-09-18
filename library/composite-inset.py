#!/usr/bin/env python3
"""
command line tool to composite a smaller "inset" image onto a corner of a
larger "main" image, adding a border around the inset first

usage: composite-inset.py <main_png> <inset_png> <output_png>
                           [--margin-px N] [--border-px N] [--border-color C]
                           [--corner {lower-left,lower-right,upper-left,upper-right}]
"""

import argparse
from PIL import Image, ImageOps

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("main_png")
parser.add_argument("inset_png")
parser.add_argument("output_png")
parser.add_argument("--margin-px", type=int, default=10)
parser.add_argument("--border-px", type=int, default=3)
parser.add_argument("--border-color", default="white")
parser.add_argument(
    "--corner",
    choices=["lower-left", "lower-right", "upper-left", "upper-right"],
    default="lower-left",
)
args = parser.parse_args()

with Image.open(args.main_png) as main_img:
    main_img.load()
    main_img = main_img.convert("RGB")
with Image.open(args.inset_png) as inset_img:
    inset_img.load()
    inset_img = inset_img.convert("RGB")

if args.border_px > 0:
    inset_img = ImageOps.expand(inset_img, border=args.border_px, fill=args.border_color)

if args.corner == "lower-left":
    position = (args.margin_px, main_img.height - inset_img.height - args.margin_px)
elif args.corner == "lower-right":
    position = (
        main_img.width - inset_img.width - args.margin_px,
        main_img.height - inset_img.height - args.margin_px,
    )
elif args.corner == "upper-left":
    position = (args.margin_px, args.margin_px)
else:  # upper-right
    position = (main_img.width - inset_img.width - args.margin_px, args.margin_px)

main_img.paste(inset_img, position)
main_img.save(args.output_png)
