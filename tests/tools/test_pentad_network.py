import importlib.util
import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

MODULE_PATH = Path(__file__).resolve().parents[2] / "tools" / "pentad_network.py"
SPEC = importlib.util.spec_from_file_location("pentad_network", MODULE_PATH)
network = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(network)

NM = ("nmcli", "-t", "-e", "yes")
ETH = "0f0e0d0c-0b0a-4908-8706-050403020100"
CAFE = "3c3c3c3c-0000-4000-8000-000000000003"
SPOT = "2c2c2c2c-0000-4000-8000-000000000002"
TAIL = "1a1a1a1a-2b2b-4c3c-8d4d-5e5e5e5e5e5e"
DOCK = "5c5c5c5c-0000-4000-8000-000000000005"
WG = "4c4c4c4c-0000-4000-8000-000000000004"
OVPN = "6c6c6c6c-0000-4000-8000-000000000006"
NEW = "11111111-2222-3333-4444-555555555555"
CONNECTION_LIST = NM + ("-f", "NAME,UUID,TYPE,DEVICE,ACTIVE,STATE,AUTOCONNECT,AUTOCONNECT-PRIORITY,TIMESTAMP", "connection", "show")
DEVICE_LIST = NM + ("-f", "DEVICE,TYPE,STATE,CONNECTION,CON-UUID", "device")
WIFI_FIELDS = "802-11-wireless.mode,802-11-wireless.ssid,connection.interface-name"

CONNECTIONS = "\n".join([
    f"Wired connection 1:{ETH}:802-3-ethernet:enp9s0:yes:activated:yes:-999:1790000000",
    f"Cafe\\: Free \\\\ Wi-Fi:{CAFE}:802-11-wireless::no::yes:5:1789000000",
    f"Hotspot:{SPOT}:802-11-wireless:wlan0:yes:activated:no:0:0",
    f"tailscale0:{TAIL}:tun:tailscale0:yes:activated:yes:0:0",
    f"docker0:{DOCK}:bridge:docker0:yes:activated:yes:0:0",
    f"wg-home:{WG}:wireguard::no::no:0:0",
    f"Office:{OVPN}:vpn::no::no:0:0",
]) + "\n"

DEVICES = "\n".join([
    f"enp9s0:ethernet:connected:Wired connection 1:{ETH}",
    "enp0s20u1:ethernet:disconnected::",
    f"tailscale0:tun:connected (externally):tailscale0:{TAIL}",
    "tun7:tun:unmanaged::",
    f"docker0:bridge:connected (externally):docker0:{DOCK}",
    "br-0123456789ab:bridge:connected (externally)::",
    "veth0000001:ethernet:unmanaged::",
    "lo:loopback:connected (externally):lo:",
    f"wlan0:wifi:connected:Hotspot:{SPOT}",
    "p2p-dev-wlan0:wifi-p2p:disconnected::",
    "AA\\:BB\\:CC\\:DD\\:EE\\:FF:bt:disconnected::",
    "cdc-wdm0:gsm:disconnected::",
]) + "\n"

ENP9S0 = """GENERAL.DEVICE:enp9s0
GENERAL.TYPE:ethernet
GENERAL.VENDOR:Realtek Semiconductor Co., Ltd.
GENERAL.PRODUCT:RTL8125 2.5GbE Controller
GENERAL.HWADDR:02:00:00:00:00:01
GENERAL.MTU:1500
GENERAL.STATE:100 (connected)
WIRED-PROPERTIES.CARRIER:on
IP4.ADDRESS[1]:192.168.1.20/24
IP4.GATEWAY:192.168.1.1
IP4.DNS[1]:192.168.1.1
IP6.ADDRESS[1]:fe80::1/64
IP6.ADDRESS[2]:2001:db8::35/64
IP6.GATEWAY:fe80::1
IP6.DNS[1]:2001:db8::1
"""
SHOW = {
    "enp9s0": ENP9S0,
    "enp0s20u1": "GENERAL.HWADDR:02:00:00:00:00:01\nGENERAL.MTU:1500\nWIRED-PROPERTIES.CARRIER:off\n",
    "tailscale0": "GENERAL.HWADDR:\nGENERAL.MTU:1280\nIP4.ADDRESS[1]:100.64.0.7/32\nIP4.GATEWAY:\n",
    "wlan0": "GENERAL.PRODUCT:RTL8852CE\nGENERAL.HWADDR:02:00:00:00:00:02\nGENERAL.MTU:1500\nIP4.ADDRESS[1]:10.42.0.1/24\n",
    "AA:BB:CC:DD:EE:FF": "GENERAL.HWADDR:AA:BB:CC:DD:EE:FF\nGENERAL.MTU:0\n",
    "cdc-wdm0": "GENERAL.MTU:1500\nGENERAL.UDI:/org/freedesktop/ModemManager1/Modem/0\n",
}
MODEM = {"modem": {"generic": {"signal-quality": {"value": "75", "recent": "yes"}, "access-technologies": ["lte"]},
                   "3gpp": {"operator-name": "Kyivstar"}}}

