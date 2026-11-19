"""用法：sudo env OPENWRT_ROOTFS=/path/to/openwrt-x86-64-rootfs.tar.gz python3 tests/rpc.py"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]
RPC = "/usr/libexec/rpcd/small-tailscale"


@unittest.skipUnless(os.environ.get("OPENWRT_ROOTFS"), "需要官方 x86_64 rootfs")
class RpcTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        subprocess.run(["tar", "xzf", os.environ["OPENWRT_ROOTFS"], "-C", self.root], check=True)
        for folder in ("tmp/log", "tmp/run", "etc/crontabs", "usr/share/small-tailscale/scripts"):
            (self.root / folder).mkdir(parents=True, exist_ok=True)
        (self.root / "dev/null").touch()
        shutil.copytree(REPO / "luci-app-small-tailscale/root", self.root, dirs_exist_ok=True)
        for script in (REPO / "scripts").glob("*.sh"):
            dest = self.root / "usr/share/small-tailscale/scripts" / script.name
            shutil.copy(script, dest)
            dest.chmod(0o755)

    def call(self, method, **args):
        proc = subprocess.run(["chroot", self.root, RPC, "call", method],
                              input=json.dumps(args), text=True, capture_output=True, timeout=8)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return json.loads(proc.stdout)

    def write(self, name, value, executable=False):
        path = self.root / name.lstrip("/")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
        if executable:
            path.chmod(0o755)

    def test_official_package_is_preserved_even_with_project_leftovers(self):
        self.write("etc/tailscale/install.conf", "MODE=local\n")
        self.write("etc/tailscale/tools.sh", "# old helper\n")
        self.write("etc/init.d/tailscale", "# official init\n")
        self.write("usr/sbin/tailscaled", "official binary")
        self.assertEqual(self.call("status")["source"], "external")
        for name in ("save", "install", "start"):
            self.assertIn("error", self.call(name))
        self.assertEqual((self.root / "etc/init.d/tailscale").read_text(), "# official init\n")

    def project_node(self):
        self.write("etc/tailscale/tools.sh", "# old tools")
        self.write("etc/tailscale/helper.sh", (REPO / "scripts/helper.sh").read_text() + "\n# old helper\n")
        self.write("etc/tailscale/install.conf", "MODE=local\nVERSION=v1.0.0\nAUTO_UPDATE=true\n")
        self.write("etc/config/tailscaled.state", "existing identity")
        self.write("usr/local/bin/tailscaled",
                   '#!/bin/sh\ncase "$1" in version) echo 1.2.3 ;; status) cat /tmp/node.json ;; esac\n', True)
        (self.root / "usr/bin/tailscale").symlink_to("/usr/local/bin/tailscaled")

    def run_postinst(self):
        self.write("tmp/postinst", (REPO / "luci-app-small-tailscale/postinst").read_text(), True)
        self.write("etc/init.d/rpcd", "#!/bin/sh\nexit 0\n", True)
        subprocess.run(["chroot", self.root, "/tmp/postinst"], check=True, timeout=5)

    def test_plugin_install_refreshes_old_project_before_first_rpc(self):
        self.project_node()
        self.write("etc/init.d/tailscale", "#!/bin/sh\n# /etc/tailscale/tools.sh\n", True)
        self.write("etc/rc.common", 'echo "$2" > /tmp/tailscale-action\n')
        conf = self.root / "etc/tailscale/install.conf"
        before = conf.read_bytes()
        self.run_postinst()
        self.assertEqual((self.root / "etc/tailscale/helper.sh").read_bytes(), (REPO / "scripts/helper.sh").read_bytes())
        self.assertIn("--on-start", (self.root / "etc/init.d/tailscale").read_text())
        self.assertEqual((self.root / "etc/config/tailscaled.state").read_text(), "existing identity")
        self.assertEqual(conf.read_bytes(), before)
        self.assertFalse((self.root / "tmp/tailscale-action").exists())

    def test_postinst_does_not_adopt_fresh_router_or_other_scripts(self):
        self.run_postinst()
        self.assertFalse((self.root / "etc/tailscale").exists())
        self.write("etc/tailscale/helper.sh", "# unrelated helper")
        self.write("etc/tailscale/tools.sh", "# unrelated tools")
        self.run_postinst()
        self.assertEqual((self.root / "etc/tailscale/tools.sh").read_text(), "# unrelated tools")
        self.assertFalse((self.root / "etc/tailscale/setup.sh").exists())

    def test_postinst_preserves_official_apk_during_transaction(self):
        self.project_node()
        self.write("usr/bin/apk", "#!/bin/sh\ntouch /tmp/nested-apk\nexit 1\n", True)
        self.write("lib/apk/db/installed", "P:tailscale\nV:1.0\n")
        self.run_postinst()
        self.assertFalse((self.root / "tmp/nested-apk").exists())
        self.assertEqual((self.root / "etc/tailscale/tools.sh").read_text(), "# old tools")

    def test_stale_browser_cannot_overwrite_cli_settings(self):
        self.project_node()
        previous = self.call("config")
        del previous["options"]
        request = dict(previous, mode="tmp")
        self.write("etc/tailscale/github-download.env", "GITHUB_DOWNLOAD_BASE_URL=https://new.example\n")
        self.assertIn("error", self.call("save", **request, previous=previous))
        current = self.call("config")
        self.assertEqual((current["mirror"], current["mode"]), ("https://new.example", "local"))
        del current["options"]
        self.assertEqual(self.call("save", **dict(current, mode="tmp"), previous=current), {"ok": True})
        install = (self.root / "etc/tailscale/install.conf").read_text().splitlines()
        self.assertIn("MODE=local", install)
        self.assertIn("REQUESTED_MODE=tmp", install)
        self.assertEqual(self.call("config")["mode"], "tmp")

    def test_old_node_shows_running_version_and_tracks_authorization(self):
        self.project_node()
        self.write("tmp/node.json", json.dumps({"BackendState": "NeedsLogin", "AuthURL": "https://login.example/a"}))
        status = self.call("status")
        self.assertEqual((status["source"], status["version"], status["auth_url"]),
                         ("project", "v1.2.3", "https://login.example/a"))
        self.write("tmp/node.json", json.dumps({"BackendState": "Running", "TailscaleIPs": ["100.70.1.2"]}))
        status = self.call("status")
        self.assertEqual((status["state"], status["ips"], status["auth_url"]), ("Running", ["100.70.1.2"], ""))

    def test_config_reads_terminal_changes_and_old_nodes_follow_latest(self):
        self.project_node()
        self.write("etc/tailscale/github-download.env", "GITHUB_DOWNLOAD_BASE_URL=https://mirror.example\n")
        self.write("etc/tailscale/tailscale_up.conf", '--hostname="router one"\n--accept-dns="false"\n')
        cfg = self.call("config")
        self.assertEqual((cfg["auto_update"], cfg["pinned_version"], cfg["mirror"]),
                         (True, "", "https://mirror.example"))
        self.assertEqual(cfg["params"], {"hostname": "router one", "accept-dns": "false"})
        self.assertIn("advertise-routes", {p["key"] for p in cfg["options"]})

    def test_browser_config_is_readable_by_cli_and_preserves_identity(self):
        self.project_node()
        request = dict(mode="tmp", auto_update=False, pinned_version="v1.5.6",
                       mirror="https://mirror.example/ts", params={"hostname": "router one", "accept-dns": "false"})
        self.assertEqual(self.call("save", **request), {"ok": True})
        cfg = self.call("config")
        self.assertEqual({k: cfg[k] for k in request}, request)
        self.assertEqual((self.root / "etc/config/tailscaled.state").read_text(), "existing identity")
        self.assertEqual(os.readlink(self.root / "usr/bin/tailscale-helper"), "/etc/tailscale/helper.sh")
        self.assertEqual((self.root / "etc/tailscale/tailscale_up.conf").read_text().splitlines(),
                         ['--accept-dns="false"', '--hostname="router one"'])
        self.assertIn("error", self.call("save", **(request | {"params": {"hostname": "a\nb"}})))
        self.assertEqual(self.call("config")["params"], request["params"])

    def test_first_download_reports_failure_without_starting_service(self):
        self.write("usr/share/small-tailscale/scripts/setup.sh",
                   '#!/bin/sh\nsleep 1\necho "连接镜像失败" >&2\nexit 1\n', True)
        self.assertEqual(self.call("install"), {"ok": True})
        self.assertTrue(self.call("status")["busy"])
        self.assertIn("error", self.call("install"))
        deadline = time.monotonic() + 5
        while self.call("status")["busy"] and time.monotonic() < deadline:
            time.sleep(0.1)
        self.assertFalse(self.call("status")["busy"])
        self.assertIn("连接镜像失败", self.call("logs", kind="install")["text"])
        self.assertNotIn("连接镜像失败", self.call("logs", kind="runtime")["text"])

    def test_start_shows_cli_authorization_link_until_node_connects(self):
        self.project_node()
        self.write("etc/init.d/tailscale", "#!/bin/sh\n# /etc/tailscale/tools.sh\nexit 0\n", True)
        self.write("usr/share/small-tailscale/scripts/setup_service.sh", "#!/bin/sh\nexit 0\n", True)
        self.write("tmp/node.json", '{"BackendState":"NeedsLogin"}')
        self.write("usr/local/bin/tailscaled",
                   '#!/bin/sh\ncase "$1" in status) cat /tmp/node.json;; version) echo 1.2.3;; '
                   'up) echo "    https://login.example/authorize/abc"; sleep 1;; esac\n', True)
        self.assertEqual(self.call("start"), {"ok": True})
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            if self.call("status")["auth_url"] == "https://login.example/authorize/abc":
                break
            time.sleep(0.1)
        else:
            self.fail(self.call("logs", kind="runtime")["text"])
        self.write("tmp/node.json", '{"BackendState":"Running","TailscaleIPs":["100.65.1.2"]}')
        self.assertEqual(self.call("status")["auth_url"], "")
        while self.call("status")["busy"] and time.monotonic() < deadline:
            time.sleep(0.1)

    def test_saved_secret_can_be_retained_without_returning_it_to_browser(self):
        self.project_node()
        self.write("etc/tailscale/tailscale_up.conf", '--auth-key="fixture-token"\n')
        cfg = self.call("config")
        self.assertEqual(cfg["params"], {"auth-key": "••••"})
        cfg.pop("options")
        cfg["params"]["hostname"] = "new-name"
        self.assertEqual(self.call("save", **cfg), {"ok": True})
        self.assertIn('--auth-key="fixture-token"', (self.root / "etc/tailscale/tailscale_up.conf").read_text())

    def test_ubus_preserves_parameter_object_when_saving(self):
        sock = "/tmp/rpc-test.sock"
        (self.root / "dev/urandom").write_bytes(os.urandom(65536))
        for exe in ("/sbin/ubusd", "/sbin/rpcd"):
            proc = subprocess.Popen(["chroot", self.root, exe, "-s", sock],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            def stop(proc=proc):
                proc.terminate()
                proc.wait(timeout=3)
            self.addCleanup(stop)
            if exe.endswith("ubusd"):
                for _ in range(50):
                    if (self.root / sock.lstrip("/")).exists():
                        break
                    time.sleep(0.02)
        ubus = ["chroot", self.root, "/bin/ubus", "-s", sock]
        for _ in range(50):
            if subprocess.run(ubus + ["list", "small-tailscale"], capture_output=True).stdout.strip():
                break
            time.sleep(0.02)
        request = dict(mode="local", auto_update=False, pinned_version="",
                       mirror="https://github.com", params={"hostname": "my-router"})
        reply = subprocess.check_output(ubus + ["call", "small-tailscale", "save", json.dumps(request)])
        self.assertEqual(json.loads(reply), {"ok": True})
        self.assertEqual(self.call("config")["params"], {"hostname": "my-router"})

    def test_fresh_router_status(self):
        status = self.call("status")
        self.assertEqual((status["source"], status["installed"], status["state"]),
                         ("none", False, "Stopped"))
        self.assertFalse((self.root / "etc/tailscale").exists())


if __name__ == "__main__":
    unittest.main()
