import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { access, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

test('native Qt ScriptModel preserves capture/window lifetimes on snapshot updates without a GUI', async t => {
    const repo=fileURLToPath(new URL('../../',import.meta.url));
    const core=path.join(repo,'artifacts/quickshell-runtime/source/src/core');
    let moc;
    for (const candidate of ['/usr/lib/qt6/libexec/moc','/usr/lib/qt6/moc']) {
        try { await access(candidate); moc=candidate; break; } catch {}
    }
    try { await access(path.join(core,'scriptmodel.cpp')); }
    catch { return t.skip('Requires local Quickshell model source'); }
    if(!moc) return t.skip('Requires Qt moc');
    const qt=spawnSync('pkg-config',['--cflags','--libs','Qt6Qml','Qt6Core'],{encoding:'utf8',timeout:5000});
    if(qt.status!==0) return t.skip('Requires Qt6Qml/Qt6Core development packages');
    const temporary=await mkdtemp(path.join(tmpdir(),'pentad-overview-core-'));
    try {
        const env={PATH:'/usr/bin:/bin',LANG:'C.UTF-8',HOME:temporary,XDG_CONFIG_HOME:temporary,
            XDG_STATE_HOME:temporary,XDG_DATA_HOME:temporary,XDG_RUNTIME_DIR:temporary,XDG_CACHE_HOME:temporary,
            DBUS_SYSTEM_BUS_ADDRESS:'unix:path='+path.join(temporary,'no-system-bus')};
        const generated=path.join(temporary,'moc_scriptmodel.cpp');
        const meta=spawnSync(moc,[path.join(core,'scriptmodel.hpp'),'-o',generated],{encoding:'utf8',timeout:10000,env});
        assert.equal(meta.status,0,meta.error?.message||meta.stderr);
        const binary=path.join(temporary,'overview-model-qt');
        const build=spawnSync('c++',['-std=c++20','-fPIC','-I'+core,path.join(repo,'tests/tools/overview-model-qt.cpp'),
            path.join(core,'scriptmodel.cpp'),generated,'-o',binary,...qt.stdout.trim().split(/\s+/)],{encoding:'utf8',timeout:60000,env});
        assert.equal(build.status,0,build.error?.message||build.stderr);
        const result=spawnSync(binary,[repo],{encoding:'utf8',timeout:10000,env});
        assert.equal(result.status,0,[result.error?.message,result.stderr,result.stdout].filter(Boolean).join('\n'));
        assert.match(result.stdout,/Qt overview identity and capture policy: passed/);
    } finally { await rm(temporary,{recursive:true,force:true}); }
});
