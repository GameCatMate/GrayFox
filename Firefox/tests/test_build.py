import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile
import io
import struct

spec = importlib.util.spec_from_file_location("builder", Path(__file__).parents[1] / "build.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)

class JarTests(unittest.TestCase):
    def test_localized_application_name(self):
        text = '/* Firefox license stays unchanged */\nCFBundleName = "Firefox";\nCFBundleDisplayName = "Firefox";\nNSCameraUsageDescription = "Камера";\n'
        expected = text.replace('= "Firefox";', '= "GrayFox";')
        for encoding in ('utf-8', 'utf-16'):
            self.assertEqual(builder.brand_localized_name(text.encode(encoding)).decode(encoding), expected)

    def test_native_addons_navigation(self):
        html = '<html><head><script src="native.js"></script></head><body><div id="full">Native controls</div></body></html>'
        patched = builder.patch_addons_navigation(html)
        self.assertIn('<div id="full">Native controls</div>', patched)
        self.assertIn('src="native.js"', patched)
        self.assertEqual(patched.count('mybro/navigation.js'), 1)
        self.assertEqual(patched.count('mybro/addons-navigation.js'), 1)
        self.assertEqual(patched.count('mybro/addons-layout.css'), 1)
        with self.assertRaises(ValueError):
            builder.patch_addons_navigation('<html></html>')

    def test_normal_zip_and_firefox_directory(self):
        with tempfile.TemporaryDirectory() as folder:
            normal = Path(folder) / "normal.jar"
            builder.write_jar(normal, {"chrome/browser.xhtml": b"hello", "defaults/pref.js": b"pref(1);"})
            self.assertEqual(builder.read_jar(normal)["chrome/browser.xhtml"], b"hello")
            data = normal.read_bytes()
            end_offset = data.rfind(b"PK\x05\x06")
            end = bytearray(data[end_offset:]); size, offset = struct.unpack_from("<II", end, 12)
            directory = bytearray(data[offset:offset + size])
            shift = 4 + size + len(end)
            cursor = 0
            while cursor < len(directory):
                original = struct.unpack_from("<I", directory, cursor + 42)[0]
                struct.pack_into("<I", directory, cursor + 42, original + shift)
                namesize, extra, comment = struct.unpack_from("<HHH", directory, cursor + 28)
                cursor += 46 + namesize + extra + comment
            struct.pack_into("<I", end, 16, 4)
            optimized = Path(folder) / "optimized.jar"
            optimized.write_bytes(struct.pack("<I", shift) + directory + end + data[:offset] + end)
            self.assertEqual(builder.read_jar(normal), builder.read_jar(optimized))

    def test_refuse_webkit_destination(self):
        with self.assertRaises(ValueError):
            builder.build(Path("missing"), builder.ROOT / "myBro.app")

if __name__ == "__main__":
    unittest.main()
