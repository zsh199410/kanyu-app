#!/usr/bin/env python3
"""Asset readiness is distinct from XCTest and visual approval."""
import argparse, hashlib, json, struct
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--strict',action='store_true');a=p.parse_args()
root=Path(__file__).resolve().parents[2];manifest=json.loads((root/'design/v5/asset-manifest.json').read_text());items=[];seen={}
for asset in manifest['assets']:
    f=root/asset['path'];v=dict(path=asset['path'],theme=asset['theme'],role=asset['role'],status='MISSING')
    if f.exists():
        data=f.read_bytes();digest=hashlib.sha256(data).hexdigest()
        if data[:8]!=b'\x89PNG\r\n\x1a\n':v['status']='INVALID_PNG'
        else:
            width,height=struct.unpack('>II',data[16:24]);v.update(pixels=[width,height],sha256=digest)
            v['status']='PRESENT_PENDING_GPT_REVIEW' if width>=asset['minimumPixels'][0] and height>=asset['minimumPixels'][1] else 'TOO_SMALL'
            if digest in seen:v.update(status='DUPLICATE_ACROSS_THEMES',duplicateOf=seen[digest])
            seen[digest]=asset['path']
    items.append(v)
blocked=[x for x in items if x['status']!='PRESENT_PENDING_GPT_REVIEW']
result=dict(visualApproval=False,required=len(items),blocked=len(blocked),assets=items)
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(f"Artwork readiness: {len(items)-len(blocked)}/{len(items)} present; GPT visual approval pending")
if a.strict and blocked:raise SystemExit(1)
