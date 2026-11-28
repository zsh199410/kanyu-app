#!/usr/bin/env python3
"""Unaltered actual screenshots next to concept references, not a fidelity score."""
import argparse,json,shutil
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.image as mpimg
p=argparse.ArgumentParser();p.add_argument('attachments',type=Path);p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
root=Path(__file__).resolve().parents[2];names={'song':'01-approved-song-pro.png','night':'02-approved-night-pro.png','celadon':'03-celadon-earlier-reference.png','collection':'04-collection-earlier-reference.png'}
manifest=json.loads((a.attachments/'manifest.json').read_text());index=[]
for group in manifest:
    for item in group['attachments']:
        title=item.get('suggestedHumanReadableName','')
        if not title.startswith('v5-visual-') or not item['exportedFileName'].endswith('.png'):continue
        parts=title.split('-');theme=parts[2];screen=parts[3].split('_')[0]
        source=a.attachments/item['exportedFileName'];dest=a.output/f'{theme}-{screen}-actual.png';shutil.copyfile(source,dest)
        if screen=='home':
            fig,axes=plt.subplots(1,2,figsize=(9,11));axes[0].imshow(mpimg.imread(root/'design/v5/reference'/names[theme]));axes[1].imshow(mpimg.imread(source))
            for ax in axes:ax.axis('off')
            axes[0].set_title('Concept reference'+(' (earlier)' if theme in ['celadon','collection'] else ' (approved)'))
            axes[1].set_title('Actual native app | fixed fixture | NOT approved')
            fig.tight_layout();fig.savefig(a.output/f'{theme}-side-by-side.png',dpi=160);plt.close(fig)
        index.append(dict(theme=theme,screen=screen,file=dest.name,visualApproval=False))
(a.output/'index.json').write_text(json.dumps(dict(screenshots=index,visualApproval=False,score=None,reason='Aesthetic approval and reviewed measurement bounds pending; asset readiness is verified separately'),indent=2)+'\n')
assert len(index)==24,f'Expected 24 actual screenshots, got {len(index)}'
print('Actual screenshots packaged:',len(index),'No fidelity score inferred.')
