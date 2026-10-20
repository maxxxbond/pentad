import assert from "node:assert/strict";
import test from "node:test";
import {
  handleWorkspaceSuperRequest,
  workspaceSuperHeld,
} from "../../quickshell/logic/workspace-super.mjs";

test("tracks both Super keys through explicit, idempotent press and release", () => {
  assert.equal(workspaceSuperHeld(), false);
  assert.deepEqual(handleWorkspaceSuperRequest(["workspace-super", "Super_L", "press"]), {
    ok: true, workspaceHeld: true,
  });
  assert.equal(handleWorkspaceSuperRequest(["workspace-super", "Super_L", "press"]).workspaceHeld, true);
  assert.equal(handleWorkspaceSuperRequest(["workspace-super", "Super_R", "press"]).workspaceHeld, true);
  assert.equal(handleWorkspaceSuperRequest(["workspace-super", "Super_L", "release"]).workspaceHeld, true);
  assert.equal(handleWorkspaceSuperRequest(["workspace-super", "Super_L", "release"]).workspaceHeld, true);
  assert.equal(handleWorkspaceSuperRequest(["workspace-super", "Super_R", "release"]).workspaceHeld, false);
  assert.equal(workspaceSuperHeld(), false);
});

test("rejects malformed requests without changing held keys", () => {
  const invalid = [
    null,
    [],
    ["other", "Super_L", "press"],
    ["workspace-super", "Super", "press"],
    ["workspace-super", "Super_L", "toggle"],
    ["workspace-super", "Super_L", "press", "extra"],
  ];
  for (const argv of invalid) {
    assert.deepEqual(handleWorkspaceSuperRequest(argv), {
      ok: false, reason: "unknown-request", workspaceHeld: false,
    });
    assert.equal(workspaceSuperHeld(), false);
  }
});
