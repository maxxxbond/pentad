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
    | 'safe-mode' | 'preview' | 'superseded' | 'invalid-response' | 'service-missing' | 'service-stopped'
    | 'cancelled' | 'busy' | 'invalid-input';
  readonly message?: string;
};
export type Failure = Exclude<Result, { readonly ok: true }>;
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
  /**
   * Capabilities the widget may call through `services.capabilities`: unique dotted names, at most 16.
   * A call to an undeclared capability fails with `denied`. Hosts older than this key ignore it.
   */
  capabilities?: string[];
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
/** Where a capability call runs. Reported before any data leaves the widget. */
export interface Disclosure {
  readonly execution: 'local' | 'remote';
  /** Display name of the provider, `pentad` for built-in local operations, `translate-shell` for the translation helper. */
  readonly provider: string;
  /** Host (and port) the data is sent to; empty when no single host applies. */
  readonly host: string;
  /** Model name; empty for operations that use no model. */
  readonly model: string;
}
export interface Availability {
  readonly available: boolean;
  /**
   * Set when unavailable: a `Result` reason (`denied`, `unsupported`, `preview`, `safe-mode`, `service-missing`)
   * or a registry reason such as `not-configured` or `unknown-provider`.
   */
  readonly reason?: string;
  /** Present whenever a route is known, including a route that was refused for lack of remote consent. */
  readonly disclosure?: Disclosure;
}
/** `images` are `file:///` URIs, allowed on `user` messages only; any image routes the call to the `vision` role. */
export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
  images?: string[];
}
/** The v1 capabilities: input accepted by `call` and the `value` of a successful result. */
export interface CapabilityMap {
  /** At most 100 messages of at most 16 KiB each. Streams `partial(requestId, { text })`. */
  'llm.chat': { input: { messages: ChatMessage[]; temperature?: number; maxTokens?: number }; value: { text: string } };
  /** 1 to 64 strings of at most 16 KiB each. */
  'text.embed': { input: { input: string[] }; value: { vectors: number[][]; dims: number } };
  /** `target` and `source` are language tags such as `uk` or `zh-CN`; `text` is at most 64 KiB. */
  'text.translate': { input: { text: string; target: string; source?: string }; value: { text: string } };
  /** `uri` is a `file:///` URI; `language` is tesseract codes joined by `+`; `psm` is 0–13. */
  'image.ocr': { input: { uri: string; language?: string; psm?: number; filterInstalled?: boolean }; value: { text: string } };
  'image.barcode': { input: { uri: string }; value: { codes: { type: string; text: string }[] } };
  'pdf.text': { input: { uri: string }; value: { text: string } };
}
export type CapabilityName = keyof CapabilityMap;
export interface CapabilityOptions {
  /** The caller's own `instanceId`; instances the host has not bound to a manifest are `denied`. */
  instanceId: string;
  /** `llm.chat` only: `chat` (default) or `fast`. */
  role?: 'chat' | 'fast';
  [key: string]: unknown;
}
/** `cached` is true when a deterministic local operation was answered from the result cache. */
export type CapabilityResult<T = unknown> = { readonly ok: true; readonly value: T; readonly cached: boolean } | Failure;
/** The first `progress` of every call, emitted before any data leaves. */
export interface CapabilityStarted { readonly stage: 'started'; readonly disclosure: Disclosure; }
/**
 * Shared capabilities backed by the user's model registry and Pentad's local tools.
 * Signals: `progress(requestId, data)`, `partial(requestId, chunk)`, `commandFinished(requestId, result: CapabilityResult)`.
 * A well-formed name outside `CapabilityName` is reported `unsupported`; invalid input is `invalid-input` with a message that names the field.
 */
export interface CapabilitiesService {
  readonly state: State<{ readonly worker: 'idle' | 'starting' | 'ready' | 'crash-loop' }>;
  available(name: string, instanceId: string): Availability;
  /** Returns a request ID; the outcome arrives through `commandFinished`. */
  call<N extends CapabilityName>(name: N, input: CapabilityMap[N]['input'], options: CapabilityOptions): string;
  call(name: string, input: object, options: CapabilityOptions): string;
  /** The call still finishes, with reason `cancelled`. Unknown or finished IDs are ignored. */
  cancel(requestId: string): void;
}
export interface WidgetServices {
  readonly apiVersion: '1';
  readonly preview: boolean;
  readonly safeMode: boolean;
  text(uk: string, en: string): string;
  readonly audio: AudioMixerService;
  readonly media: MediaService;
  readonly toolWorkspace: ToolWorkspaceService;
  /** Absent on hosts that predate capabilities; guard with `services.capabilities &&`. */
  readonly capabilities: CapabilitiesService;
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
