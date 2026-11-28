#!/usr/bin/env python3
"""Asset integrity is distinct from XCTest and GPT's visual approval."""
import argparse
import hashlib
import json
from pathlib import Path
from png_artwork import inspect_png, InvalidArtwork


def verify(root, manifest):
    items = []; seen = {}; pixels_seen = {}
    for asset in manifest['assets']:
        path = root / asset['path']
        item = dict(path=asset['path'], theme=asset['theme'], role=asset['role'], status='MISSING')
        if path.is_file():
            try:
                if path.stat().st_size > 64 * 1024 * 1024:
                    raise InvalidArtwork('Compressed file budget exceeded')
                data = path.read_bytes(); sha = hashlib.sha256(data).hexdigest()
                item.update(inspect_png(data), sha256=sha, status='PRESENT_PENDING_GPT_REVIEW')
                if any(actual < minimum for actual, minimum in zip(item['pixels'], asset['minimumPixels'])):
                    item['status'] = 'TOO_SMALL'
                elif asset['alphaRequired'] and not item['alphaChannel']:
                    item['status'] = 'ALPHA_CHANNEL_MISSING'
                elif asset.get('sha256') and sha != asset['sha256']:
                    item['status'] = 'SHA256_MISMATCH'
                elif sha in seen or item['pixelSHA256'] in pixels_seen:
                    item.update(status='DUPLICATE_ARTWORK', duplicateOf=seen.get(sha) or pixels_seen[item['pixelSHA256']])
                seen[sha] = asset['path']; pixels_seen[item['pixelSHA256']] = asset['path']
            except (InvalidArtwork, OSError) as error:
                item.update(status='INVALID_PNG', error=str(error))
        items.append(item)
    blocked = [x for x in items if x['status'] != 'PRESENT_PENDING_GPT_REVIEW']
    return dict(visualApproval=False, required=len(items), blocked=len(blocked), assets=items)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--strict', action='store_true')
    args = parser.parse_args(); root = Path(__file__).resolve().parents[2]
    result = verify(root, json.loads((root / 'design/v5/asset-manifest.json').read_text()))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(f"Artwork readiness: {result['required']-result['blocked']}/{result['required']} present; GPT visual approval pending")
    if args.strict and result['blocked']:
        raise SystemExit(1)

if __name__ == '__main__':
    main()
