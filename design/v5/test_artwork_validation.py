import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zlib
from png_artwork import inspect_png, InvalidArtwork
from verify_artwork import verify


def chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload) & 0xffffffff)


def png(mode=0, level=6):
    # Identical 2px RGBA pixels, independently encoded with None/Sub filters.
    row = bytes([255,0,0,255, 0,0,0,0])
    encoded = row if mode == 0 else row[:4] + bytes((row[i]-row[i-4]) & 255 for i in range(4,8))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB',2,1,8,6,0,0,0))
            + chunk(b'sRGB', b'\0') + chunk(b'IDAT', zlib.compress(bytes([mode])+encoded,level)) + chunk(b'IEND', b''))


class ArtworkValidationTests(unittest.TestCase):
    def test_real_scanlines_alpha_and_profile(self):
        result = inspect_png(png())
        self.assertEqual(result['pixels'], [2,1]); self.assertTrue(result['alphaChannel'])
        self.assertEqual(result['colorProfile'], 'sRGB')
    def test_reencoding_does_not_evade_duplicate_check(self):
        self.assertNotEqual(png(), png(1,9))
        self.assertEqual(inspect_png(png())['pixelSHA256'], inspect_png(png(1,9))['pixelSHA256'])
    def test_truncation_crc_and_missing_idat_rejected(self):
        broken = bytearray(png()); broken[-6] ^= 1
        for data in [png()[:24], png()[:-3], bytes(broken), png()[:33]+chunk(b'IEND',b'')]:
            with self.subTest(size=len(data)), self.assertRaises(InvalidArtwork): inspect_png(data)
    def test_valid_crc_but_bad_compression_rejected(self):
        data = png()[:33] + chunk(b'IDAT',b'not zlib') + chunk(b'IEND',b'')
        with self.assertRaises(InvalidArtwork): inspect_png(data)
    def test_decompression_bomb_bound(self):
        data = png()[:33] + chunk(b'IDAT',zlib.compress(b'\0'*10000)) + chunk(b'IEND',b'')
        with self.assertRaises(InvalidArtwork): inspect_png(data)
    def test_manifest_hash_duplicate_and_missing_receipts(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'a.png').write_bytes(png()); (root/'b.png').write_bytes(png(1,9))
            assets = [dict(path=x,theme='song',role='emblem',minimumPixels=[2,1],alphaRequired=True,sha256=None)
                      for x in ['a.png','b.png','missing.png']]
            assets[0]['sha256'] = hashlib.sha256(png()).hexdigest()
            assets[1]['sha256'] = hashlib.sha256(png(1,9)).hexdigest()
            receipt = verify(root,dict(assets=assets))
            self.assertFalse(receipt['visualApproval']); self.assertEqual(receipt['blocked'],2)
            self.assertEqual(receipt['assets'][1]['status'],'DUPLICATE_ARTWORK')
            assets[0]['sha256'] = None
            self.assertEqual(verify(root,dict(assets=assets))['assets'][0]['status'],'SHA256_NOT_PINNED')
            assets[0]['sha256'] = '0'*64
            self.assertEqual(verify(root,dict(assets=assets))['assets'][0]['status'],'SHA256_MISMATCH')

if __name__ == '__main__': unittest.main()
