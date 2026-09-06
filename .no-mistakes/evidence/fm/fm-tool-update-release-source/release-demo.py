import json, os, pathlib, subprocess, tempfile
root = pathlib.Path.cwd()
evidence = pathlib.Path('/Users/agardner/.no-mistakes/evidence/01M1V653KMSHJHHNG16Z05HT41')
lines = ['Published-release CLI demonstration', 'Real checker, registration and watcher; fixture installed commands and HTTP transport.', 'No installed tools are updated.']
with tempfile.TemporaryDirectory(prefix='.release-demo-', dir=root) as tmp:
    home = pathlib.Path(tmp)
    for directory in ['bin', 'config', 'state']:
        (home/directory).mkdir()
    tools = json.loads((root/'docs/examples/watched-tools.json').read_text())['tools'][2:5]
    for entry, version in zip(tools, ['0.8.0', '0.2.4', '0.1.47']):
        entry['command'] = 'demo-' + entry['name']
        p = home/'bin'/entry['command']
        p.write_text('#!/bin/sh\n[ "$1" = --version ] || exit 99\nprintf "%s\\n" "'+version+'"\n')
        p.chmod(0o755)
    config = home/'config/watched-tools.json'
    config.write_text(json.dumps({'tools': tools}))
    curl = home/'bin/curl'
    curl.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$FM_HOME/http.log"
case "$*" in
 *herdrdev/herdr/releases/latest*) echo '{"tag_name":"v0.8.2"}' ;;
 *tasks-axi/latest*) echo '{"version":"0.2.5"}' ;;
 *gnhf/latest*) echo '{"version":"0.1.49"}' ;;
 *) exit 99 ;;
esac
''')
    curl.chmod(0o755)
    env = dict(os.environ, FM_HOME=str(home), PATH=str(home/'bin')+':'+os.environ['PATH'], FM_CHECK_TIMEOUT='30', FM_TOOL_UPDATE_INTERVAL='0', FM_POLL='1', FM_SIGNAL_GRACE='1', FM_CHECK_INTERVAL='1')
    def run(args, code=0):
        result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=40)
        lines.extend(['\n$ '+ ' '.join(str(a).replace(str(home), '<fixture-home>') for a in args), result.stdout.rstrip() or '(no stdout)', result.stderr.rstrip(), 'exit: '+str(result.returncode)])
        assert result.returncode == code, result
        return result.stdout
    run(['bin/fm-tool-update-check.sh', 'arm'])
    out = run(['bin/fm-watch-checkpoint.sh', '--seconds', '10'])
    assert 'check:' in out
    for name in ['herdr', 'tasks-axi', 'gnhf']:
        assert name+' update available: installed' in out, out
    lines.extend(['\nPersisted report state:', (home/'state/.tool-updates').read_text()])
    assert not run(['bin/fm-tool-update-check.sh', 'check'])
    for entry, version in zip(tools, ['0.8.2','0.2.5','0.1.49']):
        p = home/'bin'/entry['command']
        p.write_text('#!/bin/sh\n[ "$1" = --version ] || exit 99\necho '+version+'\n')
    lines.append('\nInstalled-version fixtures now equal the published versions.')
    assert not run(['bin/fm-tool-update-check.sh', 'check'])
    run(['bin/fm-tool-update-check.sh', 'disarm'])
    tools[1]['published']['package'] = 'invalid package'
    config.write_text(json.dumps({'tools':tools}))
    run(['bin/fm-tool-update-check.sh', 'arm'], 1)
    assert not (home/'state/tool-updates.check.sh').exists()
    lines.extend(['\nHTTP transport requests:', (home/'http.log').read_text(), '\nVerified: all three releases reached a watcher wake; repeated reports and current versions were silent; malformed registry refused arming.'])
(evidence/'release-demo.txt').write_text('\n'.join(line for line in lines if line)+'\n')
print((evidence/'release-demo.txt').read_text())
