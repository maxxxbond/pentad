import { widgetSlots } from './plugin-manifest.mjs';
import { validatePlacementSettings } from './pentads.mjs';
import { resolveTheme } from './theme.mjs';
import { DEFAULT_ORGANIZER, parseOrganizer } from './organizer.mjs';
import { notificationStyles, parseNotificationArchive } from './notifications.mjs';
import { screenshotDefaults, parseScreenshotSettings } from './screenshot-settings.mjs';
import { parseEmojiPreferences, parseSpotlightOptions, spotlightOptionDefaults } from './spotlight-providers.mjs';
import { barToolsDefaults, parseBarTools } from './bar-tools.mjs';
import { wallpaperDefaults, parseWallpaper } from './wallpaper.mjs';
import { defaultQuickMenu, validateMenuLayout, supportsTemplate, builtinDefinitions } from './control-model.mjs';
import { barMenuModes } from './menu-prebuild.mjs';
import { modelsDefaults, parseModels } from './models.mjs';
import { chatModelSource } from './chat.mjs';

export const slots = widgetSlots;
export function normalizeSlot(slot) { return slot === 'left' ? 'telemetry' : slot === 'right' ? 'tools' : slot; }
export const defaultWidgets = [
  { instanceId: 'workspaces-main', moduleId: 'pentad.workspaces', slot: 'sidebar-left', enabled: true, settings: {} },
  { instanceId: 'weather-main', moduleId: 'pentad.weather', slot: 'sidebar-left', enabled: true, settings: {
    city: '', country: '', region: '', latitude: 0, longitude: 0, timezone: '', units: 'celsius' } },
  { instanceId: 'chat-main', moduleId: 'pentad.chat', slot: 'sidebar-left', enabled: true, settings: {
    modelSource: 'registry', modelRole: 'chat', provider: 'api', baseUrl: '', model: '', credentialRef: 'pentad-chat-api', apiKeyEnv: '' } },
  { instanceId: 'clock-main', moduleId: 'pentad.clock', slot: 'system', enabled: true, settings: { defaultDurationSeconds: 1500 } },
  { instanceId: 'activity-main', moduleId: 'pentad.activity', slot: 'center', enabled: true, settings: { preferredId: '' } },
  { instanceId: 'telemetry-main', moduleId: 'pentad.telemetry', slot: 'telemetry', enabled: true, settings: {} },
  { instanceId: 'tools-main', moduleId: 'pentad.tools', slot: 'tools', enabled: true, settings: {} },
  // The application mixer lives in the bar's sound popup; this placement stays available but starts off.
  { instanceId: 'mixer-main', moduleId: 'pentad.audio-mixer', slot: 'sidebar-right', enabled: false, settings: {} },
  { instanceId: 'mixer-bar', moduleId: 'pentad.audio-mixer', slot: 'tools', enabled: false, settings: {} },
  { instanceId: 'shelf-main', moduleId: 'pentad.shelf', slot: 'tools', enabled: false, settings: {} },
];
export const defaults = {
  theme: { schemaVersion: 1, appearance: 'dark', accent: '#869677', fontFamily: 'Geist', blur: false, reducedMotion: false, notificationColors: {} },
  layout: { schemaVersion: 1, barHeight: 40, showActiveTitle: true, showWorkspaces: true, showSeconds: false, clockLayout: 'stacked', clockSize: 18, trayIcons: 'soft', widgets: defaultWidgets,
    controlCenter: defaultQuickMenu, audioPresentation: 'range-horizontal', barTools: barToolsDefaults,
    clockFormat: '24h', clockDate: 'day-month', showBatteryPercent: false, workspaceCount: 5 },
  interface: { language: 'auto', firstDayOfWeek: 'auto', levelOverlay: true, notificationTimeout: 7, notificationPopups: 3,
    stashWindow: 'overlay', barMenus: 'speed', notificationStyle: 'toast', superKeyLogo: 'pentad' },
  spotlight: Object.assign({ emoji: { languages: 'auto' } }, spotlightOptionDefaults),
  organizer: DEFAULT_ORGANIZER,
  notifications: { schemaVersion: 1, dnd: false, records: [] },
  screenshots: screenshotDefaults,
  wallpaper: wallpaperDefaults,
  models: modelsDefaults,
};
const object = (value) => value && typeof value === 'object' && !Array.isArray(value);
export function parseDocument(name, text) {
  try {
    const input = JSON.parse(text);
    if (!object(input)) throw new Error('Document must be an object');
    const value = Object.assign({}, defaults[name] || {}, input);
    if (name === 'screenshots') return { ok: true, value: parseScreenshotSettings(input) };
    if (name === 'wallpaper') return { ok: true, value: parseWallpaper(input) };
    if (name === 'models') return { ok: true, value: parseModels(input) };
    if (name === 'spotlight') return { ok: true, value: Object.assign({}, value, parseSpotlightOptions(input), { emoji: parseEmojiPreferences(text) }) };
    if (name === 'theme') {
      if (value.schemaVersion !== 1 || value.blur !== false) throw new Error('Unsupported theme version or blur');
      resolveTheme(value);
    } else if (name === 'layout') {
      if (value.schemaVersion !== 1 || !Number.isInteger(value.barHeight) || value.barHeight < 28 || value.barHeight > 40)
        throw new Error('Invalid layout version or bar height');
      for (const key of ['showActiveTitle', 'showWorkspaces', 'showSeconds', 'showBatteryPercent'])
        if (typeof value[key] !== 'boolean') throw new Error('Invalid layout toggle');
      if (!['stacked', 'emphasis', 'inline'].includes(value.clockLayout)) throw new Error('Invalid clock layout');
      if (!Number.isInteger(value.clockSize) || value.clockSize < 14 || value.clockSize > 22) throw new Error('Invalid clock size');
      if (!['24h', '12h'].includes(value.clockFormat)) throw new Error('Invalid clock format');
      if (!['day-month', 'month-day', 'hidden'].includes(value.clockDate)) throw new Error('Invalid clock date');
      if (!['soft', 'color', 'monochrome'].includes(value.trayIcons)) throw new Error('Invalid tray icon mode');
      if (!Number.isInteger(value.workspaceCount) || value.workspaceCount < 1 || value.workspaceCount > 8)
        throw new Error('Invalid workspace count');
      const menu = validateMenuLayout(value.controlCenter);
      if (!menu.ok) throw new Error('Invalid control center: ' + menu.errors.join('; '));
      const quickIds = new Set(defaultQuickMenu.items.map(item => item.definitionId));
      const retiredIds = new Set(['tailscale']);
      if (menu.value.items.some(item => !quickIds.has(item.definitionId) && !retiredIds.has(item.definitionId)))
        throw new Error('Unsupported quick control');
      menu.value.items = menu.value.items.filter(item => !retiredIds.has(item.definitionId));
      value.controlCenter = menu.value;
      value.barTools = parseBarTools(input.barTools);
      if (!supportsTemplate(builtinDefinitions['audio-output'], value.audioPresentation))
        throw new Error('Invalid audio presentation');
      if (!Array.isArray(value.widgets)) throw new Error('Invalid placements');
      const ids = new Set();
      value.widgets = value.widgets.map((placement) => {
        if (!object(placement) || typeof placement.instanceId !== 'string' || !placement.instanceId
          || ids.has(placement.instanceId) || typeof placement.moduleId !== 'string' || !placement.moduleId
          || !slots.includes(normalizeSlot(placement.slot)) || typeof placement.enabled !== 'boolean' || !object(placement.settings))
          throw new Error('Invalid or duplicate widget placement');
        ids.add(placement.instanceId);
        let settings = Object.assign({}, placement.settings);
        const reserved = validatePlacementSettings(settings);
        if (!reserved.ok) throw new Error('Invalid widget placement settings: ' + reserved.errors.join('; '));
        if (placement.moduleId === 'pentad.weather' && Object.prototype.hasOwnProperty.call(settings, 'location')) {
          const oldLocation = object(settings.location) ? settings.location : {};
          settings = {
            city: typeof oldLocation.name === 'string' ? oldLocation.name : '',
            country: typeof oldLocation.country === 'string' ? oldLocation.country : '',
            region: typeof oldLocation.region === 'string' ? oldLocation.region : '',
            latitude: Number.isFinite(oldLocation.latitude) ? oldLocation.latitude : 0,
            longitude: Number.isFinite(oldLocation.longitude) ? oldLocation.longitude : 0,
            timezone: typeof oldLocation.timezone === 'string' ? oldLocation.timezone : '',
            units: settings.units === 'fahrenheit' ? 'fahrenheit' : 'celsius',
          };
        }
        // Chat placements from before model sources keep their own endpoint when they name one;
        // the rest use the model registry. Only a missing modelSource is filled in, legacy keys stay.
        if (placement.moduleId === 'pentad.chat' && !Object.prototype.hasOwnProperty.call(settings, 'modelSource'))
          settings.modelSource = chatModelSource(settings);
        return Object.assign({}, placement, { slot: normalizeSlot(placement.slot), settings });
      });
      if (Object.prototype.hasOwnProperty.call(input, 'widgets')) {
        for (const placement of defaultWidgets.filter(widget => widget.moduleId === 'pentad.audio-mixer')) {
          if (!ids.has(placement.instanceId) && !value.widgets.some(widget =>
            widget.moduleId === placement.moduleId && widget.slot === placement.slot)) {
            value.widgets.push(Object.assign({}, placement, { enabled: false, settings: {} }));
            ids.add(placement.instanceId);
          }
        }
      }
    } else if (name === 'interface') {
      if (!['auto', 'uk', 'en'].includes(value.language)) throw new Error('Invalid language');
      if (!['auto', 'monday', 'sunday', 'saturday'].includes(value.firstDayOfWeek)) throw new Error('Invalid first day of week');
      if (typeof value.levelOverlay !== 'boolean') throw new Error('Invalid level overlay toggle');
      if (!Number.isInteger(value.notificationTimeout) || value.notificationTimeout < 2 || value.notificationTimeout > 30)
        throw new Error('Invalid notification timeout');
      if (!Number.isInteger(value.notificationPopups) || value.notificationPopups < 1 || value.notificationPopups > 5)
        throw new Error('Invalid notification popup count');
      if (!notificationStyles.includes(value.notificationStyle)) throw new Error('Invalid notification style');
      if (!['overlay', 'window'].includes(value.stashWindow)) throw new Error('Invalid stash window mode');
      if (!barMenuModes.includes(value.barMenus)) throw new Error('Invalid bar menu mode');
      // How the cheatsheet and the submap hint draw the Super key: a logo, or the word "Super".
      if (!['pentad', 'tux', 'text'].includes(value.superKeyLogo)) throw new Error('Invalid Super key symbol');
    } else if (name === 'organizer') return { ok: true, value: parseOrganizer(input) };
    else if (name === 'notifications') {
      const archive = parseNotificationArchive(input);
      if (!archive) throw new Error('Invalid notification archive');
      return { ok: true, value: archive };
    }
    return { ok: true, value };
  } catch (error) { return { ok: false, reason: 'invalid', message: error.message }; }
}
