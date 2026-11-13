// The Network settings page: grouping, labels and form parsing over the status reply of
// tools/pentad_network.py. `t(uk, en)` is the shell's translation function.

const icons = {
  ethernet: 'material/network/lan-symbolic.svg',
  usb: 'material/network/usb-symbolic.svg',
  wifi: 'material/network/wifi-symbolic.svg',
  hotspot: 'material/network/wifi-tethering-symbolic.svg',
  bluetooth: 'material/network/bluetooth-symbolic.svg',
  mobile: 'material/network/signal-cellular-alt-symbolic.svg',
  vpn: 'material/network/vpn-lock-symbolic.svg',
  offline: 'material/wifi-off-symbolic.svg',
};
export function kindIcon(kind) { return icons[kind] || icons.ethernet; }

// A Repeater's modelData turns nested arrays into Qt lists, which Array.isArray rejects; copy any
// array-like value into a real array.
export function listOf(value) {
  if (Array.isArray(value)) return value;
  if (value && typeof value === 'object' && typeof value.length === 'number') return Array.prototype.slice.call(value);
  return [];
}
const list = listOf;
// Addresses for display: link-local IPv6 (fe80::) is noise outside a debugger.
export function joinAddresses(value) {
  return listOf(value).filter(address => String(address).toLowerCase().indexOf('fe80:') !== 0).join(', ');
}
const devicesOf = status => (status && status.ok ? list(status.devices) : []);
const connectionsOf = status => (status && status.ok ? list(status.connections) : []);

export function kindLabel(kind, t) {
  switch (kind) {
    case 'ethernet': return 'Ethernet';
    case 'usb': return t('USB-модем', 'USB tethering');
    case 'wifi': return 'Wi-Fi';
    case 'hotspot': return t('Точка доступу', 'Hotspot');
    case 'bluetooth': return t('Bluetooth-модем', 'Bluetooth tethering');
    case 'mobile': return t('Мобільний інтернет', 'Mobile broadband');
    case 'vpn': return 'VPN';
    default: return t('Мережа', 'Network');
  }
}

export function stateLabel(state, t) {
  switch (state) {
    case 'connected': case 'activated': return t('Підключено', 'Connected');
    case 'connecting': case 'activating': return t('Підключення…', 'Connecting…');
    case 'disconnecting': case 'deactivating': return t('Відключення…', 'Disconnecting…');
    case 'unavailable': return t('Кабель не під’єднано', 'Cable unplugged');
    case 'unmanaged': return t('Не керується', 'Not managed');
    case 'failed': return t('Помилка', 'Failed');
    default: return t('Відключено', 'Disconnected');
  }
}

// Link speed in Mbit/s as a short label; 0 or unknown gives "".
export function formatSpeed(mbps, t) {
  const value = Number(mbps);
  if (!(value > 0)) return '';
  if (value >= 1000) {
    const gbit = value / 1000;
    return (Number.isInteger(gbit) ? String(gbit) : gbit.toFixed(1)) + ' ' + t('Гбіт/с', 'Gbit/s');
  }
  return value + ' ' + t('Мбіт/с', 'Mbit/s');
}

export const bareAddress = cidr => String(cidr || '').split('/')[0];

export function deviceSubtitle(device, t) {
  if (!device) return '';
  const parts = [];
  if (device.external) parts.push(t('Керується іншою програмою', 'Managed by another app'));
  else if (device.kind === 'usb' && device.state === 'unavailable') parts.push(t('Не підключено', 'Not connected'));
  else parts.push(stateLabel(device.state, t));
  if (device.state === 'connected') {
    const speed = formatSpeed(device.speed, t);
    if (speed) parts.push(speed);
    const address = list(device.ipv4)[0] || list(device.ipv6)[0];
    if (address) parts.push(bareAddress(address));
  }
  if (device.mobile && device.mobile.operator) parts.push(device.mobile.operator);
  return parts.join(' · ');
}

// Wired devices on their own, the ones that are a phone on a cable apart.
export function devicesOfKind(status, kind) {
  return devicesOf(status).filter(device => device.kind === kind);
}

// Order in which an active device answers "what gives this computer its internet".
const primaryOrder = ['ethernet', 'usb', 'wifi', 'bluetooth', 'mobile'];

