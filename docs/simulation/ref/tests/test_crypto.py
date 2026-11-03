"""验证 4：加密层次的"强度边界"。

这里验证的**不是**"加密很安全"，而是：
* 各层算法能正确往返；
* 游戏内实现的强度**可以被穷举/分解**击穿 —— 测试要证明这一点，避免 UI 误标"安全"。
"""

from __future__ import annotations

from simcore.crypto import (
    ToyRSA, caesar, caesar_break_bruteforce, feistel_decrypt, feistel_encrypt,
    fnv1a32, otp_encrypt, sha256_hex,
)


def test_caesar_bruteforce_breaks() -> dict:
    plain = "ATTACK AT DAWN"
    cipher = caesar(plain, 3)
    found = [s for s, txt in caesar_break_bruteforce(cipher) if txt == plain]
    assert found == [3], found
    assert len(caesar_break_bruteforce(cipher)) == 26
    return {"candidates": 26, "recovered_shift": found[0]}


def test_otp_requires_unique_key() -> dict:
    msg = b"HELLO"
    key = bytes([0x11, 0x22, 0x33, 0x44, 0x55])
    enc = otp_encrypt(msg, key)
    assert otp_encrypt(enc, key) == msg
    # 密钥复用：两条密文异或 = 两条明文异或，信息直接泄露
    m2 = b"WORLD"
    c2 = otp_encrypt(m2, key)
    x = bytes(a ^ b for a, b in zip(enc, c2))
    y = bytes(a ^ b for a, b in zip(msg, m2))
    assert x == y
    return {"roundtrip": True, "key_reuse_leaks": True}


def test_feistel_bijection() -> dict:
    """8 位分组 × 8 位密钥：256 个分组必须构成双射，否则解密不成立。"""
    for key in range(256):
        imgs = set()
        for block in range(256):
            c = feistel_encrypt(block, key)
            assert feistel_decrypt(c, key) == block, (key, block)
            imgs.add(c)
        assert len(imgs) == 256, key
    return {"keys": 256, "blocks": 256, "bijective": True}


def test_feistel_bruteforce_breaks() -> dict:
    """密钥空间只有 256：穷举即可还原密钥，证明它不具备安全性。"""
    plain, key, cipher = 0x3C, 0xA5, None
    cipher = feistel_encrypt(plain, key)
    found = [k for k in range(256) if feistel_encrypt(plain, k) == cipher]
    assert len(found) >= 1 and key in found
    return {"key_space": 256, "matched": len(found)}


def test_rsa_toy_roundtrip_and_factorable() -> dict:
    rsa = ToyRSA()
    for m in (1, 42, 65, 1000, 3232):
        assert rsa.decrypt(rsa.encrypt(m)) == m
    p, q = rsa.factorize()
    assert p * q == rsa.n
    return {"n": rsa.n, "e": rsa.e, "d": rsa.d, "factored": (p, q),
            "security": "n=3233 可瞬间分解，仅教学"}


def test_hash_not_crypto() -> dict:
    """FNV 只做校验：改变 1 位就变，但**没有**抗碰撞承诺。"""
    a = fnv1a32(b"save")
    b = fnv1a32(b"save!")
    assert a != b
    assert len(sha256_hex(b"save")) == 64
    return {"fnv_differs": True, "sha256_len": 64}


ALL = [
    ("凯撒：26 次穷举即破", test_caesar_bruteforce_breaks),
    ("一次性密码本与密钥复用", test_otp_requires_unique_key),
    ("Feistel 玩具双射", test_feistel_bijection),
    ("Feistel 玩具可穷举", test_feistel_bruteforce_breaks),
    ("RSA 玩具可分解", test_rsa_toy_roundtrip_and_factorable),
    ("哈希≠加密", test_hash_not_crypto),
]

if __name__ == "__main__":
    for name, fn in ALL:
        r = fn()
        print(f"[PASS] {name}: {r}")
