"""加密层参考实现：从凯撒到公钥的抽象阶梯。

**强度边界（必须引用到 UI 上）**
----------------------------------
* 凯撒/单表替换：可被频率分析在**几十个字符**内破译。游戏内只作"历史上曾经有用"的演示。
* 一次性密码本（OTP）：**数学上安全，但前提是密钥真随机、等长、只用一次**。
  游戏内无法提供真随机源（确定性存档），所以游戏内 OTP 只是"OTP 结构"，
  **不得标注为安全**。
* Feistel 玩具分组密码：这里 8 位分组、4 轮、密钥 8 位，**可被穷举**（2^8 次）。
  它只演示"混淆 + 扩散"的结构，绝不是 DES/AES。
* RSA 玩具：n=3233（61×53），**可在毫秒内分解**。只演示"公钥/私钥不对称"的数学，
  没有填充（textbook RSA），确定性加密 → 相同明文得相同密文，**不安全**。
* FNV-1a：**非密码学哈希**，只用于存档校验和/去重，不能用于签名。

结论：游戏内所有自制加密都只能教"机制"，不能教"安全"。任何 UI 文案禁止出现"安全/加密后无法破解"。
"""

from __future__ import annotations

import hashlib
import math
from typing import List, Tuple


# ---- 古典 -------------------------------------------------------------------


def caesar(text: str, shift: int) -> str:
    out = []
    for ch in text:
        if "a" <= ch <= "z":
            out.append(chr((ord(ch) - 97 + shift) % 26 + 97))
        elif "A" <= ch <= "Z":
            out.append(chr((ord(ch) - 65 + shift) % 26 + 65))
        else:
            out.append(ch)
    return "".join(out)


def caesar_break_bruteforce(cipher: str) -> List[Tuple[int, str]]:
    """25 次尝试全部列出 —— 用来在游戏里"亲手体验"为什么它不安全。"""
    return [(s, caesar(cipher, -s)) for s in range(26)]


def otp_encrypt(msg: bytes, key: bytes) -> bytes:
    if len(msg) != len(key):
        raise ValueError("OTP 要求密钥与明文等长")
    return bytes(a ^ b for a, b in zip(msg, key))


# ---- Feistel 玩具（8 位分组 / 4 轮） -----------------------------------------


def _f(round_key: int, half: int) -> int:
    # 非线性-looking 但**可预测**的轮函数；只为演示结构，不提供任何强度保证
    x = (half * 0x1B + round_key) & 0xFF
    return ((x << 3) | (x >> 5)) & 0xFF


def feistel_encrypt(block: int, key: int) -> int:
    left, right = (block >> 4) & 0xF, block & 0xF
    for r in range(4):
        rk = (key >> (r * 2)) & 0x3
        left, right = right, left ^ (_f(rk, right) & 0xF)
    return (left << 4) | right


def feistel_decrypt(block: int, key: int) -> int:
    left, right = (block >> 4) & 0xF, block & 0xF
    for r in reversed(range(4)):
        rk = (key >> (r * 2)) & 0x3
        # 逆变换：(L', R') = (R, L ^ F(R,k)) → L = R' ^ F(L',k), R = L'
        left, right = right ^ (_f(rk, left) & 0xF), left
    return (left << 4) | right


# ---- RSA 玩具 -----------------------------------------------------------------


def egcd(a: int, b: int) -> Tuple[int, int, int]:
    if b == 0:
        return a, 1, 0
    g, x, y = egcd(b, a % b)
    return g, y, x - (a // b) * y


def modinv(a: int, m: int) -> int:
    g, x, _ = egcd(a % m, m)
    if g != 1:
        raise ValueError("逆元不存在")
    return x % m


class ToyRSA:
    """n=3233 的教科书 RSA。密钥可在一秒内被分解，**仅用于教学**。"""

    def __init__(self, p: int = 61, q: int = 53, e: int = 17):
        self.p, self.q = p, q
        self.n = p * q
        self.phi = (p - 1) * (q - 1)
        self.e = e
        self.d = modinv(e, self.phi)
        assert pow(pow(42, self.e, self.n), self.d, self.n) == 42

    def encrypt(self, m: int) -> int:
        if not 0 <= m < self.n:
            raise ValueError("明文超出模数")
        return pow(m, self.e, self.n)

    def decrypt(self, c: int) -> int:
        return pow(c, self.d, self.n)

    def factorize(self) -> Tuple[int, int]:
        """演示"能被瞬间分解"：直接试除。"""
        n = self.n
        for i in range(2, math.isqrt(n) + 1):
            if n % i == 0:
                return i, n // i
        return 1, n


# ---- 校验和（非密码学） --------------------------------------------------------


def fnv1a32(data: bytes) -> int:
    h = 0x811C9DC5
    for b in data:
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()