DETAILS_WIFI = f"""connection.id:Cafe: Free
connection.uuid:{CAFE}
connection.type:802-11-wireless
connection.autoconnect:yes
connection.autoconnect-priority:5
connection.metered:yes
ipv4.method:manual
ipv4.dns:1.1.1.1,9.9.9.9
ipv4.addresses:192.168.5.10/24, 10.0.0.2/8
ipv4.gateway:192.168.5.1
ipv4.ignore-auto-dns:yes
ipv6.method:auto
ipv6.dns:
ipv6.addresses:
ipv6.gateway:
ipv6.ignore-auto-dns:no
802-11-wireless.ssid:Cafe: Free
802-11-wireless.mode:infrastructure
802-11-wireless.hidden:yes
802-11-wireless.cloned-mac-address:stable
802-11-wireless-security.key-mgmt:wpa-psk
802-11-wireless-security.psk:<hidden>
"""
DETAILS_ETH = f"""connection.id:Wired connection 1
connection.uuid:{ETH}
connection.type:802-3-ethernet
connection.autoconnect:yes
connection.autoconnect-priority:-999
connection.metered:unknown
ipv4.method:auto
ipv4.dns:
ipv4.addresses:
ipv4.gateway:
ipv4.ignore-auto-dns:no
ipv6.method:auto
ipv6.addresses:
ipv6.gateway:
802-3-ethernet.cloned-mac-address:
"""


def show(uuid, fields=None):
    return NM + (("-f", fields) if fields else ()) + ("connection", "show", "uuid", uuid)


def base_answers():
    answers = {
        NM + ("-f", "RUNNING,VERSION,CONNECTIVITY,NETWORKING", "general"): "running:1.58.1:portal:enabled\n",
        NM + ("-f", "WIFI-HW,WIFI,WWAN-HW,WWAN", "radio"): "enabled:enabled:missing:enabled\n",
        CONNECTION_LIST: CONNECTIONS,
        DEVICE_LIST: DEVICES,
        show(CAFE, WIFI_FIELDS): "802-11-wireless.mode:infrastructure\n802-11-wireless.ssid:Cafe: Free\nconnection.interface-name:\n",
        show(SPOT, WIFI_FIELDS): "802-11-wireless.mode:ap\n802-11-wireless.ssid:Pentad\nconnection.interface-name:wlan0\n",
        show(OVPN, "vpn.service-type"): "vpn.service-type:org.freedesktop.NetworkManager.openvpn\n",
        show(CAFE): DETAILS_WIFI,
        show(ETH): DETAILS_ETH,
        ("mmcli", "-L"): "No modems were found\n",
        ("mmcli", "-m", "/org/freedesktop/ModemManager1/Modem/0", "-J"): json.dumps(MODEM),
        ("bluetoothctl", "info", "AA:BB:CC:DD:EE:FF"): "Device AA:BB:CC:DD:EE:FF (public)\n\tName: Pixel 7\n",
        ("nmcli", "connection", "modify"): "",
        ("nmcli", "connection", "edit"): "nmcli> Connection saved.\n",
        ("nmcli", "connection", "up"): "Connection successfully activated\n",
        ("nmcli", "connection", "down"): "",
        ("nmcli", "connection", "delete"): "",
        ("nmcli", "device", "reapply"): "",
    }
    for name, text in SHOW.items():
        answers[NM + ("-f", "GENERAL,WIRED-PROPERTIES,IP4,IP6", "device", "show", name)] = text
    return answers


class FakeRun:
    """Answers argv tuples (exact first, then the longest matching prefix) and records argv and stdin."""

    def __init__(self, answers):
        self.answers = answers
        self.calls = []

    def __call__(self, argv, timeout=10, stdin=None):
        argv = tuple(argv)
        self.calls.append((argv, stdin))
        answer = self.answers.get(argv)
        if answer is None:
            prefixes = [key for key in self.answers if argv[:len(key)] == key]
            answer = self.answers[max(prefixes, key=len)] if prefixes else None
        if callable(answer):
            answer = answer(argv)
        if isinstance(answer, BaseException):
            raise answer
        if answer is None:
            raise FileNotFoundError(2, "No such file or directory", argv[0])
        return answer

    def argvs(self, *prefix):
        return [argv for argv, _ in self.calls if argv[:len(prefix)] == prefix]

    def assert_secret_hidden(self, test, secret):
        for argv, stdin in self.calls:
            test.assertFalse(any(secret in part for part in argv), argv)
        edits = [stdin for argv, stdin in self.calls if argv[:3] == ("nmcli", "connection", "edit")]
        test.assertTrue(edits and all(secret in text for text in edits))


def failure(code, stderr="Error: boom\nmore"):
    return subprocess.CalledProcessError(code, ["nmcli"], output="", stderr=stderr)


class NetworkHelperTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        net = self.root / "sys/class/net"
        (net / "enp9s0/device").mkdir(parents=True)
        (net / "enp9s0/speed").write_text("1000\n")
        os.symlink("../../../../bus/pci/drivers/r8169", net / "enp9s0/device/driver")
        (net / "enp0s20u1/device").mkdir(parents=True)
        (net / "enp0s20u1/speed").write_text("-1\n")
        os.symlink("../../../../bus/usb/drivers/cdc_ncm", net / "enp0s20u1/device/driver")
        vpn = self.root / "usr/lib/NetworkManager/VPN"
        vpn.mkdir(parents=True)
        (vpn / "nm-openvpn-service.name").write_text("[VPN Connection]\nname=openvpn\nservice=org.freedesktop.NetworkManager.openvpn\n")
        (vpn / "nm-openconnect-service.name").write_text("[VPN Connection]\nservice=org.freedesktop.NetworkManager.openconnect\n")

    def tearDown(self):
        self.temp.cleanup()

    def call(self, request, answers=None):
        fake = FakeRun(base_answers() if answers is None else answers)
        with patch.object(network, "run", fake):
            return network.handle(request, str(self.root)), fake

    # --- status ---------------------------------------------------------------------------------------------

    def test_status_reads_general_radios_and_plugins(self):
        result, _ = self.call({"operation": "status"})
        self.assertEqual((result["ok"], result["available"], result["version"], result["networking"], result["connectivity"]),
                         (True, True, "1.58.1", True, "portal"))
        self.assertEqual(result["radios"], dict(wifi=True, wifiHardware=True, wwan=True, wwanHardware=False))
        self.assertEqual(result["vpnPlugins"], ["openconnect", "openvpn"])
        self.assertTrue(result["modemManager"])

    def test_status_connections_unescape_names_and_classify(self):
        result, _ = self.call({"operation": "status"})
        by_uuid = {item["uuid"]: item for item in result["connections"]}
        self.assertEqual(set(by_uuid), {ETH, CAFE, SPOT, WG, OVPN})  # tun and bridge profiles dropped
        self.assertEqual(by_uuid[CAFE]["name"], "Cafe: Free \\ Wi-Fi")
        self.assertEqual((by_uuid[CAFE]["kind"], by_uuid[CAFE]["priority"], by_uuid[CAFE]["active"]), ("wifi", 5, False))
        self.assertEqual((by_uuid[SPOT]["kind"], by_uuid[SPOT]["state"], by_uuid[SPOT]["device"]), ("hotspot", "activated", "wlan0"))
        self.assertEqual((by_uuid[WG]["kind"], by_uuid[WG]["vpnType"]), ("vpn", "wireguard"))
        self.assertEqual((by_uuid[OVPN]["kind"], by_uuid[OVPN]["vpnType"]), ("vpn", "openvpn"))
        self.assertEqual(by_uuid[ETH]["timestamp"], 1790000000)
        self.assertEqual(result["hotspot"], dict(uuid=SPOT, ssid="Pentad", active=True, device="wlan0"))

    def test_status_devices_filter_and_classify(self):
        result, _ = self.call({"operation": "status"})
        devices = {item["id"]: item for item in result["devices"]}
        self.assertEqual(set(devices), {"enp9s0", "enp0s20u1", "tailscale0", "wlan0", "AA:BB:CC:DD:EE:FF", "cdc-wdm0"})
        eth = devices["enp9s0"]
        self.assertEqual((eth["kind"], eth["label"], eth["speed"], eth["carrier"], eth["driver"], eth["mtu"]),
                         ("ethernet", "RTL8125 2.5GbE Controller", 1000, True, "r8169", 1500))
        self.assertEqual(eth["ipv6"], ["2001:db8::35/64", "fe80::1/64"])
        self.assertEqual(eth["dns"], ["192.168.1.1", "2001:db8::1"])
        self.assertEqual((eth["uuid"], eth["gateway4"]), (ETH, "192.168.1.1"))
        usb = devices["enp0s20u1"]
        self.assertEqual((usb["kind"], usb["driver"], usb["speed"], usb["carrier"], usb["label"]),
                         ("usb", "cdc_ncm", None, False, "enp0s20u1"))
        tun = devices["tailscale0"]
        self.assertEqual((tun["kind"], tun["state"], tun["external"], tun["ipv4"]), ("vpn", "connected", True, ["100.64.0.7/32"]))
        self.assertEqual((devices["AA:BB:CC:DD:EE:FF"]["kind"], devices["AA:BB:CC:DD:EE:FF"]["label"]), ("bluetooth", "Pixel 7"))
        self.assertEqual(devices["cdc-wdm0"]["mobile"], dict(operator="Kyivstar", signal=75, technology="lte"))
        self.assertIsNone(eth["mobile"])

    def test_status_without_running_networkmanager(self):
        answers = base_answers()
        answers[NM + ("-f", "RUNNING,VERSION,CONNECTIVITY,NETWORKING", "general")] = failure(8)
        result, fake = self.call({"operation": "status"}, answers)
        self.assertEqual((result["ok"], result["available"], result["devices"], result["connections"], result["hotspot"]),
                         (True, False, [], [], None))
        self.assertFalse(fake.argvs(*DEVICE_LIST))

    def test_status_without_mmcli_and_bluetoothctl(self):
        answers = {key: value for key, value in base_answers().items() if key[0] not in ("mmcli", "bluetoothctl")}
        result, _ = self.call({"operation": "status"}, answers)
        devices = {item["id"]: item for item in result["devices"]}
        self.assertFalse(result["modemManager"])
        self.assertIsNone(devices["cdc-wdm0"]["mobile"])
        self.assertEqual(devices["AA:BB:CC:DD:EE:FF"]["label"], "AA:BB:CC:DD:EE:FF")

    def test_device_state_mapping(self):
        self.assertEqual(network.device_state("connecting (getting IP configuration)"), ("connecting", False))
        self.assertEqual(network.device_state("deactivating"), ("disconnecting", False))
        self.assertEqual(network.device_state("connected (externally)"), ("connected", True))
        self.assertEqual(network.device_state("weird"), ("unknown", False))

    # --- details, secret ------------------------------------------------------------------------------------

    def test_details_parses_wifi_profile(self):
        result, _ = self.call({"operation": "details", "uuid": CAFE})
        self.assertEqual((result["name"], result["kind"], result["autoconnect"], result["priority"], result["metered"]),
                         ("Cafe: Free", "wifi", True, 5, "yes"))
        self.assertEqual(result["ipv4"], dict(method="manual", addresses=["192.168.5.10/24", "10.0.0.2/8"], gateway="192.168.5.1",
                                              dns=["1.1.1.1", "9.9.9.9"], ignoreAutoDns=True))
        self.assertEqual(result["ipv6"], dict(method="auto", addresses=[], gateway="", dns=[], ignoreAutoDns=False))
        self.assertEqual((result["mac"], result["ssid"], result["hidden"], result["security"], result["hasSecret"], result["apn"]),
                         ("stable", "Cafe: Free", True, "wpa-psk", True, ""))

    def test_details_ethernet_has_no_wifi_fields(self):
        result, _ = self.call({"operation": "details", "uuid": ETH})
        self.assertEqual((result["kind"], result["mac"], result["security"], result["hasSecret"], result["hidden"]),
                         ("ethernet", "", "", False, False))

    def test_secret_reads_psk_for_wifi_only(self):
        answers = base_answers()
        answers[("nmcli", "-s", "-t", "-e", "yes", "-g", "802-11-wireless-security.psk", "connection", "show", "uuid", CAFE)] = "pa\\:ss\\\\word\n"
        result, _ = self.call({"operation": "secret", "uuid": CAFE}, answers)
        self.assertEqual(result, dict(ok=True, secret="pa:ss\\word"))
        result, _ = self.call({"operation": "secret", "uuid": ETH}, answers)
        self.assertEqual(result, dict(ok=False, reason="invalid-request"))

    # --- update ---------------------------------------------------------------------------------------------

    def test_update_manual_ipv4_dns_metered_and_reapply(self):
        result, fake = self.call({"operation": "update", "uuid": ETH, "settings": {
            "metered": "yes", "priority": 10,
            "ipv4": {"method": "manual", "addresses": ["192.168.1.50/24"], "gateway": "192.168.1.1", "dns": ["1.1.1.1", "8.8.8.8"]}}})
        self.assertEqual(result, dict(ok=True, reapplied=True))
        self.assertEqual(fake.argvs("nmcli", "connection", "modify"), [(
            "nmcli", "connection", "modify", "uuid", ETH, "connection.autoconnect-priority", "10", "connection.metered", "yes",
            "ipv4.method", "manual", "ipv4.addresses", "192.168.1.50/24", "ipv4.gateway", "192.168.1.1", "ipv4.dns", "1.1.1.1,8.8.8.8")])
        self.assertEqual(fake.argvs("nmcli", "device", "reapply"), [("nmcli", "device", "reapply", "enp9s0")])
        self.assertFalse(fake.argvs("nmcli", "connection", "up"))

    def test_update_falls_back_to_reconnect_when_reapply_is_refused(self):
        answers = base_answers()
        answers[("nmcli", "device", "reapply")] = subprocess.CalledProcessError(4, ["nmcli"], stderr="Error: Can't reapply")
        fake = FakeRun(answers)
        with patch.object(network, "run", fake):
            result = network.handle({"operation": "update", "uuid": ETH, "settings": {"metered": "no"}}, str(self.root))
        self.assertEqual(result, dict(ok=True, reapplied=True))
        self.assertEqual(fake.argvs("nmcli", "connection", "up"), [("nmcli", "connection", "up", "uuid", ETH)])

    def test_update_of_name_or_autoconnect_keeps_the_link(self):
        result, fake = self.call({"operation": "update", "uuid": ETH, "settings": {"autoconnect": False, "priority": 3}})
        self.assertEqual(result, dict(ok=True, reapplied=False))
        self.assertFalse(fake.argvs("nmcli", "connection", "up"))
        self.assertFalse(fake.argvs("nmcli", "device", "reapply"))

    def test_leaving_manual_clears_static_addresses(self):
        result, fake = self.call({"operation": "update", "uuid": ETH, "settings": {"ipv4": {"method": "auto"}}})
        self.assertTrue(result["ok"])
        argv = fake.argvs("nmcli", "connection", "modify")[0]
        self.assertIn("ipv4.addresses", argv)
        self.assertEqual(argv[argv.index("ipv4.addresses") + 1], "")
        self.assertEqual(argv[argv.index("ipv4.gateway") + 1], "")
        self.assertNotIn("ipv4.dns", argv)

    def test_methods_without_ip_config_drop_dns(self):
        result, fake = self.call({"operation": "update", "uuid": ETH, "settings": {"ipv4": {"method": "disabled"}}})
        self.assertTrue(result["ok"])
        argv = fake.argvs("nmcli", "connection", "modify")[0]
        self.assertEqual(argv[argv.index("ipv4.dns") + 1], "")
        self.assertEqual(argv[argv.index("ipv4.ignore-auto-dns") + 1], "no")
        refused, _ = self.call({"operation": "update", "uuid": ETH, "settings": {"ipv4": {"method": "link-local", "dns": ["1.1.1.1"]}}})
        self.assertEqual(refused, dict(ok=False, reason="invalid-request"))

    def test_failed_secret_save_restores_autoconnect(self):
        answers = base_answers()
        answers[("nmcli", "connection", "edit")] = "nmcli> Error: failed to save\n"
        fake = FakeRun(answers)
        with patch.object(network, "run", fake), self.assertRaises(subprocess.CalledProcessError):
            network.handle({"operation": "update", "uuid": CAFE, "settings": {"password": "long enough"}}, str(self.root))
        self.assertEqual(fake.argvs("nmcli", "connection", "modify")[-1][-2:], ("connection.autoconnect", "yes"))

    def test_new_profile_without_its_secret_is_removed(self):
        answers = base_answers()
        answers[("nmcli", "connection", "edit")] = "nmcli> Error: failed to save\n"
        answers[("nmcli", "connection", "add")] = "Connection 'Hidden' (99999999-9999-9999-9999-999999999999) successfully added.\n"
        fake = FakeRun(answers)
        with patch.object(network, "run", fake), self.assertRaises(subprocess.CalledProcessError):
            network.handle({"operation": "join-hidden", "ssid": "Hidden", "security": "wpa-psk", "password": "long enough"}, str(self.root))
        self.assertEqual(fake.argvs("nmcli", "connection", "delete"),
                         [("nmcli", "connection", "delete", "uuid", "99999999-9999-9999-9999-999999999999")])

    def test_update_inactive_profile_is_not_reapplied_and_clears_orphan_gateway(self):
        result, fake = self.call({"operation": "update", "uuid": CAFE, "settings": {
            "ipv4": {"method": "auto", "addresses": []}, "mac": "02:11:22:33:44:5a", "hidden": False, "autoconnect": False}})
        self.assertEqual(result, dict(ok=True, reapplied=False))
        self.assertEqual(fake.argvs("nmcli", "connection", "modify"), [(
            "nmcli", "connection", "modify", "uuid", CAFE, "ipv4.method", "auto", "ipv4.addresses", "", "ipv4.gateway", "",
            "802-11-wireless.cloned-mac-address", "02:11:22:33:44:5A", "802-11-wireless.hidden", "no", "connection.autoconnect", "no")])
        self.assertFalse(fake.argvs("nmcli", "connection", "up"))

    def test_update_password_goes_through_editor_stdin(self):
        secret = "correct horse battery"
        result, fake = self.call({"operation": "update", "uuid": CAFE, "settings": {"password": secret}})
        self.assertEqual(result, dict(ok=True, reapplied=False))
        fake.assert_secret_hidden(self, secret)
        stdin = [s for argv, s in fake.calls if argv[:3] == ("nmcli", "connection", "edit")][0]
        self.assertEqual(stdin, f"set 802-11-wireless-security.psk {secret}\nsave persistent\nquit\n")
        modifies = fake.argvs("nmcli", "connection", "modify")
        self.assertEqual(modifies[0][-2:], ("connection.autoconnect", "no"))
        self.assertEqual(modifies[-1][-2:], ("connection.autoconnect", "yes"))

    def test_update_editor_error_is_scrubbed(self):
        secret = "s3cret-value"
        answers = base_answers()
        answers[("nmcli", "connection", "edit")] = f"nmcli> Error: failed to set 'psk' property: '{secret}' is invalid\n"
        fake = FakeRun(answers)
        with patch.object(network, "run", fake), self.assertRaises(subprocess.CalledProcessError) as caught:
            network.handle({"operation": "update", "uuid": CAFE, "settings": {"password": secret}}, str(self.root))
        self.assertNotIn(secret, caught.exception.stderr)

    def test_update_validation(self):
        cases = [
            ({"uuid": "not-a-uuid", "settings": {}}, "invalid-request"),
            ({"uuid": NEW, "settings": {}}, "unknown-connection"),
            ({"uuid": ETH, "settings": {"bogus": 1}}, "invalid-request"),
            ({"uuid": ETH, "settings": {"ipv4": {"method": "manual", "addresses": ["192.168.1.300/24"]}}}, "invalid-request"),
            ({"uuid": ETH, "settings": {"ipv4": {"method": "manual", "addresses": ["2001:db8::1/64"]}}}, "invalid-request"),
            ({"uuid": ETH, "settings": {"ipv6": {"dns": ["1.1.1.1"]}}}, "invalid-request"),
            ({"uuid": ETH, "settings": {"ipv4": {"method": "manual"}}}, "invalid-request"),
            ({"uuid": ETH, "settings": {"ipv4": {"dns": ["1.1.1.1"] * 5}}}, "invalid-request"),
            ({"uuid": ETH, "settings": {"priority": 1000}}, "invalid-request"),
            ({"uuid": ETH, "settings": {"name": "bad\nname"}}, "invalid-request"),
            ({"uuid": ETH, "settings": {"mac": "01:00:00:00:00:01"}}, "invalid-request"),
            ({"uuid": ETH, "settings": {"hidden": True}}, "invalid-request"),
            ({"uuid": ETH, "settings": {"password": "longenough"}}, "invalid-request"),
            ({"uuid": CAFE, "settings": {"password": "short"}}, "invalid-password"),
            ({"uuid": CAFE, "settings": {"password": "has\x07bell-char"}}, "invalid-password"),
            ({"uuid": CAFE, "settings": {"password": " padded password "}}, "invalid-password"),
        ]
        for request, reason in cases:
            with self.subTest(request=request):
                result, fake = self.call(dict(request, operation="update"))
                self.assertEqual(result, dict(ok=False, reason=reason))
                self.assertFalse(fake.argvs("nmcli", "connection", "modify"))

    def test_psk_accepts_hex_key(self):
        self.assertEqual(network.psk_value("a" * 64), "a" * 64)
        with self.assertRaises(network.Refuse):
            network.psk_value("x" * 64)

    # --- simple actions -------------------------------------------------------------------------------------

    def test_simple_actions_build_argv(self):
        cases = [
            ({"operation": "activate", "uuid": CAFE}, ("nmcli", "connection", "up", "uuid", CAFE)),
            ({"operation": "deactivate", "uuid": ETH}, ("nmcli", "connection", "down", "uuid", ETH)),
            ({"operation": "forget", "uuid": CAFE}, ("nmcli", "connection", "delete", "uuid", CAFE)),
            ({"operation": "connect-device", "device": "wlan0"}, ("nmcli", "device", "connect", "wlan0")),
            ({"operation": "disconnect-device", "device": "enp9s0"}, ("nmcli", "device", "disconnect", "enp9s0")),
            ({"operation": "radio", "radio": "wifi", "enabled": False}, ("nmcli", "radio", "wifi", "off")),
        ]
        for request, argv in cases:
            with self.subTest(request=request):
                answers = base_answers()
                answers[argv] = ""
                result, fake = self.call(request, answers)
                self.assertEqual(result, dict(ok=True))
                self.assertIn(argv, [call for call, _ in fake.calls])

    def test_unknown_device_and_bad_radio(self):
        self.assertEqual(self.call({"operation": "connect-device", "device": "eth9"})[0], dict(ok=False, reason="unknown-device"))
        self.assertEqual(self.call({"operation": "radio", "radio": "bt", "enabled": True})[0], dict(ok=False, reason="invalid-request"))

    def test_unsupported_operation_raises(self):
        with self.assertRaises(ValueError):
            self.call({"operation": "nope"})

    # --- creation flows -------------------------------------------------------------------------------------

    def added(self, answers, name="x"):
        answers[("nmcli", "connection", "add")] = f"Connection '{name}' ({NEW}) successfully added.\n"
        answers[("nmcli", "connection", "edit")] = "nmcli> Connection saved.\n"
        answers[("nmcli", "connection", "modify")] = ""
        answers[("nmcli", "connection", "up")] = "Connection successfully activated\n"
        return answers

    def test_join_hidden_keeps_secret_out_of_argv(self):
        secret = "hunter2hunter2"
        result, fake = self.call({"operation": "join-hidden", "ssid": "Hidden Net", "security": "sae", "password": secret},
                                 self.added(base_answers()))
        self.assertEqual(result, dict(ok=True, uuid=NEW))
        fake.assert_secret_hidden(self, secret)
        self.assertEqual(fake.argvs("nmcli", "connection", "add"), [(
            "nmcli", "connection", "add", "type", "wifi", "con-name", "Hidden Net", "ssid", "Hidden Net",
            "802-11-wireless.hidden", "yes", "connection.autoconnect", "no", "wifi-sec.key-mgmt", "sae")])
        self.assertEqual(fake.argvs("nmcli", "connection", "modify"), [("nmcli", "connection", "modify", "uuid", NEW, "connection.autoconnect", "yes")])

    def test_join_hidden_failed_activation_keeps_profile(self):
        answers = self.added(base_answers())
        answers[("nmcli", "connection", "up")] = failure(4, "Error: Connection activation failed: Secrets were required.\n")
        result, fake = self.call({"operation": "join-hidden", "ssid": "Hidden", "security": "wpa-psk", "password": "hunter2hunter2"}, answers)
        self.assertEqual(result, dict(ok=False, reason="failed", message="Error: Connection activation failed: Secrets were required.", uuid=NEW))
        self.assertFalse(fake.argvs("nmcli", "connection", "delete"))

    def test_join_hidden_validation(self):
        self.assertEqual(self.call({"operation": "join-hidden", "ssid": "x" * 33, "security": "none"})[0]["reason"], "invalid-request")
        self.assertEqual(self.call({"operation": "join-hidden", "ssid": "Net", "security": "wpa-psk", "password": "short"})[0]["reason"],
                         "invalid-password")

    def test_hotspot_reuses_profile_and_hides_password(self):
        secret = "new-hotspot-pass"
        answers = self.added(base_answers())
        answers[show(SPOT)] = f"connection.uuid:{SPOT}\nconnection.type:802-11-wireless\nconnection.autoconnect:no\n802-11-wireless.mode:ap\n" \
                              "802-11-wireless-security.key-mgmt:wpa-psk\n"
        result, fake = self.call({"operation": "hotspot", "enabled": True, "ssid": "Pentad 2", "password": secret}, answers)
        self.assertEqual(result, dict(ok=True, uuid=SPOT))
        fake.assert_secret_hidden(self, secret)
        self.assertEqual(fake.argvs("nmcli", "connection", "modify"), [("nmcli", "connection", "modify", "uuid", SPOT, "802-11-wireless.ssid", "Pentad 2")])
        self.assertEqual(fake.argvs("nmcli", "connection", "up"), [("nmcli", "connection", "up", "uuid", SPOT, "ifname", "wlan0")])

    def test_hotspot_creates_profile(self):
        secret = "fresh-hotspot-pass"
        answers = self.added(base_answers())
        answers[CONNECTION_LIST] = "\n".join(line for line in CONNECTIONS.splitlines() if SPOT not in line) + "\n"
        result, fake = self.call({"operation": "hotspot", "enabled": True, "ssid": "Pentad", "password": secret}, answers)
        self.assertEqual(result, dict(ok=True, uuid=NEW))
        fake.assert_secret_hidden(self, secret)
        add = fake.argvs("nmcli", "connection", "add")[0]
        self.assertEqual(add[3:], ("type", "wifi", "con-name", "Hotspot", "ifname", "wlan0", "ssid", "Pentad", "802-11-wireless.mode", "ap",
                                   "802-11-wireless.band", "bg", "ipv4.method", "shared", "ipv6.method", "ignore",
                                   "wifi-sec.key-mgmt", "wpa-psk", "connection.autoconnect", "no"))

    def test_hotspot_off_and_no_wifi(self):
        answers = base_answers()
        answers[("nmcli", "connection", "down")] = ""
        result, fake = self.call({"operation": "hotspot", "enabled": False}, answers)
        self.assertEqual(result, dict(ok=True, uuid=SPOT))
        self.assertEqual(fake.argvs("nmcli", "connection", "down"), [("nmcli", "connection", "down", "uuid", SPOT)])
        answers[DEVICE_LIST] = "enp9s0:ethernet:connected:Wired connection 1:\n"
        self.assertEqual(self.call({"operation": "hotspot", "enabled": True}, answers)[0], dict(ok=False, reason="no-wifi"))

    def test_bluetooth_tether_creates_panu_profile(self):
        answers = self.added(base_answers())
        result, fake = self.call({"operation": "bluetooth-tether", "address": "aa:bb:cc:dd:ee:ff", "enabled": True}, answers)
        self.assertEqual(result, dict(ok=True, uuid=NEW))
        self.assertEqual(fake.argvs("nmcli", "connection", "add")[0][3:], (
            "type", "bluetooth", "con-name", "Pixel 7 Network", "bluetooth.type", "panu", "bluetooth.bdaddr", "AA:BB:CC:DD:EE:FF",
            "connection.autoconnect", "no"))
        self.assertEqual(self.call({"operation": "bluetooth-tether", "address": "11:22:33:44:55:66", "enabled": True})[0]["reason"], "unknown-device")
        self.assertEqual(self.call({"operation": "bluetooth-tether", "address": "phone", "enabled": True})[0]["reason"], "invalid-request")

    def test_mobile_add_keeps_password_out_of_argv(self):
        secret = "operator-pass"
        result, fake = self.call({"operation": "mobile-add", "apn": "internet.kyivstar.net", "username": "user", "password": secret},
                                 self.added(base_answers()))
        self.assertEqual(result, dict(ok=True, uuid=NEW))
        fake.assert_secret_hidden(self, secret)
        self.assertEqual(fake.argvs("nmcli", "connection", "add")[0][3:], (
            "type", "gsm", "ifname", "*", "con-name", "Mobile broadband", "gsm.apn", "internet.kyivstar.net", "gsm.username", "user",
            "connection.autoconnect", "no"))
        self.assertEqual(self.call({"operation": "mobile-add", "apn": "bad apn"})[0]["reason"], "invalid-request")

    # --- VPN import -----------------------------------------------------------------------------------------

    def vpn(self, name, text):
        path = self.root / "home" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return str(path)

    def import_answers(self, seen):
        answers = base_answers()

        def imported(argv):
            folder = os.path.dirname(argv[-1])
            seen.append((argv, os.path.exists(argv[-1]), stat.S_IMODE(os.stat(folder).st_mode)))
            return f"Connection '{Path(argv[-1]).stem}' ({NEW}) successfully added.\n"
        answers[("nmcli", "connection", "import")] = imported
        answers[("nmcli", "connection", "modify")] = ""
        return answers

    def test_import_wireguard_renames_into_private_temp_dir(self):
        path = self.vpn("My Home VPN!.conf", "[Interface]\nPrivateKey = abc=\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = x\n")
        seen = []
        result, fake = self.call({"operation": "import-vpn", "path": path, "type": "auto"}, self.import_answers(seen))
        self.assertEqual(result, dict(ok=True, uuid=NEW, name="wg-MyHomeVPN"))
        argv, existed, mode = seen[0]
        self.assertEqual(argv[:6], ("nmcli", "connection", "import", "type", "wireguard", "file"))
        self.assertEqual(os.path.basename(argv[-1]), "wg-MyHomeVPN.conf")
        self.assertTrue(existed)
        self.assertEqual(mode, 0o700)
        self.assertFalse(os.path.exists(argv[-1]))
        self.assertEqual(fake.argvs("nmcli", "connection", "modify"), [("nmcli", "connection", "modify", "uuid", NEW, "connection.autoconnect", "no")])

    def test_import_type_detection(self):
        good_wg = self.vpn("wg0.conf", "[Interface]\nPrivateKey = abc=\n")
        ovpn_conf = self.vpn("office.conf", "client\nremote vpn.example.com 1194\n")
        ovpn = self.vpn("office.ovpn", "client\n")
        for path, kind in ((good_wg, "wireguard"), (ovpn_conf, "openvpn"), (ovpn, "openvpn")):
            with self.subTest(path=path):
                seen = []
                self.assertTrue(self.call({"operation": "import-vpn", "path": path, "type": "auto"}, self.import_answers(seen))[0]["ok"])
                self.assertEqual((seen[0][0][4], seen[0][0][-1]), (kind, path))

    def test_import_rejections(self):
        too_big = self.vpn("big.ovpn", "x" * (256 * 1024 + 1))
        wrong = self.vpn("notes.txt", "[Interface]\nPrivateKey = a\n")
        link = self.root / "home/link.conf"
        os.symlink(wrong, link)
        cases = [("relative.conf", "invalid-request"), (str(self.root / "missing.conf"), "invalid-file"),
                 (too_big, "invalid-file"), (wrong, "invalid-file"), (str(link), "invalid-file"),
                 (str(self.root / "home"), "invalid-file")]
        for path, reason in cases:
            with self.subTest(path=path):
                self.assertEqual(self.call({"operation": "import-vpn", "path": path, "type": "auto"})[0], dict(ok=False, reason=reason))
        for plugin in (self.root / "usr/lib/NetworkManager/VPN").glob("*openvpn*"):
            plugin.unlink()
        ovpn = self.vpn("office.ovpn", "client\n")
        self.assertEqual(self.call({"operation": "import-vpn", "path": ovpn, "type": "auto"})[0], dict(ok=False, reason="plugin-missing"))

    # --- main -----------------------------------------------------------------------------------------------

    def main_with(self, payload, error=None):
        with patch("sys.stdin") as stdin, patch("builtins.print") as printed, patch("sys.argv", ["pentad_network.py"]):
            stdin.buffer.read.return_value = payload
            if error is not None:
                with patch.object(network, "handle", side_effect=error):
                    network.main()
            else:
                network.main()
        return json.loads(printed.call_args[0][0])

    def test_main_maps_errors(self):
        request = b'{"operation":"status"}'
        self.assertEqual(self.main_with(request, failure(3)), dict(ok=False, reason="timeout"))
        self.assertEqual(self.main_with(request, failure(10)), dict(ok=False, reason="not-found"))
        self.assertEqual(self.main_with(request, failure(4)), dict(ok=False, reason="failed", message="Error: boom"))
        self.assertEqual(self.main_with(request, failure(4, "E" * 400))["message"], "E" * 300)
        self.assertEqual(self.main_with(request, failure(2))["reason"], "failed")
        self.assertEqual(self.main_with(request, subprocess.TimeoutExpired("nmcli", 10)), dict(ok=False, reason="timeout"))
        self.assertEqual(self.main_with(request, FileNotFoundError(2, "No such file or directory", "nmcli")),
                         dict(ok=False, reason="nmcli-missing"))
        self.assertEqual(self.main_with(request, FileNotFoundError(2, "No such file or directory", "/x")),
                         dict(ok=False, reason="io", message="FileNotFoundError"))

    def test_main_reports_missing_nmcli_from_status(self):
        with patch.object(network, "run", FakeRun({})):
            self.assertEqual(self.main_with(b'{"operation":"status"}'), dict(ok=False, reason="nmcli-missing"))

    def test_main_rejects_large_and_invalid_requests(self):
        self.assertEqual(self.main_with(b" " * (64 * 1024 + 1)), dict(ok=False, reason="io", message="ValueError"))
        self.assertEqual(self.main_with(b"[1]"), dict(ok=False, reason="io", message="ValueError"))
        self.assertEqual(self.main_with(b'{"operation":"nope"}'), dict(ok=False, reason="io", message="ValueError"))


if __name__ == "__main__":
    unittest.main()
