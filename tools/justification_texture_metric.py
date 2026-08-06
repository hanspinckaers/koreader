#!/usr/bin/env python3
"""Score the visual texture of justified paragraphs from raster screenshots.

This deliberately does not score hyphenation count or ragged final-line length.
The final line is excluded because it is normally not justified.  The score is
intended for comparing renders of the same text, font, size, and page geometry;
it is not an absolute typography grade across unrelated documents.

The four components are:

* equal_space: equality of word spaces within each justified line;
* line_colour: consistency of ink density between justified lines;
* river_avoidance: lack of vertically aligned word-space channels;
* spacing_rhythm: stability of mean word-space width between lines.

Usage:
    tools/justification_texture_metric.py \
        --crop 40,75,565,300 \
        Greedy=greedy.png Hybrid=hybrid.png Optimized=optimized.png
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
from PIL import Image


@dataclass(frozen=True)
class TextureResult:
    label: str
    score: float
    equal_space: float
    line_colour: float
    river_avoidance: float
    spacing_rhythm: float
    justified_lines: int
    excluded_ragged_lines: int


def consecutive_runs(mask: np.ndarray) -> list[tuple[int, int]]:
    runs: list[tuple[int, int]] = []
    start: int | None = None
    for index, active in enumerate(mask):
        if active and start is None:
            start = index
        elif not active and start is not None:
            runs.append((start, index))
            start = None
    if start is not None:
        runs.append((start, len(mask)))
    return runs


def mean(values: Iterable[float]) -> float:
    items = list(values)
    return sum(items) / len(items) if items else 0.0


def parse_crop(value: str) -> tuple[int, int, int, int]:
    try:
        x0, y0, x1, y1 = (int(part) for part in value.split(","))
    except (TypeError, ValueError) as exc:
        raise argparse.ArgumentTypeError("crop must be x0,y0,x1,y1") from exc
    if x1 <= x0 or y1 <= y0:
        raise argparse.ArgumentTypeError("crop must have positive width and height")
    return x0, y0, x1, y1


def extract_lines(
    image_path: Path,
    crop: tuple[int, int, int, int] | None,
    threshold: int,
) -> list[dict[str, object]]:
    grey = np.asarray(Image.open(image_path).convert("L"), dtype=np.float64)
    if crop is not None:
        x0, y0, x1, y1 = crop
        grey = grey[y0:y1, x0:x1]

    binary = grey < threshold
    row_runs = [
        run for run in consecutive_runs(binary.sum(axis=1) >= 3)
        if run[1] - run[0] >= 4
    ]
    if len(row_runs) < 2:
        raise ValueError(f"{image_path}: fewer than two text lines found")

    median_height = float(np.median([end - start for start, end in row_runs]))
    min_word_gap = max(3, int(round(median_height * 0.15)))
    lines: list[dict[str, object]] = []

    for top, bottom in row_runs:
        line_binary = binary[top:bottom]
        active_columns = line_binary.any(axis=0)
        ink_columns = np.flatnonzero(active_columns)
        if len(ink_columns) == 0:
            continue
        left, right = int(ink_columns[0]), int(ink_columns[-1]) + 1
        gap_runs = [
            run for run in consecutive_runs(~active_columns[left:right])
            if run[1] - run[0] >= min_word_gap
        ]
        gaps = np.asarray([end - start for start, end in gap_runs], dtype=float)
        gap_centres = np.asarray(
            [left + (start + end) / 2 for start, end in gap_runs], dtype=float
        )
        darkness = (255.0 - grey[top:bottom, left:right]) / 255.0
        lines.append({
            "width": right - left,
            "height": bottom - top,
            "gaps": gaps,
            "gap_centres": gap_centres,
            "ink_density": float(darkness.mean()),
        })

    return lines


def score_texture(
    label: str,
    image_path: Path,
    crop: tuple[int, int, int, int] | None,
    threshold: int,
) -> TextureResult:
    lines = extract_lines(image_path, crop, threshold)
    maximum_width = max(int(line["width"]) for line in lines)
    justified = [
        line for line in lines
        if int(line["width"]) >= 0.70 * maximum_width
        and len(line["gaps"]) >= 2  # type: ignore[arg-type]
    ]
    if len(justified) < 2:
        raise ValueError(f"{image_path}: fewer than two justified lines found")

    # Equality inside a line. RMS makes one visibly uneven line matter without
    # letting the number of words on that line dominate the paragraph.
    line_gap_cvs = []
    for line in justified:
        gaps = line["gaps"]
        assert isinstance(gaps, np.ndarray)
        line_gap_cvs.append(float(gaps.std() / gaps.mean()))
    equal_space_penalty = math.sqrt(mean(value * value for value in line_gap_cvs))
    equal_space = 100.0 * math.exp(-4.0 * equal_space_penalty)

    densities = np.asarray([float(line["ink_density"]) for line in justified])
    colour_penalty = float(densities.std() / densities.mean())
    line_colour = 100.0 * math.exp(-8.0 * colour_penalty)

    # A river is approximated by word-space centres recurring at nearby x
    # positions on adjacent lines. The scale is about one third of line height.
    river_samples: list[float] = []
    for first, second in zip(justified, justified[1:]):
        first_centres = first["gap_centres"]
        second_centres = second["gap_centres"]
        assert isinstance(first_centres, np.ndarray)
        assert isinstance(second_centres, np.ndarray)
        sigma = 0.35 * mean((int(first["height"]), int(second["height"])))
        for source, target in (
            (first_centres, second_centres),
            (second_centres, first_centres),
        ):
            for centre in source:
                distance = float(np.min(np.abs(target - centre)))
                river_samples.append(math.exp(-(distance * distance) / (2 * sigma * sigma)))
    river_alignment = mean(river_samples)
    river_avoidance = 100.0 * (1.0 - river_alignment)

    gap_means = []
    for line in justified:
        gaps = line["gaps"]
        assert isinstance(gaps, np.ndarray)
        gap_means.append(float(gaps.mean()))
    rhythm_penalty = mean(
        abs(math.log(second / first))
        for first, second in zip(gap_means, gap_means[1:])
    )
    spacing_rhythm = 100.0 * math.exp(-2.0 * rhythm_penalty)

    # Perceptual texture weights. Hyphens and the ragged final-line length have
    # intentionally zero weight.
    score = (
        0.30 * equal_space
        + 0.30 * line_colour
        + 0.30 * river_avoidance
        + 0.10 * spacing_rhythm
    )
    return TextureResult(
        label=label,
        score=score,
        equal_space=equal_space,
        line_colour=line_colour,
        river_avoidance=river_avoidance,
        spacing_rhythm=spacing_rhythm,
        justified_lines=len(justified),
        excluded_ragged_lines=len(lines) - len(justified),
    )


def parse_input(value: str) -> tuple[str, Path]:
    if "=" in value:
        label, path_text = value.split("=", 1)
        return label, Path(path_text)
    path = Path(value)
    return path.stem, path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("images", nargs="+", help="PNG path, optionally LABEL=path")
    parser.add_argument("--crop", type=parse_crop, help="paragraph crop: x0,y0,x1,y1")
    parser.add_argument("--threshold", type=int, default=200, help="ink threshold, default 200")
    parser.add_argument("--json", action="store_true", help="emit JSON instead of a table")
    args = parser.parse_args()

    results = [
        score_texture(label, path, args.crop, args.threshold)
        for label, path in map(parse_input, args.images)
    ]
    results.sort(key=lambda result: result.score, reverse=True)

    if args.json:
        print(json.dumps([asdict(result) for result in results], indent=2))
        return

    print("Policy       Texture  Equal spaces  Line colour  River-free  Rhythm")
    for result in results:
        print(
            f"{result.label:<12} {result.score:7.1f} {result.equal_space:13.1f}"
            f" {result.line_colour:12.1f} {result.river_avoidance:11.1f}"
            f" {result.spacing_rhythm:7.1f}"
        )
    print("Hyphen penalty: 0; ragged final line: excluded")


if __name__ == "__main__":
    main()
