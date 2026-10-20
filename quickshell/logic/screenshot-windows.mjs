const finite = value => typeof value === 'number' && Number.isFinite(value);

function targetOutput(snapshot, outputId) {
  if (!snapshot || !Array.isArray(snapshot.desktop?.outputs)) return null;
  return snapshot.desktop.outputs.find(output => output.id === outputId || output.name === outputId) || null;
}

function clipClient(client, output) {
  const values = [client.x, client.y, client.width, client.height,
    output.x, output.y, output.width, output.height];
  if (!values.every(finite) || client.width <= 0 || client.height <= 0 || output.width <= 0 || output.height <= 0)
    return null;
  const left = Math.max(client.x, output.x), top = Math.max(client.y, output.y);
  const right = Math.min(client.x + client.width, output.x + output.width);
  const bottom = Math.min(client.y + client.height, output.y + output.height);
  return right > left && bottom > top ? { left, top, right, bottom } : null;
}

function visibleOnOutput(client, output) {
  if (!client || client.mapped === false || client.hidden === true) return false;
  if (client.pinned === true) return true;
  const workspace = String(client.workspaceId ?? '');
  return !!workspace && (workspace === String(output.activeWorkspaceId ?? '')
    || (output.specialWorkspaceId != null && workspace === String(output.specialWorkspaceId)));
}

export function capturedWindowRegions(snapshot, outputId, imageWidth, imageHeight) {
  if (!finite(imageWidth) || !finite(imageHeight) || imageWidth <= 0 || imageHeight <= 0) return [];
  const output = targetOutput(snapshot, outputId);
  if (!output || !finite(output.width) || !finite(output.height) || output.width <= 0 || output.height <= 0
      || !Array.isArray(snapshot.clients)) return [];
  const scaleX = imageWidth / output.width, scaleY = imageHeight / output.height;
  return snapshot.clients
    .map((client, order) => ({ client, order, clipped: visibleOnOutput(client, output) ? clipClient(client, output) : null }))
    .filter(item => item.clipped)
    .sort((a, b) => Number(a.client.floating === true) - Number(b.client.floating === true) || a.order - b.order)
    .map(({ client, clipped }) => ({
      x: (clipped.left - output.x) * scaleX,
      y: (clipped.top - output.y) * scaleY,
      width: (clipped.right - clipped.left) * scaleX,
      height: (clipped.bottom - clipped.top) * scaleY,
      title: typeof client.title === 'string' ? client.title : '',
      address: typeof client.address === 'string' ? client.address : '',
      outputId: typeof output.name === 'string' && output.name ? output.name : String(output.id ?? outputId),
    }));
}

export function activeWindowCrop(snapshot, outputId, imageWidth, imageHeight) {
  const activeAddress = snapshot?.activeAddress;
  if (typeof activeAddress !== 'string' || !activeAddress) return null;
  const active = capturedWindowRegions(snapshot, outputId, imageWidth, imageHeight)
    .find(region => region.address === activeAddress);
  return active ? { x: active.x, y: active.y, width: active.width, height: active.height } : null;
}
