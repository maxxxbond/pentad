import QtQuick
import Quickshell
import '../logic/spotlight-intent.mjs' as Intent
import '../logic/spotlight-dispatch.mjs' as Dispatch
import '../logic/spotlight-providers.mjs' as Providers

ShellRoot {
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
                    console.log('PENTAD_TEST ' + JSON.stringify({ status: checks.every(function(check) { return check.passed; })
                        ? 'pass' : 'fail', checks: checks }));
                    Qt.quit();
                });
            }).catch(function(error) {
                console.log('PENTAD_TEST ' + JSON.stringify({ status: 'fail', name: 'qml-spotlight-logic', detail: error.message }));
                Qt.quit();
            });
        }
    }
}
