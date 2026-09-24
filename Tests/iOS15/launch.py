"""Launch the real app on the booted legacy runtime; retain visual evidence.

This proves process launch, not route injection or physical TrollStore behavior.
The screenshot also needs visual review before accepting the launch check.
"""
import json
from pathlib import Path
import re
import subprocess
import sys

device, runtime, directory = sys.argv[1:]
output = Path(directory)
bundle = 'com.dm2mymcszt.trollroute'


def simctl(*args):
    return subprocess.check_output(['xcrun', 'simctl', *args], text=True)


devices = json.loads(simctl('list', 'devices', '-j'))['devices']
actual = next(d for d in devices[runtime] if d['udid'] == device)
assert actual['state'] == 'Booted', actual
runtimes = json.loads((output / 'runtimes.json').read_text())['runtimes']
system = next(r for r in runtimes if r['identifier'] == runtime)
assert system['version'].startswith('15.'), system
(output / 'launch-environment.json').write_text(json.dumps(dict(device=actual, runtime=system), indent=2))

launch = simctl('launch', '--terminate-running-process', device, bundle)
(output / 'launch.txt').write_text(launch)
match = re.search(re.escape(bundle) + r': (\d+)', launch)
assert match, launch
pid = int(match[1])


def assert_running(name):
    processes = simctl('spawn', device, 'launchctl', 'list')
    (output / name).write_text(processes)
    assert any(line.split()[0] == str(pid) and bundle in line
               for line in processes.splitlines() if line.split()), 'App process did not remain running'


assert_running('processes-before.txt')
# Keep actual startup/dyld diagnostics, then capture the resulting display.
logs = simctl('spawn', device, 'log', 'show', '--last', '2m', '--style', 'compact',
              '--predicate', 'process == "TrollRoute"')
(output / 'app-startup.log').write_text(logs)
simctl('io', device, 'screenshot', str(output / 'actual-app-ios15-launch.png'))
assert_running('processes-after.txt')
print(f'Actual TrollRoute process {pid} running on iOS {system["version"]}; review the launch screenshot.')
