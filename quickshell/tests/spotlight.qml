import QtQuick
import Quickshell
import '../logic/spotlight-intent.mjs' as Intent
import '../logic/spotlight-dispatch.mjs' as Dispatch
import '../logic/spotlight-providers.mjs' as Providers
import "../services"

ShellRoot {
    id: root
    property var waiters: []
    property SpotlightHelper helper: SpotlightHelper {
        helperPath: decodeURIComponent(Qt.resolvedUrl('helpers/pentad_spotlight.py').toString().replace(/^file:\/\//, ''))
        stateRoot: Quickshell.env('XDG_STATE_HOME') + '/pentad-spotlight-fixture'
        emojiPath: decodeURIComponent(Qt.resolvedUrl('assets/spotlight/emoji.json').toString().replace(/^file:\/\//, ''))
        idleInterval: 300
    }
    property SpotlightHelper missingHelper: SpotlightHelper {
        helperPath: decodeURIComponent(Qt.resolvedUrl('helpers/absent_spotlight.py').toString().replace(/^file:\/\//, ''))
        stateRoot: Quickshell.env('XDG_STATE_HOME') + '/pentad-spotlight-fixture'
        emojiPath: root.helper.emojiPath
    }
    function waitFor(until, then) {
        waiters.push({ until: until, then: then });
    }
    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            const list = root.waiters;
            root.waiters = [];
            for (const waiter of list) {
                if (waiter.until())
                    waiter.then();
                else
                    root.waiters.push(waiter);
            }
        }
    }
    Timer {
        interval: 20000
        running: true
        onTriggered: {
            console.log('PENTAD_TEST ' + JSON.stringify({ status: 'fail', name: 'qml-spotlight-helper', detail: 'timed out' }));
            Qt.quit();
        }
    }
    // Drives one persistent helper process through queued requests, reuse, a crash, an idle
    // stop and a helper that cannot run.
    function helperChecks(finish) {
        const checks = [];
        const replies = [];
        const pids = [];
        const record = index => result => {
            replies.push({ index: index, result: result });
            pids.push(root.helper.worker.processId);
        };
        root.helper.request({ operation: 'history' }, record(0));
        root.helper.request({ operation: 'emoji', languages: ['en'] }, record(1));
        root.helper.request({ operation: 'unsupported' }, record(2));
        root.waitFor(() => replies.length === 3, () => {
            const emoji = replies[1].result.records && replies[1].result.records.en;
            checks.push({ name: 'qml-spotlight-helper-serves-queued-requests-in-order', passed: replies.map(reply => reply.index).join() === '0,1,2'
                && replies[0].result.ok === true && Array.isArray(replies[0].result.history.recent)
                && replies[1].result.ok === true && Array.isArray(emoji) && emoji.some(row => row[0] === '🔥')
                && replies[2].result.ok === false && pids[0] > 0 && pids[0] === pids[2] });
            const started = Date.now();
            let again = null;
            root.helper.request({ operation: 'emoji', languages: ['en'] }, result => {
                again = { result: result, pid: root.helper.worker.processId, elapsed: Date.now() - started };
            });
            root.waitFor(() => again !== null, () => {
                checks.push({ name: 'qml-spotlight-helper-reuses-one-process', passed: again.result.ok === true
                    && again.pid === pids[0], detail: 'second emoji request ' + again.elapsed + ' ms' });
                root.helper.kill();
                root.waitFor(() => !root.helper.worker.running, () => {
                    let restarted = null;
                    root.helper.request({ operation: 'history' }, result => {
                        restarted = { result: result, pid: root.helper.worker.processId };
                    });
                    root.waitFor(() => restarted !== null, () => {
                        checks.push({ name: 'qml-spotlight-helper-restarts-after-a-crash', passed: restarted.result.ok === true
                            && restarted.pid > 0 && restarted.pid !== pids[0] });
                        const idleSince = Date.now();
                        root.waitFor(() => !root.helper.worker.running || Date.now() - idleSince > 3000, () => {
                            checks.push({ name: 'qml-spotlight-helper-stops-when-idle', passed: !root.helper.worker.running
                                && root.helper.client.idle });
                            let missing = null;
                            root.missingHelper.request({ operation: 'history' }, result => { missing = result; });
                            root.waitFor(() => missing !== null, () => {
                                checks.push({ name: 'qml-spotlight-helper-reports-a-broken-helper', passed: missing.ok === false
                                    && root.missingHelper.client.idle });
                                finish(checks);
                            });
                        });
                    });
                });
            });
        });
    }
    Timer {
        interval: 30
        running: true
        onTriggered: {
            const detected = Intent.detectIntent('= 2 + 3');
            const math = Providers.evaluateExpression('2 + 3 * 4');
            const emoji = Providers.searchEmojiRecords(':fire', { en: [['🔥', 'fire', ['hot'], 'fire']] }, { languages: ['en'] });
            const emojiLanguages = Providers.resolveEmojiLanguages({ layouts: ['ua,de'] });
            const session = new Dispatch.LauncherSession();
            session.open();
            const queryToken = session.beginQuery();
            const exactResult = { id: 'app-firefox.desktop', category: 'app', title: 'Firefox', score: 100, actions: [] };
            const secondResult = { id: 'app-code.desktop', category: 'app', title: 'Code', score: 90, actions: [] };
            session.accept(queryToken, [exactResult, secondResult]);
            session.move(-5);
            const wrappedSelection = session.selectedResult.id === 'app-code.desktop';
            session.move(5);
            const returnedSelection = session.selectedResult.id === 'app-firefox.desktop';
            const actionToken = session.beginAction();
            const cancelledToken = session.beginQuery();
            const staleAccepted = session.accept(queryToken, []);

            const providers = [Providers.createMathProvider(), Providers.createAppsProvider([
                { id: 'firefox.desktop', name: 'Firefox', exec: 'firefox', keywords: [] },
            ])];
            const dispatcher = Dispatch.createSearchDispatcher(providers);
            dispatcher.query('= 2 + 3').then(function(mathResults) {
                return dispatcher.query('', true).then(function(appResults) {
                    const checks = [
                        { name: 'qml-spotlight-intent-precedence', passed: detected.mode === 'calc' && detected.cleanQuery === '2 + 3' },
                        { name: 'qml-spotlight-math-parser-is-bounded', passed: math.success && math.result === 14
                            && !Providers.evaluateExpression('globalThis.process.exit()').success },
                        { name: 'qml-spotlight-emoji-provider-uses-injected-records', passed: emoji.length === 1
                            && emoji[0].preview.content === '🔥' && emojiLanguages.indexOf('uk') >= 0 },
                        { name: 'qml-spotlight-selection-tokens-reject-stale-results', passed: !!actionToken
                            && session.pending && !staleAccepted && session.current(cancelledToken)
                            && !session.endAction(actionToken) && wrappedSelection && returnedSelection },
                        { name: 'qml-spotlight-dispatches-search-and-explicit-app-browse', passed: mathResults.length === 1
                            && mathResults[0].title === '5' && appResults.length === 1 && appResults[0].title === 'Firefox' },
                    ];
                    root.helperChecks(function(helperChecks) {
                        const all = checks.concat(helperChecks);
                        console.log('PENTAD_TEST ' + JSON.stringify({ status: all.every(function(check) { return check.passed; })
                            ? 'pass' : 'fail', checks: all }));
                        Qt.quit();
                    });
                });
            }).catch(function(error) {
                console.log('PENTAD_TEST ' + JSON.stringify({ status: 'fail', name: 'qml-spotlight-logic', detail: error.message }));
                Qt.quit();
            });
        }
    }
}
