"""Copy and summarize the latest actual Xcode test result. Does not run tests."""
from pathlib import Path
import json
import shutil
import subprocess
source = max(Path('/Users/kevishsewliya/Library/Developer/Xcode/DerivedData').glob('FitOut-*/Logs/Test/*.xcresult'), key=lambda p: p.stat().st_mtime)
if not (source / 'Info.plist').exists():
    raise SystemExit('Latest Xcode test run is still in progress; no completed result yet.')
target = Path('.build/LatestTests.xcresult')
if target.exists():
    shutil.rmtree(target)
shutil.copytree(source, target)
result = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'object', '--legacy', '--format', 'json', '--path', str(target)]))
print(source.name)
print(json.dumps(result.get('metrics', {}), indent=2))
print(json.dumps(result.get('issues', {}), indent=2))
for action in result.get('actions', {}).get('_values', []):
    print('Status:', action.get('actionResult', {}).get('status', {}).get('_value'))
