---
layout: post
title: \[번역] An In-Depth Technical Analysis of CurveBall
subtitle: CVE-2020-0601
tags: [번역]
comments: true
---

## 들어가기 전

이 글은 [An In-Depth Technical Analysis of CurveBall (CVE-2020-0601)](https://blog.trendmicro.com/trendlabs-security-intelligence/an-in-depth-technical-analysis-of-curveball-cve-2020-0601/)을 번역한 글입니다.

# An In-Depth Technical Analysis of CurveBall (CVE-2020-0601)
Microsoft의 2020년 화요일의 첫번째 [패치](https://blog.trendmicro.com/trendlabs-security-intelligence/january-patch-tuesday-update-list-includes-fixes-for-internet-explorer-remote-desktop-cryptographic-bugs/)는 [CVE-2020-0601](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2020-0601)에 대한 수정을 포함하고 있습니다. 이 취약점은 미국 NSA (National Security Agency)에 의해 밝혀졌는데, Windows 암호화 라이브러리 중 하나인 CryptoAPI의 시스템 중 암호화 인증서를 확인하는 방법에 존재합니다. Curveball 혹은 "Chain of Fool"이라고도 불리는 이 취약점을 사용한 공격자는 Windows에 의해 기본적으로 신뢰하는 인증서처럼 보이는 가짜 인증서를 만들 수 있습니다.

취약점 공개 후 며칠만에 PoC와 취약점과 관련된 ECC(Elliptic Curve Cryptography, 타원곡선 암호) 개념에 대한 몇가지 설명이 공개되었습니다. 그러나 이 포스트에서는 주로 코드 레벨에서 무엇이 문제였는지 분석하고자 합니다. 더 자세하게는 TLS를 사용하는 어플리케이션의 동작을 분석하면서 CryptoAPI에서 어떻게 인증서들을 다루는지 살펴봅니다.

코드의 바다로 잠수하기 전, 인증서와 타원곡선 암호에 대해 간단하게 알아봅시다.

  

## 인증서
[X.509](http://www.itu.int/rec/T-REC-X.509/en)는 ASN.1 형식을 사용하는 공개키 인증서에 대한 ITU(International Telecommunication Union) 표준입니다. 기본적으로, 인증서는 인증서, 전자서명 알고리즘, 인증서의 진위를 판별하기 위한 전자 서명, 이 세가지의 "첫번째 레이어"를 포함하고 있습니다. 이러한 구조는 다음과 같은 ASN.1 표현으로 나타낼 수 있습니다.  
![ASN.1 notation](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-code-1.png)  
인증서 그 자체는 다음과 같은 여러 항목들의 중첩입니다.  
![Certificate notation](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-code-2.png)  
이 중 특별히 중요한 것은 ``SubjectPublicKeyInfo``인데, 이 구조체는 다음과 같은 실제 공개키와 공개키의 알고리즘과 관련된 정보를 포함하고 있습니다.  
![SubjectPublicKeyInfo](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-code-3.png)  
``AlgorithmIdentifier`` 구조체는 공개키와 전자서명 알고리즘에 사용되는 파라미터들에 대한 정보를 담고 있습니다. 특히 OID(Object IDentifier)와 OID에 의해 정의되는 알고리즘에 기반한 옵셔널 파라미터들을 주목해야 합니다.  
![AlgorithmIdentifier](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-code-4.png)  
공개키의 컨텍스트에서, 알고리즘 필드는 무수히 많은 OID들 중에 하나입니다. 예를 들어, rsaEncryption, dsa, ecPublicKey 등이 될 수 있습니다. 만약 OID가 ecPublicKey라면, 공개키가 타원곡선 암호에 의해 생성되었다는것을 뜻합니다. 이 경우에, 파라미터 필드는 [RFC 3279](https://tools.ietf.org/html/rfc3279)에서 정의된 EcpkParameters가 되어야 합니다.  
![EcpkParameters](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-code-5.png)  
다른 말로 말하자면, 타원곡선의 파라미터는 OID에서 제공하는 알려진 “[named curves](https://docs.microsoft.com/en-us/windows/win32/seccng/cng-named-elliptic-curves)”를 사용하여 묵시적으로 정의할 수도 있고, 혹은 ecParameters를 사용하여 명시적으로 정의할 수 있습니다. 취약점은 공격자가 named curve 대신 ecParameters를 사용하여 제작한 인증서를 사용할 때 존재합니다. 취약점에 대해 상세히 설명하기 전에, 빠르게 타원곡선에 대해 설명하겠습니다.
## 타원 곡선
타원 곡선은 다음과 같은 형태의 수식을 말합니다.  
  
<img src="https://latex.codecogs.com/svg.latex?\Large&space;y^2=x^3+ax+b" title="Elliptic Curve" />  
  
타원 곡선 암호에서,