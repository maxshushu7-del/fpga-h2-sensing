"""Verify release file hashes using only Python's standard library."""
from pathlib import Path
import hashlib,json,sys
root=Path(__file__).resolve().parents[2]
manifest=json.loads((root/'release_manifest.json').read_text(encoding='utf-8'))
errors=[]
for item in manifest['files']:
 p=root/item['path']
 if not p.is_file():errors.append('MISSING '+item['path']);continue
 got=hashlib.sha256(p.read_bytes()).hexdigest()
 if got!=item['sha256']:errors.append('CHANGED '+item['path'])
print('FILES',len(manifest['files']),'ERRORS',len(errors))
for e in errors:print(e)
sys.exit(bool(errors))
