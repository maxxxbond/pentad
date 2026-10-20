const heldKeys = new Set();

export function handleWorkspaceSuperRequest(argv) {
  if (!Array.isArray(argv) || argv.length !== 3
      || argv[0] !== "workspace-super"
      || (argv[1] !== "Super_L" && argv[1] !== "Super_R")
      || (argv[2] !== "press" && argv[2] !== "release")) {
    return { ok: false, reason: "unknown-request", workspaceHeld: heldKeys.size > 0 };
  }

  if (argv[2] === "press") heldKeys.add(argv[1]);
  else heldKeys.delete(argv[1]);
  return { ok: true, workspaceHeld: heldKeys.size > 0 };
}

export function workspaceSuperHeld() {
  return heldKeys.size > 0;
}