export function primaryDevice(status) {
  const connected = devicesOf(status).filter(device => device.state === 'connected' && device.kind !== 'vpn');
  // The device that holds the default route has a gateway; prefer it over a bare link.
  const ranked = connected.slice().sort((a, b) =>
    (b.gateway4 || b.gateway6 ? 1 : 0) - (a.gateway4 || a.gateway6 ? 1 : 0)
    || primaryOrder.indexOf(a.kind) - primaryOrder.indexOf(b.kind));
  return ranked[0] || null;
}

export function activeVpns(status) {
  const managed = connectionsOf(status).filter(item => item.kind === 'vpn' && item.active);
  const external = devicesOf(status).filter(device => device.kind === 'vpn' && device.external && device.state === 'connected');
  return managed.map(item => item.name).concat(external.map(device => device.label || device.id));
}

// The card at the top of the page: which link carries the internet and whether it reaches it.
export function overview(status, t) {
  if (!status) return { tone: 'loading', icon: icons.offline, title: t('Перевірка мережі…', 'Checking the network…'), subtitle: '', vpns: [] };
  if (!status.ok) {
    const missing = status.reason === 'nmcli-missing';
    return { tone: 'unavailable', icon: icons.offline,
      title: missing ? t('NetworkManager не встановлено', 'NetworkManager is not installed') : t('Мережа недоступна', 'Network is unavailable'),
      subtitle: missing ? t('Без нього Pentad не керує з’єднаннями', 'Pentad needs it to manage connections') : errorText(status.reason, t), vpns: [] };
  }
  if (!status.available) return { tone: 'unavailable', icon: icons.offline, title: t('NetworkManager не запущено', 'NetworkManager is not running'), subtitle: '', vpns: [] };
  const device = primaryDevice(status);
  const vpns = activeVpns(status);
  if (!device) return { tone: 'offline', icon: icons.offline, title: t('Немає з’єднання', 'Not connected'),
    subtitle: status.networking === false ? t('Мережу вимкнено', 'Networking is off') : '', vpns };
  const reach = status.connectivity === 'full' ? t('Є інтернет', 'Connected to the internet')
    : status.connectivity === 'portal' ? t('Потрібен вхід у мережу', 'Sign-in required')
      : status.connectivity === 'limited' || status.connectivity === 'none' ? t('Без інтернету', 'No internet')
        : t('Підключено', 'Connected');
  const tone = status.connectivity === 'full' || status.connectivity === 'unknown' ? 'online' : 'limited';
  const name = device.kind === 'wifi' || device.kind === 'bluetooth' || device.kind === 'mobile'
    ? (device.connection || device.label) : kindLabel(device.kind, t);
  const parts = [reach];
  const speed = formatSpeed(device.speed, t);
  if (speed) parts.push(speed);
  const address = list(device.ipv4)[0];
  if (address) parts.push(bareAddress(address));
  return { tone, icon: kindIcon(device.kind), title: name, subtitle: parts.join(' · '), vpns, device };
}

// Saved Wi-Fi networks: the connected one first, then the most recently used.
export function savedWifi(status) {
  return connectionsOf(status).filter(item => item.kind === 'wifi')
    .sort((a, b) => (b.active ? 1 : 0) - (a.active ? 1 : 0) || (b.timestamp || 0) - (a.timestamp || 0)
      || String(a.name).localeCompare(String(b.name)));
}

export function vpnConnections(status) {
  return connectionsOf(status).filter(item => item.kind === 'vpn')
    .sort((a, b) => (b.active ? 1 : 0) - (a.active ? 1 : 0) || String(a.name).localeCompare(String(b.name)));
}

// VPN links NetworkManager only observes (Tailscale, a manual wg-quick): shown, never switched.
export function externalVpns(status) {
  return devicesOf(status).filter(device => device.kind === 'vpn' && device.external);
}

export function vpnTypeLabel(type) {
  switch (type) {
    case 'wireguard': return 'WireGuard';
    case 'openvpn': return 'OpenVPN';
    case 'openconnect': return 'OpenConnect';
    case 'vpnc': return 'Cisco VPN';
    case 'l2tp': return 'L2TP';
    case 'pptp': return 'PPTP';
    case 'strongswan': case 'libreswan': return 'IPsec';
    default: return type ? String(type) : 'VPN';
  }
}

export function profileFor(status, uuid) {
  return connectionsOf(status).find(item => item.uuid === uuid) || null;
}

