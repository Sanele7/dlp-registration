import sys

sys.path.insert(0, "src")

from handlers import registration


def test_reference_has_the_agreed_format():
    ref = registration._new_reference()
    assert ref.startswith("DLP-") and len(ref) == 12
    assert all(ch in registration.REF_ALPHABET for ch in ref[4:])


def test_reference_never_uses_confusing_characters():
    for _ in range(300):
        assert not set("01OI") & set(registration._new_reference()[4:])


def test_references_do_not_repeat_in_a_large_sample():
    refs = {registration._new_reference() for _ in range(500)}
    assert len(refs) == 500


def test_pin_is_always_six_digits():
    for _ in range(300):
        pin = registration._new_pin()
        assert len(pin) == 6 and pin.isdigit()


def test_pin_hash_is_not_the_pin_and_is_repeatable():
    first = registration._hash_pin("123456", "salt-one")
    assert first != "123456"
    assert first == registration._hash_pin("123456", "salt-one")


def test_same_pin_with_different_salt_gives_different_hash():
    assert registration._hash_pin("123456", "salt-one") != registration._hash_pin("123456", "salt-two")


def test_different_pin_gives_different_hash():
    assert registration._hash_pin("123456", "salt-one") != registration._hash_pin("654321", "salt-one")
