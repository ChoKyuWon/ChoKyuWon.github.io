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
다른 말로 말하자면, 타원곡선의 파라미터는 OID에서 제공하는 알려진 “[named curves](https://docs.microsoft.com/en-us/windows/win32/seccng/cng-named-elliptic-curves)”를 사용하여 묵시적으로 정의할 수도 있고, 혹은 *ecParameters*를 사용하여 명시적으로 정의할 수 있습니다. 취약점은 공격자가 *named curve* 대신 *ecParameters*를 사용하여 제작한 인증서를 사용할 때 존재합니다. 취약점에 대해 상세히 설명하기 전에, 빠르게 타원곡선에 대해 설명하겠습니다.
## 타원 곡선
타원 곡선은 다음과 같은 형태의 수식을 말합니다.  
  
<img src="https://latex.codecogs.com/svg.latex?\Large&space;y^2=x^3+ax+b" title="Elliptic Curve" />  
  
타원 곡선 암호에서, 이 방정식의 해는 유한 체 위에서 계산됩니다. 유한 체는 [갈루아 체](https://web.stanford.edu/class/ee392d/Chap7.pdf)라고도 하는데, 유한 체는 유한한 수로 구성된 집합으로 소수 p 또는 p의 거듭 제곱을 포함하며 <img src="https://latex.codecogs.com/svg.latex?\Large&space;GF(p^n)" title="Galois field" />으로 나타냅니다. 주어진 타원 곡선의 *점*은 소수 체에 대한 {0,1,2,…, p-1} 범위의 x 및 y 좌표로 구성됩니다 (i.e n이 1 인 경우). 집합의 원소 수는 체의 순서로 알려져 있음으로 타원 곡선의 순서는 곡선의 모든 점으로 구성됩니다.  
ECC에서 사용되는 타원 곡선은 기준점 혹은 생성점으로 부르는 점을 정의합니다. 이 점은 곡선 위의 다른 점을 *생성*하는데 사용 할 수 있는 곡선 위의 특별한 점입니다. 이것은 기준점과 유한 체 위의 정수 N을 곱함으로써 얻을 수 있습니다. *named curve*의 경우 a, b, 체 식별자 (일반적으로 소수 p) 및 기준점이 모두 사전에 결정되고 각 곡선의 공식 표준에 문서화되어 있습니다. 반대로, 인증서가 *ecParameters*를 정의했을 경우 다음과 같은 구조체를 통해 곡선의 모든 매개변수를 정의할 수 있습니다.  
![ecParameters](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-code-6.png)  

취약점의 맥락에서, 공격자는 이 파라미터들을 조작하여 임의의 공개키를 사용하는 인증서를 제작할 수 있습니다. 심지어 이미 알려진 인증서의 공개키를 가진 인증서를 제작할 수도 있습니다. 이는 *named curve*의 모든 다른 파라미터들은 유지하되, 기준점만을 변경함으로 수행할 수 있습니다.  
공격자는 이제 새롭게 제작한 *신뢰받는* 인증서를 사용할 수 있고 비밀키로 새로운 인증서에 서명할 수 있습니다. 이 인증서 체인을 피해자에게 제공하면 피해자는 인증서 체인을 Windows 인증서 저장소에 포함된 신뢰하는 인증서를 사용하여 검증하려 시도합니다. 이 검증 프로세스는 취약점이 존재하는 곳입니다. 패치에 적용된 변경사항을 확인하여 CryptoAPI의 프로세스를 자세히 살펴보겠습니다.

## 패치 변경점 조사
Windows CryptoAPI는 여러 라이브러리들을 사용하는데, 취약점은 ``crypt32.dll``에 존재합니다. Bindiff를 사용하여 취약점 패치 이전 가장 최신 버전 (10.0.18362.476)과 패치 적용 버전 (10.0.18362.592)을 살펴 보면 다음과 같습니다.  
![Bindiff](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-analysis-1.png)  
DLL에서 어느 부분이 변경되었을까요?  
높은 수준에서, 다섯가지의 가능성 있는 흥미로워보이는 새로운 함수가 새 버전에 추가되었고 다섯가지 함수가 변경되었습니다. 몇가지 새로운 함수가 추가된 경우에, 기존의 함수들이 새로운 함수를 사용하게 바뀌었다고 볼 수 있습니다. 다행히도, Microsoft가 디버깅 심볼을 제공해 주기 때문에, 우리는 함수 이름을 보는 것 만으로 많은 정보를 알아낼 수 있습니다.  
  
첫째로, 변경된 함수들의 이름을 확인해 봅시다.  
![changed function's name](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-analysis-2.png)  
``ChainGetSubjectStatus()``와 ``CCertObjectCache::FindKnownStoreFlags()``가 가장 크게 바뀌었고, **CCertObject**의 생성자와 소멸자 또한 바뀐 것을 확인할 수 있습니다.  
이제 새로 추가된 함수를 확인해 봅시다.  
![added functions](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-analysis-3.png)  
몇가지 새로운 함수가 눈에 띕니다. 그 중 조사를 시작하기에 가장 좋아 보이는 함수는 ``ChainLogMSRC54294Error()``이군요. 이 함수는 새로운 로깅 함수인데, exploit 가능성이 높은 시도를 로깅하기 위한 함수입니다. 이 함수의 용도는 다음 블록을 통해 식별할 수 있습니다.  
![following block](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-analysis-4.png)  
이 블록은 CVE 정보를 포함하는 문자열을 라이브러리 외부의 ``CveEventWrite()`` 함수에 전달합니다. 이는 Windows 이벤트 로그에 CVE 기반의 이벤트로 기록되게 됩니다.  
이 정보를 사용해서, 우리는 이 함수의 역참조를 조사하여 어느 상황에 이벤트가 기록되는지 확인할 수 있습니다. 이 경우에, ``ChainLogMSRC54294Error()``을 호출하는 함수는 ``ChainGetSubjectStatus()``가 유일합니다. 이 함수는 이번 패치에서 가장 큰 변화가 있었던 함수입니다.  
![ChainGetSubjectStatus](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-analysis-5.png)  
새로운 로깅 함수를 호출하는 주변 맥락을 보았을 때, ``CryptVerifyCertificateSignatureEx()``와 ``ChainComparePublicKeyParametersAndBytes()``의 결과에 의해 로깅 함수가 호출되는 것을 알 수 있습니다. 두 함수중 후자는 패치를 통해 추가된 함수입니다. 따라서 ``ChainGetSubjectStatus()``는 패치에 의한 변경점을 조사하기에도, 어느 때에 호출되는지 조사하기에도 적합한 대상으로 볼 수 있습니다.

## CryptoAPI의 인증서 검증 내부 동작
``ChainGetSubjectStatus()``의 동작을 이해하기 위해, 인증서를 다루기 위해 CryptoAPI를 사용하는 특정한 프로그램을 먼저 확인하겠습니다.  
우리의 경우, 파워쉘의 Invoke-Webrequest cmdlet에서 분석을 진행하였지만, 다른 TLS 클라이언트 또한 비슷한 방식으로 동작합니다. 파워쉘이 처음으로 로드되면, 명시적으로 신뢰하는 인증서들을 포함한 시스템 인증서 저장소의 핸들을 ``CertOpenStore()``를 호출하여 획득합니다. 따라서 파워쉘은 필요할 때 시스템 인증서 저장소를 사용할 수 있습니다. 그 뒤에 이 인증서 저장소들은 *collection*에 추가되어 하나의 통합된 인증서 저장소인것처럼 효과적으로 동작합니다.  
Invoke-Webrequest같은 커맨드를 통해 HTTP over TLS 요청을 서버에게 보내고 나면, 서버는 종딘 인증서와 그 인증서를 검증하는 데 사용되는 인증서 체인이 포함된 TLS 인증 핸드쉐이크 메세지를 전달합니다. 이 인증서들을 받고 나면, 추가적인 *in-memory* 저장소가 ``CertOpenStore()``를 추가로 호출하여 생성됩니다. 전달받은 인증서들은 새로운 인증서 저장소에 ``CertAddEncodedCertificateToStore()`` 함수를 통해 추가됩니다. 이 함수는 인증서 저장소의 핸들과 원본 인증서의 포인터, 그리고 ASN.1 구조에 해당하는 CERT_INFO 구조체의 포인터를 포함한 **CERT_CONTEXT** 구조체를 생성합니다.  
예를 들어, 이 구조체들은 종단 인증서에 ``CertAddEncodedCertificateToStore()``를 호출한 결과로 생성되었습니다.  
![CertAddEncodedCertificateToStore](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-analysis-6.png)  

이러한 항목 중 특히 일부가 중요합니다. *Issuer*는 이 인증서의 *Signer*에 속하는 인증서의 *Subject*와 정확히 일치해야하며, ``SubjectPublicKeyInfo``는 ASN.1 구조와 정확히 일치합니다. 예를 들어, 아래의 종단 인증서 공개키는 1.2.840.10045.2.1의 알고리즘 식별자 OID로 인해 타원 곡선을 사용한다는 것을 알 수 있습니다.  
![exampleCert](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-analysis-7.png)  
또한 파라미터의 첫번째 바이트를 조사하여 *named curve*를 사용하는지 그렇지 않은지 빠르게 식별할 수 있습니다.  
![inspectFirstbyte](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-analysis-8.png)  
이 경우, ``0x6``이 오브젝트 식별자의 DER 인코딩 태그로, *named curve*가 사용되었음을 의미합니다. 만일 명시적으로 *ecParameters*를 사용하였을 경우에는 ``0x6`` 대신 ``0x30``이 들어갑니다.  

받은 모든 인증서들을 *in-memory* 저장소에 추가하고 나면 파워쉘은 ``CertGetCertificateChain()``를  종단 인증서와 중간 인증서에 대해 **CERT_CONTEXT** 구조체와 함께 호출하여 인증서 체인을 구축하여 신뢰하는 루트 인증서로 돌아갑니다.  
정확하게는, ``CertGetCertificateChain()``는 인증서 체인과 체인의 유효성에 관한 데이터를 포함하는 신뢰 상태 구조체의 배열인 **CERT_CHAIN_CONTEXT** 구조체를 반환합니다. **CERT_CHAIN_CONTEXT** 는 가장 먼저 ``CCertChainEngine::GetChainContext()``에 의해 처리되어 최종적으로 인증서 체인에 대한 유효성 검사 결과를 포함하게 됩니다.  
``CCertChainEngine::GetChainContext()``는 ``CCertChainEngine::CreateChainContextFromPathGraph()``를 호출합니다. ``CCertChainEngine::CreateChainContextFromPathGraph()``는 시스템 인증서 저장소들로부터 생성된 *collection*을 포함하는 *collection*를 생성합니다. 즉, 모든 저장소가 *collection*에 속하게 됩니다. 그 후 종단 인증서를 *collection*에 추가한 뒤 ``ChainCreateCertObject()``를 종단 인증서의 **CERT_INFO**와 함께 호출합니다. ``ChainCreateCertObject()``는 캐시에서 기존의 **CCertObject**가 존재하는지 검사하고 만일 존재하지 않는 경우 새로운 **CCertObject**를 인스턴스화합니다.  
**CCertObject**의 생성자는 자신의 필드를 초기화하고, 서명의 해시값, 키 식별자등을 포함하는 **CERT_INFO** 구조체를 자신의 속성에 복사한 뒤 인증서 확장에 속하는 정책이 있는지 찾고, 중요하다고 표시된 인증서 확장이 CryptoAPI에 의해 지원되는지 확인합니다. 그 후 생성자는 ``ChainGetIssuerMatchInfo()``를 인증서에 서명한 키 식별자인 ``CERT_AUTHORITY_KEY_ID_INFO``구조체를 검색하기 위해 호출합니다. 이후 인증서가 *self-signed*인지, 혹은 공개키가 안전하지 않은 길이의 RSA 알고리즘을 사용하는지를 식별합니다.  
종단 인증서의 **CCertObject**가 생성된 직후 **CChainPathObject**가 생성됩니다. **CChainPathObject**의 초기화가 수행된 후 생성자는 ``CChainPathObject::FindAndAddIssuers()``를 호출합니다. 이 함수는 결과적으로 ``CChainPathObject::FindAndAddIssuersFromStoreByMatchType()``를 호출하고, 종단 인증서의 *Issuer*를 찾습니다. — 일반적으로 종단 인증서의 *Issuer*의 해시값과 일치하는 *Subject*의 해시를 기반으로 탐색합니다. 추가적인 인증서가 *in-memory* 저장소에 있는 경우(즉, 인증서가 종단 인증서와 함께 전송 된 경우), 이번에는 종단 인증서의 *Issuer*의 인증서(즉, *intermediate* 인증서)의 **CERT_INFO** 구조체를 매개변수로 하여 ``ChainCreateCertObject()``를 다시 한 번 호출합니다.  
이 과정은 재귀적으로 *self-signed*된 인증서(대부분의 경우 *root* 인증서)를 만날때까지 반복됩니다. *Subject*가 *Issuer*와 일치하는지 확인하고, ``CryptVerifyCertificateSignatureEx()``를 호출합니다. 이 함수는 **CERT_INFO** 구조체 내에 있는 **CERT_PUBLIC_KEY_INFO** 구조체를 참조하여 공개키와 키 알고리즘 정보를 획득하여 서명을 검즘합니다. 이후 ``ChainGetSelfSignedStatus()``를 호출합니다.
대부분의 유효성 검사는 ``I_CryptCNGVerifyEncodedSignature()``에 의해 수행됩니다. 만일 인증서가 명시적인 타원곡선 파라미터를 제공했다면, 이 함수는 타원곡선 파라미터를 포함하는 **BCRYPT_ECCFULLKEY_BLOB** 구조체를 채웁니다. **BCRYPT_ECCFULLKEY_BLOB** 구조체는 문서화되지는 않았지만 ``bcrypt.h``에 정의되어 있습니다. 이 파라미터들은 ``CNGECCVerifyEncodedSignature()``를 호출되는데 사용됩니다. 이 함수는 bcrypt 라이브러리 함수인 ``BCryptVerifySignature()``를 호출하고, 파라미터들과 서명에 대한 최종적인 검증이 수행됩니다.  
만일 서명이 성공적으로 검증되었다면, **CChainPathObject**를 생성하기 위해 ``CCertIssuerList::AddIssuer()`` 함수기 호출됩니다. 종단 인증서와 *self-signed* 인증서의 **CChainPathObject**는 ``CCertIssuerList::CreateElement()``를 호출하는데 사용되고, 이 함수는 초기화 후 ``ChainGetSubjectStatus()``를 두 **CChainPathObject**를 사용하여 호출합니다.

``ChainGetSubjectStatus()``는 먼저 **CChainPathObjects**와 연관된 각 **CCertObjects** 를 파라미터로 ``ChainGetMatchInfoStatus()``를 호출합니다. 이 함수는 두 인증서의 *subjects*가 같은지 확인합니다. 이후 ``ChainGetSubjectStatus()``는 종단 인증서의 **CCertObject**의 플래그를 확인합니다.  
![test](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-analysis-9.png)  
이 플래그는 **CCertObject** 가 생성될 때 0으로 초기화됩니다. 이것은 *self-signed* 인증서가 종단 인증서의 적합한 *issuer*인지 확인하기 위해 ``CryptVerifyCertificateSignatureEx()``가 호출되는 것을 야기합니다.  
![Figure10](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-analysis-10.png)  
만약 서명이 적합하다고 간주되면 **CERT_ISSUER_PUBLIC_KEY_MD5_HASH** 속성이 종단 인증서에 추가되고 위에서 언급한 플래그는 ``3``으로 설정됩니다.  
![test1](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-analysis-11.png)  
``CCertIssuerList::AddIssuer()``가 리턴되고 모든 함수가 원래의 ``CChainPathObject::FindAndAddIssuers()``로 리턴되면 종단 인증서의 위에서 언급한 플래그가 체크되고 만약 설정되어 있다면 ``CChainPathObject::FindAndAddIssuersFromStoreByMatchType()``과 ``CChainPathObject::FindAndAddIssuersFromStoreByMatchType()``를 다시 호출합니다.  
이번에는 신뢰할 수 있는 시스템 인증서 리스트를 포함한 *collection*이 탐색되고, ``FindElementInCollectionStore()``의 파라미터 정보를 담고있는 **CERT_STORE_PROV_FIND_INFO** 구조체를 제공합니다. ``FindElementInCollectionStore()`` 함수는 *collection*의 저장소마다 *self-signed* 인증서의 공개키의 MD5 해시값과 일치하는 해시값을 가진 인증서를 탐색합니다.  
  
만일 공개키 해시가 일치하는 인증서를 시스템 저장소에서 찾는다면, ``ChainCreateCertObject()``가 다시 호출되고, 이번에는 파라미터로 시스템 저장소에서 검색된 인증서의 **CERT_CONTEXT**를 사용합니다. 이 함수는 새로운 **CCertObject**를 생성하고 플래그를 설정하는데 이는 이 인증서가 *알려진 저장소*에서 비롯되었다는 사실에 기반합니다. 이 오브젝트는 **CCertObjectCache**에 *issuer*로 추가되고 *issuer* 리스트에 등록됩니다. 따라서 다시 새로운 **CChainPathObject**를 생성하게 되고 *self-signed* 인증서와 저장소에서 찾은 인증서의 **CChainPathObjects**를 인자로 ``CCertIssuerList::CreateElement()``를 호출합니다.  
``ChainGetSubjectStatus()``이 호출되면, 계속 언급되는 플래그가 이미 설정되어 있어서 *self-signed* 인증서의 **CERT_ISSUER_PUBLIC_KEY_MD5_HASH**를 신뢰할 수 있는 저장소의 인증서에 있는 공개키의 MD5 해시와 비교하여 검사합니다.  
![Figure12](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-analysis-12.png)  
만약 일치하면, 제공된 *self-signed* 인증서에 대한 추가적인 검증을 진행하지 않습니다. 이것은 제공된 인증서가 저장소에 있는 신뢰하는 인증서와 공개키의 해시값이 같기 때문에 신뢰할 수 있는 *self-signed*인증서를 신뢰할 수 있다는 것을 의미합니다. 추가적으로, 제공된 *self-signed* 인증서를 통해 종단 인증서 또한 성공적으로 검증할 수 있습니다. 공격자는 타원곡선 파라미터를 명시적으로 정의하여 신뢰하는 루트 인증서와 동일한 공개키를 가진 인증서를 제작하고 종단 인증서에 서명할 수 있습니다. 이 경우 종단 인증서의 서명은 마치 적합한 루트 인증서에 의해 서명된것과 같이 효과적으로 검증됩니다.  
이 신뢰는 ``CCertChainEngine::CreateChainContextFromPathGraph()``로 리턴되었을때 나타납니다. 인증서 경로에 있는 각 오브젝트(종단 인증서와 임의로 제작된 루트 인증서)는 만료 시각이나 *revocation* 상태 등에 대해 추가적인 검사를 시행합니다. **CERT_CHAIN_CONTEXT** 구조체는 이후 ``CChainPathObject::CreateChainContextFromPath()``의 호출로 생성되는데 인증서 체인의 유효성을 나타내는 **CERT_TRUST_STATUS** 를 포함하고 있습니다.  
``CertGetCertificateChain()`` 함수가 최종적으로 종료되면, 본 어플리케이션은 **CERT_CHAIN_CONTET**를 체크라여 인증서 체인이 유효한지 검사할 수 있습니다. **CERT_CHAIN_CONTET**는 공격 시나리오에 의해 유효하다고 나타내졌기 때문에 본 어플리케이션은 인증서 체인이 유효하다고 판단하게 됩니다.  
![Figure13](https://blog.trendmicro.com/trendlabs-security-intelligence/files/2020/02/curveball-analysis-13.png)
## 결론
요약하자면, CVE-2020-0601에 대한 분석 결과는 다음과 같습니다.
* 종단 인증서에 대한 서명은 임의의 타원곡선 파라미터를 갖도록 조작된 루트 인증서에 의해 검증될 수 있습니다.
* 조작된 루트 인증서의 서명은 역시 임의의 타원곡선 파라미터를 갖는 *self-signed* 인증서 검증 절차를 따릅니다.
* 조작된 루트 인증서와 동일한 공개키 해시값을 갖는 인증서는 시스템 인증서 저장소에 위치하고 있습니다.
* 적합한 인증서와 공개키 해시 비교를 통과하면 더이상 조작된 인증서에 대한 추가 검증이 없습니다. 이로 인해 조작된 종단 인증서가 검증을 통과할 수 있습니다.
Microsoft는 Figure 5에서 볼 수 있는 새로운 함수인 ``ChainComparePublicKeyParametersAndBytes()``를 추가해서 딘순히 *issuer*와 공개키 해시를 비교하는 대신 신뢰하는 루트 인증서와 실제로 종단 인증서에 서명하는데 사용된 인증서 사이에 공개 키 파라미터들과 바이트를 비교함으로써 이 문제를 해결하였습니다.
만약 둘 사이에 차이가 있을 경우, ``CryptVerifySignatuerEx()``가 종단 인증서의 서명을 다시 검증하기 위해 실제 신뢰하는 루트 인증서와 파라미터를 가지고 호출됩니다.