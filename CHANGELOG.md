# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Each version is a git tag (`0.1.0`), and
`ImageMarkupKit.version` matches it.

## [Unreleased]

## [0.1.0] - 2026-10-02

First public release.

### Added

- `MarkupEditorViewController`: full-screen markup editor for one photo, several photos (board), an in-memory
  image or a saved package.
- Tools: pen, highlighter, 11 shapes, arrows and lines, polylines and curves, text, sticky notes, object eraser.
  Every mark can be selected, moved, resized, rotated, restyled, duplicated, locked, reordered and undone.
- Boards: photos side by side, arrows bound to photos, marks attached to the photo they are drawn on,
  Arrange (row / column / grid / tidy up).
- Export to one flattened JPEG or PNG at the photos' resolution, plus an optional re-editable package.
- `MarkupFeatures`: turn tool groups or single tools off in code or with a `MarkupFeatures.json`.
- Demo app in `Example/` with sample photos and scripted screenshot scenarios.

[Unreleased]: https://github.com/thnhsng/ImageMarkupKit/compare/0.1.0...HEAD
[0.1.0]: https://github.com/thnhsng/ImageMarkupKit/releases/tag/0.1.0
