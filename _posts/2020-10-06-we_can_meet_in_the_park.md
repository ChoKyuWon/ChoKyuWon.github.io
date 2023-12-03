---
layout: post
title: We can meet in the park
subtitle: CCE 2020 Qualification Writeup
gh-repo: ChoKyuWon/writeups
gh-badge: [star, fork, follow]
tags: [writeup]
comments: true
---

Use meet-in-the-middle attack.
```python
from Crypto.Cipher import AES
import hashlib

ENCRYPTED = b'\xA5\xD1\xDB\x88\xFD\x34\xC6\x46\x0C\xF0\xC9\x55\x0F\xDB\x61\x9E\xB9\x17\xD7\x0B\xC8\x3D\xE5\x1B\x09\x71\xAE\x5F\x1C\xB5\xC7\x2C\xC5\x3F\x5A\xA7\xFB\xED\x63\xE6\xAD\x04\x0D\x16\xF6\x33\x16\x01'

memo1 = []
memo2 = []

def Check(buf, ml, cl):
    if ml != cl:
        for ch in range(0,100):
            buf[cl] = ch
            Check(buf, ml, cl+1)
        return
    for ch in range(0,100):
        buf[cl] = ch
        tmpBuf = bytes(buf)

        print(buf)
        aes1 = AES.new(hashlib.sha256(tmpBuf[0:4]).digest(), AES.MODE_ECB)
        aes2 = AES.new(hashlib.sha256(tmpBuf[0:4]).digest(), AES.MODE_ECB)

        memo1.append(aes1.encrypt(b"___FLAGHEADER___"))
        memo2.append(aes2.decrypt(ENCRYPTED[0:16]))

def key2buf(key):
    n0 = key % 100
    n1 = int(key/100) % 100
    n2 = int(key/(100**2)) % 100
    n3 = int(key/(100**3)) % 100
    buf = [n3,n2,n1,n0]
    return bytes(buf)

def main():
    buf = [0,0,0,0]
    Check(buf, 3, 0)
    
    mitm = list(set(memo1)&set(memo2))[0]

    key1 = memo1.index(mitm)
    key2 = memo2.index(mitm)

    aes1 = AES.new(hashlib.sha256(key2buf(key1)).digest(), AES.MODE_ECB)
    aes2 = AES.new(hashlib.sha256(key2buf(key2)).digest(), AES.MODE_ECB)
    result = aes1.decrypt(aes2.decrypt(ENCRYPTED))
    print(result)

if __name__ == "__main__":
    main()
```
