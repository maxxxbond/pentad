import test from 'node:test';
import assert from 'node:assert/strict';
import { overviewCaptureIds, overviewWindowIds, overviewWorkspaceIds, retainCaptureIds, workspaceGame } from '../../quickshell/logic/overview-presentation.mjs';

test('delegate keys depend only on valid unique window lifetimes, not mutable geometry or address alone', () => {
    assert.deepEqual(overviewWindowIds([{instanceId:'old',address:'0x1',x:0},{instanceId:'two',x:1}]),['old','two']);
    assert.deepEqual(overviewWindowIds([{instanceId:'old',address:'0x1',x:500},{instanceId:'two',x:2}]),['old','two']);
    assert.deepEqual(overviewWindowIds([{instanceId:'new',address:'0x1'},{instanceId:'new'},{}]),['new']);
});

test('game spaces use existing game recognition, retain their names and remain reachable outside the page', () => {
    const game={instanceId:'game',workspaceId:'9000',title:'ASTRONEER',appClass:'steam_app_361420'};
    assert.deepEqual(workspaceGame({id:'9000'},[game]),{title:'ASTRONEER',instanceId:'game'});
    assert.equal(workspaceGame({id:'9000'},[{...game,pinned:true}]),null);
    assert.equal(workspaceGame({id:'2'},[{appClass:'steam',title:'Steam',fullscreen:true}]),null);
    assert.equal(workspaceGame({id:'3'},[{appClass:'firefox',fullscreen:true}]),null);
    assert.equal(workspaceGame({id:'4'},[{appClass:'vlc',fullscreen:true}]),null);
    assert.equal(workspaceGame({game:true,displayName:'CS2'},[]).title,'CS2');
    const spaces=[{id:'1'},{id:'9000'},{id:'special:music'}];
    assert.deepEqual(overviewWorkspaceIds(['1','2'],spaces,[game]),['1','2','9000','special:music']);
    assert.deepEqual(overviewWorkspaceIds(['9000'],spaces,[game]),['9000','special:music']);
});

test('capture budget covers rail screenshots, prioritizes dragged and selected windows, excludes pins', () => {
    const clients=Array.from({length:30},(_,i)=>({instanceId:'w'+i,workspaceId:String(i%4+1)}));
    clients.push({instanceId:'pin',workspaceId:'1',pinned:true});
    const ids=overviewCaptureIds(clients,'1',['1','2','3','4'],'w28','w29');
    assert.equal(ids.length,20);
    assert.deepEqual(ids.slice(0,2),['w29','w28']);
    for(const id of ['1','2','3','4']) assert.ok(ids.some(key=>clients.find(c=>c.instanceId===key).workspaceId===id));
    assert.equal(ids.includes('pin'),false);
    assert.equal(new Set(ids).size,ids.length);
    assert.deepEqual(overviewCaptureIds([],'1',['1'],null,null),[]);
});

test('session cache retains previous page stills and never reuses an old window lifetime', () => {
    assert.deepEqual(retainCaptureIds(['next'],['old'],['next','old']),['next','old']);
    assert.deepEqual(retainCaptureIds(['next'],['old','next'],['next']),['next']);
    assert.deepEqual(retainCaptureIds(['address-reused-new'],['address-reused-old'],['address-reused-new']),['address-reused-new']);
    assert.deepEqual(retainCaptureIds(['a','b'],['c'],['a','b','c'],2),['a','b']);
});
