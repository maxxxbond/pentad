// Which centre wings fit on a bar. The island stays on the bar's physical centre, so each wing takes
// room only from its own half: telemetry from the left, tools from the right. A wing that was hidden
// needs a little spare room before it returns, so a width that wobbles by a few pixels (a network
// rate label, a tray icon coming and going) does not make it blink.
export const showMargin = 12;

// bar: { width, inset, gap, spacing, island, left, right, telemetry, tools } in pixels, where gap
// separates a wing from the island, spacing separates a wing from the side content, left and right
// are the side contents' widths (left without the window title, which only fills what is left; right
// with the privacy icons' room reserved, see rowWidth) and telemetry and tools are the wings' natural
// widths, 0 for an empty slot.
// previous: { telemetry, tools }, the wings shown now. Returns the wings to show.
export function planWings(bar, previous = {}) {
  const value = (key) => Number.isFinite(bar && bar[key]) ? Math.max(0, bar[key]) : 0;
  const half = value('width') / 2 - value('island') / 2 - value('inset');
  const room = (content) => half - content - (content > 0 ? value('spacing') : 0);
  const fits = (wing, space, shown) => wing > 0 && wing + value('gap') + (shown ? 0 : showMargin) <= space;
  return {
    telemetry: fits(value('telemetry'), room(value('left')), previous.telemetry === true),
    tools: fits(value('tools'), room(value('right')), previous.tools === true),
  };
}

// The width a Row with this spacing gives items of these widths: a Row skips an item with no width,
// together with its spacing. The bar plans its right side with the microphone and screen-recording
// icons counted whether they show or not, so a push-to-talk press never moves a wing.
export function rowWidth(widths, spacing) {
  const laid = (Array.isArray(widths) ? widths : []).filter((width) => Number.isFinite(width) && width > 0);
  const gap = Number.isFinite(spacing) ? Math.max(0, spacing) : 0;
  return laid.reduce((sum, width) => sum + width, 0) + Math.max(0, laid.length - 1) * gap;
}
