// Which centre wings fit on a bar. The island stays on the bar's physical centre, so each wing takes
// room only from its own half: telemetry from the left, tools from the right. A wing that was hidden
// needs a little spare room before it returns, so a width that wobbles by a few pixels (a network
// rate label, a tray icon coming and going) does not make it blink.
export const showMargin = 12;

// bar: { width, inset, gap, spacing, island, left, right, telemetry, tools } in pixels, where gap
// separates a wing from the island, spacing separates a wing from the side content, left and right
// are the side contents' widths (left without the window title, which only fills what is left) and
// telemetry and tools are the wings' natural widths, 0 for an empty slot.
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
