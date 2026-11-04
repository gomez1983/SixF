import json, re, urllib.request
from pathlib import Path
lock = Path('pubspec.lock').read_text(encoding='utf-8')
packages = []
for name, block in re.findall(r'^  ([\w]+):\n(.*?)(?=^  \w+:|^sdks:|\Z)', lock, re.M | re.S):
    version = re.search(r'^    version: "([^"]+)"', block, re.M)
    if version and 'source: hosted' in block:
        packages.append({'package': {'name': name, 'ecosystem': 'Pub'}, 'version': version[1]})
req = urllib.request.Request('https://api.osv.dev/v1/querybatch',
    data=json.dumps({'queries': packages}).encode(), headers={'Content-Type':'application/json'})
with urllib.request.urlopen(req, timeout=45) as response:
    results = json.load(response)['results']
findings = [{'name':p['package']['name'], 'version':p['version'], 'vulns':r.get('vulns',[])}
    for p,r in zip(packages, results) if r.get('vulns')]
out = {'source':'OSV querybatch', 'packages_checked':len(packages), 'findings':findings}
Path('docs/security/audits/support/2026-11-04-dependencies.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print(json.dumps(out))
