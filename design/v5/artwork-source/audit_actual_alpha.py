#!/usr/bin/env python3
"""Actual pixel-alpha audit for original PNGs (authoring/QA only)."""
import argparse,hashlib,json
from pathlib import Path
from PIL import Image
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);args=p.parse_args()
root=Path(__file__).resolve().parents[3];m=json.loads((root/'design/v5/asset-manifest.json').read_text());items=[]
for a in m['assets']:
 f=root/a['path']
 if not f.is_file():raise ValueError('Missing '+a['path'])
 with Image.open(f) as image:
  image.load();v=dict(path=a['path'],pixels=list(image.size),mode=image.mode,sha256=hashlib.sha256(f.read_bytes()).hexdigest())
  assert v['sha256']==a['sha256'],a['path']
  if a['alphaRequired']:
   assert image.mode=='RGBA',a['path']
   alpha=image.getchannel('A');hist=alpha.histogram();v.update(alphaRange=list(alpha.getextrema()),clearFraction=hist[0]/(image.width*image.height))
   assert v['alphaRange'][0]==0 and v['alphaRange'][1]>=220 and v['clearFraction']>=.01,v
  items.append(v)
args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(dict(required=60,checked=len(items),visualApproval=False,assets=items),ensure_ascii=False,indent=2)+'\n')
print('Real alpha/decode/SHA audit:',len(items),'/ 60')
