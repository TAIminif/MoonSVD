"""Verify the exported MoonBit CLI against fixtures and independent XML checks."""

from argparse import ArgumentParser
from hashlib import sha256
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
from urllib.request import Request, urlopen
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "fixtures"
REFERENCES = (
    (
        "ARM_Example.svd",
        "https://raw.githubusercontent.com/ARM-software/CMSIS_5/5.9.0/CMSIS/Utilities/ARM_Example.svd",
        "d1a385a7e6792ea99211e17cc507c51a6641ed5356d1e156cf97471f9c030eb8",
        33,
    ),
    (
        "STM32F407.svd",
        "https://raw.githubusercontent.com/cmsis-svd/cmsis-svd-data/c65f8551e57c770344d229dcaa0bf838fa29aff4/data/STMicro/STM32F407.svd",
        "e2afca4f03f654225886d8508551cb7ac8f3c95ee28f18953aad466ecb56e6d6",
        1540,
    ),
)


def cli(*args, code=0, diagnostic=None):
    result = subprocess.run(
        ["node", str(ROOT / "bin/moonsvd.mjs"), *map(str, args)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=45,
        check=False,
    )
    assert result.returncode == code, (args, result.returncode, result.stderr)
    if diagnostic is not None:
        assert diagnostic in result.stderr, result.stderr
        assert not result.stdout
        return None
    assert not result.stderr, result.stderr
    return json.loads(result.stdout)


def verify_fixtures():
    v1 = FIXTURES / "timer-v1.svd"
    v2 = FIXTURES / "timer-v2.svd"
    report = cli("inspect", v1)
    assert report["name"] == "TimerDemo"
    assert report["peripherals"] == ["TIMER0", "TIMER1"]
    assert len(report["registers"]) == 6
    assert cli("check", v1) == {
        "device": "TimerDemo",
        "registers": 6,
        "findings": [],
    }
    selected = cli("lookup", v1, "TIMER1.CAPTURE[1]")
    assert (selected["address"], selected["access"]) == ("0x40000114", "read-only")
    issues = cli("check", FIXTURES / "bad-field.svd", code=1)["findings"]
    assert [(item["code"], item["path"]) for item in issues] == [
        ("field-range", "TIMER.CTRL.BAD")
    ]
    changes = cli("diff", v1, v2, code=1)["changes"]
    assert [(item["path"], item["properties"]) for item in changes] == [
        ("TIMER0.CTRL", ["resetValue", "fields"]),
        ("TIMER0.EVENTS", ["added"]),
        ("TIMER1.CTRL", ["resetValue", "fields"]),
        ("TIMER1.EVENTS", ["added"]),
    ]
    assert changes[0]["fieldChanges"][0]["name"] == "MODE"
    assert changes[0]["fieldChanges"][0]["properties"] == ["bitWidth"]
    assert changes[1]["fieldChanges"] == []
    assert not cli("diff", v2, v2)["changes"]
    cli("lookup", v1, "MISSING", code=1, diagnostic="was not found")
    with TemporaryDirectory(prefix="moonsvd-malformed-") as work:
        malformed = Path(work, "broken.svd")
        malformed.write_text("<device><name></device>", encoding="utf-8")
        cli("check", malformed, code=2, diagnostic="line 1")


def verify_access_behavior():
    before = FIXTURES / "status-v1.svd"
    after = FIXTURES / "status-v2.svd"
    selected = cli("lookup", before, "IRQ.STATUS")
    assert selected["readAction"] == "clear"
    assert selected["fields"][0]["modifiedWriteValues"] == "oneToClear"
    changes = cli("diff", before, after, code=1)["changes"]
    assert len(changes) == 1
    change = changes[0]
    assert change["path"] == "IRQ.STATUS"
    assert change["properties"] == ["readAction", "fields"]
    assert change["before"]["address"] == change["after"]["address"]
    assert change["after"]["readAction"] == "modifyExternal"
    level, pending = change["fieldChanges"]
    assert (level["name"], level["properties"]) == ("LEVEL", ["writeConstraint"])
    assert level["before"]["writeConstraint"]["maximum"] == "0x7"
    assert level["after"]["writeConstraint"] == {
        "kind": "range", "minimum": "0x0", "maximum": "0x3"
    }
    assert (pending["name"], pending["properties"]) == ("PENDING", ["modifiedWriteValues"])
    assert pending["after"]["modifiedWriteValues"] == "zeroToClear"


def verified_reference(directory, name, url, expected_hash):
    dest = directory / name
    if not dest.exists():
        request = Request(url, headers={"User-Agent": "MoonSVD-reproducibility"})
        with urlopen(request, timeout=30) as response:
            data = response.read(4 * 1024 * 1024 + 1)
        assert len(data) <= 4 * 1024 * 1024, name
        assert sha256(data).hexdigest() == expected_hash, name
        dest.write_bytes(data)
    assert sha256(dest.read_bytes()).hexdigest() == expected_hash, name
    return dest


def verify_reference(directory, name, url, digest, expected_count):
    path = verified_reference(directory, name, url, digest)
    source = ElementTree.parse(path).getroot()
    report = cli("inspect", path)
    assert source.findtext("name") == report["name"]
    assert len(report["registers"]) == expected_count
    assert not cli("check", path)["findings"]
    if name == "ARM_Example.svd":
        peripheral = source.find("./peripherals/peripheral[name='TIMER0']")
        raw = peripheral.find("./registers/register[name='RELOAD[%s]']")
        wanted = "TIMER0.RELOAD[3]"
        array_delta = 3 * int(raw.findtext("dimIncrement"), 0)
    else:
        peripheral = source.find("./peripherals/peripheral[name='RCC']")
        raw = peripheral.find("./registers/register[name='CR']")
        wanted = "RCC.CR"
        array_delta = 0
    expected = (
        int(peripheral.findtext("baseAddress"), 0)
        + int(raw.findtext("addressOffset"), 0)
        + array_delta
    )
    register = cli("lookup", path, wanted)
    assert int(register["address"], 16) == expected
    assert int(register["resetValue"], 16) == int(raw.findtext("resetValue"), 0)
    if wanted == "RCC.CR":
        target = raw.find("./fields/field[name='PLLI2SRDY']")
        field = next(item for item in register["fields"] if item["name"] == "PLLI2SRDY")
        assert int(field["bitOffset"]) == int(target.findtext("bitOffset"))
        assert int(field["bitWidth"]) == int(target.findtext("bitWidth"))
        assert field["access"] == target.findtext("access")
    print(f"{report['name']}: {expected_count} registers; {wanted} = {expected:#x}")


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument(
        "--official",
        action="store_true",
        help="also verify pinned Arm and STM32 reference files",
    )
    parser.add_argument(
        "--reference-dir",
        type=Path,
        help="reuse reference downloads at this location",
    )
    options = parser.parse_args()
    verify_fixtures()
    verify_access_behavior()
    if options.official:
        if options.reference_dir:
            options.reference_dir.mkdir(parents=True, exist_ok=True)
            for reference in REFERENCES:
                verify_reference(options.reference_dir, *reference)
        else:
            with TemporaryDirectory(prefix="moonsvd-reference-") as work:
                for reference in REFERENCES:
                    verify_reference(Path(work), *reference)
    print("MoonSVD CLI verification passed")


if __name__ == "__main__":
    main()
