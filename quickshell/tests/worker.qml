import QtQuick
import Quickshell
import Quickshell.Io
import "../services" as Native

// The real Worker supervisor and resident pentad_worker.py, with a recording fake tesseract on
// PATH (the runner stages it; no model module is staged, so no request leaves the machine).
// Covers hello, round trips, the result cache, cancel, crash restart, a wrong protocol, preview,
// idle exit, FileTools through the worker and the Capabilities broker on top of it.
ShellRoot {
    id: root
    property var checks: []
    property int phase: 0
    property int waited: 0
    property var results: ({})
    property var fileJobs: ({})
    property var events: []
    property var marks: ({})
    readonly property string home: Quickshell.env('HOME')
    readonly property string tesseractLog: Quickshell.env('XDG_STATE_HOME') + '/tesseract-calls.log'
    readonly property var models: ({
            schemaVersion: 1,
            providers: [
                {
                    id: 'local',
                    kind: 'ollama',
                    name: 'Ollama',
                    baseUrl: 'http://127.0.0.1:11434',
                    credential: '',
                    credentialEnv: ''
                },
                {
                    id: 'cloud',
                    kind: 'openai-compatible',
                    name: 'Cloud',
                    baseUrl: 'https://models.example.invalid/v1',
                    credential: '',
                    credentialEnv: ''
                }
            ],
            roles: {
                chat: 'local/qwen3.5:9b',
                fast: 'cloud/gpt-test',
                vision: '',
                embed: '',
                translate: ''
            },
            roleOptions: {},
            grants: {},
            privacy: {
                localOnly: false
            },
            worker: {
                idleExitSeconds: 600,
                cacheMiB: 64
            }
        })
    readonly property var external: ({
            id: 'example.reader',
            capabilities: ['image.ocr', 'llm.chat', 'text.embed']
        })
    readonly property var builtin: ({
            id: 'pentad.reader',
            capabilities: ['image.ocr', 'llm.chat']
        })

    function check(name, passed, detail) {
        checks = checks.concat([{
                name: name,
                passed: passed === true,
                detail: passed === true ? '' : String(detail === undefined ? '' : detail)
            }]);
    }
    function helper(name) {
        return decodeURIComponent(Qt.resolvedUrl('helpers/' + name).toString().replace(/^file:\/\//, ''));
    }
    function input(name) {
        return 'file://' + home + '/worker-inputs/' + name;
    }
    function keep(key, value) {
        results = Object.assign({}, results, {
            [key]: value
        });
    }
    function recorder(key) {
        return {
            onResult: value => root.keep(key, value)
        };
    }
    function have(keys) {
        return keys.every(key => results[key] !== undefined);
    }
    function json(value) {
        return JSON.stringify(value);
    }
    function ocrCalls() {
        reader.path = tesseractLog;
        reader.reload();
        const text = reader.text() || '';
        return text.split('\n').filter(line => line.length > 0).length;
    }
    function runFile(key, operation, inputs, options, text) {
        const id = tools.run(operation, inputs, options, text, 30000);
        fileJobs = Object.assign({}, fileJobs, {
            [id]: key
        });
        return id;
    }
    // Waits until a predicate holds or about eight seconds pass, then runs the phase's checks.
    function settled(ready) {
        if (!ready && ++waited < 80)
            return false;
        waited = 0;
        return true;
    }
    function finish() {
        step.stop();
        console.log('PENTAD_TEST ' + JSON.stringify({
            status: checks.length > 0 && checks.every(c => c.passed) ? 'pass' : 'fail',
            checks: checks
        }));
        Qt.quit();
    }

    FileView {
        id: reader
        blockAllReads: true
        printErrors: false
    }
    Native.Worker {
        id: mainWorker
        helperPath: root.helper('pentad_worker.py')
    }
    Native.Worker {
        id: previewWorker
        preview: true
        helperPath: root.helper('pentad_worker.py')
    }
    Native.Worker {
        id: badWorker
        helperPath: root.helper('fake_worker_v2.py')
    }
    Native.Worker {
        id: idleWorker
        helperPath: root.helper('pentad_worker.py')
        cacheRoot: Quickshell.env('XDG_CACHE_HOME') + '/pentad/idle-worker'
        idleExitSeconds: 1
    }
    Native.FileTools {
        id: tools
        helperPath: root.helper('pentad_file_tool.py')
        worker: mainWorker
        onJobFinished: (requestId, result) => {
            if (root.fileJobs[requestId])
                root.keep(root.fileJobs[requestId], result);
        }
    }
    Native.Capabilities {
        id: caps
        worker: mainWorker
        models: root.models
        onProgress: (requestId, data) => root.events = root.events.concat([{
                    id: requestId,
                    kind: 'progress',
                    data: data
                }])
        onCommandFinished: (requestId, result) => root.events = root.events.concat([{
                    id: requestId,
                    kind: 'finished',
                    result: result
                }])
    }
    Native.Capabilities {
        id: safeCaps
        safeMode: true
        worker: mainWorker
        models: root.models
    }
    Native.Capabilities {
        id: previewCaps
        preview: true
        worker: previewWorker
        models: root.models
    }
    function eventsFor(id) {
        return events.filter(event => event.id === id);
    }

    Timer {
        id: step
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (root.phase === 0) {
                previewWorker.request('worker.stats', {}, root.recorder('preview'));
                badWorker.request('worker.stats', {}, root.recorder('bad'));
                idleWorker.request('worker.stats', {}, root.recorder('idle'));
                mainWorker.request('worker.stats', {}, root.recorder('stats'));
                root.check('results-never-arrive-before-request-returns', root.results.stats === undefined && root.results.preview === undefined, root.json(root.results));
                root.check('first-request-starts-the-process', mainWorker.worker.running || mainWorker.helloTimer.running, mainWorker.state);
                root.phase = 1;
            } else if (root.phase === 1) {
                if (!root.settled(root.have(['preview', 'bad', 'stats', 'idle'])))
                    return;
                root.check('preview-never-starts', root.results.preview && root.results.preview.reason === 'preview' && !previewWorker.worker.running && previewWorker.state === 'unavailable' && !previewWorker.accepts('file.run'), root.json(root.results.preview));
                root.check('hello-then-round-trip', root.results.stats && root.results.stats.ok === true && mainWorker.state === 'ready' && mainWorker.accepts('file.run') && !mainWorker.accepts('vendor.nothing'), root.json(root.results.stats) + ' ' + mainWorker.state);
                root.check('wrong-protocol-is-unavailable', root.results.bad && root.results.bad.reason === 'unavailable' && badWorker.state === 'unavailable' && !badWorker.accepts('file.run'), root.json(root.results.bad) + ' ' + badWorker.state);
                // Recovery: nothing for 30 s after the worker went down, then one fresh start.
                const tooEarly = badWorker.recover();
                badWorker.client.downSinceMs = Date.now() - 30000;
                const recovered = badWorker.recover();
                root.check('down-worker-recovers-once-per-window', tooEarly === false && recovered === true && badWorker.state === 'idle' && badWorker.accepts('file.run') && previewWorker.recover() === false, tooEarly + ' ' + recovered + ' ' + badWorker.state);
                root.marks = {
                    pid: mainWorker.worker.processId,
                    ocr: root.ocrCalls()
                };
                mainWorker.request('image.ocr', {
                    uri: root.input('page.png'),
                    psm: 6,
                    filterInstalled: true
                }, root.recorder('ocr'));
                mainWorker.request('vendor.nothing', {}, root.recorder('unsupported'));
                const fileId = root.runFile('checksum', 'checksum', [], {}, 'abc');
                root.check('file-tools-go-through-the-worker', !!tools.requests[fileId] && tools.requests[fileId].workerId > 0, root.json(Object.keys(tools.requests)));
                root.runFile('missing', 'checksum', ['file:///nonexistent-pentad-fixture/missing.txt'], {});
                root.phase = 2;
            } else if (root.phase === 2) {
                if (!root.settled(root.have(['ocr', 'unsupported', 'checksum', 'missing'])))
                    return;
                const ocr = root.results.ocr || {};
                root.check('ocr-through-the-worker', ocr.ok === true && ocr.value && ocr.value.text === 'Hello worker\nsecond line' && ocr.cached === false, root.json(ocr));
                root.check('unknown-op-is-unsupported', root.results.unsupported && root.results.unsupported.reason === 'unsupported', root.json(root.results.unsupported));
                const sum = root.results.checksum || {};
                root.check('file-job-keeps-the-helper-shape', sum.ok === true && sum.text === 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' && sum.value === undefined, root.json(sum));
                const missing = root.results.missing || {};
                root.check('file-failure-message-stays-in-reason', missing.ok === false && missing.reason === 'missing.txt no longer exists', root.json(missing));
                root.check('finished-jobs-leave-requests', Object.keys(tools.requests).length === 0 && !!tools.finished[Object.keys(root.fileJobs)[0]], root.json(Object.keys(tools.requests)));
                root.marks = Object.assign({}, root.marks, {
                    ocr: root.ocrCalls()
                });
                mainWorker.request('image.ocr', {
                    uri: root.input('page.png'),
                    psm: 6,
                    filterInstalled: true
                }, root.recorder('cachedOcr'));
                root.phase = 3;
            } else if (root.phase === 3) {
                if (!root.settled(root.have(['cachedOcr'])))
                    return;
                const cached = root.results.cachedOcr || {};
                root.check('repeated-ocr-comes-from-the-cache', cached.ok === true && cached.cached === true && cached.value.text === 'Hello worker\nsecond line' && root.ocrCalls() === root.marks.ocr, root.json(cached) + ' calls ' + root.ocrCalls() + '/' + root.marks.ocr);
                root.marks = Object.assign({}, root.marks, {
                    ocr: root.ocrCalls(),
                    cancelAt: Date.now()
                });
                root.marks = Object.assign({}, root.marks, {
                    slowId: mainWorker.request('image.ocr', {
                        uri: root.input('slow.png')
                    }, root.recorder('cancelled')),
                    slowFile: root.runFile('fileCancelled', 'image.ocr', [root.input('slow-file.png')], {})
                });
                root.phase = 4;
            } else if (root.phase === 4) {
                // Cancel once both fake tesseract runs are under way.
                if (!root.settled(root.ocrCalls() >= root.marks.ocr + 2))
                    return;
                mainWorker.cancel(root.marks.slowId);
                tools.cancel(root.marks.slowFile);
                root.phase = 5;
            } else if (root.phase === 5) {
                if (!root.settled(root.have(['cancelled', 'fileCancelled'])))
                    return;
                const elapsed = Date.now() - root.marks.cancelAt;
                root.check('cancel-stops-a-running-job', root.results.cancelled && root.results.cancelled.reason === 'cancelled' && elapsed < 15000, root.json(root.results.cancelled) + ' ' + elapsed + ' ms');
                const fileCancelled = root.results.fileCancelled || {};
                root.check('file-cancel-keeps-the-helper-shape', Object.keys(fileCancelled).length === 3 && fileCancelled.ok === false && fileCancelled.cancelled === true && fileCancelled.reason === 'Cancelled', root.json(fileCancelled));
                root.marks = Object.assign({}, root.marks, {
                    ocr: root.ocrCalls(),
                    pid: mainWorker.worker.processId
                });
                mainWorker.request('image.ocr', {
                    uri: root.input('slow-crash.png')
                }, root.recorder('crashed'));
                root.phase = 6;
            } else if (root.phase === 6) {
                if (!root.settled(root.ocrCalls() >= root.marks.ocr + 1))
                    return;
                mainWorker.kill();
                root.phase = 7;
            } else if (root.phase === 7) {
                if (!root.settled(root.have(['crashed'])))
                    return;
                root.check('crash-fails-in-flight-with-service-stopped', root.results.crashed && root.results.crashed.reason === 'service-stopped', root.json(root.results.crashed));
                mainWorker.request('worker.stats', {}, root.recorder('restarted'));
                root.phase = 8;
            } else if (root.phase === 8) {
                if (!root.settled(root.have(['restarted'])))
                    return;
                root.check('restarts-after-a-crash', root.results.restarted && root.results.restarted.ok === true && mainWorker.state === 'ready' && mainWorker.worker.processId > 0 && mainWorker.worker.processId !== root.marks.pid, root.json(root.results.restarted) + ' ' + mainWorker.state);

                // Capabilities: binding, availability, consent, safe mode, preview, warm.
                caps.attach('inst-ext', root.external, false);
                caps.attach('inst-ext', root.external, false);
                caps.attach('inst-builtin', root.builtin, true);
                safeCaps.attach('inst-ext', root.external, false);
                previewCaps.attach('inst-ext', root.external, false);
                const ocrAvailable = caps.available('image.ocr', 'inst-ext');
                root.check('local-op-available-with-disclosure', ocrAvailable.available === true && ocrAvailable.disclosure.execution === 'local' && ocrAvailable.disclosure.provider === 'pentad', root.json(ocrAvailable));
                root.check('unbound-instance-is-denied', caps.available('image.ocr', 'nobody').reason === 'denied', root.json(caps.available('image.ocr', 'nobody')));
                root.check('undeclared-capability-is-denied', caps.available('pdf.text', 'inst-ext').reason === 'denied');
                const chat = caps.available('llm.chat', 'inst-ext');
                root.check('local-role-discloses-its-model', chat.available === true && chat.disclosure.execution === 'local' && chat.disclosure.host === '127.0.0.1' && chat.disclosure.model === 'qwen3.5:9b', root.json(chat));
                const remote = caps.available('llm.chat', 'inst-ext', {
                    role: 'fast'
                });
                root.check('remote-role-needs-a-grant', remote.available === false && remote.reason === 'denied' && remote.disclosure && remote.disclosure.execution === 'remote', root.json(remote));
                root.check('builtin-trusts-the-remote-binding', caps.available('llm.chat', 'inst-builtin', {
                    role: 'fast'
                }).available === true);
                root.check('unset-role-is-not-configured', caps.available('text.embed', 'inst-ext').reason === 'not-configured');
                root.check('safe-mode-keeps-local-ops-only', safeCaps.available('llm.chat', 'inst-ext').reason === 'safe-mode' && safeCaps.available('image.ocr', 'inst-ext').available === true);
                root.check('preview-capabilities', previewCaps.available('image.ocr', 'inst-ext').reason === 'preview' && previewCaps.state.kind === 'unavailable');
                root.check('state-reports-the-worker', caps.state.kind === 'ready' && caps.state.value.worker === 'ready', root.json(caps.state));
                // Local ops have nothing to load; the local Ollama chat role is warmed (the worker
                // here has no model module, so it refuses the warm request without any network).
                const warmLocal = caps.warm('image.ocr', 'inst-ext');
                const warmChat = caps.warm('llm.chat', 'inst-ext');
                const warmUndeclared = caps.warm('llm.chat', 'nobody');
                root.check('warm-loads-local-models-only', warmLocal.ok === true && warmLocal.warming === false && warmChat.ok === true && warmChat.warming === true && warmUndeclared.reason === 'denied' && safeCaps.warm('llm.chat', 'inst-ext').reason === 'safe-mode', root.json([warmLocal, warmChat, warmUndeclared]));
                caps.detach('inst-ext');
                root.check('attach-is-counted', caps.available('image.ocr', 'inst-ext').available === true);

                root.marks = Object.assign({}, root.marks, {
                    capOcr: caps.call('image.ocr', {
                        uri: root.input('page.png'),
                        psm: 6,
                        filterInstalled: true
                    }, {
                        instanceId: 'inst-ext'
                    }),
                    capDenied: caps.call('pdf.text', {
                        uri: root.input('page.png')
                    }, {
                        instanceId: 'inst-ext'
                    }),
                    capInvalid: caps.call('image.ocr', {
                        uri: 'https://example.invalid/a.png'
                    }, {
                        instanceId: 'inst-ext'
                    }),
                    capChat: caps.call('llm.chat', {
                        messages: [
                            {
                                role: 'user',
                                content: 'hello'
                            }
                        ]
                    }, {
                        instanceId: 'inst-builtin'
                    }),
                    capCancelled: caps.call('image.ocr', {
                        uri: root.input('slow.png')
                    }, {
                        instanceId: 'inst-ext'
                    })
                });
                caps.cancel(root.marks.capCancelled);
                root.check('call-returns-before-any-signal', root.events.length === 0, root.json(root.events));
                root.phase = 9;
            } else if (root.phase === 9) {
                const ids = [root.marks.capOcr, root.marks.capDenied, root.marks.capInvalid, root.marks.capChat, root.marks.capCancelled];
                if (!root.settled(ids.every(id => root.eventsFor(id).some(event => event.kind === 'finished'))))
                    return;
                const ocr = root.eventsFor(root.marks.capOcr);
                root.check('call-starts-with-disclosure-then-finishes-once', ocr.length === 2 && ocr[0].kind === 'progress' && ocr[0].data.stage === 'started' && ocr[0].data.disclosure.execution === 'local' && ocr[1].kind === 'finished' && ocr[1].result.ok === true && ocr[1].result.cached === true && ocr[1].result.value.text === 'Hello worker\nsecond line', root.json(ocr));
                const denied = root.eventsFor(root.marks.capDenied);
                root.check('undeclared-call-is-denied-without-starting', denied.length === 1 && denied[0].result.reason === 'denied', root.json(denied));
                const invalid = root.eventsFor(root.marks.capInvalid);
                root.check('invalid-input-is-refused', invalid.length === 1 && invalid[0].result.ok === false && invalid[0].result.reason === 'invalid-input', root.json(invalid));
                const chat = root.eventsFor(root.marks.capChat);
                // No model module is staged, so the worker refuses llm.chat after the started progress.
                root.check('llm-call-discloses-before-dispatch', chat.length === 2 && chat[0].data.disclosure.model === 'qwen3.5:9b' && chat[1].result.reason === 'unsupported', root.json(chat));
                const cancelled = root.eventsFor(root.marks.capCancelled);
                root.check('cancel-before-dispatch', cancelled.length === 1 && cancelled[0].result.reason === 'cancelled', root.json(cancelled));
                root.check('every-call-finished-once', root.events.filter(event => event.kind === 'finished').length === ids.length, root.json(root.events));
                root.phase = 10;
            } else if (root.phase === 10) {
                // idleExitSeconds is 1: the idle worker retires about a second after its only job.
                if (!root.settled(!idleWorker.worker.running))
                    return;
                root.check('idle-worker-retires', root.results.idle && root.results.idle.ok === true && !idleWorker.worker.running && idleWorker.state === 'idle', idleWorker.state + ' ' + idleWorker.worker.running);
                root.finish();
            }
        }
    }
    Timer {
        interval: 60000
        running: true
        onTriggered: {
            root.check('fixture-timeout', false, 'phase ' + root.phase);
            root.finish();
        }
    }
}
