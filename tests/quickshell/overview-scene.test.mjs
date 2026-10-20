import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { overviewPage } from '../../quickshell/logic/overview-layout.mjs';
import * as Presentation from '../../quickshell/logic/overview-presentation.mjs';

const source = readFileSync(new URL('../../quickshell/features/overview/OverviewWindow.qml', import.meta.url), 'utf8');
const methods = [...source.matchAll(/^    function \w+\([^\n]*\) \{.*?^    \}/gms)].map(match => match[0]).join('\n');
function fixture() {
    const calls = [];
    const clients = [
        { address:'0x1', instanceId:'one', workspaceId:'1', title:'Terminal' },
        { address:'0x2', instanceId:'two', workspaceId:'13', title:'Editor' },
        { address:'0x3', instanceId:'pin', workspaceId:'1', title:'Pinned editor', pinned:true },
    ];
    const navigation = { query:'', selectedWindow:null, selectedWorkspaceId:'', dragToken:null, pickerOpen:false,
        selectWorkspace(id) { calls.push(['selectWorkspace',id]); this.selectedWorkspaceId=id; this.selectedWindow=null; },
        selectWindow(ref) { calls.push(['selectWindow',ref.instanceId]); this.selectedWindow=clients.find(c=>c.instanceId===ref.instanceId); },
        activateSelected() { calls.push(['activateSelected']); },
        activateWorkspace(id) { calls.push(['activateWorkspace',id]); },
        moveSelected(id) { calls.push(['moveSelected',id]); },
    };
    const p = vm.createContext({ navigation, clients, Presentation, Layout:{overviewPage}, workspaceIds:['1','2','3','13'], pageIds:['11','12','13'],
        services:{text(uk) {return uk;}}, workspaces:[], outputs:[], anchorOutput:null,
    });
    Object.defineProperty(p,'sceneWorkspaceId',{get:()=>navigation.selectedWindow?.workspaceId || navigation.selectedWorkspaceId || '1'});
    Object.defineProperty(p,'sceneClients',{get:()=>clients.filter(c=>c.workspaceId===p.sceneWorkspaceId && !c.pinned)});
    p.root=p;
    vm.runInContext(methods,p,{timeout:1000});
    return {p,calls,clients,navigation};
}

test('browsing workspaces changes presentation only; Enter explicitly activates the choice', () => {
    const {p,calls}=fixture();
    p.browseWorkspace('2');
    assert.deepEqual(calls,[['selectWorkspace','2']]);
    p.activateSelection();
    assert.deepEqual(calls,[['selectWorkspace','2'],['activateSelected']]);
});

test('window selection stays on the scene and captures also cover other visible workspaces', () => {
    const {p,calls,navigation}=fixture();
    p.selectRelative(1);
    assert.deepEqual(calls,[['selectWindow','one']]);
    p.browseWorkspace('13');
    p.selectRelative(1);
    assert.equal(navigation.selectedWindow.instanceId,'two');
    assert.equal(p.sceneWorkspaceId,'13');
    assert.deepEqual(Array.from(p.captureCandidates()),['two','one']);
});

test('dragging preserves its source scene; move picker dispatches only an explicit destination', () => {
    const {p,calls,navigation}=fixture();
    navigation.dragToken={};
    p.browseWorkspace('2');p.selectRelative(1);p.activateSelection();
    assert.deepEqual(calls,[]);
    navigation.dragToken=null;navigation.pickerOpen=true;navigation.selectedWindow={instanceId:'one',workspaceId:'1'};
    const handler=source.match(/function onPageStartChanged\(\) \{(.*?)\n        \}/s)[1];
    vm.runInContext(`(function(){${handler}})()`,p,{timeout:1000});
    assert.deepEqual(calls,[],'paging the destination list must never move a window');
    p.browseWorkspace('13');
    assert.deepEqual(calls,[['moveSelected','13']]);
});

