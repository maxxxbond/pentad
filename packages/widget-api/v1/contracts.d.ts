/** Public widget contract for Quickshell 0.3.2+. QML receives these as initial properties. */
export type WidgetSlot = 'navigation' | 'telemetry' | 'center' | 'tools' | 'system' | 'sidebar-left' | 'sidebar-right';
export type WidgetZone = 'left-menu' | 'left' | 'center' | 'right' | 'right-menu';
export type WidgetSize = 'icon' | 'row' | 'tile' | 'label' | 'full';
export type SettingValue = string | number | boolean;
export type State<T> =
  | { readonly kind: 'starting' }
  | { readonly kind: 'ready'; readonly value: T }
  | { readonly kind: 'unavailable'; readonly reason: string }
  | { readonly kind: 'error'; readonly message: string };
export type Result = { readonly ok: true } | {
  readonly ok: false;
  readonly reason: 'unavailable' | 'device-removed' | 'denied' | 'timeout' | 'unsupported' | 'conflict' | 'io'
    | 'safe-mode' | 'preview' | 'superseded' | 'invalid-response' | 'service-missing' | 'service-stopped';
  readonly message?: string;
};
export interface Context {
  readonly outputId: string;
  readonly slot: WidgetSlot;
  readonly compact: boolean;
  readonly preview: boolean;
  /** Inline menu hosts set false when the containing menu is closed. */
  readonly presented?: boolean;
  readonly placementZone?: WidgetZone;
  readonly placementSize?: WidgetSize;
}
export interface SettingsFieldMetadata {
  key: string;
  labelUk?: string; labelEn?: string;
  help?: string; helpUk?: string; helpEn?: string;
  group?: string; groupUk?: string; groupEn?: string;
  showWhen?: { key: string; equals: SettingValue };
}
export interface SettingsOption {
  value: SettingValue;
  label: string;
  labelUk?: string; labelEn?: string;
}
/** labelKey is a literal fallback; catalogs are not looked up at runtime. */
export type SettingsField = SettingsFieldMetadata
  & ({ label: string; labelKey?: string } | { label?: string; labelKey: string })
  & (
    | { kind: 'text'; default?: string }
    | { kind: 'integer' | 'number'; default?: number; min?: number; max?: number; step?: number }
    | { kind: 'boolean'; default?: boolean }
    | { kind: 'select'; default?: SettingValue; options: SettingsOption[] }
    | { kind: 'color'; default?: string }
  );
export interface WidgetManifest {
  id: string; name: string; version: string; apiVersion: 1;
  entry: string; controller?: string; allowedSlots: WidgetSlot[];
  /** If omitted, sections are derived from allowedSlots. */
  pentads?: WidgetZone[];
  defaults?: Record<string, SettingValue>; settingsFields?: SettingsField[];
  tool?: ToolMetadata;
  /** Secret-store references only; never secret values. */
  credentials?: Record<string, `secret://${string}`>;
}
export interface ToolMetadata {
  protocolVersion: 1;
  category: string;
  keywords: string[];
  accepts: string[];
  produces: string[];
  execution: 'local' | 'network' | 'ai';
  multiple: boolean;
  maxItems: number;
  maxBytes: number;
}
export interface ToolInputItem {
  readonly kind: 'text' | 'url' | 'file' | 'image' | 'json' | 'color';
  readonly mimeType: string;
  readonly compatibleTypes?: readonly string[];
  readonly value?: string;
  readonly uri?: string;
  readonly name?: string;
  readonly sizeBytes?: number;
}
export type ToolInputChoice = '' | 'replace' | 'append';
export interface ToolInputHandler {
  acceptInput(items: readonly ToolInputItem[], choice: ToolInputChoice): boolean;
  readonly canAppendInput?: boolean;
}
export interface ToolWorkspaceService {
  draftFor(id: string): string;
  setDraft(id: string, value: string): void;
  receive(items: readonly ToolInputItem[], compatibleIds: readonly string[], targetId?: string): void;
}
export interface MediaTrack {
  readonly trackId: string;
  readonly playerId: string;
  readonly sourceId: string;
  readonly positionMicros: number;
  readonly lengthMicros: number;
  readonly capabilities: Readonly<Record<string, boolean>>;
}
export interface MediaService {
  readonly state: State<MediaTrack>;
  readonly [command: string]: unknown;
}
/** One playback stream; a single application may expose multiple streams. */
export interface AudioStream {
  /** Lifetime token; numeric PipeWire IDs alone may be recycled. */
  readonly id: string;
  readonly nodeId: string;
  readonly appName: string;
  readonly label: string;
  readonly mediaName: string;
  readonly icon: string;
  readonly volume: number;
  readonly muted: boolean;
  readonly pendingVolume: boolean;
  readonly pendingMute: boolean;
  readonly requestedVolume: number;
}
export interface AudioMixerService {
  readonly state: State<{ readonly streams: readonly AudioStream[] }>;
  retainMixer(consumerId: string): void;
  releaseMixer(consumerId: string): void;
  setStreamVolume(id: string, value: number): string;
  toggleStreamMute(id: string): string;
}
export interface WidgetServices {
  readonly apiVersion: '1';
  readonly preview: boolean;
  readonly safeMode: boolean;
  text(uk: string, en: string): string;
  readonly audio: AudioMixerService;
  readonly media: MediaService;
  readonly toolWorkspace: ToolWorkspaceService;
}
export interface WidgetControllerProps {
  readonly instanceId: string;
  readonly settings: Readonly<Record<string, unknown>>;
  readonly services: Readonly<WidgetServices>;
}
export interface WidgetViewProps {
  readonly instanceId: string;
  readonly context: Context;
  readonly settings: Readonly<Record<string, unknown>>;
  readonly services: Readonly<WidgetServices>;
  /** Null when no controller is declared or while it is loading. */
  readonly controller: Readonly<Record<string, unknown>> | null;
}
/** QML service adapters emit commandFinished(requestId, result) after each request. */
export interface CommandCompletion { readonly requestId: string; readonly result: Result; }
