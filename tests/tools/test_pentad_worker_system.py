import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools import pentad_worker as worker
from tools import pentad_worker_system as system

core = worker.core
GIB = 1024 ** 3
MIB = 1024 ** 2


class Ctx:
    def __init__(self):
        self.scope = core.CancelScope()

    def check(self):
        self.scope.check()


class VramTests(unittest.TestCase):
    """system.vram against a fake /sys tree and a fake nvidia-smi; the real ones are never read."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.sys = self.root / 'sys'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        (self.sys / 'class' / 'drm').mkdir(parents=True)
        patcher = mock.patch.object(system, 'SYSFS_ROOT', str(self.sys))
        patcher.start()
        self.addCleanup(patcher.stop)
        # Only the fake programs are on PATH, so a real nvidia-smi never answers.
        env = mock.patch.dict(os.environ, {'PATH': str(self.bin)})
        env.start()
        self.addCleanup(env.stop)

    def card(self, name, total=None, used=None, vendor='0x1002'):
        device = self.sys / 'class' / 'drm' / name / 'device'
        device.mkdir(parents=True)
        (device / 'vendor').write_text(vendor + '\n')
        if total is not None:
            (device / 'mem_info_vram_total').write_text(f'{total}\n')
        if used is not None:
            (device / 'mem_info_vram_used').write_text(f'{used}\n')

    def nvidia(self, output, code=0):
        path = self.bin / 'nvidia-smi'
        path.write_text('#!/bin/sh\n'
                        f'printf "%s\\n" "$@" > "{self.root}/nvidia-args"\n'
                        f"printf '{output}'\n"
                        f'exit {code}\n')
        path.chmod(0o755)

    def vram(self):
        result = system.op_vram({}, Ctx())
        self.assertTrue(result['ok'])
        return result['value']

    def test_amd_sysfs_picks_the_largest_card(self):
        self.card('card0', 512 * MIB, 100 * MIB)
        self.card('card1', 17095983104, 6 * GIB)
        self.card('card1-DP-1')  # a connector, not a card
        self.card('card2', vendor='0x8086')  # no VRAM files, like an Intel iGPU
        value = self.vram()
        self.assertEqual(value['available'], True)
        self.assertEqual((value['source'], value['totalBytes'], value['usedBytes']), ('sysfs', 17095983104, 6 * GIB))
        self.assertEqual([gpu['totalBytes'] for gpu in value['gpus']], [17095983104, 512 * MIB])
        self.assertEqual(value['gpus'][0]['vendor'], 'AMD')

    def test_garbage_in_sysfs_is_ignored(self):
        self.card('card0', 'lots', 1)
        self.card('card1', 1000, 2000)
        value = self.vram()
        self.assertEqual(value['gpus'], [{'vendor': 'AMD', 'totalBytes': 1000, 'usedBytes': 1000, 'source': 'sysfs'}])

    def test_nvidia_smi_when_sysfs_has_nothing(self):
        self.nvidia('24564, 6120\\n8192, 10\\n[N/A], 3\\n')
        value = self.vram()
        self.assertEqual((value['source'], value['totalBytes'], value['usedBytes']),
                         ('nvidia-smi', 24564 * MIB, 6120 * MIB))
        self.assertEqual(len(value['gpus']), 2)
        args = (self.root / 'nvidia-args').read_text().split()
        self.assertEqual(args, ['--query-gpu=memory.total,memory.used', '--format=csv,noheader,nounits'])

    def test_unavailable_without_sysfs_or_nvidia(self):
        self.assertEqual(self.vram(), {'available': False})
        self.nvidia('', code=9)
        self.assertEqual(self.vram(), {'available': False})

    def test_missing_drm_directory(self):
        with mock.patch.object(system, 'SYSFS_ROOT', str(self.root / 'nowhere')):
            self.assertEqual(self.vram(), {'available': False})

    def test_registers_the_op(self):
        ops = {}
        system.register_ops(ops)
        self.assertEqual(sorted(ops), ['system.vram'])
        self.assertTrue(worker.OP_NAME.match('system.vram'))


if __name__ == '__main__':
    unittest.main()
