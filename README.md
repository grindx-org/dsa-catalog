# dsa-catalog

DSA problem catalog and testcase bundle source for `grindx`.

This repo publishes:
- canonical DSA catalog data under `grindx/catalog/`
- a minimal public testcase bundle packer at `scripts/build-testcases.sh`

This repo does not currently publish the full internal testcase-generation pipeline.

## Testcase bundle

`grindx` consumes a compressed testcase bundle plus `manifest.json`.

Build one locally:

```bash
bash scripts/build-testcases.sh \
  --output-dir dist/testcases-release \
  --release-tag testcases-v1 \
  --min-app-version 0.2.4
```

Outputs:
- `dist/testcases-release/testcases.tar.gz`
- `dist/testcases-release/manifest.json`

Manifest contract:
- `manifest_version`: manifest schema version
- `bundle_format_version`: archive layout version
- `bundle_kind`: currently `testcases-only`
- `release_tag`: bundle version consumed by `grindx`
- `min_app_version`: minimum compatible `grindx` version
- `sha256`: archive checksum
- `problem_count`: number of bundled problems
- `problems`: bundled problem IDs

`grindx --fetch-testcases` should point at the published `manifest.json` for a release.