// Bluetooth phones NetworkManager can use for internet, with the state of their profile.
export function bluetoothTethers(status, t) {
  return devicesOfKind(status, 'bluetooth').map(device => ({
    id: device.id, label: device.label || device.id,
    active: device.state === 'connected', busy: device.state === 'connecting' || device.state === 'disconnecting',
    subtitle: deviceSubtitle(device, t),
  }));
}

export function mobileProfiles(status) {
  return connectionsOf(status).filter(item => item.kind === 'mobile');
}

export function hotspotState(status) {
  const hotspot = status && status.ok ? status.hotspot : null;
  return hotspot && typeof hotspot === 'object' ? hotspot : null;
}

export function hasWifiDevice(status) {
  return devicesOfKind(status, 'wifi').length > 0;
}

// --- Connection details form ---

export const dnsPresets = Object.freeze([
  { id: 'cloudflare', label: 'Cloudflare', ipv4: ['1.1.1.1', '1.0.0.1'], ipv6: ['2606:4700:4700::1111', '2606:4700:4700::1001'] },
  { id: 'google', label: 'Google', ipv4: ['8.8.8.8', '8.8.4.4'], ipv6: ['2001:4860:4860::8888', '2001:4860:4860::8844'] },
  { id: 'quad9', label: 'Quad9', ipv4: ['9.9.9.9', '149.112.112.112'], ipv6: ['2620:fe::fe', '2620:fe::9'] },
  { id: 'adguard', label: 'AdGuard', ipv4: ['94.140.14.14', '94.140.15.15'], ipv6: ['2a10:50c0::ad1:ff', '2a10:50c0::ad2:ff'] },
]);

export function dnsOptions(t) {
  return [{ value: 'auto', label: t('Автоматично', 'Automatic') }]
    .concat(dnsPresets.map(preset => ({ value: preset.id, label: preset.label })))
    .concat([{ value: 'custom', label: t('Власні', 'Custom') }]);
}

const sameList = (a, b) => a.length === b.length && a.every((value, index) => value === b[index]);

// Which DNS choice the saved profile matches: auto (from the network), a preset, or custom.
export function dnsChoice(details) {
  const ipv4 = details && details.ipv4 ? details.ipv4 : {};
  const ipv6 = details && details.ipv6 ? details.ipv6 : {};
  const four = list(ipv4.dns);
  const six = list(ipv6.dns);
  if (four.length === 0 && six.length === 0) return 'auto';
  const preset = dnsPresets.find(item => sameList(item.ipv4, four) && (six.length === 0 || sameList(item.ipv6, six)));
  return preset ? preset.id : 'custom';
}

// The ipv4/ipv6 DNS part of an update request for a choice; custom servers come as text.
export function dnsSettings(choice, customText) {
  if (choice === 'auto') return { ok: true, ipv4: { dns: [], ignoreAutoDns: false }, ipv6: { dns: [], ignoreAutoDns: false } };
  const preset = dnsPresets.find(item => item.id === choice);
  if (preset) return { ok: true, ipv4: { dns: preset.ipv4.slice(), ignoreAutoDns: true }, ipv6: { dns: preset.ipv6.slice(), ignoreAutoDns: true } };
  const parsed = splitList(customText);
  if (parsed.length === 0) return { ok: false, error: 'dns-empty' };
  const four = [];
  const six = [];
  for (const value of parsed) {
    if (isIPv4(value)) four.push(value);
    else if (isIPv6(value)) six.push(value);
    else return { ok: false, error: 'dns-invalid', value };
  }
  if (four.length > 4 || six.length > 4) return { ok: false, error: 'dns-too-many' };
  return { ok: true, ipv4: { dns: four, ignoreAutoDns: four.length > 0 }, ipv6: { dns: six, ignoreAutoDns: six.length > 0 } };
}

export function splitList(text) {
  return String(text || '').split(/[\s,;]+/).map(value => value.trim()).filter(Boolean);
}

export function isIPv4(value) {
  const parts = String(value).split('.');
  return parts.length === 4 && parts.every(part => /^(0|[1-9][0-9]{0,2})$/.test(part) && Number(part) <= 255);
}

