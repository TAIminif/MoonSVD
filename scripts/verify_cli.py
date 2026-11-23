"""Verify the exported MoonBit CLI against fixtures and independent XML checks."""

from argparse import ArgumentParser
from hashlib import sha256
import json
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
from typing import NamedTuple, Optional
from urllib.request import Request, urlopen
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "fixtures"


class RegisterCheck(NamedTuple):
    peripheral: str
    register: str
    field: Optional[str] = None
    array_index: Optional[int] = None


REFERENCES = (
    (
        "ARM_Example.svd",
        "https://raw.githubusercontent.com/ARM-software/CMSIS_5/5.9.0/CMSIS/Utilities/ARM_Example.svd",
        "d1a385a7e6792ea99211e17cc507c51a6641ed5356d1e156cf97471f9c030eb8",
        33,
        (RegisterCheck("TIMER0", "RELOAD[%s]", array_index=3),),
    ),
    (
        "STM32F407.svd",
        "https://raw.githubusercontent.com/cmsis-svd/cmsis-svd-data/c65f8551e57c770344d229dcaa0bf838fa29aff4/data/STMicro/STM32F407.svd",
        "e2afca4f03f654225886d8508551cb7ac8f3c95ee28f18953aad466ecb56e6d6",
        1540,
        (RegisterCheck("RCC", "CR", "PLLI2SRDY"),),
    ),
    (
        "nrf52840.svd",
        "https://raw.githubusercontent.com/nordicsemi/nrfx/v3.14.0/mdk/nrf52840.svd",
        "da7c15ccf7f5323101ee5e4a17f10bbf9d1c504902c47fa9d8226fda42ed82b4",
        2332,
        (
            RegisterCheck("APPROTECT", "FORCEPROTECT", "FORCEPROTECT"),
            RegisterCheck("CC_HOST_RGF", "HOST_IOT_KDR1", "HOST_IOT_KDR1"),
        ),
    ),
    (
        "nrf5340_application.svd",
        "https://raw.githubusercontent.com/nordicsemi/nrfx/v3.14.0/mdk/nrf5340_application.svd",
        "6ae9ca34207a303fae6e0f3fead429531e887a42d3475f8d883d50e68ab8f708",
        9956,
        (RegisterCheck("CACHE_S", "DEBUGLOCK", "DEBUGLOCK"),),
    ),
    (
        "RP2040.svd",
        "https://raw.githubusercontent.com/raspberrypi/pico-sdk/2.2.0/src/rp2040/hardware_regs/RP2040.svd",
        "49f53398e0496b6de0849faf17a9f4e58565af311b98b727e4ebeee964619bc6",
        1182,
        (RegisterCheck("RESETS", "RESET", "USBCTRL"),),
    ),
    (
        "RP2350.svd",
        "https://raw.githubusercontent.com/raspberrypi/pico-sdk/2.2.0/src/rp2350/hardware_regs/RP2350.svd",
        "f1180d39bbc0e7c01b1a418bc61493c8450e25732f33bf2b0df381255078014c",
        3029,
        (
            RegisterCheck("RESETS", "RESET", "USBCTRL"),
            RegisterCheck("OTP_DATA", "BOOTSEL_LED_CFG"),
            RegisterCheck("OTP_DATA", "BOOTSEL_PLL_CFG"),
            RegisterCheck("OTP_DATA", "BOOTSEL_XOSC_CFG"),
            RegisterCheck("OTP_DATA", "FLASH_DEVINFO"),
        ),
        (
            ("reset-mask-width", "OTP_DATA.BOOTSEL_LED_CFG"),
            ("reset-mask-width", "OTP_DATA.BOOTSEL_PLL_CFG"),
            ("reset-mask-width", "OTP_DATA.BOOTSEL_XOSC_CFG"),
            ("reset-mask-width", "OTP_DATA.FLASH_DEVINFO"),
        ),
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
    issues = cli("check", FIXTURES / "bad-widths.svd", code=1)["findings"]
    assert [(item["code"], item["path"]) for item in issues] == [
        ("reset-mask-width", "P.R"),
        ("write-constraint-width", "P.R"),
        ("write-constraint-width", "P.R.F"),
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
    cli("lookup", v1, "bad\nname", code=1, diagnostic="bad\\u000aname")
    with TemporaryDirectory(prefix="moonsvd-malformed-") as work:
        malformed = Path(work, "broken.svd")
        malformed.write_text("<device><name></device>", encoding="utf-8")
        cli("check", malformed, code=2, diagnostic="line 1")
        document = ElementTree.tostring(
            ElementTree.parse(v1).getroot(), encoding="unicode"
        )
        declaration = '<?xml version="1.0"?>'
        for bom in ["", "\ufeff"]:
            for separator in ["", "\r\n"]:
                text = bom + declaration + separator + declaration + document
                try:
                    ElementTree.fromstring(text)
                except ElementTree.ParseError:
                    pass
                else:
                    raise AssertionError("duplicate XML declarations must be invalid")
                malformed.write_text(text, encoding="utf-8")
                cli(
                    "check", malformed, code=2,
                    diagnostic="XML declaration must occur once at the document start",
                )
            text = (
                bom + declaration + '<?xml-stylesheet href="style.xsl"?>'
                + document
            )
            ElementTree.fromstring(text)
            malformed.write_text(text, encoding="utf-8")
            assert len(cli("inspect", malformed)["registers"]) == 6
        attributes = " ".join(f'a{i}=""' for i in range(129))
        malformed.write_text(f"<device {attributes}/>", encoding="utf-8")
        cli("check", malformed, code=2, diagnostic="exceeds 128 attributes")
        malformed.write_text("<device a='" + ">" * 65_536 + "'/>", encoding="utf-8")
        cli("check", malformed, code=2, diagnostic="exceeds 65,536")
        malformed.write_bytes(b"<device>\xff</device>")
        cli("check", malformed, code=2, diagnostic="utf-8")
        with malformed.open("wb") as stream:
            stream.truncate(16 * 1024 * 1024 + 1)
        cli("check", malformed, code=2, diagnostic="at most 16 MiB")
        cli("check", work, code=2, diagnostic="regular file")
        if hasattr(os, "mkfifo"):
            pipe = Path(work, "input.svd")
            os.mkfifo(pipe)
            cli("check", pipe, code=2, diagnostic="regular file")
        boundary = Path(work, "boundary.svd")
        boundary.write_text(
            "<device><name>Chip 2.0</name><size>32</size><peripherals>"
            "<peripheral><name>P</name><baseAddress>0</baseAddress><registers>"
            "<register><dim>2</dim><dimIncrement>4</dimIncrement>"
            "<dimIndex>18446744073709551614-18446744073709551615</dimIndex>"
            "<name>R%s</name><addressOffset>0</addressOffset></register>"
            "</registers></peripheral></peripherals></device>",
            encoding="utf-8",
        )
        report = cli("inspect", boundary)
        assert report["name"] == "Chip 2.0"
        assert [item["path"] for item in report["registers"]] == [
            "P.R18446744073709551614", "P.R18446744073709551615"
        ]
        selected = cli("lookup", boundary, "P.R18446744073709551615")
        assert selected["address"] == "0x4"


def verify_address_lookup():
    fixture = FIXTURES / "timer-v1.svd"
    expected = cli("lookup", fixture, "TIMER1.CAPTURE[1]")
    for address in ["0x40000114", "0X40000114", str(0x40000114)]:
        assert cli("at", fixture, address) == {
            "device": "TimerDemo", "address": "0x40000114",
            "registers": [expected],
        }
    base = (1 << 64) - 2
    with TemporaryDirectory(prefix="moonsvd-address-") as work:
        path = Path(work, "boundary.svd")
        path.write_text(
            "<device><name>AddressDemo</name><size>8</size><peripherals>"
            f"<peripheral><name>P</name><baseAddress>{base}</baseAddress>"
            "<registers><register><dim>2</dim><dimIncrement>1</dimIncrement>"
            "<name>R%s</name><addressOffset>0</addressOffset></register>"
            "<register><name>VIEW</name><alternateRegister>R1</alternateRegister>"
            "<addressOffset>1</addressOffset></register>"
            "</registers></peripheral></peripherals></device>",
            encoding="utf-8",
        )
        assert not cli("check", path)["findings"]
        maximum = base + 1
        for argument in [str(maximum), hex(maximum), hex(maximum).upper(),
                         bin(maximum), oct(maximum), "0xffff_ffff_ffff_ffff"]:
            report = cli("at", path, argument)
            assert report["address"] == hex(maximum)
            assert [reg["path"] for reg in report["registers"]] == ["P.R1", "P.VIEW"]
            assert all(int(reg["address"], 16) == maximum for reg in report["registers"])
        report = cli("at", path, str(base))
        assert [reg["path"] for reg in report["registers"]] == ["P.R0"]
        assert cli("at", path, "0", code=1) == {
            "device": "AddressDemo", "address": "0x0", "registers": [],
        }
        assert cli("at", path, "0" * 128, code=1)["registers"] == []
        for invalid in ["", "-1", "+1", str(1 << 64), hex(1 << 64),
                        "0x", "0xZ", "1.5", "1e3", "ff", " 1", "1 ",
                        "1__0", "0x1_", "９", "0" * 129]:
            cli("at", path, invalid, code=2, diagnostic="expected an unsigned 64-bit address")


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


def verify_register_aliases():
    source = (
        "<device><name>Aliases</name><size>32</size><peripherals>"
        "<peripheral><name>P</name><baseAddress>0</baseAddress><registers>"
        "<register><name>A</name><addressOffset>0</addressOffset></register>"
        "<register><name>B</name><alternateRegister>A</alternateRegister>"
        "<addressOffset>0</addressOffset></register>"
        "<register><name>C</name><alternateRegister>B</alternateRegister>"
        "<addressOffset>0</addressOffset></register>"
        "</registers></peripheral></peripherals></device>"
    )
    with TemporaryDirectory(prefix="moonsvd-aliases-") as work:
        before = Path(work, "before.svd")
        after = Path(work, "after.svd")
        before.write_text(source, encoding="utf-8")
        assert not cli("check", before)["findings"]
        after.write_text(
            source.replace("<alternateRegister>A", "<alternateRegister>P.A"),
            encoding="utf-8",
        )
        assert not cli("diff", before, after)["changes"]
        after.write_text(
            source.replace(
                "<name>A</name>",
                "<name>A</name><alternateGroup>MODE</alternateGroup>",
            ).replace(
                "<alternateRegister>A</alternateRegister>",
                "<alternateGroup>MODE</alternateGroup>",
            ),
            encoding="utf-8",
        )
        assert not cli("check", after)["findings"]
        after.write_text(
            source.replace("<name>A</name>", "<name>A</name><alternateRegister>C</alternateRegister>"),
            encoding="utf-8",
        )
        findings = cli("check", after, code=1)["findings"]
        assert [item["path"] for item in findings if item["code"] == "alternate-register"] == [
            "P.A", "P.B", "P.C"
        ]


def verified_reference(directory, name, url, expected_hash):
    dest = directory / name
    if not dest.exists():
        request = Request(url, headers={"User-Agent": "MoonSVD-reproducibility"})
        with urlopen(request, timeout=30) as response:
            data = response.read(8 * 1024 * 1024 + 1)
        assert len(data) <= 8 * 1024 * 1024, name
        assert sha256(data).hexdigest() == expected_hash, name
        dest.write_bytes(data)
    assert sha256(dest.read_bytes()).hexdigest() == expected_hash, name
    return dest


def canonical_access(access):
    return {"writeonce": "writeOnce", "read-writeonce": "read-writeOnce"}.get(
        access, access
    )


def verify_register(path, source, check):
    peripheral = source.find(f"./peripherals/peripheral[name='{check.peripheral}']")
    raw = peripheral.find(f"./registers/register[name='{check.register}']")
    concrete_name = check.register
    array_delta = 0
    if check.array_index is not None:
        concrete_name = concrete_name.replace("%s", str(check.array_index))
        array_delta = check.array_index * int(raw.findtext("dimIncrement"), 0)
    wanted = f"{check.peripheral}.{concrete_name}"
    address = (
        int(peripheral.findtext("baseAddress"), 0)
        + int(raw.findtext("addressOffset"), 0)
        + array_delta
    )
    register = cli("lookup", path, wanted)
    assert int(register["address"], 16) == address, wanted
    at_address = cli("at", path, str(address))
    assert int(at_address["address"], 16) == address, wanted
    assert register in at_address["registers"], wanted
    assert all(int(item["address"], 16) == address for item in at_address["registers"])
    assert int(register["resetValue"], 16) == int(raw.findtext("resetValue"), 0)
    size = (
        raw.findtext("size") or peripheral.findtext("size")
        or source.findtext("size") or source.findtext("width")
    )
    assert register["size"] == int(size, 0), wanted
    reset_mask = (
        raw.findtext("resetMask") or peripheral.findtext("resetMask")
        or source.findtext("resetMask")
    )
    if reset_mask is None:
        assert register["resetMask"] is None, wanted
    else:
        assert int(register["resetMask"], 16) == int(reset_mask, 0), wanted
    access = canonical_access(
        raw.findtext("access") or peripheral.findtext("access") or source.findtext("access")
    )
    assert register["access"] == access, wanted
    if check.field is not None:
        target = raw.find(f"./fields/field[name='{check.field}']")
        field = next(item for item in register["fields"] if item["name"] == check.field)
        if target.find("bitRange") is not None:
            high, offset = map(int, target.findtext("bitRange").strip("[]").split(":"))
            width = high - offset + 1
        elif target.find("lsb") is not None:
            offset = int(target.findtext("lsb"))
            width = int(target.findtext("msb")) - offset + 1
        else:
            offset = int(target.findtext("bitOffset"))
            width = int(target.findtext("bitWidth", "1"))
        assert int(field["bitOffset"]) == offset, wanted
        assert int(field["bitWidth"]) == width, wanted
        assert field["access"] == canonical_access(target.findtext("access") or access), wanted
    return f"{wanted} = {address:#x}"


def verify_reference(
    directory, name, url, digest, expected_count, checks, expected_findings=()
):
    path = verified_reference(directory, name, url, digest)
    source = ElementTree.parse(path).getroot()
    report = cli("check", path, code=1 if expected_findings else 0)
    assert report["device"] == source.findtext("name")
    assert report["registers"] == expected_count
    assert [(item["code"], item["path"]) for item in report["findings"]] == list(
        expected_findings
    )
    verified = ", ".join(verify_register(path, source, check) for check in checks)
    print(
        f"{report['device']}: {expected_count} registers; {verified}; "
        f"{len(expected_findings)} expected diagnostics"
    )


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument(
        "--official",
        action="store_true",
        help="also verify pinned Arm, STM32, Nordic and Raspberry Pi reference files",
    )
    parser.add_argument(
        "--reference-dir",
        type=Path,
        help="reuse reference downloads at this location",
    )
    options = parser.parse_args()
    verify_fixtures()
    verify_address_lookup()
    verify_access_behavior()
    verify_register_aliases()
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