test('empty workspaces activate and capture budget prioritizes selection', () => {
    const {p,calls,navigation,clients}=fixture();
    navigation.selectedWorkspaceId='3';p.activateSelection();
    assert.deepEqual(calls,[['activateSelected']]);
    for(let i=0;i<30;i++) clients.push({instanceId:'extra-'+i,workspaceId:'1'});
    navigation.selectedWorkspaceId='1';navigation.selectedWindow=clients.at(-1);
    const captures=Array.from(p.captureCandidates());
    assert.equal(captures.length,20);assert.equal(captures[0],'extra-29');
    assert.equal(captures.includes('pin'),false);
});

test('revealing a selected window on another page does not clear it while QML bindings catch up', () => {
    const {p,calls,navigation}=fixture();
    navigation.selectedWindow={instanceId:'two',workspaceId:'13'};
    navigation.pageStart=11;
    p.pageIds=['1','2','3'];
    const handler=source.match(/function onPageStartChanged\(\) \{(.*?)\n        \}/s)[1];
    vm.runInContext(`(function(){${handler}})()`,p,{timeout:1000});
    assert.deepEqual(calls,[]);
    navigation.pageStart=21;
    vm.runInContext(`(function(){${handler}})()`,p,{timeout:1000});
    assert.deepEqual(calls,[['selectWorkspace','21']]);
});

test('dragging a rail window preserves the browsed scene and drops the exact source lifetime', () => {
    const service = readFileSync(new URL('../../quickshell/services/WindowNavigation.qml', import.meta.url), 'utf8');
    const methods = ['beginDrag','cancelDrag','canDrop','drop'].map(name =>
        service.match(new RegExp(`    function ${name}\\([^\\n]*\\) \\{.*?^    \\}`, 'ms'))[0]).join('\n');
    const selected = {address:'0x1',instanceId:'one',workspaceId:'1'};
    const source = {address:'0x2',instanceId:'two',workspaceId:'13',pinned:false,grouped:[]};
    const moves = [];
    const p = vm.createContext({ mode:'overview',generation:7,_tokenSerial:0,error:'',dragToken:null,
        selectedRef:selected,selectedWindow:selected,selectedWorkspaceId:'1',moveState:{kind:'idle'},
        snapshot:{desktop:{workspaces:[{id:'2'},{id:'13'}]}},
        clientFor(ref) {return ref?.instanceId===source.instanceId && ref.address===source.address ? source : null;},
        refFor(client) {return {address:client.address,instanceId:client.instanceId};},
        syncSelected() {p.selectedWindow=p.clientFor(p.selectedRef);},
        moveWindow(ref,id) {moves.push([ref.instanceId,id]);return true;},
    });
    vm.runInContext(methods,p,{timeout:1000});
    const token=p.beginDrag({address:'0x2',instanceId:'two'});
    assert.ok(token);
    assert.equal(p.selectedRef,selected,'starting a drag must not browse the source workspace');
    assert.equal(p.selectedWindow,selected);
    assert.equal(p.selectedWorkspaceId,'1');
    assert.equal(p.drop(token,'2'),true);
    assert.deepEqual(moves,[['two','2']]);
    p.cancelDrag(token);
    assert.equal(p.drop(token,'2'),false,'a cancelled drag must not dispatch another move');
});

test('rail window clicks preview the workspace; release after dragging never activates it', () => {
    const card = readFileSync(new URL('../../quickshell/features/overview/WorkspaceCard.qml', import.meta.url), 'utf8');
    const hitTarget = card.slice(card.indexOf('id: hitTarget'));
    const click = hitTarget.match(/onClicked: \{(.*?)\n                        \}/s)[1];
    const calls = [];
    const p = vm.createContext({hitTarget:{dragged:false},windowItem:{windowRef:{instanceId:'two'}},
        root:{miniature:true,workspaceId:'13',workspaceSelected(id){calls.push(['preview',id]);},
            navigation:{selectWindow(ref){calls.push(['select',ref.instanceId]);},activateSelected(){calls.push(['activate']);}}}});
    const run = () => vm.runInContext(`(function(){${click}})()`,p,{timeout:1000});
    run();
    assert.deepEqual(calls,[['preview','13']]);
    calls.length=0;p.hitTarget.dragged=true;run();
    assert.deepEqual(calls,[]);
    p.hitTarget.dragged=false;p.root.miniature=false;run();
    assert.deepEqual(calls,[['select','two'],['activate']]);
});