export function isIPv6(value) {
  const text = String(value);
  if (!/^[0-9A-Fa-f:.]+$/.test(text) || text.indexOf(':') < 0) return false;
  const halves = text.split('::');
  if (halves.length > 2) return false;
  const groups = halves.map(half => (half === '' ? [] : half.split(':')));
  let count = 0;
  for (let h = 0; h < groups.length; h++) {
    for (let i = 0; i < groups[h].length; i++) {
      const group = groups[h][i];
      const last = h === groups.length - 1 && i === groups[h].length - 1;
      if (last && group.indexOf('.') >= 0) { if (!isIPv4(group)) return false; count += 2; continue; }
      if (!/^[0-9A-Fa-f]{1,4}$/.test(group)) return false;
      count += 1;
    }
  }
  return halves.length === 2 ? count < 8 : count === 8;
}

// "192.168.1.20/24" or a bare address (prefix 24 for IPv4, 64 for IPv6).
export function parseCidr(text, family) {
  const value = String(text || '').trim();
  const slash = value.indexOf('/');
  const address = slash >= 0 ? value.slice(0, slash) : value;
  const prefixText = slash >= 0 ? value.slice(slash + 1) : '';
  const valid = family === 'ipv6' ? isIPv6(address) : isIPv4(address);
  if (!valid) return null;
  const max = family === 'ipv6' ? 128 : 32;
  if (slash >= 0 && !/^\d{1,3}$/.test(prefixText)) return null;
  const prefix = slash < 0 ? (family === 'ipv6' ? 64 : 24) : Number(prefixText);
  if (prefix < 1 || prefix > max) return null;
  return address + '/' + prefix;
}

// One IP family of the update request from the form, or the first problem in it.
export function ipSettings(family, form) {
  const method = form.method;
  if (method !== 'manual') return { ok: true, value: { method, addresses: [], gateway: '' } };
  const addresses = [];
  for (const text of splitList(form.addresses)) {
    const cidr = parseCidr(text, family);
    if (!cidr) return { ok: false, error: 'address-invalid', value: text };
    addresses.push(cidr);
  }
  if (addresses.length === 0) return { ok: false, error: 'address-empty' };
  const gateway = String(form.gateway || '').trim();
  if (gateway !== '' && !(family === 'ipv6' ? isIPv6(gateway) : isIPv4(gateway))) return { ok: false, error: 'gateway-invalid', value: gateway };
  return { ok: true, value: { method, addresses, gateway } };
}

export function ipv4MethodOptions(t) {
  return [
    { value: 'auto', label: t('Автоматично (DHCP)', 'Automatic (DHCP)') },
    { value: 'manual', label: t('Вручну', 'Manual') },
    { value: 'link-local', label: t('Лише локальна адреса', 'Link-local only') },
    { value: 'shared', label: t('Роздавати інтернет', 'Share this connection') },
    { value: 'disabled', label: t('Вимкнено', 'Off') },
  ];
}

export function ipv6MethodOptions(t) {
  return [
    { value: 'auto', label: t('Автоматично', 'Automatic') },
    { value: 'dhcp', label: t('Лише DHCPv6', 'DHCPv6 only') },
    { value: 'manual', label: t('Вручну', 'Manual') },
    { value: 'link-local', label: t('Лише локальна адреса', 'Link-local only') },
    { value: 'ignore', label: t('Ігнорувати', 'Ignore') },
    { value: 'disabled', label: t('Вимкнено', 'Off') },
  ];
}

export function meteredOptions(t) {
  return [
    { value: 'unknown', label: t('Авто', 'Auto') },
    { value: 'yes', label: t('Так', 'Yes') },
    { value: 'no', label: t('Ні', 'No') },
  ];
}

export function macOptions(t) {
  return [
    { value: '', label: t('Як у системі', 'System default') },
    { value: 'permanent', label: t('Справжня', 'Hardware') },
    { value: 'stable', label: t('Приватна для мережі', 'Private per network') },
    { value: 'random', label: t('Нова щоразу', 'Random each time') },
  ];
}

// A literal MAC address in the profile shows as its own choice so the menu never lies.
export function macChoices(details, t) {
  const options = macOptions(t);
  const current = details && typeof details.mac === 'string' ? details.mac : '';
  if (current !== '' && !options.some(option => option.value === current)) options.push({ value: current, label: current });
  return options;
}

export function securityOptions(t) {
  return [
    { value: 'wpa-psk', label: 'WPA2' },
    { value: 'sae', label: 'WPA3' },
    { value: 'none', label: t('Без пароля', 'None') },
  ];
}

// WPA passphrases are 8-63 printable ASCII characters, or 64 hex digits. Spaces at either end are
// refused because NetworkManager's editor would strip them and silently change the key.
export function passwordProblem(password, security) {
  if (security === 'none') return '';
  const text = String(password || '');
  if (/[^ -~]/.test(text)) return 'invalid-password';
  if (text !== text.trim()) return 'password-spaces';
  if (/^[0-9A-Fa-f]{64}$/.test(text)) return '';
  if (text.length < 8) return 'password-short';
  if (text.length > 63) return 'password-long';
  return '';
}

// Any other secret (a carrier password): no control characters, no spaces at the ends, 256 at most.
export function secretProblem(secret) {
  const text = String(secret || '');
  if (/[\u0000-\u001f\u007f]/.test(text) || text.length > 256) return 'invalid-password';
  return text !== text.trim() ? 'password-spaces' : '';
}

export function ssidProblem(ssid) {
  const text = String(ssid || '');
  if (text.trim() === '') return 'ssid-empty';
  if (/[\u0000-\u001f\u007f]/.test(text)) return 'ssid-invalid';
  // An SSID is at most 32 bytes of UTF-8.
  if (utf8Length(text) > 32) return 'ssid-long';
  return '';
}

export function utf8Length(text) {
  let bytes = 0;
  for (const char of String(text)) {
    const code = char.codePointAt(0);
    bytes += code < 0x80 ? 1 : code < 0x800 ? 2 : code < 0x10000 ? 3 : 4;
  }
  return bytes;
}

export function apnProblem(apn) {
  return /^[A-Za-z0-9._-]{0,62}$/.test(String(apn || '')) ? '' : 'apn-invalid';
}

export function errorText(reason, t, message) {
  switch (reason) {
    case 'preview': return t('Недоступно в режимі перегляду', 'Not available in preview');
    case 'safe-mode': return t('Недоступно в безпечному режимі', 'Not available in safe mode');
    case 'nmcli-missing': return t('NetworkManager (nmcli) не встановлено', 'NetworkManager (nmcli) is not installed');
    case 'denied': return t('Немає дозволу', 'Permission denied');
    case 'timeout': return t('Мережа не відповіла вчасно', 'The network did not answer in time');
    case 'not-found': case 'unknown-connection': return t('З’єднання вже немає', 'The connection is gone');
    case 'unknown-device': return t('Пристрій від’єднано', 'The device is gone');
    case 'plugin-missing': return t('Потрібен модуль NetworkManager для цього VPN', 'This VPN needs a NetworkManager plugin');
    case 'no-wifi': return t('Немає адаптера Wi-Fi', 'No Wi-Fi adapter');
    case 'invalid-password': return t('Пароль: лише латиниця, цифри й знаки', 'The password can use Latin letters, digits and symbols only');
    case 'password-spaces': return t('Пароль не може починатися чи закінчуватися пробілом', 'The password cannot start or end with a space');
    case 'secret-keyring': return t('Пароль зберігається у сховищі ключів', 'The password is kept in your keyring');
    case 'password-short': return t('Пароль — щонайменше 8 символів', 'The password needs at least 8 characters');
    case 'password-long': return t('Пароль — не більше 63 символів', 'The password can have at most 63 characters');
    case 'ssid-empty': return t('Вкажіть назву мережі', 'Enter the network name');
    case 'ssid-invalid': return t('Назва містить недопустимі символи', 'The name has invalid characters');
    case 'ssid-long': return t('Назва задовга (до 32 байтів)', 'The name is too long (32 bytes at most)');
    case 'apn-invalid': return t('Неправильна APN', 'Invalid APN');
    case 'address-invalid': return t('Неправильна IP-адреса', 'Invalid IP address');
    case 'address-empty': return t('Вкажіть IP-адресу', 'Enter an IP address');
    case 'gateway-invalid': return t('Неправильний шлюз', 'Invalid gateway');
    case 'dns-empty': return t('Вкажіть DNS-сервер', 'Enter a DNS server');
    case 'dns-invalid': return t('Неправильний DNS-сервер', 'Invalid DNS server');
    case 'dns-too-many': return t('Не більше 4 DNS-серверів на протокол', 'At most 4 DNS servers per protocol');
    case 'invalid-file': return t('Цей файл не схожий на налаштування VPN', 'This file does not look like a VPN profile');
    case 'invalid-request': return t('Неправильні дані', 'Invalid input');
    case 'failed': return message ? t('Не вдалося: ', 'Failed: ') + message : t('Не вдалося', 'Failed');
    default: return t('Не вдалося', 'Failed');
  }
}
